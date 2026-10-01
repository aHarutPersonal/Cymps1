"""Preserve detailed intake outcomes when staging plan generation."""

from alembic import op
import sqlalchemy as sa

revision = "k2l3m4n5o6p7"
down_revision = "j1k2l3m4n5o6"
branch_labels = None
depends_on = None


def upgrade():
    op.alter_column(
        "plan_generation_jobs",
        "focus",
        existing_type=sa.String(200),
        type_=sa.Text(),
        existing_nullable=True,
    )


def downgrade():
    too_long = (
        op.get_bind()
        .execute(
            sa.text(
                "SELECT EXISTS (SELECT 1 FROM plan_generation_jobs WHERE length(focus) > 200)"
            )
        )
        .scalar()
    )
    if too_long:
        raise RuntimeError(
            "Cannot narrow plan focus without losing saved learning goals"
        )
    op.alter_column(
        "plan_generation_jobs",
        "focus",
        existing_type=sa.Text(),
        type_=sa.String(200),
        existing_nullable=True,
    )
