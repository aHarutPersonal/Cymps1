"""session LLM-output caches + hot-path indexes

Adds:
  - intake_sessions.idol_suggestions_json: first successful suggest-idols
    output, reused on retry/back-navigation instead of a fresh grounded call.
  - intake_sessions.daily_feed_json: daily insights cached per calendar date.
  - feed_posts(created_at): backs the per-request ORDER BY created_at DESC
    LIMIT N scans on a table that grows forever.
  - daily_task_completions(user_id, completed_date): makes streak/today
    lookups index-only.

All additive (no data change), safe and reversible.

Revision ID: v9x0y1z2a3b4
Revises: u8w9x0y1z2a3
Create Date: 2026-07-03 00:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

# revision identifiers, used by Alembic.
revision: str = "v9x0y1z2a3b4"
down_revision: Union[str, None] = "u8w9x0y1z2a3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "intake_sessions",
        sa.Column("idol_suggestions_json", JSONB, nullable=True),
    )
    op.add_column(
        "intake_sessions",
        sa.Column("daily_feed_json", JSONB, nullable=True),
    )
    op.create_index(
        "ix_feed_posts_created_at",
        "feed_posts",
        ["created_at"],
    )
    op.create_index(
        "ix_daily_task_completions_user_date",
        "daily_task_completions",
        ["user_id", "completed_date"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_daily_task_completions_user_date", table_name="daily_task_completions"
    )
    op.drop_index("ix_feed_posts_created_at", table_name="feed_posts")
    op.drop_column("intake_sessions", "daily_feed_json")
    op.drop_column("intake_sessions", "idol_suggestions_json")
