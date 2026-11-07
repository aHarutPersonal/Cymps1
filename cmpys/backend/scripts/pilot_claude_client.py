"""Test-only Claude client for the local pilots.

The app's direct Anthropic client (``app/services/llm/anthropic_direct.py``)
with the pilots' price gate and budget estimate. The pilots default to native
JSON mode and no reasoning reserve unless a run passes one.
"""
from app.services.llm.anthropic_direct import (  # noqa: F401  (the pilot tests import these here)
    AnthropicDirectLLMClient, claude_effort, native_schema_compatible,
)

# Anthropic list prices per million tokens (input, output). Fallback models are
# listed so a fallback-served reply is costed at its own rate.
CLAUDE_PRICES = {"claude-opus-5-5": (4.00, 20.00), "claude-sonnet-5-5": (2.00, 10.00),
                 "claude-haiku-5-5": (0.10, 0.50), "claude-opus-5": (5.00, 25.00),
                 "claude-opus-4-8": (5.00, 25.00), "claude-sonnet-5": (2.00, 10.00)}
# Claude Haiku 5.5 bills prompts above 100K tokens at a higher card.
_LONG_PROMPT = {"claude-haiku-5-5": (100_000, (0.50, 2.50))}
_MOST_EXPENSIVE = max(CLAUDE_PRICES.values())


def claude_token_rates(model, input_tokens=0):
    """Per-million (input, output) rates for a request of ``input_tokens``."""
    threshold, long_rates = _LONG_PROMPT.get(model, (None, None))
    if threshold is not None and input_tokens > threshold:
        return long_rates
    return CLAUDE_PRICES.get(model, _MOST_EXPENSIVE)


class ClaudePilotClient(AnthropicDirectLLMClient):
    """The app's direct client with the pilot's price gate and budget estimate."""

    def __init__(self, *, model, max_tokens, effort=None, thinking_level=None, timeout=150,
                 json_mode="native", reasoning_reserve=0, **_ignored):
        if model not in CLAUDE_PRICES:
            raise ValueError(f"Unpriced Claude model: {model}")
        super().__init__(model=model, max_tokens=max_tokens, effort=effort, thinking_level=thinking_level,
                         timeout=timeout, json_mode=json_mode, reasoning_reserve=reasoning_reserve)

    def estimate_cost(self, response):
        if response.prompt_tokens is None or response.completion_tokens is None:
            return None
        rate_in, rate_out = claude_token_rates(response.model or self.model, response.prompt_tokens)
        return (response.prompt_tokens * rate_in + response.completion_tokens * rate_out) / 1_000_000
