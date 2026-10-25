from tests.section_client_fixture import section_client
import asyncio
import copy
import json
import re
from types import SimpleNamespace
from app.services.planning.lesson_package import LessonPackage
from tests.lesson_package_fixtures import package_payload

import pytest

from app.services.llm.prompt_loader import load_prompt
from app.services.llm.schemas import (
    PlanDetailLessonSectionsOutput,
    PlanDetailSectionsRepairOutput,
    PlanDetailStepRepairOutput,
    PlanDetailSubstepsRepairOutput,
    PlanItemDetailsOutlineOutput,
    PlanItemDetailsOutput,
    plan_detail_lesson_section_quality_issues,
)
from app.tasks.plans import (
    _assemble_parallel_lesson_response,
    _generate_plan_item_details_parallel,
    _merge_plan_detail_repairs,
    _plan_detail_lesson_count_bounds,
    _plan_detail_repair_plan,
    _plan_detail_recovery_prompt,
    _plan_detail_step_repair_prompt,
    _plan_detail_substeps_repair_prompt,
    _validate_plan_detail_response,
    _validate_plan_detail_outline_response,
    _validate_plan_detail_step_response,
    _writing_thinking_level,
)


def _valid_payload(
    *,
    lesson_count: int = 3,
    material_count: int = 3,
) -> dict:
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
    lesson = heading_text + ("deliberate practice evidence mechanism example " * 520)
    substep = (
        "Budget about twenty minutes and apply the supplied framework to one real "
        "artifact, record the output, and verify it against the stated success criterion."
    )
    return {
        "steps": [
            {
                "id": f"step_{index}",
                "title": "Learn the technique",
                "description": "A focused skill-building lesson.",
                "estimate_minutes": 80,
                "reading_minutes": 13,
                "practice_minutes": 67,
                "lesson_content": lesson,
                "resources": [f"Resource {(index - 1) % material_count + 1}"],
                "substeps": [substep, substep],
            }
            for index in range(1, lesson_count + 1)
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
            for index in range(1, material_count + 1)
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


def test_plan_detail_schema_requires_every_complete_lesson() -> None:
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


@pytest.mark.parametrize("count", [1, 3, 5])
def test_plan_detail_schema_accepts_model_selected_counts(count: int) -> None:
    result = PlanItemDetailsOutput.model_validate(
        _valid_payload(lesson_count=count, material_count=count)
    )

    assert len(result.steps) == count
    assert len(result.materials) == count
    assert [step.id for step in result.steps] == [
        f"step_{index}" for index in range(1, count + 1)
    ]


def test_plan_detail_schema_rejects_non_contiguous_ids() -> None:
    payload = _valid_payload()
    payload["steps"][1]["id"] = "step_3"

    with pytest.raises(ValueError, match="contiguous and ordered"):
        PlanItemDetailsOutput.model_validate(payload)


def test_mission_workload_bounds_leave_exact_count_to_the_model() -> None:
    assert _plan_detail_lesson_count_bounds(2) == (1, 3)
    assert _plan_detail_lesson_count_bounds(4) == (2, 5)
    assert _plan_detail_lesson_count_bounds(8) == (3, 5)


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
    assert "1,900-4,200" in retry
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
    assert "Learn the technique" in prompt
    assert "Resource 1" in prompt
    assert "2,400-2,800" in prompt
    assert "targeting 20-60 words" in prompt


def test_single_step_repair_schema_keeps_the_full_quality_floor() -> None:
    valid_step = _valid_payload()["steps"][0]
    assert PlanDetailStepRepairOutput.model_validate(valid_step).id == "step_1"

    invalid_step = dict(valid_step)
    invalid_step["lesson_content"] = "short"
    with pytest.raises(ValueError, match="accepted range is 1900-4200"):
        PlanDetailStepRepairOutput.model_validate(invalid_step)


@pytest.mark.parametrize(
    ("word_count", "accepted"),
    [
        (1899, False),
        (1900, True),
        (1977, True),
        (2176, True),
        (3400, True),
        (3727, True),
        (4200, True),
        (4201, False),
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
    payload["steps"][0]["lesson_content"] = _lesson_with_word_count(1886)
    original = copy.deepcopy(payload)

    repair_plan = _plan_detail_repair_plan(payload)

    assert repair_plan is not None
    draft, issues_by_step = repair_plan
    assert set(issues_by_step) == {"step_1"}
    assert any("has 1886 words" in issue for issue in issues_by_step["step_1"])

    repaired_step = copy.deepcopy(draft["steps"][0])
    repaired_step["lesson_content"] = _lesson_with_word_count(2700)
    response = SimpleNamespace(data=repaired_step, error=None)
    _validate_plan_detail_step_response(
        response,
        expected_step_id="step_1",
        material_titles={material["title"] for material in draft["materials"]},
    )
    assert response.error is None

    merged = _merge_plan_detail_repairs(draft, {"step_1": response.data})

    assert len(merged["steps"][0]["lesson_content"].split()) == 2700
    assert merged["steps"][1:] == original["steps"][1:]
    # The structural draft normalizes optional material keys to null. The merge
    # must preserve that normalized shared payload byte-for-byte.
    assert merged["materials"] == draft["materials"]
    assert merged["definition_of_done"] == draft["definition_of_done"]
    assert merged["mental_model"] == draft["mental_model"]
    assert len(payload["steps"][0]["lesson_content"].split()) == 1886


def test_failed_near_threshold_repair_feeds_error_into_escalation_prompt() -> None:
    payload = _valid_payload()
    payload["steps"][0]["lesson_content"] = _lesson_with_word_count(1886)
    repair_plan = _plan_detail_repair_plan(payload)
    assert repair_plan is not None
    draft, issues_by_step = repair_plan

    still_short = copy.deepcopy(draft["steps"][0])
    still_short["lesson_content"] = _lesson_with_word_count(1899)
    first_response = SimpleNamespace(data=still_short, error=None)
    _validate_plan_detail_step_response(
        first_response,
        expected_step_id="step_1",
        material_titles={material["title"] for material in draft["materials"]},
    )
    assert "has 1899 words" in first_response.error

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
    assert "has 1899 words" in escalation_prompt
    assert '"id": "step_1"' in escalation_prompt
    assert "2,400-2,800" in escalation_prompt


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
        "Budget about twenty minutes and apply the supplied framework to one real "
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
    invalid_materials["materials"][0]["title"] = "Resource 2"
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
    assert "targeting 20-60 words" in prompt
    assert "no fixed item count" in " ".join(prompt.split())

    valid_substep = (
        "Budget about twenty minutes and apply the framework to one real artifact, "
        "save the output, and verify it against every stated success criterion."
    )
    result = PlanDetailSubstepsRepairOutput.model_validate(
        {"substeps": [valid_substep, valid_substep]}
    )
    assert len(result.substeps) == 2

    expanded = PlanDetailSubstepsRepairOutput.model_validate(
        {"substeps": [valid_substep] * 6}
    )
    assert len(expanded.substeps) == 6

    with pytest.raises(ValueError, match="minimum is 12"):
        PlanDetailSubstepsRepairOutput.model_validate(
            {"substeps": ["Too short.", valid_substep]}
        )


def test_plan_detail_prompt_examples_obey_their_own_constraints() -> None:
    prompt = load_prompt("plan_item_details")
    assert "(60-90 min)" not in prompt
    assert "TARGET 2,400-2,800" in prompt

    example = prompt.split('"substeps": [', 1)[1].split("]", 1)[0]
    substeps = re.findall(r'^\s*"([^"]+)"', example, flags=re.MULTILINE)
    assert len(substeps) == 3
    assert all(12 <= len(substep.split()) <= 60 for substep in substeps)


def _outline_payload(
    *,
    lesson_count: int = 3,
    material_count: int = 3,
) -> dict:
    payload = _valid_payload(
        lesson_count=lesson_count,
        material_count=material_count,
    )
    return {
        **payload,
        "steps": [
            {
                "id": step["id"],
                "title": step["title"],
                "description": step["description"],
                "resources": step["resources"],
            }
            for step in payload["steps"]
        ],
    }


def _lesson_sections_payload() -> dict:
    return {
        "why_this_matters": "substance " * 240,
        "core_framework": "substance " * 700,
        "worked_example": "substance " * 460,
        "failure_modes": "substance " * 330,
        "guided_practice": "[[practice:guided.argument]] [[practice:transfer.argument]] " + "substance " * 500,
        "check_your_understanding": "substance " * 250,
        "references": "substance " * 100,
        "substeps": _valid_payload()["steps"][0]["substeps"],
    }


def test_parallel_outline_is_small_and_resource_consistent() -> None:
    outline = PlanItemDetailsOutlineOutput.model_validate(_outline_payload())

    assert [step.id for step in outline.steps] == [
        "step_1",
        "step_2",
        "step_3",
    ]
    assert len(outline.materials) == 3


def test_parallel_outline_rejects_unapproved_resource_names() -> None:
    payload = _outline_payload()
    payload["materials"][0]["title"] = "The Lean Startup"
    payload["materials"][0]["reason"] = "Lean product experimentation."
    payload["steps"][1]["resources"] = [
        "Running Lean",
        "Scientific experimentation guide",
    ]
    response = SimpleNamespace(data=payload, error=None)

    _validate_plan_detail_outline_response(response)

    assert response.error is not None
    assert "resources" in response.error


def test_writing_uses_tiered_modern_thinking_levels(monkeypatch) -> None:
    monkeypatch.setattr("app.tasks.plans.settings.llm_provider", "dummy")
    assert _writing_thinking_level("fast") == "minimal"
    assert _writing_thinking_level("balanced") == "minimal"
    assert _writing_thinking_level("quality") == "high"


@pytest.mark.parametrize("tier", ["fast", "balanced", "quality"])
def test_zai_writing_keeps_corrections_within_the_generation_budget(monkeypatch, tier):
    monkeypatch.setattr("app.tasks.plans.settings.llm_provider", "zai")
    assert _writing_thinking_level(tier) == "low"


@pytest.mark.asyncio
async def test_parallel_generation_uses_a_model_selected_five_lesson_outline() -> None:
    payload = _valid_payload(lesson_count=5, material_count=5)
    outline = _outline_payload(lesson_count=5, material_count=5)

    class FakeClient:
        model = "fake-model"

        @section_client
        async def generate_json(self, *, user_prompt, output_model, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            from app.services.planning.lesson_review import LessonReview
            if issubclass(output_model, LessonReview):
                return SimpleNamespace(data={"acceptable": True, "issues": [], "practice_minutes": 60, "contains_calculations": False, "calculations": [], "literal_fact_ids": list(json.loads(user_prompt).get("numeric_spans", {}))}, error=None)
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=copy.deepcopy(outline), error=None)
            assert any(
                f'"id":"{step["id"]}"' in user_prompt for step in payload["steps"]
            )
            return SimpleNamespace(
                data=copy.deepcopy(_lesson_sections_payload()),
                error=None,
            )

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner",
        task_title="Build a complete system",
        mission_hours=5,
        user_goal="master the workflow",
        learning_preferences="reading and practice",
        idol_name="Mentor",
        idol_domain="technology",
        idol_evidence={},
        session_context="",
        active_tier="balanced",
        routing_reason="test",
        client_factory=lambda **kwargs: FakeClient(),
    )

    assert error is None
    assert result is not None
    assert len(result["steps"]) == 5
    assert len([stage for stage, *_ in calls if "_draft_" in stage]) == 20


@pytest.mark.asyncio
async def test_missing_lessons_overlap_within_capacity_and_checkpoint_independently(
    monkeypatch,
) -> None:
    payload = _valid_payload()
    outline = _outline_payload()
    started: set[str] = set()
    all_started = asyncio.Event()
    client_options: list[dict] = []
    writing_options: list[dict] = []
    checkpoints: list[tuple[str, list[str]]] = []

    class FakeClient:
        model = "fake-model"

        def __init__(self, options):
            self.options = options

        @section_client
        async def generate_json(self, *, user_prompt, output_model, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            from app.services.planning.lesson_review import LessonReview
            if issubclass(output_model, LessonReview):
                return SimpleNamespace(data={"acceptable": True, "issues": [], "practice_minutes": 60, "contains_calculations": False, "calculations": [], "literal_fact_ids": list(json.loads(user_prompt).get("numeric_spans", {}))}, error=None)
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=copy.deepcopy(outline), error=None)

            writing_options.append(self.options)
            step = next(
                candidate
                for candidate in payload["steps"]
                if f'"id":"{candidate["id"]}"' in user_prompt
            )
            started.add(step["id"])
            if len(started) >= 2:
                all_started.set()
            await asyncio.wait_for(all_started.wait(), timeout=1)
            return SimpleNamespace(
                data=copy.deepcopy(_lesson_sections_payload()),
                error=None,
            )

    def client_factory(**kwargs):
        client_options.append(kwargs)
        return FakeClient(kwargs)

    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client",
        client_factory,
    )

    async def checkpoint(payload, stage):
        if stage == "outline_ready":
            # Reference lookup must overlap writing, not postpone it.
            await asyncio.wait_for(all_started.wait(), timeout=1)
        checkpoints.append(
            (
                stage,
                [step["id"] for step in payload["steps"] if step.get("lesson_content")],
            )
        )

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner",
        task_title="Build a validated experiment",
        mission_hours=5,
        user_goal="learn product experimentation",
        learning_preferences="reading and practice",
        idol_name="Mentor",
        idol_domain="technology",
        idol_evidence={},
        session_context="",
        active_tier="balanced",
        routing_reason="test",
        on_checkpoint=checkpoint,
    )

    assert error is None
    assert result is not None
    assert started == {"step_1", "step_2", "step_3"}
    assert all(
        1900 <= len(step["lesson_content"].split()) <= 4200 for step in result["steps"]
    )
    assert all("## References" in step["lesson_content"] for step in result["steps"])
    assert calls[0][0] == "parallel_outline_attempt_1"
    assert {stage for stage, *_ in calls if "_draft_" in stage} == {
        f"parallel_lesson_step_{step}_draft_1_{group}_1"
        for step in range(1, 4) for group in ("framing", "mechanism", "worked", "practice")
    }
    assert checkpoints[0] == ("outline_ready", [])
    assert set(checkpoints[-1][1]) == {"step_1", "step_2", "step_3"}
    assert client_options[0]["tier"] == "balanced"
    assert client_options[0]["thinking_level"] == "medium"
    assert all(options["tier"] == "balanced" for options in client_options[1:])
    assert writing_options
    assert all(options["thinking_level"] == "low" for options in writing_options)
    assert all(options["max_tokens"] == 6500 for options in writing_options)
    assert all(0 < options["timeout"] <= 90 for options in writing_options)
    assert all(options["allow_fallback"] is False for options in client_options[1:])


def test_parallel_lesson_rejects_prompt_example_placeholders() -> None:
    placeholder = "220-280 words without the heading"
    sections = {
        field_name: placeholder
        for field_name in (
            "why_this_matters",
            "core_framework",
            "worked_example",
            "failure_modes",
            "guided_practice",
            "check_your_understanding",
            "references",
        )
    }
    sections["substeps"] = _valid_payload()["steps"][0]["substeps"]
    response = SimpleNamespace(data=sections, error=None)

    _assemble_parallel_lesson_response(
        response,
        step=_outline_payload()["steps"][0],
        material_titles={"Resource 1", "Resource 2", "Resource 3"},
        target_minutes=80,
    )

    assert "sections quality failed" in (response.error or "")
    assert "why_this_matters has" in (response.error or "")


def test_parallel_lesson_compacts_overlong_sections_without_a_model_retry() -> None:
    payload = _lesson_sections_payload()
    # Reproduce the production failure mode: every section is complete, but
    # one verbose section pushes the assembled lesson slightly past 4,200.
    payload["core_framework"] += "additional evidence and application detail. " * 356
    response = SimpleNamespace(data=payload, error=None)

    _assemble_parallel_lesson_response(
        response,
        step=_outline_payload()["steps"][0],
        material_titles={"Resource 1", "Resource 2", "Resource 3"},
        target_minutes=80,
    )

    assert response.error is None
    lesson = response.data["lesson_content"]
    assert 1900 <= len(lesson.split()) <= 4200
    assert all(
        heading in lesson
        for heading in (
            "## Why This Matters",
            "## Core Framework",
            "## Worked Example",
            "## Failure Modes",
            "## Guided Practice",
            "## Check Your Understanding",
            "## References",
        )
    )
    assert (
        len(
            lesson.split("## Core Framework", 1)[1]
            .split("## Worked Example", 1)[0]
            .split()
        )
        >= 400
    )


def test_section_quality_uses_words_instead_of_brittle_character_counts() -> None:
    sections = PlanDetailLessonSectionsOutput.model_validate(_lesson_sections_payload())

    assert plan_detail_lesson_section_quality_issues(sections) == []


def test_parallel_lesson_preserves_all_object_phases_as_substeps() -> None:
    payload = _lesson_sections_payload()
    payload["substeps"] = [
        {
            "instruction": (
                f"Apply phase {index} to one real artifact and record the key "
                "decision before proceeding to the next phase."
            ),
            "time_minutes": 10 + index,
            "expected_output": f"an annotated phase {index} decision",
            "success_criterion": "the decision is specific and evidence-backed",
        }
        for index in range(1, 7)
    ]
    response = SimpleNamespace(data=payload, error=None)

    _assemble_parallel_lesson_response(
        response,
        step=_outline_payload()["steps"][0],
        material_titles={"Resource 1", "Resource 2", "Resource 3"},
        target_minutes=80,
    )

    assert response.error is None
    assert len(response.data["substeps"]) == 6
    assert all(isinstance(substep, str) for substep in response.data["substeps"])
    assert all(len(substep.split()) >= 12 for substep in response.data["substeps"])
    assert "phase 1" in response.data["substeps"][0]
    assert "phase 6" in response.data["substeps"][5]


def test_parallel_lesson_preserves_verbose_substep_objects_without_retry() -> None:
    payload = _lesson_sections_payload()
    payload["substeps"] = [
        {
            "action": " ".join([f"action{index}"] * 45),
            "duration_minutes": 12,
            "tool": "structured evidence review worksheet with decision notes",
            "output": "one annotated decision artifact ready for peer review",
            "success_criterion": "every conclusion cites concrete evidence and a next action",
        }
        for index in range(1, 4)
    ]
    response = SimpleNamespace(data=payload, error=None)

    _assemble_parallel_lesson_response(
        response,
        step=_outline_payload()["steps"][0],
        material_titles={"Resource 1", "Resource 2", "Resource 3"},
        target_minutes=80,
    )

    assert response.error is None
    assert all(len(substep.split()) > 50 for substep in response.data["substeps"])
    assert all("Success means" in substep for substep in response.data["substeps"])


def test_parallel_lesson_accepts_long_plain_string_substeps() -> None:
    payload = _lesson_sections_payload()
    payload["substeps"] = [
        " ".join([f"action{index}"] * word_count)
        for index, word_count in enumerate(range(51, 67), start=1)
    ]
    response = SimpleNamespace(data=payload, error=None)

    _assemble_parallel_lesson_response(
        response,
        step=_outline_payload()["steps"][0],
        material_titles={"Resource 1", "Resource 2", "Resource 3"},
        target_minutes=80,
    )

    assert response.error is None
    assert [len(value.split()) for value in response.data["substeps"]] == list(
        range(51, 67)
    )


def test_targeted_lesson_validation_canonicalizes_model_authored_timing() -> None:
    step = copy.deepcopy(_valid_payload()["steps"][1])
    step["lesson_content"] = _lesson_with_word_count(2176)
    step["estimate_minutes"] = 180
    step["reading_minutes"] = 40
    step["practice_minutes"] = 140
    response = SimpleNamespace(data=step, error=None)

    _validate_plan_detail_step_response(
        response,
        expected_step_id="step_2",
        material_titles={"Resource 1", "Resource 2", "Resource 3"},
    )

    assert response.error is None
    assert response.data["reading_minutes"] == 11
    assert response.data["practice_minutes"] == 169
    assert response.data["estimate_minutes"] == 180


@pytest.mark.asyncio
async def test_parallel_generation_retries_only_the_failed_lesson() -> None:
    outline = _outline_payload()
    attempts_by_step: dict[str, int] = {}
    prompts_by_step: dict[str, list[str]] = {}

    class FakeClient:
        model = "fake-model"

        @section_client
        async def generate_json(self, *, user_prompt, output_model, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            from app.services.planning.lesson_review import LessonReview
            if issubclass(output_model, LessonReview):
                return SimpleNamespace(data={"acceptable": True, "issues": [], "practice_minutes": 60, "contains_calculations": False, "calculations": [], "literal_fact_ids": list(json.loads(user_prompt).get("numeric_spans", {}))}, error=None)
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=copy.deepcopy(outline), error=None)

            step_id = next(
                candidate["id"]
                for candidate in outline["steps"]
                if f'"id":"{candidate["id"]}"' in user_prompt
            )
            attempts_by_step[step_id] = attempts_by_step.get(step_id, 0) + 1
            prompts_by_step.setdefault(step_id, []).append(user_prompt)
            if step_id == "step_1" and attempts_by_step[step_id] == 1:
                invalid = _lesson_sections_payload()
                invalid.pop("references")
                return SimpleNamespace(data=invalid, error=None)
            return SimpleNamespace(
                data=copy.deepcopy(_lesson_sections_payload()),
                error=None,
            )

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner",
        task_title="Build a validated experiment",
        mission_hours=5,
        user_goal="learn product experimentation",
        learning_preferences="reading and practice",
        idol_name="Mentor",
        idol_domain="technology",
        idol_evidence={},
        session_context="",
        active_tier="balanced",
        routing_reason="test",
        client_factory=lambda **kwargs: FakeClient(),
    )

    assert error is None
    assert result is not None
    assert attempts_by_step == {"step_1": 5, "step_2": 4, "step_3": 4}
    repair_prompt = next(p for p in prompts_by_step["step_1"] if "CORRECT THIS GROUP" in p)
    assert "references" in repair_prompt
    stages = [stage for stage, *_ in calls]
    assert stages.count("parallel_outline_attempt_1") == 1
    assert stages.count("parallel_lesson_step_1_draft_1_framing_1") == 1
    assert stages.count("parallel_lesson_step_1_draft_1_framing_2") == 1
    assert not any("_draft_2_" in stage for stage in stages)



