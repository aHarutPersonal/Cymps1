"""Strict wire parsing plus actual caller recovery, using local SDK streams."""
import json
from collections import Counter
from unittest.mock import AsyncMock

import pytest

from app.core.config import settings
from app.services.llm.protocol import JSONProtocolError, _complete_json_object
from app.services.llm.tracing import trace_context
from app.services.planning.lesson_package import LessonPackage, generate_package
from app.services.planning.lesson_review import review_lesson
from app.services.planning.lesson_writer import _GROUPS, _group_model, generate_lesson_sections
from app.services.planning.package_review import review_package
from tests.direct_wire import PROVIDERS, Reply, client_for, request_text, serve
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import structured_package_fixture
from tests.test_json_generation_errors import api_error, credit_error
from tests.test_lesson_section_writer import PACKAGE, complete_group


DUPLICATE = '{"workbook":{"title":"Complete synthetic title","title":""}}'


@pytest.fixture(autouse=True)
def safe_trace(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    record = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    token = trace_context.set({"trace_id": "test-protocol", "operation": "test_protocol"})
    yield record
    trace_context.reset(token)


@pytest.mark.parametrize("raw", [DUPLICATE, '{"value":NaN}', '{"value":Infinity}',
                                 '{"value":1e999}', '{"value":-1e999}', "[]", "null"])
def test_ambiguous_nonfinite_and_nonobject_documents_have_specific_type(raw):
    with pytest.raises(JSONProtocolError):
        _complete_json_object(raw)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("raw", [DUPLICATE, '{"value":NaN}', '{"value":1e999}', "[]", "", "   "])
async def test_real_collector_preserves_usage_but_never_accepts_protocol_failure(provider, raw, safe_trace):
    client = client_for(provider)
    wire = serve(client, Reply(raw, "stop"))
    response = await client.generate_json("System", "User")
    assert response.data == {}
    assert response.error.startswith(f"{provider} request failed (JSONProtocolError;")
    assert response.transport_success and not response.json_valid
    assert (response.prompt_tokens, response.completion_tokens, response.total_tokens) == (31, 47, 78)
    assert response.raw_response == raw and response.attempt_id
    assert all(stream.closed for stream in wire.streams)
    completed = [call.kwargs["response"] for call in safe_trace.call_args_list
                 if call.kwargs.get("result_status") == "transport_failed"]
    assert completed == [response] and completed[0].attempt_id == response.attempt_id
    assert response.retryable is None  # No automatic transport retry.


class WireFactory:
    """Exercise the real provider stream, strict decoder and response metadata."""
    def __init__(self, provider, operation, outcome):
        self.provider, self.operation, self.outcome = provider, operation, outcome
        self.counts = Counter()
        self.wires = []
        self.options = []
        self.models = {"LessonSectionGroup_" + group.name: _group_model(group) for group in _GROUPS}

    @property
    def streams(self):
        return [stream for wire in self.wires for stream in wire.streams]

    def __call__(self, **options):
        self.options.append(options)
        # Real transport options remain bounded by the caller's configuration.
        client = client_for(self.provider, timeout=options.get("timeout", 150.0),
                            max_tokens=options.get("max_tokens"), thinking_level=options.get("thinking_level"))
        self.wires.append(serve(client, self.respond))
        return client

    def respond(self, request):
        text = request_text(request)
        key = next((name for name in self.models if '"title": "' + name + '"' in text), self.operation)
        self.counts[key] += 1
        attempt = self.counts[key]
        if self.operation == "package":
            good = structured_package_fixture(package_payload())
        elif self.operation == "preflight":
            good = {"acceptable": True, "issues": []}
        elif self.operation == "review":
            good = {"acceptable": True, "issues": [], "practice_minutes": 40,
                    "contains_calculations": False, "calculations": []}
        else:
            good = complete_group(self.models[key])
        if self.outcome in {"no_finish", "recover"} and attempt > 1:
            return Reply(json.dumps(good), "stop")
        if self.outcome == "no_finish":
            return Reply('{"partial": ', None)  # the stream closed without a finish reason
        if self.outcome in {"recover", "two_bad"}:
            return Reply(DUPLICATE, "stop")
        if self.outcome == "value_error":
            return Reply(error=ValueError("Private implementation detail"))
        if self.outcome == "auth":
            return Reply(usage=None, open_error=api_error(self.provider, 401, {"message": "Private credentials"}))
        if self.outcome == "credit":
            return Reply(usage=None, open_error=credit_error(self.provider))
        return Reply("", "content_filter")  # a refusal


async def run_caller(operation, factory):
    if operation == "package":
        package, response, _ = await generate_package({}, {}, client_factory=factory)
        return package is not None, response
    if operation == "preflight":
        failures, response, _ = await review_package(
            LessonPackage.model_validate(package_payload()), {}, {}, client_factory=factory)
        return not failures, response
    if operation == "review":
        failures, response, _ = await review_lesson(
            {"lesson_content": "A substantive but non-numeric synthetic explanation.", "substeps": []},
            context={}, client_factory=factory)
        return not failures, response
    response, calls = await generate_lesson_sections(
        system_prompt="System", lesson_prompt="Lesson", package_context=PACKAGE, client_factory=factory)
    return response.error is None, (response, calls)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("operation", ["package", "preflight", "review", "writer"])
@pytest.mark.parametrize("outcome", ["recover", "two_bad", "value_error", "auth", "credit", "refusal", "no_finish"])
async def test_real_wire_errors_use_only_existing_bounded_caller_recovery(provider, operation, outcome, safe_trace):
    factory = WireFactory(provider, operation, outcome)
    accepted, result = await run_caller(operation, factory)
    assert accepted is (outcome in {"recover", "no_finish"})
    expected_calls = 2 if outcome in {"recover", "two_bad", "no_finish"} else 1
    assert factory.counts and all(count == expected_calls for count in factory.counts.values())
    assert all(stream.closed for stream in factory.streams)
    completed = [call.kwargs["response"] for call in safe_trace.call_args_list
                 if call.kwargs.get("result_status") in {"transport_failed", "transport_completed"}]
    assert len(completed) == sum(factory.counts.values())
    assert len({response.attempt_id for response in completed}) == len(completed)
    if outcome not in {"auth", "credit"}:
        assert all(response.total_tokens == 78 for response in completed)
    if outcome in {"recover", "two_bad"}:
        rejected = [response for response in completed if not response.json_valid]
        assert rejected and all(response.data == {} for response in rejected)
        # Preflight sanitizes its returned error, but metadata and raw usage
        # survive; other callers retain the specific protocol error category.
        assert all(response.raw_response == DUPLICATE for response in rejected)
    if operation == "writer":
        _, calls = result
        assert len(calls) == sum(factory.counts.values())
        if outcome not in {"auth", "credit"}:
            assert sum(response.total_tokens for _, response, *_ in calls) == 78 * len(calls)
    if outcome in {"auth", "credit"}:
        assert all(response.retryable is False for response in completed)


@pytest.mark.parametrize("inner", [
    '{"explanation":"Valid synthetic answer","checked":false,"checked":true}',
    '{"explanation":"Valid synthetic answer","checked":true,"value":NaN}',
])
def test_quoted_envelope_never_selects_conflicting_duplicate_or_nonfinite_value(inner):
    from app.services.llm.protocol import _unwrap_schema_answer
    from tests.test_json_response_envelopes import StructuredAnswer

    wrapper = {"answer": inner}
    assert _unwrap_schema_answer(wrapper, StructuredAnswer) is wrapper
    with pytest.raises(ValueError):
        StructuredAnswer.model_validate(wrapper)


def test_quoted_nonfinite_number_cannot_hide_behind_a_permissive_float_schema():
    from pydantic import BaseModel
    from app.services.llm.protocol import _unwrap_schema_answer

    class NumberAnswer(BaseModel):
        amount: float

    wrapper = {"answer": '{"amount":NaN}'}
    # Pydantic's ordinary float permits NaN: the strict wire boundary must
    # reject it independently rather than relying on a particular schema.
    assert NumberAnswer.model_validate({"amount": float("nan")})
    assert _unwrap_schema_answer(wrapper, NumberAnswer) is wrapper
