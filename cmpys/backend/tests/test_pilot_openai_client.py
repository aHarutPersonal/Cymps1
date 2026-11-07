"""Offline checks for the test-only OpenAI pilot client (no network, no key)."""
import asyncio
import json
from types import SimpleNamespace as NS

import httpx
import openai
from pydantic import BaseModel, Field

from app.services.planning.activity_draft import TutorialActivityDraft
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import PackagedLessonReview
from scripts.pilot_openai_client import (OpenAIPilotClient, drop_added_nulls, native_schema_compatible,
                                         openai_reasoning_effort, openai_strict_schema, openai_token_rates)


class _Out(BaseModel):
    a: int
    tags: dict[str, str] = {}


class _Inner(BaseModel):
    kind: str = Field("x", max_length=5)
    note: str | None = None


class _Plain(BaseModel):
    a: int
    items: list[_Inner] = []


def _strict_nodes(node):
    if isinstance(node, dict):
        if node.get("type") == "object":
            yield node
        for value in node.values():
            yield from _strict_nodes(value)
    elif isinstance(node, list):
        for value in node:
            yield from _strict_nodes(value)


def _client(text, *, finish="stop", refusal=None, seen=None, model="gpt-5.6-luna", **options):
    async def create(**params):
        if seen is not None:
            seen.update(params)

        class Stream:
            def __aiter__(self):
                async def chunks():
                    delta = NS(content=text, refusal=refusal)
                    yield NS(model=model + "-2026-08-01", usage=None,
                             choices=[NS(index=0, delta=delta, finish_reason=finish)])
                    usage = NS(prompt_tokens=1000, completion_tokens=200,
                               completion_tokens_details=NS(reasoning_tokens=50),
                               prompt_tokens_details=NS(cached_tokens=0))
                    yield NS(model=model + "-2026-08-01", usage=usage, choices=[])
                return chunks()

            async def close(self):
                return None
        return Stream()

    client = OpenAIPilotClient(model=model, max_tokens=1000, **options)
    client._client = NS(chat=NS(completions=NS(create=create)))
    return client


def test_effort_and_prices():
    assert [openai_reasoning_effort(x) for x in (None, "minimal", "none", "medium", "xhigh", "max")] == [
        "low", "low", "low", "medium", "high", "high"]
    assert openai_token_rates("gpt-5.6-terra-2026-08-01") == (2.00, 12.00)
    assert openai_token_rates("unknown") == (5.00, 30.00)


def test_strict_schema_rules_and_pipeline_routing():
    strict, optional = openai_strict_schema(_Plain.model_json_schema())
    for node in _strict_nodes(strict):
        assert node["additionalProperties"] is False and node["required"] == list(node["properties"])
    inner = strict["$defs"]["_Inner"]
    assert '"maxLength"' not in json.dumps(strict) and "maxLength: 5" in inner["properties"]["kind"]["anyOf"][0][
        "description"]
    assert sorted(k for keys in optional.values() for k in keys) == ["items", "kind"]  # note already nullable
    assert native_schema_compatible(TutorialActivityDraft.model_json_schema())
    draft = json.dumps(openai_strict_schema(TutorialActivityDraft.model_json_schema())[0])
    assert all(f'"{key}"' not in draft for key in ("oneOf", "allOf", "not", "contains", "const", "discriminator"))
    assert not native_schema_compatible(_Out.model_json_schema())  # free-form dict
    assert not native_schema_compatible(PackagedLessonReview.model_json_schema())
    assert not native_schema_compatible(LessonPackage.model_json_schema())  # untyped node


def test_drop_added_nulls_restores_defaults():
    strict, optional = openai_strict_schema(_Plain.model_json_schema())
    data = drop_added_nulls({"a": 1, "items": [{"kind": None, "note": None}]}, strict, optional)
    assert data == {"a": 1, "items": [{"note": None}]}
    assert _Plain.model_validate(data).items[0].kind == "x"


def test_native_mode_sends_strict_schema_reserve_and_parses():
    seen = {}
    client = _client('{"a": 2, "items": null}', seen=seen, thinking_level="minimal", reasoning_reserve=2048)
    validated, response = asyncio.run(client.generate_and_validate(
        system_prompt="s", user_prompt="u", output_model=_Plain, repair_on_failure=False))
    assert validated.a == 2 and validated.items == [] and response.finish_reason == "stop"
    fmt = seen["response_format"]
    assert fmt["type"] == "json_schema" and fmt["json_schema"]["strict"] is True
    assert fmt["json_schema"]["name"] == "_Plain"
    assert seen["max_completion_tokens"] == 3048 and seen["reasoning_effort"] == "low"
    assert seen["stream"] is True and seen["stream_options"] == {"include_usage": True}
    assert response.thoughts_tokens == 50 and client.last_attempt is response
    assert response.model == "gpt-5.6-luna-2026-08-01"
    assert abs(client.estimate_cost(response) - (1000 * 0.20 + 200 * 1.20) / 1e6) < 1e-12


def test_auto_prompt_mode_for_dicts_and_error_mapping():
    seen = {}
    client = _client('```json\n{"a": 1, "tags": {"x": "y"}}\n```', seen=seen, json_mode="auto")
    response = asyncio.run(client.generate_json(system_prompt="s", user_prompt="u", output_model=_Out))
    assert response.data == {"a": 1, "tags": {"x": "y"}} and seen["response_format"] == {"type": "json_object"}
    assert "Return one JSON object matching this schema" in seen["messages"][0]["content"]
    length = asyncio.run(_client('{"a": 1', finish="length").generate_json(
        system_prompt="s", user_prompt="u", output_model=_Plain))
    assert length.finish_reason == "length" and length.error.endswith("finish=length)")
    refused = asyncio.run(_client("", refusal="I can't").generate_json(
        system_prompt="s", user_prompt="u", output_model=_Plain))
    assert refused.error.startswith("openai refusal") and refused.retryable is False


def test_native_400_retries_once_in_prompt_mode_and_401_is_unbilled():
    calls = []

    def status_error(code):
        request = httpx.Request("POST", "https://api.openai.com/v1/chat/completions")
        cls = openai.BadRequestError if code == 400 else openai.AuthenticationError
        return cls("rejected", response=httpx.Response(code, request=request), body=None)

    client = _client('{"a": 3}', json_mode="auto")
    working = client._client.chat.completions.create

    async def create(**params):
        calls.append(params["response_format"]["type"])
        if params["response_format"]["type"] == "json_schema":
            raise status_error(400)
        return await working(**params)

    client._client = NS(chat=NS(completions=NS(create=create)))
    response = asyncio.run(client.generate_json(system_prompt="s", user_prompt="u", output_model=_Plain))
    assert calls == ["json_schema", "json_object"] and response.data == {"a": 3}
    assert response.effective_parameters["native_schema_rejected"] is True

    async def unauthorized(**params):
        raise status_error(401)

    client._client = NS(chat=NS(completions=NS(create=unauthorized)))
    denied = asyncio.run(client.generate_json(system_prompt="s", user_prompt="u", output_model=_Plain))
    assert denied.error == "openai request failed (GenerationUnavailable; 401)" and denied.retryable is False
    assert denied.error_code == "generation_unavailable"
    assert denied.prompt_tokens == 0 and client.estimate_cost(denied) == 0
