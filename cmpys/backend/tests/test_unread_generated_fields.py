"""The model is not asked for constants the server fills or fields no screen renders."""
import copy
from pathlib import Path

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanBackboneWeek, PlanTutorialOutlineOutput
from app.services.planning.generator import validate_plan_contract
from app.tasks.plans import _validate_plan_detail_outline_response
from tests.test_plan_execution_contract import _plan
from tests.test_short_tutorial_pipeline import outline

PROMPTS = Path(__file__).resolve().parents[2] / "prompts"


def _strip_outline_constants(raw: dict) -> dict:
    raw = copy.deepcopy(raw)
    raw.pop("lesson_format")
    for step in raw["steps"]:
        step.pop("lesson_format")
    for material in raw["materials"]:
        for key in ("content_markdown", "ideas", "canonical_hint", "source_strategy"):
            material.pop(key, None)
    return raw


def test_outline_without_constants_matches_stored_shape():
    full = outline(3)
    expected = LLMResponse(data=copy.deepcopy(full))
    _validate_plan_detail_outline_response(expected, minimum_lessons=1, maximum_lessons=20, tutorial=True)
    stripped = LLMResponse(data=_strip_outline_constants(full))
    _validate_plan_detail_outline_response(stripped, minimum_lessons=1, maximum_lessons=20, tutorial=True)
    assert expected.error is None and stripped.error is None
    assert stripped.data["lesson_format"] == "tutorial_v1"
    assert {step["lesson_format"] for step in stripped.data["steps"]} == {"tutorial_v1"}
    material_keys = ("title", "type", "author_or_creator", "content_markdown", "ideas")
    assert ([{k: m.get(k) for k in material_keys} for m in stripped.data["materials"]]
            == [{k: m.get(k) for k in material_keys} for m in expected.data["materials"]])


def test_legacy_outline_is_not_promoted_to_tutorial():
    response = LLMResponse(data=_strip_outline_constants(outline(3)))
    _validate_plan_detail_outline_response(response, minimum_lessons=1, maximum_lessons=20)
    assert response.error is None and "lesson_format" not in response.data


def test_outline_wire_schema_does_not_require_constants():
    schema = PlanTutorialOutlineOutput.model_json_schema()
    assert "lesson_format" not in schema.get("required", [])
    step = schema["$defs"]["PlanTutorialStepOutlineOutput"]
    assert "lesson_format" not in step.get("required", [])


def test_outline_prompt_asks_for_no_constant_fields():
    prompt = (PROMPTS / "plan_item_tutorial_outline.txt").read_text()
    for constant in ('"content_markdown"', '"ideas"', '"canonical_hint"', '"source_strategy"', '"lesson_format"'):
        assert constant not in prompt


def test_week_expansion_does_not_require_cycle_fields():
    week = _plan([1])
    week.roadmap_thesis, week.anti_goals = "", []
    issues = validate_plan_contract(week, duration_weeks=1, hours_per_week=6, require_cycle_fields=False)
    assert not any("roadmap_thesis" in issue or "anti_goals" in issue for issue in issues)
    assert any("roadmap_thesis" in issue for issue in
               validate_plan_contract(week, duration_weeks=1, hours_per_week=6))


def test_backbone_week_does_not_require_friction_fields():
    week = PlanBackboneWeek.model_validate({
        "week_number": 1, "phase": "foundation", "primary_mission": "Build a first proof.",
        "outcome": "A reviewed artifact exists.",
        "tasks": [
            {"title": "Build artifact", "type": "project", "estimated_hours": 3, "success_metric": "Passes rubric."},
            {"title": "Daily drill", "type": "practice", "estimated_hours": 2, "success_metric": "Four drills logged."},
        ],
    })
    assert week.predicted_friction == "" and week.friction_solution == ""


def test_plan_prompts_ask_for_no_unread_or_copied_fields():
    backbone = (PROMPTS / "plan_backbone_generate.txt").read_text()
    week = (PROMPTS / "plan_week_generate.txt").read_text()
    for prompt in (backbone, week):
        assert "predicted_friction" not in prompt and "friction_solution" not in prompt
    assert '"roadmap_thesis"' not in week and '"anti_goals"' not in week
