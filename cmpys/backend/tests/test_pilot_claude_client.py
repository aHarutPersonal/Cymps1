"""Offline checks for the test-only Claude pilot client (no network, no key)."""
import asyncio
from types import SimpleNamespace as NS

from pydantic import BaseModel

from app.services.planning.lesson_package import LessonPackage
from scripts.pilot_claude_client import ClaudePilotClient, claude_effort, claude_token_rates, native_schema_compatible


class _Out(BaseModel):
    a: int
    tags: dict[str, str] = {}


class _Plain(BaseModel):
    a: int


def _client(text, *, stop="end_turn", model="claude-haiku-5-5", seen=None, **options):
    class Stream:
        def __init__(self, **params):
            if seen is not None:
                seen.update(params)

        async def __aenter__(self):
            return self

        async def __aexit__(self, *exc):
            return False

        def __aiter__(self):
            async def events():
                yield NS(type="content_block_delta", delta=NS(type="text_delta", text=text))
            return events()

        async def get_final_message(self):
            usage = NS(input_tokens=1000, output_tokens=200, cache_creation_input_tokens=None,
                       cache_read_input_tokens=None, iterations=None, output_tokens_details=NS(thinking_tokens=50))
            return NS(model=model, stop_reason=stop, usage=usage,
                      content=[NS(type="thinking"), NS(type="text", text=text)])

    client = ClaudePilotClient(model=options.pop("client_model", "claude-haiku-5-5"), max_tokens=1000, **options)
    client._client = NS(beta=NS(messages=NS(stream=Stream)))
    return client


def test_effort_and_prices():
    assert [claude_effort(x) for x in (None, "minimal", "off", "medium", "xhigh", "max")] == [
        "low", "low", "low", "medium", "high", "high"]
    assert claude_token_rates("claude-haiku-5-5", 10) == (0.10, 0.50)
    assert claude_token_rates("claude-haiku-5-5", 200_000) == (0.50, 2.50)


def test_schema_compatibility_routes_dicts_and_untyped_nodes_to_prompt_mode():
    assert native_schema_compatible(_Plain.model_json_schema())
    assert not native_schema_compatible(_Out.model_json_schema())
    assert not native_schema_compatible(LessonPackage.model_json_schema())


def test_prompt_mode_parses_fenced_json_with_reserve_and_pipeline_finish_reason():
    seen = {}
    client = _client('```json\n{"a": 1, "tags": {"x": "y"}}\n```', seen=seen, json_mode="auto",
                     thinking_level="minimal", reasoning_reserve=2048)
    validated, response = asyncio.run(client.generate_and_validate(
        system_prompt="s", user_prompt="u", output_model=_Out, repair_on_failure=False))
    assert validated.tags == {"x": "y"} and response.finish_reason == "stop"
    assert seen["max_tokens"] == 3048 and seen["output_config"] == {"effort": "low"}
    assert "fallbacks" not in seen  # Claude Haiku 5.5 has no server-side fallback
    assert response.thoughts_tokens == 50 and client.last_attempt is response
    assert abs(client.estimate_cost(response) - (1000 * 0.10 + 200 * 0.50) / 1e6) < 1e-12


def test_truncation_and_prose_map_to_retryable_pipeline_errors():
    length = asyncio.run(_client('{"a": 1', stop="max_tokens").generate_json(
        system_prompt="s", user_prompt="u", output_model=_Plain))
    assert length.finish_reason == "length" and length.error.endswith("finish=length)")
    prose = asyncio.run(_client('Here: {"a": 1}', json_mode="prompt").generate_json(
        system_prompt="s", user_prompt="u", output_model=_Plain))
    # Malformed JSON is the caller's bounded correction, not a transport retry.
    assert prose.error.startswith("anthropic request failed (JSONDecodeError;")
    assert prose.retryable is None and prose.data == {}
    assert prose.effective_parameters["json_protocol_error"] == "invalid_json_syntax"


def test_native_mode_uses_structured_output_and_fallbacks_for_sonnet():
    seen = {}
    client = _client('{"a": 2}', seen=seen, client_model="claude-sonnet-5-5", model="claude-opus-5", effort="medium")
    response = asyncio.run(client.generate_json(system_prompt="s", user_prompt="u", output_model=_Plain))
    assert response.data == {"a": 2} and response.model == "claude-opus-5"
    assert seen["output_config"]["format"]["type"] == "json_schema" and seen["fallbacks"] == "default"
    assert abs(client.estimate_cost(response) - (1000 * 5 + 200 * 25) / 1e6) < 1e-12
