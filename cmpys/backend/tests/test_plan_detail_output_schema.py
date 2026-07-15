import asyncio
import copy
import re
from types import SimpleNamespace

import pytest

from app.services.llm.prompt_loader import load_prompt
from app.services.llm.schemas import (
    PlanDetailLessonSectionsOutput,
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
    _plan_detail_repair_plan,
    _plan_detail_recovery_prompt,
    _plan_detail_step_repair_prompt,
    _plan_detail_substeps_repair_prompt,
    _validate_plan_detail_response,
    _validate_plan_detail_outline_response,
    _validate_plan_detail_step_response,
    _writing_thinking_budget,
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
    lesson = heading_text + ("deliberate practice evidence mechanism example " * 520)
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
                "estimate_minutes": 80,
                "reading_minutes": 13,
                "practice_minutes": 67,
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
    assert "1,900-3,400" in retry
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
    assert "2,400-2,800" in prompt
    assert "25-40 words" in prompt


def test_single_step_repair_schema_keeps_the_full_quality_floor() -> None:
    valid_step = _valid_payload()["steps"][0]
    assert PlanDetailStepRepairOutput.model_validate(valid_step).id == "step_1"

    invalid_step = dict(valid_step)
    invalid_step["lesson_content"] = "short"
    with pytest.raises(ValueError, match="accepted range is 1900-3400"):
        PlanDetailStepRepairOutput.model_validate(invalid_step)


@pytest.mark.parametrize(
    ("word_count", "accepted"),
    [
        (1899, False),
        (1900, True),
        (1977, True),
        (2176, True),
        (3400, True),
        (3401, False),
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
    assert "25-40 word" in prompt
    assert "no fixed item count" in prompt

    valid_substep = (
        "Set a twenty minute timer, apply the framework to one real artifact, "
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

    with pytest.raises(ValueError, match="required range is 20-50"):
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
    assert all(20 <= len(substep.split()) <= 50 for substep in substeps)


def _outline_payload() -> dict:
    payload = _valid_payload()
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
        "guided_practice": "substance " * 500,
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


def test_parallel_outline_maps_alternative_resource_names_to_materials() -> None:
    payload = _outline_payload()
    payload["materials"][0]["title"] = "The Lean Startup"
    payload["materials"][0]["reason"] = "Lean product experimentation."
    payload["steps"][1]["resources"] = [
        "Running Lean",
        "Scientific experimentation guide",
    ]
    response = SimpleNamespace(data=payload, error=None)

    _validate_plan_detail_outline_response(response)

    assert response.error is None
    assert set(response.data["steps"][1]["resources"]).issubset(
        {material["title"] for material in response.data["materials"]}
    )
    assert "The Lean Startup" in response.data["steps"][1]["resources"]


def test_quality_writing_keeps_required_model_thinking_enabled() -> None:
    assert _writing_thinking_budget("quality") is None
    assert _writing_thinking_budget("balanced") == 0


@pytest.mark.asyncio
async def test_long_lessons_are_requested_concurrently_after_outline(
    monkeypatch,
) -> None:
    payload = _valid_payload()
    outline = _outline_payload()
    started: set[str] = set()
    all_started = asyncio.Event()
    client_options: list[dict] = []

    class FakeClient:
        model = "fake-model"

        async def generate_json(self, *, user_prompt, output_model, **kwargs):
            if output_model is PlanItemDetailsOutlineOutput:
                return SimpleNamespace(data=copy.deepcopy(outline), error=None)

            step = next(
                candidate
                for candidate in payload["steps"]
                if f'"id":"{candidate["id"]}"' in user_prompt
            )
            started.add(step["id"])
            if len(started) == 3:
                all_started.set()
            await asyncio.wait_for(all_started.wait(), timeout=1)
            return SimpleNamespace(
                data=copy.deepcopy(_lesson_sections_payload()),
                error=None,
            )

    def client_factory(**kwargs):
        client_options.append(kwargs)
        return FakeClient()

    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client",
        client_factory,
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
    )

    assert error is None
    assert result is not None
    assert started == {"step_1", "step_2", "step_3"}
    assert all(
        1900 <= len(step["lesson_content"].split()) <= 3400
        for step in result["steps"]
    )
    assert all(
        "## References" in step["lesson_content"]
        for step in result["steps"]
    )
    assert [stage for stage, *_ in calls] == [
        "parallel_outline_attempt_1",
        "parallel_lesson_step_1_attempt_1",
        "parallel_lesson_step_2_attempt_1",
        "parallel_lesson_step_3_attempt_1",
    ]
    assert client_options[0]["tier"] == "balanced"
    assert all(options["tier"] == "quality" for options in client_options[1:])
    assert all(options["timeout"] == 150 for options in client_options[1:])
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


def test_section_quality_uses_words_instead_of_brittle_character_counts() -> None:
    sections = PlanDetailLessonSectionsOutput.model_validate(
        _lesson_sections_payload()
    )

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
    assert all(
        20 <= len(substep.split()) <= 50
        for substep in response.data["substeps"]
    )
    assert "phase 1" in response.data["substeps"][0]
    assert "phase 6" in response.data["substeps"][5]


def test_parallel_lesson_compacts_verbose_substep_objects_without_retry() -> None:
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
    assert all(
        20 <= len(substep.split()) <= 50
        for substep in response.data["substeps"]
    )
    assert all("Success means" in substep for substep in response.data["substeps"])


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

        async def generate_json(self, *, user_prompt, output_model, **kwargs):
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
                invalid = {
                    **_lesson_sections_payload(),
                    "core_framework": "650-750 words without the heading",
                }
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
    assert attempts_by_step == {"step_1": 2, "step_2": 1, "step_3": 1}
    assert "PREVIOUS ATTEMPT ERROR" in prompts_by_step["step_1"][1]
    assert "core_framework has" in prompts_by_step["step_1"][1]
    assert [stage for stage, *_ in calls] == [
        "parallel_outline_attempt_1",
        "parallel_lesson_step_1_attempt_1",
        "parallel_lesson_step_1_attempt_2",
        "parallel_lesson_step_2_attempt_1",
        "parallel_lesson_step_3_attempt_1",
    ]


@pytest.mark.asyncio
async def test_invalid_small_outline_retries_before_long_lessons() -> None:
    payload = _valid_payload()
    invalid_outline = _outline_payload()
    invalid_outline["materials"][0]["type"] = "course"
    valid_outline = _outline_payload()
    outline_attempts = 0
    outline_prompts: list[str] = []

    class FakeClient:
        model = "fake-model"

        async def generate_json(self, *, user_prompt, output_model, **kwargs):
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
    assert "exactly one book and one video" in outline_prompts[1]
