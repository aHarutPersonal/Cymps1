import pytest

from app.core.config import settings
from app.services.llm.routing import RoutingStats, choose_llm_tier, decide_tier


def _enable(monkeypatch):
    monkeypatch.setattr(settings, "adaptive_routing_enabled", True)
    monkeypatch.setattr(settings, "adaptive_routing_min_samples", 20)
    monkeypatch.setattr(settings, "adaptive_routing_canary_percent", 10)
    monkeypatch.setattr(settings, "adaptive_routing_min_success_rate", 0.90)
    monkeypatch.setattr(settings, "adaptive_routing_min_quality_score", 0.90)


def test_disabled_policy_always_uses_default(monkeypatch):
    monkeypatch.setattr(settings, "adaptive_routing_enabled", False)

    decision = decide_tier(
        stats=RoutingStats(samples=100, successful_samples=100, quality_samples=100, average_quality=1.0),
        default_tier="balanced",
        fast_model="fast-test",
        bucket=0,
    )

    assert decision.tier == "balanced"
    assert decision.reason == "adaptive_disabled"


def test_small_canary_uses_fast_before_enough_data(monkeypatch):
    _enable(monkeypatch)

    canary = decide_tier(
        stats=RoutingStats(),
        default_tier="balanced",
        fast_model="fast-test",
        bucket=2,
    )
    holdout = decide_tier(
        stats=RoutingStats(),
        default_tier="balanced",
        fast_model="fast-test",
        bucket=50,
    )

    assert canary.tier == "fast"
    assert canary.reason == "fast_canary"
    assert holdout.tier == "balanced"


def test_fast_tier_expands_only_after_quality_threshold(monkeypatch):
    _enable(monkeypatch)
    good = RoutingStats(
        samples=25,
        successful_samples=24,
        quality_samples=25,
        average_quality=0.94,
    )
    weak = RoutingStats(
        samples=25,
        successful_samples=24,
        quality_samples=25,
        average_quality=0.75,
    )

    assert decide_tier(
        stats=good,
        default_tier="balanced",
        fast_model="fast-test",
        bucket=99,
    ).reason == "fast_proven"
    rejected = decide_tier(
        stats=weak,
        default_tier="balanced",
        fast_model="fast-test",
        bucket=0,
    )
    assert rejected.tier == "balanced"
    assert rejected.reason == "fast_below_threshold"


def test_bad_early_canary_is_stopped(monkeypatch):
    _enable(monkeypatch)
    stats = RoutingStats(
        samples=5,
        successful_samples=3,
        quality_samples=5,
        average_quality=0.70,
    )

    decision = decide_tier(
        stats=stats,
        default_tier="balanced",
        fast_model="fast-test",
        bucket=0,
    )

    assert decision.tier == "balanced"
    assert decision.reason == "fast_canary_stopped"


@pytest.mark.asyncio
async def test_choose_tier_queries_fast_model_history(monkeypatch):
    _enable(monkeypatch)
    monkeypatch.setattr(settings, "llm_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_fast_model", "fast-test")

    class Result:
        def one(self):
            return (20, 19, 20, 0.93, 500.0, 1200.0)

    class DB:
        async def execute(self, statement):
            self.statement = statement
            return Result()

    decision = await choose_llm_tier(
        operation="book_module_generation",
        routing_key="book:test",
        db=DB(),
    )

    assert decision.tier == "fast"
    assert decision.stats.samples == 20
    assert decision.stats.average_quality == 0.93
