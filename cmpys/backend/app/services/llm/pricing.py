"""Deterministic provider cost estimates for usage telemetry.

Prices are standard paid-tier USD rates per one million tokens. Gemini bills
thinking tokens as output, so the estimator conservatively treats every token
in ``total_tokens - prompt_tokens`` as output when that is larger than the
visible completion count.
"""
from __future__ import annotations

from dataclasses import dataclass

from app.core.config import settings


PRICING_VERSION = "multi-provider-2026-07-15"


@dataclass(frozen=True)
class PriceCard:
    input_usd_per_million: float
    output_usd_per_million: float
    long_context_threshold: int | None = None
    long_input_usd_per_million: float | None = None
    long_output_usd_per_million: float | None = None
    search_usd_per_unit: float = 0.0
    search_billing: str = "grounded_prompt"

    def token_rates(self, prompt_tokens: int) -> tuple[float, float]:
        if (
            self.long_context_threshold is not None
            and prompt_tokens > self.long_context_threshold
        ):
            return (
                self.long_input_usd_per_million or self.input_usd_per_million,
                self.long_output_usd_per_million or self.output_usd_per_million,
            )
        return self.input_usd_per_million, self.output_usd_per_million


def price_card_for_model(model: str, provider: str | None = None) -> PriceCard:
    """Return the closest official card, or a conservative configurable card."""
    normalized = model.casefold().removeprefix("models/")
    resolved_provider = (provider or settings.llm_provider).casefold()

    # Effective Yunwu cash rates. Recharge conversion and the token's assigned
    # route are configurable because either can change independently.
    # Grok 4.5 doubles token rates above a 200k prompt context.
    if resolved_provider == "yunwu":
        exchange_rate = max(settings.yunwu_usd_exchange_rate, 0.000001)
        cash_multiplier = (
            max(settings.yunwu_quota_price_cny, 0.0)
            / exchange_rate
            * max(settings.yunwu_group_ratio, 0.0)
        )
        if normalized == "gpt-5.6-luna":
            return PriceCard(1.0 * cash_multiplier, 6.0 * cash_multiplier)
        if normalized == "grok-4.5":
            return PriceCard(
                2.0 * cash_multiplier,
                6.0 * cash_multiplier,
                long_context_threshold=200_000,
                long_input_usd_per_million=4.0 * cash_multiplier,
                long_output_usd_per_million=12.0 * cash_multiplier,
            )
        if normalized == "claude-fable-5":
            return PriceCard(10.0 * cash_multiplier, 50.0 * cash_multiplier)

    # Order matters: Flash-Lite names also contain "flash".
    if normalized.startswith("gemini-2.5-flash-lite"):
        return PriceCard(0.10, 0.40, search_usd_per_unit=0.035)
    if normalized.startswith("gemini-2.5-flash"):
        return PriceCard(0.30, 2.50, search_usd_per_unit=0.035)
    if normalized.startswith("gemini-2.5-pro"):
        return PriceCard(
            1.25,
            10.00,
            long_context_threshold=200_000,
            long_input_usd_per_million=2.50,
            long_output_usd_per_million=15.00,
            search_usd_per_unit=0.035,
        )
    if normalized.startswith("gemini-3.1-flash-lite"):
        return PriceCard(
            0.25,
            1.50,
            search_usd_per_unit=0.014,
            search_billing="search_query",
        )
    if normalized.startswith("gemini-3-flash"):
        return PriceCard(
            0.50,
            3.00,
            search_usd_per_unit=0.014,
            search_billing="search_query",
        )
    if normalized.startswith("gemini-3.1-pro"):
        return PriceCard(
            2.00,
            12.00,
            long_context_threshold=200_000,
            long_input_usd_per_million=4.00,
            long_output_usd_per_million=18.00,
            search_usd_per_unit=0.014,
            search_billing="search_query",
        )
    return PriceCard(
        settings.llm_unknown_input_price_usd_per_million,
        settings.llm_unknown_output_price_usd_per_million,
    )


def billed_output_tokens(
    *,
    prompt_tokens: int | None,
    completion_tokens: int | None,
    total_tokens: int | None,
) -> int:
    """Include hidden thinking tokens without double-counting visible output."""
    visible_output = max(int(completion_tokens or 0), 0)
    if total_tokens is None:
        return visible_output
    non_prompt_tokens = max(int(total_tokens) - int(prompt_tokens or 0), 0)
    return max(visible_output, non_prompt_tokens)


def estimate_cost_usd(
    *,
    model: str,
    provider: str | None = None,
    prompt_tokens: int | None,
    completion_tokens: int | None,
    total_tokens: int | None,
    grounded: bool = False,
    search_queries: int = 0,
) -> float:
    """Estimate one request's paid-tier cost in USD.

    Search overage is opt-in because the normal paid Gemini 2.5 allowance is
    far above this application's default two grounded catalog calls per day.
    """
    prompt_count = max(int(prompt_tokens or 0), 0)
    output_count = billed_output_tokens(
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
    )
    card = price_card_for_model(model, provider=provider)
    input_rate, output_rate = card.token_rates(prompt_count)
    cost = (
        prompt_count * input_rate / 1_000_000
        + output_count * output_rate / 1_000_000
    )
    if settings.llm_budget_include_search_overage and grounded:
        search_units = (
            max(int(search_queries), 1)
            if card.search_billing == "search_query"
            else 1
        )
        cost += search_units * card.search_usd_per_unit
    return round(cost, 8)
