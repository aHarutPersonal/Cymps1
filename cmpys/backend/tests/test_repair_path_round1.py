"""Phase 2 round 1 of the repair path (2026-11-05), built from captured benchmark failures."""
import copy
from unittest.mock import AsyncMock

import pytest

from app.services.planning import package_builder as builder
from tests.test_staged_package_builder import Factory, components

# Phase 0 benchmark pass A1, project_design_experienced_missing: the seed's
# qualitative case shows numbers without data; its correction declares the data
# but no result, which the case schema rejects. Both rejections were hidden
# behind "Lesson package seed could not be prepared".
_ONBOARDING = ("Original fictional example. A product team writes: 'Test a new onboarding video to improve "
               "sign-ups.' Revised version: 'For new trial users during a two-week test, show the three-step "
               "video instead of the static checklist. Compare the share who finish account setup within 24 "
               "hours; keep the video only if it leads by at least 5 percentage points.'")
_ONBOARDING_DATA = [
    {"id": "window_hours", "label": "Window for account setup completion", "value": 24, "unit": "hours"},
    {"id": "threshold_points", "label": "Required lead of video group", "value": 5, "unit": "percentage points"},
]


@pytest.mark.asyncio
async def test_unprepared_seed_reports_its_hidden_rejection_codes(monkeypatch):
    monkeypatch.setattr(builder, "record_llm_response", AsyncMock())
    seed, _ = components()
    first, corrected = copy.deepcopy(seed), copy.deepcopy(seed)
    first["teaching_cases"] = [{"id": "onboarding_video", "assumptions": _ONBOARDING, "data": [], "results": []}]
    corrected["teaching_cases"] = [{"id": "onboarding_video", "assumptions": _ONBOARDING,
                                    "data": _ONBOARDING_DATA, "results": []}]
    factory = Factory({"seed": [first, corrected]})
    package, response, _ = await builder.generate_initial_package(
        {"id": "step_1", "lesson_format": "tutorial_v1"}, {"component_recovery": "bounded_per_component"},
        client_factory=factory)
    assert package is None
    # The message keeps its prefix (scorers and the learner-facing mapping use
    # it) and adds only content-free codes of the last rejection.
    assert response.error == "Lesson package seed could not be prepared (codes: seed: value_error)"
    assert response.effective_parameters["component_failure_codes"] == {"seed": ["value_error"]}
    assert "24" not in response.error


@pytest.mark.asyncio
async def test_unprepared_activity_names_the_component_and_its_codes(monkeypatch):
    monkeypatch.setattr(builder, "record_llm_response", AsyncMock())
    seed, activities = components()
    bad = copy.deepcopy(activities["transfer"])
    bad["title"] = ""
    factory = Factory({"seed": [seed], **{key: [value] for key, value in activities.items() if key != "transfer"},
                       "transfer": [bad, bad]})
    package, response, _ = await builder.generate_initial_package(
        {"id": "step_1", "title": "Learn"},
        {"component_recovery": "bounded_per_component", "target_practice_minutes": 35}, client_factory=factory)
    assert package is None
    assert response.error.startswith(
        "Lesson package activity could not be prepared; validated components are saved (codes: activity_transfer: ")
    assert "activity_practice" not in response.error  # a component that succeeded reports nothing


# --- Step 3: scoped activity repair gets one in-call correction ---------------

def _scoped_client(responses, requests):
    import json

    from app.services.llm.client import LLMResponse

    def factory(**options):
        class Client:
            model = "offline"

            async def generate_json(self, **request):
                requests.append(json.loads(request["user_prompt"]))
                return LLMResponse(data=copy.deepcopy(responses.pop(0)))
        return Client()
    return factory


