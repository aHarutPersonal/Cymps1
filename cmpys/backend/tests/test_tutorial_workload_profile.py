"""Short tutorials keep timing, private evidence and exact-approval boundaries."""
import copy
import json
from unittest.mock import AsyncMock

import pytest

from app.services.content_quality import (
    MIN_PLAN_DETAIL_LESSON_WORDS, TUTORIAL_LESSON_FORMAT,
    plan_detail_min_words, plan_detail_reading_minutes,
)
from app.services.planning.artifact_identity import progressive_ready_step_ids, validated_lesson_steps
from app.services.planning.lesson_package import (
    LessonPackage, current_package_approval, digest, validation_identity,
)
from app.services.planning.lesson_review import LessonReview, _workload_error
from app.services.planning.package_review import package_review_payload
from app.services.planning.workload_contract import (
    build_workload_contract, build_workload_planning_context, workload_feasibility_issues,
)
from tests.lesson_package_fixtures import package_payload
from tests.test_previous_release_read_compatibility import prior_approved_details


PRE_TUTORIAL_IDENTITY = {
    "capability_hash": "1815a97ad0c7246f737c493fbec7b9217c6a5dd6a7d96cacd93c0c34b3afe48f",
    "generation_contract_hash": "cfa8efe4c033294fb1eb24d22a30d9b6be720f127b253bd32292fd6c10a6eea3",
    "package_version": 1,
    "prompt_hash": "c971af6e2e3353ba6baa08a8659937a47907c800ac4eaf0f35177747a72bc089",
    "review_version": 23,
    "schema_hash": "3898967e9bf8814c14a4b9c9daae02cd492e069a0ae27ebcde887d9fa818d93b",
}


def short_package():
    source = package_payload()
    from tests.test_short_tutorial_pipeline import short_package as teaching_package
    source["teaching_cases"] = teaching_package().model_dump(mode="json")["teaching_cases"]
    for activity in source["workbook"]["activities"]:
        activity.update(minutes_min=1, minutes_max=2)
    return LessonPackage.model_validate(source)


def short_steps():
    return [{"id": "step_1", "lesson_format": TUTORIAL_LESSON_FORMAT,
             "lesson_content": "concept " * 450}]


def test_tutorial_planning_and_preflight_agree_without_changing_work_estimates():
    activities = short_package().model_dump(mode="json")["workbook"]["activities"]
    before = copy.deepcopy(activities)
    planning = build_workload_planning_context(lesson_format=TUTORIAL_LESSON_FORMAT)
    contract = build_workload_contract(activities, lesson_format=TUTORIAL_LESSON_FORMAT)
    assert planning["reading_minutes_range"] == contract["reading_minutes_range"] == [3, 4]
    assert planning["allowed_total_minutes_range"] == contract["allowed_total_minutes_range"] == [5, 8]
    assert planning["supported_practice_minutes_range"] == contract["feasible_practice_minutes_range"] == [2, 4]
    assert contract["practice_minutes_range"] == [2, 4]
    assert not workload_feasibility_issues(activities, lesson_format=TUTORIAL_LESSON_FORMAT)
    assert workload_feasibility_issues(activities)  # Legacy sessions still need their full scope.
    assert activities == before
    assert "worked_solution" not in json.dumps(contract)


def test_tutorial_exercise_time_never_fails_a_lesson():
    # Owner decision (2026-11-06): tutorial exercise time is server-set and never fails a
    # lesson, so even a long estimate is no feasibility issue; legacy lessons keep the check.
    activities = [{"id": "guided", "minutes_min": 8, "minutes_max": 10},
                  {"id": "transfer", "minutes_min": 8, "minutes_max": 10}]
    before = copy.deepcopy(activities)
    assert workload_feasibility_issues(activities, lesson_format=TUTORIAL_LESSON_FORMAT) == []
    assert activities == before


