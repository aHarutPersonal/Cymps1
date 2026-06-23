"""add reusable content resources

Revision ID: n1o2p3q4r5s6
Revises: m9n0p1q2r3s4
Create Date: 2026-05-09 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "n1o2p3q4r5s6"
down_revision: Union[str, None] = "m9n0p1q2r3s4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


content_kind_enum = postgresql.ENUM(
    "public_domain_book",
    "llm_book_summary",
    "video",
    "article",
    "in_app_lesson",
    name="content_resource_kind",
    create_type=False,
)

license_status_enum = postgresql.ENUM(
    "public_domain",
    "licensed",
    "llm_summary",
    "external_link",
    "unknown",
    name="content_resource_license_status",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    content_kind_enum.create(bind, checkfirst=True)
    license_status_enum.create(bind, checkfirst=True)

    op.create_table(
        "content_resources",
        sa.Column("kind", content_kind_enum, nullable=False),
        sa.Column("canonical_key", sa.String(length=320), nullable=False),
        sa.Column("title", sa.String(length=300), nullable=False),
        sa.Column("author_or_creator", sa.String(length=300), nullable=True),
        sa.Column("source_url", sa.String(length=2048), nullable=True),
        sa.Column("thumbnail_url", sa.String(length=2048), nullable=True),
        sa.Column("license_status", license_status_enum, nullable=False),
        sa.Column("content_markdown", sa.Text(), nullable=True),
        sa.Column("summary_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("duration_minutes", sa.Integer(), nullable=True),
        sa.Column("metadata_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("canonical_key"),
    )
    op.create_index("ix_content_resources_canonical_key", "content_resources", ["canonical_key"])
    op.create_index("ix_content_resources_kind", "content_resources", ["kind"])

    op.create_table(
        "user_content_saves",
        sa.Column("user_id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("content_resource_id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("collection", sa.String(length=80), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["content_resource_id"], ["content_resources.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "content_resource_id", name="uq_user_content_save"),
    )
    op.create_index("ix_user_content_saves_user_id", "user_content_saves", ["user_id"])

    op.create_table(
        "user_content_progress",
        sa.Column("user_id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("content_resource_id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("progress_percent", sa.Integer(), nullable=False),
        sa.Column("cursor_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["content_resource_id"], ["content_resources.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "content_resource_id", name="uq_user_content_progress"),
    )
    op.create_index("ix_user_content_progress_user_id", "user_content_progress", ["user_id"])

    op.create_table(
        "user_content_highlights",
        sa.Column("user_id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("content_resource_id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("locator_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("quote_text", sa.Text(), nullable=True),
        sa.Column("note_text", sa.Text(), nullable=True),
        sa.Column("id", sa.UUID(as_uuid=False), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["content_resource_id"], ["content_resources.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_user_content_highlights_user_resource",
        "user_content_highlights",
        ["user_id", "content_resource_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_user_content_highlights_user_resource", table_name="user_content_highlights")
    op.drop_table("user_content_highlights")
    op.drop_index("ix_user_content_progress_user_id", table_name="user_content_progress")
    op.drop_table("user_content_progress")
    op.drop_index("ix_user_content_saves_user_id", table_name="user_content_saves")
    op.drop_table("user_content_saves")
    op.drop_index("ix_content_resources_kind", table_name="content_resources")
    op.drop_index("ix_content_resources_canonical_key", table_name="content_resources")
    op.drop_table("content_resources")
    bind = op.get_bind()
    license_status_enum.drop(bind, checkfirst=True)
    content_kind_enum.drop(bind, checkfirst=True)
