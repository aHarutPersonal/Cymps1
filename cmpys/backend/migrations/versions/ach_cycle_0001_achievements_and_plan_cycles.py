"""achievements provenance and plan cycles

Revision ID: ach_cycle_0001
Revises: t7u8v9w0x1y2
Create Date: 2026-06-28

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "ach_cycle_0001"
down_revision: Union[str, None] = "t7u8v9w0x1y2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    achievement_source = sa.Enum(
        "manual", "plan_item", "plan_cycle", name="achievement_source"
    )
    achievement_source.create(op.get_bind(), checkfirst=True)

    op.add_column(
        "user_achievements",
        sa.Column(
            "source", achievement_source, nullable=False, server_default="manual"
        ),
    )
    op.add_column(
        "user_achievements", sa.Column("plan_id", sa.UUID(), nullable=True)
    )
    op.add_column(
        "user_achievements", sa.Column("plan_item_id", sa.UUID(), nullable=True)
    )
    op.add_column(
        "user_achievements",
        sa.Column("cycle_number", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_foreign_key(
        "fk_user_ach_plan", "user_achievements", "plans", ["plan_id"], ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        "fk_user_ach_plan_item", "user_achievements", "plan_items",
        ["plan_item_id"], ["id"], ondelete="SET NULL",
    )
    op.create_index(
        "uq_ach_plan_item_source",
        "user_achievements",
        ["plan_item_id"],
        unique=True,
        postgresql_where=sa.text("source = 'plan_item'"),
    )

    op.add_column(
        "plans",
        sa.Column("cycle_number", sa.Integer(), nullable=False, server_default="1"),
    )
    op.add_column(
        "plans", sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "plans", sa.Column("previous_plan_id", sa.UUID(), nullable=True)
    )
    op.create_foreign_key(
        "fk_plan_previous", "plans", "plans", ["previous_plan_id"], ["id"],
        ondelete="SET NULL",
    )

    op.add_column(
        "plan_generation_jobs",
        sa.Column("cycle_number", sa.Integer(), nullable=False, server_default="1"),
    )
    op.add_column(
        "plan_generation_jobs",
        sa.Column("previous_plan_id", sa.UUID(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("plan_generation_jobs", "previous_plan_id")
    op.drop_column("plan_generation_jobs", "cycle_number")
    op.drop_constraint("fk_plan_previous", "plans", type_="foreignkey")
    op.drop_column("plans", "previous_plan_id")
    op.drop_column("plans", "completed_at")
    op.drop_column("plans", "cycle_number")
    op.drop_index("uq_ach_plan_item_source", table_name="user_achievements")
    op.drop_constraint("fk_user_ach_plan_item", "user_achievements", type_="foreignkey")
    op.drop_constraint("fk_user_ach_plan", "user_achievements", type_="foreignkey")
    op.drop_column("user_achievements", "cycle_number")
    op.drop_column("user_achievements", "plan_item_id")
    op.drop_column("user_achievements", "plan_id")
    op.drop_column("user_achievements", "source")
    sa.Enum(name="achievement_source").drop(op.get_bind(), checkfirst=True)