@pytest.mark.parametrize("words,minutes", [(450, 3), (600, 3), (601, 4), (800, 4)])
def test_short_reading_time_uses_actual_words_and_consistent_rounding(words, minutes):
    assert plan_detail_reading_minutes(words, TUTORIAL_LESSON_FORMAT) == minutes
    assert plan_detail_reading_minutes(words) == max(1, round(words / 200))


def test_floor_changes_only_for_an_explicit_recognized_marker():
    assert plan_detail_min_words({}) == MIN_PLAN_DETAIL_LESSON_WORDS
    assert plan_detail_min_words({"lesson_format": "future_or_invalid"}) == MIN_PLAN_DETAIL_LESSON_WORDS
    assert plan_detail_min_words({"lesson_format": TUTORIAL_LESSON_FORMAT}) == 450
    details = {"steps": short_steps(), "_generation": {"status": "partial", "ready_step_ids": ["step_1"]}}
    assert progressive_ready_step_ids(details) == ("step_1",)
    details["steps"][0].pop("lesson_format")
    assert progressive_ready_step_ids(details) == ()


def test_tutorial_package_review_receives_the_same_profile_and_private_evidence():
    package = short_package()
    payload = package_review_payload(package, {"id": "step_1", "lesson_format": TUTORIAL_LESSON_FORMAT}, {})
    assert payload["workload_contract"]["allowed_total_minutes_range"] == [5, 8]
    assert payload["workload_contract"]["reading_minutes_range"] == [3, 4]
    assert all(a["worked_solution"] for a in payload["package"]["workbook"]["activities"])


@pytest.mark.parametrize("practice,reading", [(2, 3), (4, 4), (1, 3), (5, 3)])
def test_final_review_never_fails_a_tutorial_on_exercise_time(practice, reading):
    review = LessonReview(acceptable=True, issues=[], practice_minutes=practice, contains_calculations=False, calculations=[])
    assert _workload_error(review, short_package().review_context(), reading_minutes=reading,
                           lesson_format=TUTORIAL_LESSON_FORMAT) is None
    # A legacy lesson still checks the same estimate against its own longer profile.
    assert _workload_error(review, short_package().review_context(), reading_minutes=reading)


@pytest.mark.parametrize("generation", [None, {}, {"lesson_package_version": 0}, {"lesson_package_version": 1}])
def test_short_marker_never_promotes_unapproved_legacy_prose(generation):
    details = {"steps": short_steps()}
    if generation is not None:
        details["_generation"] = generation
    assert not current_package_approval(details, allow_compatible_read=True)


@pytest.mark.parametrize("marker", [None, "", "tutorial_v2", "legacy"])
def test_unknown_explicit_markers_fail_closed(marker):
    details = {"steps": short_steps()}
    details["steps"][0]["lesson_format"] = marker
    assert validated_lesson_steps(details) is None
    assert not current_package_approval(details, allow_compatible_read=True)


def test_top_level_tutorial_requires_corresponding_versioned_steps_and_approval():
    details = prior_approved_details()
    details["lesson_format"] = TUTORIAL_LESSON_FORMAT
    assert not current_package_approval(details, allow_compatible_read=True)
    assert current_package_approval(prior_approved_details(), allow_compatible_read=True)


def test_exact_pre_tutorial_identity_preserves_old_approved_content_only():
    assert digest(PRE_TUTORIAL_IDENTITY) == "05518707e7d114e842ebd192fab1160c6418f035c04f4a5c26d7cc5c7092cebb"
    details = prior_approved_details()
    generation = details["_generation"]
    generation["validation_identity"] = copy.deepcopy(PRE_TUTORIAL_IDENTITY)
    generation["lesson_validation"]["step_1"].update(PRE_TUTORIAL_IDENTITY)
    assert validation_identity() != PRE_TUTORIAL_IDENTITY
    assert current_package_approval(details, allow_compatible_read=True)
    assert not current_package_approval(details)
    changed = copy.deepcopy(details)
    changed["steps"][0]["lesson_content"] += " Unauthorized text."
    assert not current_package_approval(changed, allow_compatible_read=True)
    changed = copy.deepcopy(details)
    changed["steps"][0]["lesson_format"] = TUTORIAL_LESSON_FORMAT
    assert not current_package_approval(changed, allow_compatible_read=True)


