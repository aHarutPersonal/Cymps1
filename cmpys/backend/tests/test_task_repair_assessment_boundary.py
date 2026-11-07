"""Capture the task-level repair requests, including paths outside section writer."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.tasks.plans import _generate_plan_item_details_parallel, _lesson_prose_repair_context
from tests.lesson_package_fixtures import multi_choice_first
from tests.test_short_tutorial_pipeline import short_package, outline, sections


def assessment_package(*, numeric=False):
    raw = short_package().model_dump(mode="json")
    first = multi_choice_first(raw["workbook"]["activities"][0])
    first["instructions"] = "ASSESSMENT_SCENARIO_SENTINEL: inspect this distinct case and select the supported parts."
    first["fields"][0]["label"] = "ASSESSMENT_LABEL_SENTINEL"
    first["fields"][0]["choices"][0]["label"] = "ASSESSMENT_CHOICE_SENTINEL"
    first["worked_solution"]["steps"][0]["explanation"] = "PRIVATE_SOLUTION_SENTINEL explains the keyed selection using this assessed scenario."
    raw["teaching_cases"] = [{"id": "public_case", "assumptions":
        "PUBLIC_TEACHING_SENTINEL: an original fictional teaching example with a fully explained revision.",
        "data": [], "results": []}]
    if numeric:
        raw["teaching_cases"][0].update(
            data=[{"id": "first", "label": "First batch", "value": 11},
                  {"id": "second", "label": "Second batch", "value": 7}],
            results=[{"id": "total", "label": "Combined batch", "expression": "first+second",
                      "unit": "items", "decimal_places": 0}])
    return LessonPackage.model_validate(raw)


@pytest.mark.asyncio
@pytest.mark.parametrize("repair_path", ["binding", "semantic"])
async def test_task_level_tutorial_repair_prompts_omit_assessment_but_keep_teaching_and_timing(monkeypatch, repair_path):
    package = assessment_package(numeric=repair_path == "binding")
    before = package.model_dump_json()
    captured = []
    reviews = []
    writer_prompts = []
    private_review_issue = "The public framework conflicts with PRIVATE_REVIEWER_KEY_SENTINEL " + \
        "from ASSESSMENT_SCENARIO_SENTINEL; the private answer is PRIVATE_SOLUTION_SENTINEL."

    async def build(*_args, **_kwargs):
        return package, LLMResponse(data={}), None

    async def preflight(*_args, **_kwargs):
        return [], LLMResponse(data={}), None

    async def writer(**_kwargs):
        writer_prompts.append(_kwargs["lesson_prompt"])
        # Deliberately omit a required result token to exercise the outer
        # binding safety net; semantic mode is a valid draft needing revision.
        return LLMResponse(data=sections()), []

    async def review(*_args, **_kwargs):
        verdict = LLMResponse(data={"issues": [private_review_issue],
            "package_issues": [], "affected_sections": ["core_framework"], "practice_minutes": 3})
        reviews.append(verdict)
        return [private_review_issue], verdict, None

    class Client:
        model = "offline-captured-repair"
        async def generate_json(self, **kwargs):
            captured.append(kwargs["user_prompt"])
            # Stop after capturing the actual request: this test verifies the
            # exposure boundary, not a mocked content approval.
            return LLMResponse(data={}, error="Captured offline repair request")

    monkeypatch.setattr("app.services.planning.package_builder.generate_initial_package", build)
    monkeypatch.setattr("app.services.planning.package_preflight.review_package", preflight)
    monkeypatch.setattr("app.services.planning.lesson_writer.generate_lesson_sections", writer)
    monkeypatch.setattr("app.services.planning.lesson_review.review_lesson", review)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="Teach", task_title="Claim", mission_hours=0.1,
        user_goal="Reason", learning_preferences="examples", idol_name="Mentor", idol_domain="writing",
        idol_evidence={}, session_context="", active_tier="balanced", routing_reason="test",
        client_factory=lambda **_kwargs: Client(), lesson_format="tutorial_v1",
        existing_checkpoint={"_generation": {"outline": outline(1), "outline_contract_version": 3}})
    assert error and captured
    assert any(repair_path + "_repair" in call[0] for call in calls)
    for prompt in captured:
        assert "PUBLIC_TEACHING_SENTINEL" in prompt
        assert "workload_contract" in prompt and '"minutes_min": 1' in prompt and '"minutes_max": 2' in prompt
        assert '"activity_id": "guided"' in prompt
        for marker in ("ASSESSMENT_SCENARIO_SENTINEL", "ASSESSMENT_LABEL_SENTINEL",
                       "ASSESSMENT_CHOICE_SENTINEL", "PRIVATE_SOLUTION_SENTINEL",
                       "PRIVATE_REVIEWER_KEY_SENTINEL"):
            assert marker not in prompt
    if repair_path == "semantic":
        assert len(writer_prompts) == 2  # Failed targeted repair reaches the full-writer fallback.
        assert all('"affected_sections": ["core_framework"]' in prompt for prompt in captured)
        assert '"field_name": "core_framework"' in captured[0]
        assert '"affected_sections": ["core_framework"]' in writer_prompts[1]
        for prompt in writer_prompts:
            for marker in ("PRIVATE_REVIEWER_KEY_SENTINEL", "ASSESSMENT_SCENARIO_SENTINEL",
                           "PRIVATE_SOLUTION_SENTINEL"):
                assert marker not in prompt
        assert reviews and all(verdict.data["issues"] == [private_review_issue] for verdict in reviews)
    assert package.model_dump_json() == before


def test_long_lesson_repairs_keep_the_existing_public_workbook_context():
    package = assessment_package()
    before = copy.deepcopy(package.writer_context())
    assert _lesson_prose_repair_context(package, lesson_format=None) == before
    context = _lesson_prose_repair_context(package, lesson_format="tutorial_v1", allotted_lesson_minutes=6)
    assert "practice" not in context
    assert context["workload_contract"]["allowed_total_minutes_range"] == [6, 6]
    assert context["workload_contract"]["reading_minutes_range"] == [3, 3]
