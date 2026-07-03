"""Idol timeline model for storing normalized timeline events."""
from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, Enum as SQLEnum, Float, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin
from app.models.idol_achievement import DatePrecision

if TYPE_CHECKING:
    from app.models.idol import Idol


class IdolTimelineEvent(Base, UUIDMixin, TimestampMixin):
    """
    Stores normalized timeline events for an idol.
    
    These are deduplicated, normalized achievement events
    with computed age information.
    """
    __tablename__ = "idol_timeline_events"
    __table_args__ = (
        # Backs "events for this idol up to age N" lookups
        # (WHERE idol_id = ? AND age_at_event <= ?).
        Index("ix_idol_timeline_idol_age", "idol_id", "age_at_event"),
    )

    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    
    canonical_title: Mapped[str] = mapped_column(String(200), nullable=False)
    canonical_description: Mapped[str] = mapped_column(Text, nullable=False)
    
    event_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    date_precision: Mapped[DatePrecision] = mapped_column(
        SQLEnum(DatePrecision, name="date_precision_enum", create_type=False),
        nullable=False,
        default=DatePrecision.UNKNOWN,
    )
    
    age_at_event: Mapped[int | None] = mapped_column(Integer, nullable=True)
    
    category: Mapped[str] = mapped_column(String(50), nullable=False, default="other")
    importance_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.5)
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.5)
    
    # Store evidence as JSONB
    evidence: Mapped[dict] = mapped_column(JSONB, nullable=False, default=list)
    
    # Relationships
    idol: Mapped["Idol"] = relationship("Idol", back_populates="timeline_events")