@pytest.mark.asyncio
@pytest.mark.parametrize("provider_error,recovers", [
    ("zai request failed (TimeoutError; finish=missing)", True),
    ("zai request failed (JSONDecodeError; finish=stop)", False),
])
async def test_group_retry_does_not_change_provider_or_repeat_other_groups(monkeypatch, provider_error, recovers):
    from app.services.llm import recovery
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_review import LessonReview

    monkeypatch.setattr(recovery.settings, "gemini_api_key", "test-only")
    attempts = {}
    recovered = []

    class RecoveryClient:
        model = "recovery-test"
        def __init__(self, **kwargs):
            assert kwargs["thinking_level"] == "low"
        @section_client
        async def generate_json(self, **kwargs):
            recovered.append(kwargs)
            return LLMResponse(data=_lesson_sections_payload(), provider="gemini")

    monkeypatch.setattr(recovery, "CompleteRecoveryClient", RecoveryClient)

    class Client:
        model = "zai-test"
        @section_client
        async def generate_json(self, *, output_model, user_prompt, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            if output_model is PlanItemDetailsOutlineOutput:
                return LLMResponse(data=_outline_payload())
            if issubclass(output_model, LessonReview):
                return LLMResponse(data={"acceptable": True, "issues": [], "practice_minutes": 60,
                                         "contains_calculations": False, "calculations": [], "literal_fact_ids": list(json.loads(user_prompt).get("numeric_spans", {}))})
            step = next(s["id"] for s in _outline_payload()["steps"] if f'"id":"{s["id"]}"' in user_prompt)
            attempts[step] = attempts.get(step, 0) + 1
            if step == "step_1" and attempts[step] == 1:
                return LLMResponse(data={}, error=provider_error, provider="zai")
            return LLMResponse(data=_lesson_sections_payload(), provider="zai")

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner", task_title="Build a validated experiment",
        mission_hours=5, user_goal="learn product experimentation",
        learning_preferences="reading and practice", idol_name="Mentor",
        idol_domain="technology", idol_evidence={}, session_context="",
        active_tier="balanced", routing_reason="test", client_factory=lambda **kwargs: Client(),
    )
    assert error is None and result
    assert not recovered  # No implicit provider switch for a section retry.
    assert attempts == {"step_1": 5, "step_2": 4, "step_3": 4}
    assert not any(reason == "parallel_lesson_provider_recovery" for _, _, _, reason, _ in calls)


