"""R2-I1: completion requests can state the desired state, idempotently.

A retry after a committed-but-lost response used to toggle the step (and the
mission) back to incomplete. Both endpoints now accept an optional ``complete``
query parameter: absent keeps today's toggle; present sets exactly that state,
and a request whose state already holds returns it with no side effect.
"""

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.api.v1 import plans
from app.models.plan import PlanItem, PlanItemStatus, PlanItemType
from app.schemas.plan import ItemProgress

JOB = "33333333-3333-4333-8333-333333333333"
DONE_AT = datetime(2026, 10, 1, 12, 0, tzinfo=timezone.utc)


def _item(*, status=PlanItemStatus.NOT_STARTED) -> PlanItem:
    now = datetime.now(timezone.utc)
    return PlanItem(
        id="mission-1",
        plan_id="plan-1",
        title="Value one car wash",
        type=PlanItemType.PROJECT,
        description="A concrete mission for completion coverage.",
        week_start=1,
        week_end=1,
        success_metric="A written valuation",
        estimated_hours=2,
        status=status,
        progress_percent=0,
        details_json={
            "steps": [
                {"id": "step_1", "lesson_content": "substance " * 2200},
                {"id": "step_2", "lesson_content": "practice " * 2200},
            ],
            "_generation": {"job_id": JOB, "status": "ready"},
        },
        created_at=now,
        updated_at=now,
    )


class _Result:
    def __init__(self, scalar_one=None, scalars=None):
        self._scalar_one = scalar_one
        self._scalars = scalars or []

    def scalar_one_or_none(self):
        return self._scalar_one

    def scalars(self):
        return SimpleNamespace(all=lambda: self._scalars)


def _db(*results) -> AsyncMock:
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.return_value = DONE_AT
    db.execute.side_effect = list(results)
    return db


def _patches(item, *, progress, item_completed, plan_state=(False, 1)):
    return (
        patch.object(
            plans,
            "_lock_plan_item_toggle_state",
            AsyncMock(return_value=(SimpleNamespace(id="plan-1", completed_at=None), item, None)),
        ),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(return_value=(progress, item_completed)),
        ),
        patch.object(plans, "_plan_completion_state", AsyncMock(return_value=plan_state)),
        patch.object(plans, "_reconcile_plan_completion", AsyncMock(return_value=plan_state)),
        patch.object(plans, "_require_completion_artifact_ready", AsyncMock()),
        patch.object(plans, "_lesson_details_meet_runtime_quality", AsyncMock(return_value=True)),
    )


def _route(path_suffix: str):
    return next(
        route
        for route in plans.items_router.routes
        if getattr(route, "path", "").endswith(path_suffix)
    )


@pytest.mark.parametrize("suffix", ["/{item_id}/toggle-complete", "/{item_id}/steps/{step_id}/toggle"])
def test_complete_is_an_optional_query_parameter(suffix) -> None:
    param = next(p for p in _route(suffix).dependant.query_params if p.name == "complete")
    assert param.required is False
    assert param.default is None


@pytest.mark.asyncio
async def test_completing_an_already_complete_mission_changes_nothing() -> None:
    item = _item(status=PlanItemStatus.COMPLETED)
    completion = SimpleNamespace(completed_at=DONE_AT)
    db = _db(_Result(scalar_one=completion))
    progress = ItemProgress(completed_steps=2, total_steps=2, percent=100)
    lock, compute, state, reconcile, ready, quality = _patches(
        item, progress=progress, item_completed=True, plan_state=(True, 0)
    )
    with lock, compute, state, reconcile as reconciled, ready as require_ready, quality:
        response = await plans.toggle_item_complete(
            "mission-1", db, SimpleNamespace(id="user-1"), artifact_job_id=JOB, complete=True
        )

    assert response.completed is True
    assert response.progress == progress
    assert (response.planComplete, response.missionTasksRemaining) == (True, 0)
    assert completion.completed_at == DONE_AT  # not un-completed
    assert item.status == PlanItemStatus.COMPLETED
    db.add.assert_not_called()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()
    reconciled.assert_not_awaited()  # no plan stamp write
    require_ready.assert_not_awaited()


@pytest.mark.asyncio
async def test_uncompleting_an_incomplete_mission_changes_nothing() -> None:
    item = _item()
    db = _db(_Result(scalar_one=None))
    progress = ItemProgress(completed_steps=1, total_steps=2, percent=50)
    lock, compute, state, reconcile, ready, quality = _patches(
        item, progress=progress, item_completed=False
    )
    with lock, compute, state, reconcile as reconciled, ready, quality:
        response = await plans.toggle_item_complete(
            "mission-1", db, SimpleNamespace(id="user-1"), artifact_job_id=JOB, complete=False
        )

    assert response.completed is False
    assert (response.planComplete, response.missionTasksRemaining) == (False, 1)
    db.add.assert_not_called()
    db.commit.assert_not_awaited()
    reconciled.assert_not_awaited()


