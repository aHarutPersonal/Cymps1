"""Intake session and answer models for user onboarding questionnaires."""
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import Enum as SQLEnum, ForeignKey, String, Index
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin, TimestampUpdateMixin

if TYPE_CHECKING:
    from app.models.user import User
    from app.models.idol import Idol


class IntakeSessionStatus(str, Enum):
    """Status of an intake session."""
    DRAFT = "draft"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"


class IntakeSession(Base, UUIDMixin, TimestampUpdateMixin):
    """
    An intake questionnaire session for a user-idol pair.
    
    Stores the generated questions and tracks completion status.
    The questions_json stores the LLM-generated questions tailored to the idol.
    """
    __tablename__ = "intake_sessions"
    
    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=False,
    )
    
    status: Mapped[IntakeSessionStatus] = mapped_column(
        SQLEnum(IntakeSessionStatus, name="intake_session_status"),
        nullable=False,
        default=IntakeSessionStatus.DRAFT,
    )
    
    # JSON array of generated questions
    # Structure: [{"id": "q1", "text": "...", "type": "text|choice|scale", "options": [...], ...}]
    questions_json: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        default=None,
    )
    
    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="intake_sessions")
    idol: Mapped["Idol"] = relationship("Idol", back_populates="intake_sessions")
    answers: Mapped[list["IntakeAnswer"]] = relationship(
        "IntakeAnswer",
        back_populates="session",
        cascade="all, delete-orphan",
        order_by="IntakeAnswer.created_at",
    )
    
    # Indexes for common queries
    __table_args__ = (
        Index("ix_intake_sessions_user_id", "user_id"),
        Index("ix_intake_sessions_idol_id", "idol_id"),
        Index("ix_intake_sessions_user_idol", "user_id", "idol_id"),
        Index("ix_intake_sessions_status", "status"),
    )


class IntakeAnswer(Base, UUIDMixin, TimestampMixin):
    """
    An answer to a single intake question.
    
    Stores the user's response in a flexible JSON format to accommodate
    different question types (text, choice, scale, etc.).
    """
    __tablename__ = "intake_answers"
    
    session_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("intake_sessions.id", ondelete="CASCADE"),
        nullable=False,
    )
    
    # References the question id from the session's questions_json
    question_id: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
    )
    
    # Flexible JSON to store different answer types
    # Examples:
    # - Text: {"value": "I want to learn..."}
    # - Choice: {"selected": ["option_a", "option_b"]}
    # - Scale: {"value": 7}
    # - Multi-part: {"parts": [{"sub_id": "a", "value": "..."}, ...]}
    answer_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
    )
    
    # Relationships
    session: Mapped["IntakeSession"] = relationship(
        "IntakeSession",
        back_populates="answers",
    )
    
    # Indexes
    __table_args__ = (
        Index("ix_intake_answers_session_id", "session_id"),
        Index("ix_intake_answers_session_question", "session_id", "question_id"),
    )
