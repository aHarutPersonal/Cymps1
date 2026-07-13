import copy
import re
from types import SimpleNamespace

import pytest

from app.services.llm.prompt_loader import load_prompt
from app.services.llm.schemas import (
    PlanDetailStepRepairOutput,
    PlanDetailSubstepsRepairOutput,
    PlanItemDetailsOutput,
)
from app.tasks.plans import (
    _merge_plan_detail_repairs,
    _plan_detail_repair_plan,
    _plan_detail_recovery_prompt,
    _plan_detail_step_repair_prompt,
    _plan_detail_substeps_repair_prompt,
    _validate_plan_detail_response,
    _validate_plan_detail_step_response,
)


def _valid_payload() -> dict:
    headings = [
        "## Why This Matters",
        "## Core Framework",
        "## Worked Example",
        "## Failure Modes",
        "## Guided Practice",
        "## Check Your Understanding",
        "## References",
    ]
    heading_text = "\n\n".join(f"{heading}\n" for heading in headings)
    lesson = heading_text + ("deliberate practice evidence mechanism example " * 240)
    substep = (
        "Set a twenty minute timer, apply the supplied framework to one real "
        "artifact, record the output, and verify it against the stated success criterion."
    )
    return {
        "steps": [
            {
                "id": f"step_{index}",
                "title": f"Learn technique {index}",
                "description": "A focused skill-building lesson.",
                "estimate_minutes": 45,
                "reading_minutes": 8,
                "practice_minutes": 37,
                "lesson_content": lesson,
                "resources": ["Resource 1"],
                "substeps": [substep, substep],
            }
            for index in range(1, 4)
        ],
        "materials": [
            {
                "title": f"Resource {index}",
                "type": ("book" if index == 1 else "video" if index == 2 else "course"),
                "author_or_creator": "Known Creator",
                "search_query": f"Resource {index} Known Creator",
                "duration_minutes": 15,
                "reason": "Directly supports the mission.",
                "content_markdown": None,
                "ideas": [],
            }
            for index in range(1, 4)
        ],
        "definition_of_done": "Three lessons and their outputs are complete.",
        "mental_model": "Deliberate practice",
    }


def _lesson_with_word_count(word_count: int) -> str:
    """Build a lesson with every required heading and an exact word count."""
    headings = [
        "## Why This Matters",
        "## Core Framework",
        "## Worked Example",
        "## Failure Modes",
        "## Guided Practice",
        "## Check Your Understanding",
        "## References",
    ]
    scaffold = "\n\n".join(f"{heading}\nsection" for heading in headings)
    scaffold_words = len(scaffold.split())
    assert word_count >= scaffold_words
    return scaffold + "\n\n" + " ".join(["substance"] * (word_count - scaffold_words))


def test_plan_detail_schema_requires_all_three_complete_lessons() -> None:
    payload = _valid_payload()
    payload["steps"][0].pop("lesson_content")
    response = SimpleNamespace(data=payload, error=None)

    _validate_plan_detail_response(response)

    assert response.error is not None
    assert "lesson_content" in response.error


def test_plan_detail_schema_accepts_prompt_contract() -> None:
    result = PlanItemDetailsOutput.model_validate(_valid_payload())

    assert len(result.steps) == 3
    assert len(result.materials) == 3


def test_in_app_lesson_allows_only_a_narrow_word_count_overrun() -> None:
    payload = _valid_payload()
    payload["materials"][2]["type"] = "in_app_lesson"
    payload["materials"][2]["content_markdown"] = "lesson " * 607

    result = PlanItemDetailsOutput.model_validate(payload)

    assert result.materials[2].type == "in_app_lesson"

    payload["materials"][2]["content_markdown"] = "lesson " * 651
    with pytest.raises(ValueError, match="accepted range is 400-650"):
        PlanItemDetailsOutput.model_validate(payload)


