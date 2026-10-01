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
    client.generate_json.assert_awaited_once()


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