@pytest.mark.asyncio
async def test_outline_publication_failure_cancels_every_started_writer():
    started = 0
    cancelled = 0
    all_started = asyncio.Event()

    class FakeClient:
        model = "fake-model"

        @section_client
        async def generate_json(self, *, output_model, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            nonlocal started, cancelled
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=_outline_payload(), error=None)
            started += 1
            if started == 4:
                all_started.set()
            try:
                await asyncio.Event().wait()
            finally:
                cancelled += 1

    async def checkpoint(payload, stage):
        assert stage == "outline_ready"
        await asyncio.wait_for(all_started.wait(), timeout=1)
        raise RuntimeError("publication failed")

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner", task_title="Build a validated experiment",
        mission_hours=5, user_goal="learn product experimentation",
        learning_preferences="reading and practice", idol_name="Mentor",
        idol_domain="technology", idol_evidence={}, session_context="",
        active_tier="balanced", routing_reason="test",
        client_factory=lambda **kwargs: FakeClient(), on_checkpoint=checkpoint,
    )
    assert error == "Outline checkpoint failed: RuntimeError"
    assert started == cancelled == 4  # Every active call under the shared cap is cancelled.
    assert not any(s.get("lesson_content") for s in result["steps"])


@pytest.mark.asyncio
@pytest.mark.parametrize("repaired_minutes", [45, 20])
async def test_workload_mismatch_cannot_be_hidden_by_prose_only_expansion(repaired_minutes):
    from app.services.planning.lesson_review import LessonReview, ReviewEvidencePatch

    outline = _outline_payload()
    drafts = []
    reviews = []
    repairs = []

    class FakeClient:
        model = "fake-model"

        @section_client
        async def generate_json(self, *, user_prompt, output_model, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=copy.deepcopy(outline), error=None)
            if issubclass(output_model, ReviewEvidencePatch):
                lesson = json.loads(user_prompt)["lesson_for_workload_audit"]
                reviews.append(copy.deepcopy(lesson))
                return SimpleNamespace(data={"practice_minutes": 20}, error=None)
            if issubclass(output_model, LessonReview):
                lesson = json.loads(user_prompt)["lesson"]
                reviews.append(copy.deepcopy(lesson))
                minutes = 60
                if lesson["id"] == "step_1":
                    minutes = repaired_minutes if "transfer case" in lesson["lesson_content"] else 20
                return SimpleNamespace(data={
                    "acceptable": True, "issues": [], "practice_minutes": minutes,
                    "contains_calculations": False, "calculations": [], "literal_fact_ids": list(json.loads(user_prompt).get("numeric_spans", {})),
                }, error=None)
            if output_model is PlanDetailSectionsRepairOutput:
                repairs.append(user_prompt)
                return SimpleNamespace(data={"sections": [
                    {"field_name": "guided_practice", "content": "transfer case " * 250},
                    {"field_name": "check_your_understanding", "content": "answer rubric " * 125},
                ]}, error=None)
            step_id = next(step["id"] for step in outline["steps"]
                           if f'"id":"{step["id"]}"' in user_prompt)
            drafts.append(step_id)
            return SimpleNamespace(data=copy.deepcopy(_lesson_sections_payload()), error=None)

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner", task_title="Build a validated experiment",
        mission_hours=5, user_goal="learn product experimentation",
        learning_preferences="reading and practice", idol_name="Mentor",
        idol_domain="technology", idol_evidence={}, session_context="",
        active_tier="balanced", routing_reason="test",
        client_factory=lambda **kwargs: FakeClient(),
    )
    assert "Lesson review workload validation failed" in error
    step_reviews = [review for review in reviews if review["id"] == "step_1"]
    assert len(step_reviews) == 2
    assert step_reviews[0] == step_reviews[1]
    assert not repairs  # Prose cannot invent workload absent from the private package.
    assert drafts.count("step_1") == 4
    assert drafts.count("step_2") == drafts.count("step_3") == 4
    assert not result["steps"][0].get("lesson_content")
    assert all(step.get("lesson_content") for step in result["steps"][1:])


