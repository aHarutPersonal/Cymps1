"""add plan item content resource links

Revision ID: p3q4r5s6t7u8
Revises: o2p3q4r5s6t7
Create Date: 2026-05-10 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "p3q4r5s6t7u8"
down_revision: Union[str, None] = "o2p3q4r5s6t7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "plan_item_content_resources",
        sa.Column("plan_item_id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("content_resource_id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("material_index", sa.Integer(), nullable=False),
        sa.Column("material_type", sa.String(length=80), nullable=True),
        sa.Column("title", sa.String(length=300), nullable=True),
        sa.Column("canonical_key", sa.String(length=320), nullable=True),
        sa.Column("metadata_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["content_resource_id"], ["content_resources.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["plan_item_id"], ["plan_items.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "plan_item_id",
            "content_resource_id",
            "material_index",
            name="uq_plan_item_content_resource_material",
        ),
    )
    op.create_index(
        "ix_plan_item_content_resources_plan_item",
        "plan_item_content_resources",
        ["plan_item_id"],
    )
    op.create_index(
        "ix_plan_item_content_resources_resource",
        "plan_item_content_resources",
        ["content_resource_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_plan_item_content_resources_resource", table_name="plan_item_content_resources")
    op.drop_index("ix_plan_item_content_resources_plan_item", table_name="plan_item_content_resources")
    op.drop_table("plan_item_content_resources")
