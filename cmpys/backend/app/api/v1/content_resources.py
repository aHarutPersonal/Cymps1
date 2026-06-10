"""Shared content resource and Vault endpoints."""
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.content_resource import (
    ContentResource,
    ContentResourceKind,
    UserContentHighlight,
    UserContentProgress,
    UserContentSave,
)
from app.models.plan import Plan, PlanItem, PlanItemContentResource
from app.models.user import User
from app.schemas.content_resource import (
    ContentHighlightCreate,
    ContentHighlightListResponse,
    ContentHighlightResponse,
    ContentProgressUpdate,
    ContentResourceListResponse,
    ContentResourceResponse,
    ContentResourceSaveRequest,
    ContentResourceSaveResponse,
    ContinueReadingResponse,
)

router = APIRouter(prefix="/content-resources", tags=["content-resources"])


def _resource_response(
    resource: ContentResource,
    *,
    save: UserContentSave | None = None,
    progress: UserContentProgress | None = None,
) -> ContentResourceResponse:
    """Convert a shared resource plus user state into API shape."""
    return ContentResourceResponse(
        id=resource.id,
        kind=resource.kind.value if hasattr(resource.kind, "value") else str(resource.kind),
        canonicalKey=resource.canonical_key,
        title=resource.title,
        authorOrCreator=resource.author_or_creator,
        sourceUrl=resource.source_url,
        thumbnailUrl=resource.thumbnail_url,
        licenseStatus=resource.license_status.value
        if hasattr(resource.license_status, "value")
        else str(resource.license_status),
        contentMarkdown=resource.content_markdown,
        summaryJson=resource.summary_json,
        durationMinutes=resource.duration_minutes,
        metadataJson=resource.metadata_json,
        isSaved=save is not None,
        savedAt=save.created_at if save else None,
        progressPercent=progress.progress_percent if progress else 0,
        cursorJson=progress.cursor_json if progress else None,
        completedAt=progress.completed_at if progress else None,
        createdAt=resource.created_at,
        updatedAt=resource.updated_at,
    )


def _highlight_response(highlight: UserContentHighlight) -> ContentHighlightResponse:
    return ContentHighlightResponse(
        id=highlight.id,
        contentResourceId=highlight.content_resource_id,
        locatorJson=highlight.locator_json,
        quoteText=highlight.quote_text,
        noteText=highlight.note_text,
        createdAt=highlight.created_at,
        updatedAt=highlight.updated_at,
    )


async def _get_resource(db: AsyncSession, resource_id: str) -> ContentResource:
    resource = await db.get(ContentResource, resource_id)
    if not resource:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Resource not found")
    return resource


async def _get_save(
    db: AsyncSession,
    user_id: str,
    resource_id: str,
) -> UserContentSave | None:
    result = await db.execute(
        select(UserContentSave).where(
            UserContentSave.user_id == user_id,
            UserContentSave.content_resource_id == resource_id,
        )
    )
    return result.scalar_one_or_none()


async def _get_progress(
    db: AsyncSession,
    user_id: str,
    resource_id: str,
) -> UserContentProgress | None:
    result = await db.execute(
        select(UserContentProgress).where(
            UserContentProgress.user_id == user_id,
            UserContentProgress.content_resource_id == resource_id,
        )
    )
    return result.scalar_one_or_none()


