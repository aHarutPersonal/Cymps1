"""Keep expensive planning stages across interrupted onboarding retries."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
revision = 'l3m4n5o6p7q8'
down_revision = 'k2l3m4n5o6p7'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('plan_generation_jobs', sa.Column('generation_checkpoint_json', postgresql.JSONB(), nullable=True))

def downgrade():
    if op.get_bind().execute(sa.text("SELECT EXISTS (SELECT 1 FROM plan_generation_jobs WHERE generation_checkpoint_json IS NOT NULL)")).scalar():
        raise RuntimeError('Cannot discard saved planning work during downgrade')
    op.drop_column('plan_generation_jobs', 'generation_checkpoint_json')
