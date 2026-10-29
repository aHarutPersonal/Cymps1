"""Weekly capacity in minutes (60-900, 30-minute steps) and low-capacity plans.

Owner decision D4: intake v3 records 1-15 focused hours a week in half-hour
steps. It is stored as minutes, ``weekly_hours`` stays a legacy integer
(``ceil(minutes / 60)``), and the planner honestly supports 1-2.5 hour weeks
with one short mission instead of raising them to three hours.
"""
from __future__ import annotations

import importlib.util
import math
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.models.plan import Plan, PlanItem, PlanItemStatus, PlanItemType
from app.services.planning import generator
from app.services.planning.capacity import (
    CapacitySplit,
    capacity_split,
    daily_capacity_label,
    effective_weekly_minutes,
    legacy_weekly_hours,
    plan_item_minutes,
    plan_item_mission_hours,
    weekly_capacity_label,
)
from app.services.interview_inputs import (
    INTERVIEW_ANSWER_KEYS_V1,
    INTERVIEW_ANSWER_KEYS_V2,
    build_interview_plan_inputs,
    missing_interview_answer_keys,
    parse_weekly_minutes_answer,
    provider_interview_plan_inputs,
)

MISSION_TYPES = {PlanItemType.PROJECT, PlanItemType.COURSE, PlanItemType.READING}
DAILY_TYPES = {PlanItemType.HABIT, PlanItemType.PRACTICE}


# ---------------------------------------------------------------------------
# Parsing (Review Focus 2: typed numbers, including the comma decimal)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("answer", "expected"),
    [
        ("4.5 hours a week", 270),
        ("4,5 h", 270),
        ("4,5", 270),
        ("4 h 30", 270),
        ("4h30m", 270),
        ("4 hours 30 minutes per week", 270),
        ("270 minutes", 270),
        ("270 min a week", 270),
        # The v3 number control sends "<value> <unit>".
        ("4.5 hours / week", 270),
        ("1 hours / week", 60),
        ("1.5 hours / week", 90),
        ("2 hours / week", 120),
        ("2.5 hours / week", 150),
        ("15 hours / week", 900),
        ("1", 60),
        ("1.5", 90),
        ("8", 480),
        ("eight", 480),
        ("8 hours per week", 480),
        ("90 minutes", 90),
        # Out of range, off-step or ambiguous answers are never guessed.
        ("0.5", None),
        ("30 minutes", None),
        ("45 minutes", None),
        ("4.25 hours", None),
        ("16", None),
        ("15.5 hours", None),
        ("between 2 and 3 hours per week", None),
        ("4,5,6", None),
        ("I do not know yet", None),
        ("", None),
    ],
)
def test_parse_weekly_minutes_variants(answer, expected):
    assert parse_weekly_minutes_answer(answer) == expected


def _message(message_id, role, content, *, answer_key=None, reply_to=None):
    from app.models.chat import MessageRole  # noqa: F401  (role is passed in)

    return SimpleNamespace(
        id=message_id,
        role=role,
        content=content,
        response_ui_json=(
            {"version": 1, "kind": "text", "answer_key": answer_key}
            if answer_key
            else None
        ),
        reply_to_message_id=reply_to,
    )


def _weekly_messages(answer: str, *, legacy: bool):
    from app.models.chat import MessageRole

    first_key = "current_capability" if legacy else "work_sample"
    return [
        _message("q1", MessageRole.ASSISTANT, "First", answer_key=first_key),
        _message("a1", MessageRole.USER, "Something real", reply_to="q1"),
        _message("q2", MessageRole.ASSISTANT, "Hours?", answer_key="weekly_hours"),
        _message("a2", MessageRole.USER, answer, reply_to="q2"),
    ]


@pytest.mark.parametrize(
    ("answer", "minutes", "hours"),
    [("4.5 hours / week", 270, 4.5), ("1 hours / week", 60, 1), ("2,5", 150, 2.5)],
)
def test_v2_sessions_store_minutes_in_the_learner_baseline(answer, minutes, hours):
    messages = _weekly_messages(answer, legacy=False)
    baseline = build_interview_plan_inputs(messages)
    assert baseline["interview_key_set"] == "v2"
    assert baseline["weekly_capacity_minutes"] == minutes
    assert baseline["weekly_capacity_hours"] == hours
    assert baseline["weekly_capacity_confirmed"] is True
    assert "weekly_hours" not in missing_interview_answer_keys(messages)
    provider = provider_interview_plan_inputs(baseline)
    assert provider["weekly_capacity_minutes"] == minutes
    assert provider["weekly_capacity_hours"] == minutes / 60


