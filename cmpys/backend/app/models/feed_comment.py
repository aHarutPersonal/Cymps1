"""Feed comment — user comment on a feed post."""
from sqlalchemy import ForeignKey, Index, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDMixin


class FeedComment(Base, UUIDMixin, TimestampMixin):
    """A comment from a user on a feed post."""

    __tablename__ = "feed_comments"
    __table_args__ = (
        # Backs listing a post's comments ordered by recency
        # (WHERE post_id = ? ORDER BY created_at).
        Index("ix_feed_comments_post_created", "post_id", "created_at"),
    )

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("users.id", ondelete="CASCADE"), nullable=False,
    )
    post_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False), ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False,
    )
    text: Mapped[str] = mapped_column(Text, nullable=False)

    post = relationship("FeedPost", back_populates="comments")
