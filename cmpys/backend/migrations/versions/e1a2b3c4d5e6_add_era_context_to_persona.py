"""Add era context fields to idol personas

Revision ID: e1a2b3c4d5e6
Revises: a38bc9f11f7b
Create Date: 2026-01-08

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'e1a2b3c4d5e6'
down_revision = 'a38bc9f11f7b'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add era_context column
    op.add_column(
        'idol_personas',
        sa.Column('era_context', sa.String(50), nullable=True, server_default='contemporary')
    )
    
    # Add lexicon_allow column
    op.add_column(
        'idol_personas',
        sa.Column('lexicon_allow', postgresql.ARRAY(sa.String(200)), nullable=True)
    )
    
    # Add lexicon_ban column
    op.add_column(
        'idol_personas',
        sa.Column('lexicon_ban', postgresql.ARRAY(sa.String(200)), nullable=True)
    )
    
    # Add worldview_adapter column (JSONB for flexible mapping)
    op.add_column(
        'idol_personas',
        sa.Column('worldview_adapter', postgresql.JSONB, nullable=True)
    )
    
    # Add default_frameworks column
    op.add_column(
        'idol_personas',
        sa.Column('default_frameworks', postgresql.ARRAY(sa.String(300)), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('idol_personas', 'default_frameworks')
    op.drop_column('idol_personas', 'worldview_adapter')
    op.drop_column('idol_personas', 'lexicon_ban')
    op.drop_column('idol_personas', 'lexicon_allow')
    op.drop_column('idol_personas', 'era_context')