@pytest.mark.parametrize(
    ("answer", "minutes"),
    [("8 hours per week", 480), ("3", 180), ("60", 3600), ("2", None), ("4.5", None)],
)
def test_v1_sessions_keep_the_3_to_60_whole_hour_contract_stored_as_minutes(answer, minutes):
    messages = _weekly_messages(answer, legacy=True)
    baseline = build_interview_plan_inputs(messages)
    assert baseline["interview_key_set"] == "v1"
    assert baseline["weekly_capacity_minutes"] == minutes
    assert ("weekly_hours" in missing_interview_answer_keys(messages)) is (minutes is None)


# ---------------------------------------------------------------------------
# Capacity split
# ---------------------------------------------------------------------------


def _legacy_rule(weekly_hours):
    """The integer-hour rule of _generate_deterministic_items before minutes."""
    weekly_hours = max(3, weekly_hours)
    available_for_missions = weekly_hours - 1
    mission_count = (
        1 if weekly_hours < 6 else min(3, max(2, (available_for_missions + 7) // 8))
    )
    mission_budget = min(available_for_missions, mission_count * 8)
    daily_hours = weekly_hours - mission_budget
    return daily_hours * 60, mission_budget * 60, mission_count


@pytest.mark.parametrize("weekly_minutes", range(180, 901, 30))
def test_capacity_split_matches_legacy_rule_at_or_above_3h(weekly_minutes):
    split = capacity_split(weekly_minutes)
    assert isinstance(split, CapacitySplit)
    assert (split.rhythm_minutes, split.mission_minutes, split.mission_count) == (
        _legacy_rule(weekly_minutes / 60)
    )
    assert split.rhythm_minutes + split.mission_minutes == weekly_minutes
    # The generator exposes the same rule the deterministic planner uses.
    assert generator.capacity_split(weekly_minutes) == split


@pytest.mark.parametrize("weekly_hours", [3, 4, 5, 6, 8, 10, 15, 30, 60])
def test_capacity_split_reproduces_whole_hour_weeks_exactly(weekly_hours):
    split = capacity_split(weekly_hours * 60)
    assert (split.rhythm_minutes, split.mission_minutes, split.mission_count) == (
        _legacy_rule(weekly_hours)
    )


@pytest.mark.parametrize(
    ("weekly_minutes", "rhythm", "mission"),
    [(60, 15, 45), (90, 15, 75), (120, 30, 90), (150, 30, 120)],
)
def test_capacity_split_low_capacity(weekly_minutes, rhythm, mission):
    assert capacity_split(weekly_minutes) == CapacitySplit(
        rhythm_minutes=rhythm, mission_minutes=mission, mission_count=1
    )


def test_capacity_labels_and_legacy_hours():
    assert weekly_capacity_label(270) == "4.5 h / week"
    assert weekly_capacity_label(60) == "1 h / week"
    assert daily_capacity_label(270) == "about 39 min a day"
    assert legacy_weekly_hours(270) == 5
    assert legacy_weekly_hours(60) == 1
    assert legacy_weekly_hours(90) == 2
    assert legacy_weekly_hours(600) == 10


def test_effective_weekly_minutes_tolerates_rows_written_before_the_column():
    assert effective_weekly_minutes(SimpleNamespace(weekly_minutes=270, weekly_hours=5)) == 270
    assert effective_weekly_minutes(SimpleNamespace(weekly_minutes=None, weekly_hours=8)) == 480
    assert effective_weekly_minutes(SimpleNamespace(weekly_hours=8)) == 480
    # A legacy writer that changed only weekly_hours wins over a stale minutes value.
    assert effective_weekly_minutes(SimpleNamespace(weekly_minutes=270, weekly_hours=8)) == 480


# ---------------------------------------------------------------------------
# Low-capacity plans (Review Focus 5)
# ---------------------------------------------------------------------------


def _phase(week: int) -> str:
    return (
        "foundation" if week <= 3 else "core_skills" if week <= 6
        else "applied_practice" if week <= 9 else "integration"
    )


def _low_capacity_backbone(mission_hours: float, rhythm_hours: float):
    from app.services.llm.schemas import PlanBackboneResponse

    return PlanBackboneResponse.model_validate({
        "roadmap_thesis": "Build one checked artifact each short week.",
        "anti_goals": ["Avoid collecting advice without a checked artifact."],
        "weeks": [
            {
                "week_number": week,
                "phase": _phase(week),
                "primary_mission": f"Complete short proof {week}.",
                "outcome": f"Short proof {week} passes its rubric.",
                "tasks": [
                    {"title": f"Build short proof {week}", "type": "project",
                     "estimated_hours": mission_hours,
                     "success_metric": f"Proof {week} passes its rubric."},
                    {"title": "Daily recall drill", "type": "practice",
                     "estimated_hours": rhythm_hours,
                     "success_metric": "Three dated recall notes are saved."},
                ],
            }
            for week in range(1, 13)
        ],
    })


def _low_capacity_week(mission_hours: float, rhythm_hours: float):
    from app.services.llm.schemas import PlanGenerationResponse

    return PlanGenerationResponse.model_validate({
        "roadmap_thesis": "Build one checked artifact each short week.",
        "anti_goals": ["Avoid collecting advice without a checked artifact."],
        "weeks": [{
            "week_number": 1,
            "primary_mission": "Complete short proof 1.",
            "binary_tasks": [
                {"title": "Build short proof 1", "type": "project",
                 "description": " ".join(["domain-specific"] * 52),
                 "estimated_hours": mission_hours,
                 "success_metric": "Proof 1 passes its rubric."},
                {"title": "Daily recall drill", "type": "practice",
                 "description": " ".join(["recall"] * 32),
                 "estimated_hours": rhythm_hours,
                 "daily_instructions": " ".join(["practice"] * 42),
                 "success_metric": "Three dated recall notes are saved."},
            ],
        }],
    })


@pytest.mark.parametrize("weekly_minutes", [60, 90, 120, 150])
def test_low_capacity_plan_passes_capacity_validators(weekly_minutes):
    from tests.test_short_tutorial_pipeline import complete_step, outline
    from app.services.planning.tutorial_capacity import (
        pending_tutorial_allocation,
        reading_capacity_targets,
    )
    from app.tasks.plans import _plan_detail_lesson_count_bounds, normalize_lesson_durations

    split = capacity_split(weekly_minutes)
    mission_hours, rhythm_hours = split.mission_minutes / 60, split.rhythm_minutes / 60

    # The deterministic planner fits the week exactly: one mission, one rhythm.
    roadmap = generator._generate_deterministic_items(
        None, 12, weekly_minutes=weekly_minutes,
        idol_name="Ada Lovelace", user_goal="learn computational thinking",
    )
    for week in range(1, 13):
        items = [item for item in roadmap.items if item.week_start == week]
        missions = [item for item in items if item.type in MISSION_TYPES]
        rhythms = [item for item in items if item.type in DAILY_TYPES]
        assert len(missions) == 1 and len(rhythms) == 1
        assert plan_item_minutes(missions[0]) == split.mission_minutes
        assert plan_item_minutes(rhythms[0]) == split.rhythm_minutes
        assert sum(plan_item_minutes(item) for item in items) == weekly_minutes
        # Legacy readers get a whole, never-zero hour estimate.
        assert all(item.estimated_hours == math.ceil(plan_item_minutes(item) / 60) for item in items)
        cadence = rhythms[0].description + rhythms[0].meta_json["daily_instructions"]
        assert "ten-to-twenty" not in cadence and "ten to twenty" not in cadence

    # The LLM backbone and week contracts accept the exact short split ...
    backbone = _low_capacity_backbone(mission_hours, rhythm_hours)
    assert generator.validate_plan_backbone(
        backbone, duration_weeks=12, weekly_minutes=weekly_minutes) == []
    assert generator.validate_plan_contract(
        _low_capacity_week(mission_hours, rhythm_hours), duration_weeks=1,
        weekly_minutes=weekly_minutes) == []
    # ... reject a week that exceeds the capacity ...
    overfull = _low_capacity_backbone(mission_hours + 1, rhythm_hours)
    assert any("weekly capacity" in issue for issue in generator.validate_plan_backbone(
        overfull, duration_weeks=12, weekly_minutes=weekly_minutes))
    # ... and the server's workload arithmetic snaps model drift to the split.
    drifted = _low_capacity_backbone(1.0, 0.5)
    corrected, changes = generator._normalize_backbone_workload(
        drifted, weekly_minutes=weekly_minutes)
    assert generator.validate_plan_backbone(
        corrected, duration_weeks=12, weekly_minutes=weekly_minutes) == []
    roadmap = generator._roadmap_from_backbone(
        corrected, expanded_week=_low_capacity_week(mission_hours, rhythm_hours).weeks[0],
        weekly_minutes=weekly_minutes,
    )
    mission_item = next(item for item in roadmap.items if item.type in MISSION_TYPES)
    assert plan_item_minutes(mission_item) == split.mission_minutes
    assert plan_item_mission_hours(mission_item) == mission_hours

    # Downstream tutorial validators accept the short mission made of 5-8
    # minute tutorials (no hidden two-hour mission floor).
    count = round(split.mission_minutes / 6)
    low, high = _plan_detail_lesson_count_bounds(mission_hours, lesson_format="tutorial_v1")
    assert low <= count <= high
    steps = [complete_step(step) for step in outline(count)["steps"]]
    assert all(5 <= step["estimate_minutes"] <= 8 for step in steps)
    details = normalize_lesson_durations(
        {"lesson_format": "tutorial_v1", "steps": steps}, mission_hours=mission_hours)
    assert details["workload"]["status"] == "reconciled"
    assert details["workload"]["allocated_minutes"] == split.mission_minutes
    assert reading_capacity_targets(steps, mission_hours, set()) == []
    assert pending_tutorial_allocation(
        steps[:-2], mission_hours, pending_count=2, planned_minutes=6) is None


def test_short_week_rejects_extra_tasks_without_a_misleading_repair_hint():
    from app.services.llm.schemas import PlanBackboneTask

    backbone = _low_capacity_backbone(0.75, 0.25)
    backbone.weeks[0].tasks.append(PlanBackboneTask(
        title="Second daily drill", type="habit", estimated_hours=0.25,
        success_metric="Three more dated notes are saved."))
    issues = generator.validate_plan_backbone(backbone, duration_weeks=12, weekly_minutes=60)
    assert "week 1 has invalid daily task count" in issues
    assert not any("at most 0 missions" in issue for issue in issues)
    assert any("weekly capacity" in issue for issue in issues)


def test_whole_hour_weeks_keep_the_legacy_hour_contract():
    # Six whole hours keep integer-hour rounding and the 2-8 hour mission range.
    from tests.test_plan_execution_contract import _plan

    assert generator.validate_plan_contract(_plan([1, 2]), duration_weeks=2, weekly_minutes=360) == []
    issues = generator.validate_plan_contract(_plan([1], mission_hours=1), duration_weeks=1,
                                              weekly_minutes=360)
    assert any("stores 4 hours" in issue for issue in issues)
    assert any("mission range is 2-8" in issue for issue in issues)


@pytest.mark.asyncio
async def test_catalog_capacity_reserves_the_short_mission_minutes():
    from app.services.planning import catalog_lessons as catalog
    from tests.test_catalog_personalization import _FakeDB, _Result

    plan = SimpleNamespace(id="plan-1", weekly_hours=1, weekly_minutes=60, duration_weeks=1)
    rows = [
        SimpleNamespace(week_start=1, week_end=1, type=PlanItemType.PROJECT,
                        estimated_hours=1, meta_json={"estimated_minutes": 45}),
        SimpleNamespace(week_start=1, week_end=1, type=PlanItemType.PRACTICE,
                        estimated_hours=1, meta_json={"estimated_minutes": 15}),
    ]
    capacity = await catalog._catalog_capacity_by_week(
        _FakeDB([_Result(rows)]), plan=plan, start_week=1, max_week=1)
    assert capacity == {1: 45}


# ---------------------------------------------------------------------------
# Plan job: the raise to three hours is gone
# ---------------------------------------------------------------------------


async def _run_plan_job(monkeypatch, job, *, session_ctx=None):
    from app.tasks import plans

    db = AsyncMock()
    db.add = MagicMock()

    async def execute(statement):
        sql = str(statement)
        if sql.startswith("UPDATE plan_generation_jobs"):
            return SimpleNamespace(rowcount=1)
        row = job if "FROM plan_generation_jobs" in sql else None
        return SimpleNamespace(scalar_one_or_none=lambda: row,
                               scalars=lambda: SimpleNamespace(all=lambda: []))

    db.execute.side_effect = execute

    class Context:
        async def __aenter__(self):
            return db

        async def __aexit__(self, *_args):
            return None

    generated = AsyncMock(return_value=generator.PlanRoadmap())
    finalize = AsyncMock(return_value={"status": "completed"})
    monkeypatch.setattr(plans, "async_session_maker", Context)
    monkeypatch.setattr(plans, "_build_idol_plan_context", MagicMock(return_value={}))
    monkeypatch.setattr(plans, "_load_session_context", AsyncMock(return_value=session_ctx or {}))
    monkeypatch.setattr(plans, "generate_plan", generated)
    monkeypatch.setattr(plans, "_finalize_generated_plan", finalize)
    assert await plans._run_plan_generation_async("job-1") == {"status": "completed"}
    plan = finalize.await_args.args[2]
    return generated.await_args.kwargs, plan


def _job(**fields):
    values = dict(
        id="job-1", user_id="owner", idol_id="idol-1", session_id=None, plan_id=None,
        idol=SimpleNamespace(name="Ada", domain="computing"),
        created_at=datetime.now(timezone.utc), target_age=24,
        focus="Learn computational thinking", duration_weeks=12, cycle_number=1,
        previous_plan_id=None, generation_checkpoint_json=None,
    )
    values.update(fields)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("fields", "minutes", "hours"),
    [
        ({"weekly_hours": 2, "weekly_minutes": 90}, 90, 2),
        ({"weekly_hours": 1, "weekly_minutes": 60}, 60, 1),
        # A row written before the column existed falls back to whole hours.
        ({"weekly_hours": 2, "weekly_minutes": None}, 120, 2),
    ],
)
async def test_job_below_3h_not_raised(monkeypatch, fields, minutes, hours):
    job = _job(**fields)
    kwargs, plan = await _run_plan_job(monkeypatch, job)
    assert kwargs["weekly_minutes"] == minutes
    assert job.weekly_hours == hours
    assert plan.weekly_minutes == minutes
    assert plan.weekly_hours == hours


@pytest.mark.asyncio
async def test_job_uses_the_confirmed_session_minutes(monkeypatch):
    job = _job(weekly_hours=10, weekly_minutes=600)
    baseline = {"interview_key_set": "v2", "weekly_capacity_minutes": 150,
                "weekly_capacity_hours": 2.5, "weekly_capacity_confirmed": True,
                "answered_keys": ["weekly_hours"]}
    kwargs, plan = await _run_plan_job(
        monkeypatch, job, session_ctx={"learner_baseline": baseline})
    assert kwargs["weekly_minutes"] == 150
    assert (job.weekly_minutes, job.weekly_hours) == (150, 3)
    assert (plan.weekly_minutes, plan.weekly_hours) == (150, 3)


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------


def _plan(**fields):
    now = datetime.now(timezone.utc)
    plan = Plan(
        id="plan-1", user_id="user-1", idol_id=None, target_age=30,
        duration_weeks=12, cycle_number=1, roadmap_json={}, **fields,
    )
    plan.created_at = now
    plan.items = []
    return plan


def test_plan_response_includes_weekly_minutes():
    from app.api.v1 import plans as plans_api

    response = plans_api._plan_to_response(_plan(weekly_hours=5, weekly_minutes=270))
    assert response.weeklyHours == 5
    assert response.weeklyMinutes == 270
    assert response.model_dump()["weeklyMinutes"] == 270

    # Rows from before the migration report their whole hours as minutes.
    legacy = plans_api._plan_to_response(_plan(weekly_hours=8, weekly_minutes=None))
    assert (legacy.weeklyHours, legacy.weeklyMinutes) == (8, 480)


def test_short_mission_item_reports_its_minutes():
    from app.api.v1 import plans as plans_api

    now = datetime.now(timezone.utc)
    item = PlanItem(
        id="item-1", plan_id="plan-1", title="Build short proof", type=PlanItemType.PROJECT,
        description="A short mission.", week_start=1, week_end=1,
        success_metric="Proof passes its rubric.", estimated_hours=1,
        status=PlanItemStatus.NOT_STARTED, progress_percent=0, meta_json={"estimated_minutes": 45},
    )
    item.created_at = item.updated_at = now
    response = plans_api._item_to_response(item)
    assert (response.estimatedHours, response.estimatedMinutes) == (1, 45)


def test_plan_request_accepts_short_weeks():
    from pydantic import ValidationError
    from app.schemas.plan import PlanGenerateRequest

    assert PlanGenerateRequest(idolId="i", targetAge=30, weeklyHours=1).weeklyHours == 1
    assert PlanGenerateRequest(idolId="i", targetAge=30, weeklyMinutes=90).weeklyMinutes == 90
    with pytest.raises(ValidationError):
        PlanGenerateRequest(idolId="i", targetAge=30, weeklyHours=0)
    with pytest.raises(ValidationError):
        PlanGenerateRequest(idolId="i", targetAge=30, weeklyMinutes=45)


def test_next_cycle_keeps_the_parent_minutes():
    from app.api.v1.plans import _next_cycle_fields

    fields = _next_cycle_fields(SimpleNamespace(
        id="p1", cycle_number=1, idol_id="i1", weekly_hours=3, weekly_minutes=150,
        target_age=25, duration_weeks=12))
    assert (fields["weekly_minutes"], fields["weekly_hours"]) == (150, 3)


@pytest.mark.asyncio
async def test_session_job_stores_minutes_and_legacy_hours():
    from app.api.v1 import sessions as sessions_api

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: None)
    session = SimpleNamespace(id="session-1", idol_id="idol-1", user_goal="goal", user_age=30)
    job = await sessions_api._get_or_create_session_plan_job(
        db, session=session, user_id="user-1", weekly_minutes=150, focus="Ship it")
    assert (job.weekly_minutes, job.weekly_hours) == (150, 3)


