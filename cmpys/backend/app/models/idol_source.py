from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol import Idol
    from app.models.source_chunk import SourceChunk


class IdolSource(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "idol_sources"

    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=False,
    )
    source_type: Mapped[str] = mapped_column(String(50), nullable=False, default="wikipedia")
    url: Mapped[str] = mapped_column(String(2048), nullable=False)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    summary_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    full_text: Mapped[str] = mapped_column(Text, nullable=False)

    # Relationships
    idol: Mapped["Idol"] = relationship("Idol", back_populates="sources")
    chunks: Mapped[list["SourceChunk"]] = relationship(
        "SourceChunk", back_populates="source", cascade="all, delete-orphan"
    )
