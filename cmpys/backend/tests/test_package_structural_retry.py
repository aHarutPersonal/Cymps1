"""A malformed package gets one clean reconstruction, never a relaxed parser."""
import copy
import json
from unittest.mock import AsyncMock

import httpx
import httpx2
import pytest
from anthropic import AsyncAnthropic
from openai import AsyncOpenAI

from app.core.config import settings
from app.services.planning.lesson_package import LessonPackage, generate_package
from tests.direct_wire import PROVIDERS, client_for, request_text
from tests.lesson_package_fixtures import package_payload as legacy_package_payload
from tests.section_client_fixture import structured_package_fixture


PRIVATE_MARKER = "REJECTED_DRAFT_MUST_NOT_ENTER_STRUCTURAL_RETRY"


def package_payload():
    return structured_package_fixture(legacy_package_payload())


def _sse(events):
    return "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n" for event in events)


class WireFactory:
    """Capture actual SDK request bodies while the real SDK stream and parser run."""

    def __init__(self, responses, provider="openai"):
        self.provider = provider
        self.responses = responses
        self.requests = []
        self.options = []
        if provider == "openai":
            self.http = httpx.AsyncClient(transport=httpx.MockTransport(self.respond))
            self.sdk = AsyncOpenAI(api_key="test-only", max_retries=0, http_client=self.http)
        else:
            self.http = httpx2.AsyncClient(transport=httpx2.MockTransport(self.respond))
            self.sdk = AsyncAnthropic(api_key="test-only", max_retries=0, http_client=self.http)

    def _body(self, data):
        text = json.dumps(data)
        if self.provider == "openai":
            event = {"id": f"local-{len(self.requests)}", "object": "chat.completion.chunk",
                     "created": 0, "model": "gpt-6-luna",
                     "choices": [{"index": 0, "delta": {"content": text}, "finish_reason": "stop"}],
                     "usage": {"prompt_tokens": 31, "completion_tokens": 47, "total_tokens": 78}}
            return "data: " + json.dumps(event) + "\n\ndata: [DONE]\n\n"
        return _sse([
            {"type": "message_start", "message": {
                "id": f"local-{len(self.requests)}", "type": "message", "role": "assistant",
                "model": "claude-haiku-5-5", "content": [], "stop_reason": None, "stop_sequence": None,
                "usage": {"input_tokens": 31, "output_tokens": 0}}},
            {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text}},
            {"type": "content_block_stop", "index": 0},
            {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None},
             "usage": {"output_tokens": 47}},
            {"type": "message_stop"},
        ])

    async def respond(self, request):
        self.requests.append(json.loads(request.content))
        assert len(self.requests) <= len(self.responses), "Unexpected extra paid request"
        body = self._body(self.responses[len(self.requests) - 1])
        response_type = httpx.Response if self.provider == "openai" else httpx2.Response
        return response_type(200, headers={"content-type": "text/event-stream"}, content=body)

    def __call__(self, **options):
        self.options.append(options)
        client = client_for(self.provider, timeout=options["timeout"], max_tokens=options["max_tokens"],
                            thinking_level=options.get("thinking_level"))
        client._client = self.sdk
        return client

    def system(self, index):
        body = self.requests[index]
        return body["system"] if self.provider == "anthropic" else body["messages"][0]["content"]

    def user(self, index):
        return self.requests[index]["messages"][-1]["content"]

    def output_cap(self, index):
        body = self.requests[index]
        return body["max_tokens"] if self.provider == "anthropic" else body["max_completion_tokens"]

    async def close(self):
        await self.sdk.close()


