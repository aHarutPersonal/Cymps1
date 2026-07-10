"""
Discover Feed API — AI-generated content persisted to DB with social features.

Flow:
1. GET /feed — Returns mix of existing DB posts + fresh AI-generated posts.
   New AI items are auto-saved to DB before returning.
2. POST /feed/{id}/like — Toggle like on a post
3. GET /feed/{id}/comments — List comments
4. POST /feed/{id}/comments — Add a comment
"""
import asyncio
import json as json_lib
import logging
import random
from datetime import datetime, timezone
from typing import Annotated, Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.config import settings
from app.core.db import get_db
from app.models.feed_comment import FeedComment
from app.models.feed_like import FeedLike
from app.models.feed_post import FeedPost
from app.models.idol import CatalogStatus
from app.models.llm_usage_event import LLMUsageEvent
from app.models.plan import Plan
from app.models.user import User
from app.models.verified_quote import QuoteType, QuoteVerificationState, VerifiedQuote
from app.services.llm.telemetry import record_llm_response
from app.services.llm.prompt_loader import load_and_render

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/feed", tags=["feed"])


# ─── Response Models ───────────────────────────────────────────────

class FeedItemResponse(BaseModel):
    id: str
    type: str        # "quote" | "video"
    title: str
    content: str | None = None
    category: str | None = None
    url: str | None = None
    source: str | None = None
    reason: str | None = None
    like_count: int = 0
    comment_count: int = 0
    is_liked: bool = False
    speaker: str | None = None
    is_sourced: bool = False
    is_verified: bool = False
    verification_level: str | None = None
    quote_type: str | None = None
    source_url: str | None = None
    source_title: str | None = None
    source_reference: str | None = None


class FeedResponse(BaseModel):
    items: list[FeedItemResponse]
    total: int
    page: int
    page_size: int
    has_more: bool


class LLMOperationUsageResponse(BaseModel):
    operation: str
    model: str
    calls: int
    successful_calls: int
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    estimated_cost_usd: float
    average_duration_ms: float
    average_quality_score: float | None = None


class FeedQualityStatsResponse(BaseModel):
    quote_counts: dict[str, int]
    published_quotes: int
    verification_calls_today: int
    prompt_tokens_today: int
    completion_tokens_today: int
    total_tokens_today: int
    search_queries_today: int
    average_duration_ms_today: float
    daily_call_limit: int
    batch_size: int
    max_quotes_checked_per_day: int
    llm_usage_by_operation_today: list[LLMOperationUsageResponse]
    routing_decisions_today: dict[str, int]
    estimated_cost_usd_today: float
    background_estimated_cost_usd_today: float
    background_reserved_cost_usd: float
    background_daily_budget_usd: float
    background_budget_remaining_usd: float
    background_budget_used_percent: float
    background_budget_state: str
    pricing_version: str
    search_overage_included: bool


class CommentResponse(BaseModel):
    id: str
    user_id: str
    user_name: str | None = None
    text: str
    created_at: datetime


class CommentRequest(BaseModel):
    text: str


# ─── Helpers ───────────────────────────────────────────────────────

async def _materialize_verified_quotes(
    db: AsyncSession,
    *,
    limit: int = 20,
) -> list[FeedPost]:
    """Turn published catalog quotes into reusable feed posts without an LLM."""
    if limit <= 0:
        return []

    result = await db.execute(
        select(VerifiedQuote)
        .outerjoin(FeedPost, FeedPost.quote_id == VerifiedQuote.id)
        .where(
            VerifiedQuote.status == CatalogStatus.PUBLISHED,
            VerifiedQuote.quote_type == QuoteType.SOURCED,
            FeedPost.id.is_(None),
        )
        .order_by(
            (VerifiedQuote.verification_state == QuoteVerificationState.VERIFIED).desc(),
            VerifiedQuote.confidence.desc(),
            VerifiedQuote.created_at.asc(),
        )
        .limit(limit)
    )
    quotes = list(result.scalars().all())
    if not quotes:
        return []

    proposed = [
        (
            quote,
            f"{quote.speaker} — {quote.category or 'Mindset'}",
        )
        for quote in quotes
    ]
    hashes = [FeedPost.compute_hash(title, quote.text) for quote, title in proposed]
    existing_hashes = set(
        (
            await db.execute(
                select(FeedPost.content_hash).where(FeedPost.content_hash.in_(hashes))
            )
        ).scalars()
    )

    posts: list[FeedPost] = []
    for (quote, title), content_hash in zip(proposed, hashes):
        if content_hash in existing_hashes:
            continue
        post = FeedPost(
            id=str(uuid4()),
            type="quote",
            title=title[:255],
            content=quote.text,
            category=quote.category,
            source=(quote.source_reference or quote.source_title or "Wikiquote")[:255],
            url=quote.source_url[:1024],
            content_hash=content_hash,
            generated_by_user_id=None,
            quote_id=quote.id,
            quote=quote,
        )
        db.add(post)
        posts.append(post)
        existing_hashes.add(content_hash)

    await db.flush()
    return posts


