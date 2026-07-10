"""Daily monetary budget policy for autonomous catalog work."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.ingest_job import IngestJob, IngestKind, IngestState
from app.models.llm_usage_event import LLMUsageEvent


BACKGROUND_OPERATIONS = frozenset(
    {
        "book_module_generation",
        "idol_profile_extraction",
        "idol_achievements_extraction",
        "idol_timeline_normalization",
        "idol_milestones_by_age",
        "idol_persona_generation",
        "quote_verification",
    }
)


@dataclass(frozen=True)
class DailyBudgetStatus:
    spent_usd: float
    reserved_usd: float
    committed_usd: float
    limit_usd: float
    remaining_usd: float
    used_ratio: float
    state: str


def classify_budget(*, spent_usd: float, limit_usd: float, soft_ratio: float) -> str:
    if limit_usd <= 0 or spent_usd >= limit_usd:
        return "hard_limit"
    if spent_usd >= limit_usd * min(max(soft_ratio, 0.0), 1.0):
        return "soft_limit"
    return "normal"


def make_budget_status(
    *,
    spent_usd: float,
    reserved_usd: float = 0.0,
) -> DailyBudgetStatus:
    limit = max(float(settings.llm_background_daily_budget_usd), 0.0)
    spent = max(float(spent_usd), 0.0)
    reserved = max(float(reserved_usd), 0.0)
    committed = spent + reserved
    remaining = max(limit - committed, 0.0)
    used_ratio = committed / limit if limit > 0 else 1.0
    return DailyBudgetStatus(
        spent_usd=round(spent, 8),
        reserved_usd=round(reserved, 8),
        committed_usd=round(committed, 8),
        limit_usd=round(limit, 8),
        remaining_usd=round(remaining, 8),
        used_ratio=used_ratio,
        state=classify_budget(
            spent_usd=committed,
            limit_usd=limit,
            soft_ratio=settings.llm_background_budget_soft_ratio,
        ),
    )


async def get_daily_background_budget_status(
    db: AsyncSession,
    *,
    now: datetime | None = None,
    exclude_running_job_id: str | None = None,
) -> DailyBudgetStatus:
    current = now or datetime.now(timezone.utc)
    day_start = current.replace(hour=0, minute=0, second=0, microsecond=0)
    spent = float(
        (
            await db.execute(
                select(
                    func.coalesce(func.sum(LLMUsageEvent.estimated_cost_usd), 0.0)
                ).where(
                    LLMUsageEvent.created_at >= day_start,
                    LLMUsageEvent.operation.in_(BACKGROUND_OPERATIONS),
                )
            )
        ).scalar_one()
        or 0.0
    )
    running_query = select(IngestJob.kind).where(
        IngestJob.state == IngestState.RUNNING
    )
    if exclude_running_job_id:
        running_query = running_query.where(IngestJob.id != exclude_running_job_id)
    running_kinds = (await db.execute(running_query)).scalars().all()
    reserved = sum(job_budget_reserve_usd(kind) for kind in running_kinds)
    return make_budget_status(spent_usd=spent, reserved_usd=reserved)


def job_budget_reserve_usd(kind: IngestKind) -> float:
    if kind == IngestKind.BOOK:
        return max(settings.catalog_book_budget_reserve_usd, 0.0)
    if kind == IngestKind.IDOL:
        return max(settings.catalog_idol_budget_reserve_usd, 0.0)
    if kind == IngestKind.QUOTE_VERIFICATION:
        return max(settings.catalog_quote_verification_budget_reserve_usd, 0.0)
    return 0.0


def budget_allows_job(
    *,
    kind: IngestKind,
    status: DailyBudgetStatus,
    projected_spend_usd: float,
) -> bool:
    reserve = job_budget_reserve_usd(kind)
    if reserve == 0:
        return True
    if status.state != "normal":
        return False
    soft_ceiling = status.limit_usd * min(
        max(settings.llm_background_budget_soft_ratio, 0.0), 1.0
    )
    return projected_spend_usd + reserve <= soft_ceiling
