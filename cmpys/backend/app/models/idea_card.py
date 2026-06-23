from typing import TYPE_CHECKING

from sqlalchemy import Boolean, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol import Idol


class IdeaCard(Base, UUIDMixin, TimestampMixin):
    """
    Atomic idea card — a single snackable insight tied to an idol.

    Each card holds 1-3 sentences of markdown content, categorised by
    a tag (e.g. "mindset", "discipline", "leadership").  Cards can
    optionally be locked behind premium gating.
    """

    __tablename__ = "idea_cards"

    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    category_tag: Mapped[str] = mapped_column(
        String(64), nullable=False, index=True,
    )
    content_markdown: Mapped[str] = mapped_column(
        Text, nullable=False,
    )
    is_locked: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="false", nullable=False,
    )
    sort_order: Mapped[int] = mapped_column(
        Integer, default=0, server_default="0", nullable=False,
    )

    # Relationships
    idol: Mapped["Idol"] = relationship(
        "Idol", back_populates="idea_cards",
    )
