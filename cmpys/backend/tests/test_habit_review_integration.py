"""Opt-in real PostgreSQL flow; all synthetic records roll back together."""

import os
from datetime import date, datetime, timedelta, timezone
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from app.api.v1 import daily_tasks, plans, practice
from app.models import User, Plan, PlanItem, PlanItemType, LessonPractice
from app.services.planning import habit_schedule
from app.services.practice import habit_review
from app.services.practice.contracts import (
    Workbook,
    DraftRequest,
    SubmitRequest,
    lesson_version,
)


@pytest.mark.asyncio
@pytest.mark.skipif(
    not os.environ.get("HABIT_TEST_DATABASE_URL"),
    reason="Opt-in isolated PostgreSQL test",
)
async def test_checked_habit_flow_uses_real_persistence_and_preserves_lesson():
    engine = create_async_engine(os.environ["HABIT_TEST_DATABASE_URL"])
    day = date(2026, 10, 26)
    try:
        async with engine.connect() as connection:
            outer = await connection.begin()
            try:
                async with AsyncSession(
                    connection,
                    expire_on_commit=False,
                    join_transaction_mode="create_savepoint",
                ) as db:
                    owner = User(
                        email=f"habit-review-{uuid4().hex}@example.invalid",
                        password_hash="synthetic-unused-hash",
                    )
                    db.add(owner)
                    await db.flush()
                    plan = Plan(
                        user_id=owner.id,
                        target_age=30,
                        duration_weeks=2,
                        weekly_hours=6,
                        weekly_minutes=360,
                    )
                    db.add(plan)
                    await db.flush()
                    step = {
                        "id": "s1",
                        "title": "Subtract expenses",
                        "lesson_content": "Subtract expenses from receipts to find the remainder.",
                    }
                    mission = PlanItem(
                        plan_id=plan.id,
                        title="Use the two amounts",
                        type=PlanItemType.COURSE,
                        description="A synthetic taught lesson",
                        week_start=1,
                        week_end=1,
                        estimated_hours=5,
                        success_metric="Explain the remainder",
                        details_json={"steps": [step]},
                    )
                    routine = PlanItem(
                        plan_id=plan.id,
                        title="Review the taught method",
                        type=PlanItemType.PRACTICE,
                        description="Recall, solve and correct",
                        week_start=1,
                        week_end=1,
                        estimated_hours=1,
                        success_metric="Save a checked attempt",
                        meta_json={"estimated_minutes": 60},
                    )
                    db.add_all([mission, routine])
                    await db.flush()
                    activity = {
                        "id": "case",
                        "title": "Calculate a remainder",
                        "kind": "practice",
                        "instructions": "A fictional shop receives 12 units and spends 5 units. Calculate the remaining units using the supplied data.",
                        "data": [
                            {"id": "received", "label": "Received", "value": 12},
                            {"id": "spent", "label": "Spent", "value": 5},
                        ],
                        "fields": [
                            {
                                "id": "remaining",
                                "label": "Units remaining",
                                "kind": "number",
                                "expression": "received-spent",
                            }
                        ],
                        "hint": "Subtract the amount spent from the amount received.",
                        "worked_solution": "Twelve units were received and five were spent. Subtract five from twelve; seven units remain.",
                        "minutes_min": 3,
                        "minutes_max": 6,
                    }
                    workbook = Workbook.model_validate(
                        {
                            "title": "Source practice",
                            "activities": [
                                activity,
                                {**activity, "id": "transfer", "kind": "transfer"},
                            ],
                        }
                    )
                    source = LessonPractice(
                        user_id=owner.id,
                        plan_item_id=mission.id,
                        step_id="s1",
                        lesson_version=lesson_version(mission, step),
                        state="ready",
                        revision=1,
                        workbook_json=workbook.model_dump(),
                        answers_json={"case.remaining": "7"},
                        attempts_json=[
                            {
                                "request_id": "original-attempt",
                                "activity_id": "case",
                                "answers": {"remaining": "7"},
                                "passed": True,
                                "assisted": False,
                                "feedback": [],
                                "submitted_at": datetime.combine(
                                    day - timedelta(days=3),
                                    datetime.min.time(),
                                    tzinfo=timezone.utc,
                                ).isoformat(),
                            }
                        ],
                        hints_json=[],
                    )
                    db.add(source)
                    await db.commit()
                    original = dict(source.answers_json)
                    provider = AsyncMock(
                        side_effect=AssertionError(
                            "This flow must never call a provider"
                        )
                    )
                    with (
                        patch.object(habit_schedule, "learning_today", lambda: day),
                        patch.object(daily_tasks, "learning_today", lambda: day),
                        patch.object(habit_review, "learning_today", lambda: day),
                        patch.object(practice, "generate_workbook", provider),
                        patch.object(practice, "review_text", provider),
                    ):
                        today = await daily_tasks.get_today_view(plan.id, db, owner)
                        assert today.total_today == 1
                        assert today.items[0].session_minutes == 20
                        detail = await plans.get_plan_item_detailed(
                            routine.id, db, owner, peek=True
                        )
                        assert detail.habit_review["available"] is True
                        key = detail.habit_review["step_id"]
                        state = await practice.prepare_practice(
                            routine.id, key, db, owner
                        )
                        assert state["state"] == "ready"
                        field = state["workbook"]["activities"][0]
                        assert "worked_solution" not in field
                        assert "expression" not in field["fields"][0]
                        answer_key = field["id"] + ".remaining"
                        state = await practice.save_draft(
                            routine.id,
                            key,
                            DraftRequest(
                                revision=state["revision"], answers={answer_key: "8"}
                            ),
                            db,
                            owner,
                        )
                        state = await practice.submit_practice(
                            routine.id,
                            key,
                            SubmitRequest(
                                revision=state["revision"],
                                request_id="wrong-attempt",
                                activity_id=field["id"],
                            ),
                            db,
                            owner,
                        )
                        assert state["attempts"][-1]["passed"] is False
                        state = await practice.get_hint(
                            routine.id,
                            key,
                            SubmitRequest(
                                revision=state["revision"],
                                request_id="solution-hint",
                                activity_id=field["id"],
                            ),
                            db,
                            owner,
                            solution=True,
                        )
                        assert "seven" in state["hints"][-1]["content"]
                        state = await practice.save_draft(
                            routine.id,
                            key,
                            DraftRequest(
                                revision=state["revision"], answers={answer_key: "7"}
                            ),
                            db,
                            owner,
                        )
                        state = await practice.submit_practice(
                            routine.id,
                            key,
                            SubmitRequest(
                                revision=state["revision"],
                                request_id="corrected-attempt",
                                activity_id=field["id"],
                            ),
                            db,
                            owner,
                        )
                        assert state["complete"] is True
                        assert (
                            state["learning_evidence"]["status"]
                            == "review_needs_practice"
                        )
                        await plans.save_daily_reflection(
                            routine.id,
                            plans.DailyReflectionRequest(
                                text="Subtract the expense instead of adding it.",
                                session_date=day,
                            ),
                            db,
                            owner,
                        )
                        completion = await daily_tasks.toggle_daily_completion(
                            routine.id, db, owner
                        )
                        assert completion.completed is True
                        today = await daily_tasks.get_today_view(plan.id, db, owner)
                        assert today.completed_today == 1
                        await db.refresh(source)
                        assert source.answers_json == original
                        assert len(source.attempts_json) == 1
                        assert not (routine.meta_json or {}).get("practice_versions")
                        provider.assert_not_called()
            finally:
                await outer.rollback()
    finally:
        await engine.dispose()
