"""Converge the curriculum usage-ledger lookup index.

Revision ID: i0j1k2l3m4n5
Revises: h9j0k1l2m3n4
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "i0j1k2l3m4n5"
down_revision: Union[str, None] = "h9j0k1l2m3n4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # The index originated in g4, but databases stamped by an early working
    # copy of that revision may not have it. Reconcile forward without editing
    # an applied migration; fresh databases already have it and no-op here.
    op.execute(
        sa.text(
            """
            CREATE INDEX IF NOT EXISTS ix_llm_usage_events_curriculum_job
            ON llm_usage_events ((metadata_json ->> 'curriculum_job_id'))
            WHERE metadata_json ? 'curriculum_job_id'
            """
        )
    )


def downgrade() -> None:
    # This is a convergence revision for a g4-owned schema contract. Dropping
    # the index at h10 -> h9 would make a fully applied g4 schema incomplete;
    # g4's own downgrade removes it when the table contract is rolled back.
    pass
