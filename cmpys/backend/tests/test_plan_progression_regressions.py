"""Regression coverage for daily rhythms, week unlocks, and detail failures."""

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api.v1 import plans
from app.api.v1.daily_tasks import _execution_focus_week
from app.models.plan import PlanItem, PlanItemStatus, PlanItemType
from app.schemas.plan import DetailsStatus, ItemProgress
from app.tasks import plans as plan_tasks


def _item(
    item_id: str,
    item_type: PlanItemType,
    week: int,
    *,
    status: PlanItemStatus = PlanItemStatus.NOT_STARTED,
    meta_json: dict | None = None,
) -> PlanItem:
    now = datetime.now(timezone.utc)
    return PlanItem(
        id=item_id,
        plan_id="plan-1",
        title=f"Task {item_id}",
        type=item_type,
        description="A concrete task description for regression coverage.",
        week_start=week,
        week_end=week,
        success_metric="Completed as specified",
        estimated_hours=1,
        status=status,
        progress_percent=0,
        meta_json=meta_json,
        created_at=now,
        updated_at=now,
    )


def test_execution_week_advances_after_week_one_missions_complete() -> None:
    items = [
        _item("mission-1", PlanItemType.PROJECT, 1),
        _item("daily-1", PlanItemType.PRACTICE, 1),
        _item("mission-2", PlanItemType.READING, 2),
        _item("daily-2", PlanItemType.HABIT, 2),
    ]

    assert _execution_focus_week(items, set(), 12) == 1
    assert _execution_focus_week(items, {"mission-1"}, 12) == 2


def test_daily_rhythms_never_gate_execution_week() -> None:
    items = [
        _item("mission-1", PlanItemType.PROJECT, 1),
        _item("practice-1", PlanItemType.PRACTICE, 1),
        _item("mission-2", PlanItemType.COURSE, 2),
    ]

    assert _execution_focus_week(items, {"mission-1"}, 12) == 2


def test_current_plan_response_hydrates_completion_records() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)

    response = plans._item_to_response(
        item,
        completed_item_ids={"mission-1"},
    )

    assert response.status.value == "completed"
    assert response.progressPercent == 100


def test_daily_item_never_uses_permanent_completion_state() -> None:
    item = _item(
        "daily-1",
        PlanItemType.PRACTICE,
        1,
        status=PlanItemStatus.COMPLETED,
    )

    response = plans._item_to_response(
        item,
        completed_item_ids={"daily-1"},
    )

    assert response.status.value == "not_started"
    assert response.progressPercent == 0


