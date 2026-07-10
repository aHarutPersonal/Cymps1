"""Budgeted 24/7 catalog scheduler.

Celery Beat calls ``catalog_tick``. The tick seeds work from pending catalog
rows, recovers stale leases, and dispatches a small, daily-capped batch. Heavy
network/LLM work runs in ``process_catalog_job`` on the dedicated catalog queue.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import func, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.core.celery import celery_app
from app.core.config import settings
from app.core.db import async_session_maker
from app.models.content_resource import ContentResource, ContentResourceKind
from app.models.feed_post import FeedPost
from app.models.idol import CatalogStatus, Idol
from app.models.idol_job import IdolImportJob
from app.models.idol_profile import IdolProfile
from app.models.ingest_job import IngestJob, IngestKind, IngestState
from app.models.llm_usage_event import LLMUsageEvent
from app.models.verified_quote import QuoteVerificationState, VerifiedQuote

logger = logging.getLogger(__name__)

BOOK_JOB_SOURCE = "book_module_v2"
IDOL_JOB_SOURCE = "idol_profile_v2"
QUOTE_JOB_SOURCE = "wikiquote_v1"
QUOTE_VERIFICATION_JOB_SOURCE = "gemini_grounded_quote_v1"


def retry_delay_seconds(attempts: int) -> int:
    """Five minutes, doubling per failure, capped at six hours."""
    return min(300 * (2 ** max(attempts - 1, 0)), 6 * 60 * 60)


async def _insert_job(
    db,
    *,
    kind: IngestKind,
    source: str,
    external_id: str,
    payload: dict,
    priority: int,
) -> str | None:
    job_id = str(uuid4())
    stmt = (
        pg_insert(IngestJob)
        .values(
            id=job_id,
            kind=kind.value,
            source=source,
            external_id=external_id,
            payload_json=payload,
            priority=priority,
            state=IngestState.QUEUED.value,
            attempts=0,
        )
        .on_conflict_do_nothing(constraint="uq_ingest_identity")
        .returning(IngestJob.id)
    )
    result = await db.execute(stmt)
    return result.scalar_one_or_none()


@celery_app.task(name="app.tasks.catalog.enqueue_catalog_book")
def enqueue_catalog_book(
    title: str,
    author: str | None,
    user_goal: str | None = None,
    source_context: str | None = None,
    priority: int = 80,
) -> dict:
    """Idempotently add one user-demanded book to the tracked catalog queue."""
    return asyncio.run(
        _enqueue_catalog_book_async(
            title=title,
            author=author,
            user_goal=user_goal,
            source_context=source_context,
            priority=priority,
        )
    )


async def _enqueue_catalog_book_async(
    *,
    title: str,
    author: str | None,
    user_goal: str | None,
    source_context: str | None,
    priority: int,
) -> dict:
    from app.services.content_resources import canonical_book_key

    canonical_key = canonical_book_key(title, author)
    async with async_session_maker() as db:
        job_id = await _insert_job(
            db,
            kind=IngestKind.BOOK,
            source=BOOK_JOB_SOURCE,
            external_id=canonical_key,
            payload={
                "title": title,
                "author": author,
                # Stored for audit only. The shared module generator deliberately
                # uses a neutral goal and never bakes this user's goal into cache.
                "requested_goal": user_goal,
                "source_context": source_context,
            },
            priority=priority,
        )
        await db.commit()

    # Wake the dispatcher immediately; Beat remains the recovery mechanism.
    catalog_tick.apply_async(queue="catalog_control")
    return {"queued": bool(job_id), "job_id": job_id, "canonical_key": canonical_key}


@celery_app.task(name="app.tasks.catalog.catalog_tick")
def catalog_tick() -> dict:
    if not settings.catalog_scheduler_enabled:
        return {"status": "disabled"}
    return asyncio.run(_catalog_tick_async())


async def _catalog_tick_async() -> dict:
    from app.services.llm.budget import (
        budget_allows_job,
        get_daily_background_budget_status,
        job_budget_reserve_usd,
    )

    now = datetime.now(timezone.utc)
    stale_before = now - timedelta(minutes=settings.catalog_stale_job_minutes)
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    seeded = 0
    recovered = 0

    async with async_session_maker() as db:
        stale_result = await db.execute(
            select(IngestJob)
            .where(
                IngestJob.state == IngestState.RUNNING,
                IngestJob.locked_at.is_not(None),
                IngestJob.locked_at < stale_before,
            )
            .with_for_update(skip_locked=True)
        )
        for job in stale_result.scalars().all():
            job.locked_at = None
            if job.attempts >= settings.catalog_max_attempts:
                job.state = IngestState.FAILED
                job.completed_at = now
            else:
                job.state = IngestState.QUEUED
                job.next_attempt_at = now
            recovered += 1

        idol_result = await db.execute(
            select(Idol)
            .outerjoin(IdolProfile, IdolProfile.idol_id == Idol.id)
            .where(
                Idol.status == CatalogStatus.PENDING,
                IdolProfile.id.is_(None),
            )
            .order_by(Idol.created_at.asc())
            .limit(settings.catalog_seed_per_tick)
        )
        for idol in idol_result.scalars().all():
            inserted = await _insert_job(
                db,
                kind=IngestKind.IDOL,
                source=IDOL_JOB_SOURCE,
                external_id=str(idol.id),
                payload={"idol_id": str(idol.id), "name": idol.name},
                priority=100,
            )
            seeded += int(bool(inserted))

        remaining_seed = max(settings.catalog_seed_per_tick - seeded, 0)
        if remaining_seed:
            book_result = await db.execute(
                select(ContentResource)
                .where(
                    ContentResource.status == CatalogStatus.PENDING,
                    ContentResource.kind.in_(
                        [
                            ContentResourceKind.PUBLIC_DOMAIN_BOOK,
                            ContentResourceKind.LLM_BOOK_SUMMARY,
                        ]
                    ),
                )
                .order_by(ContentResource.created_at.asc())
                .limit(remaining_seed)
            )
            for resource in book_result.scalars().all():
                inserted = await _insert_job(
                    db,
                    kind=IngestKind.BOOK,
                    source=BOOK_JOB_SOURCE,
                    external_id=resource.canonical_key,
                    payload={
                        "content_resource_id": str(resource.id),
                        "title": resource.title,
                        "author": resource.author_or_creator,
                    },
                    priority=50,
                )
                seeded += int(bool(inserted))

        verification_started_today = int(
            (
                await db.execute(
                    select(func.count(IngestJob.id)).where(
                        IngestJob.source == QUOTE_VERIFICATION_JOB_SOURCE,
                        IngestJob.last_started_at.is_not(None),
                        IngestJob.last_started_at >= day_start,
                    )
                )
            ).scalar_one()
            or 0
        )
        verification_active = int(
            (
                await db.execute(
                    select(func.count(IngestJob.id)).where(
                        IngestJob.source == QUOTE_VERIFICATION_JOB_SOURCE,
                        IngestJob.state.in_([IngestState.QUEUED, IngestState.RUNNING]),
                    )
                )
            ).scalar_one()
            or 0
        )
        if (
            settings.catalog_quote_verification_enabled
            and settings.gemini_api_key
            and verification_started_today
            < settings.catalog_quote_verification_daily_limit
            and verification_active == 0
        ):
            verification_result = await db.execute(
                select(VerifiedQuote)
                .outerjoin(FeedPost, FeedPost.quote_id == VerifiedQuote.id)
                .where(
                    VerifiedQuote.status == CatalogStatus.PUBLISHED,
                    VerifiedQuote.verification_state
                    == QuoteVerificationState.SOURCE_BACKED,
                )
                .order_by(
                    FeedPost.like_count.desc().nullslast(),
                    VerifiedQuote.confidence.desc(),
                    VerifiedQuote.created_at.asc(),
                )
                .limit(settings.catalog_quote_verification_batch_size)
            )
            quotes_to_verify = list(verification_result.scalars().all())
            if quotes_to_verify:
                quote_ids = [str(quote.id) for quote in quotes_to_verify]
                inserted = await _insert_job(
                    db,
                    kind=IngestKind.QUOTE_VERIFICATION,
                    source=QUOTE_VERIFICATION_JOB_SOURCE,
                    external_id=",".join(quote_ids),
                    payload={"quote_ids": quote_ids},
                    priority=65,
                )
                seeded += int(bool(inserted))

        remaining_seed = max(settings.catalog_seed_per_tick - seeded, 0)
        if remaining_seed:
            existing_quote = select(VerifiedQuote.id).where(
                VerifiedQuote.idol_id == Idol.id
            ).exists()
            quote_idol_result = await db.execute(
                select(Idol)
                .where(
                    Idol.status == CatalogStatus.PUBLISHED,
                    ~existing_quote,
                )
                .order_by(Idol.quality_score.desc(), Idol.created_at.asc())
                .limit(remaining_seed)
            )
            for idol in quote_idol_result.scalars().all():
                inserted = await _insert_job(
                    db,
                    kind=IngestKind.QUOTE,
                    source=QUOTE_JOB_SOURCE,
                    external_id=str(idol.id),
                    payload={"idol_id": str(idol.id), "name": idol.name},
                    # This path has no LLM cost, so let it run before book jobs.
                    priority=70,
                )
                seeded += int(bool(inserted))

        started_today = int(
            (
                await db.execute(
                    select(func.count(IngestJob.id)).where(
                        IngestJob.last_started_at.is_not(None),
                        IngestJob.last_started_at >= day_start,
                    )
                )
            ).scalar_one()
            or 0
        )
        capacity = max(settings.catalog_daily_job_limit - started_today, 0)
        dispatch_limit = min(settings.catalog_dispatch_per_tick, capacity)
        dispatched_ids: list[str] = []
        budget_deferred = 0
        budget_status = await get_daily_background_budget_status(db, now=now)
        projected_spend = budget_status.committed_usd
        if dispatch_limit:
            due_result = await db.execute(
                select(IngestJob)
                .where(
                    IngestJob.state == IngestState.QUEUED,
                    IngestJob.attempts < settings.catalog_max_attempts,
                    or_(
                        IngestJob.next_attempt_at.is_(None),
                        IngestJob.next_attempt_at <= now,
                    ),
                )
                .order_by(IngestJob.priority.desc(), IngestJob.created_at.asc())
                # Look beyond expensive high-priority rows so zero-cost quote
                # imports can continue even after the LLM budget pauses.
                .limit(max(dispatch_limit * 20, 50))
                .with_for_update(skip_locked=True)
            )
            for job in due_result.scalars().all():
                if len(dispatched_ids) >= dispatch_limit:
                    break
                if not budget_allows_job(
                    kind=job.kind,
                    status=budget_status,
                    projected_spend_usd=projected_spend,
                ):
                    budget_deferred += 1
                    continue
                job.state = IngestState.RUNNING
                job.attempts += 1
                job.locked_at = now
                job.last_started_at = now
                job.next_attempt_at = None
                dispatched_ids.append(str(job.id))
                projected_spend += job_budget_reserve_usd(job.kind)

        await db.commit()

    for job_id in dispatched_ids:
        process_catalog_job.apply_async(args=[job_id], queue="catalog")

    return {
        "status": "ok",
        "seeded": seeded,
        "recovered": recovered,
        "dispatched": len(dispatched_ids),
        "daily_started": started_today,
        "daily_limit": settings.catalog_daily_job_limit,
        "background_budget_state": budget_status.state,
        "background_spent_usd": budget_status.spent_usd,
        "background_reserved_usd": budget_status.reserved_usd,
        "background_budget_usd": budget_status.limit_usd,
        "budget_deferred": budget_deferred,
    }


@celery_app.task(name="app.tasks.catalog.process_catalog_job")
def process_catalog_job(job_id: str) -> dict:
    return asyncio.run(_process_catalog_job_async(job_id))


async def _process_catalog_job_async(job_id: str) -> dict:
    try:
        async with async_session_maker() as db:
            job = await db.get(IngestJob, job_id)
            if job is None:
                return {"status": "missing", "job_id": job_id}
            if job.state != IngestState.RUNNING:
                return {"status": "ignored", "state": job.state.value}
            kind = job.kind
            payload = dict(job.payload_json or {})

            # Second check closes the window between Beat dispatch and worker
            # execution. Source-only quote imports always pass with zero reserve.
            from app.services.llm.budget import (
                budget_allows_job,
                get_daily_background_budget_status,
            )

            budget_status = await get_daily_background_budget_status(
                db,
                exclude_running_job_id=job_id,
            )
            if not budget_allows_job(
                kind=kind,
                status=budget_status,
                projected_spend_usd=budget_status.committed_usd,
            ):
                now = datetime.now(timezone.utc)
                tomorrow = (now + timedelta(days=1)).replace(
                    hour=0, minute=1, second=0, microsecond=0
                )
                job.state = IngestState.QUEUED
                job.attempts = max(job.attempts - 1, 0)
                job.locked_at = None
                job.next_attempt_at = tomorrow
                job.last_error = f"deferred: background_budget_{budget_status.state}"
                await db.commit()
                return {
                    "status": "deferred_budget",
                    "job_id": job_id,
                    "budget_state": budget_status.state,
                    "next_attempt_at": tomorrow.isoformat(),
                }

        if kind == IngestKind.BOOK:
            result = await _process_book_job(job_id, payload)
        elif kind == IngestKind.IDOL:
            result = await _process_idol_job(job_id, payload)
        elif kind == IngestKind.QUOTE:
            result = await _process_quote_job(job_id, payload)
        elif kind == IngestKind.QUOTE_VERIFICATION:
            result = await _process_quote_verification_job(job_id, payload)
        else:
            raise RuntimeError(f"Unsupported catalog job kind: {kind}")
        return result
    except Exception as exc:
        logger.exception("[CATALOG] Job %s failed", job_id)
        return await _record_failure(job_id, str(exc))


async def _process_book_job(job_id: str, payload: dict) -> dict:
    from app.services.content_resources import (
        SHARED_BOOK_GOAL,
        get_or_create_book_module_resource,
    )

    title = str(payload.get("title") or "").strip()
    author = payload.get("author")
    if not title:
        raise RuntimeError("Book job is missing title")

    async with async_session_maker() as db:
        resource = await get_or_create_book_module_resource(
            db,
            title=title,
            author=str(author) if author else None,
            user_goal=SHARED_BOOK_GOAL,
            source_context=None,
        )
        job = await db.get(IngestJob, job_id)
        if job is None:
            raise RuntimeError("Catalog job disappeared during book generation")
        job.state = (
            IngestState.DONE
            if resource.status == CatalogStatus.PUBLISHED
            else IngestState.FLAGGED
        )
        job.completed_at = datetime.now(timezone.utc)
        job.locked_at = None
        job.last_error = None
        await db.commit()
        return {
            "status": job.state.value,
            "job_id": job_id,
            "content_resource_id": str(resource.id),
            "canonical_key": resource.canonical_key,
        }


async def _process_idol_job(job_id: str, payload: dict) -> dict:
    idol_id = str(payload.get("idol_id") or "")
    if not idol_id:
        raise RuntimeError("Idol job is missing idol_id")

    async with async_session_maker() as db:
        idol = await db.get(Idol, idol_id)
        if idol is None:
            raise RuntimeError(f"Idol not found: {idol_id}")
        existing_profile = await db.scalar(
            select(IdolProfile.id).where(IdolProfile.idol_id == idol_id)
        )
        if existing_profile and idol.status == CatalogStatus.PUBLISHED:
            job = await db.get(IngestJob, job_id)
            job.state = IngestState.DONE
            job.completed_at = datetime.now(timezone.utc)
            job.locked_at = None
            await db.commit()
            return {"status": "done", "idol_id": idol_id, "reused": True}

        import_job = IdolImportJob(
            user_id=None,
            idol_id=idol_id,
            query_text=idol.name,
            status="queued",
            step="queued",
            progress_percent=0,
        )
        db.add(import_job)
        await db.flush()
        import_job_id = str(import_job.id)
        await db.commit()

    from app.tasks.ingestion import _run_ingestion_async

    ingestion_result = await _run_ingestion_async(import_job_id)
    if ingestion_result.get("error"):
        raise RuntimeError(str(ingestion_result["error"]))

    async with async_session_maker() as db:
        idol = await db.get(Idol, idol_id)
        job = await db.get(IngestJob, job_id)
        if idol is None or job is None:
            raise RuntimeError("Catalog state disappeared after idol ingestion")
        job.state = (
            IngestState.DONE
            if idol.status == CatalogStatus.PUBLISHED
            else IngestState.FLAGGED
        )
        job.completed_at = datetime.now(timezone.utc)
        job.locked_at = None
        job.last_error = None
        await db.commit()
        return {
            "status": job.state.value,
            "job_id": job_id,
            "idol_id": idol_id,
            "quality_score": idol.quality_score,
        }


async def _process_quote_job(job_id: str, payload: dict) -> dict:
    """Fetch and persist only source-backed quotes for one published idol."""
    from app.providers.wikiquote import fetch_wikiquote_page, parse_wikiquote_page

    idol_id = str(payload.get("idol_id") or "")
    idol_name = str(payload.get("name") or "").strip()
    if not idol_id or not idol_name:
        raise RuntimeError("Quote job is missing idol identity")

    page = await fetch_wikiquote_page(idol_name)
    parsed = parse_wikiquote_page(page) if page else []
    candidates = [
        item
        for item in parsed
        if item.confidence >= settings.catalog_quote_min_confidence
    ][: settings.catalog_quotes_per_idol_limit]
    now = datetime.now(timezone.utc)

    async with async_session_maker() as db:
        idol = await db.get(Idol, idol_id)
        job = await db.get(IngestJob, job_id)
        if idol is None or job is None:
            raise RuntimeError("Catalog state disappeared during quote ingestion")

        candidate_hashes = [
            VerifiedQuote.compute_hash(idol.name, item.text) for item in candidates
        ]
        existing_hashes: set[str] = set()
        if candidate_hashes:
            existing_hashes = set(
                (
                    await db.execute(
                        select(VerifiedQuote.normalized_hash).where(
                            VerifiedQuote.normalized_hash.in_(candidate_hashes)
                        )
                    )
                ).scalars()
            )

        created = 0
        for item, normalized_hash in zip(candidates, candidate_hashes):
            if normalized_hash in existing_hashes:
                continue
            db.add(
                VerifiedQuote(
                    idol_id=idol.id,
                    speaker=idol.name,
                    text=item.text,
                    normalized_hash=normalized_hash,
                    quote_type=item.quote_type,
                    language="en",
                    category=item.category,
                    context=item.section,
                    source_title=item.source_title,
                    source_url=item.source_url,
                    source_reference=item.source_reference,
                    source_provider="wikiquote",
                    confidence=item.confidence,
                    evidence_json={
                        "wikiquote_section": item.section,
                        "reference": item.source_reference,
                        "parser_version": QUOTE_JOB_SOURCE,
                    },
                    status=CatalogStatus.PUBLISHED,
                    published_at=now,
                )
            )
            existing_hashes.add(normalized_hash)
            created += 1

        await db.flush()
        total_for_idol = int(
            (
                await db.execute(
                    select(func.count(VerifiedQuote.id)).where(
                        VerifiedQuote.idol_id == idol.id,
                        VerifiedQuote.status == CatalogStatus.PUBLISHED,
                    )
                )
            ).scalar_one()
            or 0
        )
        job.state = IngestState.DONE if total_for_idol else IngestState.FLAGGED
        job.completed_at = now
        job.locked_at = None
        job.last_error = None if total_for_idol else "No source-backed Wikiquote entries found"
        await db.commit()
        return {
            "status": job.state.value,
            "job_id": job_id,
            "idol_id": idol_id,
            "created": created,
            "published_total": total_for_idol,
            "source_page": page.url if page else None,
        }


async def _process_quote_verification_job(job_id: str, payload: dict) -> dict:
    """Cross-check a small source-backed batch and persist usage telemetry."""
    from app.services.quote_verification import verify_quote_batch

    requested_ids = [str(value) for value in payload.get("quote_ids", []) if value]
    if not requested_ids:
        raise RuntimeError("Quote verification job has no quote_ids")

    async with async_session_maker() as db:
        result = await db.execute(
            select(VerifiedQuote).where(VerifiedQuote.id.in_(requested_ids))
        )
        by_id = {str(quote.id): quote for quote in result.scalars().all()}
        quotes = [by_id[quote_id] for quote_id in requested_ids if quote_id in by_id]
    if not quotes:
        raise RuntimeError("Quote verification batch no longer exists")

    run = await verify_quote_batch(quotes)
    now = datetime.now(timezone.utc)
    state_counts: dict[str, int] = {}

    async with async_session_maker() as db:
        from app.services.llm.pricing import PRICING_VERSION, estimate_cost_usd

        job = await db.get(IngestJob, job_id)
        if job is None:
            raise RuntimeError("Catalog job disappeared during quote verification")
        usage_event = LLMUsageEvent(
            operation="quote_verification",
            provider="gemini",
            model=run.model,
            prompt_tokens=run.prompt_tokens,
            completion_tokens=run.completion_tokens,
            total_tokens=run.total_tokens,
            estimated_cost_usd=estimate_cost_usd(
                model=run.model,
                prompt_tokens=run.prompt_tokens,
                completion_tokens=run.completion_tokens,
                total_tokens=run.total_tokens,
                grounded=True,
                search_queries=run.search_queries,
            ),
            duration_ms=run.duration_ms,
            grounded=True,
            search_queries=run.search_queries,
            success=run.error is None,
            error_code="invalid_response" if run.error else None,
            result_status="invalid_response" if run.error else "checked",
            metadata_json={
                "quote_count": len(quotes),
                "grounded_source_count": len(run.grounded_sources),
                "job_id": job_id,
                "pricing_version": PRICING_VERSION,
            },
        )
        db.add(usage_event)
        if run.error:
            await db.commit()
            raise RuntimeError(run.error)

        current_result = await db.execute(
            select(VerifiedQuote).where(VerifiedQuote.id.in_(requested_ids))
        )
        current_by_id = {
            str(quote.id): quote for quote in current_result.scalars().all()
        }
        grounded_sources = [
            {"title": source.title, "url": source.url}
            for source in run.grounded_sources[:20]
        ]
        for check in run.results:
            quote = current_by_id.get(check.quote_id)
            if quote is None:
                continue
            quote.verification_state = check.state
            quote.verification_confidence = check.confidence
            quote.verification_model = run.model
            quote.verification_attempted_at = now
            quote.verified_source_title = check.evidence_title
            quote.verified_source_url = check.evidence_url
            quote.verification_json = {
                "canonical_text": check.canonical_text,
                "explanation": check.explanation,
                "grounded_sources": grounded_sources,
                "search_queries": run.search_queries,
                "prompt_tokens": run.prompt_tokens,
                "completion_tokens": run.completion_tokens,
            }
            if check.state == QuoteVerificationState.VERIFIED:
                quote.verified_at = now
                quote.status = CatalogStatus.PUBLISHED
            elif check.state == QuoteVerificationState.REJECTED:
                quote.verified_at = None
                quote.status = CatalogStatus.FLAGGED
            state_counts[check.state.value] = state_counts.get(check.state.value, 0) + 1

        decisive_count = state_counts.get("verified", 0) + state_counts.get("rejected", 0)
        usage_event.quality_score = decisive_count / max(len(run.results), 1)
        usage_event.metadata_json = {
            **(usage_event.metadata_json or {}),
            "states": state_counts,
        }

        job.state = IngestState.DONE
        job.completed_at = now
        job.locked_at = None
        job.last_error = None
        await db.commit()
        return {
            "status": "done",
            "job_id": job_id,
            "checked": len(run.results),
            "states": state_counts,
            "model": run.model,
            "prompt_tokens": run.prompt_tokens,
            "completion_tokens": run.completion_tokens,
            "search_queries": run.search_queries,
            "duration_ms": round(run.duration_ms, 1),
        }


async def _record_failure(job_id: str, error: str) -> dict:
    now = datetime.now(timezone.utc)
    async with async_session_maker() as db:
        job = await db.get(IngestJob, job_id)
        if job is None:
            return {"status": "missing", "error": error}
        job.last_error = error[:4000]
        job.locked_at = None
        if job.attempts >= settings.catalog_max_attempts:
            job.state = IngestState.FAILED
            job.completed_at = now
        else:
            job.state = IngestState.QUEUED
            job.next_attempt_at = now + timedelta(
                seconds=retry_delay_seconds(job.attempts)
            )
        await db.commit()
        return {
            "status": job.state.value,
            "job_id": job_id,
            "attempts": job.attempts,
            "next_attempt_at": (
                job.next_attempt_at.isoformat() if job.next_attempt_at else None
            ),
            "error": job.last_error,
        }
