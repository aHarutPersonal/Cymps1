"""``GET /plan-items/{id}/detailed?peek=true`` is a pure read.

The Plan tab peeks at every mission of the week except the one in front of
the learner. A peek returns what a normal read would, but never promotes a
prefetch job onto the foreground worker, never enqueues a new job and never
writes a job row. The default read keeps doing all three.
"""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.api.v1 import plans
from app.models.plan import PlanItem, PlanItemStatus, PlanItemType
from app.schemas.plan import DetailsStatus, ItemProgress

JOB_PREFETCH = "11111111-1111-4111-8111-111111111111"
JOB_NEW = "22222222-2222-4222-8222-222222222222"


def _item(details_json: dict | None = None) -> PlanItem:
    now = datetime.now(timezone.utc)
    return PlanItem(
        id="mission-2",
        plan_id="plan-1",
        title="Write a one-page owner’s memo",
        type=PlanItemType.PROJECT,
        description="A concrete task description for peek coverage.",
        week_start=1,
        week_end=1,
        success_metric="Completed as specified",
        estimated_hours=1,
        status=PlanItemStatus.NOT_STARTED,
        progress_percent=0,
        meta_json=None,
        details_json=details_json,
        created_at=now,
        updated_at=now,
    )


class _Result:
    def __init__(self, scalar_one=None):
        self._scalar_one = scalar_one

    def scalar_one_or_none(self):
        return self._scalar_one


def _job(*, status: str, step: str, age: timedelta = timedelta(0)):
    stamp = datetime.now(timezone.utc) - age
    return SimpleNamespace(
        id=JOB_PREFETCH,
        status=status,
        step=step,
        progress_percent=0,
        error_message=None,
        created_at=stamp,
        updated_at=stamp,
    )


def _db(job=None) -> AsyncMock:
    db = AsyncMock()
    db.add = MagicMock(side_effect=lambda row: setattr(row, "id", JOB_NEW))
    db.execute.return_value = _Result(job)
    return db


async def _read(item: PlanItem, db: AsyncMock, *, peek: bool, ready=False):
    """Run the handler with the item, empty progress and a mocked database."""
    with (
        patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)),
        patch.object(
            plans,
            "_item_progress_snapshot",
            AsyncMock(return_value=(ItemProgress(), False, [])),
        ),
        patch.object(
            plans,
            "_lesson_details_meet_runtime_quality",
            AsyncMock(return_value=ready),
        ),
    ):
        return await plans.get_plan_item_detailed(
            "mission-2",
            db,
            SimpleNamespace(id="user-1"),
            peek=peek,
        )


def test_peek_is_an_optional_query_parameter_defaulting_to_off() -> None:
    route = next(
        r
        for r in plans.items_router.routes
        if getattr(r, "path", "").endswith("/{item_id}/detailed")
    )
    peek = next(p for p in route.dependant.query_params if p.name == "peek")
    assert peek.default is False
    assert peek.required is False


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("status", "step"),
    [("pending", "prefetch_queued"), ("queued", "background_queued")],
)
async def test_peek_does_not_promote_a_prefetch_job(status, step) -> None:
    job = _job(status=status, step=step)
    db = _db(job)

    with (
        patch.object(
            plans, "_promote_prefetched_detail_job", AsyncMock()
        ) as promote,
        patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue,
    ):
        response = await _read(_item(), db, peek=True)

    promote.assert_not_awaited()
    enqueue.assert_not_called()
    db.commit.assert_not_awaited()
    db.add.assert_not_called()
    # The prefetch job is reported as it stands: still waiting.
    assert response.details_status == DetailsStatus.PENDING
    assert response.job_id == JOB_PREFETCH
    assert response.details_step == step
    assert (job.status, job.step) == (status, step)


@pytest.mark.asyncio
async def test_default_read_still_promotes_the_prefetch_job() -> None:
    job = _job(status="pending", step="prefetch_queued")
    db = _db(job)

    with patch.object(
        plans, "_promote_prefetched_detail_job", AsyncMock()
    ) as promote:
        response = await _read(_item(), db, peek=False)

    promote.assert_awaited_once_with(db, job)
    assert response.details_status == DetailsStatus.PENDING
    assert response.job_id == JOB_PREFETCH


@pytest.mark.asyncio
async def test_peek_does_not_enqueue_when_there_is_no_job_and_no_details() -> None:
    db = _db(None)

    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue:
        response = await _read(_item(), db, peek=True)

    enqueue.assert_not_called()
    db.add.assert_not_called()
    db.commit.assert_not_awaited()
    db.refresh.assert_not_awaited()
    # The "preparing" shape the app already understands, with nothing behind it.
    assert response.details_status == DetailsStatus.PENDING
    assert response.job_id is None
    assert response.details is None
    assert response.completed is False
    assert response.details_progress == 0


