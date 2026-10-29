"""intake_sessions.situation_json: the onboarding situation chips and note.

The v3 onboarding "Your situation" step collects chips ("I work full-time",
"Evenings are best") and an optional note. They are stored as
``{"situation": [...], "note": str | null}`` and threaded into the comparison,
blueprint and plan prompts.

Additive and nullable: it does not rewrite existing rows, so it is safe for a
rolling deployment, and application code from before this revision ignores the
column. Production rollback should roll back application code and retain it.

Revision ID: o6p7q8r9s0t1
Revises: n5o6p7q8r9s0
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "o6p7q8r9s0t1"
down_revision = "n5o6p7q8r9s0"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "intake_sessions",
        sa.Column("situation_json", postgresql.JSONB(), nullable=True),
    )


def downgrade():
    op.drop_column("intake_sessions", "situation_json")