@pytest.mark.asyncio
async def test_builder_uses_short_prompts_and_workload_without_removing_private_solutions(monkeypatch):
    from app.services.planning import package_builder as builder
    from tests.test_staged_package_builder import Factory, components

    from tests.lesson_package_fixtures import multi_choice_first

    seed, activities = components()
    seed["teaching_cases"] = short_package().model_dump(mode="json")["teaching_cases"]
    for activity in activities.values():
        activity.update(minutes_min=1, minutes_max=2)
        multi_choice_first(activity)  # new tutorials need a number or multi_choice answer
    factory = Factory({"seed": [seed], **{key: [value] for key, value in activities.items()}})
    monkeypatch.setattr(builder, "record_llm_response", AsyncMock(return_value=True))
    package, response, _ = await builder.generate_initial_package(
        {"id": "step_1", "title": "One concept", "lesson_format": TUTORIAL_LESSON_FORMAT},
        {"lesson_format": TUTORIAL_LESSON_FORMAT, "target_practice_minutes": 3}, client_factory=factory)
    assert package and not response.error
    assert len(factory.requests) == 3  # One seed and two small independent phases.
    assert all("tutorial_v1" in request[1]["system_prompt"] for request in factory.requests)
    assert all(request[2]["workload_plan"]["allowed_total_minutes_range"] == [5, 8] for request in factory.requests)
    assert all(activity.worked_solution for activity in package.workbook.activities)
    assert all("worked_solution" not in activity for activity in package.writer_context()["practice"]["activities"])


def test_current_tutorial_approval_binds_the_marker_and_exact_content():
    from app.services.llm.schemas import plan_detail_step_model

    details = prior_approved_details()
    step = details["steps"][0]
    step.update(lesson_format=TUTORIAL_LESSON_FORMAT,
                lesson_content=" ".join(step["lesson_content"].split()[:600]),
                reading_minutes=3, practice_minutes=3, estimate_minutes=6)
    canonical = plan_detail_step_model(step).model_validate(step).model_dump(mode="json")
    details["steps"] = [canonical]
    details["lesson_format"] = TUTORIAL_LESSON_FORMAT
    identity = validation_identity()
    details["_generation"]["validation_identity"] = identity
    details["_generation"]["lesson_validation"]["step_1"] = {
        **identity, "content_hash": digest(canonical),
        "package_hash": digest(short_package().model_dump(mode="json")),
    }
    assert current_package_approval(details)
    changed = copy.deepcopy(details)
    changed["steps"][0].pop("lesson_format")
    assert not current_package_approval(changed)
    changed = copy.deepcopy(details)
    changed["steps"][0]["lesson_content"] += " More unapproved text."
    assert not current_package_approval(changed)


@pytest.mark.asyncio
async def test_split_preflight_uses_short_profile_before_semantic_review(monkeypatch):
    from app.services.planning import package_preflight
    from tests.test_package_split_preflight import Harness

    from tests.text_audit_fixtures import argument_text_audits, public_notice_teaching_audits
    harness = Harness(semantic=[{"acceptable": True, "issues": [],
        "text_audits": argument_text_audits(short_package()),
        "teaching_case_audits": public_notice_teaching_audits(short_package())}])
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock(return_value=True))
    failures, response, _ = await package_preflight.review_package(
        short_package(), {"id": "step_1", "lesson_format": TUTORIAL_LESSON_FORMAT}, {},
        client_factory=harness.factory)
    assert failures == [] and not response.error
    assert len(harness.requests) == 1
    request = harness.requests[0][1]
    body = json.loads(request["user_prompt"])
    assert body["workload_contract"]["allowed_total_minutes_range"] == [5, 8]
    assert "tutorial_v1" in request["system_prompt"]