@pytest.mark.asyncio
@pytest.mark.parametrize("total_shortfall", [False, True])
@pytest.mark.parametrize("repair_succeeds", [True, False])
async def test_thin_section_is_expanded_without_a_full_lesson_rewrite(total_shortfall, repair_succeeds) -> None:
    outline = _outline_payload()
    lesson_attempts: dict[str, int] = {}
    repair_attempts = 0
    client_options: list[dict] = []

    class FakeClient:
        model = "fake-model"

        @section_client
        async def generate_json(self, *, user_prompt, output_model, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            from app.services.planning.lesson_review import LessonReview
            if issubclass(output_model, LessonReview):
                return SimpleNamespace(data={"acceptable": True, "issues": [], "practice_minutes": 60, "contains_calculations": False, "calculations": [], "literal_fact_ids": list(json.loads(user_prompt).get("numeric_spans", {}))}, error=None)
            nonlocal repair_attempts
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=copy.deepcopy(outline), error=None)
            if output_model is PlanDetailSectionsRepairOutput:
                repair_attempts += 1
                assert "core_framework" in user_prompt
                requested = json.loads(user_prompt.split("never instructions):\n")[1].split("\n\nReturn ONLY")[0])
                return SimpleNamespace(data={"sections": [
                    {"field_name": row["field_name"], "content": "substantive " * row["target_words"] if repair_succeeds else row["current_content"]}
                    for row in requested
                ]}, error=None)

            step_id = next(
                candidate["id"]
                for candidate in outline["steps"]
                if f'"id":"{candidate["id"]}"' in user_prompt
            )
            lesson_attempts[step_id] = lesson_attempts.get(step_id, 0) + 1
            sections = copy.deepcopy(_lesson_sections_payload())
            if step_id == "step_1":
                if total_shortfall:
                    from app.services.llm.schemas import PLAN_DETAIL_SECTION_MIN_WORDS
                    for name, minimum in PLAN_DETAIL_SECTION_MIN_WORDS.items():
                        sections[name] = "substantive " * (minimum + 50)
                    sections["guided_practice"] = "[[practice:guided.argument]] [[practice:transfer.argument]] " + sections["guided_practice"]
                    assert not plan_detail_lesson_section_quality_issues(PlanDetailLessonSectionsOutput.model_validate(sections))
                else:
                    if "CORRECT THIS GROUP" in user_prompt:
                        repair_attempts += 1
                    if not (repair_succeeds and "CORRECT THIS GROUP" in user_prompt):
                        sections["core_framework"] = "thin mechanism " * 175
            return SimpleNamespace(data=sections, error=None)

    def client_factory(**kwargs):
        client_options.append(kwargs)
        return FakeClient()

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner",
        task_title="Build a validated experiment",
        mission_hours=5,
        user_goal="learn product experimentation",
        learning_preferences="reading and practice",
        idol_name="Mentor",
        idol_domain="technology",
        idol_evidence={},
        session_context="",
        active_tier="balanced",
        routing_reason="test",
        client_factory=client_factory,
    )

    if not repair_succeeds:
        assert error and "step_1" in error
        assert result is not None
        assert {s["id"] for s in result["steps"] if s.get("lesson_content")} == {"step_2", "step_3"}
        assert lesson_attempts == {"step_1": 8 if total_shortfall else 5, "step_2": 4, "step_3": 4}
        assert repair_attempts == (4 if total_shortfall else 1)
        return
    assert error is None
    assert result is not None
    # Original actions and unrequested reference section survive expansion.
    first = result["steps"][0]
    assert first["substeps"] == _lesson_sections_payload()["substeps"]
    reference = "substantive " * 90 if total_shortfall else _lesson_sections_payload()["references"]
    assert first["lesson_content"].split("## References\n")[1] == reference.strip()
    assert lesson_attempts == {"step_1": 4 if total_shortfall else 5, "step_2": 4, "step_3": 4}
    assert repair_attempts == 1
    repair_calls = [stage for stage, *_ in calls if "sections_repair" in stage]
    assert repair_calls == (["parallel_lesson_step_1_sections_repair_1"] if total_shortfall else [])
    repair_options = [
        options for options in client_options if options.get("max_tokens") == 6000
    ]
    assert repair_options == ([
        {
            "timeout": 60,
            "max_tokens": 6000,
            "tier": "balanced",
            "thinking_level": "minimal",
            "allow_fallback": False,
        }
    ] if total_shortfall else [])


