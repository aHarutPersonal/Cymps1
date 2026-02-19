from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampUpdateMixin

if TYPE_CHECKING:
    from app.models.user import User


class UserProfile(Base, UUIDMixin, TimestampUpdateMixin):
    __tablename__ = "user_profiles"

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    full_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    birth_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    focus_areas: Mapped[list[str] | None] = mapped_column(
        ARRAY(String(100)), nullable=True
    )
    timezone: Mapped[str | None] = mapped_column(String(50), nullable=True)
    
    # Intake-derived fields
    weekly_hours: Mapped[int | None] = mapped_column(Integer, nullable=True)
    goals: Mapped[list[str] | None] = mapped_column(ARRAY(String(500)), nullable=True)
    interests: Mapped[list[str] | None] = mapped_column(ARRAY(String(200)), nullable=True)
    domains: Mapped[list[str] | None] = mapped_column(ARRAY(String(100)), nullable=True)
    constraints: Mapped[list[str] | None] = mapped_column(ARRAY(String(300)), nullable=True)
    learning_preferences: Mapped[list[str] | None] = mapped_column(ARRAY(String(200)), nullable=True)
    skills: Mapped[dict | None] = mapped_column(JSONB, nullable=True)  # [{name, level, evidence}]
    achievements_raw: Mapped[str | None] = mapped_column(Text, nullable=True)
    readiness_by_gap: Mapped[dict | None] = mapped_column(JSONB, nullable=True)  # {category: level}

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="profile")
