"""
Idol management endpoints.

PROMPT MAPPING:
- POST /idols/import
  - Enqueues ingestion job ONLY (no LLM in request thread)
  - LLM called in background worker via Celery task: run_idol_ingestion
  - Worker prompts: extractor_system.txt + profile_extract.txt, 
    achievements_extract.txt, timeline_normalize.txt, persona_pack.txt

- GET /idols/discover (Wikidata only, no LLM)
  - Uses Wikidata API for exact name searches
"""
import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from google import genai
from google.genai import types
from pydantic import BaseModel
from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.core.validation import is_valid_uuid
from app.models.idol import CatalogStatus, Idol
from app.models.idol_alias import IdolAlias
from app.models.idol_external_id import IdolExternalId
from app.models.idol_job import IdolImportJob
from app.models.idol_persona import IdolPersona
from app.models.idol_profile import IdolProfile
from app.models.idol_tag import IdolTag
from app.models.idol_tag_link import IdolTagLink
from app.models.idol_timeline import IdolTimelineEvent
from app.models.user import User
from app.providers import DiscoveryResponse, search_candidates
from app.providers.wikidata import fetch_entity_by_id
from app.schemas.idol import (
    EvidenceResponse,
    IdolAliasResponse,
    IdolDetailResponse,
    IdolExternalIdResponse,
    IdolImportRequest,
    IdolImportResponse,
    IdolPersonaResponse,
    IdolProfileResponse,
    IdolResponse,
    IdolSearchResponse,
    IdolSuggestResponse,
    IdolTagResponse,
    TimelineEventResponse,
    TimelineResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/idols", tags=["idols"])


def _published_only(stmt):
    """Restrict an Idol select to published catalog entries."""
    return stmt.where(Idol.status == CatalogStatus.PUBLISHED)


def _validate_idol_id(idol_id: str) -> str:
    """Path-param dependency: reject malformed idol ids with a clean 404.

    The id is queried against a UUID-typed column; a non-UUID string would
    otherwise raise inside the driver and surface as HTTP 500.
    """
    if not is_valid_uuid(idol_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )
    return idol_id


def _timeline_date_precision(value: object) -> str:
    """Return a stable response value for enum/string/legacy precision data."""
    if value is None:
        return "unknown"
    enum_value = getattr(value, "value", None)
    if enum_value:
        return str(enum_value)
    text = str(value).lower()
    if "." in text:
        text = text.rsplit(".", 1)[-1]
    return text or "unknown"


def _idol_to_response(idol: Idol) -> IdolResponse:
    """Convert Idol model to response schema."""
    return IdolResponse(
        id=idol.id,
        name=idol.name,
        birth_date=idol.birth_date,
        domain=idol.domain,
        image_url=idol.image_url,
        imageSourceUrl=idol.image_source_url,
        imageLicense=idol.image_license,
        imageAttribution=idol.image_attribution_json,
        aliases=[
            IdolAliasResponse(id=alias.id, alias_text=alias.alias_text)
            for alias in idol.aliases
        ],
        tags=[
            IdolTagResponse(id=link.tag.id, name=link.tag.name, type=link.tag.type)
            for link in idol.tag_links
        ],
    )


def _profile_to_response(profile: IdolProfile) -> IdolProfileResponse:
    """Convert an extracted idol profile to the public API shape."""
    evidence_list = []
    if isinstance(profile.evidence, list):
        for ev in profile.evidence:
            evidence_list.append(EvidenceResponse(
                sourceId=ev.get("source_id", ""),
                chunkIndex=ev.get("chunk_index", 0),
                sourceUrl=ev.get("source_url", ""),
                snippet=ev.get("snippet", ""),
                confidence=ev.get("confidence", 0.0),
            ))

    return IdolProfileResponse(
        id=profile.id,
        idolId=profile.idol_id,
        displayName=profile.display_name,
        shortDescription=profile.short_description,
        birthDate=profile.birth_date,
        deathDate=profile.death_date,
        nationality=profile.nationality or [],
        domains=profile.domains or [],
        primaryRoles=profile.primary_roles or [],
        eraTags=profile.era_tags or [],
        notableThemes=profile.notable_themes or [],
        wikipediaUrl=profile.wikipedia_url,
        confidence=profile.confidence,
        evidence=evidence_list,
        createdAt=profile.created_at,
    )


@router.get("/search", response_model=IdolSearchResponse)
async def search_idols(
    db: Annotated[AsyncSession, Depends(get_db)],
    q: str = Query("", description="Search query for idol name or alias"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> IdolSearchResponse:
    """Search idols by name or alias."""
    # Build base query with eager loading
    base_query = _published_only(
        select(Idol)
        .options(
            selectinload(Idol.aliases),
            selectinload(Idol.tag_links).selectinload(IdolTagLink.tag),
        )
        .distinct()
    )

    # Apply search filter if query provided
    if q.strip():
        search_term = f"%{q.strip()}%"
        # Join with aliases to search both name and alias_text
        base_query = (
            base_query
            .outerjoin(IdolAlias, Idol.id == IdolAlias.idol_id)
            .where(
                or_(
                    Idol.name.ilike(search_term),
                    IdolAlias.alias_text.ilike(search_term),
                )
            )
        )

    # Get total count
    count_query = _published_only(select(func.count(func.distinct(Idol.id))))
    if q.strip():
        search_term = f"%{q.strip()}%"
        count_query = (
            count_query
            .outerjoin(IdolAlias, Idol.id == IdolAlias.idol_id)
            .where(
                or_(
                    Idol.name.ilike(search_term),
                    IdolAlias.alias_text.ilike(search_term),
                )
            )
        )
    count_result = await db.execute(count_query)
    total = count_result.scalar() or 0

    # Apply pagination
    query = base_query.offset(offset).limit(limit)
    result = await db.execute(query)
    idols = result.scalars().unique().all()

    return IdolSearchResponse(
        idols=[_idol_to_response(idol) for idol in idols],
        total=total,
    )


@router.get("/suggest-legacy", response_model=IdolSuggestResponse)
async def suggest_idols_legacy(
    db: Annotated[AsyncSession, Depends(get_db)],
    focus: str = Query("", description="Comma-separated focus areas/tags"),
    limit: int = Query(10, ge=1, le=50),
) -> IdolSuggestResponse:
    """
    Legacy suggest endpoint - simple tag-based suggestions from local DB only.
    
    Use /suggest for hybrid local+web suggestions.
    """
    # Parse focus areas
    focus_areas = [f.strip().lower() for f in focus.split(",") if f.strip()]

    query = _published_only(
        select(Idol)
        .options(
            selectinload(Idol.aliases),
            selectinload(Idol.tag_links).selectinload(IdolTagLink.tag),
        )
        .distinct()
    )

    if focus_areas:
        # Join with tags and filter by tag name or domain
        query = (
            query
            .outerjoin(IdolTagLink, Idol.id == IdolTagLink.idol_id)
            .outerjoin(IdolTag, IdolTagLink.tag_id == IdolTag.id)
            .where(
                or_(
                    IdolTag.name.in_(focus_areas),
                    Idol.domain.in_(focus_areas),
                )
            )
        )

    query = query.limit(limit)
    result = await db.execute(query)
    idols = result.scalars().unique().all()

    return IdolSuggestResponse(
        idols=[_idol_to_response(idol) for idol in idols],
    )


@router.get("/discover", response_model=DiscoveryResponse)
async def discover_idols(
    q: str = Query(..., description="Search query for discovering idols by name"),
    limit: int = Query(10, ge=1, le=20),
) -> DiscoveryResponse:
    """
    Discover idols by name from Wikidata.
    
    Best for exact name searches like "Elon Musk", "Warren Buffett".
    For interest-based suggestions, use /suggest instead.
    
    Returns candidates with confidence scores based on:
    - Exact name match
    - Has birth date
    - Has Wikipedia link
    - Is a human entity
    """
    candidates = await search_candidates(q, limit)
    return DiscoveryResponse(query=q, candidates=candidates)


@router.post("/import", response_model=IdolImportResponse, status_code=status.HTTP_201_CREATED)
async def import_idol(
    data: IdolImportRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IdolImportResponse:
    """
    Import an idol from an external provider.
    
    LLM USAGE: INDIRECT (background worker only)
    
    This endpoint enqueues an import job and returns immediately.
    The actual LLM extraction happens in the Celery worker.
    
    WORKER TASK: app.tasks.ingestion.run_idol_ingestion
    
    WORKER PROMPTS USED:
    - extractor_system.txt (system prompt for all extraction steps)
    - profile_extract.txt (profile extraction)
    - achievements_extract.txt (achievement candidate extraction)
    - timeline_normalize.txt (timeline normalization)
    - persona_pack.txt (chat persona generation)
    
    If the external ID already exists, returns the existing idol.
    Otherwise creates a new idol and queues an import job.
    """
    # Check if external ID already exists
    stmt = (
        select(IdolExternalId)
        .options(selectinload(IdolExternalId.idol).selectinload(Idol.import_jobs))
        .where(
            and_(
                IdolExternalId.provider == data.provider,
                IdolExternalId.external_id == data.externalId,
            )
        )
    )
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()

    if existing:
        # Staleness threshold: jobs not updated in 10 minutes are considered stale
        STALE_THRESHOLD_MINUTES = 10
        now = datetime.now(timezone.utc)
        stale_cutoff = now - timedelta(minutes=STALE_THRESHOLD_MINUTES)
        
        # Check if there's an active (non-stale) job
        active_statuses = ["queued", "running", "pending"]
        
        fresh_jobs = []
        stale_jobs = []
        
        for job in existing.idol.import_jobs:
            if job.status not in active_statuses:
                continue
            
            # Check if job is stale
            job_updated = job.updated_at
            if job_updated.tzinfo is None:
                job_updated = job_updated.replace(tzinfo=timezone.utc)
            
            if job_updated < stale_cutoff:
                stale_jobs.append(job)
            else:
                fresh_jobs.append(job)
        
        # Mark stale jobs as failed
        for stale_job in stale_jobs:
            logger.warning(
                f"[IDOL_IMPORT] Marking stale job {stale_job.id} as failed "
                f"(last updated: {stale_job.updated_at}, idol: {existing.idol.name})"
            )
            stale_job.status = "failed"
            stale_job.error_message = "Job timed out - worker may have crashed"
        
        if stale_jobs:
            await db.flush()
        
        if fresh_jobs:
            # Return existing idol with fresh active job
            return IdolImportResponse(
                idolId=existing.idol_id,
                jobId=fresh_jobs[0].id,
                status=fresh_jobs[0].status,
            )
        
        # Create new job for existing idol (either no active jobs or all were stale)
        job = IdolImportJob(
            user_id=current_user.id,
            idol_id=existing.idol_id,
            query_text=existing.idol.name,
            status="queued",
            step="queued",
            progress_percent=0,
        )
        db.add(job)
        await db.flush()
        
        # Trigger ingestion task
        from app.tasks.ingestion import run_idol_ingestion
        run_idol_ingestion.delay(job.id)
        
        logger.info(
            f"[IDOL_IMPORT] Created new job {job.id} for existing idol {existing.idol.name} "
            f"(stale jobs marked failed: {len(stale_jobs)})"
        )
        
        return IdolImportResponse(
            idolId=existing.idol_id,
            jobId=job.id,
            status="queued",
        )

    # Fetch entity details from provider
    if data.provider == "wikidata":
        entity_data = await fetch_entity_by_id(data.externalId)
        if not entity_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Entity {data.externalId} not found on {data.provider}",
            )
        
        name = entity_data.get("name", data.externalId)
        birth_date = entity_data.get("birth_date")
        wikipedia_url = entity_data.get("wikipedia_url")
        image_url = entity_data.get("image_url")
        domain = "general"  # Default domain
    elif data.provider == "llm":
        # LLM-sourced imports: use data passed in request (no external API)
        if not data.name:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Name is required for LLM-sourced imports",
            )
        
        name = data.name
        birth_date = data.birthDate
        wikipedia_url = data.wikipediaUrl
        image_url = None
        # Infer domain from occupations if available
        domain = data.occupations[0] if data.occupations else "general"
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported provider: {data.provider}",
        )

    # Create new idol
    idol = Idol(
        name=name,
        birth_date=birth_date,
        domain=domain,
        image_url=image_url,
    )
    db.add(idol)
    await db.flush()

    # Create external ID link
    external_id = IdolExternalId(
        idol_id=idol.id,
        provider=data.provider,
        external_id=data.externalId,
        wikipedia_url=wikipedia_url,
    )
    db.add(external_id)

    # Create import job
    job = IdolImportJob(
        user_id=current_user.id,
        idol_id=idol.id,
        query_text=name,
        status="queued",
        step="queued",
        progress_percent=0,
    )
    db.add(job)
    await db.flush()

    # Trigger ingestion task
    from app.tasks.ingestion import run_idol_ingestion
    run_idol_ingestion.delay(job.id)

    return IdolImportResponse(
        idolId=idol.id,
        jobId=job.id,
        status="queued",
    )


@router.get("/my", response_model=list[IdolProfileResponse])
async def get_my_idols(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> list[IdolProfileResponse]:
    """Return profiles for idols the current user has imported or selected."""
    jobs_result = await db.execute(
        select(IdolImportJob.idol_id)
        .where(
            IdolImportJob.user_id == current_user.id,
            IdolImportJob.idol_id.is_not(None),
        )
        .order_by(IdolImportJob.updated_at.desc())
    )

    idol_ids = []
    seen = set()
    for idol_id in jobs_result.scalars().all():
        if idol_id and idol_id not in seen:
            seen.add(idol_id)
            idol_ids.append(idol_id)

    if not idol_ids:
        return []

    profiles_result = await db.execute(
        select(IdolProfile).where(IdolProfile.idol_id.in_(idol_ids))
    )
    profiles_by_id = {
        profile.idol_id: profile for profile in profiles_result.scalars().all()
    }

    return [
        _profile_to_response(profiles_by_id[idol_id])
        for idol_id in idol_ids
        if idol_id in profiles_by_id
    ]


@router.post("/{idol_id}/select", status_code=status.HTTP_204_NO_CONTENT)
async def select_current_idol(
    idol_id: Annotated[str, Depends(_validate_idol_id)],
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> None:
    """Validate that an idol can be selected by the current user."""
    idol = await db.get(Idol, idol_id)
    if not idol:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )

    existing_job_result = await db.execute(
        select(IdolImportJob.id)
        .where(
            IdolImportJob.user_id == current_user.id,
            IdolImportJob.idol_id == idol_id,
        )
        .limit(1)
    )
    if existing_job_result.scalar_one_or_none() is None:
        job = IdolImportJob(
            user_id=current_user.id,
            idol_id=idol_id,
            query_text=idol.name,
            status="done",
            step="selected",
            progress_percent=100,
        )
        db.add(job)
        await db.commit()


@router.get("/{idol_id}", response_model=IdolDetailResponse)
async def get_idol(
    idol_id: Annotated[str, Depends(_validate_idol_id)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> IdolDetailResponse:
    """Get detailed information about an idol."""
    stmt = _published_only(
        select(Idol)
        .options(
            selectinload(Idol.aliases),
            selectinload(Idol.tag_links).selectinload(IdolTagLink.tag),
            selectinload(Idol.external_ids),
        )
        .where(Idol.id == idol_id)
    )
    result = await db.execute(stmt)
    idol = result.scalar_one_or_none()

    if not idol:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )

    return IdolDetailResponse(
        id=idol.id,
        name=idol.name,
        birth_date=idol.birth_date,
        domain=idol.domain,
        image_url=idol.image_url,
        imageSourceUrl=idol.image_source_url,
        imageLicense=idol.image_license,
        imageAttribution=idol.image_attribution_json,
        created_at=idol.created_at,
        aliases=[
            IdolAliasResponse(id=alias.id, alias_text=alias.alias_text)
            for alias in idol.aliases
        ],
        tags=[
            IdolTagResponse(id=link.tag.id, name=link.tag.name, type=link.tag.type)
            for link in idol.tag_links
        ],
        external_ids=[
            IdolExternalIdResponse(
                id=ext.id,
                provider=ext.provider,
                externalId=ext.external_id,
                wikipediaUrl=ext.wikipedia_url,
            )
            for ext in idol.external_ids
        ],
    )


# =============================================================================
# Profile Endpoint
# =============================================================================


@router.get("/{idol_id}/profile", response_model=IdolProfileResponse)
async def get_idol_profile(
    idol_id: Annotated[str, Depends(_validate_idol_id)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> IdolProfileResponse:
    """
    Get the extracted profile for an idol.
    
    Returns structured biographical data extracted from sources.
    """
    stmt = (
        select(IdolProfile)
        .where(IdolProfile.idol_id == idol_id)
    )
    result = await db.execute(stmt)
    profile = result.scalar_one_or_none()

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found. Import the idol first to generate a profile.",
        )

    return _profile_to_response(profile)


# =============================================================================
# Timeline Endpoint
# =============================================================================


@router.get("/{idol_id}/timeline", response_model=TimelineResponse)
async def get_idol_timeline(
    idol_id: Annotated[str, Depends(_validate_idol_id)],
    db: Annotated[AsyncSession, Depends(get_db)],
    age: int | None = Query(None, ge=0, le=150, description="Filter by age at event"),
    mode: str = Query("up_to", pattern="^(exact|up_to)$", description="Filter mode: 'exact' or 'up_to'"),
    category: str | None = Query(None, description="Filter by category"),
    limit: int = Query(50, ge=1, le=200, description="Maximum events to return"),
) -> TimelineResponse:
    """
    Get the timeline of events for an idol.
    
    Optionally filter by age (exact or up_to) and category.
    
    Parameters:
    - age: Target age to filter by
    - mode: 'exact' returns events at exactly that age, 'up_to' returns events up to and including that age
    - category: Filter by event category (career, learning, finance, impact, mindset, other)
    - limit: Maximum number of events to return
    """
    # First verify the idol exists
    idol_stmt = select(Idol).where(Idol.id == idol_id)
    idol_result = await db.execute(idol_stmt)
    idol = idol_result.scalar_one_or_none()
    
    if not idol:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )

    # Build query for timeline events
    stmt = (
        select(IdolTimelineEvent)
        .where(IdolTimelineEvent.idol_id == idol_id)
    )

    # Apply filters
    filters_applied = {}
    
    if age is not None:
        filters_applied["age"] = age
        filters_applied["mode"] = mode
        if mode == "exact":
            stmt = stmt.where(IdolTimelineEvent.age_at_event == age)
        else:  # up_to
            stmt = stmt.where(IdolTimelineEvent.age_at_event <= age)
    
    if category:
        filters_applied["category"] = category
        stmt = stmt.where(IdolTimelineEvent.category == category)

    # Order by age (nulls last), then by importance
    stmt = stmt.order_by(
        IdolTimelineEvent.age_at_event.nulls_last(),
        IdolTimelineEvent.importance_score.desc(),
    ).limit(limit)

    result = await db.execute(stmt)
    events = result.scalars().all()

    # Get total count (without limit)
    count_stmt = (
        select(func.count())
        .select_from(IdolTimelineEvent)
        .where(IdolTimelineEvent.idol_id == idol_id)
    )
    if age is not None:
        if mode == "exact":
            count_stmt = count_stmt.where(IdolTimelineEvent.age_at_event == age)
        else:
            count_stmt = count_stmt.where(IdolTimelineEvent.age_at_event <= age)
    if category:
        count_stmt = count_stmt.where(IdolTimelineEvent.category == category)
    
    count_result = await db.execute(count_stmt)
    total_count = count_result.scalar() or 0

    # Convert events to response format
    event_responses = []
    for event in events:
        # Convert evidence JSONB to response format
        evidence_list = []
        if isinstance(event.evidence, list):
            for ev in event.evidence:
                evidence_list.append(EvidenceResponse(
                    sourceId=ev.get("source_id", ""),
                    chunkIndex=ev.get("chunk_index", 0),
                    sourceUrl=ev.get("source_url", ""),
                    snippet=ev.get("snippet", ""),
                    confidence=ev.get("confidence", 0.0),
                ))

        event_responses.append(TimelineEventResponse(
            id=event.id,
            idolId=event.idol_id,
            canonicalTitle=event.canonical_title or "Untitled milestone",
            canonicalDescription=event.canonical_description or "",
            eventDate=event.event_date,
            datePrecision=_timeline_date_precision(event.date_precision),
            ageAtEvent=event.age_at_event,
            category=event.category or "other",
            importanceScore=event.importance_score or 0.5,
            confidence=event.confidence or 0.5,
            evidence=evidence_list,
            createdAt=event.created_at,
        ))

    return TimelineResponse(
        idolId=idol_id,
        idolName=idol.name,
        events=event_responses,
        totalEvents=total_count,
        filteredBy=filters_applied if filters_applied else None,
    )


# =============================================================================
# Persona Endpoint
# =============================================================================


@router.get("/{idol_id}/persona", response_model=IdolPersonaResponse)
async def get_idol_persona(
    idol_id: Annotated[str, Depends(_validate_idol_id)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> IdolPersonaResponse:
    """
    Get the chat persona for an idol.
    
    Returns persona data that can be used for AI-powered chat simulations.
    """
    stmt = (
        select(IdolPersona)
        .where(IdolPersona.idol_id == idol_id)
    )
    result = await db.execute(stmt)
    persona = result.scalar_one_or_none()

    if not persona:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Persona not found. Import the idol first to generate a persona.",
        )

    # Convert evidence JSONB to response format
    evidence_list = []
    if isinstance(persona.grounding_evidence, list):
        for ev in persona.grounding_evidence:
            evidence_list.append(EvidenceResponse(
                sourceId=ev.get("source_id", ""),
                chunkIndex=ev.get("chunk_index", 0),
                sourceUrl=ev.get("source_url", ""),
                snippet=ev.get("snippet", ""),
                confidence=ev.get("confidence", 0.0),
            ))

    return IdolPersonaResponse(
        id=persona.id,
        idolId=persona.idol_id,
        voiceStyle=persona.voice_style,
        principles=persona.principles or [],
        dos=persona.dos or [],
        donts=persona.donts or [],
        signaturePhrases=persona.signature_phrases or [],
        topicsOfStrength=persona.topics_of_strength or [],
        tabooTopics=persona.taboo_topics or [],
        groundingEvidence=evidence_list,
        disclaimer=persona.disclaimer,
        createdAt=persona.created_at,
    )

# =============================================================================
# Image Generation Endpoint
# =============================================================================

class ImageGenerationResponse(BaseModel):
    imageUrl: str
    sourceUrl: str | None = None
    licenseStatus: str | None = None
    attribution: dict | None = None

@router.post("/{idol_id}/generate-image", response_model=ImageGenerationResponse)
async def generate_idol_image(
    idol_id: Annotated[str, Depends(_validate_idol_id)],
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    age: int | None = Query(None, description="Age to depict the idol at (defaults to current age or 30)"),
) -> ImageGenerationResponse:
    """
    Resolve/cache a real Wikimedia/Wikipedia idol photo, with generated art as
    a compatibility fallback for older clients that call this endpoint.
    """
    from app.core.config import settings

    # 1. Fetch Idol
    stmt = (
        select(Idol)
        .options(selectinload(Idol.external_ids))
        .where(Idol.id == idol_id)
    )
    result = await db.execute(stmt)
    idol = result.scalar_one_or_none()

    if not idol:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )

    # 1.5. Idempotency Check: Don't generate if already exists
    if idol.image_url:
        logger.info(f"Avatar for {idol.name} already exists. Returning early.")
        return ImageGenerationResponse(
            imageUrl=idol.image_url,
            sourceUrl=idol.image_source_url,
            licenseStatus=idol.image_license,
            attribution=idol.image_attribution_json,
        )

    wikidata_qid = None
    wikipedia_url = None
    for external in idol.external_ids:
        if external.provider == "wikidata":
            wikidata_qid = external.external_id
        if external.wikipedia_url:
            wikipedia_url = external.wikipedia_url

    try:
        from app.services.idol_photos import get_or_resolve_idol_photo

        real_photo = await get_or_resolve_idol_photo(
            db,
            idol,
            wikidata_qid=wikidata_qid,
            wikipedia_url=wikipedia_url,
            hints=[idol.name, wikidata_qid or "", wikipedia_url or ""],
        )
        if real_photo and real_photo.get("image_url"):
            return ImageGenerationResponse(
                imageUrl=real_photo["image_url"],
                sourceUrl=real_photo.get("source_url"),
                licenseStatus=real_photo.get("license_status"),
                attribution=real_photo.get("attribution"),
            )
    except Exception as photo_err:
        logger.warning(f"Real photo resolution failed for {idol.name}: {photo_err}")

    # 2. Determine Age
    target_age = age
    if target_age is None:
        # Try to calculate current age if alive
        if idol.birth_date:
            today = datetime.now().date()
            target_age = today.year - idol.birth_date.year - (
                (today.month, today.day) < (idol.birth_date.month, idol.birth_date.day)
            )
            # Cap realistic maximum at 90 for cartoon appeal unless specified
            if target_age > 90:
                target_age = 90
        else:
            target_age = 30 # Default prime age

    # 3. Read Prompt Template
    try:
        import os
        # backend/app/api/v1/idols.py -> ... -> backend (root of python app)
        # We need to go up from backend to get to prompts if they are at the same level as backend dir
        # If structure is:
        # cmpys/
        #   backend/
        #   prompts/
        
        current_file = os.path.abspath(__file__)
        # Up 4 levels: v1 -> api -> app -> backend
        backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(current_file))))
        # Up 1 more level to cmpys root
        project_root = os.path.dirname(backend_dir)
        
        prompt_path = os.path.join(project_root, "prompts", "image_generate.txt")
        
        with open(prompt_path, "r") as f:
            prompt_template = f.read()
    except FileNotFoundError:
        logger.error(f"prompts/image_generate.txt not found at {prompt_path}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Image generation prompt missing",
        )
    # 4. Generate safe physical description
    if not settings.gemini_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Gemini API key not configured",
        )

    try:
        client = genai.Client(api_key=settings.gemini_api_key)
        
        # Step 4a: Pre-process the prompt to extract historically accurate physical attributes
        try:
            bypass_prompt = (
                f"Describe {idol.name} at age {target_age} in exactly 2 short sentences. "
                f"Sentence 1: Their hair color/style, build, and most distinctive facial feature. "
                f"Sentence 2: What they typically wore at that age. "
                f"Do NOT use their name in your response. Start directly with 'He' or 'She'."
            )
            description_response = await client.aio.models.generate_content(
                model=settings.gemini_fast_model,
                contents=bypass_prompt
            )
            safe_description = description_response.text.strip()
            
            # Also get a role description for context
            role_prompt = f"In one short phrase, describe {idol.name}'s profession without using their name. Example: 'a visionary tech entrepreneur'"
            role_response = await client.aio.models.generate_content(
                model=settings.gemini_fast_model,
                contents=role_prompt
            )
            role_context = role_response.text.strip().strip('"').strip("'")
            
            prompt = prompt_template.replace("{idol_description}", safe_description).replace("{age}", str(target_age)).replace("{idol_name}", role_context)
        except Exception as bypass_e:
            logger.warning(f"Failed to generate historical description for {idol.name}: {bypass_e}")
            prompt = prompt_template.replace("{idol_description}", "").replace("{age}", str(target_age)).replace("{idol_name}", idol.name)

        # 5. Call Gemini Imagen 4
        print(f"FINAL PROMPT TO IMAGEN: {prompt}")
        response = await client.aio.models.generate_images(
            model="imagen-4.0-generate-001",
            prompt=prompt,
            config=types.GenerateImagesConfig(
                number_of_images=1,
                output_mime_type="image/jpeg",
                aspect_ratio="1:1",
                person_generation="ALLOW_ADULT"
            )
        )

        if not response.generated_images:
             raise Exception("No image returned from Gemini")

        image_bytes = response.generated_images[0].image.image_bytes
        
        # 6. Save bytes locally
        filename = f"{str(idol.id)}_{int(time.time())}.jpg"
        filepath = os.path.join("media", filename)
        with open(filepath, "wb") as f:
            f.write(image_bytes)

        # Ensure image URL is relative (e.g. /media/...) so Flutter can use Env.apiBaseUrl 
        # to properly route requests from Android Emulator or iOS Simulator correctly
        image_url = f"/api/v1/media/{filename}" if hasattr(settings, 'api_url') else f"/media/{filename}"
        
        # 7. Save to DB
        idol.image_url = image_url
        idol.image_license = "generated"
        idol.image_attribution_json = {
            "provider": "gemini_imagen",
            "note": "Generated fallback avatar; real Wikimedia photo was unavailable.",
        }
        db.add(idol)
        await db.commit()

        return ImageGenerationResponse(
            imageUrl=image_url,
            licenseStatus=idol.image_license,
            attribution=idol.image_attribution_json,
        )

    except Exception as e:
        logger.exception(f"Image generation failed for {idol.name}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Image generation failed: {str(e)}",
        )
