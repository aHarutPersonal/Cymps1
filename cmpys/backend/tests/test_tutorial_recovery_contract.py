"""Regression coverage for the failed short writing tutorial."""
from copy import deepcopy

import pytest
from pydantic import ValidationError

from app.services.planning.activity_draft import LessonActivityDraft, TutorialActivityDraft
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import review_package
from tests.lesson_package_fixtures import multi_choice_first, package_payload
from tests.test_activity_draft import draft_payload


@pytest.mark.asyncio
async def test_noop_private_patch_recovers_only_independently_rejected_activity(monkeypatch):
    from types import SimpleNamespace
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_package import generate_package
    from tests.test_scoped_activity_repair import structured_package, replacement
    from tests.section_client_fixture import activity_draft_fixture
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    prior = structured_package()
    payload = prior.model_dump(mode="json")
    for activity in payload["workbook"]["activities"]:
        multi_choice_first(activity)  # a new tutorial needs a number or multi_choice answer
    prior = LessonPackage.model_validate(payload)
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data={}), LLMResponse(data=activity_draft_fixture(multi_choice_first(replacement())))]))
    result, response, _ = await generate_package({"lesson_format": "tutorial_v1"}, {},
        client_factory=lambda **kw: client, prior_package=prior,
        defects=["The response label exposes the answer and needs correction."],
        repair_targets=["practice.transfer.argument"])
    assert result and not response.error and not response.semantic_accepted
    assert result.workbook.activities[0] == prior.workbook.activities[0]
    assert result.workbook.activities[1].fields[1] == prior.workbook.activities[1].fields[1]
    assert client.generate_json.await_count == 2
    assert issubclass(client.generate_json.call_args.kwargs["output_model"], TutorialActivityDraft)
    # The one-shot repair must not steer a tutorial into the text-only shape its own wire rejects.
    repair_prompt = " ".join(client.generate_json.call_args.kwargs["system_prompt"].split())
    assert "keeps at least one number or multi_choice field" in repair_prompt
    assert "at most one text field" in repair_prompt


def test_tutorial_wire_rejects_long_quiz_without_changing_long_lessons():
    raw = draft_payload()
    LessonActivityDraft.model_validate(raw)
    with pytest.raises(ValidationError, match="at most 2"):
        TutorialActivityDraft.model_validate(raw)
    raw["fields"] = raw["fields"][:2]
    assert len(TutorialActivityDraft.model_validate(raw).fields) == 2
    assert TutorialActivityDraft.model_json_schema()["properties"]["fields"]["maxItems"] == 2


@pytest.mark.asyncio
async def test_unreviewable_tutorial_fails_before_provider_and_authorizes_only_affected_activity():
    payload = package_payload()
    for a in payload["workbook"]["activities"]:
        a.update(minutes_min=1, minutes_max=2)
    affected = payload["workbook"]["activities"][0]
    original = affected["fields"][0]
    affected["fields"] = [{**deepcopy(original), "id": f"response_{i}"} for i in range(7)]
    package = LessonPackage.model_validate(payload)
    original = package.model_dump(mode="json")

    def forbidden(**kwargs):
        raise AssertionError("Invalid task should be repaired before paid review")

    failures, response, _ = await review_package(package, {"lesson_format": "tutorial_v1"},
        {"allotted_lesson_minutes": 7}, client_factory=forbidden)
    assert failures and not response.semantic_accepted
    assert response.effective_parameters["request_count"] == 0
    assert response.effective_parameters["validated_repair_targets"] == ["practice.guided"]
    assert package.model_dump(mode="json") == original