@pytest.mark.asyncio
async def test_daily_detail_is_immediate_and_uses_daily_completion() -> None:
    item = _item(
        "practice-1",
        PlanItemType.PRACTICE,
        1,
        meta_json={"daily_instructions": "Practice the drill for twenty minutes."},
    )
    db = AsyncMock()
    db.scalar.return_value = 1
    original_get = plans._get_item_for_user
    plans._get_item_for_user = AsyncMock(return_value=item)
    try:
        response = await plans.get_plan_item_detailed(
            "practice-1",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get

    assert response.details_status == DetailsStatus.AVAILABLE
    assert response.job_id is None
    assert response.completed_today is True
    assert response.daily_instructions == "Practice the drill for twenty minutes."
    db.execute.assert_not_awaited()


class _Result:
    def __init__(self, *, scalars: list | None = None, scalar_one=None):
        self._scalars = scalars or []
        self._scalar_one = scalar_one

    def scalars(self):
        return SimpleNamespace(all=lambda: self._scalars)

    def scalar_one_or_none(self):
        return self._scalar_one


@pytest.mark.asyncio
async def test_current_week_details_publish_in_background_at_high_priority() -> None:
    missions = [
        _item("mission-1", PlanItemType.PROJECT, 1),
        _item("mission-2", PlanItemType.READING, 1),
    ]
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        _Result(scalars=missions),
        _Result(scalars=[]),
    ]

    async def assign_job_ids() -> None:
        for index, call in enumerate(db.add.call_args_list, start=1):
            call.args[0].id = f"detail-job-{index}"

    db.flush.side_effect = assign_job_ids

    with patch(
        "app.tasks.plans.regenerate_plan_item_details.apply_async"
    ) as enqueue:
        job_ids = await plan_tasks._enqueue_plan_week_details_generation_async(
            db,
            plan_id="plan-1",
            user_id="user-1",
            week=1,
            priority="high",
        )

    assert job_ids == ["detail-job-1", "detail-job-2"]
    assert [call.args[0].status for call in db.add.call_args_list] == [
        "queued",
        "queued",
    ]
    assert [call.args[0].step for call in db.add.call_args_list] == [
        "background_queued",
        "background_queued",
    ]
    assert enqueue.call_count == 2
    assert all(
        call.kwargs["queue"] == "high_priority"
        for call in enqueue.call_args_list
    )
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_week_prefetch_reuses_active_jobs_instead_of_duplicating() -> None:
    missions = [
        _item("mission-1", PlanItemType.PROJECT, 2),
        _item("mission-2", PlanItemType.READING, 2),
    ]
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        _Result(scalars=missions),
        _Result(scalars=["mission-1", "mission-2"]),
    ]

    with patch(
        "app.tasks.plans.regenerate_plan_item_details.apply_async"
    ) as enqueue:
        job_ids = await plan_tasks._enqueue_plan_week_details_generation_async(
            db,
            plan_id="plan-1",
            user_id="user-1",
            week=2,
            priority="low",
        )

    assert job_ids == []
    db.add.assert_not_called()
    enqueue.assert_not_called()
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("initial_status", "initial_step"),
    [
        ("pending", "prefetch_queued"),
        ("queued", "background_queued"),
    ],
)
async def test_opening_prefetched_detail_promotes_it_once(
    initial_status: str,
    initial_step: str,
) -> None:
    job = SimpleNamespace(
        id="job-prefetch",
        plan_item_id="mission-1",
        status=initial_status,
        step=initial_step,
        error_message=None,
    )
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(rowcount=1)

    with patch(
        "app.tasks.plans.regenerate_plan_item_details.apply_async"
    ) as enqueue:
        result = await plans._promote_prefetched_detail_job(db, job)

    assert result == "promoted"
    assert job.status == "queued"
    enqueue.assert_called_once_with(
        args=["job-prefetch"], queue="high_priority"
    )
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_prefetch_publish_failure_becomes_terminal() -> None:
    job = SimpleNamespace(
        id="job-prefetch",
        plan_item_id="mission-1",
        status="pending",
        step="prefetch_queued",
        error_message=None,
    )
    db = AsyncMock()
    db.execute.side_effect = [
        SimpleNamespace(rowcount=1),
        SimpleNamespace(rowcount=1),
    ]

    with patch(
        "app.tasks.plans.regenerate_plan_item_details.apply_async",
        side_effect=RuntimeError("broker unavailable"),
    ):
        result = await plans._promote_prefetched_detail_job(db, job)

    assert result == "failed"
    assert job.status == "failed"
    assert db.commit.await_count == 2


