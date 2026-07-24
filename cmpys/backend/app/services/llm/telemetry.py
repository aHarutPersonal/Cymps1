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


def infer_provider(model: str | None) -> str:
    lowered = (model or "").casefold()
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
        duration_ms=getattr(response, "duration_ms", None),
        grounded=grounded,
        search_queries=search_queries,
        success=not bool(error),
        error_code="llm_error" if error else None,
        result_status=result_status,
        quality_score=quality_score,
        metadata={
            **(metadata or {}),
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
    if estimated_cost is None:
        estimated_cost = estimate_cost_usd(
            model=record.model,
            provider=record.provider,
            prompt_tokens=record.prompt_tokens,
            completion_tokens=record.completion_tokens,
            total_tokens=record.total_tokens,
            grounded=record.grounded,
            search_queries=record.search_queries,
        )
    return LLMUsageEvent(
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
        metadata_json={**record.metadata, "pricing_version": PRICING_VERSION},
    )


async def record_usage_records(
    records: list[UsageRecord],
    *,
    db: AsyncSession | None = None,
) -> None:
    """Persist records without ever failing the operation being measured."""
    records = [record for record in records if record.model != "unknown"]
    if not settings.llm_usage_telemetry_enabled or not records:
        return
    try:
        if db is not None:
            # Isolate best-effort telemetry in a SAVEPOINT so a missing table
            # or transient insert failure cannot poison the caller's main
            # transaction (plan/feed/content writes must still commit).
            async with db.begin_nested():
                db.add_all([_event(record) for record in records])
                await db.flush()
            return

        from app.core.db import async_session_maker

        async with async_session_maker() as telemetry_db:
            telemetry_db.add_all([_event(record) for record in records])
            await telemetry_db.commit()
    except Exception as exc:  # pragma: no cover - depends on external DB state
        logger.warning("[LLM_USAGE] Could not persist telemetry: %s", exc)


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
) -> None:
    await record_usage_records(
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
