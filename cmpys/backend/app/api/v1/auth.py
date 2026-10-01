from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from starlette.concurrency import run_in_threadpool

from app.core.db import get_db
from app.core.security import create_access_token, create_refresh_token, hash_password, verify_password
from app.models.user import User
from app.schemas.auth import LoginRequest, RegisterRequest, RefreshTokenRequest, TokenResponse

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
    access_token = create_access_token(subject=user.id)
    refresh_token = create_refresh_token(subject=user.id)

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

    access_token = create_access_token(subject=user.id)
    refresh_token = create_refresh_token(subject=user.id)

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
    
    result = await db.execute(select(User.id).where(User.id == user_id))
    if result.scalar_one_or_none() is None:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    new_access_token = create_access_token(subject=user_id)
    # Ideally rotate refresh token too to prevent reuse attacks
    new_refresh_token = create_refresh_token(subject=user_id)

    return TokenResponse(accessToken=new_access_token, refreshToken=new_refresh_token)
