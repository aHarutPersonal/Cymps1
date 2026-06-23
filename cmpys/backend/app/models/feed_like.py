"""Feed like — user ↔ post relationship."""
from sqlalchemy import ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDMixin


class FeedLike(Base, UUIDMixin, TimestampMixin):
    """A single like from a user on a feed post."""

    __tablename__ = "feed_likes"
    __table_args__ = (
        {"extend_existing": True},
    )

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("users.id", ondelete="CASCADE"), nullable=False,
    )
    post_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False,
    )

    post = relationship("FeedPost", back_populates="likes")
