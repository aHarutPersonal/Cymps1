from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.plan import PlanItem
    from app.models.user import User


class PlanItemDetailJob(Base, UUIDMixin, TimestampMixin):
    """
    Tracks the status and thinking text of a plan item detail (steps/materials) regeneration.
    """
    __tablename__ = "plan_item_detail_jobs"

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
