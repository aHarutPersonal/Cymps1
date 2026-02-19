"""Chat models for idol chat threads and messages."""
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import Enum as SQLEnum, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
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
    
    # Relationships
    thread: Mapped["ChatThread"] = relationship("ChatThread", back_populates="messages")
