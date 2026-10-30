"""Executable, private reviews; exact capacity and non-punitive calendars."""

from datetime import date, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.v1 import daily_tasks, practice
from app.models.plan import PlanItem, PlanItemType
from app.services.planning import habit_schedule as schedule
from app.services.planning.generator import daily_workload_issues
from app.services.practice import habit_review as review
from app.services.practice.contracts import (
    Activity,
    GeneratedWorkbook,
    Workbook,
    ReviewWorkbook,
    public_workbook,
)
from app.services.practice.evidence import practice_summary

MONDAY = date(2026, 10, 26)


def habit(minutes=60, **meta):
    return PlanItem(
        id="habit",
        plan_id="plan",
        type=PlanItemType.PRACTICE,
        title="Recall and apply",
        estimated_hours=(minutes + 59) // 60,
        week_start=2,
        week_end=2,
        meta_json={"estimated_minutes": minutes, **meta},
    )


def activity(name="case", kind="practice", minutes=6):
    return Activity(
        id=name,
        title="Compare two amounts",
        kind=kind,
        instructions="A fictional shop received 12 units and spent 5 units. Calculate the remainder using the supplied inputs.",
        data=[
            {"id": "received", "label": "Received", "value": 12},
            {"id": "spent", "label": "Spent", "value": 5},
        ],
        fields=[
            {
                "id": "remaining",
                "label": "How much remains?",
                "kind": "number",
                "expression": "received-spent",
                "rubric_criterion": "Subtracts the expense",
            }
        ],
        hint="Subtract what was spent from what was received.",
        worked_solution="Subtract the five units spent from the twelve units received. Seven units remain.",
        minutes_min=3,
        minutes_max=minutes,
    )


@pytest.mark.parametrize("minutes", [1, 2, 15, 45, 50, 60, 90, 105, 120])
def test_every_displayed_session_adds_up_to_exact_weekly_capacity(minutes):
    item = habit(minutes)
    result = schedule.schedule_for(item, MONDAY)
    assert sum(a["minutes"] for a in result["session_allocations"]) == minutes
    assert all(a["minutes"] >= 1 for a in result["session_allocations"])
    for allocation in result["session_allocations"]:
        assert (
            schedule.schedule_for(item, MONDAY + timedelta(days=allocation["weekday"]))[
                "session_minutes"
            ]
            == allocation["minutes"]
        )


def test_sixty_minutes_is_three_twenty_minute_sessions_and_rest_days_are_explicit():
    item = habit(
        daily_instructions="Three 30-minute sessions, whichever comes later. Use the provided answer key."
    )
    monday = schedule.schedule_for(item, MONDAY)
    tuesday = schedule.schedule_for(item, MONDAY + timedelta(days=1))
    assert monday["label"] == "Mon, Wed, Fri · 20 min"
    assert monday["scheduled_today"] is True
    assert tuesday["scheduled_today"] is False
    assert tuesday["next_date"] == "2026-10-28"
    instructions = schedule.practice_instructions(item)
    assert (
        "provided answer key" not in instructions
        and "whichever comes later" not in instructions
    )


def test_schedule_edit_never_rewrites_old_practice_days():
    history = [{"from": "2026-10-28", "weekdays": [1, 3], "cue": "After breakfast"}]
    item = habit(habit_schedule_history=history)
    assert schedule.schedule_for(item, MONDAY)["weekdays"] == [0, 2, 4]
    assert schedule.schedule_for(item, date(2026, 10, 29))["session_minutes"] == 30
    assert schedule.schedule_for(item, date(2026, 10, 29))["cue"] == "After breakfast"


def test_rest_days_do_not_reset_streak_but_missed_scheduled_days_do():
    completed = {MONDAY, MONDAY + timedelta(days=2), MONDAY + timedelta(days=4)}
    assert schedule.scheduled_streak(
        completed, {0, 2, 4}, MONDAY + timedelta(days=6)
    ) == (3, 3)
    # Today's opportunity remains open, but an uncompleted Monday is missed Tuesday.
    assert schedule.scheduled_streak(
        completed, {0, 2, 4}, MONDAY + timedelta(days=7)
    ) == (3, 3)
    assert schedule.scheduled_streak(
        completed, {0, 2, 4}, MONDAY + timedelta(days=8)
    ) == (0, 3)


@pytest.mark.parametrize(
    "text",
    [
        "three 30-minute sessions",
        "3 sessions of 30 minutes",
        "three sessions per week at 30 minutes",
    ],
)
def test_cadence_arithmetic_is_validated(text):
    assert daily_workload_issues(
        SimpleNamespace(
            type="practice",
            title="Review",
            estimated_hours=1,
            description=text,
            daily_instructions="",
        )
    )


