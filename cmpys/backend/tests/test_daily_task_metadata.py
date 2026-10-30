"""Tests for daily task metadata used by Today and Daily Focus."""

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.api.v1 import daily_tasks
from app.api.v1.daily_tasks import _daily_instructions_for_item, _session_minutes
from app.models.plan import PlanItem, PlanItemType


def test_generated_daily_instructions_use_executable_review():
    """A generated script cannot promise unavailable materials."""
    item = PlanItem(
        id="item-1",
        meta_json={"daily_instructions": "Read chapter 1 and write three notes."},
        details_json={"daily_instructions": "Fallback detail instruction."},
    )

    assert "Open your review" in _daily_instructions_for_item(item)
    assert "chapter 1" not in _daily_instructions_for_item(item)


def test_old_generated_detail_scripts_use_executable_review():
    """Legacy generated prose is retained in storage but replaced in the response."""
    item = PlanItem(
        id="item-1",
        meta_json={},
        details_json={"daily_instructions": "Use the generated detail instructions."},
    )

    assert "Stop and save" in _daily_instructions_for_item(item)
    assert "generated detail instructions" not in _daily_instructions_for_item(item)


@pytest.mark.parametrize(
    ("hours", "meta_minutes", "expected"),
    [
        (1, 15, 5),  # a 60-minute week's rhythm: three 5-minute sessions
        (1, 50, 17),  # under an hour: three sessions: 17, 17, 16 minutes
        (1, None, 20),  # a legacy whole hour: three 20-minute sessions
        (2, 90, 30),  # 90 minutes split into three 30-minute sessions
        (2, None, 40),
        (0, None, 1),  # never below one minute
    ],
)
def test_session_minutes_follow_the_rhythm_cadence(
    hours, meta_minutes, expected, monkeypatch
):
    """A habit's weekly minutes are practised in rhythm_cadence sessions."""
    item = PlanItem(
        id="habit-1",
        estimated_hours=hours,
        meta_json={} if meta_minutes is None else {"estimated_minutes": meta_minutes},
    )

    from datetime import date

    monkeypatch.setattr(
        "app.services.planning.habit_schedule.learning_today",
        lambda: date(2026, 10, 26),
    )
    assert _session_minutes(item) == expected


@pytest.mark.asyncio
async def test_today_view_reports_weekly_and_session_minutes():
    """Today rows carry the week's minutes and one session's minutes."""
    item = PlanItem(
        id="habit-1",
        title="Set a 5-minute timer and read",
        type=PlanItemType.HABIT,
        week_start=1,
        week_end=12,
        estimated_hours=1,
        meta_json={"estimated_minutes": 15},
    )
    plan_result = MagicMock()
    plan_result.scalar_one_or_none.return_value = SimpleNamespace(id="plan-1")
    completions = MagicMock()
    completions.fetchall.return_value = []
    db = AsyncMock()
    db.execute.side_effect = [plan_result, completions]

    with (
        patch.object(
            daily_tasks,
            "_items_and_execution_week",
            AsyncMock(return_value=([item], 1)),
        ),
        patch.object(daily_tasks, "calculate_streak", AsyncMock(return_value=0)),
        patch(
            "app.services.practice.habit_review.review_status",
            AsyncMock(return_value={"available": True}),
        ),
    ):
        response = await daily_tasks.get_today_view(
            "plan-1", db, SimpleNamespace(id="user-1")
        )

    row = response.items[0]
    assert row.estimated_minutes == 15
    assert row.session_minutes == 5
    assert response.model_dump()["items"][0]["session_minutes"] == 5
