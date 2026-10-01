"""Provider JSON wrappers must not force expensive valid content rewrites."""
import json

import pytest
from pydantic import BaseModel, ConfigDict, Field

from app.services.llm.openlux import OpenLuxLLMClient, _unwrap_schema_answer
from app.services.llm.zai import ZaiLLMClient
from tests.test_openlux import chunk, transport


class StructuredAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")
    explanation: str = Field(min_length=5)
    checked: bool


VALID = {"explanation": "A complete answer", "checked": True}


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", ["openlux", "zai"])
@pytest.mark.parametrize("streaming", [False, True])
@pytest.mark.parametrize("quoted", [False, True])
async def test_complete_wrapped_schema_recovered_without_new_call(
    monkeypatch, provider, streaming, quoted
):
    factory = ZaiLLMClient if provider == "zai" else OpenLuxLLMClient
    client = factory(
        api_key="fake-envelope-test-key",
        model="glm-5.3" if provider == "zai" else "gpt-5.6-terra",
        base_url="https://api.z.ai/api/paas/v4" if provider == "zai" else "https://api.openlux.ai/v1",
    )
    wrapped = {"answer": json.dumps(VALID) if quoted else VALID}
    raw = json.dumps(wrapped)
    stream, _ = transport(monkeypatch, client, [chunk(raw, "stop")])
    method = client.generate_json_streaming if streaming else client.generate_json
    response = await method("System", "User", output_model=StructuredAnswer)
    assert response.error is None
    assert response.data == VALID
    assert response.raw_response == raw
    assert stream.closed


@pytest.mark.parametrize("data", [
    {"answer": '{"explanation":"unfinished'},
    {"answer": []},
    {"answer": {"explanation": "short missing required boolean"}},
    {"answer": {**VALID, "unexpected": "must not be stripped"}},
    {"answer": {"answer": VALID}},
    {"answer": VALID, "error": "ambiguous response"},
])
def test_invalid_or_ambiguous_wrappers_never_escape_schema_checks(data):
    assert _unwrap_schema_answer(data, StructuredAnswer) is data


def test_declared_answer_field_and_unknown_schema_preserved():
    class ActualAnswer(BaseModel):
        answer: str

    data = {"answer": json.dumps(VALID)}
    assert _unwrap_schema_answer(data, ActualAnswer) is data
    assert _unwrap_schema_answer(data, None) is data


@pytest.mark.parametrize("blocking", [False, True])
def test_review_envelope_keeps_editorial_and_semantic_checks(blocking):
    from app.services.planning.lesson_review import LessonReview

    review = {
        "acceptable": True,
        "issues": ["Promised answer key is missing"] if blocking else [],
        "advisories": ["Minor wording improvement"],
        "practice_minutes": 40,
        "contains_calculations": False,
        "calculations": [],
    }
    recovered = _unwrap_schema_answer({"answer": json.dumps(review)}, LessonReview)
    assert recovered == review
    assert bool(LessonReview.model_validate(recovered).failures()) is blocking


def test_wrapped_review_cannot_approve_wrong_arithmetic():
    from app.services.planning.lesson_review import LessonReview

    review = {
        "acceptable": True, "issues": [], "practice_minutes": 40,
        "contains_calculations": True,
        "calculations": [{
            "location": "Worked example", "expression": "2 + 2", "claimed_result": 5,
        }],
    }
    recovered = _unwrap_schema_answer({"answer": json.dumps(review)}, LessonReview)
    assert recovered == review
    assert LessonReview.model_validate(recovered).failures()


@pytest.mark.asyncio
async def test_truncated_stream_wrapper_is_rejected(monkeypatch):
    client = ZaiLLMClient(
        api_key="fake-envelope-test-key", model="glm-5.3",
        base_url="https://api.z.ai/api/paas/v4",
    )
    transport(monkeypatch, client, [chunk(json.dumps({"answer": VALID}), "length")])
    response = await client.generate_json("System", "User", output_model=StructuredAnswer)
    assert response.error and response.data == {}
