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
    fast = price_card_for_model("gemini-3.1-flash-lite")
    balanced = price_card_for_model("gemini-2.5-flash")
    quality = price_card_for_model("gemini-3.1-pro-preview")

    assert (fast.input_usd_per_million, fast.output_usd_per_million) == (0.25, 1.5)
    assert (balanced.input_usd_per_million, balanced.output_usd_per_million) == (
        0.3,
        2.5,
    )
    assert (quality.input_usd_per_million, quality.output_usd_per_million) == (
        2.0,
        12.0,
    )
    assert PRICING_VERSION.startswith("multi-provider-")


def test_yunwu_default_route_price_cards_use_effective_cash_cost(monkeypatch):
    monkeypatch.setattr(settings, "yunwu_group_ratio", 1.0)
    monkeypatch.setattr(settings, "yunwu_quota_price_cny", 0.5)
    monkeypatch.setattr(settings, "yunwu_usd_exchange_rate", 7.3)
    fast = price_card_for_model("gpt-5.6-luna", provider="yunwu")
    balanced = price_card_for_model("grok-4.5", provider="yunwu")
    quality = price_card_for_model("claude-fable-5", provider="yunwu")

    assert fast.input_usd_per_million == pytest.approx(1 / 14.6)
    assert fast.output_usd_per_million == pytest.approx(6 / 14.6)
    assert balanced.input_usd_per_million == pytest.approx(2 / 14.6)
    assert balanced.output_usd_per_million == pytest.approx(6 / 14.6)
    assert quality.input_usd_per_million == pytest.approx(10 / 14.6)
    assert quality.output_usd_per_million == pytest.approx(50 / 14.6)
    assert balanced.token_rates(200_001) == pytest.approx((4 / 14.6, 12 / 14.6))


def test_yunwu_price_card_respects_assigned_route_multiplier(monkeypatch):
    monkeypatch.setattr(settings, "yunwu_group_ratio", 6.0)
    monkeypatch.setattr(settings, "yunwu_quota_price_cny", 0.5)
    monkeypatch.setattr(settings, "yunwu_usd_exchange_rate", 7.3)

    balanced = price_card_for_model("grok-4.5", provider="yunwu")

    assert balanced.input_usd_per_million == pytest.approx(12 / 14.6)
    assert balanced.output_usd_per_million == pytest.approx(36 / 14.6)


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