@pytest.mark.asyncio
async def test_profile_stores_minutes_and_legacy_hours():
    from app.api.v1 import sessions as sessions_api
    from app.models.intake import IntakeSession
    from app.models.user_profile import UserProfile
    from tests.test_interview_profile_persistence import _Database

    profile = UserProfile(id="p1", user_id="user-1")
    await sessions_api._sync_user_profile_from_interview(
        _Database(profile), session=IntakeSession(id="s1", user_id="user-1"),
        user_id="user-1",
        plan_inputs={"interview_key_set": "v2", "weekly_capacity_minutes": 270,
                     "weekly_capacity_hours": 4.5},
    )
    assert (profile.weekly_minutes, profile.weekly_hours) == (270, 5)


# ---------------------------------------------------------------------------
# Interview endpoint: V2 accepts 60-900 minutes, V1 keeps 3-60 hours
# ---------------------------------------------------------------------------


def _v2_thread_awaiting_weekly_answer():
    from app.models.chat import ChatMessage, MessageRole
    from tests.test_interview_streaming import _v2_thread_through

    thread = _v2_thread_through("learning_preferences")
    thread.messages.extend([
        ChatMessage(id="answer-10", thread_id="thread-1", role=MessageRole.USER,
                    content="Worked examples", reply_to_message_id=thread.messages[-1].id),
        ChatMessage(id="question-11", thread_id="thread-1", role=MessageRole.ASSISTANT,
                    content="How many focused hours a week?",
                    response_ui_json={
                        "version": 1, "kind": "number", "min": 1, "max": 15, "step": 0.5,
                        "initial": 4, "unit": "hours / week", "answer_key": "weekly_hours",
                    }),
    ])
    return thread


