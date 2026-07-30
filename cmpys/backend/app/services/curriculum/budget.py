"""Separate daily spend guard for autonomous curriculum work."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import func, literal_column, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.curriculum import CurriculumGenerationJob
from app.models.llm_usage_event import LLMUsageEvent


CURRICULUM_OPERATIONS = frozenset(
    {
        "curriculum_grounded_research",
        "curriculum_research_curation",
        "curriculum_research_claim_verification",
        "curriculum_technique_plan",
        "curriculum_module_outline",
        "curriculum_module_draft",
        "curriculum_module_repair",
        "curriculum_review_structure",
        "curriculum_review_factual",
        "curriculum_review_pedagogy",
        "curriculum_review_originality",
        "curriculum_mentor_claim_curation",
        "curriculum_mentor_claim_verification",
    }
)


@dataclass(frozen=True, slots=True)
class CurriculumBudgetStatus:
    spent_usd: float
    reserved_usd: float
    committed_usd: float
    limit_usd: float
    soft_limit_usd: float
    state: str


@dataclass(frozen=True, slots=True)
class CurriculumJobUsage:
    """All persisted provider usage attributable to one durable curriculum job."""

    input_tokens: int
    output_tokens: int
    total_tokens: int
    estimated_cost_usd: float
    event_count: int
    failed_event_count: int
    operations: dict[str, dict[str, Any]]


_STAGE_RESERVE_USD = {
    "taxonomy": 0.0,
    "source_research": 0.06,
    "technique_design": 0.02,
    "outline": 0.03,
    "writing": 0.10,
    "factual_review": 0.025,
    "pedagogy_review": 0.025,
    "originality_review": 0.025,
    "publish": 0.0,
    "mentor_evidence": 0.05,
}
_ACTIVE_COST_RESERVATION_KEY = "_active_cost_reservation"
_CURRICULUM_JOB_ID_JSON_KEY = literal_column("'curriculum_job_id'")


def _utc_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _attempt_is_today(
    attempt: dict[str, Any],
    *,
    day_start: datetime,
    current: datetime,
) -> bool:
    reserved_at = _utc_datetime(attempt.get("reserved_at"))
    return reserved_at is not None and day_start <= reserved_at <= current


def _job_unreconciled_reserve_today(
    *,
    state: Any,
    estimated_cost_usd: Any,
    stored_cost_usd: Any,
    checkpoints: Any,
    authoritative_cost_usd: float,
    day_start: datetime,
    current: datetime,
) -> float:
    """Return today's conservative gap not represented by usage telemetry.

    Reconciled attempts live in ``cost_attempts``. A crashed attempt can still
    live in the active reservation even after its job becomes queued/retryable.
    The active reservation of a RUNNING job is omitted because callers already
    include the current lease reserve in ``reserved_usd``.
    """

    persisted_estimate = max(float(estimated_cost_usd or 0), 0.0)
    persisted_cost = max(float(stored_cost_usd or 0), 0.0)
    authoritative_cost = max(float(authoritative_cost_usd or 0), persisted_cost)
    total_unreconciled = max(persisted_estimate - authoritative_cost, 0.0)
    if total_unreconciled <= 0 or not isinstance(checkpoints, dict):
        return 0.0

    today_gap = 0.0
    attempts = checkpoints.get("cost_attempts")
    if isinstance(attempts, list):
        for attempt in attempts:
            if not isinstance(attempt, dict) or not _attempt_is_today(
                attempt,
                day_start=day_start,
                current=current,
            ):
                continue
            reserve = max(float(attempt.get("reserve_usd") or 0), 0.0)
            actual = max(float(attempt.get("actual_cost_usd") or 0), 0.0)
            today_gap += max(reserve - actual, 0.0)

    state_value = getattr(state, "value", state)
    active = checkpoints.get(_ACTIVE_COST_RESERVATION_KEY)
    if (
        state_value != "running"
        and isinstance(active, dict)
        and _attempt_is_today(active, day_start=day_start, current=current)
    ):
        reserve = max(float(active.get("reserve_usd") or 0), 0.0)
        cost_before = max(float(active.get("actual_cost_before_usd") or 0), 0.0)
        observed_attempt_cost = max(authoritative_cost - cost_before, 0.0)
        today_gap += max(reserve - observed_attempt_cost, 0.0)

    # The durable estimate is the upper bound for all conservative gaps. This
    # protects against duplicated/malformed history entries while subtracting
    # telemetry that arrived after a worker crash but before reconciliation.
    return round(min(today_gap, total_unreconciled), 8)


def _usage_by_curriculum_job_ids_statement(job_ids: list[str]):
    """Build the grouped ledger query with the partial-index predicate."""

    job_id_expression = LLMUsageEvent.metadata_json[_CURRICULUM_JOB_ID_JSON_KEY].astext
    return (
        select(
            job_id_expression,
            func.coalesce(func.sum(LLMUsageEvent.estimated_cost_usd), 0.0),
        )
        .where(
            LLMUsageEvent.operation.in_(CURRICULUM_OPERATIONS),
            LLMUsageEvent.metadata_json.has_key(_CURRICULUM_JOB_ID_JSON_KEY),
            job_id_expression.in_(job_ids),
        )
        .group_by(job_id_expression)
    )


def _usage_for_curriculum_job_statement(job_id: str):
    """Build the event query with the same partial-index predicate."""

    return select(
        LLMUsageEvent.operation,
        LLMUsageEvent.provider,
        LLMUsageEvent.model,
        LLMUsageEvent.prompt_tokens,
        LLMUsageEvent.completion_tokens,
        LLMUsageEvent.total_tokens,
        LLMUsageEvent.estimated_cost_usd,
        LLMUsageEvent.success,
    ).where(
        LLMUsageEvent.operation.in_(CURRICULUM_OPERATIONS),
        LLMUsageEvent.metadata_json.has_key(_CURRICULUM_JOB_ID_JSON_KEY),
        LLMUsageEvent.metadata_json[_CURRICULUM_JOB_ID_JSON_KEY].astext
        == str(job_id),
    )


async def _durable_unreconciled_reserve_today(
    db: AsyncSession,
    *,
    day_start: datetime,
    current: datetime,
) -> float:
    job_rows = (
        await db.execute(
            select(
                CurriculumGenerationJob.id,
                CurriculumGenerationJob.state,
                CurriculumGenerationJob.estimated_cost_usd,
                CurriculumGenerationJob.cost_usd,
                CurriculumGenerationJob.checkpoints_json,
            ).where(
                CurriculumGenerationJob.estimated_cost_usd
                > CurriculumGenerationJob.cost_usd,
                CurriculumGenerationJob.updated_at >= day_start,
            )
        )
    ).all()
    if not job_rows:
        return 0.0

    job_ids = [str(row[0]) for row in job_rows]
    usage_rows = (
        await db.execute(_usage_by_curriculum_job_ids_statement(job_ids))
    ).all()
    usage_by_job = {
        str(job_id): max(float(cost or 0), 0.0)
        for job_id, cost in usage_rows
        if job_id is not None
    }
    return round(
        sum(
            _job_unreconciled_reserve_today(
                state=state,
                estimated_cost_usd=estimated_cost,
                stored_cost_usd=stored_cost,
                checkpoints=checkpoints,
                authoritative_cost_usd=usage_by_job.get(str(job_id), 0.0),
                day_start=day_start,
                current=current,
            )
            for job_id, state, estimated_cost, stored_cost, checkpoints in job_rows
        ),
        8,
    )


def curriculum_stage_reserve_usd(stage: str | None = None) -> float:
    limit = max(float(settings.curriculum_daily_budget_usd), 0.0)
    if stage is not None:
        return min(limit, _STAGE_RESERVE_USD.get(stage, 0.05))
    daily_jobs = max(int(settings.curriculum_daily_job_limit), 1)
    return min(limit, max(0.01, min(0.025, limit / daily_jobs)))


def make_curriculum_budget_status(
    *,
    spent_usd: float,
    running_jobs: int = 0,
    reserved_usd: float | None = None,
) -> CurriculumBudgetStatus:
    limit = max(float(settings.curriculum_daily_budget_usd), 0.0)
    soft_limit = limit * 0.85
    spent = max(float(spent_usd), 0.0)
    reserved = (
        max(float(reserved_usd), 0.0)
        if reserved_usd is not None
        else max(int(running_jobs), 0) * curriculum_stage_reserve_usd()
    )
    committed = spent + reserved
    state = "normal"
    if limit <= 0 or committed >= limit:
        state = "hard_limit"
    elif committed >= soft_limit:
        state = "soft_limit"
    return CurriculumBudgetStatus(
        spent_usd=round(spent, 8),
        reserved_usd=round(reserved, 8),
        committed_usd=round(committed, 8),
        limit_usd=round(limit, 8),
        soft_limit_usd=round(soft_limit, 8),
        state=state,
    )


async def get_curriculum_budget_status(
    db: AsyncSession,
    *,
    now: datetime | None = None,
    running_jobs: int = 0,
    reserved_usd: float | None = None,
) -> CurriculumBudgetStatus:
    current = now or datetime.now(timezone.utc)
    day_start = current.replace(hour=0, minute=0, second=0, microsecond=0)
    spent = float(
        (
            await db.execute(
                select(
                    func.coalesce(func.sum(LLMUsageEvent.estimated_cost_usd), 0.0)
                ).where(
                    LLMUsageEvent.created_at >= day_start,
                    LLMUsageEvent.operation.in_(CURRICULUM_OPERATIONS),
                )
            )
        ).scalar_one()
        or 0.0
    )
    durable_unreconciled = await _durable_unreconciled_reserve_today(
        db,
        day_start=day_start,
        current=current,
    )
    current_lease_reserve = (
        max(float(reserved_usd), 0.0)
        if reserved_usd is not None
        else max(int(running_jobs), 0) * curriculum_stage_reserve_usd()
    )
    return make_curriculum_budget_status(
        spent_usd=spent,
        reserved_usd=current_lease_reserve + durable_unreconciled,
    )


async def get_curriculum_job_usage(
    db: AsyncSession,
    *,
    job_id: str,
) -> CurriculumJobUsage:
    """Read authoritative all-time usage, including calls from failed attempts."""

    rows = (
        await db.execute(_usage_for_curriculum_job_statement(job_id))
    ).all()
    operations: dict[str, dict[str, Any]] = {}
    input_tokens = 0
    output_tokens = 0
    total_tokens = 0
    cost_usd = 0.0
    failed_events = 0
    for (
        operation,
        provider,
        model,
        prompt_tokens,
        completion_tokens,
        event_total_tokens,
        estimated_cost,
        success,
    ) in rows:
        input_count = max(int(prompt_tokens or 0), 0)
        output_count = max(int(completion_tokens or 0), 0)
        total_count = max(
            int(event_total_tokens or input_count + output_count),
            input_count + output_count,
        )
        event_cost = max(float(estimated_cost or 0.0), 0.0)
        input_tokens += input_count
        output_tokens += output_count
        total_tokens += total_count
        cost_usd += event_cost
        failed_events += int(not success)
        key = f"{operation}:{provider}:{model}"
        item = operations.setdefault(
            key,
            {
                "operation": operation,
                "provider": provider,
                "model": model,
                "calls": 0,
                "failed_calls": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "total_tokens": 0,
                "estimated_cost_usd": 0.0,
            },
        )
        item["calls"] += 1
        item["failed_calls"] += int(not success)
        item["input_tokens"] += input_count
        item["output_tokens"] += output_count
        item["total_tokens"] += total_count
        item["estimated_cost_usd"] = round(
            float(item["estimated_cost_usd"]) + event_cost,
            8,
        )
    return CurriculumJobUsage(
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        total_tokens=total_tokens,
        estimated_cost_usd=round(cost_usd, 8),
        event_count=len(rows),
        failed_event_count=failed_events,
        operations=operations,
    )


def apply_curriculum_job_usage(
    job: Any,
    usage: CurriculumJobUsage,
    *,
    stage_usage: dict[str, Any] | None = None,
) -> None:
    """Replace counters from the event ledger; never increment and double count."""

    job.input_tokens = usage.input_tokens
    job.output_tokens = usage.output_tokens
    job.cost_usd = Decimal(str(usage.estimated_cost_usd))
    existing = job.model_usage_json if isinstance(job.model_usage_json, dict) else {}
    stages = stage_usage if stage_usage is not None else existing.get("stages", {})
    job.model_usage_json = {
        "stages": stages,
        "authoritative_telemetry": {
            "event_count": usage.event_count,
            "failed_event_count": usage.failed_event_count,
            "total_tokens": usage.total_tokens,
            "operations": usage.operations,
        },
    }


def curriculum_job_budget_allows_stage(
    *,
    spent_usd: float,
    budget_limit_usd: float | None,
    reserve_usd: float,
) -> bool:
    if budget_limit_usd is None:
        # A missing persisted ceiling is corrupt configuration, not permission
        # for unbounded provider spend. Factory-created jobs always pin an
        # explicit limit; legacy/manual rows must fail closed.
        return False
    return max(float(spent_usd), 0.0) + max(float(reserve_usd), 0.0) <= max(
        float(budget_limit_usd), 0.0
    )


def curriculum_budget_allows_stage(
    status: CurriculumBudgetStatus,
    *,
    additional_reserve_usd: float | None = None,
) -> bool:
    reserve = (
        curriculum_stage_reserve_usd()
        if additional_reserve_usd is None
        else max(float(additional_reserve_usd), 0.0)
    )
    return (
        status.state == "normal"
        and status.committed_usd + reserve <= status.soft_limit_usd
    )


def estimate_curriculum_grounded_cost_usd(
    *,
    model: str,
    prompt_tokens: int | None,
    completion_tokens: int | None,
    total_tokens: int | None,
    search_queries: int,
) -> float:
    """Always account autonomous Google Search usage, independent of legacy flags."""
    from app.services.llm.pricing import estimate_cost_usd, price_card_for_model

    token_cost = estimate_cost_usd(
        model=model,
        provider="gemini",
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
        grounded=False,
        search_queries=0,
    )
    card = price_card_for_model(model, provider="gemini")
    search_units = (
        max(int(search_queries), 1) if card.search_billing == "search_query" else 1
    )
    return round(token_cost + search_units * card.search_usd_per_unit, 8)
