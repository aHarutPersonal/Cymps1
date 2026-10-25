from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.planning.lesson_review import (
    LessonReview, _validated_package_issue_targets, review_lesson,
)

PACKAGE = {"teaching_cases": [], "private_workbook": {"activities": [
    {"id": "revise", "kind": "practice", "title": "Revise", "instructions": "Revise the provided example.",
     "data": [], "fields": [{"id": "feedback", "kind": "text", "label": "Revision", "criteria": ["Correct the conflict"]}],
     "minutes_min": 20, "minutes_max": 30, "worked_solution": "Explain a valid revision."},
]}}


def verdict(targets):
    return LessonReview(acceptable=False, issues=[], package_issues=["The revision criterion contradicts the task."],
                        package_issue_targets=targets, practice_minutes=25,
                        contains_calculations=False, calculations=[])


@pytest.mark.parametrize("targets", [[], ["package"], ["practice.unknown"], ["practice.revise.missing"],
                                      ["practice.revise", "practice.revise.feedback"]])
def test_invalid_or_incomplete_independent_scope_grants_no_repair(targets):
    assert _validated_package_issue_targets(verdict(targets), PACKAGE) == []


@pytest.mark.parametrize("target", ["practice.revise", "practice.revise.feedback"])
def test_independent_verdict_preserves_exact_owner_scope(target):
    assert _validated_package_issue_targets(verdict([target]), PACKAGE) == [target]


@pytest.mark.asyncio
async def test_negative_final_review_carries_validated_scope_to_repair():
    response = SimpleNamespace(data=verdict(["practice.revise.feedback"]).model_dump(mode="json"),
                               error=None, effective_parameters={})
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, reviewed, _ = await review_lesson(
        {"lesson_content": "Revise the provided fictional scene and explain the change."},
        client_factory=lambda **kw: client, context={"lesson_package": PACKAGE})
    assert failures == ["The revision criterion contradicts the task."]
    assert reviewed.effective_parameters["validated_repair_targets"] == ["practice.revise.feedback"]
    assert reviewed.data["acceptable"] is False
