from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from starlette.concurrency import run_in_threadpool

from app.core.db import get_db
from app.core.security import create_access_token, create_refresh_token, hash_password, verify_password
from app.models.user import User
from app.schemas.auth import (
    LoginRequest, PasswordResetConfirm, PasswordResetRequest,
    RegisterRequest, RefreshTokenRequest, TokenResponse,
)
from app.services import password_recovery

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(
    data: RegisterRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TokenResponse:
    """Register a new user."""
    # Check if user already exists
    stmt = select(User).where(User.email == data.email)
    result = await db.execute(stmt)
    existing_user = result.scalar_one_or_none()

    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    # Create new user
    user = User(
        email=data.email,
        password_hash=await run_in_threadpool(hash_password, data.password),
    )
    db.add(user)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        ) from None

    if data.full_name and data.full_name.strip():
        from app.models.user_profile import UserProfile
        db.add(UserProfile(user_id=user.id, full_name=data.full_name.strip()))
        await db.flush()

    # Generate tokens
    access_token = create_access_token(subject=user.id, auth_version=getattr(user, "auth_version", 0) or 0)
    refresh_token = create_refresh_token(subject=user.id, auth_version=getattr(user, "auth_version", 0) or 0)

    return TokenResponse(accessToken=access_token, refreshToken=refresh_token)


@router.post("/login", response_model=TokenResponse)
async def login(
    data: LoginRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TokenResponse:
    """Login with email and password."""
    stmt = select(User).where(User.email == data.email)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user or not await run_in_threadpool(
        verify_password, data.password, user.password_hash
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    access_token = create_access_token(subject=user.id, auth_version=getattr(user, "auth_version", 0) or 0)
    refresh_token = create_refresh_token(subject=user.id, auth_version=getattr(user, "auth_version", 0) or 0)

    return TokenResponse(accessToken=access_token, refreshToken=refresh_token)


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(
    data: RefreshTokenRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TokenResponse:
    """Refresh access token."""
    from app.core.security import decode_token

    payload = decode_token(data.refreshToken)
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, 
            detail="Invalid token subject"
        )
    
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None or payload.get("ver", 0) != (getattr(user, "auth_version", 0) or 0):
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    new_access_token = create_access_token(subject=user_id, auth_version=user.auth_version)
    new_refresh_token = create_refresh_token(subject=user_id, auth_version=user.auth_version)

    return TokenResponse(accessToken=new_access_token, refreshToken=new_refresh_token)


# The code is copied from email into the app. No public reset-page domain or
# unverified custom URL scheme is required to deliver a secure recovery token.
@router.get("/password-reset/availability")
async def password_reset_availability() -> dict:
    return {"available": password_recovery.recovery_available()}


@router.post("/password-reset/request", status_code=202)
async def request_password_reset(
    data: PasswordResetRequest, request: Request, background: BackgroundTasks,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    if not password_recovery.recovery_available():
        raise HTTPException(503, "Account recovery is not connected yet.")
    await password_recovery.enforce_recovery_limit(
        request.client.host if request.client else "unknown", email=str(data.email),
    )
    recipient, token = await password_recovery.issue_reset(db, str(data.email))
    background.add_task(password_recovery.deliver_reset, recipient, token)
    return {"message": password_recovery.GENERIC_MESSAGE}


@router.post("/password-reset/confirm", status_code=204)
async def confirm_password_reset(
    data: PasswordResetConfirm, request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Response:
    await password_recovery.enforce_recovery_limit(
        request.client.host if request.client else "unknown",
    )
    if not await password_recovery.confirm_reset(db, data.token, data.password):
        raise HTTPException(400, "This recovery code is invalid or expired. Request a new code.")
    return Response(status_code=204)
