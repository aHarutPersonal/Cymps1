"""Provider JSON wrappers must not force expensive valid content rewrites."""
import json

import pytest
from pydantic import BaseModel, ConfigDict, Field

from app.core.config import settings
from app.services.llm.protocol import _complete_json_object, _unwrap_schema_answer
from tests.direct_wire import PROVIDERS, Reply, client_for, serve


class StructuredAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")
    explanation: str = Field(min_length=5)
    checked: bool


VALID = {"explanation": "A complete answer", "checked": True}


@pytest.fixture(autouse=True)
def no_admission_network(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})


@pytest.mark.parametrize('raw', [
    '```json\n{"explanation":"A complete answer","checked":true}\n```',
    '{"explanation":"A complete\nanswer","checked":true}',
])
def test_lossless_complete_json_framing(raw):
    parsed = _complete_json_object(raw)
    assert StructuredAnswer.model_validate(parsed).checked
    assert 'complete' in parsed['explanation']


@pytest.mark.parametrize('raw', [
    '```json\n{"checked":true}',
    'Here is the answer: {"checked":true}',
    '{"checked":true} {"checked":false}',
    '{"checked":true,"checked":false}',
    '{"checked":NaN}',
    '{"checked":true,}',
    '{"checked":true',
])
def test_json_framing_never_guesses_or_selects_ambiguous_content(raw):
    with pytest.raises(ValueError):
        _complete_json_object(raw)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_complete_fenced_stream_is_decoded_but_truncation_is_rejected(provider):
    client = client_for(provider)
    raw = '```json\n' + json.dumps(VALID) + '\n```'
    serve(client, Reply(raw, 'stop'))
    response = await client.generate_json('System', 'User', output_model=StructuredAnswer)
    assert response.error is None and response.data == VALID
    serve(client, Reply(raw, 'length'))
    response = await client.generate_json('System', 'User', output_model=StructuredAnswer)
    assert response.error and response.data == {}


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("quoted", [False, True])
async def test_complete_wrapped_schema_recovered_without_new_call(provider, quoted):
    # A wrapper can only arrive on the prompt-JSON wire; native schemas constrain decoding.
    client = client_for(provider, json_mode="prompt")
    wrapped = {"answer": json.dumps(VALID) if quoted else VALID}
    raw = json.dumps(wrapped)
    wire = serve(client, Reply(raw, "stop"))
    response = await client.generate_json("System", "User", output_model=StructuredAnswer)
    assert response.error is None
    assert response.data == VALID
    assert response.raw_response == raw
    assert len(wire.requests) == 1
    assert all(stream.closed for stream in wire.streams)


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
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("json_mode", ["auto", "prompt"])
async def test_truncated_stream_wrapper_is_rejected(provider, json_mode):
    client = client_for(provider, json_mode=json_mode)
    serve(client, Reply(json.dumps({"answer": VALID}), "length"))
    response = await client.generate_json("System", "User", output_model=StructuredAnswer)
    assert response.error and response.data == {}
