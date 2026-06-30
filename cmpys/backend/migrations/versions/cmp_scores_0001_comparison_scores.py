"""comparison scores json on intake_sessions

Revision ID: cmp_scores_0001
Revises: ach_cycle_0001
Create Date: 2026-06-29

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "cmp_scores_0001"
down_revision: Union[str, None] = "ach_cycle_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "intake_sessions",
        sa.Column("comparison_scores_json", postgresql.JSONB(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("intake_sessions", "comparison_scores_json")
