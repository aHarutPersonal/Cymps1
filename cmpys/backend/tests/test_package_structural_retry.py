"""A malformed package gets one clean reconstruction, never a relaxed parser."""
import copy
import json
from unittest.mock import AsyncMock

import httpx
import pytest
from openai import AsyncOpenAI

from app.core.config import settings
from app.services.planning.lesson_package import LessonPackage, generate_package
from tests.lesson_package_fixtures import package_payload as legacy_package_payload
from tests.section_client_fixture import structured_package_fixture
from tests.test_json_generation_errors import client_for


PRIVATE_MARKER = "REJECTED_DRAFT_MUST_NOT_ENTER_STRUCTURAL_RETRY"


def package_payload():
    return structured_package_fixture(legacy_package_payload())


class WireFactory:
    """Capture actual SDK request bodies while the real streaming parser runs."""

    def __init__(self, responses):
        self.responses = responses
        self.requests = []
        self.options = []
        self.http = httpx.AsyncClient(transport=httpx.MockTransport(self.respond))
        self.sdk = AsyncOpenAI(api_key="test-only", base_url="https://api.z.ai/api/paas/v4",
                               max_retries=0, http_client=self.http)

    async def respond(self, request):
        self.requests.append(json.loads(request.content))
        assert len(self.requests) <= len(self.responses), "Unexpected extra paid request"
        data = self.responses[len(self.requests) - 1]
        event = {"id": f"local-{len(self.requests)}", "object": "chat.completion.chunk",
                 "created": 0, "model": "glm-5.3",
                 "choices": [{"index": 0, "delta": {"content": json.dumps(data)}, "finish_reason": "stop"}],
                 "usage": {"prompt_tokens": 31, "completion_tokens": 47, "total_tokens": 78}}
        return httpx.Response(200, headers={"content-type": "text/event-stream"},
                              content="data: " + json.dumps(event) + "\n\ndata: [DONE]\n\n")

    def __call__(self, **options):
        self.options.append(options)
        client = client_for("zai")
        client.timeout = options["timeout"]
        client.max_tokens = options["max_tokens"]
        client._get_client = lambda key: self.sdk
        return client


@pytest.fixture
def isolated(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    monkeypatch.setattr(settings, "zai_reasoning_token_reserve", 2048)
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
@pytest.mark.parametrize("kind", ["missing", "extra", "list", "model", "many", "hierarchy"])
async def test_structural_retry_uses_original_context_and_never_replays_rejected_source(kind, isolated):
    draft = malformed(kind)
    original = copy.deepcopy(draft)
    wire = WireFactory([draft, package_payload()])
    try:
        package, response, _ = await generate_package(
            {"id": "step_1", "title": "Preserve original task"},
            {"locale": "hy", "goal": "Preserve original objective"}, client_factory=wire)
    finally:
        await wire.sdk.close()
    assert package == LessonPackage.model_validate(package_payload())
    assert response.error is None and response.total_tokens == 78
    assert draft == original
    assert len(wire.requests) == 2 and len(wire.options) == 1
    assert wire.options[0] == {"tier": "balanced", "timeout": 120, "max_tokens": 6500,
                               "thinking_level": "low", "allow_fallback": False}
    assert all(request["max_tokens"] == 8548 for request in wire.requests)
    retry = wire.requests[1]["messages"]
    assert PRIVATE_MARKER not in json.dumps(retry)
    assert "rejected_package" not in json.dumps(retry)
    original_user = wire.requests[0]["messages"][1]["content"]
    assert retry[1]["content"].startswith(original_user)
    summary = json.loads(retry[1]["content"].split("STRUCTURAL VALIDATION SUMMARY (untrusted diagnostic data):\n")[1])
    assert 1 <= len(summary["errors"]) <= 12
    assert len(json.dumps(summary)) < 2200
    assert all(set(error) == {"type", "loc"} for error in summary["errors"])
    assert "NEW COMPLETE LessonPackage" in retry[0]["content"]
    assert "never another derived result ID" in retry[0]["content"]
    assert "worked_solution, minutes_min, minutes_max" in retry[0]["content"]
    if kind == "many":
        assert summary["additional_errors"] > 0
        assert all(error["loc"] == ["<unknown>"] for error in summary["errors"])
    rejected = [call.kwargs for call in isolated.await_args_list
                if call.kwargs.get("operation") == "lesson_package_repair"]
    assert len(rejected) == 1 and rejected[0]["response"].total_tokens == 78


@pytest.mark.asyncio
async def test_two_structural_failures_remain_terminal_without_a_third_request(isolated):
    wire = WireFactory([malformed("hierarchy"), {"teaching_cases": []}])
    try:
        package, response, _ = await generate_package({}, {}, client_factory=wire)
    finally:
        await wire.sdk.close()
    assert package is None and response.error == "Lesson package failed its exercise/derivation contract"
    assert response.total_tokens == 78 and len(wire.requests) == 2


@pytest.mark.asyncio
async def test_semantic_formula_failure_preserves_targeted_package_correction(isolated):
    data = package_payload()
    data["workbook"]["title"] = PRIVATE_MARKER
    data["workbook"]["activities"][0]["fields"][0].update(kind="number", expression="missing_fact + 1")
    wire = WireFactory([data, package_payload()])
    try:
        package, response, _ = await generate_package({}, {}, client_factory=wire)
    finally:
        await wire.sdk.close()
    assert package is not None and response.error is None
    retry = wire.requests[1]["messages"][1]["content"]
    assert "rejected_package" in retry and PRIVATE_MARKER in retry
    assert "STRUCTURAL VALIDATION SUMMARY" not in retry


@pytest.mark.asyncio
async def test_malformed_private_patch_keeps_original_package_and_targeted_patch_mode(isolated):
    original = LessonPackage.model_validate(package_payload())
    wire = WireFactory([
        {"field_patches": [{"activity_id": "guided"}]},
        {"field_patches": [{"activity_id": "guided", "field_id": "argument",
                            "criteria": ["Tests a substantive objection and revises the claim"]}]},
    ])
    try:
        package, response, _ = await generate_package({}, {}, client_factory=wire,
                                                     prior_package=original, defects=["Correct the rubric"])
    finally:
        await wire.sdk.close()
    assert package is not None and package != original and response.error is None
    retry = wire.requests[1]["messages"]
    assert "PrivatePackageRepair" in retry[0]["content"]
    assert "rejected_patch" in retry[1]["content"] and "previous_package" in retry[1]["content"]
    assert "STRUCTURAL VALIDATION SUMMARY" not in retry[1]["content"]
    assert len(wire.requests) == 2 and all(request["max_tokens"] == 5548 for request in wire.requests)