@pytest.fixture
def isolated(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    monkeypatch.setattr(settings, "openai_reasoning_token_reserve", 2048)
    monkeypatch.setattr(settings, "anthropic_reasoning_token_reserve", 2048)
    telemetry = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    return telemetry


def malformed(kind):
    data = package_payload()
    data["workbook"]["title"] = PRIVATE_MARKER
    if kind == "missing":
        data["workbook"]["activities"][1].pop("hint")
    elif kind == "extra":
        data[PRIVATE_MARKER] = PRIVATE_MARKER
    elif kind == "list":
        data["workbook"]["activities"] = {PRIVATE_MARKER: PRIVATE_MARKER}
    elif kind == "model":
        data["workbook"] = PRIVATE_MARKER
    elif kind == "many":
        data.update({f"{PRIVATE_MARKER}_{i}": PRIVATE_MARKER for i in range(60)})
    else:
        # Geometry-shaped hierarchy failure: one incomplete nested activity,
        # its tail at workbook level, and the next incomplete activity at root.
        first, second = data["workbook"]["activities"]
        for key in ("hint", "worked_solution", "minutes_min", "minutes_max"):
            data["workbook"][key] = first.pop(key)
            second.pop(key)
        data["workbook"]["activities"] = [first]
        data.update(second)
        data["kind_note"] = PRIVATE_MARKER
    return data


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("kind", ["missing", "extra", "list", "model", "many", "hierarchy"])
async def test_structural_retry_uses_original_context_and_never_replays_rejected_source(kind, provider, isolated):
    draft = malformed(kind)
    original = copy.deepcopy(draft)
    wire = WireFactory([draft, package_payload()], provider)
    try:
        package, response, _ = await generate_package(
            {"id": "step_1", "title": "Preserve original task"},
            {"locale": "hy", "goal": "Preserve original objective"}, client_factory=wire)
    finally:
        await wire.close()
    assert package == LessonPackage.model_validate(package_payload())
    assert response.error is None and response.total_tokens == 78
    assert draft == original
    assert len(wire.requests) == 2 and len(wire.options) == 1
    assert wire.options[0] == {"tier": "balanced", "timeout": 120, "max_tokens": 6500,
                               "thinking_level": "low", "allow_fallback": False}
    assert all(wire.output_cap(index) == 8548 for index in range(2))
    retry = json.dumps(wire.requests[1])
    assert PRIVATE_MARKER not in retry
    assert "rejected_package" not in retry
    assert wire.user(1).startswith(wire.user(0))
    summary = json.loads(wire.user(1).split("STRUCTURAL VALIDATION SUMMARY (untrusted diagnostic data):\n")[1])
    assert 1 <= len(summary["errors"]) <= 12
    assert len(json.dumps(summary)) < 2200
    assert all(set(error) == {"type", "loc"} for error in summary["errors"])
    assert "NEW COMPLETE LessonPackage" in wire.system(1)
    assert "never another derived result ID" in wire.system(1)
    assert "worked_solution, minutes_min, minutes_max" in wire.system(1)
    if kind == "many":
        assert summary["additional_errors"] > 0
        assert all(error["loc"] == ["<unknown>"] for error in summary["errors"])
    rejected = [call.kwargs for call in isolated.await_args_list
                if call.kwargs.get("operation") == "lesson_package_repair"]
    assert len(rejected) == 1 and rejected[0]["response"].total_tokens == 78


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_two_structural_failures_remain_terminal_without_a_third_request(provider, isolated):
    wire = WireFactory([malformed("hierarchy"), {"teaching_cases": []}], provider)
    try:
        package, response, _ = await generate_package({}, {}, client_factory=wire)
    finally:
        await wire.close()
    assert package is None and response.error == "Lesson package failed its exercise/derivation contract"
    assert response.total_tokens == 78 and len(wire.requests) == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_semantic_formula_failure_preserves_targeted_package_correction(provider, isolated):
    data = package_payload()
    data["workbook"]["title"] = PRIVATE_MARKER
    data["workbook"]["activities"][0]["fields"][0].update(kind="number", expression="missing_fact + 1")
    wire = WireFactory([data, package_payload()], provider)
    try:
        package, response, _ = await generate_package({}, {}, client_factory=wire)
    finally:
        await wire.close()
    assert package is not None and response.error is None
    retry = wire.user(1)
    assert "rejected_package" in retry and PRIVATE_MARKER in retry
    assert "STRUCTURAL VALIDATION SUMMARY" not in retry


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_malformed_private_patch_keeps_original_package_and_targeted_patch_mode(provider, isolated):
    original = LessonPackage.model_validate(package_payload())
    wire = WireFactory([
        {"field_patches": [{"activity_id": "guided"}]},
        {"field_patches": [{"activity_id": "guided", "field_id": "argument",
                            "criteria": ["Tests a substantive objection and revises the claim"]}]},
    ], provider)
    try:
        package, response, _ = await generate_package({}, {}, client_factory=wire,
                                                     prior_package=original, defects=["Correct the rubric"])
    finally:
        await wire.close()
    assert package is not None and package != original and response.error is None
    # The patch schema travels in the prompt or as the native schema, whichever mode it fits.
    assert "PrivatePackageRepair" in request_text(wire.requests[1])
    assert "rejected_patch" in wire.user(1) and "previous_package" in wire.user(1)
    assert "STRUCTURAL VALIDATION SUMMARY" not in wire.user(1)
    assert len(wire.requests) == 2 and all(wire.output_cap(index) == 5548 for index in range(2))
