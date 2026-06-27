"""merge catalog_foundation and session_id heads

Two migration lineages both reached a head independently:
  - 0528e5d2fba2 (catalog_foundation)
  - s6t7u8v9w0x1 (add session_id to plan_generation_jobs)

`alembic upgrade head` errors with "multiple heads" until they are merged.
This is an empty merge revision that joins them into a single head so the
deploy migrate step (`alembic upgrade head`) runs cleanly.

Revision ID: t7u8v9w0x1y2
Revises: 0528e5d2fba2, s6t7u8v9w0x1
Create Date: 2026-06-28 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "t7u8v9w0x1y2"
down_revision: Union[str, Sequence[str], None] = ("0528e5d2fba2", "s6t7u8v9w0x1")
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
