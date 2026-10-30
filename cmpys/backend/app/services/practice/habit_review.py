"""Bounded, private review sessions assembled from already studied practice.

No provider call prepares a habit. Its dated LessonPractice row is independent
of mission completion. Immutable source keys keep reviews alive across weeks
without treating a changed lesson or answer key as the same learned material.
"""

from datetime import date, datetime, timedelta, timezone
from hashlib import sha256

from fastapi import HTTPException
from sqlalchemy import select

from app.models.lesson_practice import LessonPractice
from app.models.plan import Plan, PlanItem, PlanItemType
from app.services.planning.habit_schedule import (
    learning_today,
    learning_offset,
    schedule_for,
    uses_checked_review,
)
from app.services.planning.artifact_identity import artifact_job_reference_is_valid
from app.services.practice.contracts import Workbook, ReviewWorkbook, lesson_version

DAILY_TYPES = {PlanItemType.HABIT, PlanItemType.PRACTICE}
PREFIX = "review_"


def session_key(day: date) -> str:
    return f"{PREFIX}{day.isoformat()}"


def session_version(item_id: str, step_id: str) -> str:
    return sha256(f"habit-review-v1:{item_id}:{step_id}".encode()).hexdigest()


def review_due(seed: date, events: list[dict]) -> date:
    """Conservative 1/3/7/14/30-day defaults; errors or help shorten the gap.

    Only the first attempt in a dated session can extend its interval. A
    correction is valuable but is not evidence of independent delayed recall.
    """
    due, successes = seed + timedelta(days=1), 0
    # Two routines must not count two same-day repetitions as spaced successes.
    by_day = {}
    for event in events:
        prior = by_day.get(event["date"])
        by_day[event["date"]] = {
            **event,
            "passed": event.get("passed") is True
            and (prior is None or prior["passed"]),
            "assisted": event.get("assisted") is not False
            or bool(prior and prior["assisted"]),
        }
    for event in sorted(by_day.values(), key=lambda e: e["date"]):
        independent = event.get("passed") is True and event.get("assisted") is False
        successes = min(successes + 1, 4) if independent else 0
        gap = (1, 3, 7, 14, 30)[successes]
        due = max(
            seed + timedelta(days=1),
            date.fromisoformat(event["date"]) + timedelta(days=gap),
        )
    return due


def select_reviews(
    candidates: list[dict], history: dict[str, list[dict]], on: date, budget: int
) -> list[dict]:
    eligible = []
    for candidate in candidates:
        events = history.get(candidate["key"], [])
        due = review_due(candidate["seed"], events)
        if due <= on:
            latest = max(events, key=lambda e: e["date"], default={})
            needs_practice = (
                (not latest.get("passed") or latest.get("assisted") is not False)
                if latest
                else candidate.get("needs_practice", False)
            )
            eligible.append({**candidate, "due": due, "needs_practice": needs_practice})
    # Overdue errors first, then earlier learning. Limit the session, never add
    # a second stack of reviews on top of its allocated minutes.
    eligible.sort(
        key=lambda c: (
            not c["needs_practice"],
            c["due"],
            c["activity"].kind != "transfer",
            c["key"],
        )
    )
    selected, remaining = [], max(1, budget - 2)
    for candidate in eligible:
        if candidate["activity"].minutes_min <= remaining:
            selected.append(candidate)
            # A case may take longer than its low estimate. The UI stops at the
            # session cap and preserves unfinished answers for the next visit.
            remaining -= candidate["activity"].minutes_max
        if len(selected) == 3:
            break
    return selected


