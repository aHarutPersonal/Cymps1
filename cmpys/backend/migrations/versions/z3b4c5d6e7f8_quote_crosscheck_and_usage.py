"""add quote cross-check state and llm usage telemetry

Revision ID: z3b4c5d6e7f8
Revises: y2a3b4c5d6e7
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "z3b4c5d6e7f8"
down_revision: Union[str, None] = "y2a3b4c5d6e7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "ALTER TYPE ingest_kind ADD VALUE IF NOT EXISTS 'quote_verification'"
    )
    verification_state = postgresql.ENUM(
        "source_backed",
        "verified",
        "inconclusive",
        "rejected",
        name="quote_verification_state",
        create_type=False,
    )
    postgresql.ENUM(
        "source_backed",
        "verified",
        "inconclusive",
        "rejected",
        name="quote_verification_state",
    ).create(op.get_bind(), checkfirst=True)

    op.add_column(
        "verified_quotes",
        sa.Column(
            "verification_state",
            verification_state,
            nullable=False,
            server_default="source_backed",
        ),
    )
    op.add_column(
        "verified_quotes",
        sa.Column("verification_confidence", sa.Float(), nullable=True),
    )
    op.add_column(
        "verified_quotes",
        sa.Column("verification_model", sa.String(100), nullable=True),
    )
    op.add_column(
        "verified_quotes",
        sa.Column("verification_json", postgresql.JSONB(), nullable=True),
    )
    op.add_column(
        "verified_quotes",
        sa.Column("verified_source_title", sa.String(500), nullable=True),
    )
    op.add_column(
        "verified_quotes",
        sa.Column("verified_source_url", sa.String(2048), nullable=True),
    )
    op.add_column(
        "verified_quotes",
        sa.Column(
            "verification_attempted_at", sa.DateTime(timezone=True), nullable=True
        ),
    )
    op.add_column(
        "verified_quotes",
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_verified_quotes_verification_state",
        "verified_quotes",
        ["verification_state"],
    )

    op.create_table(
        "llm_usage_events",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column("operation", sa.String(80), nullable=False),
        sa.Column("provider", sa.String(30), nullable=False),
        sa.Column("model", sa.String(100), nullable=False),
        sa.Column("prompt_tokens", sa.Integer(), nullable=True),
        sa.Column("completion_tokens", sa.Integer(), nullable=True),
        sa.Column("total_tokens", sa.Integer(), nullable=True),
        sa.Column("duration_ms", sa.Float(), nullable=True),
        sa.Column("grounded", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("search_queries", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("success", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("error_code", sa.String(100), nullable=True),
        sa.Column("result_status", sa.String(50), nullable=True),
        sa.Column("quality_score", sa.Float(), nullable=True),
        sa.Column("metadata_json", postgresql.JSONB(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_llm_usage_events_operation_created",
        "llm_usage_events",
        ["operation", "created_at"],
    )
    op.create_index(
        "ix_llm_usage_events_model_created",
        "llm_usage_events",
        ["model", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_llm_usage_events_model_created", table_name="llm_usage_events")
    op.drop_index("ix_llm_usage_events_operation_created", table_name="llm_usage_events")
    op.drop_table("llm_usage_events")
    op.drop_index("ix_verified_quotes_verification_state", table_name="verified_quotes")
    for column in (
        "verified_at",
        "verification_attempted_at",
        "verified_source_url",
        "verified_source_title",
        "verification_json",
        "verification_model",
        "verification_confidence",
        "verification_state",
    ):
        op.drop_column("verified_quotes", column)
    postgresql.ENUM(name="quote_verification_state").drop(
        op.get_bind(), checkfirst=True
    )
    # PostgreSQL enum values are intentionally retained on downgrade.
