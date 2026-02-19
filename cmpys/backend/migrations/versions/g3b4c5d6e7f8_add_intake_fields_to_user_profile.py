"""Add intake fields to user profiles

Revision ID: g3b4c5d6e7f8
Revises: f2a3b4c5d6e7
Create Date: 2026-01-08

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'g3b4c5d6e7f8'
down_revision = 'f2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add intake-derived fields to user_profiles
    op.add_column('user_profiles', sa.Column('weekly_hours', sa.Integer(), nullable=True))
    op.add_column('user_profiles', sa.Column('goals', postgresql.ARRAY(sa.String(500)), nullable=True))
    op.add_column('user_profiles', sa.Column('interests', postgresql.ARRAY(sa.String(200)), nullable=True))
    op.add_column('user_profiles', sa.Column('domains', postgresql.ARRAY(sa.String(100)), nullable=True))
    op.add_column('user_profiles', sa.Column('constraints', postgresql.ARRAY(sa.String(300)), nullable=True))
    op.add_column('user_profiles', sa.Column('learning_preferences', postgresql.ARRAY(sa.String(200)), nullable=True))
    op.add_column('user_profiles', sa.Column('skills', postgresql.JSONB, nullable=True))
    op.add_column('user_profiles', sa.Column('achievements_raw', sa.Text(), nullable=True))
    op.add_column('user_profiles', sa.Column('readiness_by_gap', postgresql.JSONB, nullable=True))


def downgrade() -> None:
    op.drop_column('user_profiles', 'readiness_by_gap')
    op.drop_column('user_profiles', 'achievements_raw')
    op.drop_column('user_profiles', 'skills')
    op.drop_column('user_profiles', 'learning_preferences')
    op.drop_column('user_profiles', 'constraints')
    op.drop_column('user_profiles', 'domains')
    op.drop_column('user_profiles', 'interests')
    op.drop_column('user_profiles', 'goals')
    op.drop_column('user_profiles', 'weekly_hours')
