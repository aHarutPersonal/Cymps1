"""Feed post — persisted feed content (quotes, videos)."""
import hashlib

from sqlalchemy import Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDMixin


class FeedPost(Base, UUIDMixin, TimestampMixin):
    """A single persisted feed item visible to all users."""

    __tablename__ = "feed_posts"

    type: Mapped[str] = mapped_column(String(20), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    content: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str | None] = mapped_column(String(50), nullable=True)
    source: Mapped[str | None] = mapped_column(String(255), nullable=True)
    url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    content_hash: Mapped[str] = mapped_column(
        String(64), nullable=False, unique=True, index=True,
    )

    like_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    comment_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")

    likes = relationship("FeedLike", back_populates="post", cascade="all, delete-orphan")
    comments = relationship("FeedComment", back_populates="post", cascade="all, delete-orphan")

    @staticmethod
    def compute_hash(title: str, content: str | None) -> str:
        """Create a content hash for deduplication."""
        raw = f"{title}|{content or ''}"
        return hashlib.sha256(raw.encode()).hexdigest()
