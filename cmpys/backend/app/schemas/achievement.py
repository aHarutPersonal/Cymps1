"""Schemas for user achievements."""
from datetime import date, datetime
from enum import Enum

from pydantic import BaseModel, Field

from app.models.user_achievement import AchievementSource


class AchievementCategory(str, Enum):
    CAREER = "career"
    LEARNING = "learning"
    FINANCE = "finance"
    IMPACT = "impact"
    MINDSET = "mindset"
    OTHER = "other"


class AchievementCreate(BaseModel):
    """Create a new user achievement."""

    title: str = Field(..., max_length=200)
    category: AchievementCategory = AchievementCategory.OTHER
    achievementDate: date | None = None
    notes: str | None = Field(None, max_length=5000)
    evidenceLink: str | None = Field(None, max_length=2048)
    source: AchievementSource = AchievementSource.MANUAL
    planId: str | None = None
    planItemId: str | None = None
    cycleNumber: int = 1


class AchievementUpdate(BaseModel):
    """Update an existing achievement."""
    
    title: str | None = Field(None, max_length=200)
    category: AchievementCategory | None = None
    achievementDate: date | None = None
    notes: str | None = Field(None, max_length=5000)
    evidenceLink: str | None = Field(None, max_length=2048)


class AchievementResponse(BaseModel):
    """Achievement response schema."""

    id: str
    userId: str
    title: str
    category: AchievementCategory
    achievementDate: date | None = None
    notes: str | None = None
    evidenceLink: str | None = None
    createdAt: datetime
    updatedAt: datetime | None = None  # Optional - falls back to createdAt
    source: AchievementSource = AchievementSource.MANUAL
    planId: str | None = None
    planItemId: str | None = None
    cycleNumber: int = 1

    model_config = {"from_attributes": True}


class AchievementListResponse(BaseModel):
    """List of achievements."""
    
    achievements: list[AchievementResponse]
    total: int