def test_plan_detail_schema_rejects_non_material_resource_reference() -> None:
    payload = _valid_payload()
    payload["steps"][0]["resources"] = ["Invented Resource"]
    response = SimpleNamespace(data=payload, error=None)

    _validate_plan_detail_response(response)

    assert "top-level material titles" in (response.error or "")


def test_semantic_validation_failure_gets_quality_specific_retry() -> None:
    retry, stage = _plan_detail_recovery_prompt(
        "original prompt",
        "Plan detail schema validation failed: lesson has 20 words",
    )

    assert stage == "quality_recovery"
    assert "1,200-1,800" in retry
    assert "lesson has 20 words" in retry


def test_json_parse_failure_gets_json_specific_retry() -> None:
    retry, stage = _plan_detail_recovery_prompt(
        "original prompt",
        "Invalid JSON: missing comma",
    )

    assert stage == "json_recovery"
    assert "strictly valid JSON" in retry


def test_plan_detail_schema_reports_every_semantic_defect() -> None:
    payload = _valid_payload()
    headings = "\n".join(
        [
            "## Why This Matters",
            "## Core Framework",
            "## Worked Example",
            "## Failure Modes",
            "## Guided Practice",
            "## Check Your Understanding",
            "## References",
        ]
    )
    payload["steps"][0]["lesson_content"] = headings + (" short" * 100)
    payload["steps"][0]["substeps"][0] = "Too short."
    payload["steps"][1]["lesson_content"] = headings + (" short" * 200)
    response = SimpleNamespace(data=payload, error=None)

    _validate_plan_detail_response(response)

    assert "step_1 lesson_content" in response.error
    assert "step_1 substep 1" in response.error
    assert "step_2 lesson_content" in response.error


def test_repair_plan_preserves_valid_lessons_and_lists_only_invalid_ones() -> None:
    payload = _valid_payload()
    original_step_3 = dict(payload["steps"][2])
    payload["steps"][0]["lesson_content"] = "thin lesson"
    payload["steps"][1]["substeps"][0] = "Too short."

    repair_plan = _plan_detail_repair_plan(payload)

    assert repair_plan is not None
    draft, issues = repair_plan
    assert set(issues) == {"step_1", "step_2"}
    assert draft["steps"][2] == original_step_3


def test_merge_replaces_only_repaired_steps_and_revalidates_everything() -> None:
    payload = _valid_payload()
    original_step_2 = dict(payload["steps"][1])
    repaired_step_1 = dict(payload["steps"][0])
    repaired_step_1["title"] = "Repaired technique"

    merged = _merge_plan_detail_repairs(
        payload,
        {"step_1": repaired_step_1},
    )

    assert merged["steps"][0]["title"] == "Repaired technique"
    assert merged["steps"][1] == original_step_2


def test_targeted_repair_prompt_includes_draft_materials_and_safe_target() -> None:
    payload = _valid_payload()
    prompt = _plan_detail_step_repair_prompt(
        task_title="Build a proof",
        user_goal="Launch a useful product",
        learning_preferences="hands-on",
        idol_name="A documented mentor",
        session_context="The learner needs a narrower experiment.",
        step=payload["steps"][0],
        materials=payload["materials"],
        issues=["step_1 lesson_content has 1145 words"],
    )

    assert "PREVIOUS STEP DRAFT TO IMPROVE" in prompt
    assert "Learn technique 1" in prompt
    assert "Resource 1" in prompt
    assert "1,400-1,600" in prompt
    assert "25-40 words" in prompt


def test_single_step_repair_schema_keeps_the_full_quality_floor() -> None:
    valid_step = _valid_payload()["steps"][0]
    assert PlanDetailStepRepairOutput.model_validate(valid_step).id == "step_1"

    invalid_step = dict(valid_step)
    invalid_step["lesson_content"] = "short"
    with pytest.raises(ValueError, match="required range is 1200-1800"):
        PlanDetailStepRepairOutput.model_validate(invalid_step)


