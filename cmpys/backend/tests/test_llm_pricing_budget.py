import pytest

from app.core.config import settings
from app.models.ingest_job import IngestKind
from app.services.llm.budget import (
    budget_allows_job,
    classify_budget,
    job_budget_reserve_usd,
    make_budget_status,
)
from app.services.llm.pricing import (
    PRICING_VERSION,
    billed_output_tokens,
    estimate_cost_usd,
    price_card_for_model,
)


def test_cost_estimate_includes_hidden_thinking_tokens():
    assert billed_output_tokens(
        prompt_tokens=1_000,
        completion_tokens=1_000,
        total_tokens=3_000,
    ) == 2_000
    assert estimate_cost_usd(
        model="gemini-2.5-flash",
        prompt_tokens=1_000,
        completion_tokens=1_000,
        total_tokens=3_000,
    ) == pytest.approx(0.0053)


def test_current_gemini_price_cards_cover_all_configured_tiers():
    fast = price_card_for_model("gemini-3.5-flash-lite")
    balanced = price_card_for_model("gemini-3.6-flash")
    quality = price_card_for_model("gemini-3.1-pro-preview")

    assert (fast.input_usd_per_million, fast.output_usd_per_million) == (0.3, 2.5)
    assert (balanced.input_usd_per_million, balanced.output_usd_per_million) == (
        1.5,
        7.5,
    )
    assert (quality.input_usd_per_million, quality.output_usd_per_million) == (
        2.0,
        12.0,
    )
    assert PRICING_VERSION.startswith("direct-providers-")


def test_direct_provider_price_cards_cover_both_routed_models():
    haiku = price_card_for_model("claude-haiku-5-5", provider="anthropic")
    luna = price_card_for_model("gpt-6-luna-2026-08-01", provider="openai")  # a dated snapshot

    assert (haiku.input_usd_per_million, haiku.output_usd_per_million) == (0.10, 0.50)
    # Haiku 5.5 bills prompts above 100K tokens at the higher card.
    assert haiku.token_rates(100_000) == (0.10, 0.50)
    assert haiku.token_rates(100_001) == (0.50, 2.50)
    # Budgeted above its third-party list price so spend caps stay conservative.
    assert (luna.input_usd_per_million, luna.output_usd_per_million) == (0.20, 1.20)


def test_search_overage_is_opt_in_and_25_is_billed_per_grounded_prompt(monkeypatch):
    kwargs = {
        "model": "gemini-2.5-flash",
        "prompt_tokens": 0,
        "completion_tokens": 0,
        "total_tokens": 0,
        "grounded": True,
        "search_queries": 3,
    }
    monkeypatch.setattr(settings, "llm_budget_include_search_overage", False)
    assert estimate_cost_usd(**kwargs) == 0.0

    monkeypatch.setattr(settings, "llm_budget_include_search_overage", True)
    assert estimate_cost_usd(**kwargs) == pytest.approx(0.035)


def test_background_budget_preserves_headroom_and_never_blocks_free_jobs(monkeypatch):
    monkeypatch.setattr(settings, "llm_background_daily_budget_usd", 0.50)
    monkeypatch.setattr(settings, "llm_background_budget_soft_ratio", 0.85)
    monkeypatch.setattr(settings, "catalog_book_budget_reserve_usd", 0.06)

    status = make_budget_status(spent_usd=0.34, reserved_usd=0.06)
    assert status.state == "normal"
    assert status.committed_usd == pytest.approx(0.40)
    assert budget_allows_job(
        kind=IngestKind.BOOK,
        status=status,
        projected_spend_usd=status.committed_usd,
    ) is False
    assert budget_allows_job(
        kind=IngestKind.QUOTE,
        status=status,
        projected_spend_usd=status.committed_usd,
    ) is True
    assert classify_budget(spent_usd=0.43, limit_usd=0.50, soft_ratio=0.85) == (
        "soft_limit"
    )
    assert job_budget_reserve_usd(IngestKind.QUOTE) == 0.0


def test_unknown_failed_usage_is_not_reported_as_free():
    from app.services.llm.telemetry import UsageRecord, _event
    event = _event(UsageRecord(operation='book_module_generation', model='test',
                               provider='openlux', success=False))
    assert event.estimated_cost_usd is None
    assert event.metadata_json['usage_unknown'] is True
    event = _event(UsageRecord(operation='book_module_generation', model='test',
        provider='openlux', success=False, estimated_cost_usd=0))
    assert event.estimated_cost_usd == 0
    assert event.metadata_json['usage_unknown'] is False


@pytest.mark.asyncio
async def test_unreconciled_charge_blocks_autonomous_work_across_days(monkeypatch):
    from unittest.mock import AsyncMock, MagicMock
    from app.services.llm.budget import get_daily_background_budget_status
    spent, running, unknown = MagicMock(), MagicMock(), MagicMock()
    spent.scalar_one.return_value = 0
    running.scalars.return_value.all.return_value = []
    unknown.scalar_one_or_none.return_value = 'failed-call'
    db = MagicMock(execute=AsyncMock(side_effect=[spent, running, unknown]))
    status = await get_daily_background_budget_status(db)
    assert status.state == 'usage_unknown'
    assert not budget_allows_job(kind=IngestKind.BOOK, status=status, projected_spend_usd=0)
    query = str(db.execute.call_args.args[0])
    assert 'created_at' not in query
