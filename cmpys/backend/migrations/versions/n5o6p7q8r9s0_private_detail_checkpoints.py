"""Preserve private lesson work across interrupted generation attempts.

The nullable column permits rolling deployment and does not rewrite old rows.
Production rollback should roll back application code and retain this column.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "n5o6p7q8r9s0"
down_revision = "m4n5o6p7q8r9"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "plan_item_detail_jobs",
        sa.Column("private_checkpoint_json", postgresql.JSONB(), nullable=True),
    )


def downgrade():
    if op.get_bind().execute(sa.text(
        "SELECT EXISTS (SELECT 1 FROM plan_item_detail_jobs "
        "WHERE private_checkpoint_json IS NOT NULL)"
    )).scalar():
        raise RuntimeError("Cannot discard saved private lesson work during downgrade")
    op.drop_column("plan_item_detail_jobs", "private_checkpoint_json")
