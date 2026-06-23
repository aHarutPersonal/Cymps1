"""add daily task completions table

Revision ID: q4r5s6t7u8v9
Revises: n1o2p3q4r5s6
Create Date: 2026-05-11 14:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "q4r5s6t7u8v9"
down_revision: Union[str, None] = "n1o2p3q4r5s6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "daily_task_completions",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=False),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=False),
            nullable=False,
        ),
        sa.Column(
            "plan_item_id",
            postgresql.UUID(as_uuid=False),
            nullable=False,
        ),
        sa.Column(
            "completed_date",
            sa.Date(),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["plan_item_id"], ["plan_items.id"], ondelete="CASCADE"
        ),
        sa.UniqueConstraint(
            "user_id",
            "plan_item_id",
            "completed_date",
            name="uq_daily_task_completion_user_item_date",
        ),
    )
    op.create_index(
        "ix_daily_task_completions_user_id",
        "daily_task_completions",
        ["user_id"],
    )
    op.create_index(
        "ix_daily_task_completions_plan_item_id",
        "daily_task_completions",
        ["plan_item_id"],
    )
    op.create_index(
        "ix_daily_task_completions_completed_date",
        "daily_task_completions",
        ["completed_date"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_daily_task_completions_completed_date", table_name="daily_task_completions"
    )
    op.drop_index(
        "ix_daily_task_completions_plan_item_id", table_name="daily_task_completions"
    )
    op.drop_index(
        "ix_daily_task_completions_user_id", table_name="daily_task_completions"
    )
    op.drop_table("daily_task_completions")