@pytest.mark.asyncio
async def test_final_review_receives_actual_short_reading_and_visual_requirements():
    from types import SimpleNamespace
    from app.services.planning.lesson_review import review_lesson
    from tests.test_lesson_review_contract import _review

    response = SimpleNamespace(error=None, data=_review(practice_minutes=3))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "concept " * 450, "lesson_format": TUTORIAL_LESSON_FORMAT},
        client_factory=lambda **kwargs: client, context={"lesson_package": short_package().review_context()})
    assert not failures and returned.error is None
    request = client.generate_json.call_args.kwargs
    body = json.loads(request["user_prompt"])
    assert body["lesson"]["reading_minutes"] == 3
    assert "workload_contract" not in body["context"]  # exercise time is the server's (2026-11-06)
    assert "native diagram or comparison" in request["system_prompt"]
    assert "private-answer and transfer-independence checks" in request["system_prompt"]


@pytest.mark.parametrize("allocation,reading,practice,words", [
    (5, 3, 2, [450, 600]), (6, 3, 3, [450, 600]),
    (7, 3, 4, [450, 600]), (8, 4, 4, [601, 800]),
])
def test_exact_mission_allocation_has_feasible_honest_reading_and_practice(allocation, reading, practice, words):
    activities = short_package().model_dump(mode="json")["workbook"]["activities"]
    plan = build_workload_planning_context(lesson_format=TUTORIAL_LESSON_FORMAT, allotted_lesson_minutes=allocation)
    ledger = build_workload_contract(activities, lesson_format=TUTORIAL_LESSON_FORMAT, allotted_lesson_minutes=allocation)
    assert plan["reading_word_range"] == words
    assert plan["reading_minutes_range"] == ledger["reading_minutes_range"] == [reading, reading]
    assert plan["supported_practice_minutes_range"] == ledger["feasible_practice_minutes_range"] == [practice, practice]
    assert ledger["allowed_total_minutes_range"] == [allocation, allocation]
    review = LessonReview(acceptable=True, issues=[], practice_minutes=practice, contains_calculations=False, calculations=[])
    assert _workload_error(review, short_package().review_context(), reading_minutes=reading,
        lesson_format=TUTORIAL_LESSON_FORMAT, allotted_lesson_minutes=allocation) is None
    # Since 2026-11-06 an off-allocation total no longer fails a tutorial either.
    assert _workload_error(review, short_package().review_context(), reading_minutes=reading + 1,
        lesson_format=TUTORIAL_LESSON_FORMAT, allotted_lesson_minutes=allocation) is None


@pytest.mark.parametrize("allocation", [True, 4, 9, "6"])
def test_allocation_is_validated_without_silent_conversion(allocation):
    with pytest.raises(ValueError, match="Invalid tutorial workload allocation"):
        build_workload_planning_context(lesson_format=TUTORIAL_LESSON_FORMAT, allotted_lesson_minutes=allocation)


@pytest.mark.asyncio
@pytest.mark.parametrize("mutated", [False, True])
async def test_approved_short_tutorial_persists_exact_private_workbook_without_overwriting_answers(mutated):
    from types import SimpleNamespace
    from app.services.llm.schemas import plan_detail_step_model
    from app.services.planning.lesson_package import persist_prepared_workbooks, provenance

    package = short_package()
    step = prior_approved_details()["steps"][0]
    step.update(lesson_format=TUTORIAL_LESSON_FORMAT,
                lesson_content=" ".join(step["lesson_content"].split()[:600]),
                reading_minutes=3, practice_minutes=3, estimate_minutes=6)
    canonical = plan_detail_step_model(step).model_validate(step).model_dump(mode="json")
    approval = provenance(canonical, package)
    if mutated:
        canonical["lesson_content"] += " Changed after review."
    item = SimpleNamespace(id="item", details_json={"lesson_format": TUTORIAL_LESSON_FORMAT,
        "steps": [canonical], "_generation": {"lesson_package_version": 1,
            "lesson_validation": {"step_1": approval}}})
    db = SimpleNamespace(execute=AsyncMock())
    await persist_prepared_workbooks(db, item, {"step_1": package}, user_id="learner")
    if mutated:
        db.execute.assert_not_awaited()
        return
    db.execute.assert_awaited_once()
    statement = db.execute.call_args.args[0]
    assert "ON CONFLICT ON CONSTRAINT uq_lesson_practice_version DO NOTHING" in str(statement)
    assert "DO UPDATE" not in str(statement)
    assert statement.compile().params["workbook_json"] == package.workbook.model_dump(mode="json")
    assert "worked_solution" not in json.dumps(item.details_json)