async def _get_user_context(user: User, db: AsyncSession) -> dict:
    """Build user context for LLM prompts."""
    # get_current_user already selectinloads the profile on request paths;
    # only hit the DB again when it's genuinely unloaded (background refill).
    from sqlalchemy import inspect as sa_inspect
    if "profile" in sa_inspect(user).unloaded:
        await db.refresh(user, ["profile"])
    profile = user.profile

    interests = []
    goals = []
    idol_name = "Unknown"

    if profile:
        interests = profile.interests or profile.focus_areas or []
        goals = profile.goals or []

    stmt = (
        select(Plan)
        .options(selectinload(Plan.idol))
        .where(Plan.user_id == user.id)
        .order_by(Plan.created_at.desc())
        .limit(1)
    )
    result = await db.execute(stmt)
    plan = result.scalar_one_or_none()
    if plan and plan.idol:
        idol_name = plan.idol.name

    return {
        "interests": interests,
        "goals": goals,
        "idol_name": idol_name,
    }


async def _generate_and_persist(
    interests: list[str],
    goals: list[str],
    idol_name: str,
    db: AsyncSession,
    count: int = 12,
) -> list[FeedPost]:
    """Generate AI content and persist new items to DB. Returns the saved FeedPost objects."""
    try:
        from app.services.llm import get_llm_client

        # Recently generated titles: without this the prompt converges on the
        # same handful of sources and hash-dedup silently drops the yield.
        recent_stmt = (
            select(FeedPost.title)
            .order_by(FeedPost.created_at.desc())
            .limit(40)
        )
        recent_titles = [row[0] for row in (await db.execute(recent_stmt)).all()]

        prompt = load_and_render("discover_feed.txt", {
            "count": str(count),
            "interests_json": json_lib.dumps(interests) if interests else '["personal development", "entrepreneurship"]',
            "goals_json": json_lib.dumps(goals) if goals else '["build a successful career"]',
            "idol_name": idol_name,
            "exclude_titles_json": json_lib.dumps(recent_titles),
        })

        # Feed cards are short, highly structured, and non-critical. Flash-Lite
        # is materially cheaper and keeps the balanced model for plans/books.
        client = get_llm_client(timeout=60.0, tier="fast")
        response = await client.generate_json(
            system_prompt="You are a content curator. Return only valid JSON, no markdown code blocks.",
            user_prompt=prompt,
        )

        if response.error:
            await record_llm_response(
                operation="feed_generation",
                response=response,
                db=db,
                model=getattr(client, "model", None),
                result_status="generation_failed",
                metadata={"requested_count": count},
            )
            logger.warning(f"[FEED] LLM error: {response.error}")
            return []

        parsed = response.data
        # The model may return a bare list, or wrap it in an object
        # ({"items": [...]}, {"posts": [...]}, …). Normalise to a list of dicts
        # so iterating never yields dict keys (strings) → 'str' has no .get.
        if isinstance(parsed, dict):
            for key in ("items", "posts", "feed", "quotes", "data"):
                if isinstance(parsed.get(key), list):
                    parsed = parsed[key]
                    break
            else:
                parsed = []
        if not isinstance(parsed, list):
            parsed = []

        saved_posts: list[FeedPost] = []
        video_posts_needing_urls: list[tuple[FeedPost, str]] = []  # (post, search_query)

        # ⚡ Bolt Optimization: Batch fetch existing posts to prevent N+1 query problem
        # 1. First pass: compute hashes for valid items
        valid_items = []
        hashes = []
        for item in parsed:
            if not isinstance(item, dict):
                continue
            item_type = item.get("type", "")
            if item_type not in ("quote", "video", "motivation"):
                continue
            title = item.get("title", "")
            content = item.get("content", "")
            content_hash = FeedPost.compute_hash(title, content)
            valid_items.append((item, item_type, title, content, content_hash))
            hashes.append(content_hash)

        # 2. Batch fetch existing posts from DB
        existing_posts_by_hash: dict[str, FeedPost | None] = {}
        if hashes:
            existing_stmt = (
                select(FeedPost)
                .options(selectinload(FeedPost.quote))
                .where(FeedPost.content_hash.in_(hashes))
            )
            existing_result = await db.execute(existing_stmt)
            for post in existing_result.scalars():
                if post.quote_id and post.quote.status != CatalogStatus.PUBLISHED:
                    # Reserve the unique hash but never resurrect a quote that
                    # the independent verification pipeline rejected.
                    existing_posts_by_hash[post.content_hash] = None
                else:
                    existing_posts_by_hash[post.content_hash] = post

        # 3. Second pass: process items, reusing existing posts or creating new ones
        for item, item_type, title, content, content_hash in valid_items:
            if content_hash in existing_posts_by_hash:
                existing_post = existing_posts_by_hash[content_hash]
                if existing_post:
                    saved_posts.append(existing_post)
                continue

            is_video = item_type == "video"

            post = FeedPost(
                id=str(uuid4()),
                type="video" if is_video else "quote",
                title=title,
                content=content if not is_video else None,
                category=item.get("category", "Mindset"),
                source=item.get("source"),
                url=None,  # Never trust LLM URLs — resolve via Tavily
                content_hash=content_hash,
                generated_by_user_id=None,  # Global content, not user-specific
            )
            db.add(post)
            saved_posts.append(post)

            # Cache newly created post to handle duplicates within the same batch
            existing_posts_by_hash[content_hash] = post

            if is_video:
                # Build search query from title + source
                source = item.get("source", "")
                search_query = f"{title} {source}".strip()
                video_posts_needing_urls.append((post, search_query))

        # Resolve video URLs via Tavily (real YouTube links)
        if video_posts_needing_urls:
            from app.services.tavily import resolve_material_urls
            materials = [
                {"title": q, "type": "video", "search_query": q}
                for _, q in video_posts_needing_urls
            ]
            resolved = await resolve_material_urls(materials)
            for (post, _), mat in zip(video_posts_needing_urls, resolved):
                post.url = mat.get("url")
                logger.info(f"[FEED] Resolved video URL: {post.title} → {post.url}")

        await db.flush()
        await record_llm_response(
            operation="feed_generation",
            response=response,
            db=db,
            model=getattr(client, "model", None),
            result_status="persisted" if saved_posts else "empty",
            quality_score=min(1.0, len(saved_posts) / max(count, 1)),
            metadata={
                "requested_count": count,
                "parsed_count": len(valid_items),
                "saved_or_reused_count": len(saved_posts),
                "video_count": len(video_posts_needing_urls),
            },
        )
        logger.info(f"[FEED] Generated and persisted {len(saved_posts)} items")
        return saved_posts

    except Exception as e:
        logger.warning(f"[FEED] Content generation failed: {e}")
        return []


