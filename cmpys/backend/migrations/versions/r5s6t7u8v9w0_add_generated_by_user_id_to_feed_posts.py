"""add generated_by_user_id to feed_posts

Revision ID: r5s6t7u8v9w0
Revises: q4r5s6t7u8v9
Create Date: 2026-05-14 17:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "r5s6t7u8v9w0"
down_revision: Union[str, None] = "q4r5s6t7u8v9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "feed_posts",
        sa.Column("generated_by_user_id", sa.String(36), nullable=True),
    )
    op.create_index(
        "ix_feed_posts_generated_by_user_id",
        "feed_posts",
        ["generated_by_user_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_feed_posts_generated_by_user_id")
    op.drop_column("feed_posts", "generated_by_user_id")