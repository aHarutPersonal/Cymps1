"""Gemini model-family compatibility and reasoning configuration.

Gemini 3 models use ``thinking_level`` and no longer need sampling parameters.
Gemini 2.5 uses the older numeric ``thinking_budget`` contract.  Keeping the
translation in one place prevents a model upgrade from silently adding latency
or sending a parameter that a newer endpoint rejects.
"""

from __future__ import annotations

from typing import Literal


ThinkingLevel = Literal["minimal", "low", "medium", "high"]


def is_gemini_3_model(model: str | None) -> bool:
    normalized = (model or "").casefold().removeprefix("models/")
    return normalized.startswith("gemini-3")


def _level_from_budget(budget: int) -> ThinkingLevel:
    if budget <= 0:
        return "minimal"
    if budget <= 1_024:
        return "low"
    if budget <= 4_096:
        return "medium"
    return "high"


def _budget_from_level(level: ThinkingLevel) -> int:
    return {
        "minimal": 0,
        "low": 1_024,
        "medium": 4_096,
        # -1 asks Gemini 2.5 to choose a dynamic budget.
        "high": -1,
    }[level]


def resolve_thinking_config(
    *,
    model: str,
    tier: str,
    thinking_level: ThinkingLevel | None,
    thinking_budget: int | None,
) -> tuple[ThinkingLevel | None, int | None]:
    """Return exactly one reasoning control appropriate for ``model``."""
    if is_gemini_3_model(model):
        resolved_level = thinking_level
        if resolved_level is None and thinking_budget is not None:
            resolved_level = _level_from_budget(thinking_budget)
        if resolved_level is None:
            resolved_level = {
                "fast": "minimal",
                "balanced": "low",
                "quality": "high",
            }.get(tier, "low")

        # Gemini 3 Pro supports low/medium/high, but not minimal.
        if "pro" in model.casefold() and resolved_level == "minimal":
            resolved_level = "low"
        return resolved_level, None

    resolved_budget = thinking_budget
    if resolved_budget is None and thinking_level is not None:
        resolved_budget = _budget_from_level(thinking_level)
    if resolved_budget is None and tier == "fast":
        resolved_budget = 0
    return None, resolved_budget


def generation_config_kwargs(
    *,
    model: str,
    temperature: float | None = None,
    thinking_level: ThinkingLevel | None = None,
    thinking_budget: int | None = None,
) -> dict:
    """Build SDK kwargs without mixing old and new Gemini parameters."""
    from google.genai import types

    kwargs: dict = {}
    if not is_gemini_3_model(model) and temperature is not None:
        kwargs["temperature"] = temperature
    if thinking_level is not None:
        kwargs["thinking_config"] = types.ThinkingConfig(
            thinking_level=thinking_level,
        )
    elif thinking_budget is not None:
        kwargs["thinking_config"] = types.ThinkingConfig(
            thinking_budget=thinking_budget,
        )
    return kwargs
