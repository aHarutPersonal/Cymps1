"""Private versioned workbook, draft and immutable attempt snapshots."""

from datetime import datetime
from sqlalchemy import DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column
from app.models.base import Base, UUIDMixin, TimestampUpdateMixin


class LessonPractice(Base, UUIDMixin, TimestampUpdateMixin):
    __tablename__ = "lesson_practices"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "plan_item_id",
            "step_id",
            "lesson_version",
            name="uq_lesson_practice_version",
        ),
    )
    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    plan_item_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plan_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    step_id: Mapped[str] = mapped_column(String(100), nullable=False)
    lesson_version: Mapped[str] = mapped_column(String(64), nullable=False)
    state: Mapped[str] = mapped_column(String(20), nullable=False, default="preparing")
    revision: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    generation_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    review_calls: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    lease_token: Mapped[str | None] = mapped_column(String(80))
    lease_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    workbook_json: Mapped[dict | None] = mapped_column(JSONB)
    answers_json: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    attempts_json: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    hints_json: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