@pytest.mark.asyncio
@pytest.mark.parametrize("allocation,practice", [(6, 2), (6, 4), (7, 3), (6, 5)])
async def test_real_review_never_rejects_a_tutorial_for_its_exercise_time(monkeypatch, allocation, practice):
    # Owner decision (2026-11-06): neither an allocation mismatch nor an estimate outside the
    # package range is a package defect or missing evidence for a tutorial any more.
    from types import SimpleNamespace
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_review import review_lesson
    from tests.test_lesson_review_contract import _review

    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=_review(practice_minutes=practice))))
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock(return_value=True))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "concept " * 450, "lesson_format": TUTORIAL_LESSON_FORMAT},
        client_factory=lambda **kwargs: client,
        context={"lesson_package": short_package().review_context(), "allotted_lesson_minutes": allocation})
    client.generate_json.assert_awaited_once()  # no evidence patch for the estimate
    assert failures == [] and returned.error is None
    assert returned.data["acceptable"] is True and not returned.data.get("package_issues")


DEPLOYED_RECOVERY11_IDENTITY = {'review_version': 23, 'package_version': 1, 'capability_hash': '1815a97ad0c7246f737c493fbec7b9217c6a5dd6a7d96cacd93c0c34b3afe48f', 'prompt_hash': 'fc899f550b96b760a700da1f5bac50b0118b87b2e615c8106a6b0e4d47ef69eb', 'generation_contract_hash': '80f26df4ca315e830f7ef268eb3410bb44a3130ee3bed9f200526ae7ef626db0', 'schema_hash': '6c9911659a81cbd8598269be5181940c1bd27d828843305fabac7de560b91a01'}

DEPLOYED_RECOVERY12_IDENTITY = {'review_version': 23, 'package_version': 1, 'capability_hash': '1815a97ad0c7246f737c493fbec7b9217c6a5dd6a7d96cacd93c0c34b3afe48f', 'prompt_hash': 'fc899f550b96b760a700da1f5bac50b0118b87b2e615c8106a6b0e4d47ef69eb', 'generation_contract_hash': 'a7acf3cfd9e4165dd6b8713fe0ab75d3b5416a847c7465866f42762b2f32bfa2', 'schema_hash': '6c9911659a81cbd8598269be5181940c1bd27d828843305fabac7de560b91a01'}

@pytest.mark.parametrize("identity_source", [DEPLOYED_RECOVERY11_IDENTITY, DEPLOYED_RECOVERY12_IDENTITY])
@pytest.mark.parametrize("mutation", [None, "content", "identity", "approval", "missing_package"])
def test_exact_deployed_tutorial_remains_readable_but_never_new_approval(mutation, identity_source):
    from app.services.llm.schemas import PlanTutorialStepOutput
    from app.services.planning.lesson_package import provenance
    from tests.test_short_tutorial_pipeline import complete_step
    step = complete_step()
    step = PlanTutorialStepOutput.model_validate(step).model_dump(mode="json")
    identity = copy.deepcopy(identity_source)
    assert digest(identity) in {"2636602586868d76495ab24a54220f85ee9a117b7adb9e7452829d7c1dc31d23", "2cb574206bc24b0e8578956fa60753c41828220a79baca9cb6a2cd1ca30c8700"}
    approval = {**identity, "content_hash": digest(step), "package_hash": digest(short_package().model_dump(mode="json"))}
    details = {"lesson_format": "tutorial_v1", "steps": [step], "_generation": {
        "lesson_package_version": 1, "validation_identity": identity, "lesson_validation": {step["id"]: approval}}}
    if mutation == "content": step["lesson_content"] += " Changed prose."
    elif mutation == "identity": identity["generation_contract_hash"] = "unknown"
    elif mutation == "approval": approval["prompt_hash"] = "different"
    elif mutation == "missing_package": approval.pop("package_hash")
    assert current_package_approval(details, allow_compatible_read=True) is (mutation is None)
    assert not current_package_approval(details)


