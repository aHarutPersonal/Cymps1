from app.models.plan import PlanItemType
from app.services.llm.schemas import PlanGenerationResponse
from app.services.planning.generator import (
    _generate_deterministic_items,
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


def test_plan_contract_accepts_complete_capacity_bounded_plan() -> None:
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
    assert any("above the 6-hour cap" in issue for issue in issues)


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
        assert sum(item.estimated_hours for item in items) <= 6
        assert all(item.success_metric for item in items)
