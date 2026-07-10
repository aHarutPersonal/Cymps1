"""
Idol ingestion task for collecting sources and extracting achievements.

Multi-step LLM extraction pipeline:
1. Collect Wikipedia sources and chunk text
2. Extract profile from sources
3. Extract achievement candidates
4. Normalize timeline with age computation
5. Generate persona pack
6. Store all extracted data
"""
import asyncio
import logging
import re
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.celery import celery_app
from app.core.db import async_session_maker
from app.models.achievement_evidence import AchievementEvidence
from app.models.idol import CatalogStatus, Idol
from app.models.idol_achievement import DatePrecision, IdolAchievement
from app.models.idol_external_id import IdolExternalId
from app.models.idol_job import IdolImportJob
from app.models.idol_persona import IdolPersona
from app.models.idol_profile import IdolProfile
from app.models.idol_source import IdolSource
from app.models.idol_timeline import IdolTimelineEvent
from app.models.source_chunk import SourceChunk
from app.providers.wikipedia import WikipediaContent, chunk_text, fetch_wikipedia_content
from app.services.ingestion.extract import (
    run_achievements_extraction,
    run_persona_pack,
    run_profile_extraction,
    run_timeline_normalization,
)
from app.services.content_quality import (
    MIN_PLAN_DETAIL_LESSON_WORDS,
    MIN_PLAN_DETAIL_MATERIAL_WORDS,
)
from app.services.llm.schemas import (
    AchievementsExtractionResponse,
    PersonaPackResponse,
    ProfileExtractionResponse,
    TimelineNormalizationResponse,
)

logger = logging.getLogger(__name__)


def _idol_catalog_quality(
    *,
    profile_confidence: float,
    profile_evidence_count: int,
    timeline_events: list,
    persona_generated: bool,
    persona_evidence_count: int,
) -> tuple[float, bool]:
    """Require source evidence, not merely model-reported confidence."""
    event_count = len(timeline_events)
    evidence_backed_events = sum(
        1
        for event in timeline_events
        if float(getattr(event, "confidence", 0.0)) >= 0.55
        and bool(getattr(event, "evidence", None))
    )
    evidence_backed_ratio = evidence_backed_events / event_count if event_count else 0.0
    score = (
        min(max(profile_confidence, 0.0), 1.0) * 0.35
        + (0.15 if profile_evidence_count >= 1 else 0.0)
        + min(event_count / 6, 1.0) * 0.15
        + evidence_backed_ratio * 0.25
        + (0.10 if persona_generated and persona_evidence_count >= 1 else 0.0)
    )
    score = round(score, 3)
    publishable = (
        profile_confidence >= 0.60
        and profile_evidence_count >= 1
        and evidence_backed_events >= 2
        and score >= 0.70
    )
    return score, publishable


