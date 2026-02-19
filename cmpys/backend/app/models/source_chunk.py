from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol_source import IdolSource


class SourceChunk(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "source_chunks"

    source_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idol_sources.id", ondelete="CASCADE"),
        nullable=False,
    )
    chunk_index: Mapped[int] = mapped_column(Integer, nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)

    # Relationships
    source: Mapped["IdolSource"] = relationship("IdolSource", back_populates="chunks")