def test_good_cadence_is_accepted_but_missing_material_promises_are_not():
    task = SimpleNamespace(
        type="practice",
        title="Review",
        estimated_hours=1,
        description="three 20-minute sessions",
        daily_instructions="Stop and save at the time limit.",
    )
    assert daily_workload_issues(task) == []
    task.daily_instructions = "Use the supplied worked example and provided answer key."
    assert daily_workload_issues(task)


def test_spacing_uses_first_attempt_and_shortens_after_help_or_error():
    assert review.review_due(MONDAY, []) == MONDAY + timedelta(days=1)
    success = {"date": "2026-10-28", "passed": True, "assisted": False}
    assert review.review_due(MONDAY, [success]) == date(2026, 10, 31)
    assisted = {"date": "2026-10-31", "passed": True, "assisted": True}
    assert review.review_due(MONDAY, [success, assisted]) == date(2026, 11, 1)
    assert review.review_due(MONDAY, [success, success]) == date(2026, 10, 31)


def test_due_reviews_fit_budget_and_exclude_future_reviews():
    candidates = [
        {"key": key, "activity": activity(name=key), "seed": seed}
        for key, seed in (("old", MONDAY - timedelta(days=5)), ("new", MONDAY))
    ]
    selected = review.select_reviews(candidates, {}, MONDAY, 20)
    assert [c["key"] for c in selected] == ["old"]
    assert review.select_reviews(candidates, {}, MONDAY, 3) == []
    # A five-minute session can start a 3–6-minute case and save at its time cap.
    assert len(review.select_reviews(candidates, {}, MONDAY, 5)) == 1


def test_review_identity_cannot_overwrite_a_lesson_or_another_day():
    first = review.session_version("habit", review.session_key(MONDAY))
    assert first != review.session_version(
        "habit", review.session_key(MONDAY + timedelta(days=1))
    )
    assert first != review.session_version("another-habit", review.session_key(MONDAY))


def test_private_answers_stay_private_and_legacy_workbook_shape_stays_stable():
    lesson = Workbook(
        title="Lesson", activities=[activity(), activity("transfer", "transfer")]
    )
    assert "purpose" not in lesson.model_dump() and "review" not in lesson.model_dump()
    workbook = ReviewWorkbook(
        title="Review",
        activities=[activity()],
        review={
            "date": "2026-10-26",
            "budget_minutes": 20,
            "sources": {"secret": "private lesson"},
            "resume_answers": {"case.remaining": "7"},
            "source_titles": ["Prior lesson"],
        },
    )
    public = public_workbook(workbook)
    assert (
        "sources" not in public["review"] and "resume_answers" not in public["review"]
    )
    assert "expression" not in public["activities"][0]["fields"][0]
    assert "worked_solution" not in public["activities"][0]
    with pytest.raises(ValidationError):
        GeneratedWorkbook.model_validate(workbook.model_dump())
    with pytest.raises(ValidationError):
        Workbook(title="Incomplete lesson", activities=[activity()])


def test_corrected_review_is_not_presented_as_unassisted_transfer():
    workbook = ReviewWorkbook(
        title="Review", activities=[activity("case", "transfer")], review={}
    )
    row = SimpleNamespace(
        answers_json={"case.remaining": "7"},
        attempts_json=[
            {
                "activity_id": "case",
                "answers": {"remaining": "9"},
                "passed": False,
                "assisted": False,
            },
            {
                "activity_id": "case",
                "answers": {"remaining": "7"},
                "passed": True,
                "assisted": False,
            },
        ],
    )
    evidence = practice_summary(row, workbook)
    assert evidence["status"] == "review_needs_practice"
    assert "not novel transfer" in evidence["scope"]


@pytest.mark.asyncio
async def test_rest_day_never_loads_or_generates_content(monkeypatch):
    sources = AsyncMock()
    monkeypatch.setattr(review, "_sources", sources)
    result, reason = await review.compose_review(
        AsyncMock(), habit(), "user", MONDAY + timedelta(days=1)
    )
    assert result is None and "Rest day" in reason
    sources.assert_not_called()


@pytest.mark.asyncio
async def test_prior_week_source_is_reused_with_private_inputs_and_no_mutation(
    monkeypatch,
):
    original = activity()
    source = {
        "key": "a" * 64,
        "activity": original,
        "seed": MONDAY - timedelta(days=3),
        "title": "Earlier lesson",
        "source_item": "week-one",
        "source_step": "s1",
        "source_version": "immutable-key",
        "lesson_content": "Private teaching context",
    }
    monkeypatch.setattr(review, "_sources", AsyncMock(return_value=[source]))
    monkeypatch.setattr(review, "_history", AsyncMock(return_value=({}, {})))
    workbook, reason = await review.compose_review(AsyncMock(), habit(), "user", MONDAY)
    assert reason is None and workbook.purpose == "review"
    assert workbook.activities[0].data == original.data
    assert original.id == "case" and workbook.activities[0].id != original.id
    assert (
        workbook.review["sources"][workbook.activities[0].id]["source_item"]
        == "week-one"
    )
    assert workbook.review["budget_minutes"] == 20