@pytest.mark.parametrize(
    ("word_count", "accepted"),
    [
        (1186, False),
        (1199, False),
        (1200, True),
        (1800, True),
        (1801, False),
    ],
)
def test_single_step_repair_enforces_exact_lesson_boundaries(
    word_count: int,
    accepted: bool,
) -> None:
    step = copy.deepcopy(_valid_payload()["steps"][0])
    step["lesson_content"] = _lesson_with_word_count(word_count)

    if accepted:
        repaired = PlanDetailStepRepairOutput.model_validate(step)
        assert len(repaired.lesson_content.split()) == word_count
    else:
        with pytest.raises(ValueError, match=rf"has {word_count} words"):
            PlanDetailStepRepairOutput.model_validate(step)


def test_near_threshold_repair_preserves_every_valid_shared_component() -> None:
    payload = _valid_payload()
    payload["steps"][0]["lesson_content"] = _lesson_with_word_count(1186)
    original = copy.deepcopy(payload)

    repair_plan = _plan_detail_repair_plan(payload)

    assert repair_plan is not None
    draft, issues_by_step = repair_plan
    assert set(issues_by_step) == {"step_1"}
    assert any("has 1186 words" in issue for issue in issues_by_step["step_1"])

    repaired_step = copy.deepcopy(draft["steps"][0])
    repaired_step["lesson_content"] = _lesson_with_word_count(1400)
    response = SimpleNamespace(data=repaired_step, error=None)
    _validate_plan_detail_step_response(
        response,
        expected_step_id="step_1",
        material_titles={material["title"] for material in draft["materials"]},
    )
    assert response.error is None

    merged = _merge_plan_detail_repairs(draft, {"step_1": response.data})

    assert len(merged["steps"][0]["lesson_content"].split()) == 1400
    assert merged["steps"][1:] == original["steps"][1:]
    # The structural draft normalizes optional material keys to null. The merge
    # must preserve that normalized shared payload byte-for-byte.
    assert merged["materials"] == draft["materials"]
    assert merged["definition_of_done"] == draft["definition_of_done"]
    assert merged["mental_model"] == draft["mental_model"]
    assert len(payload["steps"][0]["lesson_content"].split()) == 1186


def test_failed_near_threshold_repair_feeds_error_into_escalation_prompt() -> None:
    payload = _valid_payload()
    payload["steps"][0]["lesson_content"] = _lesson_with_word_count(1186)
    repair_plan = _plan_detail_repair_plan(payload)
    assert repair_plan is not None
    draft, issues_by_step = repair_plan

    still_short = copy.deepcopy(draft["steps"][0])
    still_short["lesson_content"] = _lesson_with_word_count(1199)
    first_response = SimpleNamespace(data=still_short, error=None)
    _validate_plan_detail_step_response(
        first_response,
        expected_step_id="step_1",
        material_titles={material["title"] for material in draft["materials"]},
    )
    assert "has 1199 words" in first_response.error

    escalation_prompt = _plan_detail_step_repair_prompt(
        task_title="Build a proof",
        user_goal="Launch a useful product",
        learning_preferences="hands-on",
        idol_name="A documented mentor",
        session_context="The learner needs a narrower experiment.",
        step=draft["steps"][0],
        materials=draft["materials"],
        issues=issues_by_step["step_1"],
        prior_error=first_response.error,
    )

    assert "THE PREVIOUS REPAIR ALSO FAILED" in escalation_prompt
    assert "has 1199 words" in escalation_prompt
    assert '"id": "step_1"' in escalation_prompt
    assert "1,400-1,600" in escalation_prompt


