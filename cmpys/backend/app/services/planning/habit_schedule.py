"""One calendar and minute allocation for recurring learning practice.

Schedules are product defaults, not claims about an optimal spacing interval.
The request's UTC offset makes Today, reflections and completion agree locally.
"""

from contextvars import ContextVar
from datetime import date, datetime, timedelta, timezone
import re

from app.services.planning.capacity import DEFAULT_PRACTICE_WEEKDAYS, plan_item_minutes

learning_offset: ContextVar[int] = ContextVar("learning_offset", default=0)
DAY_NAMES = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
DEFAULT_DAYS = DEFAULT_PRACTICE_WEEKDAYS
COUNTS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7}


def uses_checked_review(item) -> bool:
    """Generated learning routines require evidence; explicit personal habits do not."""
    return (item.meta_json or {}).get("practice_mode") != "manual"


def learning_today() -> date:
    return datetime.now(timezone(timedelta(minutes=learning_offset.get()))).date()


class LearningCalendarMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        try:
            offset = int(
                dict(scope.get("headers", [])).get(b"x-learning-utc-offset", b"0")
            )
        except (ValueError, TypeError):
            offset = 0
        token = learning_offset.set(offset if -720 <= offset <= 840 else 0)
        try:
            await self.app(scope, receive, send)
        finally:
            learning_offset.reset(token)


def cadence_claims(text: str) -> list[tuple[int, float]]:
    """Read explicit 'three 20-minute sessions' and '3 sessions of 20 minutes'."""
    count = r"(\d+|one|two|three|four|five|six|seven)"
    patterns = (
        rf"\b{count}\s+(\d+(?:\.\d+)?)\s*[-– ]?\s*minute\s+sessions?\b",
        rf"\b{count}\s+sessions?(?:\s+(?:per|a|each)\s+week)?\s+(?:of|at)\s+(\d+(?:\.\d+)?)\s*[-– ]?\s*minutes?\b",
    )
    found = []
    for pattern in patterns:
        for n, minutes in re.findall(pattern, text, re.I):
            found.append(
                (COUNTS.get(n.lower(), int(n) if n.isdigit() else 0), float(minutes))
            )
    return found


def schedule_for(item, on: date | None = None) -> dict:
    on = on or learning_today()
    minutes = max(1, plan_item_minutes(item))
    stored = (item.meta_json or {}).get("habit_schedule") or {}
    history = (item.meta_json or {}).get("habit_schedule_history") or []
    if history:
        stored = next(
            (
                entry
                for entry in reversed(history)
                if entry.get("from", "9999") <= on.isoformat()
            ),
            {},
        )
    days = stored.get("weekdays")
    if (
        not isinstance(days, list)
        or not days
        or any(type(d) is not int or d not in range(7) for d in days)
    ):
        days = list(DEFAULT_DAYS[: min(3, minutes)])
    days = sorted(set(days))
    if len(days) > minutes:
        days = days[:minutes]
    quotient, remainder = divmod(minutes, len(days))
    allocations = {day: quotient + (i < remainder) for i, day in enumerate(days)}
    # A pending next-week schedule also controls the next practice date.
    for i in range(14):
        next_day = on + timedelta(days=i)
        future = next(
            (
                entry
                for entry in reversed(history)
                if entry.get("from", "9999") <= next_day.isoformat()
            ),
            None,
        )
        next_days = sorted(set(future["weekdays"]))[:minutes] if future else days
        if next_day.weekday() in next_days:
            quotient_next, remainder_next = divmod(minutes, len(next_days))
            next_minutes = quotient_next + (
                next_days.index(next_day.weekday()) < remainder_next
            )
            break
    durations = [allocations[d] for d in days]
    duration_label = (
        str(durations[0])
        if len(set(durations)) == 1
        else f"{min(durations)}–{max(durations)}"
    )
    return {
        "weekdays": days,
        "session_allocations": [
            {"weekday": d, "minutes": allocations[d]} for d in days
        ],
        "weekly_minutes": minutes,
        "session_minutes": allocations.get(on.weekday(), next_minutes),
        "scheduled_today": on.weekday() in days,
        "next_date": next_day.isoformat(),
        "label": f"{', '.join(DAY_NAMES[d] for d in days)} · {duration_label} min",
        "cue": str(stored.get("cue") or "After your usual morning or evening routine")[
            :200
        ],
        "pending": next(
            (entry for entry in history if entry["from"] > on.isoformat()), None
        ),
    }


def practice_instructions(item) -> str:
    schedule = schedule_for(item)
    return (
        f"Practise on {', '.join(DAY_NAMES[d] for d in schedule['weekdays'])}, "
        f"within the {schedule['weekly_minutes']}-minute weekly allocation. "
        f"Cue ({schedule['cue']}): close distractions and reconstruct a taught rule and its deciding cue in your own words before reopening the lesson. "
        "Open your review to find the exercise, its inputs and saved answer fields. "
        "Try it from memory before requesting a hint. Check your answer, read the feedback, and "
        "revise a mistake or explain the corrected rule in your reflection. "
        "Stop and save when the session budget ends; unfinished work is preserved. "
        "Reviews reuse studied lessons and revisit earlier mistakes across weeks. "
        "Complete a lesson practice first if there is nothing ready to review. "
        "Logging a session records participation; answer checks provide separate learning evidence."
    )


def scheduled_streak(
    completed: set[date],
    weekdays: set[int],
    today: date,
    history: list[dict] | None = None,
) -> tuple[int, int]:
    """Count practice days; a planned rest day cannot break the run.

    Today stays open until midnight. Optional practice on a rest day is welcome
    but neither adds a scheduled success nor hides a missed scheduled day.
    """
    if not completed or not weekdays:
        return 0, 0
    run = longest = 0
    cursor = min(completed)
    while cursor <= today:
        applicable = next(
            (
                entry["weekdays"]
                for entry in reversed(history or [])
                if entry["from"] <= cursor.isoformat()
            ),
            weekdays,
        )
        if cursor.weekday() in applicable:
            if cursor in completed:
                run += 1
                longest = max(longest, run)
            elif cursor < today:
                run = 0
        cursor += timedelta(days=1)
    return run, longest