async def _answer(monkeypatch, thread, content):
    from fastapi import HTTPException  # noqa: F401
    from app.api.v1 import sessions as sessions_api
    from app.models.user import User
    from app.schemas.session import InterviewMessageRequest
    from tests.test_interview_response_ui import (
        _Database, _body_events, _patch_session, _session,
    )

    session = _session(turn=11)
    db = _Database(thread)

    async def question_stream(*_args, **_kwargs):
        yield "What single result do you want in twelve weeks?"

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions_api, "interview_stream", question_stream)
    response = await sessions_api.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content=content, question_id=thread.messages[-1].id),
        db=db,
        current_user=User(id="user-1", email="learner@example.com", password_hash="hash"),
    )
    return db, await _body_events(response)


@pytest.mark.asyncio
@pytest.mark.parametrize("answer", ["1 hours / week", "1.5 hours / week", "2.5 hours / week",
                                    "4.5 hours / week", "4,5"])
async def test_v2_interview_accepts_short_and_half_hour_weeks(monkeypatch, answer):
    from app.models.chat import ChatMessage, MessageRole

    db, events = await _answer(monkeypatch, _v2_thread_awaiting_weekly_answer(), answer)
    assert any(event["type"] == "done" for event in events)
    saved = [item for item in db.added
             if isinstance(item, ChatMessage) and item.role == MessageRole.USER]
    assert saved and saved[0].content == answer


