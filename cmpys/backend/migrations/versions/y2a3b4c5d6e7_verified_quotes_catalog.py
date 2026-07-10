"""add sourced quote catalog and feed provenance

Revision ID: y2a3b4c5d6e7
Revises: x1z2a3b4c5d6
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "y2a3b4c5d6e7"
down_revision: Union[str, None] = "x1z2a3b4c5d6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TYPE ingest_kind ADD VALUE IF NOT EXISTS 'quote'")
    quote_type = postgresql.ENUM(
        "sourced",
        "attributed",
        "paraphrase",
        name="quote_type",
        create_type=False,
    )
    quote_type.create(op.get_bind(), checkfirst=True)
    catalog_status = postgresql.ENUM(
        "pending", "published", "flagged", name="catalog_status", create_type=False
    )
    op.create_table(
        "verified_quotes",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "idol_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("idols.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column("speaker", sa.String(255), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("normalized_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("quote_type", quote_type, nullable=False),
        sa.Column("language", sa.String(12), nullable=False, server_default="en"),
        sa.Column("category", sa.String(50), nullable=True),
        sa.Column("context", sa.Text(), nullable=True),
        sa.Column("source_title", sa.String(500), nullable=True),
        sa.Column("source_url", sa.String(2048), nullable=False),
        sa.Column("source_reference", sa.Text(), nullable=True),
        sa.Column("source_provider", sa.String(50), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False, server_default="0"),
        sa.Column("evidence_json", postgresql.JSONB(), nullable=True),
        sa.Column("status", catalog_status, nullable=False, server_default="pending"),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index(
        "ix_verified_quotes_idol_status", "verified_quotes", ["idol_id", "status"]
    )
    op.create_index("ix_verified_quotes_category", "verified_quotes", ["category"])
    op.create_index("ix_verified_quotes_status", "verified_quotes", ["status"])
    op.add_column(
        "feed_posts",
        sa.Column(
            "quote_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("verified_quotes.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.create_index("uq_feed_posts_quote_id", "feed_posts", ["quote_id"], unique=True)


def downgrade() -> None:
    op.drop_index("uq_feed_posts_quote_id", table_name="feed_posts")
    op.drop_column("feed_posts", "quote_id")
    op.drop_index("ix_verified_quotes_status", table_name="verified_quotes")
    op.drop_index("ix_verified_quotes_category", table_name="verified_quotes")
    op.drop_index("ix_verified_quotes_idol_status", table_name="verified_quotes")
    op.drop_table("verified_quotes")
    postgresql.ENUM(name="quote_type").drop(op.get_bind(), checkfirst=True)
    # PostgreSQL enum values cannot be removed safely in a downgrade. Keeping
    # ingest_kind='quote' is harmless after the table/worker rollback.
