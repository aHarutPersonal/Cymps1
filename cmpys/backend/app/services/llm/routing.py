"""Quality-first adaptive selection between fast and balanced LLM tiers."""
from __future__ import annotations

import hashlib
import logging
import time
from collections import OrderedDict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.llm_usage_event import LLMUsageEvent

logger = logging.getLogger(__name__)
_stats_cache: OrderedDict[tuple, tuple[float, "RoutingStats"]] = OrderedDict()
STATS_CACHE_SECONDS = 30
STATS_CACHE_SIZE = 128


@dataclass(frozen=True)
class RoutingStats:
    samples: int = 0
    successful_samples: int = 0
    quality_samples: int = 0
    average_quality: float | None = None
    average_total_tokens: float | None = None
    average_duration_ms: float | None = None
    critical_defects: int = 0

    @property
    def success_rate(self) -> float:
        return self.successful_samples / self.samples if self.samples else 0.0


@dataclass(frozen=True)
class RoutingDecision:
    tier: str
    reason: str
    fast_model: str | None
    stats: RoutingStats
    exploration_bucket: int


def _model_for_tier(tier: str) -> str | None:
    if settings.llm_provider == "zai":
        return {"fast": settings.zai_fast_model, "balanced": settings.zai_model}.get(tier)
    if settings.llm_provider == "openlux":
        return {
            "fast": settings.openlux_fast_model,
            "balanced": settings.openlux_model,
        }.get(tier)
    if settings.llm_provider == "gemini":
        return {
            "fast": settings.gemini_fast_model,
            "balanced": settings.gemini_model,
        }.get(tier)
    if settings.llm_provider == "openai":
        return {
            "fast": settings.openai_fast_model,
            "balanced": settings.openai_model,
        }.get(tier)
    if settings.llm_provider == "yunwu":
        return {
            "fast": settings.yunwu_fast_model,
            "balanced": settings.yunwu_model,
        }.get(tier)
    return None


def exploration_bucket(operation: str, routing_key: str) -> int:
    """Stable within an ISO week, but rotates to gather representative samples."""
    year, week, _ = datetime.now(timezone.utc).isocalendar()
    digest = hashlib.sha256(
        f"{operation}|{routing_key}|{year}-W{week}".encode()
    ).digest()
    return int.from_bytes(digest[:4], "big") % 100


