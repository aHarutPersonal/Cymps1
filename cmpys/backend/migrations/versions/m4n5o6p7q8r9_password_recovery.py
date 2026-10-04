"""Single-use recovery digests and revocable authentication versions."""
from alembic import op
import sqlalchemy as sa

revision = 'm4n5o6p7q8r9'
down_revision = 'l3m4n5o6p7q8'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('users', sa.Column('auth_version', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('users', sa.Column('reset_token_hash', sa.String(64), nullable=True))
    op.add_column('users', sa.Column('reset_expires_at', sa.DateTime(timezone=True), nullable=True))
    op.create_unique_constraint('uq_users_reset_token_hash', 'users', ['reset_token_hash'])


def downgrade():
    raise RuntimeError('Authentication revocations must not be discarded by downgrade')