@pytest.mark.asyncio
async def test_field_scoped_repair_hears_why_it_was_rejected_and_corrects_once():
    # Phase 0 benchmark A5 accounting_novice_missing: a field-scoped correction
    # also rewrote the shared instructions and was rejected without a retry.
    from app.services.planning import lesson_package as module
    from tests.section_client_fixture import activity_draft_fixture
    from tests.test_scoped_activity_repair import replacement, structured_package

    package, good = structured_package(), replacement()
    bad = copy.deepcopy(good)
    bad["instructions"] += " Also rewrite the shared task."
    requests, record = [], AsyncMock(return_value=True)
    repaired, response, _ = await module._repair_public_activities_serial(
        {}, {}, package, {"transfer": {"argument"}}, ["The argument field accepts an unsupported claim."],
        client_factory=_scoped_client([activity_draft_fixture(bad), activity_draft_fixture(good)], requests),
        _record_response=record)
    assert repaired is not None and not response.error
    assert repaired.workbook.activities[1].instructions == package.workbook.activities[1].instructions
    assert len(requests) == 2 and "correction" not in requests[0]
    (error,) = requests[1]["correction"]["validation_errors"]
    assert error["message"] == "Field-owned correction changed shared public activity content"
    assert "instructions" in error["changed_properties"] and "copy title, instructions" in error["correction"]
    assert requests[1]["correction"]["rejected_activity"]["instructions"] == bad["instructions"]
    # The scope never widens: the same targets and field ids are requested again.
    assert requests[1]["validated_repair_targets"] == requests[0]["validated_repair_targets"]
    assert requests[1]["field_ids"] == ["argument"]
    assert record.await_args.kwargs["result_status"] == "rejected"


@pytest.mark.asyncio
async def test_scoped_repair_stops_after_its_one_correction():
    from app.services.planning import lesson_package as module
    from tests.section_client_fixture import activity_draft_fixture
    from tests.test_scoped_activity_repair import replacement, structured_package

    package = structured_package()
    unchanged = activity_draft_fixture(package.workbook.activities[1].model_dump(mode="json"))
    requests = []
    repaired, response, _ = await module._repair_public_activities_serial(
        {}, {}, package, {"transfer": None}, ["The transfer repeats the practice task."],
        client_factory=_scoped_client([unchanged, unchanged, unchanged], requests),
        _record_response=AsyncMock(return_value=True))
    # Phase 0 benchmark B4 geometry_novice_missing returned the activity unchanged.
    assert repaired is None and len(requests) == 2
    assert response.error == ("Scoped activity correction failed validation: "
                              "Exercise repair did not change the rejected package")
    assert "make the change the blocking_defects require" in (
        requests[1]["correction"]["validation_errors"][0]["correction"])


def test_an_activity_datum_names_its_own_id_when_a_case_reuses_it():
    # Phase 0 benchmark B3 geometry_novice_missing: "slant_edge" was declared by
    # the activity and by the teaching case with different labels, so the leak
    # had no unique name and the whole correction was rejected.
    from app.services.planning.lesson_package import (
        TeachingCase, internal_id_leaks, relabel_internal_ids, require_no_internal_ids,
    )
    from app.services.planning.package_builder import LessonPackageActivity
    from tests.test_scoped_activity_repair import structured_package

    case = TeachingCase.model_validate({"id": "plot", "assumptions": "A triangular plot has a base and a height.",
        "data": [{"id": "slant_edge", "label": "Slanted edge, not perpendicular to the base", "value": 10, "unit": "m"}],
        "results": [{"id": "double_edge", "label": "Twice the edge", "expression": "slant_edge * 2", "unit": "m",
                     "decimal_places": 0}]})
    raw = structured_package().workbook.activities[1].model_dump(mode="json")
    raw["data"] = [{"id": "slant_edge", "label": "Slanted edge, not perpendicular to either base", "value": 13,
                    "unit": "m"}]
    raw["worked_solution"]["steps"][0]["explanation"] = (
        "The slanted edge (slant_edge, 13 m) is stated not to be perpendicular to either base, so it is not a height.")
    activity = LessonPackageActivity.model_validate(raw)
    assert ("worked_solution.argument", "slant_edge") in internal_id_leaks(activity, [case])
    relabelled = relabel_internal_ids(activity, [case])
    require_no_internal_ids(relabelled, [case])
    assert "(slanted edge, not perpendicular to either base, 13 m)" in relabelled.worked_solution.steps[0].explanation


# --- Step 4: one outer writer rewrite ------------------------------------------

