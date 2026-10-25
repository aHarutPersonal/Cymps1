"""Malformed editorial rejections cannot be retried into approval."""
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_review import review_lesson, review_response_quality


@pytest.mark.asyncio
@pytest.mark.parametrize("context", [{}, {"lesson_package": {"teaching_cases": []}}])
@pytest.mark.parametrize("rejection", [
    {"acceptable": False, "issues": []},
    {"acceptable": True, "issues": ["Required independent practice is missing."]},
    {"acceptable": True, "issues": [], "package_issues": ["The answer key is wrong."]},
])
async def test_missing_required_review_field_preserves_negative_verdict(context, rejection, monkeypatch):
    telemetry = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    first = LLMResponse(data={
        **rejection, "contains_calculations": False, "calculations": [],
        # practice_minutes deliberately absent, as in the observed failure.
    })
    approval = LLMResponse(data={
        "acceptable": True, "issues": [], "practice_minutes": 40,
        "contains_calculations": False, "calculations": [],
    })
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[first, approval]))
    failures, response, _ = await review_lesson(
        {"lesson_content": "A qualitative lesson."},
        client_factory=lambda **_: client, context=context,
    )
    assert failures and response is first
    assert "practice_minutes: missing" in response.error
    assert response.data == first.data
    assert review_response_quality(response) == 0
    client.generate_json.assert_awaited_once()
    telemetry.assert_not_awaited()