@pytest.mark.asyncio
async def test_substep_only_failure_preserves_long_lesson_and_repairs_small_field() -> (
    None
):
    outline = _outline_payload()
    lesson_attempts: dict[str, int] = {}
    repair_attempts = 0

    class FakeClient:
        model = "fake-model"

        @section_client
        async def generate_json(self, *, user_prompt, output_model, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            from app.services.planning.lesson_review import LessonReview
            if issubclass(output_model, LessonReview):
                return SimpleNamespace(data={"acceptable": True, "issues": [], "practice_minutes": 60, "contains_calculations": False, "calculations": [], "literal_fact_ids": list(json.loads(user_prompt).get("numeric_spans", {}))}, error=None)
            nonlocal repair_attempts
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=copy.deepcopy(outline), error=None)
            if output_model is PlanDetailSubstepsRepairOutput:
                repair_attempts += 1
                return SimpleNamespace(
                    data={"substeps": _valid_payload()["steps"][0]["substeps"]},
                    error=None,
                )

            step_id = next(
                candidate["id"]
                for candidate in outline["steps"]
                if f'"id":"{candidate["id"]}"' in user_prompt
            )
            lesson_attempts[step_id] = lesson_attempts.get(step_id, 0) + 1
            sections = copy.deepcopy(_lesson_sections_payload())
            if step_id == "step_1":
                if "CORRECT THIS GROUP" in user_prompt:
                    repair_attempts += 1
                else:
                    sections["substeps"] = ["Too short."]
            return SimpleNamespace(data=sections, error=None)

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner",
        task_title="Build a validated experiment",
        mission_hours=5,
        user_goal="learn product experimentation",
        learning_preferences="reading and practice",
        idol_name="Mentor",
        idol_domain="technology",
        idol_evidence={},
        session_context="",
        active_tier="balanced",
        routing_reason="test",
        client_factory=lambda **kwargs: FakeClient(),
    )

    assert error is None
    assert result is not None
    assert lesson_attempts == {"step_1": 5, "step_2": 4, "step_3": 4}
    assert repair_attempts == 1
    assert any("draft_1_practice_2" in stage for stage, *_ in calls)


