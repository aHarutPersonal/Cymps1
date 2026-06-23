"""catalog foundation

Revision ID: 0528e5d2fba2
Revises: p3q4r5s6t7u8
Create Date: 2026-06-23 16:01:13.070919

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '0528e5d2fba2'
down_revision: Union[str, None] = 'p3q4r5s6t7u8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


CATALOG_STATUS = postgresql.ENUM(
    "pending", "published", "flagged",
    name="catalog_status",
    create_type=False,
)
INGEST_KIND = postgresql.ENUM(
    "idol", "book",
    name="ingest_kind",
    create_type=False,
)
INGEST_STATE = postgresql.ENUM(
    "queued", "running", "done", "failed", "flagged",
    name="ingest_state",
    create_type=False,
)


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    bind = op.get_bind()
    CATALOG_STATUS.create(bind, checkfirst=True)
    INGEST_KIND.create(bind, checkfirst=True)
    INGEST_STATE.create(bind, checkfirst=True)

    # idols
    op.add_column("idols", sa.Column("status", CATALOG_STATUS, nullable=False, server_default="pending"))
    op.add_column("idols", sa.Column("embedding", Vector(1024), nullable=True))
    op.add_column("idols", sa.Column("quality_score", sa.Float(), nullable=True))
    op.add_column("idols", sa.Column("published_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index("ix_idols_status", "idols", ["status"])

    # content_resources
    op.add_column("content_resources", sa.Column("status", CATALOG_STATUS, nullable=False, server_default="pending"))
    op.add_column("content_resources", sa.Column("embedding", Vector(1024), nullable=True))
    op.add_column("content_resources", sa.Column("is_public_domain", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("content_resources", sa.Column("source_provider", sa.String(50), nullable=True))
    op.add_column("content_resources", sa.Column("source_external_id", sa.String(255), nullable=True))
    op.add_column("content_resources", sa.Column("read_minutes", sa.Integer(), nullable=True))
    op.create_index("ix_content_resources_status", "content_resources", ["status"])

    # ingest_jobs
    op.create_table(
        "ingest_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column("kind", INGEST_KIND, nullable=False),
        sa.Column("source", sa.String(50), nullable=False),
        sa.Column("external_id", sa.String(255), nullable=False),
        sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("state", INGEST_STATE, nullable=False, server_default="queued"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("kind", "source", "external_id", name="uq_ingest_identity"),
    )
    op.create_index("ix_ingest_jobs_state_priority", "ingest_jobs", ["state", "priority"])

    # HNSW vector indexes (cosine) — only created when column has data, but safe to create empty
    op.execute("CREATE INDEX ix_idols_embedding ON idols USING hnsw (embedding vector_cosine_ops) WHERE embedding IS NOT NULL")
    op.execute("CREATE INDEX ix_content_resources_embedding ON content_resources USING hnsw (embedding vector_cosine_ops) WHERE embedding IS NOT NULL")

    # review_queue view
    op.execute("""
        CREATE VIEW review_queue AS
        SELECT 'idol' AS kind, id, name AS title, status, quality_score, created_at
        FROM idols WHERE status = 'flagged'
        UNION ALL
        SELECT 'book' AS kind, id, title, status, NULL::double precision AS quality_score, created_at
        FROM content_resources WHERE status = 'flagged'
    """)

    # Backfill existing rows to published so nothing disappears
    op.execute("UPDATE idols SET status = 'published', published_at = now() WHERE status = 'pending'")
    op.execute("UPDATE content_resources SET status = 'published' WHERE status = 'pending'")


def downgrade() -> None:
    op.execute("DROP VIEW IF EXISTS review_queue")
    op.execute("DROP INDEX IF EXISTS ix_content_resources_embedding")
    op.execute("DROP INDEX IF EXISTS ix_idols_embedding")
    op.drop_index("ix_ingest_jobs_state_priority", table_name="ingest_jobs")
    op.drop_table("ingest_jobs")
    op.drop_index("ix_content_resources_status", table_name="content_resources")
    for col in ("read_minutes", "source_external_id", "source_provider", "is_public_domain", "embedding", "status"):
        op.drop_column("content_resources", col)
    op.drop_index("ix_idols_status", table_name="idols")
    for col in ("published_at", "quality_score", "embedding", "status"):
        op.drop_column("idols", col)
    bind = op.get_bind()
    INGEST_STATE.drop(bind, checkfirst=True)
    INGEST_KIND.drop(bind, checkfirst=True)
    CATALOG_STATUS.drop(bind, checkfirst=True)
