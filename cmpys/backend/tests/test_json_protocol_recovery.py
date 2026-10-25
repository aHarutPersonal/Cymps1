"""Strict wire parsing plus actual caller recovery, using local SDK streams."""
import json
from collections import Counter
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock

import pytest
from openai import AuthenticationError, RateLimitError

from app.core.config import settings
from app.services.llm.openlux import JSONProtocolError, _complete_json_object
from app.services.llm.tracing import trace_context
from app.services.planning.lesson_package import LessonPackage, generate_package
from app.services.planning.lesson_review import review_lesson
from app.services.planning.lesson_writer import _GROUPS, _group_model, generate_lesson_sections
from app.services.planning.package_review import review_package
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import structured_package_fixture
from tests.test_json_generation_errors import api_error, client_for
from tests.test_lesson_section_writer import PACKAGE, complete_group
from tests.test_openlux import Stream, chunk, transport


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
@pytest.mark.parametrize("provider", ["zai", "openlux"])
@pytest.mark.parametrize("raw", [DUPLICATE, '{"value":NaN}', '{"value":1e999}', "[]", "", "   "])
async def test_real_collector_preserves_usage_but_never_accepts_protocol_failure(monkeypatch, provider, raw, safe_trace):
    client = client_for(provider)
    usage = NS(prompt_tokens=31, completion_tokens=47, total_tokens=78)
    stream, _ = transport(monkeypatch, client, [chunk(raw, "stop"), NS(choices=[], usage=usage)])
    response = await client.generate_json("System", "User")
    assert response.data == {} and "JSONProtocolError; finish=stop" in response.error
    assert response.retryable is None  # No automatic transport retry.
    assert response.transport_success and not response.json_valid
    assert (response.prompt_tokens, response.completion_tokens, response.total_tokens) == (31, 47, 78)
    assert response.raw_response == raw and response.attempt_id
    assert stream.closed
    completed = [call.kwargs["response"] for call in safe_trace.call_args_list
                 if call.kwargs.get("result_status") == "transport_failed"]
    assert completed == [response] and completed[0].attempt_id == response.attempt_id


class WireFactory:
    """Exercise the real provider stream, strict decoder and response metadata."""
    def __init__(self, provider, operation, outcome):
        self.provider, self.operation, self.outcome = provider, operation, outcome
        self.counts = Counter()
        self.streams = []
        self.options = []
        self.models = {"LessonSectionGroup_" + group.name: _group_model(group) for group in _GROUPS}

    def __call__(self, **options):
        self.options.append(options)
        client = client_for(self.provider)
        # Real transport options remain bounded by the caller's configuration.
        client.timeout = options.get("timeout", client.timeout)
        client.max_tokens = options.get("max_tokens", client.max_tokens)

        async def create(**request):
            system = request["messages"][0]["content"]
            key = next((name for name in self.models if '"title": "' + name + '"' in system), self.operation)
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
            usage = NS(prompt_tokens=31, completion_tokens=47, total_tokens=78)
            if self.outcome == "recover" and attempt > 1:
                events = [chunk(json.dumps(good), "stop"), NS(choices=[], usage=usage)]
            elif self.outcome in {"recover", "two_bad"}:
                events = [chunk(DUPLICATE, "stop"), NS(choices=[], usage=usage)]
            elif self.outcome == "value_error":
                events = [NS(choices=[], usage=usage), ValueError("Private implementation detail")]
            elif self.outcome == "auth":
                events = [api_error(AuthenticationError, 401, {"message": "Private credentials"})]
            elif self.outcome == "credit":
                events = [api_error(RateLimitError, 429, {"code": "1113" if self.provider == "zai" else "insufficient_quota"})]
            else:
                events = [chunk("", "content_filter"), NS(choices=[], usage=usage)]
            stream = Stream(events)
            self.streams.append(stream)
            return stream

        client._get_client = lambda key: NS(chat=NS(completions=NS(create=create)))
        return client


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
@pytest.mark.parametrize("provider", ["zai", "openlux"])
@pytest.mark.parametrize("operation", ["package", "preflight", "review", "writer"])
@pytest.mark.parametrize("outcome", ["recover", "two_bad", "value_error", "auth", "credit", "refusal"])
async def test_real_wire_errors_use_only_existing_bounded_caller_recovery(provider, operation, outcome, safe_trace):
    factory = WireFactory(provider, operation, outcome)
    accepted, result = await run_caller(operation, factory)
    assert accepted is (outcome == "recover")
    expected_calls = 2 if outcome in {"recover", "two_bad"} else 1
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
    from app.services.llm.openlux import _unwrap_schema_answer
    from tests.test_json_response_envelopes import StructuredAnswer

    wrapper = {"answer": inner}
    assert _unwrap_schema_answer(wrapper, StructuredAnswer) is wrapper
    with pytest.raises(ValueError):
        StructuredAnswer.model_validate(wrapper)


def test_quoted_nonfinite_number_cannot_hide_behind_a_permissive_float_schema():
    from pydantic import BaseModel
    from app.services.llm.openlux import _unwrap_schema_answer

    class NumberAnswer(BaseModel):
        amount: float

    wrapper = {"answer": '{"amount":NaN}'}
    # Pydantic's ordinary float permits NaN: the strict wire boundary must
    # reject it independently rather than relying on a particular schema.
    assert NumberAnswer.model_validate({"amount": float("nan")})
    assert _unwrap_schema_answer(wrapper, NumberAnswer) is wrapper
