from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin

if TYPE_CHECKING:
    from app.models.idea_card import IdeaCard
    from app.models.user import User


class StashedIdea(Base, UUIDMixin, TimestampMixin):
    """
    Many-to-Many join: users ↔ idea_cards (stash / bookmark).

    A user can stash any unlocked IdeaCard into their personal library.
    The unique constraint prevents duplicate stashes for the same card.
    """

    __tablename__ = "stashed_ideas"
    __table_args__ = (
        UniqueConstraint("user_id", "idea_card_id", name="uq_user_idea_card"),
    )

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    idea_card_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idea_cards.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Relationships
    user: Mapped["User"] = relationship(
        "User", back_populates="stashed_ideas",
    )
    idea_card: Mapped["IdeaCard"] = relationship("IdeaCard")
