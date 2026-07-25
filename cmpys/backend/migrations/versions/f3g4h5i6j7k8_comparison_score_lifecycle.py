"""add durable comparison score generation lifecycle

Revision ID: f3g4h5i6j7k8
Revises: e2f3g4h5i6j7
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "f3g4h5i6j7k8"
down_revision: Union[str, None] = "e2f3g4h5i6j7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "intake_sessions",
        sa.Column(
            "comparison_scores_status",
            sa.String(length=24),
            nullable=False,
            server_default="not_started",
        ),
    )
    op.add_column(
        "intake_sessions",
        sa.Column(
            "comparison_scores_attempts",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "intake_sessions",
        sa.Column("comparison_scores_error", sa.Text(), nullable=True),
    )
    op.add_column(
        "intake_sessions",
        sa.Column(
            "comparison_scores_last_attempt_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.add_column(
        "intake_sessions",
        sa.Column(
            "comparison_scores_next_retry_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )

    # Current honest scores are ready.  Completed verdicts without a current
    # score are queued so the first authenticated read publishes a backfill.
    op.execute(
        """
        UPDATE intake_sessions
        SET comparison_scores_status = CASE
            WHEN comparison_scores_json->>'version' = '2'
             AND comparison_scores_json->>'methodology' = 'like_for_like_evidence'
                THEN 'ready'
            WHEN comparison_output IS NOT NULL THEN 'queued'
            ELSE 'not_started'
        END
        """
    )


def downgrade() -> None:
    op.drop_column("intake_sessions", "comparison_scores_next_retry_at")
    op.drop_column("intake_sessions", "comparison_scores_last_attempt_at")
    op.drop_column("intake_sessions", "comparison_scores_error")
    op.drop_column("intake_sessions", "comparison_scores_attempts")
    op.drop_column("intake_sessions", "comparison_scores_status")
