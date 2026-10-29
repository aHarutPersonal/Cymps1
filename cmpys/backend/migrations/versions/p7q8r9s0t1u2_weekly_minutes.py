"""weekly_minutes: weekly capacity in minutes on plans, plan jobs and profiles.

Intake v3 records 1-15 focused hours a week in half-hour steps, so capacity
is stored as minutes (60-900). ``weekly_hours`` stays and is written as
``ceil(weekly_minutes / 60)`` for legacy readers and old app builds.

Additive and nullable, with a one-time backfill of ``weekly_hours * 60`` for
existing rows. Application code reads ``weekly_minutes`` and falls back to
``weekly_hours * 60`` when it is NULL, so a row written by an older release
during a rolling deploy remains valid. Production rollback should roll back
application code and retain the column.

Revision ID: p7q8r9s0t1u2
Revises: o6p7q8r9s0t1
"""

from alembic import op
import sqlalchemy as sa

revision = "p7q8r9s0t1u2"
down_revision = "o6p7q8r9s0t1"
branch_labels = None
depends_on = None

_TABLES = ("plans", "plan_generation_jobs", "user_profiles")


def upgrade():
    for table in _TABLES:
        op.add_column(table, sa.Column("weekly_minutes", sa.Integer(), nullable=True))
        op.execute(
            sa.text(
                f"UPDATE {table} SET weekly_minutes = weekly_hours * 60 "
                "WHERE weekly_minutes IS NULL AND weekly_hours IS NOT NULL"
            )
        )


def downgrade():
    for table in reversed(_TABLES):
        op.drop_column(table, "weekly_minutes")
