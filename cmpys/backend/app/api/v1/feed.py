"""
Discover Feed API — AI-generated content persisted to DB with social features.

Flow:
1. GET /feed — Returns mix of existing DB posts + fresh AI-generated posts.
   New AI items are auto-saved to DB before returning.
2. POST /feed/{id}/like — Toggle like on a post
3. GET /feed/{id}/comments — List comments
4. POST /feed/{id}/comments — Add a comment
"""
import json as json_lib
import logging
import random
from datetime import datetime
from typing import Annotated, Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select, func, exists
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.feed_comment import FeedComment
from app.models.feed_like import FeedLike
from app.models.feed_post import FeedPost
from app.models.plan import Plan
from app.models.user import User
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


class FeedResponse(BaseModel):
    items: list[FeedItemResponse]
    total: int
    page: int
    page_size: int
    has_more: bool


class CommentResponse(BaseModel):
    id: str
    user_id: str
    user_name: str | None = None
    text: str
    created_at: datetime


class CommentRequest(BaseModel):
    text: str


# ─── Helpers ───────────────────────────────────────────────────────

async def _get_user_context(user: User, db: AsyncSession) -> dict:
    """Build user context for LLM prompts."""
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

        prompt = load_and_render("discover_feed.txt", {
            "count": str(count),
            "interests_json": json_lib.dumps(interests) if interests else '["personal development", "entrepreneurship"]',
            "goals_json": json_lib.dumps(goals) if goals else '["build a successful career"]',
            "idol_name": idol_name,
        })

        client = get_llm_client(timeout=60.0)
        response = await client.generate_json(
            system_prompt="You are a content curator. Return only valid JSON, no markdown code blocks.",
            user_prompt=prompt,
        )

        if response.error:
            logger.warning(f"[FEED] LLM error: {response.error}")
            return []

        parsed = response.data
        saved_posts: list[FeedPost] = []
        video_posts_needing_urls: list[tuple[FeedPost, str]] = []  # (post, search_query)

        for item in parsed:
            item_type = item.get("type", "")
            if item_type not in ("quote", "video", "motivation"):
                continue

            title = item.get("title", "")
            content = item.get("content", "")
            content_hash = FeedPost.compute_hash(title, content)

            # Check if already exists (dedup by content_hash)
            existing = await db.execute(
                select(FeedPost).where(FeedPost.content_hash == content_hash)
            )
            existing_post = existing.scalar_one_or_none()

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
        logger.info(f"[FEED] Generated and persisted {len(saved_posts)} items")
        return saved_posts

    except Exception as e:
        logger.warning(f"[FEED] Content generation failed: {e}")
        return []


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
    # 1. Load existing posts from DB (most recent 100)
    db_stmt = (
        select(FeedPost)
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

    # 2. Generate fresh content when pool is low or forced refresh
    if usable < 20 or refresh:
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

    await db.commit()

    # 3. Check which posts current user has liked
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

    # 4. Shuffle and paginate (deterministic seed for consistent pagination)
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
        ))

    return FeedResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        has_more=has_more,
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
