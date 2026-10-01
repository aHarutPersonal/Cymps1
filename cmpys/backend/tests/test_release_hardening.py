"""Behavior checks for authentication and public resource boundaries."""
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import ValidationError

from app.api.dependencies import get_current_user
from app.api.v1 import auth, media
from app.core.security import create_access_token, create_refresh_token, decode_token
from app.schemas.auth import LoginRequest, RegisterRequest, RefreshTokenRequest


@pytest.mark.parametrize('password', ['', 'short', 'a' * 73, 'é' * 37])
def test_registration_rejects_passwords_bcrypt_cannot_safely_accept(password):
    with pytest.raises(ValidationError):
        RegisterRequest(email='test@example.com', password=password)


def test_login_keeps_legacy_short_password_compatibility():
    assert LoginRequest(email='test@example.com', password='short').password == 'short'
    with pytest.raises(ValidationError):
        LoginRequest(email='test@example.com', password='é' * 37)


@pytest.mark.asyncio
async def test_refresh_token_cannot_authorize_api_requests():
    db = AsyncMock()
    credentials = HTTPAuthorizationCredentials(
        scheme='Bearer', credentials=create_refresh_token('test-user')
    )
    with pytest.raises(HTTPException) as error:
        await get_current_user(credentials, db)
    assert error.value.status_code == 401
    db.execute.assert_not_called()
    assert decode_token(create_access_token('test-user'))['type'] == 'access'


@pytest.mark.asyncio
async def test_deleted_account_cannot_refresh():
    db = AsyncMock()
    db.execute.return_value = Mock(scalar_one_or_none=Mock(return_value=None))
    with pytest.raises(HTTPException) as error:
        await auth.refresh_token(
            RefreshTokenRequest(refreshToken=create_refresh_token('test-user')), db
        )
    assert error.value.status_code == 401


@pytest.mark.asyncio
async def test_login_verifies_password_off_event_loop(monkeypatch):
    db = AsyncMock()
    db.execute.return_value = Mock(scalar_one_or_none=Mock(
        return_value=SimpleNamespace(id='test-user', password_hash='stored-hash')
    ))
    offload = AsyncMock(return_value=True)
    monkeypatch.setattr(auth, 'run_in_threadpool', offload)
    result = await auth.login(LoginRequest(email='test@example.com', password='legacy'), db)
    offload.assert_awaited_once_with(auth.verify_password, 'legacy', 'stored-hash')
    assert decode_token(result.accessToken)['type'] == 'access'


@pytest.mark.asyncio
async def test_public_media_is_serve_only_and_cannot_escape_directory(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    directory = tmp_path / 'media'
    directory.mkdir()
    (directory / 'portrait.jpg').write_bytes(b'photo')
    (tmp_path / 'private.txt').write_text('private')
    (directory / 'link.jpg').symlink_to(tmp_path / 'private.txt')
    assert (await media.get_media('portrait.jpg')).path.name == 'portrait.jpg'
    for filename in ('unknown_paid_generation.jpg', '../private.txt', 'link.jpg'):
        with pytest.raises(HTTPException) as error:
            await media.get_media(filename)
        assert error.value.status_code == 404


@pytest.mark.asyncio
async def test_wav_narration_delivery_supports_native_player_byte_ranges(tmp_path, monkeypatch):
    import io
    import wave

    import httpx
    from fastapi import FastAPI

    monkeypatch.chdir(tmp_path)
    directory = tmp_path / 'media'
    directory.mkdir()
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as recording:
        recording.setnchannels(1)
        recording.setsampwidth(2)
        recording.setframerate(24000)
        recording.writeframes(b'\x00\x00' * 24000)
    audio = buffer.getvalue()
    (directory / 'book_narration_test.wav').write_bytes(audio)
    application = FastAPI()
    application.include_router(media.router, prefix='/media')
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=application), base_url='http://test'
    ) as client:
        full = await client.get('/media/book_narration_test.wav')
        partial = await client.get(
            '/media/book_narration_test.wav', headers={'Range': 'bytes=1024-2047'}
        )
    assert full.status_code == 200
    assert full.headers['content-type'] in {'audio/wav', 'audio/x-wav', 'audio/vnd.wave'}
    assert full.content == audio
    assert partial.status_code == 206
    assert partial.headers['accept-ranges'] == 'bytes'
    assert partial.headers['content-range'] == f'bytes 1024-2047/{len(audio)}'
    assert partial.content == audio[1024:2048]


@pytest.mark.asyncio
@pytest.mark.parametrize('mode,expected', [('timeout', 504), ('oversized', 502), ('upstream', 502), ('ok', 200)])
async def test_news_handles_bounded_upstream_failures(monkeypatch, mode, expected):
    import httpx
    from app.api.v1 import tools

    class Response:
        async def __aenter__(self):
            if mode == 'timeout':
                raise httpx.ReadTimeout('private upstream detail')
            return self

        async def __aexit__(self, *args):
            pass

        def raise_for_status(self):
            if mode == 'upstream':
                request = httpx.Request('GET', 'https://news.google.com')
                raise httpx.HTTPStatusError('private upstream detail', request=request,
                    response=httpx.Response(503, request=request))

        async def aiter_bytes(self):
            if mode == 'oversized':
                yield b'x' * 1_000_001
            else:
                yield b'<rss><channel><item><title>News</title><link>https://example.com/news</link></item></channel></rss>'

    class Client:
        def __init__(self, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            pass

        def stream(self, method, url):
            return Response()

    monkeypatch.setattr(tools.httpx, 'AsyncClient', Client)
    if expected == 200:
        articles = await tools.get_news('science')
        assert articles[0].title == 'News'
        assert articles[0].link == 'https://example.com/news'
    else:
        with pytest.raises(HTTPException) as error:
            await tools.get_news('science')
        assert error.value.status_code == expected
        assert 'private' not in error.value.detail
