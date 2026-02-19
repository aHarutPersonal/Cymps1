from typing import TYPE_CHECKING

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idol_tag_link import IdolTagLink


class IdolTag(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "idol_tags"

    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    type: Mapped[str] = mapped_column(String(50), nullable=False)  # e.g., "domain", "focus", "industry"

    # Relationships
    idol_links: Mapped[list["IdolTagLink"]] = relationship(
        "IdolTagLink", back_populates="tag", cascade="all, delete-orphan"
    )
