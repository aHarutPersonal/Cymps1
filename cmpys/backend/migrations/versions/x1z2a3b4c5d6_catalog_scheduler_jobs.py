"""add catalog scheduler state to ingest jobs

Revision ID: x1z2a3b4c5d6
Revises: w0y1z2a3b4c5
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "x1z2a3b4c5d6"
down_revision: Union[str, None] = "w0y1z2a3b4c5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("ingest_jobs", sa.Column("payload_json", postgresql.JSONB(), nullable=True))
    op.add_column(
        "ingest_jobs", sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column("ingest_jobs", sa.Column("locked_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column(
        "ingest_jobs", sa.Column("last_started_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "ingest_jobs", sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.create_index(
        "ix_ingest_jobs_state_due_priority",
        "ingest_jobs",
        ["state", "next_attempt_at", "priority"],
    )


def downgrade() -> None:
    op.drop_index("ix_ingest_jobs_state_due_priority", table_name="ingest_jobs")
    for column in (
        "completed_at",
        "last_started_at",
        "locked_at",
        "next_attempt_at",
        "payload_json",
    ):
        op.drop_column("ingest_jobs", column)