@router.get("", response_model=ContentResourceListResponse)
async def list_content_resources(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    kind: str | None = Query(default=None),
    q: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> ContentResourceListResponse:
    """List reusable resources, optionally filtered by kind/search."""
    stmt = select(ContentResource)
    if kind:
        try:
            parsed_kind = ContentResourceKind(kind)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="Invalid resource kind") from exc
        stmt = stmt.where(ContentResource.kind == parsed_kind)
    if q:
        needle = f"%{q}%"
        stmt = stmt.where(
            or_(
                ContentResource.title.ilike(needle),
                ContentResource.author_or_creator.ilike(needle),
                ContentResource.canonical_key.ilike(needle),
            )
        )

    # Bolt: Optimizing pagination count query to avoid slow subquery
    total_result = await db.execute(stmt.with_only_columns(func.count(ContentResource.id)).order_by(None))
    total = total_result.scalar() or 0

    result = await db.execute(
        stmt.order_by(ContentResource.updated_at.desc()).offset(offset).limit(limit)
    )
    resources = list(result.scalars().all())
    resource_ids = [r.id for r in resources]

    saves_by_resource: dict[str, UserContentSave] = {}
    progress_by_resource: dict[str, UserContentProgress] = {}
    if resource_ids:
        save_result = await db.execute(
            select(UserContentSave).where(
                UserContentSave.user_id == current_user.id,
                UserContentSave.content_resource_id.in_(resource_ids),
            )
        )
        saves_by_resource = {s.content_resource_id: s for s in save_result.scalars().all()}

        progress_result = await db.execute(
            select(UserContentProgress).where(
                UserContentProgress.user_id == current_user.id,
                UserContentProgress.content_resource_id.in_(resource_ids),
            )
        )
        progress_by_resource = {
            p.content_resource_id: p for p in progress_result.scalars().all()
        }

    return ContentResourceListResponse(
        resources=[
            _resource_response(
                r,
                save=saves_by_resource.get(r.id),
                progress=progress_by_resource.get(r.id),
            )
            for r in resources
        ],
        total=total,
    )