@pytest.mark.asyncio
@pytest.mark.parametrize("answer", ["0.5", "16 hours / week", "4.25 hours", "I am not sure"])
async def test_v2_interview_rejects_out_of_range_minutes(monkeypatch, answer):
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc_info:
        await _answer(monkeypatch, _v2_thread_awaiting_weekly_answer(), answer)
    assert exc_info.value.status_code == 409
    assert exc_info.value.detail["code"] == "invalid_interview_answer"
    assert "1 and 15 hours" in exc_info.value.detail["message"]


@pytest.mark.asyncio
@pytest.mark.parametrize("answer", ["2", "1.5"])
async def test_v1_interview_keeps_rejecting_weeks_under_three_hours(monkeypatch, answer):
    from fastapi import HTTPException
    from tests.test_interview_response_ui import _thread_awaiting_weekly_answer

    with pytest.raises(HTTPException) as exc_info:
        await _answer(monkeypatch, _thread_awaiting_weekly_answer(), answer)
    assert exc_info.value.status_code == 409
    assert exc_info.value.detail["code"] == "invalid_interview_answer"
    assert "3 and 60 hours" in exc_info.value.detail["message"]


# ---------------------------------------------------------------------------
# Prompts and migration
# ---------------------------------------------------------------------------


def test_plan_prompts_receive_minutes_and_a_human_label():
    from app.services.llm.prompt_loader import get_required_placeholders, load_and_render

    for name in ("plan_backbone_generate.txt", "plan_week_generate.txt", "blueprint_generate.txt"):
        required = set(get_required_placeholders(name))
        assert {"weekly_minutes", "weekly_capacity_label"} <= required, name

    params = generator.capacity_prompt_params(60)
    assert params["weekly_minutes"] == "60"
    assert params["weekly_capacity_label"] == "1 h / week (about 9 min a day)"
    assert "45 minutes" in params["capacity_rule"] and "15 minutes" in params["capacity_rule"]
    week = load_and_render("plan_week_generate.txt", {
        "user_goal": "Learn", "user_context": "", "idol_name": "Ada", "idol_domain": "computing",
        "roadmap_thesis": "Thesis", "backbone_week_json": {}, "session_context": "", **params,
    })
    assert "1 h / week (about 9 min a day)" in week
    assert "60 minutes" in week
    assert "{" + "weekly_minutes}" not in week

    whole = generator.capacity_prompt_params(480)
    assert whole["hours_per_week"] == "8"
    assert "whole" in whole["capacity_rule"]


