"""intake_sessions.user_goal — the onboarding goal, previously discarded

The client collects an explicit goal in onboarding but used to fold it into
financial_status lossily. Store it verbatim so idol suggestion, the interview,
and comparison/blueprint prompts can use it.

Additive (no data change), safe and reversible.

Revision ID: w0y1z2a3b4c5
Revises: v9x0y1z2a3b4
Create Date: 2026-07-05 00:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "w0y1z2a3b4c5"
down_revision: Union[str, None] = "v9x0y1z2a3b4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "intake_sessions",
        sa.Column("user_goal", sa.String(200), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("intake_sessions", "user_goal")