@pytest.mark.asyncio
async def test_completing_an_incomplete_mission_still_completes_it() -> None:
    item = _item()
    db = _db(_Result(scalar_one=None), _Result(scalars=[]))
    progress = ItemProgress(completed_steps=2, total_steps=2, percent=100)
    lock, compute, state, reconcile, ready, quality = _patches(
        item, progress=progress, item_completed=True
    )
    with lock, compute, state, reconcile, ready, quality:
        response = await plans.toggle_item_complete(
            "mission-1", db, SimpleNamespace(id="user-1"), artifact_job_id=JOB, complete=True
        )

    assert response.completed is True
    assert item.status == PlanItemStatus.COMPLETED
    db.commit.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_uncomplete_request_on_a_complete_mission_still_uncompletes_it() -> None:
    item = _item(status=PlanItemStatus.COMPLETED)
    completion = SimpleNamespace(completed_at=DONE_AT)
    db = _db(_Result(scalar_one=completion))
    progress = ItemProgress(completed_steps=2, total_steps=2, percent=100)
    lock, compute, state, reconcile, ready, quality = _patches(
        item, progress=progress, item_completed=False
    )
    with lock, compute, state, reconcile, ready, quality:
        response = await plans.toggle_item_complete(
            "mission-1", db, SimpleNamespace(id="user-1"), artifact_job_id=JOB, complete=False
        )

    assert response.completed is False and completion.completed_at is None
    db.commit.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_retried_finish_of_a_completed_last_step_keeps_step_and_mission_done() -> None:
    """The reader's finish committed, the response was lost, the app retries."""
    item = _item(status=PlanItemStatus.COMPLETED)
    step_completion = SimpleNamespace(completed_at=DONE_AT)
    db = _db(_Result(scalar_one=step_completion))
    progress = ItemProgress(completed_steps=2, total_steps=2, percent=100)
    lock, compute, state, reconcile, ready, quality = _patches(
        item, progress=progress, item_completed=True
    )
    with (
        lock, compute, state, reconcile as reconciled, ready as require_ready, quality,
        patch("app.tasks.plans.prefetch_plan_week_details.apply_async") as prefetch,
    ):
        response = await plans.toggle_step_complete(
            "mission-1", "step_2", db, SimpleNamespace(id="user-1"),
            artifact_job_id=JOB, complete=True,
        )

    assert response.step_id == "step_2"
    assert response.completed is True
    assert response.item_completed is True
    assert response.progress == progress
    assert step_completion.completed_at == DONE_AT
    db.add.assert_not_called()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()
    reconciled.assert_not_awaited()
    require_ready.assert_not_awaited()
    prefetch.assert_not_called()


@pytest.mark.asyncio
async def test_uncompleting_an_incomplete_step_changes_nothing() -> None:
    item = _item()
    db = _db(_Result(scalar_one=None))
    progress = ItemProgress(completed_steps=0, total_steps=2, percent=0)
    lock, compute, state, reconcile, ready, quality = _patches(
        item, progress=progress, item_completed=False
    )
    with lock, compute, state, reconcile, ready, quality:
        response = await plans.toggle_step_complete(
            "mission-1", "step_1", db, SimpleNamespace(id="user-1"),
            artifact_job_id=JOB, complete=False,
        )

    assert response.completed is False and response.item_completed is False
    db.add.assert_not_called()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_without_complete_the_step_endpoint_still_toggles() -> None:
    """An old client (no parameter) keeps the pure toggle."""
    item = _item()
    step_completion = SimpleNamespace(completed_at=DONE_AT)
    db = _db(_Result(scalar_one=step_completion), _Result(scalar_one=None))
    progress = ItemProgress(completed_steps=0, total_steps=2, percent=0)
    lock, compute, state, reconcile, ready, quality = _patches(
        item, progress=progress, item_completed=False
    )
    with lock, compute, state, reconcile, ready, quality:
        response = await plans.toggle_step_complete(
            "mission-1", "step_1", db, SimpleNamespace(id="user-1"), artifact_job_id=JOB,
        )

    assert response.completed is False
    assert step_completion.completed_at is None
    db.commit.assert_awaited_once_with()
