"""Add plan item details and completion tracking

Revision ID: h4c5d6e7f8g9
Revises: g3b4c5d6e7f8
Create Date: 2026-01-09

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'h4c5d6e7f8g9'
down_revision = 'g3b4c5d6e7f8'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add details_json column to plan_items
    op.add_column(
        'plan_items',
        sa.Column('details_json', postgresql.JSONB, nullable=True)
    )
    
    # Create plan_item_step_completions table
    op.create_table(
        'plan_item_step_completions',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('plan_item_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('step_id', sa.String(100), nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['plan_item_id'], ['plan_items.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_plan_item_step_completions_user_id', 'plan_item_step_completions', ['user_id'])
    op.create_index('ix_plan_item_step_completions_plan_item_id', 'plan_item_step_completions', ['plan_item_id'])
    op.create_index(
        'ix_plan_item_step_completions_unique',
        'plan_item_step_completions',
        ['user_id', 'plan_item_id', 'step_id'],
        unique=True
    )
    
    # Create plan_item_completions table
    op.create_table(
        'plan_item_completions',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('plan_item_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['plan_item_id'], ['plan_items.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_plan_item_completions_user_id', 'plan_item_completions', ['user_id'])
    op.create_index('ix_plan_item_completions_plan_item_id', 'plan_item_completions', ['plan_item_id'])
    op.create_index(
        'ix_plan_item_completions_unique',
        'plan_item_completions',
        ['user_id', 'plan_item_id'],
        unique=True
    )


def downgrade() -> None:
    # Drop plan_item_completions table
    op.drop_index('ix_plan_item_completions_unique', table_name='plan_item_completions')
    op.drop_index('ix_plan_item_completions_plan_item_id', table_name='plan_item_completions')
    op.drop_index('ix_plan_item_completions_user_id', table_name='plan_item_completions')
    op.drop_table('plan_item_completions')
    
    # Drop plan_item_step_completions table
    op.drop_index('ix_plan_item_step_completions_unique', table_name='plan_item_step_completions')
    op.drop_index('ix_plan_item_step_completions_plan_item_id', table_name='plan_item_step_completions')
    op.drop_index('ix_plan_item_step_completions_user_id', table_name='plan_item_step_completions')
    op.drop_table('plan_item_step_completions')
    
    # Drop details_json column from plan_items
    op.drop_column('plan_items', 'details_json')
