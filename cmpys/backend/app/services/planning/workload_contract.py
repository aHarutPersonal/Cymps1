"""One timing ledger shared by package preflight, writing and final review.

Feasibility is an arithmetic prerequisite, never proof that the proposed work
really takes this long. Independent semantic review still assesses realism.
"""
from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from typing import Any

from app.services.content_quality import (
    TUTORIAL_LESSON_FORMAT, plan_detail_min_words, plan_detail_max_words,
    plan_detail_reading_minutes,
)

MINIMUM_TOTAL_MINUTES = 40
MAXIMUM_TOTAL_MINUTES = 180


def _reading_range(reading_minutes: int | None, lesson_format: str | None = None,
                   allotted_lesson_minutes: int | None = None) -> list[int]:
    if reading_minutes is None and allotted_lesson_minutes is not None:
        # Exact tutorial allocations have an explicit prose scope before writing:
        # 450–600 words reserve three minutes; 601–800 reserve four.
        reading = 4 if allotted_lesson_minutes == 8 else 3
        return [reading, reading]
    profile = {"lesson_format": lesson_format}
    return ([plan_detail_reading_minutes(plan_detail_min_words(profile), lesson_format),
             plan_detail_reading_minutes(plan_detail_max_words(profile), lesson_format)]
            if reading_minutes is None else [reading_minutes, reading_minutes])


def _total_bounds(lesson_format: str | None, allotted_lesson_minutes: int | None = None) -> tuple[int, int]:
    if allotted_lesson_minutes is not None:
        if (lesson_format != TUTORIAL_LESSON_FORMAT
                or type(allotted_lesson_minutes) is not int or not 5 <= allotted_lesson_minutes <= 8):
            raise ValueError("Invalid tutorial workload allocation")
        return allotted_lesson_minutes, allotted_lesson_minutes
    return (5, 8) if lesson_format == TUTORIAL_LESSON_FORMAT else (MINIMUM_TOTAL_MINUTES, MAXIMUM_TOTAL_MINUTES)


def build_workload_planning_context(*, target_practice_minutes: int | None = None,
                                    lesson_format: str | None = None,
                                    allotted_lesson_minutes: int | None = None) -> dict[str, Any]:
    """Give planning the same bounds as review, before activities exist.

    A target is a scope-planning reference, never a prediction of actual work.
    Adjusting that reference to supported bounds must not alter an activity's
    eventual honest estimate, which independent review still verifies.
    """
    if target_practice_minutes is not None and (
            type(target_practice_minutes) is not int or target_practice_minutes < 1):
        raise ValueError("Invalid workload planning target")
    minimum, maximum = _total_bounds(lesson_format, allotted_lesson_minutes)
    reading = _reading_range(None, lesson_format, allotted_lesson_minutes)
    supported = [max(1, minimum - reading[0]), maximum - reading[1]]
    target = (supported[0] if target_practice_minutes is None else
              max(supported[0], min(supported[1], target_practice_minutes)))
    return {
        **({"reading_word_range": [601, 800] if allotted_lesson_minutes == 8 else [450, 600]}
           if allotted_lesson_minutes is not None else {}),
        "reading_minutes_range": reading,
        "reading_basis": "accepted_word_bounds",
        "allowed_total_minutes_range": [minimum, maximum],
        "supported_practice_minutes_range": supported,
        "requested_practice_minutes": target_practice_minutes,
        "planning_practice_minutes": target,
        "counting_rule": "The practice target is shared across ALL activities, including doing, explaining, checking and one revision; reading is separate.",
        "scope_rule": "Plan enough substantive work to fit the supported total range. Targets are planning references, never permission to inflate honest activity estimates.",
    }


def activity_timing_changes(previous_public_workbook: dict, current_public_workbook: dict) -> list[dict]:
    """Describe changed estimates without approving or altering either task.

    Callers supply public workbooks from validated packages. Equality is exact,
    excluding titles and timing; even a real content change still needs semantic
    review to establish that it adds work. No task prose or answer data is emitted.
    """
    if not isinstance(previous_public_workbook, dict) or not isinstance(current_public_workbook, dict):
        raise ValueError("Invalid public workload comparison")
    previous = previous_public_workbook.get("activities")
    current = current_public_workbook.get("activities")
    # Reuse ID, uniqueness and timing validation; do not silently match corrupt
    # or ambiguous IDs. This does not decide workload feasibility or realism.
    build_workload_contract(previous)
    build_workload_contract(current)
    task_keys = ("kind", "instructions", "data", "fields", "diagram")
    for activity in [*previous, *current]:
        if not {"kind", "instructions", "data", "fields"} <= activity.keys():
            raise ValueError("Incomplete public task for workload comparison")
    old_by_id = {activity["id"]: activity for activity in previous}
    changes = []
    for activity in current:
        old = old_by_id.get(activity["id"])
        if old is None:
            continue
        before = [old["minutes_min"], old["minutes_max"]]
        after = [activity["minutes_min"], activity["minutes_max"]]
        if before != after:
            changes.append({"activity_id": activity["id"], "previous_minutes": before,
                            "revised_minutes": after,
                            "unchanged_task": all(old.get(key) == activity.get(key) for key in task_keys)})
    return changes