# Single-flight guard: many users hitting a low pool at once should trigger
# one refill, not a stampede of LLM generations.
_refill_in_progress = False


async def _background_refill(user_id: str) -> None:
    """Top up the shared feed pool outside the request path.

    Runs on its own DB session — the request's session is closed by the time
    this executes. Failures are logged and swallowed; the next low-pool
    request simply tries again.
    """
    global _refill_in_progress
    if _refill_in_progress:
        return
    _refill_in_progress = True
    try:
        from app.core.db import async_session_maker

        async with async_session_maker() as bg_db:
            sourced_posts = await _materialize_verified_quotes(bg_db, limit=12)
            remaining = max(12 - len(sourced_posts), 0)
            if remaining == 0:
                await bg_db.commit()
                logger.info("[FEED] Background refill used 12 sourced catalog quotes")
                return
            user = await bg_db.get(User, user_id)
            if user is None:
                return
            ctx = await _get_user_context(user, bg_db)
            await _generate_and_persist(
                interests=ctx["interests"],
                goals=ctx["goals"],
                idol_name=ctx["idol_name"],
                db=bg_db,
                count=remaining,
            )
            await bg_db.commit()
            logger.info("[FEED] Background refill completed")
    except Exception as e:
        logger.warning(f"[FEED] Background refill failed: {e}")
    finally:
        _refill_in_progress = False


