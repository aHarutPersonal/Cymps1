import enum
from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, Enum, Float, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol import Idol
    from app.models.achievement_evidence import AchievementEvidence


class DatePrecision(str, enum.Enum):
    DAY = "day"
    MONTH = "month"
    YEAR = "year"
    UNKNOWN = "unknown"


class IdolAchievement(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "idol_achievements"

    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("idols.id", ondelete="CASCADE"), nullable=False
    )
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    achievement_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    date_precision: Mapped[DatePrecision] = mapped_column(
        Enum(DatePrecision, name="date_precision"),
        nullable=False,
        default=DatePrecision.UNKNOWN,
    )
    age_at_achievement: Mapped[int | None] = mapped_column(Integer, nullable=True)
    category: Mapped[str] = mapped_column(String(100), nullable=False)
    importance_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    confidence_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    # Relationships
    idol: Mapped["Idol"] = relationship("Idol", back_populates="achievements")
    evidence: Mapped[list["AchievementEvidence"]] = relationship(
        "AchievementEvidence", back_populates="achievement", cascade="all, delete-orphan"
    )
