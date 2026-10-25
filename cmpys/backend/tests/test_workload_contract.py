"""Timing consistency is checked independently from pedagogical realism."""
import copy
import json

import pytest

from app.services.planning.workload_contract import (
    activity_timing_changes, build_workload_contract, build_workload_planning_context,
    workload_feasibility_issues,
)


def activities():
    return [
        {"id": "guided", "minutes_min": 12, "minutes_max": 17},
        {"id": "transfer", "minutes_min": 12, "minutes_max": 18},
    ]


def test_ledger_counts_activities_once_and_exposes_no_private_contract_fields():
    source = activities()
    source[0].update(worked_solution="PRIVATE_SOLUTION", hint="PRIVATE_HINT",
                     data=[{"value": 999}], fields=[{"expression": "PRIVATE_FORMULA"}])
    before = copy.deepcopy(source)
    contract = build_workload_contract(source)
    assert contract["activities"] == activities_as_ledger()
    assert contract["practice_minutes_range"] == [24, 35]
    assert contract["reading_minutes_range"] == [10, 21]
    assert contract["reading_basis"] == "accepted_word_bounds"
    assert contract["feasible_practice_minutes_range"] == [30, 35]
    assert "PRIVATE" not in json.dumps(contract)
    assert "999" not in json.dumps(contract)
    assert source == before


@pytest.mark.parametrize("target,reference", [(None, 30), (26, 30), (40, 40), (200, 159)])
def test_planning_uses_review_bounds_without_changing_actual_activity_estimates(target, reference):
    source = activities()
    before = copy.deepcopy(source)
    plan = build_workload_planning_context(target_practice_minutes=target)
    ledger = build_workload_contract(source)
    assert plan["reading_minutes_range"] == ledger["reading_minutes_range"]
    assert plan["allowed_total_minutes_range"] == ledger["allowed_total_minutes_range"]
    assert plan["supported_practice_minutes_range"] == [30, 159]
    assert plan["requested_practice_minutes"] == target
    assert plan["planning_practice_minutes"] == reference
    assert ledger["practice_minutes_range"] == [24, 35]
    assert source == before
    assert "ALL activities" in plan["counting_rule"]
    assert "never permission to inflate" in plan["scope_rule"]


def test_planning_reading_bounds_follow_configured_word_contract(monkeypatch):
    from app.services import content_quality

    monkeypatch.setattr(content_quality, "MIN_PLAN_DETAIL_LESSON_WORDS", 2400)
    monkeypatch.setattr(content_quality, "MAX_PLAN_DETAIL_LESSON_WORDS", 2800)
    plan = build_workload_planning_context(target_practice_minutes=26)
    ledger = build_workload_contract(activities())
    assert plan["reading_minutes_range"] == ledger["reading_minutes_range"] == [12, 14]
    assert plan["supported_practice_minutes_range"] == [28, 166]
    assert plan["planning_practice_minutes"] == 28


@pytest.mark.parametrize("target", [True, 0, -1, 30.5, "30"])
def test_planning_rejects_invalid_targets_without_silent_coercion(target):
    with pytest.raises(ValueError, match="Invalid workload planning target"):
        build_workload_planning_context(target_practice_minutes=target)


def public_workbook():
    from app.services.planning.lesson_package import LessonPackage
    from tests.lesson_package_fixtures import package_payload

    return LessonPackage.model_validate(package_payload()).writer_context()["practice"]


def test_timing_comparison_reports_only_changed_same_id_ranges_without_private_or_public_prose():
    previous = public_workbook()
    current = copy.deepcopy(previous)
    current["activities"].reverse()
    revised = next(a for a in current["activities"] if a["id"] == "guided")
    old = next(a for a in previous["activities"] if a["id"] == "guided")
    revised["minutes_min"] += 2
    revised["minutes_max"] += 2
    revised["title"] = "Renamed title does not add work"
    before = copy.deepcopy((previous, current))
    comparison = activity_timing_changes(previous, current)
    assert comparison == [{"activity_id": "guided",
                           "previous_minutes": [old["minutes_min"], old["minutes_max"]],
                           "revised_minutes": [revised["minutes_min"], revised["minutes_max"]],
                           "unchanged_task": True}]
    assert (previous, current) == before
    assert old["instructions"] not in json.dumps(comparison)
    assert old["fields"][0]["label"] not in json.dumps(comparison)


