"""Idol profile model for storing extracted profile data."""
from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, Float, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol import Idol


class IdolProfile(Base, UUIDMixin, TimestampMixin):
    """
    Stores extracted profile data for an idol.
    
    Contains structured biographical information extracted
    from source content using the LLM extraction pipeline.
    """
    __tablename__ = "idol_profiles"

    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    
    display_name: Mapped[str] = mapped_column(String(255), nullable=False)
    short_description: Mapped[str | None] = mapped_column(Text, nullable=True)
    
    birth_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    death_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    
    # Stored as PostgreSQL arrays
    nationality: Mapped[list[str]] = mapped_column(
        ARRAY(String(100)), nullable=False, default=list
    )
    domains: Mapped[list[str]] = mapped_column(
        ARRAY(String(100)), nullable=False, default=list
    )
    primary_roles: Mapped[list[str]] = mapped_column(
        ARRAY(String(100)), nullable=False, default=list
    )
    era_tags: Mapped[list[str]] = mapped_column(
        ARRAY(String(100)), nullable=False, default=list
    )
    notable_themes: Mapped[list[str]] = mapped_column(
        ARRAY(String(100)), nullable=False, default=list
    )
    
    wikipedia_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    
    # Store evidence as JSONB
    evidence: Mapped[dict] = mapped_column(JSONB, nullable=False, default=list)
    
    # Relationships
    idol: Mapped["Idol"] = relationship("Idol", back_populates="profile")
