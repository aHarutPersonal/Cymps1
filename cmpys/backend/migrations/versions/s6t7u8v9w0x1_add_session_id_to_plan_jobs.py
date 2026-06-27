"""add session_id to plan_generation_jobs

Revision ID: s6t7u8v9w0x1
Revises: r5s6t7u8v9w0
Create Date: 2026-06-11 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "s6t7u8v9w0x1"
down_revision: Union[str, None] = "r5s6t7u8v9w0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "plan_generation_jobs",
        sa.Column("session_id", sa.UUID(as_uuid=False), nullable=True),
    )
    op.create_index(
        "ix_plan_generation_jobs_session_id",
        "plan_generation_jobs",
        ["session_id"],
    )
    op.create_foreign_key(
        "fk_plan_generation_jobs_session_id",
        "plan_generation_jobs",
        "intake_sessions",
        ["session_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_plan_generation_jobs_session_id",
        "plan_generation_jobs",
        type_="foreignkey",
    )
    op.drop_index(
        "ix_plan_generation_jobs_session_id",
        table_name="plan_generation_jobs",
    )
    op.drop_column("plan_generation_jobs", "session_id")