# ─── Endpoints ─────────────────────────────────────────────────────

@router.get("", response_model=FeedResponse)
async def get_feed(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=10, ge=1, le=50),
    seed: Optional[int] = Query(default=None),
    refresh: bool = Query(default=False),
):
    """
    Discover feed — mix of DB posts + fresh AI posts.
    Fresh AI items are auto-persisted to DB.
    Pass refresh=true to force new content generation.
    """
    # 1. Materialize already-verified catalog content first. This is both
    #    faster and cheaper than generating lookalike quotes on the request.
    await _materialize_verified_quotes(db, limit=20)

    # 2. Load existing posts from DB (most recent 100)
    db_stmt = (
        select(FeedPost)
        .outerjoin(VerifiedQuote, FeedPost.quote_id == VerifiedQuote.id)
        .options(selectinload(FeedPost.quote))
        .where(
            or_(
                FeedPost.quote_id.is_(None),
                VerifiedQuote.status == CatalogStatus.PUBLISHED,
            )
        )
        .order_by(FeedPost.created_at.desc())
        .limit(100)
    )
    db_result = await db.execute(db_stmt)
    db_posts = list(db_result.scalars().all())
    existing_ids = {p.id for p in db_posts}

    # Count usable posts (quotes + videos with valid watch URLs)
    usable = sum(
        1 for p in db_posts
        if p.type != "video" or (p.url and "watch?v=" in p.url)
    )

    # 3. Generate fresh content when the pool is low or on forced refresh.
    #    Only block the request when we must: an explicit refresh (the user
    #    asked for new content) or a completely empty pool. A merely-low pool
    #    is topped up in the background — LLM + video resolution can take
    #    15-60s and should never stall the main scroll surface.
    if refresh or usable == 0:
        ctx = await _get_user_context(current_user, db)
        ai_posts = await _generate_and_persist(
            interests=ctx["interests"],
            goals=ctx["goals"],
            idol_name=ctx["idol_name"],
            db=db,
            count=12,
        )
        for post in ai_posts:
            if post.id not in existing_ids:
                db_posts.append(post)
                existing_ids.add(post.id)
    elif usable < 20:
        asyncio.create_task(_background_refill(current_user.id))

    await db.commit()

    # 4. Check which posts current user has liked
    if db_posts:
        post_ids = [p.id for p in db_posts]
        liked_stmt = select(FeedLike.post_id).where(
            FeedLike.user_id == current_user.id,
            FeedLike.post_id.in_(post_ids),
        )
        liked_result = await db.execute(liked_stmt)
        liked_ids = {row[0] for row in liked_result.all()}
    else:
        liked_ids = set()

    # 5. Shuffle and paginate (deterministic seed for consistent pagination)
    if seed is None:
        # Use date-based seed so pagination is consistent within a day
        seed = int(datetime.now().strftime("%Y%m%d"))
    rng = random.Random(seed)
    rng.shuffle(db_posts)

    total = len(db_posts)
    start = (page - 1) * page_size
    end = start + page_size
    page_posts = db_posts[start:end]
    has_more = end < total

    items = []
    for post in page_posts:
        # Skip video posts with no resolved URL — they show a broken black screen
        if post.type == "video" and not post.url:
            continue
        quote = post.quote if post.quote_id else None
        items.append(FeedItemResponse(
            id=post.id,
            type=post.type,
            title=post.title,
            content=post.content,
            category=post.category,
            url=post.url,
            source=post.source,
            reason=post.content if post.type == "video" else None,
            like_count=post.like_count,
            comment_count=post.comment_count,
            is_liked=post.id in liked_ids,
            speaker=quote.speaker if quote else None,
            is_sourced=quote is not None,
            is_verified=(
                quote.verification_state == QuoteVerificationState.VERIFIED
                if quote
                else False
            ),
            verification_level=quote.verification_state.value if quote else None,
            quote_type=quote.quote_type.value if quote else None,
            source_url=(quote.verified_source_url or quote.source_url if quote else None),
            source_title=(
                quote.verified_source_title or quote.source_title if quote else None
            ),
            source_reference=quote.source_reference if quote else None,
        ))

    return FeedResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        has_more=has_more,
    )


