"""User achievements CRUD endpoints."""
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.user import User
from app.models.user_achievement import UserAchievement, AchievementCategory
from app.schemas.achievement import (
    AchievementCreate,
    AchievementListResponse,
    AchievementResponse,
    AchievementUpdate,
)

router = APIRouter(prefix="/achievements", tags=["achievements"])


def _to_response(achievement: UserAchievement) -> AchievementResponse:
    """Convert model to response schema."""
    return AchievementResponse(
        id=achievement.id,
        userId=achievement.user_id,
        title=achievement.title,
        category=achievement.category,
        achievementDate=achievement.achievement_date,
        notes=achievement.notes,
        evidenceLink=achievement.evidence_link,
        createdAt=achievement.created_at,
        updatedAt=getattr(achievement, "updated_at", None) or achievement.created_at,
    )


@router.post("", response_model=AchievementResponse, status_code=status.HTTP_201_CREATED)
async def create_achievement(
    data: AchievementCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> AchievementResponse:
    """Create a new user achievement."""
    achievement = UserAchievement(
        user_id=current_user.id,
        title=data.title,
        category=AchievementCategory(data.category.value),
        achievement_date=data.achievementDate,
        notes=data.notes,
        evidence_link=data.evidenceLink,
    )
    db.add(achievement)
    await db.commit()
    await db.refresh(achievement)
    
    return _to_response(achievement)


@router.get("", response_model=AchievementListResponse)
async def list_achievements(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    category: str | None = Query(None, description="Filter by category"),
    q: str | None = Query(None, description="Search in title and notes"),
    from_date: date | None = Query(None, alias="fromDate", description="From date"),
    to_date: date | None = Query(None, alias="toDate", description="To date"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> AchievementListResponse:
    """List user achievements with optional filters."""
    stmt = select(UserAchievement).where(UserAchievement.user_id == current_user.id)
    
    if category:
        try:
            cat_enum = AchievementCategory(category)
            stmt = stmt.where(UserAchievement.category == cat_enum)
        except ValueError:
            pass  # Invalid category, ignore filter
    
    if q:
        search_filter = or_(
            UserAchievement.title.ilike(f"%{q}%"),
            UserAchievement.notes.ilike(f"%{q}%"),
        )
        stmt = stmt.where(search_filter)
    
    if from_date:
        stmt = stmt.where(UserAchievement.achievement_date >= from_date)
    
    if to_date:
        stmt = stmt.where(UserAchievement.achievement_date <= to_date)
    
    # Get total count
    # Bolt: optimized count query to avoid slow subquery processing
    count_stmt = stmt.with_only_columns(func.count(UserAchievement.id)).order_by(None)
    total_result = await db.execute(count_stmt)
    total = total_result.scalar() or 0
    
    # Get paginated results
    stmt = stmt.order_by(UserAchievement.achievement_date.desc().nulls_last())
    stmt = stmt.offset(offset).limit(limit)
    
    result = await db.execute(stmt)
    achievements = result.scalars().all()
    
    return AchievementListResponse(
        achievements=[_to_response(a) for a in achievements],
        total=total,
    )


@router.get("/{achievement_id}", response_model=AchievementResponse)
async def get_achievement(
    achievement_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> AchievementResponse:
    """Get a specific achievement."""
    stmt = select(UserAchievement).where(
        and_(
            UserAchievement.id == achievement_id,
            UserAchievement.user_id == current_user.id,
        )
    )
    result = await db.execute(stmt)
    achievement = result.scalar_one_or_none()
    
    if not achievement:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Achievement not found",
        )
    
    return _to_response(achievement)


@router.patch("/{achievement_id}", response_model=AchievementResponse)
async def update_achievement(
    achievement_id: str,
    data: AchievementUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> AchievementResponse:
    """Update an achievement."""
    stmt = select(UserAchievement).where(
        and_(
            UserAchievement.id == achievement_id,
            UserAchievement.user_id == current_user.id,
        )
    )
    result = await db.execute(stmt)
    achievement = result.scalar_one_or_none()
    
    if not achievement:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Achievement not found",
        )
    
    if data.title is not None:
        achievement.title = data.title
    if data.category is not None:
        achievement.category = AchievementCategory(data.category.value)
    if data.achievementDate is not None:
        achievement.achievement_date = data.achievementDate
    if data.notes is not None:
        achievement.notes = data.notes
    if data.evidenceLink is not None:
        achievement.evidence_link = data.evidenceLink
    
    await db.commit()
    await db.refresh(achievement)
    
    return _to_response(achievement)


@router.delete("/{achievement_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_achievement(
    achievement_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> None:
    """Delete an achievement."""
    stmt = select(UserAchievement).where(
        and_(
            UserAchievement.id == achievement_id,
            UserAchievement.user_id == current_user.id,
        )
    )
    result = await db.execute(stmt)
    achievement = result.scalar_one_or_none()
    
    if not achievement:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Achievement not found",
        )
    
    await db.delete(achievement)
    await db.commit()
