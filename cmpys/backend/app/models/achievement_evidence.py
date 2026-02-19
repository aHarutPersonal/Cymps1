from typing import TYPE_CHECKING

from sqlalchemy import Float, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol_achievement import IdolAchievement


class AchievementEvidence(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "achievement_evidence"

    achievement_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idol_achievements.id", ondelete="CASCADE"),
        nullable=False,
    )
    source_title: Mapped[str] = mapped_column(String(500), nullable=False)
    source_url: Mapped[str] = mapped_column(String(2048), nullable=False)
    snippet: Mapped[str] = mapped_column(Text, nullable=False)
    confidence_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    # Relationships
    achievement: Mapped["IdolAchievement"] = relationship(
        "IdolAchievement", back_populates="evidence"
    )
