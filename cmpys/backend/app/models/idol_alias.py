from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol import Idol


class IdolAlias(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "idol_aliases"

    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("idols.id", ondelete="CASCADE"), nullable=False
    )
    alias_text: Mapped[str] = mapped_column(String(255), nullable=False)

    # Relationships
    idol: Mapped["Idol"] = relationship("Idol", back_populates="aliases")
