"""Intake session and answer models for user onboarding questionnaires.

Supports two flows:
1. Legacy idol-specific intake (IntakeSessionStatus-based)
2. Agentic 5-phase workflow (SessionPhase-based)
"""
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import Enum as SQLEnum, ForeignKey, Integer, String, Text, Index
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin, TimestampUpdateMixin

if TYPE_CHECKING:
    from app.models.user import User
    from app.models.idol import Idol
    from app.models.chat import ChatThread


class IntakeSessionStatus(str, Enum):
    """Status of an intake session (legacy flow)."""
    DRAFT = "draft"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"


class SessionPhase(str, Enum):
    """Phase of the 5-state agentic workflow."""
    INTAKE = "intake"
    IDOL_SELECTION = "idol_selection"
    INTERVIEW = "interview"
    COMPARISON = "comparison"
    BLUEPRINT = "blueprint"
    GUIDED_LEARNING = "guided_learning"
    COMPLETED = "completed"

# Valid forward transitions for the state machine
VALID_PHASE_TRANSITIONS: dict[SessionPhase, list[SessionPhase]] = {
    SessionPhase.INTAKE: [SessionPhase.IDOL_SELECTION],
    SessionPhase.IDOL_SELECTION: [SessionPhase.INTERVIEW],
    SessionPhase.INTERVIEW: [SessionPhase.COMPARISON],
    SessionPhase.COMPARISON: [SessionPhase.BLUEPRINT, SessionPhase.INTERVIEW],  # INTERVIEW for retry
    SessionPhase.BLUEPRINT: [SessionPhase.COMPLETED, SessionPhase.GUIDED_LEARNING, SessionPhase.COMPARISON],  # COMPARISON for retry
    SessionPhase.GUIDED_LEARNING: [SessionPhase.COMPLETED],
    SessionPhase.COMPLETED: [],
}


def validate_phase_transition(current: SessionPhase, target: SessionPhase) -> bool:
    """Check if a phase transition is valid. Raises ValueError if not."""
    valid_targets = VALID_PHASE_TRANSITIONS.get(current, [])
    if target not in valid_targets:
        raise ValueError(
            f"Invalid phase transition: {current.value} → {target.value}. "
            f"Valid transitions from {current.value}: {[t.value for t in valid_targets]}"
        )
    return True


class IntakeSession(Base, UUIDMixin, TimestampUpdateMixin):
    """
    An intake questionnaire session for a user-idol pair.
    
    Supports two modes:
    1. Legacy: Uses status + questions_json for idol-specific questionnaires.
    2. Agentic: Uses phase + agentic columns for the 5-phase workflow.
    
    The questions_json stores the LLM-generated questions tailored to the idol.
    """
    __tablename__ = "intake_sessions"
    
    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    idol_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=True,  # Nullable for agentic flow (idol selected in Phase 2)
    )
    
    # Legacy status field
    status: Mapped[IntakeSessionStatus] = mapped_column(
        SQLEnum(
            IntakeSessionStatus,
            name="intake_session_status",
            values_callable=lambda e: [x.value for x in e],
        ),
        nullable=False,
        default=IntakeSessionStatus.DRAFT,
    )
    
    # JSON array of generated questions (legacy flow)
    # Structure: [{"id": "q1", "text": "...", "type": "text|choice|scale", "options": [...], ...}]
    questions_json: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        default=None,
    )
    
    # =========================================================================
    # Agentic Workflow Fields
    # =========================================================================
    
    # Current phase of the 5-state workflow
    phase: Mapped[SessionPhase | None] = mapped_column(
        SQLEnum(SessionPhase, name="session_phase"),
        nullable=True,
        default=None,
    )
    
    # User intake data (collected in Phase 1)
    user_age: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        default=None,
    )
    user_financial_status: Mapped[str | None] = mapped_column(
        String(500),
        nullable=True,
        default=None,
    )
    user_interests: Mapped[list | None] = mapped_column(
        JSONB,
        nullable=True,
        default=None,
    )
    
    # Interview tracking (Phase 3)
    interview_thread_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("chat_threads.id", ondelete="SET NULL"),
        nullable=True,
        default=None,
    )
    interview_turn_count: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
    )
    
    # Guided Learning tracking (Phase 6)
    learning_thread_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("chat_threads.id", ondelete="SET NULL"),
        nullable=True,
        default=None,
    )
    
    # Cached idol facts from web search (used across Phases 3–5)
    idol_facts_json: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        default=None,
    )

    # Structured comparison scores (dimensions + milestones) generated after the
    # prose comparison. Null until generated / if generation fails.
    comparison_scores_json: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        default=None,
    )

    # Cached idol suggestions (Phase 2). Inputs (age/status/interests) are
    # frozen on the session, so the first successful generation is reused on
    # retries/back-navigation instead of a fresh grounded LLM call.
    idol_suggestions_json: Mapped[list | None] = mapped_column(
        JSONB,
        nullable=True,
        default=None,
    )

    # Cached daily insights: {"date": "YYYY-MM-DD", "insights": [...]}.
    # Regenerated only when the date changes — the feed is daily by design.
    daily_feed_json: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        default=None,
    )

    # Generated outputs (Phases 4–5)
    comparison_output: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        default=None,
    )
    blueprint_output: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        default=None,
    )
    
    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="intake_sessions")
    idol: Mapped["Idol | None"] = relationship("Idol", back_populates="intake_sessions")
    interview_thread: Mapped["ChatThread | None"] = relationship(
        "ChatThread",
        foreign_keys=[interview_thread_id],
    )
    learning_thread: Mapped["ChatThread | None"] = relationship(
        "ChatThread",
        foreign_keys=[learning_thread_id],
    )
    answers: Mapped[list["IntakeAnswer"]] = relationship(
        "IntakeAnswer",
        back_populates="session",
        cascade="all, delete-orphan",
        order_by="IntakeAnswer.created_at",
    )
    
    def transition_to(self, target_phase: SessionPhase) -> None:
        """Transition to a new phase with validation."""
        if self.phase is None:
            raise ValueError("Session has no phase set (legacy session?)")
        validate_phase_transition(self.phase, target_phase)
        self.phase = target_phase
    
    # Indexes for common queries
    __table_args__ = (
        Index("ix_intake_sessions_user_id", "user_id"),
        Index("ix_intake_sessions_idol_id", "idol_id"),
        Index("ix_intake_sessions_user_idol", "user_id", "idol_id"),
        Index("ix_intake_sessions_status", "status"),
        Index("ix_intake_sessions_phase", "phase"),
        Index("ix_intake_sessions_user_phase", "user_id", "phase"),
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
    # - Multi-part: {"parts": [{"sub_id": "a", "value": "..."}, ...]
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
