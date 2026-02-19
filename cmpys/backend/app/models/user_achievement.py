"""User achievement model for tracking personal accomplishments."""
from datetime import date
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import Date, Enum as SQLEnum, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.user import User


class AchievementCategory(str, Enum):
    CAREER = "career"
    LEARNING = "learning"
    FINANCE = "finance"
    IMPACT = "impact"
    MINDSET = "mindset"
    OTHER = "other"


class UserAchievement(Base, UUIDMixin, TimestampMixin):
    """
    User's personal achievements/milestones.
    
    Separate from idol achievements - these are things the user
    has accomplished that can be compared against idol milestones.
    """
    __tablename__ = "user_achievements"

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    category: Mapped[AchievementCategory] = mapped_column(
        SQLEnum(AchievementCategory, name="user_achievement_category"),
        nullable=False,
        default=AchievementCategory.OTHER,
    )
    achievement_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    evidence_link: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    
    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="achievements")
