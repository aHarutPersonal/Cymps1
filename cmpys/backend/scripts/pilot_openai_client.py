"""Test-only OpenAI client for the local pilots (not used by the app).

Mirrors ``scripts/pilot_claude_client.py`` so GPT models get the same
schema-enforced contract Claude gets. Implements the ``BaseLLMClient`` surface
the planning pipeline uses (``generate_json``, the inherited
``generate_and_validate``, ``model``, ``provider_name``, ``max_tokens``,
``timeout``, ``thinking_level`` and ``last_attempt``). Every request streams
chat.completions directly from api.openai.com (key from ``OPENAI_API_KEY``)
with usage, and returns an ``LLMResponse`` in the pipeline's finish-reason
vocabulary (stop/length); refusals and content filtering are errors.

JSON modes:
- ``native``: ``response_format`` json_schema with ``strict: True`` and the
  strict-compatible schema from ``openai_strict_schema`` (outline pilot).
- ``prompt``: the schema is appended to the system prompt (with
  ``response_format=json_object``) and parsed strictly (fenced JSON allowed, no
  brace balancing).
- ``auto``: native when the schema converts cleanly (no free-form dict fields,
  no untyped nodes, inside the strict-mode size limits), else prompt; a native
  400 retries once in prompt mode under the same budget reservation (a 400 is
  not billed).

Strict schema: the OpenAI SDK's ``_ensure_strict_json_schema`` only adds
``additionalProperties: false``/all-required and inlines ``$ref`` siblings, so
this module transforms conservatively in the same spirit as Anthropic's
``transform_schema``: keywords strict mode supports are kept, ``oneOf`` becomes
``anyOf``, ``const`` becomes a one-value ``enum``, every property is required
and a property the source schema made optional becomes nullable (a null for it
is dropped before validation so the Pydantic default applies). Any other
keyword (``minLength``/``maxLength``, ``default``, ``contains``, ``not``, ...)
is moved into the node's description as ``{key: value}``, as Anthropic does,
so the hint survives and Pydantic still enforces it after parsing.
"""
from app.services.llm.openai_direct import (  # noqa: F401  (the pilot tests import these here)
    OpenAIDirectLLMClient, StrictSchemaError, drop_added_nulls, native_schema_compatible, openai_reasoning_effort,
    openai_strict_schema,
)

# Per million tokens (input, output). These come from third-party listings
# after the 30 Jul 2026 knowledge cut, not from an OpenAI price page; cached
# input is billed here at the full input rate (conservative). gpt-6-luna is
# listed at $0.10/$0.50; it is budgeted at gpt-5.6-luna's rate so caps stay conservative.
OPENAI_PRICES = {"gpt-5.6-luna": (0.20, 1.20), "gpt-5.6-terra": (2.00, 12.00),
                 "gpt-5.6-sol": (5.00, 30.00), "gpt-6-luna": (0.20, 1.20)}
_MOST_EXPENSIVE = max(OPENAI_PRICES.values())


def openai_token_rates(model, input_tokens=0):
    """Per-million (input, output) rates; a dated snapshot is priced as its alias."""
    for name, rates in OPENAI_PRICES.items():
        if model == name or str(model or "").startswith(name + "-"):
            return rates
    return _MOST_EXPENSIVE


class OpenAIPilotClient(OpenAIDirectLLMClient):
    """The app's direct client with the pilot's price gate and budget estimate."""

    def __init__(self, *, model, max_tokens, effort=None, thinking_level=None, timeout=150,
                 json_mode="native", reasoning_reserve=0, **_ignored):
        if model not in OPENAI_PRICES:
            raise ValueError(f"Unpriced OpenAI model: {model}")
        super().__init__(model=model, max_tokens=max_tokens, effort=effort, thinking_level=thinking_level,
                         timeout=timeout, json_mode=json_mode, reasoning_reserve=reasoning_reserve)

    def estimate_cost(self, response):
        if response.prompt_tokens is None or response.completion_tokens is None:
            return None
        rate_in, rate_out = openai_token_rates(response.model or self.model, response.prompt_tokens)
        return (response.prompt_tokens * rate_in + response.completion_tokens * rate_out) / 1_000_000