@pytest.mark.asyncio
async def test_unfinished_answers_resume_without_revealing_a_solution(monkeypatch):
    original = activity()
    source = {
        "key": "a" * 64,
        "activity": original,
        "seed": MONDAY - timedelta(days=3),
        "title": "Earlier lesson",
        "source_item": "week-one",
        "source_step": "s1",
        "source_version": "immutable-key",
        "lesson_content": "Private teaching context",
    }
    monkeypatch.setattr(review, "_sources", AsyncMock(return_value=[source]))
    monkeypatch.setattr(
        review,
        "_history",
        AsyncMock(
            return_value=(
                {},
                {source["key"]: {"date": "2026-10-23", "answers": {"remaining": "6"}}},
            )
        ),
    )
    workbook, _ = await review.compose_review(AsyncMock(), habit(), "user", MONDAY)
    assert list(workbook.review["resume_answers"].values()) == ["6"]
    assert "resume_answers" not in public_workbook(workbook)["review"]


@pytest.mark.asyncio
async def test_review_pool_only_uses_current_owned_studied_sources(monkeypatch):
    from app.services.practice.contracts import lesson_version

    source = PlanItem(
        id="source",
        plan_id="plan",
        type=PlanItemType.COURSE,
        title="Arithmetic",
        details_json={
            "steps": [
                {
                    "id": "s1",
                    "title": "Subtract",
                    "lesson_content": "Use the two supplied amounts.",
                }
            ]
        },
    )
    step = source.details_json["steps"][0]
    workbook = Workbook(
        title="Lesson", activities=[activity(), activity("second", "transfer")]
    )
    row = SimpleNamespace(
        id="practice",
        lesson_version=lesson_version(source, step),
        step_id="s1",
        workbook_json=workbook.model_dump(),
        attempts_json=[
            {
                "activity_id": "case",
                "passed": False,
                "assisted": False,
                "submitted_at": "2026-10-23T10:00:00+00:00",
            }
        ],
    )
    result = MagicMock()
    result.all.return_value = [(row, source)]
    db = AsyncMock()
    db.execute.return_value = result
    found = await review._sources(db, habit(), "owner")
    assert len(found) == 1 and found[0]["needs_practice"] is True
    query = db.execute.call_args.args[0]
    assert "owner" in query.compile().params.values()
    assert "plans.user_id" in str(query) and "lesson_practices.user_id" in str(query)
    row.lesson_version = "superseded"
    assert await review._sources(db, habit(), "owner") == []
    row.lesson_version = lesson_version(source, step)
    source.details_json = {**source.details_json, "_generation": {"status": "revoked"}}
    assert await review._sources(db, habit(), "owner") == []


@pytest.mark.asyncio
async def test_schedule_save_is_owned_and_preserves_history_and_budget(monkeypatch):
    monkeypatch.setattr(daily_tasks, "learning_today", lambda: MONDAY)
    plan = SimpleNamespace(id="plan", roadmap_json={"roadmap_thesis": "Keep this"})
    item = habit()
    first, second = MagicMock(), MagicMock()
    first.scalar_one_or_none.return_value = plan
    second.scalars.return_value.all.return_value = [item]
    db = AsyncMock()
    db.execute.side_effect = [first, second]
    response = await daily_tasks.update_practice_schedule(
        "habit",
        daily_tasks.PracticeScheduleRequest(weekdays=[1, 3], cue="After breakfast"),
        db,
        SimpleNamespace(id="owner"),
    )
    assert response["effective_from"] == "2026-11-02"
    assert schedule.schedule_for(item, MONDAY)["pending"]["weekdays"] == [1, 3]
    sunday = schedule.schedule_for(item, MONDAY + timedelta(days=6))
    assert sunday["next_date"] == "2026-11-03"
    assert sunday["session_minutes"] == 30
    assert plan.roadmap_json["roadmap_thesis"] == "Keep this"
    assert schedule.schedule_for(item, MONDAY)["session_minutes"] == 20
    assert (
        schedule.schedule_for(item, MONDAY + timedelta(days=8))["session_minutes"] == 30
    )
    for week in (0, 1):
        days = [
            schedule.schedule_for(item, MONDAY + timedelta(days=week * 7 + d))
            for d in range(7)
        ]
        assert sum(d["session_minutes"] for d in days if d["scheduled_today"]) == 60
    assert "owner" in db.execute.call_args_list[0].args[0].compile().params.values()
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_old_reflection_cannot_be_silently_saved_on_a_new_day(monkeypatch):
    from app.api.v1 import plans

    monkeypatch.setattr(plans, "_get_item_for_user", AsyncMock(return_value=habit()))
    monkeypatch.setattr(schedule, "learning_today", lambda: MONDAY)
    db = AsyncMock()
    with pytest.raises(HTTPException) as error:
        await plans.save_daily_reflection(
            "habit",
            plans.DailyReflectionRequest(
                text="Yesterday's correction", session_date=MONDAY - timedelta(days=1)
            ),
            db,
            SimpleNamespace(id="owner"),
        )
    assert error.value.status_code == 409
    db.commit.assert_not_called()