@pytest.mark.asyncio
async def test_failed_detail_job_is_returned_instead_of_requeued_forever() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    failed_job = SimpleNamespace(
        id="job-1",
        status="failed",
        step="error",
        progress_percent=60,
        error_message="provider failed",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalars=[]),
        _Result(scalar_one=failed_job),
    ]
    original_get = plans._get_item_for_user
    original_progress = plans._compute_item_progress
    plans._get_item_for_user = AsyncMock(return_value=item)
    plans._compute_item_progress = AsyncMock(return_value=(ItemProgress(), False))
    try:
        response = await plans.get_plan_item_detailed(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get
        plans._compute_item_progress = original_progress

    assert response.details_status == DetailsStatus.FAILED
    assert response.job_id == "job-1"
    assert response.details_error
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_completed_legacy_mission_never_enqueues_or_polls_details() -> None:
    item = _item(
        "mission-complete",
        PlanItemType.PROJECT,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    db = AsyncMock()
    db.execute.return_value = _Result(scalars=[])
    original_get = plans._get_item_for_user
    original_progress = plans._compute_item_progress
    plans._get_item_for_user = AsyncMock(return_value=item)
    plans._compute_item_progress = AsyncMock(
        return_value=(ItemProgress(percent=100), True)
    )
    try:
        response = await plans.get_plan_item_detailed(
            "mission-complete",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get
        plans._compute_item_progress = original_progress

    assert response.completed is True
    assert response.details_status == DetailsStatus.AVAILABLE
    assert response.job_id is None
    assert db.execute.await_count == 1
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_stale_detail_job_stops_and_requires_explicit_retry() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    stale_time = datetime(2020, 1, 1, tzinfo=timezone.utc)
    stale_job = SimpleNamespace(
        id="job-stale",
        status="running",
        step="generating",
        progress_percent=60,
        error_message=None,
        created_at=stale_time,
        updated_at=stale_time,
    )
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalars=[]),
        _Result(scalar_one=stale_job),
    ]
    original_get = plans._get_item_for_user
    original_progress = plans._compute_item_progress
    plans._get_item_for_user = AsyncMock(return_value=item)
    plans._compute_item_progress = AsyncMock(return_value=(ItemProgress(), False))
    try:
        response = await plans.get_plan_item_detailed(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get
        plans._compute_item_progress = original_progress

    assert response.details_status == DetailsStatus.FAILED
    assert stale_job.status == "failed"
    assert db.add.call_count == 0
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_detail_retry_reuses_an_active_job() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    now = datetime.now(timezone.utc)
    active_job = SimpleNamespace(
        id="job-active",
        status="running",
        created_at=now,
        updated_at=now,
    )
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=active_job)
    original_get = plans._get_item_for_user
    get_item = AsyncMock(return_value=item)
    plans._get_item_for_user = get_item
    try:
        response = await plans.regenerate_item_details(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get

    assert response.job_id == "job-active"
    assert db.add.call_count == 0
    db.commit.assert_not_awaited()
    assert get_item.await_args.kwargs["for_update"] is True


@pytest.mark.asyncio
async def test_detail_retry_does_not_enqueue_when_lesson_is_already_ready() -> None:
    item = _item("mission-ready", PlanItemType.PROJECT, 1)
    item.details_json = {
        "steps": [
            {
                "id": f"step-{index}",
                "lesson_content": "word " * 2200,
            }
            for index in range(3)
        ]
    }
    db = AsyncMock()
    original_get = plans._get_item_for_user
    plans._get_item_for_user = AsyncMock(return_value=item)
    try:
        with patch(
            "app.tasks.plans.regenerate_plan_item_details.apply_async"
        ) as enqueue:
            response = await plans.regenerate_item_details(
                "mission-ready",
                db,
                SimpleNamespace(id="user-1"),
            )
    finally:
        plans._get_item_for_user = original_get

    assert response.job_id == ""
    enqueue.assert_not_called()
    db.execute.assert_not_awaited()
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_detail_retry_does_not_enqueue_an_authoritatively_completed_item() -> None:
    item = _item("mission-completed", PlanItemType.PROJECT, 1)
    completion = SimpleNamespace(id="completion-1")
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalar_one=None),  # no active detail job
        _Result(scalar_one=completion),  # authoritative completion record
    ]
    original_get = plans._get_item_for_user
    plans._get_item_for_user = AsyncMock(return_value=item)
    try:
        with patch(
            "app.tasks.plans.regenerate_plan_item_details.apply_async"
        ) as enqueue:
            response = await plans.regenerate_item_details(
                "mission-completed",
                db,
                SimpleNamespace(id="user-1"),
            )
    finally:
        plans._get_item_for_user = original_get

    assert response.job_id == ""
    enqueue.assert_not_called()
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_detail_retry_surfaces_prefetch_publish_failure_as_503() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    pending_job = SimpleNamespace(id="job-pending", status="pending")
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=pending_job)
    original_get = plans._get_item_for_user
    original_promote = plans._promote_prefetched_detail_job
    plans._get_item_for_user = AsyncMock(return_value=item)
    plans._promote_prefetched_detail_job = AsyncMock(return_value="failed")
    try:
        with pytest.raises(HTTPException) as exc_info:
            await plans.regenerate_item_details(
                "mission-1",
                db,
                SimpleNamespace(id="user-1"),
            )
    finally:
        plans._get_item_for_user = original_get
        plans._promote_prefetched_detail_job = original_promote

    assert exc_info.value.status_code == 503
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_detail_generation_lock_uses_owned_plan_item_row() -> None:
    item = _item("mission-locked", PlanItemType.PROJECT, 1)

    class Result:
        def scalar_one_or_none(self):
            return item

    class Database:
        statement = None

        async def execute(self, statement):
            self.statement = statement
            return Result()

    db = Database()
    result = await plans._get_item_for_user(
        db,
        "mission-locked",
        "user-1",
        for_update=True,
    )

    assert result is item
    assert db.statement._for_update_arg is not None
    assert "plans.user_id" in str(db.statement)
    assert "user-1" in db.statement.compile().params.values()
