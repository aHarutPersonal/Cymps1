"""Chat models for idol chat threads and messages."""
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, Enum as SQLEnum, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.user import User
    from app.models.idol import Idol


class MessageRole(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"


class ChatThread(Base, UUIDMixin, TimestampMixin):
    """
    A chat thread between a user and an idol persona.
    """
    __tablename__ = "chat_threads"

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Short-lived durable lease for interview generation. It covers kickoff as
    # well as answer turns, so retries across workers cannot generate twice.
    interview_claim_key: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
        default=None,
    )
    interview_claim_token: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        nullable=True,
        default=None,
    )
    interview_claimed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        default=None,
    )

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="chat_threads", lazy="selectin")
    idol: Mapped["Idol"] = relationship("Idol", lazy="selectin")
    messages: Mapped[list["ChatMessage"]] = relationship(
        "ChatMessage", back_populates="thread", cascade="all, delete-orphan",
        order_by="ChatMessage.created_at",
        lazy="selectin"
    )


class ChatMessage(Base, UUIDMixin, TimestampMixin):
    """
    A message in a chat thread.
    """
    __tablename__ = "chat_messages"

    thread_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("chat_threads.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    role: Mapped[MessageRole] = mapped_column(
        SQLEnum(MessageRole, name="message_role"),
        nullable=False,
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    # Durable request chain for interview idempotency. A user answer points to
    # its assistant question; the generated assistant reply points to that
    # answer. The unique constraint permits only one direct reply per message.
    reply_to_message_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("chat_messages.id", ondelete="SET NULL"),
        nullable=True,
        unique=True,
        default=None,
    )
    # Used only on user interview answers: pending | completed | failed.
    generation_status: Mapped[str | None] = mapped_column(
        String(20),
        nullable=True,
        default=None,
    )
    # Lets interview questions restore choice/number controls on resume while
    # keeping the message content as the canonical provider-agnostic transcript.
    response_ui_json: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        default=None,
    )

    # Relationships
    thread: Mapped["ChatThread"] = relationship("ChatThread", back_populates="messages")
