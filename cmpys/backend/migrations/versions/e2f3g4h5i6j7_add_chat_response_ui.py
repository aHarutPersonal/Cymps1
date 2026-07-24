"""add interview response UI and idempotency metadata to chat messages

Revision ID: e2f3g4h5i6j7
Revises: d1e2f3g4h5i6
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "e2f3g4h5i6j7"
down_revision: Union[str, None] = "d1e2f3g4h5i6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "chat_threads",
        sa.Column("interview_claim_key", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "chat_threads",
        sa.Column(
            "interview_claim_token",
            postgresql.UUID(as_uuid=False),
            nullable=True,
        ),
    )
    op.add_column(
        "chat_threads",
        sa.Column("interview_claimed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "chat_messages",
        sa.Column(
            "response_ui_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True
        ),
    )
    op.add_column(
        "chat_messages",
        sa.Column("reply_to_message_id", postgresql.UUID(as_uuid=False), nullable=True),
    )
    op.add_column(
        "chat_messages",
        sa.Column("generation_status", sa.String(length=20), nullable=True),
    )
    op.create_foreign_key(
        "fk_chat_messages_reply_to_message_id",
        "chat_messages",
        "chat_messages",
        ["reply_to_message_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_unique_constraint(
        "uq_chat_messages_reply_to_message_id",
        "chat_messages",
        ["reply_to_message_id"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_chat_messages_reply_to_message_id",
        "chat_messages",
        type_="unique",
    )
    op.drop_constraint(
        "fk_chat_messages_reply_to_message_id",
        "chat_messages",
        type_="foreignkey",
    )
    op.drop_column("chat_messages", "generation_status")
    op.drop_column("chat_messages", "reply_to_message_id")
    op.drop_column("chat_messages", "response_ui_json")
    op.drop_column("chat_threads", "interview_claimed_at")
    op.drop_column("chat_threads", "interview_claim_token")
    op.drop_column("chat_threads", "interview_claim_key")
