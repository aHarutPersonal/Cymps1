"""Feed like — user ↔ post relationship."""
from sqlalchemy import ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDMixin


class FeedLike(Base, UUIDMixin, TimestampMixin):
    """A single like from a user on a feed post."""

    __tablename__ = "feed_likes"
    __table_args__ = (
        # Backs the feed "which of these posts did I like" lookup
        # (WHERE user_id = ? AND post_id IN (...)).
        Index("ix_feed_likes_user_post", "user_id", "post_id"),
        {"extend_existing": True},
    )

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("users.id", ondelete="CASCADE"), nullable=False,
    )
    post_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False,
    )

    post = relationship("FeedPost", back_populates="likes")