def decide_tier(
    *,
    stats: RoutingStats,
    default_tier: str,
    fast_model: str | None,
    bucket: int,
) -> RoutingDecision:
    if not settings.adaptive_routing_enabled:
        return RoutingDecision(default_tier, "adaptive_disabled", fast_model, stats, bucket)
    if fast_model is None or default_tier != "balanced":
        return RoutingDecision(default_tier, "tier_not_eligible", fast_model, stats, bucket)
    if stats.critical_defects:
        return RoutingDecision(default_tier, "critical_defect_veto", fast_model, stats, bucket)

    enough_data = (
        stats.samples >= settings.adaptive_routing_min_samples
        and stats.quality_samples >= settings.adaptive_routing_min_samples
    )
    if enough_data:
        quality = stats.average_quality or 0.0
        if (
            stats.success_rate >= settings.adaptive_routing_min_success_rate
            and quality >= settings.adaptive_routing_min_quality_score
        ):
            return RoutingDecision("fast", "fast_proven", fast_model, stats, bucket)
        return RoutingDecision(default_tier, "fast_below_threshold", fast_model, stats, bucket)

    early_stop_samples = max(5, settings.adaptive_routing_min_samples // 4)
    if stats.samples >= early_stop_samples:
        quality = stats.average_quality or 0.0
        if (
            stats.success_rate < settings.adaptive_routing_min_success_rate
            or (
                stats.quality_samples >= early_stop_samples
                and quality < settings.adaptive_routing_min_quality_score
            )
        ):
            return RoutingDecision(default_tier, "fast_canary_stopped", fast_model, stats, bucket)

    if bucket < settings.adaptive_routing_canary_percent:
        return RoutingDecision("fast", "fast_canary", fast_model, stats, bucket)
    return RoutingDecision(default_tier, "balanced_holdout", fast_model, stats, bucket)


async def choose_llm_tier(
    *,
    operation: str,
    routing_key: str,
    default_tier: str = "balanced",
    db: AsyncSession | None = None,
    subtask: str | None = None,
) -> RoutingDecision:
    fast_model = _model_for_tier("fast")
    bucket = exploration_bucket(operation, routing_key)
    if not settings.adaptive_routing_enabled or fast_model is None:
        return decide_tier(
            stats=RoutingStats(),
            default_tier=default_tier,
            fast_model=fast_model,
            bucket=bucket,
        )

    contract = None
    if operation == "plan_item_detail_generation":
        from app.services.planning.lesson_package import routing_validation_contract
        contract = routing_validation_contract()
    cutoff = datetime.now(timezone.utc) - timedelta(
        days=settings.adaptive_routing_lookback_days
    )

    async def _query(session: AsyncSession) -> RoutingStats:
        stage = LLMUsageEvent.metadata_json["stage"].astext
        meta = LLMUsageEvent.metadata_json
        selection = stage == "draft"
        if operation == "plan_item_detail_generation":
            selection = and_(meta["attempt_role"].astext == "initial",
                             meta["subtask"].astext == (subtask or "lesson"),
                             meta["validation_contract"].astext == contract)
        row = (
            await session.execute(
                select(
                    func.count(LLMUsageEvent.id),
                    func.count(LLMUsageEvent.id).filter(
                        LLMUsageEvent.success.is_(True)
                    ),
                    func.count(LLMUsageEvent.quality_score),
                    func.avg(LLMUsageEvent.quality_score),
                    func.avg(LLMUsageEvent.total_tokens),
                    func.avg(LLMUsageEvent.duration_ms),
                    func.count(LLMUsageEvent.id).filter(meta["critical_defect"].astext == "true"),
                ).where(
                    LLMUsageEvent.operation == operation,
                    LLMUsageEvent.provider == settings.llm_provider,
                    LLMUsageEvent.model == fast_model,
                    LLMUsageEvent.created_at >= cutoff,
                    selection,
                )
            )
        ).one()
        return RoutingStats(
            samples=int(row[0] or 0),
            successful_samples=int(row[1] or 0),
            quality_samples=int(row[2] or 0),
            average_quality=float(row[3]) if row[3] is not None else None,
            average_total_tokens=float(row[4]) if row[4] is not None else None,
            average_duration_ms=float(row[5]) if row[5] is not None else None,
            critical_defects=int(row[6] or 0) if len(row) > 6 else 0,
        )

    try:
        cache_key = (operation, subtask, settings.llm_provider, fast_model, contract, settings.adaptive_routing_lookback_days)
        cached = _stats_cache.get(cache_key)
        if cached and time.monotonic() - cached[0] < STATS_CACHE_SECONDS:
            stats = cached[1]
        elif db is not None:
            stats = await _query(db)
        else:
            from app.core.db import async_session_maker

            async with async_session_maker() as routing_db:
                stats = await _query(routing_db)
        if not cached or time.monotonic() - cached[0] >= STATS_CACHE_SECONDS:
            _stats_cache[cache_key] = (time.monotonic(), stats)
            _stats_cache.move_to_end(cache_key)
            while len(_stats_cache) > STATS_CACHE_SIZE:
                _stats_cache.popitem(last=False)
    except Exception as exc:  # pragma: no cover - external DB availability
        logger.warning("[LLM_ROUTING] Falling back to %s: %s", default_tier, exc)
        return RoutingDecision(
            default_tier,
            "telemetry_unavailable",
            fast_model,
            RoutingStats(),
            bucket,
        )

    return decide_tier(
        stats=stats,
        default_tier=default_tier,
        fast_model=fast_model,
        bucket=bucket,
    )
