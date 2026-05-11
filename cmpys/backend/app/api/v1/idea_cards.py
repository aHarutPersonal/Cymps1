"""
IdeaCards API — Deepstash-style atomic insights tied to Idols.

Endpoints:
  GET  /idols/{idol_id}/syllabus         — Category outline for an idol's cards
  GET  /idols/{idol_id}/daily-ideas      — Paginated IdeaCards
  POST /stash/{idea_card_id}             — Toggle stash on an IdeaCard
  GET  /stash                            — List user's stashed IdeaCards
"""
import json as json_lib
import logging
from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import CurrentUser, get_current_user
from app.core.config import settings
from app.core.db import get_db
from app.models.idea_card import IdeaCard
from app.models.idol import Idol
from app.models.idol_persona import IdolPersona
from app.models.plan import Plan
from app.models.stashed_idea import StashedIdea
from app.models.user import User
from app.schemas.idea_card import (
    IdeaCardListResponse,
    IdeaCardResponse,
    StashActionResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["idea-cards"])


# ─── Response helpers ────────────────────────────────────────────────


def _card_to_response(card: IdeaCard, stashed_ids: set[str]) -> IdeaCardResponse:
    return IdeaCardResponse(
        id=card.id,
        idol_id=card.idol_id,
        category_tag=card.category_tag,
        content_markdown=card.content_markdown,
        is_locked=card.is_locked,
        sort_order=card.sort_order,
        created_at=card.created_at,
        is_stashed=card.id in stashed_ids,
    )


# ─── GET /idols/{idol_id}/syllabus ───────────────────────────────────


class SyllabusCategoryResponse:
    """Dict-based response for syllabus — not a Pydantic model to stay lightweight."""

    pass


@router.get("/idols/{idol_id}/syllabus")
async def get_idol_syllabus(
    idol_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: CurrentUser,
):
    """
    Returns a structured category breakdown for an idol's IdeaCards.

    Example response:
    {
      "idol_id": "...",
      "idol_name": "Marcus Aurelius",
      "categories": [
        {"tag": "mindset", "count": 8, "unlocked": 5, "locked": 3},
        {"tag": "discipline", "count": 6, "unlocked": 6, "locked": 0},
      ],
      "total_cards": 14,
      "total_stashed": 3
    }
    """
    # Verify idol exists
    idol = await db.get(Idol, idol_id)
    if not idol:
        raise HTTPException(status_code=404, detail="Idol not found")

    # Category aggregation
    stmt = (
        select(
            IdeaCard.category_tag,
            func.count(IdeaCard.id).label("count"),
            func.sum(func.cast(IdeaCard.is_locked == False, Integer)).label(  # noqa: E712
                "unlocked"
            ),
            func.sum(func.cast(IdeaCard.is_locked == True, Integer)).label(  # noqa: E712
                "locked"
            ),
        )
        .where(IdeaCard.idol_id == idol_id)
        .group_by(IdeaCard.category_tag)
        .order_by(IdeaCard.category_tag)
    )
    result = await db.execute(stmt)
    rows = result.all()

    # Count stashed
    stash_count_stmt = (
        select(func.count(StashedIdea.id))
        .join(IdeaCard, StashedIdea.idea_card_id == IdeaCard.id)
        .where(
            StashedIdea.user_id == current_user.id,
            IdeaCard.idol_id == idol_id,
        )
    )
    stash_result = await db.execute(stash_count_stmt)
    total_stashed = stash_result.scalar() or 0

    categories = []
    total_cards = 0
    for row in rows:
        cat_count = row.count or 0
        total_cards += cat_count
        categories.append(
            {
                "tag": row.category_tag,
                "count": cat_count,
                "unlocked": row.unlocked or 0,
                "locked": row.locked or 0,
            }
        )

    return {
        "idol_id": idol_id,
        "idol_name": idol.name,
        "categories": categories,
        "total_cards": total_cards,
        "total_stashed": total_stashed,
    }


# Import Integer for cast
from sqlalchemy import Integer  # noqa: E402