async def _sources(db, item, user_id, *, source_items: set[str] | None = None):
    from app.api.v1.plans import _validated_lesson_steps, _progress_eligible_step_ids
    from app.services.planning.catalog_lessons import (
        catalog_details_are_ready_in_database,
    )

    statement = (
        select(LessonPractice, PlanItem)
        .join(PlanItem, PlanItem.id == LessonPractice.plan_item_id)
        .join(Plan, Plan.id == PlanItem.plan_id)
        .where(
            Plan.id == item.plan_id,
            Plan.user_id == user_id,
            LessonPractice.user_id == user_id,
            LessonPractice.state.in_(("ready", "reviewing")),
            PlanItem.type.notin_(DAILY_TYPES),
        )
        .order_by(LessonPractice.updated_at.desc())
    )
    if source_items is not None:
        statement = statement.where(PlanItem.id.in_(source_items))
    result = await db.execute(statement.limit(2000))
    candidates, checked_items = [], {}
    for row, source in result.all():
        details = source.details_json or {}
        if (
            not row.attempts_json
            or (details.get("_generation") or {}).get("status") == "revoked"
        ):
            continue
        step = next(
            (
                s
                for s in (_validated_lesson_steps(details) or [])
                if s.get("id") == row.step_id
            ),
            None,
        )
        if not step or row.step_id not in _progress_eligible_step_ids(details):
            continue
        try:
            if row.lesson_version != lesson_version(source, step):
                continue
            workbook = Workbook.model_validate(row.workbook_json)
        except (ValueError, TypeError):
            continue
        if source.id not in checked_items:
            checked_items[source.id] = await artifact_job_reference_is_valid(
                db, details, user_id=user_id, plan_item_id=str(source.id)
            ) and await catalog_details_are_ready_in_database(
                db, details, user_id=user_id, plan_item_id=str(source.id)
            )
        if not checked_items[source.id]:
            continue
        for activity in workbook.activities:
            attempts = [
                a for a in row.attempts_json if a.get("activity_id") == activity.id
            ]
            # Only review what was actually attempted. New transfer tasks remain
            # part of teaching; a repeated case is never labelled a novel test.
            if not attempts:
                continue
            try:
                submitted = datetime.fromisoformat(attempts[-1]["submitted_at"])
                if submitted.tzinfo is None:
                    submitted = submitted.replace(tzinfo=timezone.utc)
                seed = submitted.astimezone(
                    timezone(timedelta(minutes=learning_offset.get()))
                ).date()
            except (KeyError, ValueError, TypeError):
                continue
            key = sha256(
                f"{row.id}:{row.lesson_version}:{activity.id}".encode()
            ).hexdigest()
            candidates.append(
                {
                    "key": key,
                    "activity": activity,
                    "seed": seed,
                    "needs_practice": any(
                        not attempt.get("passed")
                        or attempt.get("assisted") is not False
                        for attempt in attempts
                    ),
                    "title": str(step.get("title") or source.title),
                    "lesson_content": step.get("lesson_content", ""),
                    "source_item": str(source.id),
                    "source_step": row.step_id,
                    "source_version": row.lesson_version,
                }
            )
    return candidates


async def _history(db, item, user_id) -> tuple[dict[str, list[dict]], dict[str, dict]]:
    rows = (
        (
            await db.execute(
                select(LessonPractice)
                .join(PlanItem, PlanItem.id == LessonPractice.plan_item_id)
                .where(
                    PlanItem.plan_id == item.plan_id,
                    LessonPractice.user_id == user_id,
                    PlanItem.type.in_(DAILY_TYPES),
                )
                .order_by(LessonPractice.created_at.desc())
                .limit(400)
            )
        )
        .scalars()
        .all()
    )
    result: dict[str, list[dict]] = {}
    drafts = {}
    for row in rows:
        meta = (row.workbook_json or {}).get("review") or {}
        for activity_id, source in (meta.get("sources") or {}).items():
            first = next(
                (
                    a
                    for a in row.attempts_json or []
                    if a.get("activity_id") == activity_id
                ),
                None,
            )
            if first and meta.get("date"):
                result.setdefault(source["key"], []).append(
                    {
                        "date": meta["date"],
                        "passed": first.get("passed"),
                        "assisted": first.get("assisted"),
                    }
                )
            elif meta.get("date") and meta["date"] < learning_today().isoformat():
                answers = {
                    k.split(".", 1)[1]: value
                    for k, value in (row.answers_json or {}).items()
                    if k.startswith(activity_id + ".") and value.strip()
                }
                if answers and source["key"] not in drafts:
                    drafts[source["key"]] = {"date": meta["date"], "answers": answers}
    return result, drafts


