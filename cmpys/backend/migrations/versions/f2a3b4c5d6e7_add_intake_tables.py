"""Add intake sessions and answers tables

Revision ID: f2a3b4c5d6e7
Revises: e1a2b3c4d5e6
Create Date: 2026-01-08

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'f2a3b4c5d6e7'
down_revision = 'e1a2b3c4d5e6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create intake_session_status enum
    intake_session_status = postgresql.ENUM(
        'draft', 'in_progress', 'completed',
        name='intake_session_status'
    )
    intake_session_status.create(op.get_bind())
    
    # Create intake_sessions table
    op.create_table(
        'intake_sessions',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('idol_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column(
            'status',
            postgresql.ENUM('draft', 'in_progress', 'completed', name='intake_session_status', create_type=False),
            nullable=False,
            server_default='draft'
        ),
        sa.Column('questions_json', postgresql.JSONB, nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['idol_id'], ['idols.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    
    # Create indexes for intake_sessions
    op.create_index('ix_intake_sessions_user_id', 'intake_sessions', ['user_id'])
    op.create_index('ix_intake_sessions_idol_id', 'intake_sessions', ['idol_id'])
    op.create_index('ix_intake_sessions_user_idol', 'intake_sessions', ['user_id', 'idol_id'])
    op.create_index('ix_intake_sessions_status', 'intake_sessions', ['status'])
    
    # Create intake_answers table
    op.create_table(
        'intake_answers',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('session_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('question_id', sa.String(50), nullable=False),
        sa.Column('answer_json', postgresql.JSONB, nullable=False, server_default='{}'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['session_id'], ['intake_sessions.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    
    # Create indexes for intake_answers
    op.create_index('ix_intake_answers_session_id', 'intake_answers', ['session_id'])
    op.create_index('ix_intake_answers_session_question', 'intake_answers', ['session_id', 'question_id'])


def downgrade() -> None:
    # Drop indexes
    op.drop_index('ix_intake_answers_session_question', table_name='intake_answers')
    op.drop_index('ix_intake_answers_session_id', table_name='intake_answers')
    op.drop_index('ix_intake_sessions_status', table_name='intake_sessions')
    op.drop_index('ix_intake_sessions_user_idol', table_name='intake_sessions')
    op.drop_index('ix_intake_sessions_idol_id', table_name='intake_sessions')
    op.drop_index('ix_intake_sessions_user_id', table_name='intake_sessions')
    
    # Drop tables
    op.drop_table('intake_answers')
    op.drop_table('intake_sessions')
    
    # Drop enum
    intake_session_status = postgresql.ENUM(
        'draft', 'in_progress', 'completed',
        name='intake_session_status'
    )
    intake_session_status.drop(op.get_bind())