@pytest.mark.parametrize("component", ["instructions", "data", "fields", "diagram", "kind"])
def test_timing_comparison_preserves_every_task_component_for_semantic_review(component):
    previous = public_workbook()
    current = copy.deepcopy(previous)
    activity = current["activities"][0]
    activity["minutes_max"] += 1
    if component == "instructions":
        activity[component] += " Explain an alternative approach."
    elif component == "data":
        activity[component].append({"id": "new_fact", "label": "A new input", "value": 15, "unit": "m"})
    elif component == "fields":
        activity[component][0]["label"] += " Explain the alternative too."
    elif component == "diagram":
        activity[component] = {"type": "triangle", "vertices": []}
    else:
        activity[component] = "transfer"
    assert activity_timing_changes(previous, current)[0]["unchanged_task"] is False


def test_timing_comparison_does_not_treat_new_tasks_or_unchanged_timing_as_inflation():
    previous = public_workbook()
    current = copy.deepcopy(previous)
    current["activities"][0]["instructions"] += " A substantial additional demand."
    new_task = copy.deepcopy(current["activities"][-1])
    new_task["id"] = "new_transfer"
    current["activities"].append(new_task)
    assert activity_timing_changes(previous, current) == []


def test_timing_comparison_reports_decreased_range_without_judging_or_mutating_it():
    previous = public_workbook()
    current = copy.deepcopy(previous)
    current["activities"][0]["minutes_min"] -= 1
    comparison = activity_timing_changes(previous, current)
    assert comparison[0]["unchanged_task"] is True
    assert comparison[0]["revised_minutes"][0] == comparison[0]["previous_minutes"][0] - 1


@pytest.mark.parametrize("defect", ["duplicate", "missing_content", "invalid_timing"])
def test_timing_comparison_rejects_ambiguous_or_incomplete_inputs(defect):
    previous = public_workbook()
    current = copy.deepcopy(previous)
    if defect == "duplicate":
        current["activities"][1]["id"] = current["activities"][0]["id"]
    elif defect == "missing_content":
        current["activities"][0].pop("instructions")
    else:
        current["activities"][0]["minutes_min"] = True
    with pytest.raises(ValueError):
        activity_timing_changes(previous, current)


def activities_as_ledger():
    return [{"activity_id": a["id"], "minutes_min": a["minutes_min"], "minutes_max": a["minutes_max"]}
            for a in activities()]


def test_actual_reading_changes_feasible_interval_without_clamping_package():
    contract = build_workload_contract(activities(), reading_minutes=10)
    assert contract["practice_minutes_range"] == [24, 35]
    assert contract["feasible_practice_minutes_range"] == [30, 35]
    assert contract["reading_basis"] == "actual_word_count"
    assert not workload_feasibility_issues(activities(), reading_minutes=10)


def test_impossible_short_package_is_rejected_before_prose():
    source = activities()
    for activity in source:
        activity.update(minutes_min=5, minutes_max=10)
    errors = workload_feasibility_issues(source)
    assert errors and "cannot meet" in errors[0]
    assert build_workload_contract(source)["feasible_practice_minutes_range"] is None
    assert not workload_feasibility_issues(source, minimum_total_minutes=30)


def test_short_accepted_prose_is_accounted_for_before_paid_writing():
    source = activities()
    for activity in source:
        activity.update(minutes_min=12, minutes_max=13)
    # The old optimistic plan passed because 26 + 14 reaches40, then paid
    # writing/review failed when valid1900-word prose supplied only10minutes.
    assert workload_feasibility_issues(source)
    assert workload_feasibility_issues(source, reading_minutes=10)


def test_every_planned_feasible_estimate_fits_every_accepted_reading_time():
    contract = build_workload_contract(activities())
    low, high = contract["feasible_practice_minutes_range"]
    for practice in range(low, high + 1):
        for reading in range(*[contract["reading_minutes_range"][0], contract["reading_minutes_range"][1] + 1]):
            assert 40 <= practice + reading <= 180


def test_longer_supported_work_is_not_arbitrarily_capped_at_sixty():
    source = activities()
    for activity in source:
        activity.update(minutes_min=40, minutes_max=45)
    assert not workload_feasibility_issues(source)
    assert workload_feasibility_issues(source, maximum_total_minutes=60)


@pytest.mark.parametrize("defect", ["duplicate", "missing", "boolean", "reversed", "not_mapping"])
def test_malformed_timing_fails_without_coercion_or_private_input_echo(defect):
    source = activities()
    if defect == "duplicate":
        source[1]["id"] = source[0]["id"]
    elif defect == "missing":
        source[0].pop("minutes_min")
    elif defect == "boolean":
        source[0]["minutes_min"] = True
    elif defect == "reversed":
        source[0]["minutes_min"] = 30
    else:
        source[0] = "PRIVATE_BROKEN_INPUT"
    errors = workload_feasibility_issues(source)
    assert errors and "PRIVATE" not in " ".join(errors)
