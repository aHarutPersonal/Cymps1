"""Review failures remain strict, diagnosable, and accurately measured."""
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.telemetry import usage_record_from_response
from app.services.planning.lesson_review import review_lesson, review_response_quality


def _review(**changes):
    return {
        "acceptable": True,
        "issues": [],
        "advisories": ["Optional external clock; no app timer is required."],
        "practice_minutes": 46,
        "contains_calculations": False,
        "calculations": [],
        **changes,
    }


@pytest.mark.asyncio
@pytest.mark.parametrize("payload,expected", [
    ({"answer": "PRIVATE_LESSON_TEXT"}, "acceptable: missing"),
    (_review(advisories="PRIVATE_LESSON_TEXT"), "advisories: list_type"),
    (_review(calculations=[{"location": "PRIVATE_LESSON_TEXT"}]), "calculations.0.expression: missing"),
    (_review(PRIVATE_LESSON_TEXT="PRIVATE_LESSON_TEXT"), "<unknown_field>: extra_forbidden"),
    (None, "review: model_type"),
])
async def test_schema_failure_has_safe_persistable_diagnostics(payload, expected, caplog):
    response = SimpleNamespace(error=None, data=payload)
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "PRIVATE_LESSON_TEXT"},
        client_factory=lambda **kwargs: client, context={},
    )
    assert returned is response
    assert failures == [response.error]
    assert expected in response.error
    assert "PRIVATE_LESSON_TEXT" not in response.error + caplog.text
    usage = usage_record_from_response(operation="plan_item_detail_generation", response=response)
    assert not usage.success
    assert usage.metadata["error"] == response.error
    assert review_response_quality(response) == 0.0
    assert client.generate_json.await_count == 2


@pytest.mark.parametrize("payload,score", [
    (_review(), 1.0),
    (_review(acceptable=False), 0.0),
    (_review(issues=["The required answer key is missing."]), 0.0),
    (_review(contains_calculations=True), 0.0),
    (_review(contains_calculations=True, calculations=[{
        "location": "case answer", "expression": "4 + 2", "claimed_result": 7,
    }]), 0.0),
    (_review(calculations=[{
        "location": "case answer", "expression": "4 + 2", "claimed_result": 6,
    }]), 1.0),
    ({"answer": "not a valid review"}, 0.0),
])
def test_review_telemetry_scores_contract_instead_of_lesson_word_count(payload, score):
    assert review_response_quality(SimpleNamespace(data=payload, error=None)) == score


@pytest.mark.asyncio
async def test_valid_review_retains_approval_and_advisories():
    response = SimpleNamespace(error=None, data=_review())
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "Useful teaching content"},
        client_factory=lambda **kwargs: client, context={},
    )
    assert not failures
    assert returned.error is None
    assert returned.data["advisories"]
    assert review_response_quality(returned) == 1.0


@pytest.mark.asyncio
async def test_invalid_review_retried_without_rewriting_lesson():
    invalid = SimpleNamespace(error=None, data=_review(calculations=[{
        "location": "example", "expression": "2+2", "claimed_result": 4,
        "absolute_tolerance": 1,
    }]))
    valid = SimpleNamespace(error=None, data=_review(calculations=[{
        "location": "example", "expression": "2+2", "claimed_result": 4,
        "absolute_tolerance": 0.01,
    }]))
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[invalid, valid]))
    failures, response, _ = await review_lesson(
        {"lesson_content": "Keep this complete lesson"}, client_factory=lambda **kw: client, context={})
    assert not failures and response is valid
    first, second = client.generate_json.await_args_list
    assert first.kwargs["user_prompt"] == second.kwargs["user_prompt"]
    assert "less_than_equal" in second.kwargs["system_prompt"]


@pytest.mark.asyncio
async def test_negative_content_review_is_not_retried_for_approval():
    negative = SimpleNamespace(error=None, data=_review(acceptable=False, issues=["Incorrect calculation"]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=negative))
    failures, _, _ = await review_lesson(
        {"lesson_content": "Wrong example"}, client_factory=lambda **kw: client, context={})
    assert failures == ["Incorrect calculation"]
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize('expression,claimed,source,approved', [
    ('(60-40)/60*100', 33.3, 'Margin of safety: 33.3%.', True),
    ('(20.5333-15)/20.5333*100', 26.97, 'Discount: 26.97%.', False),
    ('(20.5333-15)/20.5333*100', 26.95, 'Discount: 26.95%.', True),
    ('10*(1540000/750000)', 20.5, 'Value is $20.5.', True),
    ('10*(1540000/750000)', 20.5, 'Value is $20.50.', False),
    ('10*(1540000/750000)', 20.5, 'Value 20.5; table value 20.50.', False),
    ('(24-20.50)/20.50*100', 17, 'Premium: 17%.', True),
    ('100/3', 33.3, 'No numeric result was supplied.', False),
    ('4+2', 7, 'Result: 7.', False),
    ('-100/3', -33.3, 'Result: -33.3.', True),
    ('2.675', 2.68, 'Result: 2.68.', True),
    ('10000/3', 3333.3, 'Result: 3,333.3.', True),
])
async def test_review_uses_actual_displayed_precision(expression, claimed, source, approved):
    from app.services.llm.client import LLMResponse
    response = LLMResponse(data=_review(contains_calculations=True, calculations=[{
        'location': 'worked example', 'expression': expression, 'claimed_result': claimed,
        'absolute_tolerance': 0.01, 'claimed_literal': '0',
    }]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(
        {'lesson_content': source}, client_factory=lambda **kw: client, context={})
    assert (not failures) == approved
    assert review_response_quality(returned) == float(approved)
    client.generate_json.assert_awaited_once()