@pytest.mark.asyncio
async def test_default_read_still_enqueues_when_there_is_no_job() -> None:
    db = _db(None)

    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue:
        response = await _read(_item(), db, peek=False)

    enqueue.assert_called_once()
    assert enqueue.call_args.kwargs["queue"] == "default"
    assert response.details_status == DetailsStatus.PENDING
    assert response.job_id == JOB_NEW


@pytest.mark.asyncio
async def test_peek_does_not_write_a_stale_job_failure() -> None:
    item = _item()
    job = _job(status="queued", step="user_priority", age=timedelta(minutes=30))
    db = _db(job)

    with (
        patch.object(
            plans, "_promote_prefetched_detail_job", AsyncMock()
        ) as promote,
        patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue,
    ):
        peeked = await _read(item, db, peek=True)

    promote.assert_not_awaited()
    enqueue.assert_not_called()
    db.commit.assert_not_awaited()
    # Reported as stopped, exactly as a normal read reports it, but unwritten.
    assert peeked.details_status == DetailsStatus.FAILED
    assert peeked.details_step == "error"
    assert peeked.details_error
    assert (job.status, job.step) == ("queued", "user_priority")

    # The normal read writes the failure down.
    stale = _job(status="queued", step="user_priority", age=timedelta(minutes=30))
    normal_db = _db(stale)
    with patch.object(plans, "_promote_prefetched_detail_job", AsyncMock()):
        normal = await _read(item, normal_db, peek=False)
    assert normal.model_dump() == peeked.model_dump()
    assert stale.status == "failed"
    normal_db.commit.assert_awaited()


@pytest.mark.asyncio
async def test_peek_returns_a_running_job_as_generating() -> None:
    job = _job(status="running", step="generating_lessons")
    db = _db(job)

    response = await _read(_item(), db, peek=True)

    assert response.details_status == DetailsStatus.GENERATING
    assert response.job_id == JOB_PREFETCH
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_peek_returns_ready_details_unchanged() -> None:
    details = {
        "steps": [
            {
                "id": "step_1",
                "title": "Ready lesson",
                "lesson_content": "substance " * 2200,
            },
            {
                "id": "step_2",
                "title": "Ready practice",
                "lesson_content": "practice " * 2200,
            },
        ],
        "_generation": {"job_id": JOB_PREFETCH, "status": "ready"},
    }

    item = _item(details)
    peeked_db = _db(None)
    peeked = await _read(item, peeked_db, peek=True, ready=True)
    normal = await _read(item, _db(None), peek=False, ready=True)

    assert peeked.details_status == DetailsStatus.AVAILABLE
    assert [s.id for s in peeked.details.steps] == ["step_1", "step_2"]
    assert peeked.artifact_job_id == JOB_PREFETCH
    assert peeked.model_dump() == normal.model_dump()
    peeked_db.commit.assert_not_awaited()
    peeked_db.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("status", "step"),
    [("pending", "prefetch_queued"), ("queued", "background_queued")],
)
async def test_peek_never_reports_a_long_queued_prefetch_as_stopped(status, step) -> None:
    """R1-M2 / R2-M5: a prefetch waits on the low-priority queue for as long as
    it takes. A normal read promotes it (refreshing its clock) before the stale
    rule runs; a peek never promotes, so it must not apply the queue-stale rule
    to it either, or the Plan tab shows a healthy prefetch as failed."""
    job = _job(status=status, step=step, age=timedelta(minutes=30))
    db = _db(job)

    with (
        patch.object(plans, "_promote_prefetched_detail_job", AsyncMock()) as promote,
        patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue,
    ):
        response = await _read(_item(), db, peek=True)

    promote.assert_not_awaited()
    enqueue.assert_not_called()
    db.commit.assert_not_awaited()
    assert response.details_status == DetailsStatus.PENDING
    assert response.details_step == step
    assert response.details_error is None
    assert (job.status, job.step) == (status, step)


def test_stale_rule_skips_only_queued_prefetch_jobs_under_peek() -> None:
    old = timedelta(minutes=30)
    prefetch = _job(status="pending", step="prefetch_queued", age=old)
    background = _job(status="queued", step="background_queued", age=old)
    user_queued = _job(status="queued", step="user_priority", age=old)
    running = _job(status="running", step="prefetch_queued", age=timedelta(hours=1))

    assert plans._detail_job_reads_as_stale(prefetch, peek=False)
    assert not plans._detail_job_reads_as_stale(prefetch, peek=True)
    assert not plans._detail_job_reads_as_stale(background, peek=True)
    # Everything else keeps the existing rule, peek or not.
    assert plans._detail_job_reads_as_stale(user_queued, peek=True)
    assert plans._detail_job_reads_as_stale(running, peek=True)