def sanitize_for_postgres(data: Any) -> Any:
    """
    Sanitize data for PostgreSQL storage by removing null characters (\u0000)
    and other problematic Unicode sequences that PostgreSQL cannot store.
    
    PostgreSQL text/JSONB fields cannot contain null bytes.
    """
    if isinstance(data, str):
        # Remove null characters and other problematic control characters
        # \u0000 is the null character that PostgreSQL rejects
        sanitized = data.replace('\u0000', '')
        # Also remove other potentially problematic control characters (C0 controls except common ones)
        # Keep: \t (tab), \n (newline), \r (carriage return)
        sanitized = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', sanitized)
        return sanitized
    elif isinstance(data, dict):
        return {k: sanitize_for_postgres(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [sanitize_for_postgres(item) for item in data]
    else:
        return data


@celery_app.task(bind=True)
def run_idol_ingestion(self, job_id: str) -> dict:
    """
    Run the idol ingestion pipeline.
    
    Steps:
    1. collecting_sources - Fetch Wikipedia content
    2. extracting_profile - Extract canonical profile
    3. extracting_achievements - Extract achievement candidates
    4. normalizing_timeline - Normalize and dedupe timeline
    5. generating_persona - Generate chat persona
    6. finalizing - Store data and mark complete
    """
    logger.info(f"[INGESTION] Starting ingestion task for job_id={job_id}")
    try:
        result = asyncio.get_event_loop().run_until_complete(_run_ingestion_async(job_id))
        logger.info(f"[INGESTION] Completed job_id={job_id}, result={result}")
        return result
    except Exception as e:
        logger.exception(f"[INGESTION] Fatal error in job_id={job_id}: {e}")
        raise


async def _run_ingestion_async(job_id: str) -> dict:
    """Async implementation of the ingestion pipeline."""
    logger.info(f"[INGESTION] Starting async pipeline for job_id={job_id}")
    
    async with async_session_maker() as db:
        # Fetch job with idol and external IDs
        logger.debug("[INGESTION] Fetching job from database...")
        stmt = (
            select(IdolImportJob)
            .options(
                selectinload(IdolImportJob.idol).selectinload(Idol.external_ids),
            )
            .where(IdolImportJob.id == job_id)
        )
        result = await db.execute(stmt)
        job = result.scalar_one_or_none()

        if not job:
            logger.error(f"[INGESTION] Job {job_id} not found in database")
            return {"error": "Job not found"}

        logger.info(f"[INGESTION] Found job for idol: {job.idol.name if job.idol else 'NO IDOL'}")

        if not job.idol:
            logger.error(f"[INGESTION] No idol associated with job {job_id}")
            await _update_job(db, job, status="failed", step="error", error_message="No idol associated")
            return {"error": "No idol associated with job"}

        try:
            # =================================================================
            # Step 1: Collecting sources (0-20%)
            # =================================================================
            logger.info(f"[INGESTION][{job_id}] Step 1/6: Collecting sources...")
            await _update_job(
                db, job, 
                status="running", 
                step="collecting_sources", 
                progress=5,
                thought=f"I'm searching for reliable sources about {job.idol.name}..."
            )

            wikipedia_url = _get_wikipedia_url(job.idol.external_ids)
            wikidata_qid = _get_wikidata_qid(job.idol.external_ids)
            logger.info(f"[INGESTION][{job_id}] Wikipedia URL: {wikipedia_url}, Wikidata QID: {wikidata_qid}")
            
            source = await _collect_wikipedia_source(db, job.idol, wikipedia_url)

            if not source:
                logger.error(f"[INGESTION][{job_id}] Failed to fetch Wikipedia content")
                await _update_job(
                    db, job, status="failed", step="error",
                    error_message="Failed to fetch Wikipedia content",
                    progress=10
                )
                return {"error": "Failed to fetch Wikipedia content"}

            logger.info(f"[INGESTION][{job_id}] Source collected: {source.title} ({len(source.full_text or '')} chars)")
            await _update_job(
                db, job, 
                step="collecting_sources", 
                progress=20,
                thought=f"Found {source.title}. Reading through {len(source.full_text or '')} characters of text..."
            )

            # Load chunks for extraction
            chunks = await _load_chunks(db, source.id)
            logger.info(f"[INGESTION][{job_id}] Created {len(chunks)} chunks from source")
            if not chunks:
                logger.error(f"[INGESTION][{job_id}] No chunks created from source")
                await _update_job(
                    db, job, status="failed", step="error",
                    error_message="No chunks created from source",
                    progress=25
                )
                return {"error": "No chunks created from source"}

            # =================================================================
            # Steps 2+3: Extract profile AND achievements in parallel
            # =================================================================
            logger.info(f"[INGESTION][{job_id}] Steps 2-3/6: Extracting profile and achievements in parallel...")
            await _update_job(
                db, job, 
                step="extracting_profile", 
                progress=25,
            )

            # Generate natural thinking stream (LLM) concurrently
            try:
                import openai
                from app.core.config import settings as app_settings
                
                if app_settings.openai_api_key:
                    initial_history = job.thinking_text or ""
                    idol_name = job.idol.name
                    
                    # Prepare preview of text content for the LLM to "read"
                    text_preview = "\n\n".join([c.text[:500] for c in chunks[:3]])
                    
                    async def _generate_thinking_stream_concurrently():
                        try:
                            # Use an independent DB session to avoid ConcurrentModificationError
                            async with async_session_maker() as stream_db:
                                # Fetch a fresh instance for this session
                                stream_stmt = select(IdolImportJob).where(IdolImportJob.id == job_id)
                                stream_res = await stream_db.execute(stream_stmt)
                                stream_job = stream_res.scalar_one_or_none()
                                
                                if not stream_job:
                                    return
                                    
                                thinking_system = (
                                    f"You are an expert biographer researching {idol_name}. "
                                    "You are reading source material to extract facts. "
                                    "Think out loud about the SPECIFIC FACTS you are finding in the text. "
                                    "Do NOT describe your search strategy. "
                                    "Instead, say 'I found...' or 'Interesting, the text mentions...'. "
                                    "Use markdown bold (**text**) for key dates, names, and terms."
                                )
                                
                                thinking_prompt = (
                                    f"Here is the text content I am reading:\n\n{text_preview}\n\n"
                                    "Narrate your discovery process based on this text. What specific details jumped out?"
                                )
                                
                                openai_client = openai.AsyncOpenAI(api_key=app_settings.openai_api_key)
                                
                                stream = await openai_client.chat.completions.create(
                                    model="gpt-4o-mini",
                                    messages=[
                                        {"role": "system", "content": thinking_system},
                                        {"role": "user", "content": thinking_prompt},
                                    ],
                                    stream=True,
                                    max_tokens=120,
                                    temperature=0.7,
                                )
                                
                                import asyncio
                                accumulated_stream = ""
                                buffer = ""
                                last_update_time = asyncio.get_event_loop().time()

                                async for chunk in stream:
                                    delta = chunk.choices[0].delta
                                    if delta.content:
                                        content_piece = delta.content
                                        accumulated_stream += content_piece
                                        buffer += content_piece
                                        
                                        current_time = asyncio.get_event_loop().time()
                                        
                                        # Buffer updates (every 20 chars or 200ms)
                                        if len(buffer) >= 20 or (current_time - last_update_time) > 0.2:
                                            sep = "\n" if initial_history else ""
                                            stream_job.thinking_text = f"{initial_history}{sep}{accumulated_stream}"
                                            await stream_db.commit()
                                            buffer = ""
                                            last_update_time = current_time
                                            
                                # Final flush
                                if buffer:
                                    sep = "\n" if initial_history else ""
                                    stream_job.thinking_text = f"{initial_history}{sep}{accumulated_stream}"
                                    await stream_db.commit()
                        except Exception as e:
                            logger.warning(f"[INGESTION][{job_id}] Concurrent thinking stream failed: {e}")

                    # Start thinking generation in the background!
                    logger.info(f"[INGESTION][{job_id}] Starting concurrent thinking stream...")
                    asyncio.create_task(_generate_thinking_stream_concurrently())
            except Exception as e:
                logger.warning(f"[INGESTION][{job_id}] Failed to start thinking stream: {e}")
                # Fallback to static update if LLM fails
                await _update_job(
                    db, job, 
                    thought=f"Now analyzing {len(chunks)} text chunks to extract profile and achievements concurrently..."
                )

            # Run profile and achievements extraction concurrently
            profile_task = run_profile_extraction(
                chunks=chunks,
                source_url=source.url,
                source_id=source.id,
                idol_name=job.idol.name,
                wikidata_qid=wikidata_qid,
                wikipedia_url=wikipedia_url,
            )
            achievements_task = run_achievements_extraction(
                chunks=chunks,
                source_url=source.url,
                source_id=source.id,
                idol_name=job.idol.name,
            )

            # Wait for both to complete
            profile_response, achievements_response = await asyncio.gather(
                profile_task, achievements_task
            )

            # Handle profile result
            if not profile_response:
                logger.warning(f"[INGESTION][{job_id}] Profile extraction failed, using fallback")
                profile_response = _create_fallback_profile(job.idol, source)
            else:
                logger.info(f"[INGESTION][{job_id}] Profile extracted: {profile_response.profile.display_name}")

            # Handle achievements result
            if not achievements_response:
                logger.warning(f"[INGESTION][{job_id}] Achievements extraction failed, using fallback")
                achievements_response = _create_fallback_achievements()
            else:
                logger.info(f"[INGESTION][{job_id}] Extracted {len(achievements_response.candidates)} achievement candidates")

            await _update_job(
                db, job, 
                step="extracting_achievements", 
                progress=55,
                thought=f"Found {len(achievements_response.candidates)} potential achievements. Now validating..."
            )

            # =================================================================
            # Steps 4+5: Normalize timeline AND Generate persona IN PARALLEL
            # =================================================================
            logger.info(f"[INGESTION][{job_id}] Steps 4-5/6: Timeline + Persona in parallel...")
            await _update_job(
                db, job, 
                step="normalizing_timeline", 
                progress=60,
                thought="Building timeline and generating persona concurrently..."
            )

            timeline_task = run_timeline_normalization(
                profile=profile_response,
                candidates=achievements_response,
            )
            persona_task = run_persona_pack(
                profile=profile_response,
                chunks=chunks,
                source_url=source.url,
                source_id=source.id,
            )

            timeline_response, persona_response = await asyncio.gather(
                timeline_task, persona_task
            )

            # Handle timeline result
            if not timeline_response:
                logger.warning(f"[INGESTION][{job_id}] Timeline normalization failed, using fallback")
                timeline_response = _create_fallback_timeline(achievements_response)
            else:
                logger.info(f"[INGESTION][{job_id}] Normalized {len(timeline_response.timeline)} timeline events")

            # Handle persona result
            if persona_response:
                logger.info(f"[INGESTION][{job_id}] Persona generated: {persona_response.persona.voice_style[:50] if persona_response.persona.voice_style else 'N/A'}...")
            else:
                logger.warning(f"[INGESTION][{job_id}] Persona generation returned None")

            await _update_job(
                db, job, 
                step="generating_persona", 
                progress=85,
                thought=f"Timeline: {len(timeline_response.timeline)} events. Persona: {persona_response.persona.voice_style if persona_response else 'Default'}."
            )

            # =================================================================
            # Step 6: Store extracted data (85-100%)
            # =================================================================
            logger.info(f"[INGESTION][{job_id}] Step 6/6: Storing extracted data...")
            await _update_job(
                db, job, 
                step="storing_data", 
                progress=90,
                thought="Saving all extracted data to the database..."
            )

            # Store profile
            logger.debug(f"[INGESTION][{job_id}] Storing profile...")
            await _store_profile(db, job.idol, profile_response)

            # Store timeline events
            logger.debug(f"[INGESTION][{job_id}] Storing {len(timeline_response.timeline)} timeline events...")
            await _store_timeline(db, job.idol, timeline_response, source)

            # Store persona
            if persona_response:
                logger.debug(f"[INGESTION][{job_id}] Storing persona...")
                await _store_persona(db, job.idol, persona_response)

            quality_score, publishable = _idol_catalog_quality(
                profile_confidence=profile_response.profile.confidence,
                profile_evidence_count=len(profile_response.profile.evidence),
                timeline_events=timeline_response.timeline,
                persona_generated=persona_response is not None,
                persona_evidence_count=(
                    len(persona_response.persona.grounding_evidence)
                    if persona_response
                    else 0
                ),
            )
            job.idol.quality_score = quality_score
            if profile_response.profile.domains and job.idol.domain in {"", "unknown"}:
                job.idol.domain = profile_response.profile.domains[0]
            job.idol.status = (
                CatalogStatus.PUBLISHED if publishable else CatalogStatus.FLAGGED
            )
            job.idol.published_at = datetime.now(timezone.utc) if publishable else None

            await _update_job(db, job, step="storing_data", progress=95)

            # =================================================================
            # Finalize
            # =================================================================
            logger.info(f"[INGESTION][{job_id}] ✅ Pipeline completed successfully!")
            await _update_job(
                db, job,
                status="completed",
                step="done",
                progress=100,
                thought=f"Research complete! {job.idol.name} is ready."
            )

            result = {
                "status": "completed",
                "idol_id": job.idol_id,
                "profile_extracted": profile_response is not None,
                "achievements_count": len(achievements_response.candidates) if achievements_response else 0,
                "timeline_events": len(timeline_response.timeline) if timeline_response else 0,
                "persona_generated": persona_response is not None,
                "catalog_status": job.idol.status.value,
                "quality_score": quality_score,
            }
            logger.info(f"[INGESTION][{job_id}] Final result: {result}")
            
            # NOTE: IdeaCards pre-generation was removed here. The task it
            # enqueued imported app.api.v1.idea_cards, which no longer exists,
            # so every enqueue crashed a worker with ModuleNotFoundError.
            # Daily insights are served by GET /sessions/{id}/feed (cached
            # per day) instead.

            return result

        except Exception as e:
            logger.exception(f"Ingestion failed for job {job_id}")
            await _update_job(
                db, job,
                status="failed",
                step="error",
                error_message=str(e)
            )
            return {"error": str(e)}


# =============================================================================
# Helper Functions
# =============================================================================


async def _update_job(
    db,
    job: IdolImportJob,
    status: str | None = None,
    step: str | None = None,
    progress: int | None = None,
    error_message: str | None = None,
    thought: str | None = None,
) -> None:
    """Update job status and progress."""
    if status:
        job.status = status
    if step:
        job.step = step
    if progress is not None:
        job.progress_percent = progress
    if error_message:
        job.error_message = error_message
    
    if thought:
        # Append thinking text
        current = job.thinking_text or ""
        if current:
            job.thinking_text = current + "\n" + thought
        else:
            job.thinking_text = thought

    logger.debug(f"[INGESTION][{job.id}] Job update: status={job.status}, step={job.step}, progress={job.progress_percent}%, thought={thought}")
    await db.commit()


def _get_wikipedia_url(external_ids: list[IdolExternalId]) -> str | None:
    """Get Wikipedia URL from external IDs."""
    for ext_id in external_ids:
        if ext_id.wikipedia_url:
            return ext_id.wikipedia_url
    return None


def _get_wikidata_qid(external_ids: list[IdolExternalId]) -> str | None:
    """Get Wikidata QID from external IDs."""
    for ext_id in external_ids:
        if ext_id.provider == "wikidata":
            return ext_id.external_id
    return None


async def _collect_wikipedia_source(
    db,
    idol: Idol,
    wikipedia_url: str | None,
) -> IdolSource | None:
    """Fetch Wikipedia content and store as source with chunks."""
    content: WikipediaContent | None = None

    if wikipedia_url:
        content = await fetch_wikipedia_content(wikipedia_url=wikipedia_url)

    if not content:
        content = await fetch_wikipedia_content(title=idol.name)

    if not content or not content.full_text:
        return None

    # Sanitize title (remove HTML tags)
    clean_title = re.sub(r'<[^>]+>', '', content.title)

    source = IdolSource(
        idol_id=idol.id,
        source_type="wikipedia",
        url=content.url,
        title=sanitize_for_postgres(clean_title),
        summary_text=sanitize_for_postgres(content.summary),
        full_text=sanitize_for_postgres(content.full_text),
    )
    db.add(source)
    await db.flush()

    sanitized_full_text = sanitize_for_postgres(content.full_text)
    chunks = chunk_text(sanitized_full_text, min_size=900, max_size=1200)

    for idx, chunk_text_content in enumerate(chunks):
        chunk = SourceChunk(
            source_id=source.id,
            chunk_index=idx,
            text=chunk_text_content,  # Already sanitized via sanitized_full_text
        )
        db.add(chunk)

    await db.commit()
    return source


async def _load_chunks(db, source_id: str) -> list[SourceChunk]:
    """Load and return sorted chunks for a source."""
    stmt = (
        select(SourceChunk)
        .where(SourceChunk.source_id == source_id)
        .order_by(SourceChunk.chunk_index)
    )
    result = await db.execute(stmt)
    return list(result.scalars().all())


# =============================================================================
# Fallback Creators (when LLM fails)
# =============================================================================


def _create_fallback_profile(idol: Idol, source: IdolSource) -> ProfileExtractionResponse:
    """Create a minimal profile from available data."""
    from app.services.llm.schemas import Evidence, ExtractedProfile, ProfileExtractionResponse
    
    return ProfileExtractionResponse(
        profile=ExtractedProfile(
            display_name=idol.name,
            short_description=source.summary_text,
            birth_date=idol.birth_date,
            domains=[idol.domain] if idol.domain else [],
            wikipedia_url=source.url,
            confidence=0.5,
            evidence=[
                Evidence(
                    source_id=source.id,
                    chunk_index=0,
                    source_url=source.url,
                    snippet=source.summary_text[:200] if source.summary_text else "",
                    confidence=0.5,
                )
            ] if source.summary_text else [],
        )
    )


def _create_fallback_achievements() -> AchievementsExtractionResponse:
    """Create empty achievements response."""
    from app.services.llm.schemas import AchievementsExtractionResponse
    return AchievementsExtractionResponse(candidates=[])


def _create_fallback_timeline(
    achievements: AchievementsExtractionResponse,
) -> TimelineNormalizationResponse:
    """Create timeline from achievements without normalization."""
    from app.services.llm.schemas import TimelineEvent, TimelineNormalizationResponse
    
    events = []
    for c in achievements.candidates:
        events.append(TimelineEvent(
            canonical_title=c.title,
            canonical_description=c.description,
            date=c.date,
            date_precision=c.date_precision,
            age_at_event=c.age_at_event,
            category=c.category,
            importance_score=0.5,
            confidence=c.confidence,
            evidence=c.evidence,
        ))
    
    return TimelineNormalizationResponse(timeline=events, dedupe_notes=[])


# =============================================================================
# Data Storage
# =============================================================================


async def _store_profile(
    db,
    idol: Idol,
    profile_response: ProfileExtractionResponse,
) -> IdolProfile:
    """Store extracted profile data."""
    p = profile_response.profile
    
    # Check for existing profile
    stmt = select(IdolProfile).where(IdolProfile.idol_id == idol.id)
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()
    
    if existing:
        # Update existing
        existing.display_name = sanitize_for_postgres(p.display_name)
        existing.short_description = sanitize_for_postgres(p.short_description)
        existing.birth_date = p.birth_date
        existing.death_date = p.death_date
        existing.nationality = sanitize_for_postgres(p.nationality)
        existing.domains = sanitize_for_postgres(p.domains)
        existing.primary_roles = sanitize_for_postgres(p.primary_roles)
        existing.era_tags = sanitize_for_postgres(p.era_tags)
        existing.notable_themes = sanitize_for_postgres(p.notable_themes)
        existing.wikipedia_url = p.wikipedia_url
        existing.confidence = p.confidence
        existing.evidence = sanitize_for_postgres([e.model_dump(mode="json") for e in p.evidence])
        profile = existing
    else:
        # Create new
        profile = IdolProfile(
            idol_id=idol.id,
            display_name=sanitize_for_postgres(p.display_name),
            short_description=sanitize_for_postgres(p.short_description),
            birth_date=p.birth_date,
            death_date=p.death_date,
            nationality=sanitize_for_postgres(p.nationality),
            domains=sanitize_for_postgres(p.domains),
            primary_roles=sanitize_for_postgres(p.primary_roles),
            era_tags=sanitize_for_postgres(p.era_tags),
            notable_themes=sanitize_for_postgres(p.notable_themes),
            wikipedia_url=p.wikipedia_url,
            confidence=p.confidence,
            evidence=sanitize_for_postgres([e.model_dump(mode="json") for e in p.evidence]),
        )
        db.add(profile)
    
    # Also update idol birth_date if extracted
    if p.birth_date and not idol.birth_date:
        idol.birth_date = p.birth_date
    
    await db.commit()
    return profile


async def _store_timeline(
    db,
    idol: Idol,
    timeline_response: TimelineNormalizationResponse,
    source: IdolSource,
) -> list[IdolTimelineEvent]:
    """Store timeline events."""
    # Delete existing timeline events
    stmt = select(IdolTimelineEvent).where(IdolTimelineEvent.idol_id == idol.id)
    result = await db.execute(stmt)
    existing = result.scalars().all()
    for e in existing:
        await db.delete(e)
    
    events = []
    for t in timeline_response.timeline:
        # Map category string to DatePrecision enum for date_precision
        date_precision = DatePrecision.UNKNOWN
        if t.date_precision.value == "day":
            date_precision = DatePrecision.DAY
        elif t.date_precision.value == "month":
            date_precision = DatePrecision.MONTH
        elif t.date_precision.value == "year":
            date_precision = DatePrecision.YEAR
        
        event = IdolTimelineEvent(
            idol_id=idol.id,
            canonical_title=sanitize_for_postgres(t.canonical_title),
            canonical_description=sanitize_for_postgres(t.canonical_description),
            event_date=t.date,
            date_precision=date_precision,
            age_at_event=t.age_at_event,
            category=t.category.value,
            importance_score=t.importance_score,
            confidence=t.confidence,
            evidence=sanitize_for_postgres([e.model_dump(mode="json") for e in t.evidence]),
        )
        db.add(event)
        events.append(event)
        
        # Also create IdolAchievement for backward compatibility
        achievement = IdolAchievement(
            idol_id=idol.id,
            title=sanitize_for_postgres(t.canonical_title),
            description=sanitize_for_postgres(t.canonical_description),
            achievement_date=t.date,
            date_precision=date_precision,
            age_at_achievement=t.age_at_event,
            category=t.category.value,
            importance_score=t.importance_score,
            confidence_score=t.confidence,
        )
        db.add(achievement)
        await db.flush()
        
        # Add evidence
        for ev in t.evidence:
            evidence_record = AchievementEvidence(
                achievement_id=achievement.id,
                source_title=sanitize_for_postgres(source.title),
                source_url=ev.source_url,
                snippet=sanitize_for_postgres(ev.snippet),
                confidence_score=ev.confidence,
            )
            db.add(evidence_record)
    
    await db.commit()
    return events


async def _store_persona(
    db,
    idol: Idol,
    persona_response: PersonaPackResponse,
) -> IdolPersona:
    """Store persona data."""
    p = persona_response.persona
    
    # Check for existing
    stmt = select(IdolPersona).where(IdolPersona.idol_id == idol.id)
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()
    
    # Prepare era-aware fields (with fallback for older LLM responses)
    era_context = getattr(p, 'era_context', None)
    era_context_value = era_context.value if era_context and hasattr(era_context, 'value') else (era_context or 'contemporary')
    
    lexicon_allow = getattr(p, 'lexicon_allow', None) or []
    lexicon_ban = getattr(p, 'lexicon_ban', None) or []
    
    worldview_adapter = getattr(p, 'worldview_adapter', None)
    worldview_adapter_dict = worldview_adapter.model_dump() if worldview_adapter and hasattr(worldview_adapter, 'model_dump') else (worldview_adapter or {})
    
    default_frameworks = getattr(p, 'default_frameworks', None) or []
    
    if existing:
        # Update
        existing.voice_style = sanitize_for_postgres(p.voice_style)
        existing.principles = sanitize_for_postgres(p.principles)
        existing.dos = sanitize_for_postgres(p.dos)
        existing.donts = sanitize_for_postgres(p.donts)
        existing.signature_phrases = sanitize_for_postgres(p.signature_phrases)
        existing.topics_of_strength = sanitize_for_postgres(p.topics_of_strength)
        existing.taboo_topics = sanitize_for_postgres(p.taboo_topics)
        existing.grounding_evidence = sanitize_for_postgres([e.model_dump(mode="json") for e in p.grounding_evidence])
        existing.disclaimer = sanitize_for_postgres(p.disclaimer)
        # New era-aware fields
        existing.era_context = sanitize_for_postgres(era_context_value)
        existing.lexicon_allow = sanitize_for_postgres(lexicon_allow)
        existing.lexicon_ban = sanitize_for_postgres(lexicon_ban)
        existing.worldview_adapter = sanitize_for_postgres(worldview_adapter_dict)
        existing.default_frameworks = sanitize_for_postgres(default_frameworks)
        persona = existing
    else:
        # Create
        persona = IdolPersona(
            idol_id=idol.id,
            voice_style=sanitize_for_postgres(p.voice_style),
            principles=sanitize_for_postgres(p.principles),
            dos=sanitize_for_postgres(p.dos),
            donts=sanitize_for_postgres(p.donts),
            signature_phrases=sanitize_for_postgres(p.signature_phrases),
            topics_of_strength=sanitize_for_postgres(p.topics_of_strength),
            taboo_topics=sanitize_for_postgres(p.taboo_topics),
            grounding_evidence=sanitize_for_postgres([e.model_dump(mode="json") for e in p.grounding_evidence]),
            disclaimer=sanitize_for_postgres(p.disclaimer),
            # New era-aware fields
            era_context=sanitize_for_postgres(era_context_value),
            lexicon_allow=sanitize_for_postgres(lexicon_allow),
            lexicon_ban=sanitize_for_postgres(lexicon_ban),
            worldview_adapter=sanitize_for_postgres(worldview_adapter_dict),
            default_frameworks=sanitize_for_postgres(default_frameworks),
        )
        db.add(persona)
    
    await db.commit()
    return persona


# =============================================================================
# Plan Item Details Regeneration Task
# =============================================================================

def _validate_plan_item_details_schema(details: dict) -> list[str]:
    """
    Validate the JSON schema for plan item details.
    
    Accepts both the prompt schema (instruction, kind) and normalized schema (description, type).
    
    Returns list of validation errors (empty if valid).
    """
    errors = []
    
    # Check steps
    if "steps" not in details:
        errors.append("Missing 'steps' array")
    elif not isinstance(details["steps"], list):
        errors.append("'steps' must be an array")
    elif len(details["steps"]) == 0:
        errors.append("'steps' array is empty")
    else:
        for i, step in enumerate(details["steps"]):
            if not isinstance(step, dict):
                errors.append(f"steps[{i}] must be an object")
                continue
            if "title" not in step:
                errors.append(f"steps[{i}] missing 'title'")
            # Accept either 'description' or 'instruction' (from prompt schema)
            # Normalization will handle mapping
    
    # Check materials (optional but should be array if present)
    if "materials" in details:
        if not isinstance(details["materials"], list):
            errors.append("'materials' must be an array")
        else:
            for i, material in enumerate(details["materials"]):
                if not isinstance(material, dict):
                    errors.append(f"materials[{i}] must be an object")
                    continue
                if "title" not in material:
                    errors.append(f"materials[{i}] missing 'title'")
                # Accept either 'type' or 'kind' (from prompt schema)
                # Normalization will handle mapping
    
    return errors


def _normalize_plan_item_details(details: dict) -> dict:
    """
    Normalize plan item details from `plan_item_details.txt` output schema.

    New schema (plan_item_details.txt):
      { steps: [{id, title, description, estimate_minutes, substeps: [str...]}],
        materials: [{title, type, url, reason}],
        definition_of_done, mental_model }

    Legacy schema (micro_steps):
      { mental_model, micro_steps: [str...], definition_of_done, common_trap }

    Output storage schema:
      { steps: [{id, title, description, estimate_minutes, substeps, completed}],
        materials: [{title, type, url, reason}],
        meta: {mental_model, definition_of_done, ...} }
    """
    import re

    # --- Handle legacy micro_steps schema ---
    if "micro_steps" in details and "steps" not in details:
        micro_steps: list = details.get("micro_steps", [])
        steps = []
        for i, step_text in enumerate(micro_steps):
            step_str = str(step_text).strip()
            match = re.match(r"^step\s*\d+[:\-]\s*(.+)$", step_str, re.IGNORECASE)
            title = match.group(1)[:80] if match else step_str[:80]
            steps.append({
                "id": f"step_{i + 1}",
                "title": title,
                "description": step_str,
                "substeps": [],
            })
        details["steps"] = steps
        details.pop("micro_steps", None)

    # --- Normalize `steps` array ---
    if "steps" in details:
        for i, step in enumerate(details["steps"]):
            # Ensure ID
            if "id" not in step or not step["id"]:
                step["id"] = f"step_{i + 1}"
            # Map instruction -> description
            if "description" not in step and "instruction" in step:
                step["description"] = step.pop("instruction")
            elif "description" not in step:
                step["description"] = step.get("expected_output", "")
            # Preserve substeps — normalize bare strings to descriptive objects if needed
            if "substeps" not in step:
                step["substeps"] = []
            # Normalize estimate_minutes
            if "estimate_minutes" in step and "estimateMinutes" not in step:
                step["estimateMinutes"] = step.pop("estimate_minutes")
            # Ensure completion state defaults to false (never trust LLM on this)
            step.setdefault("completed", False)

    # --- Validate content depth ---
    min_lesson_words = MIN_PLAN_DETAIL_LESSON_WORDS
    min_material_words = MIN_PLAN_DETAIL_MATERIAL_WORDS

    # Flag steps with thin lesson_content (should be 500+ words per prompt)
    for step in details.get("steps", []):
        lesson = step.get("lesson_content", "")
        if lesson and len(lesson.split()) < min_lesson_words:
            logger.warning(
                f"[PLAN_DETAILS] Step '{step.get('title', '?')}' has thin lesson_content: "
                f"{len(lesson.split())} words (minimum {min_lesson_words})"
            )

    # --- Validate materials content depth ---
    for mat in details.get("materials", []):
        md = mat.get("content_markdown", "")
        if md and len(md.split()) < min_material_words:
            logger.warning(
                f"[PLAN_DETAILS] Material '{mat.get('title', '?')}' has thin content_markdown: "
                f"{len(md.split())} words (minimum {min_material_words})"
            )

    # --- Store meta fields ---
    meta = details.setdefault("meta", {})
    for key in ("mental_model", "definition_of_done", "common_trap"):
        if key in details:
            meta[key] = details.pop(key)

    # --- Ensure materials array exists ---
    if "materials" not in details:
        details["materials"] = []

    # --- Normalize materials ---
    valid_types = {"book", "article", "video", "tool", "course", "template", "in_app_lesson"}
    kind_to_type = {
        "in_app_lesson": "in_app_lesson",
        "search": "article",
        "link": "article",
        "book": "book",
        "video": "video",
        "course": "course",
        "tool": "tool",
        "template": "template",
    }

    normalized_materials = []
    for material in details.get("materials", []):
        if "type" not in material:
            kind = material.get("kind", "article")
            material["type"] = kind_to_type.get(kind, "article")
        if material.get("type") not in valid_types:
            material["type"] = "article"
        # Drop materials with no title (malformed)
        if not material.get("title"):
            continue
        # Preserve content_markdown for in-app lessons
        # (no need to strip — frontend handles it)
        normalized_materials.append(material)
    details["materials"] = normalized_materials

    return details


# =============================================================================
# IdeaCards Pre-generation Task (retired)
# =============================================================================
# The generator it delegated to (app.api.v1.idea_cards._generate_idea_cards)
# was removed, so this task crashed with ModuleNotFoundError on every run.
# Kept as a registered no-op so stale queued messages drain harmlessly instead
# of erroring; nothing enqueues it anymore.

@celery_app.task(bind=True)
def run_generate_idea_cards(self, idol_id: str, user_id: str) -> dict:
    logger.warning(
        f"[IDEA_CARDS_TASK] Retired task invoked (idol={idol_id}); ignoring. "
        "IdeaCards pre-generation was removed with app.api.v1.idea_cards."
    )
    return {"status": "retired"}
