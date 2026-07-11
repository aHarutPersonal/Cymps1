"""Structural guarantees for LLM-generated plans."""

import pytest
from pydantic import ValidationError

from app.services.llm.schemas import PlanWeek


def _task(task_type: str) -> dict:
    return {
        "title": f"A {task_type} task",
        "description": "A sufficiently detailed and measurable plan task.",
        "type": task_type,
        "estimated_hours": 1,
    }


def test_plan_week_requires_daily_rhythm() -> None:
    with pytest.raises(ValidationError, match="daily rhythm"):
        PlanWeek(
            week_number=1,
            primary_mission="Build the foundation",
            binary_tasks=[_task("project"), _task("reading")],
        )


def test_plan_week_requires_primary_mission() -> None:
    with pytest.raises(ValidationError, match="primary mission"):
        PlanWeek(
            week_number=1,
            primary_mission="Build the foundation",
            binary_tasks=[_task("habit"), _task("practice")],
        )


def test_plan_week_accepts_mission_and_daily_rhythm() -> None:
    week = PlanWeek(
        week_number=1,
        primary_mission="Build the foundation",
        binary_tasks=[_task("project"), _task("habit")],
    )

    assert [task.type for task in week.binary_tasks] == ["project", "habit"]
