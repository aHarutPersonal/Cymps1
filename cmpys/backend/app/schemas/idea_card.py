from datetime import datetime

from pydantic import BaseModel, Field


class IdeaCardResponse(BaseModel):
    """Single IdeaCard — strict snake_case output."""

    id: str
    idol_id: str
    category_tag: str
    content_markdown: str
    is_locked: bool
    sort_order: int
    created_at: datetime
    is_stashed: bool = Field(
        default=False,
        description="Whether the authenticated user has stashed this card",
    )

    model_config = {"from_attributes": True}


class IdeaCardListResponse(BaseModel):
    """Paginated list of IdeaCards."""

    idea_cards: list[IdeaCardResponse]
    total: int
    page: int
    page_size: int


class StashedIdeaResponse(BaseModel):
    """Stash confirmation / listing item."""

    id: str
    user_id: str
    idea_card_id: str
    stashed_at: datetime = Field(
        description="Alias for created_at — when the card was stashed",
    )
    idea_card: IdeaCardResponse | None = None

    model_config = {"from_attributes": True}


class StashActionResponse(BaseModel):
    """Response after stash/unstash action."""

    success: bool
    action: str = Field(description="'stashed' or 'unstashed'")
    idea_card_id: str