# ─── GET /idols/{idol_id}/daily-ideas ─────────────────────────────────


@router.get("/idols/{idol_id}/daily-ideas", response_model=IdeaCardListResponse)
async def get_daily_ideas(
    idol_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: CurrentUser,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=10, ge=1, le=50),
    category: str | None = Query(default=None, description="Filter by category_tag"),
    refresh: bool = Query(default=False, description="Force-generate new IdeaCards"),
):
    """
    Paginated IdeaCards for an idol.

    If the idol has fewer than `page_size` cards (or refresh=true),
    triggers LLM generation to fill the pool.
    """
    # Verify idol exists
    idol = await db.get(Idol, idol_id)
    if not idol:
        raise HTTPException(status_code=404, detail="Idol not found")

    # Count existing cards
    count_stmt = select(func.count(IdeaCard.id)).where(IdeaCard.idol_id == idol_id)
    count_result = await db.execute(count_stmt)
    existing_count = count_result.scalar() or 0

    # Generate if pool is empty or forced refresh
    if existing_count < page_size or refresh:
        await _generate_idea_cards(
            idol=idol,
            user=current_user,
            db=db,
            count=max(12, page_size),
        )

    # Build query
    query = (
        select(IdeaCard)
        .where(IdeaCard.idol_id == idol_id)
        .order_by(IdeaCard.sort_order, IdeaCard.created_at.desc())
    )
    if category:
        query = query.where(IdeaCard.category_tag == category)

    # Total count (after filter)
    total_stmt = select(func.count()).select_from(query.subquery())
    total_result = await db.execute(total_stmt)
    total = total_result.scalar() or 0

    # Paginate
    offset = (page - 1) * page_size
    page_stmt = query.offset(offset).limit(page_size)
    result = await db.execute(page_stmt)
    cards = list(result.scalars().all())

    # Get user's stash set
    stashed_ids = await _get_stashed_ids(current_user.id, db)

    return IdeaCardListResponse(
        idea_cards=[_card_to_response(c, stashed_ids) for c in cards],
        total=total,
        page=page,
        page_size=page_size,
    )


# ─── POST /stash/{idea_card_id} ──────────────────────────────────────


@router.post("/stash/{idea_card_id}", response_model=StashActionResponse)
async def toggle_stash(
    idea_card_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: CurrentUser,
):
    """
    Toggle stash on an IdeaCard. Idempotent.

    - If not stashed → stash it.
    - If already stashed → un-stash it.
    """
    # Verify card exists
    card = await db.get(IdeaCard, idea_card_id)
    if not card:
        raise HTTPException(status_code=404, detail="IdeaCard not found")

    # Check existing stash
    existing_stmt = select(StashedIdea).where(
        StashedIdea.user_id == current_user.id,
        StashedIdea.idea_card_id == idea_card_id,
    )
    result = await db.execute(existing_stmt)
    existing = result.scalar_one_or_none()

    if existing:
        # Un-stash
        await db.delete(existing)
        await db.commit()
        return StashActionResponse(
            success=True,
            action="unstashed",
            idea_card_id=idea_card_id,
        )
    else:
        # Stash
        stash = StashedIdea(
            id=str(uuid4()),
            user_id=current_user.id,
            idea_card_id=idea_card_id,
        )
        db.add(stash)
        await db.commit()
        return StashActionResponse(
            success=True,
            action="stashed",
            idea_card_id=idea_card_id,
        )


# ─── GET /stash ───────────────────────────────────────────────────────


@router.get("/stash", response_model=IdeaCardListResponse)
async def get_stash(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: CurrentUser,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=50),
):
    """
    List the authenticated user's stashed IdeaCards (for Library tab).
    """
    base = (
        select(IdeaCard)
        .join(StashedIdea, StashedIdea.idea_card_id == IdeaCard.id)
        .where(StashedIdea.user_id == current_user.id)
        .order_by(StashedIdea.created_at.desc())
    )

    # Total
    total_stmt = select(func.count()).select_from(base.subquery())
    total_result = await db.execute(total_stmt)
    total = total_result.scalar() or 0

    # Paginate
    offset = (page - 1) * page_size
    page_stmt = base.offset(offset).limit(page_size)
    result = await db.execute(page_stmt)
    cards = list(result.scalars().all())

    # All of these are stashed by definition
    stashed_ids = {c.id for c in cards}

    return IdeaCardListResponse(
        idea_cards=[_card_to_response(c, stashed_ids) for c in cards],
        total=total,
        page=page,
        page_size=page_size,
    )


