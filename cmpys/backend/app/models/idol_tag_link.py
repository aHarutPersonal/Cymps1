from typing import TYPE_CHECKING

from sqlalchemy import Float, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol import Idol
    from app.models.idol_tag import IdolTag


class IdolTagLink(Base, TimestampMixin):
    __tablename__ = "idol_tag_links"
    __table_args__ = (
        UniqueConstraint("idol_id", "tag_id", name="uq_idol_tag"),
    )

    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        primary_key=True,
    )
    tag_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idol_tags.id", ondelete="CASCADE"),
        primary_key=True,
    )
    weight: Mapped[float] = mapped_column(Float, nullable=False, default=1.0)

    # Relationships
    idol: Mapped["Idol"] = relationship("Idol", back_populates="tag_links")
    tag: Mapped["IdolTag"] = relationship("IdolTag", back_populates="idol_links")
