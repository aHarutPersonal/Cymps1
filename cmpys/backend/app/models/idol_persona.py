"""Idol persona model for storing chat persona data."""
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol import Idol


class IdolPersona(Base, UUIDMixin, TimestampMixin):
    """
    Stores chat persona data for an idol.
    
    Used for AI chat simulations grounded in source content.
    """
    __tablename__ = "idol_personas"

    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    
    voice_style: Mapped[str] = mapped_column(Text, nullable=False)
    
    principles: Mapped[list[str]] = mapped_column(
        ARRAY(String(500)), nullable=False, default=list
    )
    dos: Mapped[list[str]] = mapped_column(
        ARRAY(String(500)), nullable=False, default=list
    )
    donts: Mapped[list[str]] = mapped_column(
        ARRAY(String(500)), nullable=False, default=list
    )
    signature_phrases: Mapped[list[str]] = mapped_column(
        ARRAY(String(500)), nullable=False, default=list
    )
    topics_of_strength: Mapped[list[str]] = mapped_column(
        ARRAY(String(200)), nullable=False, default=list
    )
    taboo_topics: Mapped[list[str]] = mapped_column(
        ARRAY(String(200)), nullable=False, default=list
    )
    
    # Store grounding evidence as JSONB
    grounding_evidence: Mapped[dict] = mapped_column(JSONB, nullable=False, default=list)
    
    disclaimer: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        default="AI simulation based on public sources; may be inaccurate.",
    )
    
    # Era-aware fields for historical authenticity
    era_context: Mapped[str | None] = mapped_column(
        String(50),
        nullable=True,
        default="contemporary",
    )
    lexicon_allow: Mapped[list[str] | None] = mapped_column(
        ARRAY(String(200)),
        nullable=True,
        default=list,
    )
    lexicon_ban: Mapped[list[str] | None] = mapped_column(
        ARRAY(String(200)),
        nullable=True,
        default=list,
    )
    worldview_adapter: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        default=dict,
    )
    default_frameworks: Mapped[list[str] | None] = mapped_column(
        ARRAY(String(300)),
        nullable=True,
        default=list,
    )
    
    # Relationships
    idol: Mapped["Idol"] = relationship("Idol", back_populates="persona")