def test_substep_only_repair_preserves_the_entire_valid_lesson() -> None:
    payload = _valid_payload()
    payload["steps"][0]["substeps"][0] = "Too short."
    original_lesson = payload["steps"][0]["lesson_content"]
    repair_plan = _plan_detail_repair_plan(payload)
    assert repair_plan is not None
    draft, issues_by_step = repair_plan
    assert set(issues_by_step) == {"step_1"}
    assert all(" substep " in issue for issue in issues_by_step["step_1"])

    repaired_substep = (
        "Set a twenty minute timer, apply the supplied framework to one real "
        "artifact, save the output, and verify it against the stated success "
        "criterion before proceeding."
    )
    candidate = copy.deepcopy(draft["steps"][0])
    candidate["substeps"] = [repaired_substep, repaired_substep]
    response = SimpleNamespace(data=candidate, error=None)
    _validate_plan_detail_step_response(
        response,
        expected_step_id="step_1",
        material_titles={material["title"] for material in draft["materials"]},
    )
    assert response.error is None

    merged = _merge_plan_detail_repairs(draft, {"step_1": response.data})
    assert merged["steps"][0]["lesson_content"] == original_lesson
    assert merged["steps"][0]["title"] == payload["steps"][0]["title"]
    assert merged["steps"][0]["resources"] == payload["steps"][0]["resources"]


def test_targeted_repair_declines_unsafe_shared_or_structural_drafts() -> None:
    duplicate_ids = _valid_payload()
    duplicate_ids["steps"][1]["id"] = "step_1"
    assert _plan_detail_repair_plan(duplicate_ids) is None

    invalid_materials = _valid_payload()
    invalid_materials["materials"][0]["type"] = "course"
    invalid_materials["steps"][0]["lesson_content"] = "thin"
    assert _plan_detail_repair_plan(invalid_materials) is None

    structurally_incomplete = _valid_payload()
    structurally_incomplete["steps"][0].pop("lesson_content")
    assert _plan_detail_repair_plan(structurally_incomplete) is None


def test_targeted_step_validator_rejects_identity_and_resource_drift() -> None:
    payload = _valid_payload()
    material_titles = {material["title"] for material in payload["materials"]}

    wrong_id = copy.deepcopy(payload["steps"][1])
    response = SimpleNamespace(data=wrong_id, error=None)
    _validate_plan_detail_step_response(
        response,
        expected_step_id="step_1",
        material_titles=material_titles,
    )
    assert "expected step_1" in response.error

    invented_resource = copy.deepcopy(payload["steps"][0])
    invented_resource["resources"] = ["Invented Resource"]
    response = SimpleNamespace(data=invented_resource, error=None)
    _validate_plan_detail_step_response(
        response,
        expected_step_id="step_1",
        material_titles=material_titles,
    )
    assert "top-level material titles" in response.error


def test_substep_only_repair_contract_is_small_and_actionable() -> None:
    step = _valid_payload()["steps"][0]
    prompt = _plan_detail_substeps_repair_prompt(
        task_title="Build a proof",
        step=step,
        issues=["step_1 substep 1 has 10 words"],
    )
    assert "do not return the lesson" in prompt
    assert "25-40 words" in prompt

    valid_substep = (
        "Set a twenty minute timer, apply the framework to one real artifact, "
        "save the output, and verify it against every stated success criterion."
    )
    result = PlanDetailSubstepsRepairOutput.model_validate(
        {"substeps": [valid_substep, valid_substep]}
    )
    assert len(result.substeps) == 2

    with pytest.raises(ValueError, match="required range is 20-50"):
        PlanDetailSubstepsRepairOutput.model_validate(
            {"substeps": ["Too short.", valid_substep]}
        )


def test_plan_detail_prompt_examples_obey_their_own_constraints() -> None:
    prompt = load_prompt("plan_item_details")
    assert "(60-90 min)" not in prompt
    assert "TARGET 1,400-1,600" in prompt

    example = prompt.split('"substeps": [', 1)[1].split("]", 1)[0]
    substeps = re.findall(r'^\s*"([^"]+)"', example, flags=re.MULTILINE)
    assert len(substeps) == 3
    assert all(20 <= len(substep.split()) <= 50 for substep in substeps)
