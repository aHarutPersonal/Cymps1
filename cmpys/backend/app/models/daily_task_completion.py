"""Daily task completion tracking for habits and practices."""
from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, ForeignKey, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.user import User
    from app.models.plan import PlanItem


class DailyTaskCompletion(Base, UUIDMixin, TimestampMixin):
    """
    Tracks daily completion of habit/practice plan items.

    Each record represents a user completing a habit or practice item on a specific date.
    """
    __tablename__ = "daily_task_completions"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "plan_item_id",
            "completed_date",
            name="uq_daily_task_completion_user_item_date",
        ),
        Index("ix_daily_task_completions_user_id", "user_id"),
        Index("ix_daily_task_completions_plan_item_id", "plan_item_id"),
        Index("ix_daily_task_completions_completed_date", "completed_date"),
        # Backs streak/today lookups (WHERE user_id = ? ORDER BY/filter
        # completed_date) as index-only scans.
        Index("ix_daily_task_completions_user_date", "user_id", "completed_date"),
    )

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    plan_item_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plan_items.id", ondelete="CASCADE"),
        nullable=False,
    )
    completed_date: Mapped[date] = mapped_column(
        Date,
        nullable=False,
    )

    # Relationships
    user: Mapped["User"] = relationship("User")
    plan_item: Mapped["PlanItem"] = relationship("PlanItem")
