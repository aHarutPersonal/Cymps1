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


def test_short_profile_does_not_clamp_a_long_exercise_to_its_budget():
    activities = [{"id": "guided", "minutes_min": 8, "minutes_max": 10},
                  {"id": "transfer", "minutes_min": 8, "minutes_max": 10}]
    before = copy.deepcopy(activities)
    issues = workload_feasibility_issues(activities, lesson_format=TUTORIAL_LESSON_FORMAT)
    assert issues and "5–8" in issues[0]
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


@pytest.mark.parametrize("practice,reading,accepted", [(2, 3, True), (4, 4, True), (1, 3, False), (5, 3, False)])
def test_final_review_preserves_honest_workload_and_short_profile_bounds(practice, reading, accepted):
    review = LessonReview(acceptable=True, issues=[], practice_minutes=practice, contains_calculations=False, calculations=[])
    error = _workload_error(review, short_package().review_context(), reading_minutes=reading,
                            lesson_format=TUTORIAL_LESSON_FORMAT)
    assert (error is None) is accepted
    if accepted:
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

    harness = Harness()
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
    assert body["context"]["workload_contract"]["allowed_total_minutes_range"] == [5, 8]
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
    assert _workload_error(review, short_package().review_context(), reading_minutes=reading + 1,
        lesson_format=TUTORIAL_LESSON_FORMAT, allotted_lesson_minutes=allocation)


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
@pytest.mark.parametrize("allocation,practice", [(6, 2), (6, 4), (7, 3)])
async def test_real_review_classifies_honest_allocation_mismatch_as_repairable_package_scope(allocation, practice):
    from types import SimpleNamespace
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_review import review_lesson
    from tests.test_lesson_review_contract import _review

    response = LLMResponse(data=_review(practice_minutes=practice),
                           effective_parameters={"provider_option": "retained"})
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "concept " * 450, "lesson_format": TUTORIAL_LESSON_FORMAT},
        client_factory=lambda **kwargs: client,
        context={"lesson_package": short_package().review_context(), "allotted_lesson_minutes": allocation})
    # A verified estimate of actual work is a scope finding, not unavailable
    # evidence or permission to re-ask the reviewer for a more convenient number.
    client.generate_json.assert_awaited_once()
    assert returned.error is None
    assert returned.data["acceptable"] is False
    assert failures == returned.data["package_issues"]
    assert returned.data["package_issue_targets"] == ["package"]
    assert returned.effective_parameters == {
        "provider_option": "retained", "validated_repair_targets": ["package"]}
    assert returned.data["practice_minutes"] == practice
    assert "do not pad or relabel" in failures[0]


@pytest.mark.asyncio
async def test_real_review_out_of_package_estimate_stays_unavailable_evidence(monkeypatch):
    from types import SimpleNamespace
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_review import review_lesson
    from tests.test_lesson_review_contract import _review

    first = LLMResponse(data=_review(practice_minutes=5))  # Package supports only2–4.
    patch = LLMResponse(data={"practice_minutes": 5})
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[first, patch]))
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock(return_value=True))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "concept " * 450, "lesson_format": TUTORIAL_LESSON_FORMAT},
        client_factory=lambda **kwargs: client,
        context={"lesson_package": short_package().review_context(), "allotted_lesson_minutes": 6})
    assert client.generate_json.await_count == 2
    assert failures and returned.error == "Lesson review evidence patch validation failed"
    assert not returned.data["package_issues"]
    assert "validated_repair_targets" not in returned.effective_parameters


@pytest.mark.asyncio
async def test_corrected_review_evidence_can_reveal_honest_allocation_scope(monkeypatch):
    from types import SimpleNamespace
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_review import review_lesson
    from tests.test_lesson_review_contract import _review

    first = LLMResponse(data=_review(practice_minutes=5))
    patch = LLMResponse(data={"practice_minutes": 2})  # Verified but too little work for allocated6.
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[first, patch]))
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock(return_value=True))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "concept " * 450, "lesson_format": TUTORIAL_LESSON_FORMAT},
        client_factory=lambda **kwargs: client,
        context={"lesson_package": short_package().review_context(), "allotted_lesson_minutes": 6})
    assert client.generate_json.await_count == 2
    assert returned.error is None and failures == returned.data["package_issues"]
    assert returned.data["practice_minutes"] == 2
    assert returned.data["acceptable"] is False
    assert returned.effective_parameters["validated_repair_targets"] == ["package"]


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
