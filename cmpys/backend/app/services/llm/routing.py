"""Quality-first adaptive selection between fast and balanced LLM tiers."""
from __future__ import annotations

import hashlib
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.llm_usage_event import LLMUsageEvent

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class RoutingStats:
    samples: int = 0
    successful_samples: int = 0
    quality_samples: int = 0
    average_quality: float | None = None
    average_total_tokens: float | None = None
    average_duration_ms: float | None = None

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

    cutoff = datetime.now(timezone.utc) - timedelta(
        days=settings.adaptive_routing_lookback_days
    )

    async def _query(session: AsyncSession) -> RoutingStats:
        stage = LLMUsageEvent.metadata_json["stage"].astext
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
                ).where(
                    LLMUsageEvent.operation == operation,
                    LLMUsageEvent.model == fast_model,
                    LLMUsageEvent.created_at >= cutoff,
                    stage == "draft",
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
        )

    try:
        if db is not None:
            stats = await _query(db)
        else:
            from app.core.db import async_session_maker

            async with async_session_maker() as routing_db:
                stats = await _query(routing_db)
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
