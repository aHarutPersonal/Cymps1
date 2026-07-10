"""Sourced quotations collected for the shared catalog."""
from __future__ import annotations

import hashlib
import re
import unicodedata
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, Enum as SQLEnum, Float, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampUpdateMixin, UUIDMixin
from app.models.idol import CatalogStatus

if TYPE_CHECKING:
    from app.models.feed_post import FeedPost
    from app.models.idol import Idol


class QuoteType(str, Enum):
    SOURCED = "sourced"
    ATTRIBUTED = "attributed"
    PARAPHRASE = "paraphrase"


class QuoteVerificationState(str, Enum):
    SOURCE_BACKED = "source_backed"
    VERIFIED = "verified"
    INCONCLUSIVE = "inconclusive"
    REJECTED = "rejected"


class VerifiedQuote(Base, UUIDMixin, TimestampUpdateMixin):
    __tablename__ = "verified_quotes"
    __table_args__ = (
        Index("ix_verified_quotes_idol_status", "idol_id", "status"),
        Index("ix_verified_quotes_category", "category"),
    )

    idol_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=True,
    )
    speaker: Mapped[str] = mapped_column(String(255), nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    normalized_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    quote_type: Mapped[QuoteType] = mapped_column(
        SQLEnum(
            QuoteType,
            name="quote_type",
            values_callable=lambda values: [value.value for value in values],
        ),
        nullable=False,
        default=QuoteType.ATTRIBUTED,
    )
    language: Mapped[str] = mapped_column(String(12), nullable=False, default="en")
    category: Mapped[str | None] = mapped_column(String(50), nullable=True)
    context: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_title: Mapped[str | None] = mapped_column(String(500), nullable=True)
    source_url: Mapped[str] = mapped_column(String(2048), nullable=False)
    source_reference: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_provider: Mapped[str] = mapped_column(String(50), nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    evidence_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    verification_state: Mapped[QuoteVerificationState] = mapped_column(
        SQLEnum(
            QuoteVerificationState,
            name="quote_verification_state",
            values_callable=lambda values: [value.value for value in values],
        ),
        nullable=False,
        default=QuoteVerificationState.SOURCE_BACKED,
        index=True,
    )
    verification_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    verification_model: Mapped[str | None] = mapped_column(String(100), nullable=True)
    verification_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    verified_source_title: Mapped[str | None] = mapped_column(String(500), nullable=True)
    verified_source_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    verification_attempted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[CatalogStatus] = mapped_column(
        SQLEnum(
            CatalogStatus,
            name="catalog_status",
            create_type=False,
            values_callable=lambda values: [value.value for value in values],
        ),
        nullable=False,
        default=CatalogStatus.PENDING,
        index=True,
    )
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    idol: Mapped["Idol | None"] = relationship("Idol", back_populates="verified_quotes")
    feed_post: Mapped["FeedPost | None"] = relationship(
        "FeedPost", back_populates="quote", uselist=False
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("quote_type", QuoteType.ATTRIBUTED)
        kwargs.setdefault("status", CatalogStatus.PENDING)
        kwargs.setdefault("language", "en")
        kwargs.setdefault("confidence", 0.0)
        kwargs.setdefault("verification_state", QuoteVerificationState.SOURCE_BACKED)
        super().__init__(**kwargs)

    @staticmethod
    def compute_hash(speaker: str, text: str) -> str:
        normalized = unicodedata.normalize("NFKC", text).lower()
        normalized = re.sub(r"[“”„‟\"']", "", normalized)
        normalized = re.sub(r"\s+", " ", normalized).strip()
        return hashlib.sha256(f"{speaker.strip().lower()}|{normalized}".encode()).hexdigest()