async def _run_tutorial(monkeypatch, drafts, *, reviews=None, repairs_reply=None, preflights=None, package=None):
    """One 6-minute tutorial through the real writer and assembly; reviews mocked.

    ``reviews`` and ``preflights`` list verdicts in order (default: approve);
    ``repairs_reply(request)`` answers every non-writer request (section or case repair).
    """
    from types import SimpleNamespace

    from app.services.llm.client import LLMResponse
    from app.services.llm.schemas import PlanTutorialLessonSectionsOutput
    from app.tasks.plans import _generate_plan_item_details_parallel
    from tests.test_short_tutorial_pipeline import outline, short_package

    package, prompts, repairs = package or short_package(), [], []
    reviewed, repair_prompts, preflighted = [], [], []
    _run_tutorial.reviewed, _run_tutorial.repair_prompts = reviewed, repair_prompts
    _run_tutorial.preflighted = preflighted

    async def build(step, context, **kwargs):
        return package, LLMResponse(data={}), SimpleNamespace(model="offline")

    checks = list(preflights or [])

    async def preflight(checked, *args, **kwargs):
        preflighted.append(checked)
        if checks:
            return checks.pop(0)
        return [], LLMResponse(data={}), SimpleNamespace(model="offline")

    verdicts = list(reviews or [])

    async def review(step, **kwargs):
        reviewed.append(copy.deepcopy(step))
        if verdicts:
            return verdicts.pop(0)
        return [], LLMResponse(data={"practice_minutes": 3}), SimpleNamespace(model="offline")

    class Client:
        model = "offline"

        async def generate_json(self, **kwargs):
            if repairs_reply is not None and not issubclass(kwargs["output_model"], PlanTutorialLessonSectionsOutput):
                repair_prompts.append(kwargs["user_prompt"])
                return LLMResponse(data=repairs_reply(kwargs), finish_reason="stop")
            assert issubclass(kwargs["output_model"], PlanTutorialLessonSectionsOutput)
            prompts.append(kwargs["user_prompt"])
            return LLMResponse(data=copy.deepcopy(drafts[min(len(prompts), len(drafts)) - 1]), finish_reason="stop")

    monkeypatch.setattr("app.services.planning.package_builder.generate_initial_package", build)
    monkeypatch.setattr("app.services.planning.package_preflight.review_package", preflight)
    monkeypatch.setattr("app.services.planning.lesson_review.review_lesson", review)
    payload, _, error = await _generate_plan_item_details_parallel(
        system_prompt="Teach", task_title="Claim", mission_hours=0.1, user_goal="Reason",
        learning_preferences="examples", idol_name="Mentor", idol_domain="writing", idol_evidence={},
        session_context="", active_tier="balanced", routing_reason="test",
        client_factory=lambda **kwargs: Client(), prepared_packages={}, validation_records={},
        repair_attempts=repairs,
        existing_checkpoint={"_generation": {"outline": outline(1), "outline_contract_version": 3}})
    return payload, error, prompts, repairs


def _near_miss():
    # Phase 0 benchmark A3/B2/B3: 413-415 words against the 430 floor, twice.
    from tests.test_short_tutorial_pipeline import sections

    short = sections()
    short["core_framework"] = short["core_framework"].replace("explanation " * 45, "", 1)
    short["worked_example"] = short["worked_example"].replace("explanation " * 44, "", 1)
    return short


@pytest.mark.asyncio
async def test_a_writer_near_miss_gets_one_rewrite_that_hears_the_validator_error(monkeypatch):
    from tests.test_short_tutorial_pipeline import sections

    payload, error, prompts, repairs = await _run_tutorial(monkeypatch, [_near_miss(), _near_miss(), sections()])
    assert error is None and payload["steps"][0]["lesson_content"]
    # The writer's own draft and correction, then one outer rewrite.
    assert len(prompts) == 3
    assert "they must total 430-720 words" not in prompts[0]
    assert "they must total 430-720 words before canonical headings" in prompts[2]
    assert [(entry["kind"], entry["source"], entry["outcome"]) for entry in repairs] == [
        ("writer_rewrite", "writer", "requested")]
    assert repairs[0]["error"].startswith("Section drafting failed: tutorial: ")


@pytest.mark.asyncio
async def test_the_outer_rewrite_is_spent_once(monkeypatch):
    payload, error, prompts, repairs = await _run_tutorial(monkeypatch, [_near_miss()])
    assert error == ("step_1: Section drafting failed: tutorial: tutorial fields have 415 words; they must "
                     "total 430-720 words before canonical headings")
    assert not payload["steps"][0].get("lesson_content")
    assert len(prompts) == 4 and len(repairs) == 1


