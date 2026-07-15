import pytest
from pydantic import ValidationError

from app.models.plan import PlanItemType
from app.schemas.plan import PlanGenerateRequest
from app.services.llm.schemas import PlanBackboneResponse, PlanGenerationResponse
from app.services.planning.generator import (
    _generate_deterministic_items,
    validate_plan_backbone,
    validate_plan_contract,
)


def _task(task_type: str, hours: float) -> dict:
    mission = task_type in {"project", "course", "reading"}
    return {
        "title": f"Specific {task_type} output",
        "description": " ".join(
            ["domain-specific"] * (52 if mission else 32)
        ),
        "type": task_type,
        "estimated_hours": hours,
        "success_metric": "One named artifact and its verification record are saved.",
        "daily_instructions": (
            " ".join(["practice"] * 42) if not mission else None
        ),
    }


def _plan(week_numbers: list[int], *, mission_hours: float = 2) -> PlanGenerationResponse:
    return PlanGenerationResponse.model_validate(
        {
            "roadmap_thesis": "Build evidence through progressive practice.",
            "anti_goals": ["Avoid passive collection without an artifact."],
            "weeks": [
                {
                    "week_number": number,
                    "primary_mission": f"Complete week {number} proof",
                    "binary_tasks": [
                        _task("project", mission_hours),
                        _task("reading", mission_hours),
                        _task("practice", 2),
                    ],
                    "predicted_friction": "Unclear scope",
                    "friction_solution": "Use one explicit rubric",
                }
                for number in week_numbers
            ],
        }
    )


def test_plan_contract_accepts_plan_that_fills_weekly_capacity() -> None:
    assert validate_plan_contract(
        _plan([1, 2]),
        duration_weeks=2,
        hours_per_week=6,
    ) == []


def test_plan_contract_rejects_missing_weeks_and_post_rounding_overflow() -> None:
    issues = validate_plan_contract(
        _plan([1], mission_hours=2.6),
        duration_weeks=2,
        hours_per_week=6,
    )

    assert any("weeks must be exactly" in issue for issue in issues)
    assert any("fill the 6-hour weekly capacity" in issue for issue in issues)


def test_plan_contract_rejects_thin_week_below_declared_capacity() -> None:
    issues = validate_plan_contract(
        _plan([1], mission_hours=1),
        duration_weeks=1,
        hours_per_week=6,
    )

    assert any("stores 4 hours" in issue for issue in issues)
    assert any("fill the 6-hour weekly capacity" in issue for issue in issues)


def test_plan_request_requires_an_honest_minimum_weekly_capacity() -> None:
    with pytest.raises(ValidationError):
        PlanGenerateRequest(
            idolId="idol-1",
            targetAge=30,
            weeklyHours=2,
        )

    request = PlanGenerateRequest(
        idolId="idol-1",
        targetAge=30,
        weeklyHours=3,
    )
    assert request.weeklyHours == 3


def test_backbone_contract_rejects_thin_week_below_declared_capacity() -> None:
    backbone = PlanBackboneResponse.model_validate(
        {
            "roadmap_thesis": "Build evidence through progressive practice.",
            "anti_goals": ["Avoid passive collection without an artifact."],
            "weeks": [
                {
                    "week_number": week,
                    "phase": (
                        "foundation"
                        if week <= 3
                        else "core_skills"
                        if week <= 6
                        else "applied_practice"
                        if week <= 9
                        else "integration"
                    ),
                    "primary_mission": f"Complete proof {week}.",
                    "outcome": f"Proof {week} passes review.",
                    "tasks": [
                        {
                            "title": f"Build proof {week}",
                            "type": "project",
                            "estimated_hours": 3,
                            "success_metric": f"Proof {week} passes its rubric.",
                        },
                        {
                            "title": f"Practice proof skill {week}",
                            "type": "practice",
                            "estimated_hours": 2,
                            "success_metric": f"Four Week {week} drills are saved.",
                        },
                    ],
                    "predicted_friction": "Scope may expand.",
                    "friction_solution": "Freeze the rubric first.",
                }
                for week in range(1, 13)
            ],
        }
    )

    issues = validate_plan_backbone(
        backbone,
        duration_weeks=12,
        hours_per_week=6,
    )

    assert any("stores 5 hours" in issue for issue in issues)
    assert any("fill the 6-hour weekly capacity" in issue for issue in issues)


def test_deterministic_fallback_preserves_weekly_execution_shape() -> None:
    roadmap = _generate_deterministic_items(
        6,
        2,
        idol_name="Ada Lovelace",
        user_goal="learn computational thinking",
    )

    for week in (1, 2):
        items = [item for item in roadmap.items if item.week_start == week]
        assert sum(item.type in {
            PlanItemType.PROJECT,
            PlanItemType.COURSE,
            PlanItemType.READING,
        } for item in items) == 2
        assert sum(item.type in {
            PlanItemType.HABIT,
            PlanItemType.PRACTICE,
        } for item in items) == 1
        assert sum(item.estimated_hours for item in items) == 6
        assert all(
            2 <= item.estimated_hours <= 8
            for item in items
            if item.type
            in {
                PlanItemType.PROJECT,
                PlanItemType.COURSE,
                PlanItemType.READING,
            }
        )
        assert all(item.success_metric for item in items)
