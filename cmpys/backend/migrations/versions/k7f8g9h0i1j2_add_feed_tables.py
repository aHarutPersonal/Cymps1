"""Add feed tables (feed_posts, feed_likes, feed_comments).

Revision ID: k7f8g9h0i1j2
Revises: 4e91b83a38a2
Create Date: 2026-03-21
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "k7f8g9h0i1j2"
down_revision = "4e91b83a38a2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "feed_posts",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column("type", sa.String(20), nullable=False),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("content", sa.Text, nullable=True),
        sa.Column("category", sa.String(50), nullable=True),
        sa.Column("source", sa.String(255), nullable=True),
        sa.Column("url", sa.String(1024), nullable=True),
        sa.Column("content_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("like_count", sa.Integer, server_default="0", nullable=False),
        sa.Column("comment_count", sa.Integer, server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_feed_posts_content_hash", "feed_posts", ["content_hash"])

    op.create_table(
        "feed_likes",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=False), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("post_id", postgresql.UUID(as_uuid=False), sa.ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "post_id", name="uq_feed_like_user_post"),
    )

    op.create_table(
        "feed_comments",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=False), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("post_id", postgresql.UUID(as_uuid=False), sa.ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("text", sa.Text, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("feed_comments")
    op.drop_table("feed_likes")
    op.drop_index("ix_feed_posts_content_hash", table_name="feed_posts")
    op.drop_table("feed_posts")