# --- Step 5: repairs hear the actual finding, never a private answer -----------

def test_prose_writers_hear_only_findings_inside_the_assessment_boundary():
    from app.tasks.plans import _public_safe_findings
    from tests.test_lesson_compact_repairs import numeric_package

    package = numeric_package()  # workbook: profit 14 / interest 4 = coverage 3.5 (private)
    lesson = "## Core Framework\nA ratio compares two amounts: 12 divided by 3 gives 4. Name the cause before the effect."
    solution = package.workbook.activities[0].worked_solution
    explanation = solution.steps[0].explanation if hasattr(solution, "steps") else str(solution)
    findings = [
        "core_framework: the ratio compares the effect before the cause.",
        "worked_example: 12 divided by 3 gives 4 before the cause.",
        "worked_example: the coverage answer is 3.5.",                          # a private answer
        "check_your_understanding: it says " + " ".join(explanation.split()[:8]),  # quotes a private solution
        "core_framework: interest expense is never named.",                     # names the practice case
        "core_framework: the guided_coverage ratio is undefined.",               # an unknown identifier
    ]
    assert _public_safe_findings(findings, package, lesson) == findings[:2]


def _review(failures, **data):
    from types import SimpleNamespace

    from app.services.llm.client import LLMResponse
    return failures, LLMResponse(data={"practice_minutes": 3, **data}), SimpleNamespace(model="offline")


@pytest.mark.asyncio
async def test_a_section_repair_and_its_rewrite_hear_the_reviewers_finding(monkeypatch):
    from tests.test_short_tutorial_pipeline import sections

    finding = "core_framework: the comparison says bounded claims need no evidence, which contradicts the rule."
    repaired = sections()["core_framework"].replace("explanation", "corrected", 3)
    blocked = _review([finding], affected_sections=["core_framework"])
    payload, error, prompts, _ = await _run_tutorial(
        monkeypatch, [sections()], reviews=[blocked, blocked, blocked, blocked],
        repairs_reply=lambda request: {"sections": [{"field_name": "core_framework", "content": repaired}]})
    (repair_prompt,) = _run_tutorial.repair_prompts
    assert '"findings": ["' + finding in repair_prompt
    # Still blocked after the repair: the rewrite hears the latest finding too.
    assert len(prompts) == 2 and finding in prompts[1]
    assert error and finding in error


@pytest.mark.asyncio
async def test_a_practice_only_correction_keeps_the_tutorial_reading(monkeypatch):
    # The tutorial reading is written from teaching cases alone. A corrected
    # activity used to force a full prose rewrite (and, on a last attempt, the
    # final error "The exercise contract was corrected..."; benchmark B4).
    from types import SimpleNamespace

    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_package import LessonPackage
    from tests.test_short_tutorial_pipeline import sections, short_package

    original = short_package().model_dump(mode="json")
    original["workbook"]["activities"][0]["instructions"] += " State the deciding cue in your own words."
    corrected = LessonPackage.model_validate(original)
    package_repair = AsyncMock(return_value=(corrected, LLMResponse(data={}), SimpleNamespace(model="offline")))
    monkeypatch.setattr("app.tasks.plans.generate_package", package_repair)
    issue = "practice.guided: The public instructions state the deciding cue the field asks for."
    flagged = _review([issue], package_issues=[issue])
    flagged[1].effective_parameters = {"validated_repair_targets": ["practice.guided"]}
    payload, error, prompts, repairs = await _run_tutorial(monkeypatch, [sections()], reviews=[flagged])
    assert error is None and payload["steps"][0]["lesson_content"]
    assert package_repair.await_count == 1 and len(prompts) == 1
    first, second = _run_tutorial.reviewed
    assert first["lesson_content"] == second["lesson_content"]
    assert [(entry["kind"], entry["outcome"]) for entry in repairs] == [("package_repair", "applied")]


# --- Step 6: teaching-case text patches (R2 + R3) --------------------------------

