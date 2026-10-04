import os
import socketserver
import threading
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock
from uuid import uuid4

import httpx
import pytest
from fastapi import FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import ValidationError
from sqlalchemy import DateTime, Integer, String, select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.api.dependencies import get_current_user
from app.api.v1 import auth
from app.core.config import settings
from app.core.db import get_db
from app.core.security import create_access_token, create_refresh_token, hash_password, verify_password
from app.schemas.auth import PasswordResetConfirm, RefreshTokenRequest
from app.services import password_recovery as recovery


@pytest.mark.parametrize('password', ['short', 'é' * 37])
def test_reset_password_requires_valid_bcrypt_input(password):
    with pytest.raises(ValidationError):
        PasswordResetConfirm(token='a' * 43, password=password)


@pytest.mark.parametrize('token', ['', 'a' * 42, 'a' * 44, '!' * 43])
def test_reset_rejects_malformed_codes(token):
    with pytest.raises(ValidationError):
        PasswordResetConfirm(token=token, password='longpassword')


@pytest.mark.asyncio
async def test_reset_revokes_access_and_refresh_sessions():
    user = SimpleNamespace(id='test-user', auth_version=1)
    db = AsyncMock()
    db.execute.return_value = Mock(scalar_one_or_none=Mock(return_value=user))
    with pytest.raises(HTTPException) as exc:
        await get_current_user(HTTPAuthorizationCredentials(scheme='Bearer', credentials=create_access_token('test-user')), db)
    assert exc.value.status_code == 401
    with pytest.raises(HTTPException) as exc:
        await auth.refresh_token(RefreshTokenRequest(refreshToken=create_refresh_token('test-user')), db)
    assert exc.value.status_code == 401
    assert await get_current_user(HTTPAuthorizationCredentials(scheme='Bearer', credentials=create_access_token('test-user', auth_version=1)), db) is user
    assert (await auth.refresh_token(RefreshTokenRequest(refreshToken=create_refresh_token('test-user', auth_version=1)), db)).accessToken


@pytest.mark.asyncio
async def test_request_does_not_reveal_account_or_code(monkeypatch):
    app = FastAPI(); app.include_router(auth.router)
    async def database(): yield AsyncMock()
    app.dependency_overrides[get_db] = database
    monkeypatch.setattr(recovery, 'recovery_available', lambda: True)
    monkeypatch.setattr(recovery, 'enforce_recovery_limit', AsyncMock())
    delivery = AsyncMock(); monkeypatch.setattr(recovery, 'deliver_reset', delivery)
    monkeypatch.setattr(recovery, 'issue_reset', AsyncMock(side_effect=[('known@example.com', 'a'*43), (None, 'b'*43)]))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as c:
        known = await c.post('/auth/password-reset/request', json={'email':'known@example.com'})
        unknown = await c.post('/auth/password-reset/request', json={'email':'unknown@example.com'})
    assert known.status_code == unknown.status_code == 202
    assert known.json() == unknown.json() == {'message':recovery.GENERIC_MESSAGE}
    assert 'a'*43 not in known.text and delivery.await_count == 2


@pytest.mark.asyncio
async def test_disabled_recovery_is_explicit_for_every_address(monkeypatch):
    monkeypatch.setattr(recovery, 'recovery_available', lambda: False)
    app=FastAPI(); app.include_router(auth.router)
    async def database(): yield AsyncMock()
    app.dependency_overrides[get_db]=database
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as c:
        assert (await c.get('/auth/password-reset/availability')).json()=={'available':False}
        assert (await c.post('/auth/password-reset/request',json={'email':'any@example.com'})).status_code==503


@pytest.mark.asyncio
async def test_delivery_failure_does_not_log_address_or_token(monkeypatch, caplog):
    def fail(*args): raise RuntimeError('private@example.com '+ 'a'*43)
    monkeypatch.setattr(recovery,'_send_code',fail)
    await recovery.deliver_reset('private@example.com','a'*43)
    assert 'RuntimeError' in caplog.text
    assert 'private@example.com' not in caplog.text and 'a'*43 not in caplog.text


@pytest.mark.parametrize('host,tls,expected', [('smtp.example.com','local',False),('127.0.0.1','local',True),('smtp.example.com','starttls',True),('smtp.example.com','ssl',True),('smtp.example.com','bad',False)])
def test_plain_smtp_only_allowed_for_loopback_stand(monkeypatch,host,tls,expected):
    monkeypatch.setattr(settings,'recovery_smtp_host',host)
    monkeypatch.setattr(settings,'recovery_smtp_tls',tls)
    monkeypatch.setattr(settings,'recovery_email_sender','sender@example.com')
    assert recovery.recovery_available() is expected