async def compose_review(db, item, user_id, on: date):
    schedule = schedule_for(item, on)
    if not schedule["scheduled_today"]:
        return None, f"Rest day. Your next practice day is {schedule['next_date']}."
    candidates = await _sources(db, item, user_id)
    history, drafts = await _history(db, item, user_id) if candidates else ({}, {})
    budget = schedule["session_minutes"]
    selected = select_reviews(candidates, history, on, budget)
    if not selected:
        next_due = min(
            (review_due(c["seed"], history.get(c["key"], [])) for c in candidates),
            default=None,
        )
        reason = "Complete a lesson practice first. Your review will use its exercises and feedback."
        if candidates:
            reason = (
                f"Your next review is available from {next_due.isoformat()}. Rest days are part of the plan."
                if next_due > on
                else "The available cases need a longer session. Choose fewer practice days to give each session enough time."
            )
        return None, reason
    activities, sources, resumed = [], {}, {}
    for source in selected:
        activity = source["activity"].model_copy(
            update={"id": "r_" + source["key"][:24]}
        )
        activities.append(activity)
        sources[activity.id] = {
            k: source[k]
            for k in (
                "key",
                "source_item",
                "source_step",
                "source_version",
                "lesson_content",
            )
        }
        draft = drafts.get(source["key"])
        last_checked = max(
            (e["date"] for e in history.get(source["key"], [])), default=""
        )
        if draft and draft["date"] >= last_checked:
            resumed.update(
                {
                    f"{activity.id}.{field}": value
                    for field, value in draft["answers"].items()
                }
            )
    return ReviewWorkbook(
        title="Practice and review",
        activities=activities,
        review={
            "date": on.isoformat(),
            "budget_minutes": budget,
            "sources": sources,
            "source_titles": list(dict.fromkeys(c["title"] for c in selected)),
            "resume_answers": resumed,
            "recall_prompt": "Before opening a reference, recall the rule you need. Then solve the case and explain any correction.",
        },
    ), None


async def load_review(db, item, user_id, step_id):
    if not uses_checked_review(item):
        raise HTTPException(422, "Personal habits use manual participation tracking.")
    try:
        on = date.fromisoformat(step_id.removeprefix(PREFIX))
        if step_id != session_key(on) or on > learning_today():
            raise ValueError()
    except ValueError as exc:
        raise HTTPException(404, "Review session not found") from exc
    version = session_version(str(item.id), step_id)
    row = (
        await db.execute(
            select(LessonPractice)
            .where(
                LessonPractice.user_id == user_id,
                LessonPractice.plan_item_id == item.id,
                LessonPractice.step_id == step_id,
                LessonPractice.lesson_version == version,
            )
            .execution_options(populate_existing=True)
        )
    ).scalar_one_or_none()
    if on != learning_today() and row is None:
        raise HTTPException(404, "Review session not found")
    if row is None:
        from app.api.v1.daily_tasks import _items_and_execution_week

        plan = await db.get(Plan, item.plan_id)
        if plan is None or str(plan.user_id) != user_id:
            raise HTTPException(404, "Review session not found")
        _, current_week = await _items_and_execution_week(
            db, plan=plan, user_id=user_id
        )
        if not item.week_start <= current_week <= item.week_end:
            raise HTTPException(409, "Open the practice routine for your current week.")
    content = ""
    if row and row.workbook_json:
        workbook = ReviewWorkbook.model_validate(row.workbook_json)
        sources = workbook.review.get("sources") or {}
        # Revalidation prevents a withdrawn or replaced answer key being used.
        source_items = {s["source_item"] for s in sources.values()}
        valid = {
            c["key"]
            for c in await _sources(db, item, user_id, source_items=source_items)
        }
        if any(s["key"] not in valid for s in sources.values()):
            raise HTTPException(
                409,
                "A source lesson changed. Practise the updated lesson; its exercises can enter a review on a later practice day.",
            )
        content = "\n\n".join(s.get("lesson_content", "") for s in sources.values())
    return (
        item,
        {
            "id": step_id,
            "title": "Practice and review",
            "lesson_content": content,
            "_review_user_id": user_id,
        },
        row,
        version,
    )


async def review_status(db, item, user_id, *, on=None):
    on = on or learning_today()
    try:
        _, _, row, _ = await load_review(db, item, user_id, session_key(on))
    except HTTPException as exc:
        if exc.status_code != 409:
            raise
        return {
            "step_id": session_key(on),
            "date": on.isoformat(),
            "available": False,
            "message": exc.detail,
            "attempted": False,
            "checked": False,
            "needs_correction": False,
            "source_titles": [],
        }
    reason = None
    if row and row.workbook_json:
        workbook = ReviewWorkbook.model_validate(row.workbook_json)
    else:
        workbook, reason = await compose_review(db, item, user_id, on)
    attempts = row.attempts_json if row else []
    return {
        "step_id": session_key(on),
        "date": on.isoformat(),
        "available": workbook is not None,
        "message": reason,
        "attempted": bool(attempts),
        "checked": bool(attempts),
        "needs_correction": bool(attempts and not attempts[-1].get("passed")),
        "source_titles": workbook.review.get("source_titles", []) if workbook else [],
    }