@router.get("/vault", response_model=ContentResourceListResponse)
async def list_vault_resources(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> ContentResourceListResponse:
    """List the current user's saved books, videos, articles, and lessons."""
    total_result = await db.execute(
        select(func.count(UserContentSave.id)).where(UserContentSave.user_id == current_user.id)
    )
    total = total_result.scalar() or 0

    result = await db.execute(
        select(ContentResource, UserContentSave, UserContentProgress)
        .join(UserContentSave, UserContentSave.content_resource_id == ContentResource.id)
        .outerjoin(
            UserContentProgress,
            and_(
                UserContentProgress.content_resource_id == ContentResource.id,
                UserContentProgress.user_id == current_user.id,
            ),
        )
        .where(UserContentSave.user_id == current_user.id)
        .order_by(UserContentSave.created_at.desc())
        .offset(offset)
        .limit(limit)
    )
    rows = result.all()

    return ContentResourceListResponse(
        resources=[
            _resource_response(resource, save=save, progress=progress)
            for resource, save, progress in rows
        ],
        total=total,
    )


@router.get("/library", response_model=ContentResourceListResponse)
async def list_library_resources(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    kind: str | None = Query(default=None),
    q: str | None = Query(default=None),
    sort: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> ContentResourceListResponse:
    """List all content resources available to the user.

    Includes: vault saves, plan-linked materials, and public-domain books.
    Supports filtering by kind, searching by title/author, and sorting.
    """
    # Collect resource IDs from three sources: vault, plan links, and public domain
    resource_ids: set[str] = set()

    # 1. Vault saves
    vault_result = await db.execute(
        select(UserContentSave.content_resource_id).where(
            UserContentSave.user_id == current_user.id
        )
    )
    resource_ids.update(row[0] for row in vault_result.fetchall())

    # 2. Plan-linked materials
    plan_result = await db.execute(
        select(Plan.id).where(Plan.user_id == current_user.id).limit(1)
    )
    plan_id = plan_result.scalar_one_or_none()
    if plan_id:
        link_result = await db.execute(
            select(PlanItemContentResource.content_resource_id)
            .join(PlanItem, PlanItemContentResource.plan_item_id == PlanItem.id)
            .where(PlanItem.plan_id == plan_id)
        )
        resource_ids.update(row[0] for row in link_result.fetchall())

    # 3. Public domain books (always available)
    pd_result = await db.execute(
        select(ContentResource.id).where(
            ContentResource.kind == ContentResourceKind.PUBLIC_DOMAIN_BOOK
        )
    )
    resource_ids.update(row[0] for row in pd_result.fetchall())

    if not resource_ids:
        return ContentResourceListResponse(resources=[], total=0)

    # Build base query filtering to accessible resource IDs
    stmt = select(ContentResource).where(ContentResource.id.in_(resource_ids))

    # Apply kind filter
    if kind:
        try:
            parsed_kind = ContentResourceKind(kind)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="Invalid resource kind") from exc
        stmt = stmt.where(ContentResource.kind == parsed_kind)

    # Apply search filter
    if q:
        needle = f"%{q}%"
        stmt = stmt.where(
            or_(
                ContentResource.title.ilike(needle),
                ContentResource.author_or_creator.ilike(needle),
            )
        )

    # Count total before pagination
    # Bolt: Optimizing pagination count query to avoid slow subquery
    total_result = await db.execute(stmt.with_only_columns(func.count(ContentResource.id)).order_by(None))
    total = total_result.scalar() or 0

    # Apply sort
    if sort == "duration":
        stmt = stmt.order_by(ContentResource.duration_minutes.asc().nulls_last())
    elif sort == "duration_desc":
        stmt = stmt.order_by(ContentResource.duration_minutes.desc().nulls_last())
    elif sort == "title":
        stmt = stmt.order_by(ContentResource.title.asc())
    else:
        stmt = stmt.order_by(ContentResource.updated_at.desc())

    result = await db.execute(stmt.offset(offset).limit(limit))
    resources = list(result.scalars().all())

    # Fetch user state for all resources
    saves_by_resource: dict[str, UserContentSave] = {}
    progress_by_resource: dict[str, UserContentProgress] = {}
    if resources:
        resource_id_list = [r.id for r in resources]
        save_result = await db.execute(
            select(UserContentSave).where(
                UserContentSave.user_id == current_user.id,
                UserContentSave.content_resource_id.in_(resource_id_list),
            )
        )
        saves_by_resource = {s.content_resource_id: s for s in save_result.scalars().all()}
        progress_result = await db.execute(
            select(UserContentProgress).where(
                UserContentProgress.user_id == current_user.id,
                UserContentProgress.content_resource_id.in_(resource_id_list),
            )
        )
        progress_by_resource = {
            p.content_resource_id: p for p in progress_result.scalars().all()
        }

    return ContentResourceListResponse(
        resources=[
            _resource_response(
                r,
                save=saves_by_resource.get(r.id),
                progress=progress_by_resource.get(r.id),
            )
            for r in resources
        ],
        total=total,
    )


@router.get("/continue-reading", response_model=ContinueReadingResponse | None)
async def get_continue_reading(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ContinueReadingResponse | None:
    """Get the most recent in-progress content resource for the current user.

    Returns the resource with progress > 0 and < 100, ordered by most recently updated.
    Returns null if no in-progress resource exists.
    """
    result = await db.execute(
        select(ContentResource, UserContentProgress)
        .join(
            UserContentProgress,
            UserContentProgress.content_resource_id == ContentResource.id,
        )
        .where(
            UserContentProgress.user_id == current_user.id,
            UserContentProgress.progress_percent > 0,
            UserContentProgress.progress_percent < 100,
        )
        .order_by(UserContentProgress.updated_at.desc())
        .limit(1)
    )
    row = result.first()
    if not row:
        return None

    resource, progress = row
    save = await _get_save(db, current_user.id, resource.id)
    resource_resp = _resource_response(resource, save=save, progress=progress)
    return ContinueReadingResponse(resource=resource_resp)


@router.get("/{resource_id}", response_model=ContentResourceResponse)
async def get_content_resource(
    resource_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ContentResourceResponse:
    """Get a shared resource and this user's save/progress state."""
    resource = await _get_resource(db, resource_id)
    save = await _get_save(db, current_user.id, resource_id)
    progress = await _get_progress(db, current_user.id, resource_id)
    return _resource_response(resource, save=save, progress=progress)


@router.post("/{resource_id}/save", response_model=ContentResourceSaveResponse)
async def save_content_resource(
    resource_id: str,
    data: ContentResourceSaveRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ContentResourceSaveResponse:
    """Save a shared resource into the current user's Vault."""
    resource = await _get_resource(db, resource_id)
    save = await _get_save(db, current_user.id, resource_id)
    action = "saved"
    if save:
        action = "updated"
    else:
        save = UserContentSave(
            user_id=current_user.id,
            content_resource_id=resource_id,
        )
        db.add(save)

    if data.collection is not None:
        save.collection = data.collection
    if data.note is not None:
        save.note = data.note
    await db.flush()

    progress = await _get_progress(db, current_user.id, resource_id)
    return ContentResourceSaveResponse(
        success=True,
        action=action,
        resource=_resource_response(resource, save=save, progress=progress),
    )


@router.delete("/{resource_id}/save", status_code=status.HTTP_204_NO_CONTENT)
async def unsave_content_resource(
    resource_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> None:
    """Remove a shared resource from the current user's Vault."""
    await _get_resource(db, resource_id)
    save = await _get_save(db, current_user.id, resource_id)
    if save:
        await db.delete(save)


@router.patch("/{resource_id}/progress", response_model=ContentResourceResponse)
async def update_content_progress(
    resource_id: str,
    data: ContentProgressUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ContentResourceResponse:
    """Update user-specific reading/watch progress for a shared resource."""
    resource = await _get_resource(db, resource_id)
    progress = await _get_progress(db, current_user.id, resource_id)
    if not progress:
        progress = UserContentProgress(
            user_id=current_user.id,
            content_resource_id=resource_id,
        )
        db.add(progress)

    progress.progress_percent = data.progressPercent
    progress.cursor_json = data.cursorJson
    if data.completed is True or data.progressPercent == 100:
        progress.completed_at = datetime.now(timezone.utc)
    elif data.completed is False:
        progress.completed_at = None
    await db.flush()

    save = await _get_save(db, current_user.id, resource_id)
    return _resource_response(resource, save=save, progress=progress)


@router.get("/{resource_id}/highlights", response_model=ContentHighlightListResponse)
async def list_content_highlights(
    resource_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ContentHighlightListResponse:
    """List this user's highlights/notes for a shared resource."""
    await _get_resource(db, resource_id)
    result = await db.execute(
        select(UserContentHighlight)
        .where(
            UserContentHighlight.user_id == current_user.id,
            UserContentHighlight.content_resource_id == resource_id,
        )
        .order_by(UserContentHighlight.created_at.desc())
    )
    highlights = list(result.scalars().all())
    return ContentHighlightListResponse(
        highlights=[_highlight_response(h) for h in highlights],
        total=len(highlights),
    )


@router.post(
    "/{resource_id}/highlights",
    response_model=ContentHighlightResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_content_highlight(
    resource_id: str,
    data: ContentHighlightCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ContentHighlightResponse:
    """Create a user-specific highlight or note on a shared resource."""
    await _get_resource(db, resource_id)
    highlight = UserContentHighlight(
        user_id=current_user.id,
        content_resource_id=resource_id,
        locator_json=data.locatorJson,
        quote_text=data.quoteText,
        note_text=data.noteText,
    )
    db.add(highlight)
    await db.flush()
    return _highlight_response(highlight)


@router.delete(
    "/{resource_id}/highlights/{highlight_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_content_highlight(
    resource_id: str,
    highlight_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> None:
    """Delete one of the current user's notes/highlights for a shared resource."""
    await _get_resource(db, resource_id)
    result = await db.execute(
        select(UserContentHighlight).where(
            UserContentHighlight.id == highlight_id,
            UserContentHighlight.user_id == current_user.id,
            UserContentHighlight.content_resource_id == resource_id,
        )
    )
    highlight = result.scalar_one_or_none()
    if not highlight:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Highlight not found")
    await db.delete(highlight)
