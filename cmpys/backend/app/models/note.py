"""Note and NoteAttachment models for user notes."""
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampUpdateMixin

if TYPE_CHECKING:
    from app.models.user import User
    from app.models.idol import Idol
    from app.models.plan import PlanItem
    from app.models.user_achievement import UserAchievement


class Note(Base, UUIDMixin, TimestampUpdateMixin):
    """
    User's personal notes.
    """
    __tablename__ = "notes"

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    
    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="notes")
    attachments: Mapped[list["NoteAttachment"]] = relationship(
        "NoteAttachment", back_populates="note", cascade="all, delete-orphan"
    )


class NoteAttachment(Base, UUIDMixin, TimestampUpdateMixin):
    """
    Links a note to idols, plan items, or achievements.
    """
    __tablename__ = "note_attachments"

    note_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("notes.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    
    # Optional foreign keys - at least one should be set
    idol_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=True,
    )
    plan_item_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plan_items.id", ondelete="CASCADE"),
        nullable=True,
    )
    achievement_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("user_achievements.id", ondelete="CASCADE"),
        nullable=True,
    )
    
    # Relationships
    note: Mapped["Note"] = relationship("Note", back_populates="attachments")
    idol: Mapped["Idol | None"] = relationship("Idol")
    plan_item: Mapped["PlanItem | None"] = relationship("PlanItem")
    achievement: Mapped["UserAchievement | None"] = relationship("UserAchievement")