def _numeric_tutorial_package():
    # Modelled on Phase 0 benchmark A4 accounting_novice_evidence: the worked
    # analysis misstated a cash effect, the preflight targeted the case's result
    # (teaching.cafe_march.cash_net), and the repair ended in "Exercise repair
    # lacks an exact independently validated activity scope".
    from app.services.planning.lesson_package import LessonPackage
    from tests.test_short_tutorial_pipeline import short_package

    raw = short_package().model_dump(mode="json")
    raw["teaching_cases"] = [{"id": "cafe_march", "assumptions": (
        "Original fictional cafe. In March it records 900 credits of sales and pays 620 credits in cash. Worked "
        "analysis: supplies bought but not yet paid raise cash, so net cash is 280 credits."),
        "data": [{"id": "sales", "label": "Sales recorded in March", "value": 900, "unit": "credits"},
                 {"id": "cash_paid", "label": "Cash paid in March", "value": 620, "unit": "credits"}],
        "results": [{"id": "cash_net", "label": "Net cash in March", "expression": "sales - cash_paid",
                     "unit": "credits", "decimal_places": 0}]}]
    return LessonPackage.model_validate(raw)


def _numeric_sections():
    from tests.test_short_tutorial_pipeline import sections

    draft = sections()
    draft["worked_example"] = "The net cash is [[result:cafe_march.cash_net]] credits. " + draft["worked_example"]
    return draft


_FIXED = ("Original fictional cafe. In March it records 900 credits of sales and pays 620 credits in cash. Worked "
          "analysis: supplies bought but not yet paid leave cash unchanged, so net cash is 280 credits.")


def test_a_teaching_patch_changes_only_the_case_text():
    from app.services.planning.lesson_package import TeachingCaseRepair, apply_teaching_case_patches

    package = _numeric_tutorial_package()
    patched = apply_teaching_case_patches(package, TeachingCaseRepair.model_validate(
        {"case_patches": [{"case_id": "cafe_march", "assumptions": _FIXED}]}), {"cafe_march"})
    assert patched.teaching_cases[0].assumptions == _FIXED
    assert patched.teaching_cases[0].data == package.teaching_cases[0].data
    assert patched.teaching_cases[0].results == package.teaching_cases[0].results
    assert patched.workbook == package.workbook


@pytest.mark.parametrize("repair,message", [
    ({"case_patches": [{"case_id": "cafe_march", "assumptions": _FIXED.replace("280", "300")}]}, "shows 300"),
    ({"case_patches": []}, "exactly once"),
    ({"case_patches": [{"case_id": "cafe_march", "assumptions": _numeric_tutorial_package()
                        .teaching_cases[0].assumptions}]}, "did not change"),
    ({"requires_data_change": ["The case needs a datum for unpaid supplies."]}, "requires a data"),
])
def test_a_teaching_patch_never_invents_a_fact_or_skips_its_case(repair, message):
    from app.services.planning.lesson_package import TeachingCaseRepair, apply_teaching_case_patches

    with pytest.raises(ValueError, match=message):
        apply_teaching_case_patches(_numeric_tutorial_package(), TeachingCaseRepair.model_validate(repair),
                                    {"cafe_march"})


def _flag(target, description, **parameters):
    from types import SimpleNamespace

    from app.services.llm.client import LLMResponse
    response = LLMResponse(data={}, effective_parameters={"validated_repair_targets": [target], **parameters})
    return [f"{target}: {description}"], response, SimpleNamespace(model="offline")


@pytest.mark.asyncio
async def test_a_preflight_result_target_is_patched_and_rechecked_without_a_rebuild(monkeypatch):
    package = _numeric_tutorial_package()
    monkeypatch.setattr("app.tasks.plans.generate_package",
                        AsyncMock(side_effect=AssertionError("No activity was rejected")))
    flagged = _flag("teaching.cafe_march.cash_net", "unpaid supplies do not raise cash; the analysis says they do.")
    payload, error, prompts, repairs = await _run_tutorial(
        monkeypatch, [_numeric_sections()], package=package, preflights=[flagged],
        repairs_reply=lambda request: {"case_patches": [{"case_id": "cafe_march", "assumptions": _FIXED}]})
    assert error is None and payload["steps"][0]["lesson_content"]
    (patch_request,) = _run_tutorial.repair_prompts
    assert '"targeted_case_ids": ["cafe_march"]' in patch_request
    # The recheck reviewed the patched case before any prose was written, and
    # the audit log shows no rebuild and no activity repair.
    first, recheck = _run_tutorial.preflighted
    assert recheck.teaching_cases[0].assumptions == _FIXED and first.teaching_cases[0].data == recheck.teaching_cases[0].data
    assert [(entry["kind"], entry["source"], entry["targets"], entry["outcome"]) for entry in repairs] == [
        ("teaching_text_patch", "preflight", ["teaching.cafe_march.cash_net"], "applied")]


