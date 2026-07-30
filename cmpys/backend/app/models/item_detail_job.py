from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, false, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampUpdateMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.plan import PlanItem
    from app.models.user import User


class PlanItemDetailJob(Base, UUIDMixin, TimestampUpdateMixin):
    """
    Tracks the status and thinking text of a plan item detail (steps/materials) regeneration.
    """

    __tablename__ = "plan_item_detail_jobs"

    # Artifact chronology needs a post-lock wall-clock epoch. Keep inherited
    # created_at as ordinary audit metadata: PostgreSQL now() is transaction-
    # start time and is therefore unsafe for latest-job selection.
    artifact_epoch_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.clock_timestamp(),
        nullable=False,
    )
    # Set before a job first publishes over any user-visible artifact. This is
    # durable even when the predecessor was a legacy artifact with no job ID.
    supersedes_artifact: Mapped[bool] = mapped_column(
        Boolean,
        server_default=false(),
        default=False,
        nullable=False,
    )

    plan_item_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plan_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    status: Mapped[str] = mapped_column(String(50), nullable=False, default="queued")
    step: Mapped[str | None] = mapped_column(String(100), nullable=True)
    progress_percent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    thinking_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    result_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    # Relationships
    plan_item: Mapped["PlanItem"] = relationship("PlanItem")
    user: Mapped["User"] = relationship("User")