def test_new_tutorial_activities_get_server_time_not_the_models_estimate():
    from app.services.planning.activity_draft import TUTORIAL_ACTIVITY_MINUTES, with_tutorial_timing

    draft = {"id": "guided", "minutes_min": 6, "minutes_max": 9, "fields": []}
    assert with_tutorial_timing(draft) == {**draft, "minutes_min": 1, "minutes_max": 2}
    assert draft["minutes_min"] == 6  # no mutation
    assert TUTORIAL_ACTIVITY_MINUTES == {"minutes_min": 1, "minutes_max": 2}
    # Two activities always make the tutorial's 2–4 minute practice budget.
    assert not workload_feasibility_issues([{**TUTORIAL_ACTIVITY_MINUTES}] * 2, lesson_format=TUTORIAL_LESSON_FORMAT)


def test_tutorial_reviewers_judge_correctness_not_exercise_time():
    from app.services.llm.prompt_loader import load_and_render
    from app.services.planning.package_preflight import _SEMANTIC_PROMPT, _TUTORIAL_SEMANTIC_PROMPT
    from app.services.planning.tutorial_rules import tutorial_review_rules, tutorial_rule

    assert tutorial_rule("R-TIME") not in tutorial_review_rules()
    assert "[R-TIME]" in load_and_render("tutorial_activity_generate.txt", {})  # generators still size work
    for timing in ("timing ledger", "2–4 minutes", "5–8 minute", "Honest workload"):
        assert timing not in _TUTORIAL_SEMANTIC_PROMPT and timing in _SEMANTIC_PROMPT
    assert "judge whether each exercise is correct and can be completed from its inputs" in _TUTORIAL_SEMANTIC_PROMPT


def test_a_tutorial_timing_finding_is_advisory_but_a_legacy_one_still_blocks():
    from app.services.planning.package_preflight import _server_owned_workload_as_advisory

    finding = {"severity": "blocking", "target": "practice.transfer",
               "description": "The transfer needs about 6 practice minutes, above the 2–4 minute workload."}
    data = {"acceptable": False, "issues": [finding]}
    tutorial = _server_owned_workload_as_advisory(data, {"feasible_practice_minutes_range": None}, tutorial=True)
    assert tutorial["issues"][0]["severity"] == "advisory" and data["issues"][0]["severity"] == "blocking"
    legacy = _server_owned_workload_as_advisory(data, {"feasible_practice_minutes_range": [20, 40]})
    assert legacy["issues"][0]["severity"] == "blocking"  # activity-targeted, legacy: still blocks
    content = {**finding, "description": "The transfer's answer key multiplies base by the slanted side."}
    kept = _server_owned_workload_as_advisory({"acceptable": False, "issues": [content]}, {}, tutorial=True)
    assert kept["issues"][0]["severity"] == "blocking"  # a correctness finding is untouched


# Pilot 2026-11-07 (gpt-6-luna): both "Exercise contract review failed" endings
# were the final lesson reviewer judging time, which only the exercise reviewer
# had stopped doing.
LUNA_TIMING_FINDINGS = (
    "This tutorial’s actual practice is specified as 6–9 minutes across its two activities, while "
    "tutorial_v1 permits 2–4 minutes of practice and 5–8 minutes total including the 3-minute reading.",
    "The practice activity ranges allow at most 2 minutes for the calculation, explanation of the "
    "diagnostic error, unit reasoning, checking, and revision. That is not a realistic estimate for all required work.",
)


