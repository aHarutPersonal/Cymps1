"""Weekly capacity in minutes and the planner's mission/rhythm split.

Intake v3 records 1-15 focused hours a week in half-hour steps and stores
them as minutes (60-900, multiples of 30). Legacy 8-key intakes keep their
3-60 whole-hour answers, stored as ``hours * 60``.

``weekly_hours`` remains an integer column for legacy readers and old app
builds; it is always written as ``ceil(weekly_minutes / 60)``. Every capacity
computation reads minutes, falling back to ``weekly_hours * 60`` for rows
written before the ``weekly_minutes`` column existed.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

MIN_WEEKLY_MINUTES = 60
MAX_WEEKLY_MINUTES = 900
WEEKLY_MINUTES_STEP = 30
# Below three hours a week the plan is one short mission plus a short rhythm.
LOW_CAPACITY_MINUTES = 180
# Below six hours a week the plan has exactly one mission.
MULTI_MISSION_MINUTES = 360
MIN_RHYTHM_MINUTES = 15
# A whole-hour mission block keeps the historical 2-8 hour range.
MIN_MISSION_MINUTES = 120
MAX_MISSION_MINUTES = 480
DEFAULT_WEEKLY_MINUTES = 600


@dataclass(frozen=True)
class CapacitySplit:
    """Minutes for the daily rhythm and, in total, for the weekly missions."""

    rhythm_minutes: int
    mission_minutes: int
    mission_count: int


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def capacity_split(weekly_minutes: int) -> CapacitySplit:
    """Split a weekly capacity into rhythm minutes and mission minutes.

    At 180 minutes or more this is the historical integer-hour rule of the
    deterministic planner, applied to minutes: one hour of daily rhythm,
    one mission under six hours, otherwise 2-3 missions of at most 8 hours
    each, with any remainder going to the rhythm. For whole hours it
    reproduces that rule exactly (times 60).

    Below 180 minutes there is exactly one mission. The rhythm takes a
    quarter of the week rounded down to 15 minutes (at least 15) and the
    mission takes the rest, so 60 -> (15, 45, 1) and 120 -> (30, 90, 1).
    """
    if not _is_int(weekly_minutes):
        raise ValueError("Weekly capacity must be a whole number of minutes")
    if weekly_minutes < MIN_WEEKLY_MINUTES:
        raise ValueError("Weekly capacity must be at least 60 minutes")
    if weekly_minutes < LOW_CAPACITY_MINUTES:
        rhythm = max(MIN_RHYTHM_MINUTES, (weekly_minutes // 4) // 15 * 15)
        return CapacitySplit(rhythm, weekly_minutes - rhythm, 1)
    available = weekly_minutes - 60
    count = (
        1
        if weekly_minutes < MULTI_MISSION_MINUTES
        else min(3, max(2, (available + 420) // 480))
    )
    mission = min(available, count * MAX_MISSION_MINUTES)
    return CapacitySplit(weekly_minutes - mission, mission, count)


def mission_allocations(split: CapacitySplit) -> list[int]:
    """Distribute the mission minutes over the missions, largest first.

    Whole-hour budgets are shared in whole hours, as before; otherwise in
    half hours, or quarter hours for an odd short week.
    """
    unit = next(
        size for size in (60, 30, 15, 1) if split.mission_minutes % size == 0
    )
    base, remainder = divmod(split.mission_minutes // unit, split.mission_count)
    return [
        (base + (1 if index < remainder else 0)) * unit
        for index in range(split.mission_count)
    ]


def legacy_weekly_hours(weekly_minutes: int) -> int:
    """The integer ``weekly_hours`` written for legacy readers."""
    return math.ceil(int(weekly_minutes) / 60)


def hours_value(minutes: int) -> int | float:
    """Minutes as hours: an ``int`` for whole hours, otherwise a ``float``."""
    return minutes // 60 if minutes % 60 == 0 else minutes / 60


def format_hours(minutes: int) -> str:
    """``270`` -> ``"4.5"``, ``60`` -> ``"1"``, ``45`` -> ``"0.75"``."""
    return f"{minutes / 60:.2f}".rstrip("0").rstrip(".")


def weekly_capacity_label(weekly_minutes: int) -> str:
    """Human label for a weekly capacity, e.g. ``"4.5 h / week"``."""
    return f"{format_hours(weekly_minutes)} h / week"


def daily_capacity_label(weekly_minutes: int) -> str:
    """Average daily time, e.g. ``"about 39 min a day"`` for 4.5 hours."""
    return f"about {round(weekly_minutes / 7)} min a day"


def effective_weekly_minutes(record: Any) -> int | None:
    """Weekly minutes of a plan, plan job or profile row.

    Rows written before the column existed (``weekly_minutes`` NULL) fall
    back to ``weekly_hours * 60``. So does a row whose ``weekly_hours`` a
    legacy writer changed without updating the minutes: the stored minutes
    are trusted only while ``ceil(minutes / 60)`` still equals the hours.
    """
    minutes = getattr(record, "weekly_minutes", None)
    hours = getattr(record, "weekly_hours", None)
    if _is_int(minutes) and minutes > 0 and (
        not _is_int(hours) or legacy_weekly_hours(minutes) == hours
    ):
        return minutes
    if _is_int(hours):
        return hours * 60
    return None


def set_weekly_minutes(record: Any, weekly_minutes: int) -> None:
    """Write the canonical minutes and the derived legacy hours together."""
    record.weekly_minutes = int(weekly_minutes)
    record.weekly_hours = legacy_weekly_hours(weekly_minutes)


def plan_item_minutes(item: Any) -> int:
    """A plan item's allocated weekly minutes.

    New items record exact minutes in ``meta_json["estimated_minutes"]``;
    their integer ``estimated_hours`` is ``ceil(minutes / 60)`` for legacy
    readers. Older or manually created items use their whole hours.
    """
    hours = getattr(item, "estimated_hours", 0) or 0
    meta = getattr(item, "meta_json", None)
    if isinstance(meta, dict):
        minutes = meta.get("estimated_minutes")
        if _is_int(minutes) and minutes > 0 and (
            not _is_int(hours) or legacy_weekly_hours(minutes) == hours
        ):
            return minutes
    return round(float(hours) * 60)


def plan_item_mission_hours(item: Any) -> int | float:
    """Allocated hours for lesson planning: whole hours stay integers."""
    return hours_value(plan_item_minutes(item))


_COUNT_WORDS = {2: "two", 3: "three", 4: "four", 5: "five"}


def rhythm_cadence(rhythm_minutes: int) -> tuple[int, int | float]:
    """Sessions per week and minutes per session for a daily rhythm."""
    sessions = 3 if rhythm_minutes < 60 else 4
    per_session = rhythm_minutes / sessions
    return sessions, int(per_session) if per_session == int(per_session) else per_session


def capacity_rule(weekly_minutes: int) -> str:
    """The capacity rule a plan prompt must follow for this week size."""
    if weekly_minutes < LOW_CAPACITY_MINUTES:
        split = capacity_split(weekly_minutes)
        sessions, per_session = rhythm_cadence(split.rhythm_minutes)
        return (
            f"This is a short week of {weekly_minutes} minutes, under 3 hours, and it is "
            "a real plan. Use exactly one mission task of "
            f"{split.mission_minutes} minutes (estimated_hours "
            f"{format_hours(split.mission_minutes)}) and exactly one daily rhythm task of "
            f"{split.rhythm_minutes} minutes (estimated_hours "
            f"{format_hours(split.rhythm_minutes)}). The 2-hour mission minimum, the "
            "1-hour daily minimum and the whole-hour rule do not apply to this week. "
            "Scope the mission to a few short 5-8 minute tutorials with their practice, "
            f"and the rhythm to {_COUNT_WORDS.get(sessions, str(sessions))} "
            f"{per_session}-minute sessions."
        )
    if weekly_minutes % 60:
        return (
            f"The capacity ends in a half hour, so estimated_hours may use whole or "
            "half hours (for example 3.5); every other count and hour rule applies."
        )
    return "Use whole integer hours; every count and hour rule applies."


def capacity_prompt_params(weekly_minutes: int) -> dict[str, str]:
    """Placeholders that let plan prompts reason about minutes, not just hours."""
    return {
        "hours_per_week": format_hours(weekly_minutes),
        "weekly_minutes": str(weekly_minutes),
        "weekly_capacity_label": (
            f"{weekly_capacity_label(weekly_minutes)} "
            f"({daily_capacity_label(weekly_minutes)})"
        ),
        "capacity_rule": capacity_rule(weekly_minutes),
    }