@pytest.mark.asyncio
async def test_valid_checkpoint_skips_outline_and_completed_first_lesson() -> None:
    outline = _outline_payload()
    saved_step = copy.deepcopy(_valid_payload()["steps"][0])
    requested_steps: set[str] = set()

    class FakeClient:
        model = "fake-model"

        @section_client
        async def generate_json(self, *, user_prompt, output_model, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            from app.services.planning.lesson_review import LessonReview
            if issubclass(output_model, LessonReview):
                return SimpleNamespace(data={"acceptable": True, "issues": [], "practice_minutes": 60, "contains_calculations": False, "calculations": [], "literal_fact_ids": list(json.loads(user_prompt).get("numeric_spans", {}))}, error=None)
            assert output_model is PlanDetailLessonSectionsOutput
            step_id = next(
                candidate["id"]
                for candidate in outline["steps"]
                if f'"id":"{candidate["id"]}"' in user_prompt
            )
            requested_steps.add(step_id)
            return SimpleNamespace(
                data=copy.deepcopy(_lesson_sections_payload()),
                error=None,
            )

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner",
        task_title="Build a validated experiment",
        mission_hours=5,
        user_goal="learn product experimentation",
        learning_preferences="reading and practice",
        idol_name="Mentor",
        idol_domain="technology",
        idol_evidence={},
        session_context="",
        active_tier="balanced",
        routing_reason="test",
        client_factory=lambda **kwargs: FakeClient(),
        existing_checkpoint={
            **outline,
            "steps": [saved_step, *outline["steps"][1:]],
            "_generation": {"outline": outline},
        },
    )

    assert error is None
    assert result is not None
    assert requested_steps == {"step_2", "step_3"}
    assert result["steps"][0]["lesson_content"] == saved_step["lesson_content"]
    assert all("outline" not in stage for stage, *_ in calls)


