"""Best-effort persistence for LLM usage and downstream quality outcomes."""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.llm_usage_event import LLMUsageEvent

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class UsageRecord:
    operation: str
    model: str
    provider: str
    prompt_tokens: int | None = None
    completion_tokens: int | None = None
    total_tokens: int | None = None
    estimated_cost_usd: float | None = None
    duration_ms: float | None = None
    grounded: bool = False
    search_queries: int = 0
    success: bool = True
    error_code: str | None = None
    result_status: str | None = None
    quality_score: float | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
    event_id: str | None = None


def infer_provider(model: str | None) -> str:
    lowered = (model or "").casefold()
    if settings.llm_provider == "openlux":
        return "openlux"
    if settings.llm_provider == "yunwu":
        return "yunwu"
    if "gemini" in lowered:
        return "gemini"
    if lowered.startswith(("gpt-", "o1", "o3", "o4")):
        return "openai"
    return settings.llm_provider if settings.llm_provider != "dummy" else "unknown"


def usage_record_from_response(
    *,
    operation: str,
    response,
    model: str | None = None,
    grounded: bool = False,
    search_queries: int = 0,
    result_status: str | None = None,
    quality_score: float | None = None,
    metadata: dict[str, Any] | None = None,
) -> UsageRecord:
    resolved_model = str(getattr(response, "model", None) or model or "unknown")
    prompt_tokens = getattr(response, "prompt_tokens", None)
    completion_tokens = getattr(response, "completion_tokens", None)
    total_tokens = getattr(response, "total_tokens", None)
    if total_tokens is None and (prompt_tokens is not None or completion_tokens is not None):
        total_tokens = int(prompt_tokens or 0) + int(completion_tokens or 0)
    error = getattr(response, "error", None)
    return UsageRecord(
        operation=operation,
        model=resolved_model,
        provider=str(getattr(response, "provider", None) or infer_provider(resolved_model)),
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
        event_id=getattr(response, "attempt_id", None),
        duration_ms=getattr(response, "duration_ms", None),
        grounded=grounded,
        search_queries=search_queries,
        success=not bool(error),
        error_code="llm_error" if error else None,
        result_status=result_status,
        quality_score=quality_score,
        metadata={
            **(metadata or {}),
            **({"trace_id": response.trace_id, "attempt_id": response.attempt_id}
               if getattr(response, "attempt_id", None) else {}),
            **{key: getattr(response, key) for key in (
                "first_event_ms", "first_content_ms", "response_chars", "admission_wait_ms", "cached_prompt_tokens", "effective_parameters",
                "transport_success", "json_valid", "semantic_accepted", "critical_defect",
            ) if getattr(response, key, None) is not None},
            **(
                {"finish_reason": response.finish_reason}
                if getattr(response, "finish_reason", None)
                else {}
            ),
            **(
                {"thoughts_tokens": response.thoughts_tokens}
                if getattr(response, "thoughts_tokens", None) is not None
                else {}
            ),
            **({"error": str(error)[:500]} if error else {}),
            **(
                {
                    "fallback_from_model": response.fallback_from_model,
                    "fallback_from_provider": response.fallback_from_provider,
                    "fallback_error": str(response.fallback_error)[:500],
                }
                if getattr(response, "fallback_from_model", None)
                else {}
            ),
        },
    )


def _event(record: UsageRecord) -> LLMUsageEvent:
    from app.services.llm.pricing import PRICING_VERSION, estimate_cost_usd

    estimated_cost = record.estimated_cost_usd
    usage_unknown = (
        record.prompt_tokens is None
        and record.completion_tokens is None
        and record.total_tokens is None
        and record.estimated_cost_usd is None
    )
    if estimated_cost is None and not usage_unknown:
        estimated_cost = estimate_cost_usd(
            model=record.model,
            provider=record.provider,
            prompt_tokens=record.prompt_tokens,
            completion_tokens=record.completion_tokens,
            total_tokens=record.total_tokens,
            grounded=record.grounded,
            search_queries=record.search_queries,
        )
    event = LLMUsageEvent(
        operation=record.operation,
        provider=record.provider,
        model=record.model,
        prompt_tokens=record.prompt_tokens,
        completion_tokens=record.completion_tokens,
        total_tokens=record.total_tokens,
        estimated_cost_usd=estimated_cost,
        duration_ms=record.duration_ms,
        grounded=record.grounded,
        search_queries=record.search_queries,
        success=record.success,
        error_code=record.error_code,
        result_status=record.result_status,
        quality_score=record.quality_score,
        metadata_json={**record.metadata, "pricing_version": PRICING_VERSION,
                       "usage_unknown": usage_unknown},
    )
    if record.event_id:
        event.id = record.event_id
    return event


async def record_usage_records(
    records: list[UsageRecord],
    *,
    db: AsyncSession | None = None,
) -> bool:
    """Persist records without ever failing the operation being measured."""
    records = [record for record in records if record.model != "unknown"]
    if not settings.llm_usage_telemetry_enabled or not records:
        return False
    async def persist(session):
        new_events = []
        for record in records:
            event = _event(record)
            if record.event_id:
                await session.merge(event)
            else:
                new_events.append(event)
        if new_events:
            session.add_all(new_events)
    try:
        if db is not None:
            # Isolate best-effort telemetry in a SAVEPOINT so a missing table
            # or transient insert failure cannot poison the caller's main
            # transaction (plan/feed/content writes must still commit).
            async with db.begin_nested():
                await persist(db)
                await db.flush()
            return True

        from app.core.db import async_session_maker

        async with async_session_maker() as telemetry_db:
            await persist(telemetry_db)
            await telemetry_db.commit()
            return True
    except Exception as exc:  # pragma: no cover - depends on external DB state
        logger.warning("[LLM_USAGE] Could not persist telemetry: %s", exc)
        return False


async def record_llm_response(
    *,
    operation: str,
    response,
    db: AsyncSession | None = None,
    model: str | None = None,
    grounded: bool = False,
    search_queries: int = 0,
    result_status: str | None = None,
    quality_score: float | None = None,
    metadata: dict[str, Any] | None = None,
) -> bool:
    return await record_usage_records(
        [
            usage_record_from_response(
                operation=operation,
                response=response,
                model=model,
                grounded=grounded,
                search_queries=search_queries,
                result_status=result_status,
                quality_score=quality_score,
                metadata=metadata,
            )
        ],
        db=db,
    )