def test_weekly_minutes_migration_adds_and_backfills_the_columns(monkeypatch):
    versions = Path(__file__).resolve().parents[1] / "migrations" / "versions"
    [path] = list(versions.glob("*_weekly_minutes.py"))
    spec = importlib.util.spec_from_file_location("weekly_minutes_migration", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.down_revision == "o6p7q8r9s0t1"

    calls = []
    monkeypatch.setattr(module, "op", SimpleNamespace(
        add_column=lambda table, column: calls.append(("add", table, column.name)),
        execute=lambda sql: calls.append(("execute", str(sql))),
        drop_column=lambda table, column: calls.append(("drop", table, column)),
    ))
    module.upgrade()
    tables = {"plans", "plan_generation_jobs", "user_profiles"}
    assert {(table, name) for kind, table, name in
            [call for call in calls if call[0] == "add"]} == {(t, "weekly_minutes") for t in tables}
    backfills = [call[1] for call in calls if call[0] == "execute"]
    for table in tables:
        assert any(table in sql and "weekly_hours * 60" in sql and "weekly_minutes IS NULL" in sql
                   for sql in backfills), table
    calls.clear()
    module.downgrade()
    assert {(call[1], call[2]) for call in calls} == {(t, "weekly_minutes") for t in tables}


def test_key_sets_are_unchanged():
    assert "weekly_hours" in INTERVIEW_ANSWER_KEYS_V1
    assert "weekly_hours" in INTERVIEW_ANSWER_KEYS_V2