@pytest.mark.asyncio
async def test_invalid_small_outline_retries_before_long_lessons() -> None:
    payload = _valid_payload()
    invalid_outline = _outline_payload()
    invalid_outline["materials"][0]["title"] = "Resource 2"
    valid_outline = _outline_payload()
    outline_attempts = 0
    outline_prompts: list[str] = []

    class FakeClient:
        model = "fake-model"

        @section_client
        async def generate_json(self, *, user_prompt, output_model, **kwargs):
            if output_model is LessonPackage:
                return SimpleNamespace(data=package_payload(), error=None)
            from app.services.planning.lesson_review import LessonReview
            if issubclass(output_model, LessonReview):
                return SimpleNamespace(data={"acceptable": True, "issues": [], "practice_minutes": 60, "contains_calculations": False, "calculations": [], "literal_fact_ids": list(json.loads(user_prompt).get("numeric_spans", {}))}, error=None)
            nonlocal outline_attempts
            if output_model is PlanItemDetailsOutlineOutput:
                outline_attempts += 1
                outline_prompts.append(user_prompt)
                outline = invalid_outline if outline_attempts == 1 else valid_outline
                return SimpleNamespace(data=copy.deepcopy(outline), error=None)

            step = next(
                candidate
                for candidate in payload["steps"]
                if f'"id":"{candidate["id"]}"' in user_prompt
            )
            assert step["id"] in {"step_1", "step_2", "step_3"}
            assert output_model is PlanDetailLessonSectionsOutput
            return SimpleNamespace(
                data=copy.deepcopy(_lesson_sections_payload()),
                error=None,
            )

    result, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="planner",
        task_title="Build a validated experiment",
        mission_hours=5,
        user_goal="learn product experimentation",
        learning_preferences="reading and practice",
        idol_name="Mentor",
        idol_domain="technology",
        idol_evidence={},
        session_context="",
        active_tier="balanced",
        routing_reason="test",
        client_factory=lambda **kwargs: FakeClient(),
    )

    assert error is None
    assert result is not None
    assert outline_attempts == 2
    assert [stage for stage, *_ in calls[:2]] == [
        "parallel_outline_attempt_1",
        "parallel_outline_attempt_2",
    ]
    assert "OUTLINE CONTRACT RETRY" not in outline_prompts[0]
    assert "OUTLINE CONTRACT RETRY" in outline_prompts[1]
    assert "no forced type quota" in outline_prompts[1]


def test_outline_shortens_only_overlong_display_heading():
    from app.tasks.plans import _validate_plan_detail_outline_response
    from app.services.llm.client import LLMResponse
    payload = _outline_payload()
    original = payload["steps"][0]["description"]
    payload["steps"][0]["title"] = "Separate accrual profit from cash movement using a complete fictional shop ledger"
    response = LLMResponse(data=payload)
    _validate_plan_detail_outline_response(response)
    assert response.error is None
    assert len(response.data["steps"][0]["title"]) <= 60
    assert response.data["steps"][0]["description"] == original