@pytest.mark.asyncio
async def test_the_final_tutorial_reviewer_gets_no_timing_rules_or_ledger():
    from types import SimpleNamespace
    from app.services.planning.lesson_review import _TUTORIAL_TIME_RULE, review_lesson
    from tests.test_lesson_review_contract import _review

    prompts = {}
    for lesson_format in (TUTORIAL_LESSON_FORMAT, None):
        client = SimpleNamespace(generate_json=AsyncMock(
            return_value=SimpleNamespace(error=None, data=_review(practice_minutes=3))))
        await review_lesson(
            {"lesson_content": "concept " * 450, "lesson_format": lesson_format},
            client_factory=lambda **kwargs: client,
            context={"lesson_package": short_package().review_context(), "allotted_lesson_minutes": 7,
                     "activity_timing_changes": [{"activity_id": "guided"}]})
        prompts[lesson_format] = client.generate_json.call_args.kwargs
    tutorial, legacy = prompts[TUTORIAL_LESSON_FORMAT], prompts[None]
    for timing in ("Honest workload", "realistic workload", "unrealistic activity timing",
                   "minutes_min..minutes_max", "2–4 minutes of actual practice", "allotted_lesson_minutes"):
        assert timing not in tutorial["system_prompt"]
    assert _TUTORIAL_TIME_RULE in tutorial["system_prompt"]
    assert "Honest workload" in legacy["system_prompt"] and _TUTORIAL_TIME_RULE not in legacy["system_prompt"]
    context = json.loads(tutorial["user_prompt"])["context"]
    assert not {"workload_contract", "allotted_lesson_minutes", "activity_timing_changes"} & context.keys()


@pytest.mark.asyncio
@pytest.mark.parametrize("finding", LUNA_TIMING_FINDINGS)
async def test_a_final_reviewer_timing_finding_never_fails_a_tutorial(monkeypatch, finding):
    from types import SimpleNamespace
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_review import review_lesson
    from tests.test_lesson_review_contract import _review

    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock(return_value=True))
    verdict = _review(acceptable=False, practice_minutes=6, package_issues=[finding], package_issue_targets=["package"])
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=verdict)))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "concept " * 450, "lesson_format": TUTORIAL_LESSON_FORMAT},
        client_factory=lambda **kwargs: client, context={"lesson_package": short_package().review_context()})
    assert failures == [] and returned.data["acceptable"] is True
    assert finding in returned.data["advisories"] and verdict["package_issues"] == [finding]  # no mutation


def test_only_timing_findings_become_advisory():
    from app.services.planning.lesson_review import _tutorial_timing_as_advisory

    content = ("The Core Framework gives away the central risk the independent transfer asks learners to identify.",
               "The exercise says the train takes 40 minutes, but its answer key uses 50 minutes.")
    data = {"issues": [*content, LUNA_TIMING_FINDINGS[1]], "package_issues": [LUNA_TIMING_FINDINGS[0]],
            "package_issue_targets": ["package"]}
    marked = _tutorial_timing_as_advisory(data)
    assert marked["issue_severities"] == ["blocking", "blocking", "advisory"]
    assert marked["package_issue_severities"] == ["advisory"]
    assert _tutorial_timing_as_advisory({"issues": list(content)}) == {"issues": list(content)}
    misaligned = {"package_issues": [LUNA_TIMING_FINDINGS[0]], "package_issue_targets": ["package", "x"]}
    assert _tutorial_timing_as_advisory(misaligned) is misaligned  # left for strict parsing


def test_a_scoped_tutorial_repair_keeps_the_server_minutes():
    from app.services.planning.lesson_package import _replace_public_activity

    package = short_package()
    original = package.workbook.activities[0]
    replacement = original.model_copy(update={"minutes_min": 4, "minutes_max": 6, "title": original.title + " (revised)"})
    kept = _replace_public_activity(package, {original.id: None}, replacement, keep_minutes=True)
    repaired = next(activity for activity in kept.workbook.activities if activity.id == original.id)
    assert (repaired.minutes_min, repaired.minutes_max, repaired.title) == (1, 2, original.title + " (revised)")
    legacy = _replace_public_activity(package, {original.id: None}, replacement)
    assert next(a for a in legacy.workbook.activities if a.id == original.id).minutes_max == 6
