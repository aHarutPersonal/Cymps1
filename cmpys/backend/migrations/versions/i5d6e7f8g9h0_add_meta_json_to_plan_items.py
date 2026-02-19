"""Add meta_json to plan_items

Revision ID: i5d6e7f8g9h0
Revises: h4c5d6e7f8g9
Create Date: 2026-01-09

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'i5d6e7f8g9h0'
down_revision = 'h4c5d6e7f8g9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add meta_json column to plan_items
    op.add_column(
        'plan_items',
        sa.Column('meta_json', postgresql.JSONB, nullable=True)
    )


def downgrade() -> None:
    # Drop meta_json column from plan_items
    op.drop_column('plan_items', 'meta_json')
