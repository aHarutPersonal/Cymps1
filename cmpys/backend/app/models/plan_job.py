from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampUpdateMixin

class PlanGenerationJob(Base, UUIDMixin, TimestampUpdateMixin):
    __tablename__ = "plan_generation_jobs"

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("idols.id", ondelete="CASCADE"), nullable=False
    )
    # Optional link to the agentic IntakeSession this plan was generated from, so
    # the interview transcript / comparison / blueprint can be threaded in
    # precisely (added in migration s6t7u8v9w0x1). Nullable for legacy /plans jobs.
    session_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("intake_sessions.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    # Relationships
    idol = relationship("Idol")
    status: Mapped[str] = mapped_column(String(50), nullable=False, default="pending")
    progress_percent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    step: Mapped[str | None] = mapped_column(String(100), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    thinking_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    
    # Optional parameters used for generation
    target_age: Mapped[int] = mapped_column(Integer, nullable=False)
    duration_weeks: Mapped[int] = mapped_column(Integer, nullable=False, default=12)
    weekly_hours: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    focus: Mapped[str | None] = mapped_column(String(200), nullable=True)

    # Resulting plan ID (populated when done)
    plan_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False), ForeignKey("plans.id", ondelete="SET NULL"), nullable=True
    )
