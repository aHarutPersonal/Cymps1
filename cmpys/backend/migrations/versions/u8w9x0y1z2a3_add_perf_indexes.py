"""add performance indexes for feed lookups and idol timeline filtering

Adds composite indexes that back hot read paths:
  - feed_likes(user_id, post_id): the feed "which of these posts did I like"
    lookup (WHERE user_id = ? AND post_id IN (...)).
  - feed_comments(post_id, created_at): listing a post's comments by recency.
  - idol_timeline_events(idol_id, age_at_event): timeline events up to an age
    (WHERE idol_id = ? AND age_at_event <= ?).

All are additive (no data change), so this is a safe, reversible migration.

Revision ID: u8w9x0y1z2a3
Revises: cmp_scores_0001
Create Date: 2026-07-01 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "u8w9x0y1z2a3"
down_revision: Union[str, None] = "cmp_scores_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index(
        "ix_feed_likes_user_post",
        "feed_likes",
        ["user_id", "post_id"],
    )
    op.create_index(
        "ix_feed_comments_post_created",
        "feed_comments",
        ["post_id", "created_at"],
    )
    op.create_index(
        "ix_idol_timeline_idol_age",
        "idol_timeline_events",
        ["idol_id", "age_at_event"],
    )


def downgrade() -> None:
    op.drop_index("ix_idol_timeline_idol_age", table_name="idol_timeline_events")
    op.drop_index("ix_feed_comments_post_created", table_name="feed_comments")
    op.drop_index("ix_feed_likes_user_post", table_name="feed_likes")