def build_workload_contract(
    activities: Sequence[Mapping[str, Any]], *, reading_minutes: int | None = None,
    minimum_total_minutes: int | None = None, maximum_total_minutes: int | None = None,
    lesson_format: str | None = None,
    allotted_lesson_minutes: int | None = None,
) -> dict[str, Any]:
    """Return only public activity IDs and timing, never private answer data.

    Before prose exists, use the accepted word-count bounds rather than an
    optimistic writing target. A package must leave a feasible practice range
    for any accepted prose length. After drafting, use actual reading time.
    Configured total bounds are constraints, not a workload estimate.
    """
    profile_minimum, profile_maximum = _total_bounds(lesson_format, allotted_lesson_minutes)
    minimum_total_minutes = profile_minimum if minimum_total_minutes is None else minimum_total_minutes
    maximum_total_minutes = profile_maximum if maximum_total_minutes is None else maximum_total_minutes
    if (not isinstance(activities, (list, tuple)) or not activities
            or type(minimum_total_minutes) is not int or minimum_total_minutes < 1
            or type(maximum_total_minutes) is not int
            or maximum_total_minutes < minimum_total_minutes
            or (reading_minutes is not None
                and (type(reading_minutes) is not int or reading_minutes < 1))):
        raise ValueError("Invalid workload contract inputs")
    ledger = []
    seen = set()
    for activity in activities:
        if not isinstance(activity, Mapping):
            raise ValueError("Invalid workload activity timing")
        activity_id = activity.get("id")
        lower, upper = activity.get("minutes_min"), activity.get("minutes_max")
        if (not isinstance(activity_id, str)
                or re.fullmatch(r"[a-z][a-z0-9_]{0,39}", activity_id) is None
                or activity_id in seen or type(lower) is not int or type(upper) is not int
                or not 1 <= lower <= upper <= 60):
            raise ValueError("Invalid workload activity timing")
        seen.add(activity_id)
        ledger.append({"activity_id": activity_id, "minutes_min": lower, "minutes_max": upper})
    reading = _reading_range(reading_minutes, lesson_format, allotted_lesson_minutes)
    lower = sum(activity["minutes_min"] for activity in ledger)
    upper = sum(activity["minutes_max"] for activity in ledger)
    # Plan against both extremes. Using the longest reading time to meet the
    # minimum silently approved packages that shorter valid prose cannot use.
    feasible = [max(lower, minimum_total_minutes - reading[0]),
                min(upper, maximum_total_minutes - reading[1])]
    if lesson_format == TUTORIAL_LESSON_FORMAT:
        feasible = [max(2, feasible[0]), min(4, feasible[1])]
    return {
        **({"allowed_practice_minutes_range": [2, 4]} if lesson_format == TUTORIAL_LESSON_FORMAT else {}),
        "activities": ledger,
        "reading_minutes_range": reading,
        "reading_basis": "accepted_word_bounds" if reading_minutes is None else "actual_word_count",
        "practice_minutes_range": [lower, upper],
        "total_supported_minutes_range": [lower + reading[0], upper + reading[1]],
        "allowed_total_minutes_range": [minimum_total_minutes, maximum_total_minutes],
        "feasible_practice_minutes_range": feasible if feasible[0] <= feasible[1] else None,
        "counting_rules": [
            "Count each activity once, including doing, explaining, checking and revision.",
            "Practice phases and substeps describe parts of these activities; they add no separate time.",
            "Map each phase to its exact activity ID and existing answer fields; add no required tasks.",
            "Reading and worked examples belong to reading time, not an extra practice activity.",
            "Activity ranges are estimates to assess honestly, not durations to force or inflate.",
            "Reject an unrealistic range with its activity ID; never clamp an honest estimate to fit.",
        ],
    }


def workload_feasibility_issues(
    activities: Sequence[Mapping[str, Any]], *, reading_minutes: int | None = None,
    minimum_total_minutes: int | None = None, maximum_total_minutes: int | None = None,
    lesson_format: str | None = None,
    allotted_lesson_minutes: int | None = None,
) -> list[str]:
    """Reject impossible supported totals before spending on lesson prose."""
    try:
        contract = build_workload_contract(
            activities, reading_minutes=reading_minutes,
            minimum_total_minutes=minimum_total_minutes,
            maximum_total_minutes=maximum_total_minutes,
            lesson_format=lesson_format,
            allotted_lesson_minutes=allotted_lesson_minutes,
        )
    except ValueError as exc:
        return [str(exc)]
    if contract["feasible_practice_minutes_range"] is not None:
        return []
    low, high = contract["total_supported_minutes_range"]
    minimum_total_minutes, maximum_total_minutes = contract["allowed_total_minutes_range"]
    return [
        f"Prepared activities support {low}–{high} total minutes including reading; "
        f"this cannot meet the configured {minimum_total_minutes}–{maximum_total_minutes} minute range "
        "across the accepted reading-time range. "
        "Revise the actual activity scope before writing prose; do not inflate timing labels."
    ]
