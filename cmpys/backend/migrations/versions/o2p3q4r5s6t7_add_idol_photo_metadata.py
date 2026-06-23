"""add idol photo metadata

Revision ID: o2p3q4r5s6t7
Revises: n1o2p3q4r5s6
Create Date: 2026-05-09 00:00:00.000000
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "o2p3q4r5s6t7"
down_revision: str | None = "n1o2p3q4r5s6"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("idols", sa.Column("image_source_url", sa.String(length=2048), nullable=True))
    op.add_column("idols", sa.Column("image_license", sa.String(length=120), nullable=True))
    op.add_column("idols", sa.Column("image_attribution_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True))


def downgrade() -> None:
    op.drop_column("idols", "image_attribution_json")
    op.drop_column("idols", "image_license")
    op.drop_column("idols", "image_source_url")
