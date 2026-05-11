"""Add idea_cards and stashed_ideas tables.

Revision ID: l8g9h0i1j2k3
Revises: k7f8g9h0i1j2
Create Date: 2026-04-18
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "l8g9h0i1j2k3"
down_revision = "k7f8g9h0i1j2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "idea_cards",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "idol_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("idols.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("category_tag", sa.String(64), nullable=False),
        sa.Column("content_markdown", sa.Text, nullable=False),
        sa.Column("is_locked", sa.Boolean, server_default="false", nullable=False),
        sa.Column("sort_order", sa.Integer, server_default="0", nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_idea_cards_idol_id", "idea_cards", ["idol_id"])
    op.create_index("ix_idea_cards_category_tag", "idea_cards", ["category_tag"])

    op.create_table(
        "stashed_ideas",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "idea_card_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("idea_cards.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("user_id", "idea_card_id", name="uq_user_idea_card"),
    )
    op.create_index("ix_stashed_ideas_user_id", "stashed_ideas", ["user_id"])
    op.create_index(
        "ix_stashed_ideas_idea_card_id", "stashed_ideas", ["idea_card_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_stashed_ideas_idea_card_id", table_name="stashed_ideas")
    op.drop_index("ix_stashed_ideas_user_id", table_name="stashed_ideas")
    op.drop_table("stashed_ideas")
    op.drop_index("ix_idea_cards_category_tag", table_name="idea_cards")
    op.drop_index("ix_idea_cards_idol_id", table_name="idea_cards")
    op.drop_table("idea_cards")