@pytest.mark.asyncio
async def test_review_preparation_never_calls_provider_or_requires_mission_completion(
    monkeypatch,
):
    item = habit()
    item.success_metric = "Correct a misconception"
    row = SimpleNamespace(
        workbook_json=None,
        generation_attempts=0,
        review_calls=0,
        lease_until=None,
        state="ready",
        revision=0,
        lesson_version="v",
        answers_json={},
        attempts_json=[],
        hints_json=[],
    )
    step = {"id": "review_2026-10-26", "lesson_content": ""}
    monkeypatch.setattr(
        practice, "_load", AsyncMock(return_value=(item, step, row, "v"))
    )
    prepared = ReviewWorkbook(
        title="Review", activities=[activity()], review={"date": "2026-10-26"}
    )
    monkeypatch.setattr(
        practice, "_canonical_workbook", AsyncMock(return_value=prepared)
    )
    provider = AsyncMock()
    monkeypatch.setattr(practice, "generate_workbook", provider)
    result = await practice.prepare_practice(
        "habit", step["id"], AsyncMock(), SimpleNamespace(id="user")
    )
    assert result["state"] == "ready" and row.generation_attempts == 0
    assert not item.meta_json.get("practice_versions")
    provider.assert_not_called()


@pytest.mark.asyncio
async def test_empty_review_cannot_fall_back_to_paid_generation(monkeypatch):
    monkeypatch.setattr(
        practice,
        "_load",
        AsyncMock(return_value=(habit(), {"id": "review_2026-10-26"}, None, "v")),
    )
    monkeypatch.setattr(practice, "_canonical_workbook", AsyncMock(return_value=None))
    provider = AsyncMock()
    monkeypatch.setattr(practice, "generate_workbook", provider)
    with pytest.raises(HTTPException) as error:
        await practice.prepare_practice(
            "habit", "review_2026-10-26", AsyncMock(), SimpleNamespace(id="user")
        )
    assert error.value.status_code == 409
    provider.assert_not_called()


@pytest.mark.asyncio
async def test_generated_routine_completion_requires_checked_evidence(monkeypatch):
    monkeypatch.setattr(
        daily_tasks, "_get_item_for_user", AsyncMock(return_value=habit())
    )
    monkeypatch.setattr(
        review, "load_review", AsyncMock(return_value=(habit(), {}, None, "v"))
    )
    result = MagicMock()
    result.scalar_one_or_none.return_value = None
    db = AsyncMock()
    db.execute.return_value = result
    with pytest.raises(HTTPException) as error:
        await daily_tasks.toggle_daily_completion(
            "habit", db, SimpleNamespace(id="user")
        )
    assert error.value.status_code == 409
    db.commit.assert_not_called()


@pytest.mark.asyncio
async def test_personal_habit_keeps_manual_participation_and_own_instructions(
    monkeypatch,
):
    item = habit(practice_mode="manual", daily_instructions="Practise piano scales.")
    monkeypatch.setattr(daily_tasks, "_get_item_for_user", AsyncMock(return_value=item))
    monkeypatch.setattr(daily_tasks, "calculate_streak", AsyncMock(return_value=1))
    load = AsyncMock(
        side_effect=AssertionError("A personal habit needs no lesson review")
    )
    monkeypatch.setattr(review, "load_review", load)
    result = MagicMock()
    result.scalar_one_or_none.return_value = None
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = result
    response = await daily_tasks.toggle_daily_completion(
        "habit", db, SimpleNamespace(id="user")
    )
    assert response.completed is True
    assert daily_tasks._daily_instructions_for_item(item) == "Practise piano scales."
    load.assert_not_called()
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_timezone_offset_is_bounded_and_request_scoped():
    seen = []

    async def app(scope, receive, send):
        seen.append(schedule.learning_offset.get())

    middleware = schedule.LearningCalendarMiddleware(app)
    for value in (b"240", b"-720", b"bad", b"99999"):
        await middleware(
            {"type": "http", "headers": [(b"x-learning-utc-offset", value)]}, None, None
        )
        assert schedule.learning_offset.get() == 0
    assert seen == [240, -720, 0, 0]
