"""Bounded, single-use password recovery; only digests are persisted."""
import asyncio
import hashlib
import logging
import secrets
import smtplib
import ssl
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage

from fastapi import HTTPException
from pydantic import EmailStr, TypeAdapter, ValidationError
from redis.asyncio import Redis
from sqlalchemy import update
from starlette.concurrency import run_in_threadpool

from app.core.config import settings
from app.core.security import hash_password
from app.models.user import User

logger = logging.getLogger(__name__)
RESET_TTL_MINUTES = 20
GENERIC_MESSAGE = "If an account uses this email, a recovery code will arrive shortly."


def recovery_available() -> bool:
    if not settings.recovery_smtp_host or not settings.recovery_email_sender:
        return False
    try:
        TypeAdapter(EmailStr).validate_python(settings.recovery_email_sender)
    except ValidationError:
        return False
    return settings.recovery_smtp_tls in {"starttls", "ssl"} or (
        settings.recovery_smtp_tls == "local"
        and settings.recovery_smtp_host in {"127.0.0.1", "localhost", "::1"}
    )


def token_digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


async def enforce_recovery_limit(client_ip: str, *, email: str | None = None) -> None:
    """Atomic shared limits; never trust a raw forwarded header here."""
    buckets = [("ip:" + client_ip, 20 if email is not None else 10)]
    if email is not None:
        buckets.append(("email:" + email.strip().casefold(), 3))
    redis = Redis.from_url(settings.redis_url, socket_connect_timeout=2, socket_timeout=2)
    script = """
    local n = redis.call('INCR', KEYS[1])
    if n == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
    return n
    """
    try:
        async with asyncio.timeout(3):
            for identity, limit in buckets:
                key = "password-recovery:" + token_digest(identity)
                count = await redis.eval(script, 1, key, 900)
                if count > limit:
                    raise HTTPException(429, "Too many recovery attempts. Try again later.",
                                        headers={"Retry-After": "900"})
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "Account recovery is temporarily unavailable.") from None
    finally:
        await redis.aclose()


async def issue_reset(db, email: str) -> tuple[str | None, str]:
    # Generate the same random token and execute the same update for any address.
    # No raw token is saved, returned by HTTP, or written to logs.
    token = secrets.token_urlsafe(32)
    result = await db.execute(
        update(User).where(User.email == email).values(
            reset_token_hash=token_digest(token),
            reset_expires_at=datetime.now(timezone.utc) + timedelta(minutes=RESET_TTL_MINUTES),
        ).returning(User.email)
    )
    recipient = result.scalar_one_or_none()
    await db.commit()  # Publish the digest before the background email can arrive.
    return recipient, token


async def confirm_reset(db, token: str, password: str) -> bool:
    password_hash = await run_in_threadpool(hash_password, password)
    result = await db.execute(
        update(User).where(
            User.reset_token_hash == token_digest(token),
            User.reset_expires_at > datetime.now(timezone.utc),
        ).values(
            password_hash=password_hash,
            reset_token_hash=None,
            reset_expires_at=None,
            auth_version=User.auth_version + 1,
        ).returning(User.id)
    )
    changed = result.scalar_one_or_none() is not None
    await db.commit()
    return changed


def _send_code(recipient: str, token: str) -> None:
    if not recovery_available():
        raise RuntimeError("Recovery sender is not configured")
    message = EmailMessage()
    message["Subject"] = "Reset your CMPYS password"
    message["From"] = settings.recovery_email_sender
    message["To"] = recipient
    message.set_content(
        "Someone requested a password reset for your CMPYS account.\n\n"
        "Open Account access in CMPYS, choose Enter recovery code, and paste:\n\n"
        + token + "\n\nThis code can be used once and expires in 20 minutes. "
        "If you did not request this, ignore this email. Your password has not changed.\n"
    )
    context = ssl.create_default_context()
    client_type = smtplib.SMTP_SSL if settings.recovery_smtp_tls == "ssl" else smtplib.SMTP
    options = {"timeout": 10}
    if client_type is smtplib.SMTP_SSL:
        options["context"] = context
    with client_type(settings.recovery_smtp_host, settings.recovery_smtp_port, **options) as smtp:
        if settings.recovery_smtp_tls == "starttls":
            smtp.starttls(context=context)
        if settings.recovery_smtp_username:
            smtp.login(settings.recovery_smtp_username, settings.recovery_smtp_password or "")
        smtp.send_message(message)


async def deliver_reset(recipient: str | None, token: str) -> None:
    if recipient is None:
        return
    try:
        await asyncio.to_thread(_send_code, recipient, token)
    except Exception as exc:
        # Do not expose existence, SMTP addresses, credentials, or reset codes.
        logger.error("Password recovery delivery failed (%s)", type(exc).__name__)