# ─── Private: LLM Generation ─────────────────────────────────────────


async def _get_stashed_ids(user_id: str, db: AsyncSession) -> set[str]:
    """Get set of idea_card_ids stashed by this user."""
    stmt = select(StashedIdea.idea_card_id).where(StashedIdea.user_id == user_id)
    result = await db.execute(stmt)
    return {row[0] for row in result.all()}


async def _generate_idea_cards(
    idol: Idol,
    user: User,
    db: AsyncSession,
    count: int = 12,
) -> list[IdeaCard]:
    """
    Generate atomized IdeaCards via LLM and persist to DB.

    Uses the `idea_cards_generate.txt` prompt template which instructs
    the LLM to return a strict JSON array of card objects.
    """
    try:
        from google import genai
        from google.genai import types

        from app.services.llm.prompt_loader import load_and_render

        # Build user context
        await db.refresh(user, ["profile"])
        profile = user.profile

        user_profile_data = {}
        if profile:
            user_profile_data = {
                "goals": profile.goals or [],
                "interests": profile.interests or [],
                "focus_areas": profile.focus_areas or [],
            }

        # Load persona for tone matching
        persona_stmt = select(IdolPersona).where(IdolPersona.idol_id == idol.id)
        persona_result = await db.execute(persona_stmt)
        persona = persona_result.scalar_one_or_none()

        persona_context = ""
        if persona:
            persona_context = (
                f"Voice style: {persona.voice_style}\n"
                f"Principles: {', '.join(persona.principles or [])}\n"
                f"Signature phrases: {', '.join(persona.signature_phrases or [])}\n"
                f"Era context: {persona.era_context or 'contemporary'}\n"
            )

        prompt = load_and_render(
            "idea_cards_generate.txt",
            {
                "count": str(count),
                "idol_name": idol.name,
                "idol_domain": idol.domain,
                "persona_context": persona_context,
                "user_profile_json": json_lib.dumps(user_profile_data),
            },
        )

        client = genai.Client(api_key=settings.gemini_api_key)
        response = await client.aio.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0.9,
                response_mime_type="application/json",
            ),
        )

        if not response.text:
            logger.warning("[IDEA_CARDS] LLM returned empty response")
            return []

        text = response.text.strip()
        # Strip markdown code fences if present
        if text.startswith("```json"):
            text = text[7:]
        if text.startswith("```"):
            text = text[3:]
        if text.endswith("```"):
            text = text[:-3]

        parsed = json_lib.loads(text.strip())

        # Handle both {"idea_cards": [...]} and bare [...] formats
        if isinstance(parsed, dict) and "idea_cards" in parsed:
            items = parsed["idea_cards"]
        elif isinstance(parsed, list):
            items = parsed
        else:
            logger.warning(f"[IDEA_CARDS] Unexpected JSON shape: {type(parsed)}")
            return []

        saved: list[IdeaCard] = []
        for idx, item in enumerate(items):
            content = item.get("content_markdown", item.get("content", ""))
            category = item.get("category_tag", item.get("category", "mindset"))

            if not content:
                continue

            card = IdeaCard(
                id=str(uuid4()),
                idol_id=idol.id,
                category_tag=category.lower().strip(),
                content_markdown=content.strip(),
                is_locked=item.get("is_locked", False),
                sort_order=idx,
            )
            db.add(card)
            saved.append(card)

        await db.flush()
        logger.info(f"[IDEA_CARDS] Generated {len(saved)} cards for {idol.name}")
        return saved

    except Exception as e:
        logger.exception(f"[IDEA_CARDS] Generation failed: {e}")
        return []
