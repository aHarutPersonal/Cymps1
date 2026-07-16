from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest

from app.models.idol import Idol
from app.models.plan import Plan, PlanItem, PlanItemType
from app.services.llm.schemas import PlanWeek
from app.tasks import plans as plan_tasks


class _Result:
    def __init__(self, *, scalars=None, scalar_one=None):
        self._scalars = scalars or []
        self._scalar_one = scalar_one

    def scalars(self):
        return SimpleNamespace(all=lambda: self._scalars)

    def scalar_one_or_none(self):
        return self._scalar_one


def _backbone_week() -> dict:
    return {
        "week_number": 2,
        "phase": "foundation",
        "primary_mission": "Build a second proof.",
        "outcome": "A reviewed second artifact exists.",
        "tasks": [
            {
                "title": "Build artifact 2",
                "type": "project",
                "estimated_hours": 3,
                "success_metric": "Artifact 2 passes its rubric.",
            },
            {
                "title": "Practice technique 2",
                "type": "practice",
                "estimated_hours": 2,
                "success_metric": "Four week-2 drills are logged.",
            },
        ],
        "predicted_friction": "The scope may expand.",
        "friction_solution": "Use one explicit completion rubric.",
    }


@pytest.mark.asyncio
async def test_future_week_enriches_placeholders_in_place(monkeypatch) -> None:
    plan = Plan(
        id="plan-1",
        user_id="user-1",
        idol_id="idol-1",
        target_age=30,
        duration_weeks=12,
        weekly_hours=5,
        roadmap_json={
            "roadmap_thesis": "Build evidence progressively.",
            "backbone_weeks": [_backbone_week()],
        },
    )
    plan.idol = Idol(id="idol-1", name="Ada Lovelace", domain="computing")
    items = [
        PlanItem(
            id=f"item-{index}",
            plan_id="plan-1",
            title=title,
            type=item_type,
            description="Backbone description",
            week_start=2,
            week_end=2,
            success_metric="Backbone metric",
            estimated_hours=hours,
            meta_json={
                "backbone_task_index": index,
                "week_content_status": "backbone",
            },
        )
        for index, (title, item_type, hours) in enumerate(
            [
                ("Build artifact 2", PlanItemType.PROJECT, 3),
                ("Practice technique 2", PlanItemType.PRACTICE, 2),
            ]
        )
    ]
    expanded = PlanWeek.model_validate(
        {
            "week_number": 2,
            "primary_mission": "Produce and review the second computational artifact.",
            "binary_tasks": [
                {
                    "title": "Build and review artifact 2",
                    "description": "A complete execution-ready mission description.",
                    "type": "project",
                    "estimated_hours": 3,
                    "success_metric": "Artifact 2 passes its rubric.",
                },
                {
                    "title": "Run four technique drills",
                    "description": "A complete daily rhythm description.",
                    "type": "practice",
                    "estimated_hours": 2,
                    "success_metric": "Four week-2 drills are logged.",
                    "daily_instructions": "Run the approved drill and save its evidence.",
                },
            ],
            "predicted_friction": "The artifact may grow beyond its rubric.",
            "friction_solution": "Freeze scope before the first implementation pass.",
        }
    )
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalars=items),
        _Result(
            scalar_one=SimpleNamespace(
                goals=["learn computational thinking"],
                interests=["software"],
                learning_preferences=["hands-on"],
            )
        ),
        _Result(scalars=items),
    ]
    monkeypatch.setattr(
        plan_tasks,
        "_load_session_context",
        AsyncMock(return_value={}),
    )
    generate_week = AsyncMock(return_value=expanded)
    monkeypatch.setattr(
        "app.services.planning.generator.generate_plan_week_from_backbone",
        generate_week,
    )

    result = await plan_tasks._prepare_plan_week_items_async(
        db,
        plan=plan,
        user_id="user-1",
        week=2,
    )

    assert result == "ready"
    assert [item.id for item in items] == ["item-0", "item-1"]
    assert [item.title for item in items] == [
        "Build and review artifact 2",
        "Run four technique drills",
    ]
    assert all(item.meta_json["week_content_status"] == "ready" for item in items)
    assert items[1].meta_json["daily_instructions"] == (
        "Run the approved drill and save its evidence."
    )
    assert generate_week.await_count == 1
    # Lease commit, read-transaction release before the model call, and final
    # in-place update commit.
    assert db.commit.await_count == 3


def test_week_prefetch_retries_transient_preparation_failure(monkeypatch) -> None:
    task = plan_tasks.prefetch_plan_week_details
    run_prefetch = AsyncMock(return_value={"status": "failed", "jobs": []})
    monkeypatch.setattr(
        plan_tasks,
        "_prefetch_plan_week_details_async",
        run_prefetch,
    )
    retry = Mock(side_effect=RuntimeError("retry requested"))
    monkeypatch.setattr(task, "retry", retry)

    with pytest.raises(RuntimeError, match="retry requested"):
        task.run("plan-1", "user-1", 2, priority="low")

    retry.assert_called_once()
    assert retry.call_args.kwargs["countdown"] == 60
