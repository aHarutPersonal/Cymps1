"""Add private versioned lesson practice and durable attempt snapshots."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "j1k2l3m4n5o6"
down_revision = "i0j1k2l3m4n5"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "lesson_practices",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "plan_item_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("plan_items.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("step_id", sa.String(100), nullable=False),
        sa.Column("lesson_version", sa.String(64), nullable=False),
        sa.Column("state", sa.String(20), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("generation_attempts", sa.Integer(), nullable=False),
        sa.Column("review_calls", sa.Integer(), nullable=False),
        sa.Column("lease_token", sa.String(80)),
        sa.Column("lease_until", sa.DateTime(timezone=True)),
        sa.Column("workbook_json", postgresql.JSONB()),
        sa.Column("answers_json", postgresql.JSONB(), nullable=False),
        sa.Column("attempts_json", postgresql.JSONB(), nullable=False),
        sa.Column("hints_json", postgresql.JSONB(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "user_id",
            "plan_item_id",
            "step_id",
            "lesson_version",
            name="uq_lesson_practice_version",
        ),
    )
    op.create_index(
        "ix_lesson_practices_plan_item_id", "lesson_practices", ["plan_item_id"]
    )


def downgrade():
    op.drop_table("lesson_practices")