@router.get("/quality-stats", response_model=FeedQualityStatsResponse)
async def get_feed_quality_stats(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """Expose catalog quality and grounded-call usage for budget monitoring."""
    del current_user  # Authentication is required; statistics are global.
    from app.services.llm.budget import get_daily_background_budget_status
    from app.services.llm.pricing import PRICING_VERSION

    quote_rows = (
        await db.execute(
            select(
                VerifiedQuote.verification_state,
                func.count(VerifiedQuote.id),
            ).group_by(VerifiedQuote.verification_state)
        )
    ).all()
    quote_counts = {state.value: int(count) for state, count in quote_rows}
    for state in QuoteVerificationState:
        quote_counts.setdefault(state.value, 0)

    published_quotes = int(
        (
            await db.execute(
                select(func.count(VerifiedQuote.id)).where(
                    VerifiedQuote.status == CatalogStatus.PUBLISHED
                )
            )
        ).scalar_one()
        or 0
    )
    day_start = datetime.now(timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    usage = (
        await db.execute(
            select(
                func.count(LLMUsageEvent.id),
                func.coalesce(func.sum(LLMUsageEvent.prompt_tokens), 0),
                func.coalesce(func.sum(LLMUsageEvent.completion_tokens), 0),
                func.coalesce(func.sum(LLMUsageEvent.total_tokens), 0),
                func.coalesce(func.sum(LLMUsageEvent.search_queries), 0),
                func.coalesce(func.avg(LLMUsageEvent.duration_ms), 0.0),
            ).where(
                LLMUsageEvent.operation == "quote_verification",
                LLMUsageEvent.created_at >= day_start,
            )
        )
    ).one()
    operation_rows = (
        await db.execute(
            select(
                LLMUsageEvent.operation,
                LLMUsageEvent.model,
                func.count(LLMUsageEvent.id),
                func.count(LLMUsageEvent.id).filter(LLMUsageEvent.success.is_(True)),
                func.coalesce(func.sum(LLMUsageEvent.prompt_tokens), 0),
                func.coalesce(func.sum(LLMUsageEvent.completion_tokens), 0),
                func.coalesce(func.sum(LLMUsageEvent.total_tokens), 0),
                func.coalesce(func.sum(LLMUsageEvent.estimated_cost_usd), 0.0),
                func.coalesce(func.avg(LLMUsageEvent.duration_ms), 0.0),
                func.avg(LLMUsageEvent.quality_score),
            )
            .where(LLMUsageEvent.created_at >= day_start)
            .group_by(LLMUsageEvent.operation, LLMUsageEvent.model)
            .order_by(func.coalesce(func.sum(LLMUsageEvent.total_tokens), 0).desc())
        )
    ).all()
    operation_usage = [
        LLMOperationUsageResponse(
            operation=str(row[0]),
            model=str(row[1]),
            calls=int(row[2] or 0),
            successful_calls=int(row[3] or 0),
            prompt_tokens=int(row[4] or 0),
            completion_tokens=int(row[5] or 0),
            total_tokens=int(row[6] or 0),
            estimated_cost_usd=round(float(row[7] or 0.0), 6),
            average_duration_ms=round(float(row[8] or 0.0), 1),
            average_quality_score=(
                round(float(row[9]), 3) if row[9] is not None else None
            ),
        )
        for row in operation_rows
    ]
    routing_reason = LLMUsageEvent.metadata_json["routing_reason"].astext
    routing_rows = (
        await db.execute(
            select(routing_reason, func.count(LLMUsageEvent.id))
            .where(
                LLMUsageEvent.created_at >= day_start,
                routing_reason.is_not(None),
            )
            .group_by(routing_reason)
        )
    ).all()
    routing_decisions = {str(reason): int(count) for reason, count in routing_rows}
    total_cost_today = float(
        (
            await db.execute(
                select(
                    func.coalesce(func.sum(LLMUsageEvent.estimated_cost_usd), 0.0)
                ).where(LLMUsageEvent.created_at >= day_start)
            )
        ).scalar_one()
        or 0.0
    )
    background_budget = await get_daily_background_budget_status(db)

    daily_limit = settings.catalog_quote_verification_daily_limit
    batch_size = settings.catalog_quote_verification_batch_size
    return FeedQualityStatsResponse(
        quote_counts=quote_counts,
        published_quotes=published_quotes,
        verification_calls_today=int(usage[0] or 0),
        prompt_tokens_today=int(usage[1] or 0),
        completion_tokens_today=int(usage[2] or 0),
        total_tokens_today=int(usage[3] or 0),
        search_queries_today=int(usage[4] or 0),
        average_duration_ms_today=round(float(usage[5] or 0.0), 1),
        daily_call_limit=daily_limit,
        batch_size=batch_size,
        max_quotes_checked_per_day=daily_limit * batch_size,
        llm_usage_by_operation_today=operation_usage,
        routing_decisions_today=routing_decisions,
        estimated_cost_usd_today=round(total_cost_today, 6),
        background_estimated_cost_usd_today=round(
            background_budget.spent_usd, 6
        ),
        background_reserved_cost_usd=round(background_budget.reserved_usd, 6),
        background_daily_budget_usd=background_budget.limit_usd,
        background_budget_remaining_usd=round(background_budget.remaining_usd, 6),
        background_budget_used_percent=round(background_budget.used_ratio * 100, 2),
        background_budget_state=background_budget.state,
        pricing_version=PRICING_VERSION,
        search_overage_included=settings.llm_budget_include_search_overage,
    )


@router.post("/{post_id}/like")
async def toggle_like(
    post_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """Toggle like on a feed post. Returns new like state and count."""
    # Check post exists
    post = await db.get(FeedPost, post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    # Check if already liked
    existing = await db.execute(
        select(FeedLike).where(
            FeedLike.user_id == current_user.id,
            FeedLike.post_id == post_id,
        )
    )
    like = existing.scalar_one_or_none()

    if like:
        # Unlike
        await db.delete(like)
        post.like_count = max(0, post.like_count - 1)
        is_liked = False
    else:
        # Like
        new_like = FeedLike(
            id=str(uuid4()),
            user_id=current_user.id,
            post_id=post_id,
        )
        db.add(new_like)
        post.like_count += 1
        is_liked = True

    await db.commit()
    return {"is_liked": is_liked, "like_count": post.like_count}


@router.get("/{post_id}/comments", response_model=list[CommentResponse])
async def get_comments(
    post_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """Get all comments for a feed post."""
    post = await db.get(FeedPost, post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    stmt = (
        select(FeedComment)
        .where(FeedComment.post_id == post_id)
        .order_by(FeedComment.created_at.asc())
    )
    result = await db.execute(stmt)
    comments = result.scalars().all()

    return [
        CommentResponse(
            id=c.id,
            user_id=c.user_id,
            user_name="You" if c.user_id == current_user.id else "User",
            text=c.text,
            created_at=c.created_at,
        )
        for c in comments
    ]


@router.post("/{post_id}/comments", response_model=CommentResponse)
async def add_comment(
    post_id: str,
    body: CommentRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """Add a comment to a feed post."""
    post = await db.get(FeedPost, post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    if not body.text.strip():
        raise HTTPException(status_code=400, detail="Comment text cannot be empty")

    comment = FeedComment(
        id=str(uuid4()),
        user_id=current_user.id,
        post_id=post_id,
        text=body.text.strip(),
    )
    db.add(comment)
    post.comment_count += 1
    await db.commit()

    return CommentResponse(
        id=comment.id,
        user_id=comment.user_id,
        user_name="You",
        text=comment.text,
        created_at=comment.created_at,
    )