def test_real_smtp_adapter_delivers_to_controlled_loopback_stand(monkeypatch):
    received=[]
    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            self.wfile.write(b'220 test SMTP\r\n')
            while line:=self.rfile.readline():
                verb=line.split(b' ',1)[0].strip().upper()
                if verb in {b'EHLO',b'HELO'}: self.wfile.write(b'250 localhost\r\n')
                elif verb==b'DATA':
                    self.wfile.write(b'354 send data\r\n'); body=[]
                    while (line:=self.rfile.readline()) not in {b'.\r\n',b''}: body.append(line)
                    received.append(b''.join(body)); self.wfile.write(b'250 accepted\r\n')
                elif verb==b'QUIT': self.wfile.write(b'221 bye\r\n'); return
                else: self.wfile.write(b'250 ok\r\n')
    with socketserver.TCPServer(('127.0.0.1',0),Handler) as server:
        thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        monkeypatch.setattr(settings,'recovery_smtp_host','127.0.0.1')
        monkeypatch.setattr(settings,'recovery_smtp_port',server.server_address[1])
        monkeypatch.setattr(settings,'recovery_smtp_tls','local')
        monkeypatch.setattr(settings,'recovery_email_sender','sender@example.com')
        monkeypatch.setattr(settings,'recovery_smtp_username',None)
        try: recovery._send_code('test@example.com','a'*43)
        finally: server.shutdown(); thread.join(timeout=2)
    assert len(received)==1
    assert b'To: test@example.com' in received[0] and b'a'*43 in received[0]
    assert b'20 minutes' in received[0]


@pytest.mark.asyncio
async def test_recovery_counter_is_shared_and_fails_closed(monkeypatch):
    redis=SimpleNamespace(eval=AsyncMock(return_value=4),aclose=AsyncMock())
    monkeypatch.setattr(recovery.Redis,'from_url',lambda *a,**k:redis)
    with pytest.raises(HTTPException) as exc: await recovery.enforce_recovery_limit('127.0.0.1',email='Private@example.com')
    assert exc.value.status_code==429
    assert all('Private' not in str(call) for call in redis.eval.call_args_list)
    redis.eval.side_effect=ConnectionError('secret')
    with pytest.raises(HTTPException) as exc: await recovery.enforce_recovery_limit('127.0.0.1')
    assert exc.value.status_code==503 and 'secret' not in exc.value.detail


@pytest.mark.asyncio
async def test_single_use_replacement_expiry_and_password_change_postgres(monkeypatch):
    if os.environ.get('RUN_POSTGRES_INTEGRATION')!='1': pytest.skip('PostgreSQL integration opt-in')
    class Base(DeclarativeBase): pass
    class ProbeUser(Base):
        __tablename__='recovery_probe_'+uuid4().hex
        id:Mapped[int]=mapped_column(Integer,primary_key=True)
        email:Mapped[str]=mapped_column(String,unique=True)
        password_hash:Mapped[str]=mapped_column(String)
        auth_version:Mapped[int]=mapped_column(Integer,default=0)
        reset_token_hash:Mapped[str|None]=mapped_column(String,unique=True)
        reset_expires_at:Mapped[datetime|None]=mapped_column(DateTime(timezone=True))
    monkeypatch.setattr(recovery,'User',ProbeUser)
    engine=create_async_engine(settings.database_url)
    try:
        async with engine.connect() as connection:
            transaction=await connection.begin()
            try:
                await connection.run_sync(Base.metadata.create_all)
                async with AsyncSession(connection,expire_on_commit=False,join_transaction_mode='create_savepoint') as db:
                    db.add(ProbeUser(id=1,email='known@example.com',password_hash=hash_password('old-password')))
                    await db.commit()
                    address,first=await recovery.issue_reset(db,'known@example.com')
                    assert address=='known@example.com'
                    row=(await db.execute(select(ProbeUser))).scalar_one()
                    assert row.reset_token_hash==recovery.token_digest(first) and row.reset_token_hash!=first
                    _,second=await recovery.issue_reset(db,'known@example.com')
                    assert not await recovery.confirm_reset(db,first,'new-password')
                    assert await recovery.confirm_reset(db,second,'new-password')
                    assert not await recovery.confirm_reset(db,second,'other-password')
                    await db.refresh(row)
                    assert row.auth_version==1 and row.reset_token_hash is None
                    assert verify_password('new-password',row.password_hash)
                    assert not verify_password('old-password',row.password_hash)
                    _,expired=await recovery.issue_reset(db,'known@example.com')
                    row.reset_expires_at=datetime.now(timezone.utc)-timedelta(seconds=1)
                    await db.commit()
                    assert not await recovery.confirm_reset(db,expired,'other-password')
                    assert (await recovery.issue_reset(db,'missing@example.com'))[0] is None
            finally: await transaction.rollback()
    finally: await engine.dispose()
