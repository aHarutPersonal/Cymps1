from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import CurrentUser
from app.core.db import get_db
from app.models.user_profile import UserProfile
from app.schemas.user import MeResponse, UpdateProfileRequest, UserProfileResponse

router = APIRouter(tags=["me"])


def _profile_to_response(profile: UserProfile | None) -> UserProfileResponse | None:
    """Convert UserProfile model to response schema."""
    if profile is None:
        return None
    return UserProfileResponse(
        id=profile.id,
        fullName=profile.full_name,
        birthDate=profile.birth_date,
        focusAreas=profile.focus_areas,
        timezone=profile.timezone,
    )


@router.get("/me", response_model=MeResponse)
async def get_me(current_user: CurrentUser) -> MeResponse:
    """Get current user information."""
    return MeResponse(
        id=current_user.id,
        email=current_user.email,
        profile=_profile_to_response(current_user.profile),
    )


@router.patch("/me", response_model=MeResponse)
async def update_me(
    data: UpdateProfileRequest,
    current_user: CurrentUser,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> MeResponse:
    """Update current user profile."""
    profile = current_user.profile

    # Create profile if it doesn't exist
    if profile is None:
        profile = UserProfile(user_id=current_user.id)
        db.add(profile)

    # Update only provided fields
    if data.fullName is not None:
        profile.full_name = data.fullName
    if data.birthDate is not None:
        profile.birth_date = data.birthDate
    if data.focusAreas is not None:
        profile.focus_areas = data.focusAreas
    if data.timezone is not None:
        profile.timezone = data.timezone

    await db.flush()
    await db.refresh(profile)

    return MeResponse(
        id=current_user.id,
        email=current_user.email,
        profile=_profile_to_response(profile),
    )