@pytest.mark.asyncio
async def test_a_review_teaching_target_is_patched_rechecked_and_the_reading_rewritten(monkeypatch):
    # Phase 0 benchmark B3 accounting_experienced_evidence: the review could only
    # say "package" for a teaching-case defect, which granted no repair at all.
    package = _numeric_tutorial_package()
    monkeypatch.setattr("app.tasks.plans.generate_package",
                        AsyncMock(side_effect=AssertionError("No activity was rejected")))
    issue = "teaching.cafe_march: the analysis says unpaid supplies raise cash."
    flagged = _review([issue], package_issues=[issue])
    flagged[1].effective_parameters = {"validated_repair_targets": ["teaching.cafe_march"]}
    payload, error, prompts, repairs = await _run_tutorial(
        monkeypatch, [_numeric_sections()], package=package, reviews=[flagged],
        repairs_reply=lambda request: {"case_patches": [{"case_id": "cafe_march", "assumptions": _FIXED}]})
    assert error is None and payload["steps"][0]["lesson_content"]
    assert len(_run_tutorial.preflighted) == 2  # the first preflight, then the patched case
    assert len(prompts) == 2 and "The exercise contract was corrected" in prompts[1]
    assert [(entry["kind"], entry["outcome"]) for entry in repairs] == [
        ("teaching_text_patch", "applied"), ("prose_rewrite", "requested")]


def test_review_targets_may_name_an_existing_teaching_case_only():
    from app.services.planning.lesson_review import LessonReview, _validated_package_issue_targets

    context = _numeric_tutorial_package().review_context()

    def targets(*names):
        review = LessonReview.model_validate({"acceptable": False, "issues": [], "package_issues": ["defect"] * len(names),
            "package_issue_targets": list(names), "practice_minutes": 3, "contains_calculations": False,
            "calculations": []})
        return _validated_package_issue_targets(review, context)

    assert targets("teaching.cafe_march") == ["teaching.cafe_march"]
    assert targets("teaching.cafe_march", "practice.guided") == ["practice.guided", "teaching.cafe_march"]
    assert targets("teaching.unknown") == []
    assert targets("package") == []


# --- Step 7: a numeric-binding defect names the span it could not bind ----------

def test_an_unbindable_span_is_named_by_id_path_and_its_own_words():
    # Phase 0 benchmark A4 geometry_experienced_evidence: "Numeric evidence for
    # spans n2 could not be bound ... (codes: invalid_math_role, ...)" named n2,
    # but not which sentence of the activity n2 is.
    from app.services.planning.package_preflight import _evidence_defect_description, _server_evidence_facts

    spans = {"n2": "The sail's base is 14 m and its perpendicular height is 9 m, so its area is 63 m².",
             "n5": "A slanted edge of 11 m is not a height."}
    facts = _server_evidence_facts(["n2"], spans, {"n2": "instructions"},
                                   ["n2: 14.0 * 9.0 / 2 = 63, not 64"])
    assert facts == ['n2 at instructions quoting "' + spans["n2"] + '" (the span states 64; the server '
                     'evaluated the bound calculation 14 * 9 / 2 = 63)']
    description = _evidence_defect_description(
        {"claim_ids": ["n2"], "codes": ["invalid_math_role"], "paths": []}, facts)
    assert "codes: invalid_math_role" in description and spans["n2"] in description
    assert len(description) <= 2000 and "n5" not in description


def test_a_long_span_quote_is_bounded():
    from app.services.planning.package_preflight import _server_evidence_facts

    (row,) = _server_evidence_facts(["n1"], {"n1": "word " * 100}, {"n1": "hint"})
    assert row.endswith('..."') and len(row) < 200
