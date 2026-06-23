"""add user_id to idol import jobs

Revision ID: m9n0p1q2r3s4
Revises: l8g9h0i1j2k3
Create Date: 2026-05-08 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "m9n0p1q2r3s4"
down_revision = "l8g9h0i1j2k3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "idol_import_jobs",
        sa.Column("user_id", postgresql.UUID(as_uuid=False), nullable=True),
    )
    op.create_foreign_key(
        "fk_idol_import_jobs_user_id_users",
        "idol_import_jobs",
        "users",
        ["user_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_idol_import_jobs_user_id",
        "idol_import_jobs",
        ["user_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_idol_import_jobs_user_id", table_name="idol_import_jobs")
    op.drop_constraint(
        "fk_idol_import_jobs_user_id_users",
        "idol_import_jobs",
        type_="foreignkey",
    )
    op.drop_column("idol_import_jobs", "user_id")
