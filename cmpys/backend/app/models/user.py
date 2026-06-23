from typing import TYPE_CHECKING

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.chat import ChatThread
    from app.models.content_resource import UserContentHighlight, UserContentProgress, UserContentSave
    from app.models.intake import IntakeSession
    from app.models.note import Note
    from app.models.plan import Plan
    from app.models.user_achievement import UserAchievement
    from app.models.user_profile import UserProfile
    from app.models.stashed_idea import StashedIdea


class User(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    # Relationships
    profile: Mapped["UserProfile | None"] = relationship(
        "UserProfile", back_populates="user", uselist=False, cascade="all, delete-orphan"
    )
    achievements: Mapped[list["UserAchievement"]] = relationship(
        "UserAchievement", back_populates="user", cascade="all, delete-orphan"
    )
    plans: Mapped[list["Plan"]] = relationship(
        "Plan", back_populates="user", cascade="all, delete-orphan"
    )
    notes: Mapped[list["Note"]] = relationship(
        "Note", back_populates="user", cascade="all, delete-orphan"
    )
    chat_threads: Mapped[list["ChatThread"]] = relationship(
        "ChatThread", back_populates="user", cascade="all, delete-orphan"
    )
    intake_sessions: Mapped[list["IntakeSession"]] = relationship(
        "IntakeSession", back_populates="user", cascade="all, delete-orphan"
    )
    stashed_ideas: Mapped[list["StashedIdea"]] = relationship(
        "StashedIdea", back_populates="user", cascade="all, delete-orphan"
    )
    content_saves: Mapped[list["UserContentSave"]] = relationship(
        "UserContentSave", back_populates="user", cascade="all, delete-orphan"
    )
    content_progress: Mapped[list["UserContentProgress"]] = relationship(
        "UserContentProgress", back_populates="user", cascade="all, delete-orphan"
    )
    content_highlights: Mapped[list["UserContentHighlight"]] = relationship(
        "UserContentHighlight", back_populates="user", cascade="all, delete-orphan"
    )
