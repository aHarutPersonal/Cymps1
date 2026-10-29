"""One-ahead window: completion trigger, enqueue paths and the detailed response contract."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from sqlalchemy.sql.dml import Update

from app.api.v1 import plans
from app.models.plan import PlanItem, PlanItemStatus, PlanItemType
from app.schemas.plan import DetailsStatus, ItemProgress
from app.services.planning.generation_window import (
    GenerationWindow, window_queue, window_requeue_decision, window_response,
)
from app.tasks import plans as plan_tasks
from tests.test_short_tutorial_pipeline import complete_step, outline

JOB = "44444444-4444-4444-8444-444444444444"
OTHER_JOB = "55555555-5555-4555-8555-555555555555"
DONE_AT = datetime(2026, 10, 1, 12, 0, tzinfo=timezone.utc)


def _details(ready=("step_1", "step_2"), count=4):
    raw = outline(count)
    steps = [complete_step(step) if step["id"] in ready else step for step in raw["steps"]]
    return {**raw, "steps": steps, "_generation": {
        "status": "partial", "job_id": JOB, "ready_step_ids": list(ready),
        "outline": {"lesson_format": "tutorial_v1"},
    }}


def _item(details=None) -> PlanItem:
    now = datetime.now(timezone.utc)
    return PlanItem(
        id="mission-1", plan_id="plan-1", title="Value one car wash", type=PlanItemType.PROJECT,
        description="A concrete mission.", week_start=1, week_end=1, success_metric="A valuation",
        estimated_hours=1, status=PlanItemStatus.IN_PROGRESS, progress_percent=0,
        details_json=details if details is not None else _details(), created_at=now, updated_at=now,
    )


def _job(status="completed", step="waiting_for_learner", job_id=JOB, age=timedelta(hours=3)):
    stamp = datetime.now(timezone.utc) - age
    return SimpleNamespace(id=job_id, status=status, step=step, progress_percent=100,
                           error_message=None, created_at=stamp, updated_at=stamp)


class _Result:
    def __init__(self, scalar_one=None, scalars=None, rowcount=1):
        self._scalar_one = scalar_one
        self._scalars = scalars or []
        self.rowcount = rowcount

    def scalar_one_or_none(self):
        return self._scalar_one

    def scalars(self):
        return SimpleNamespace(all=lambda: self._scalars)


# --- window rules ---------------------------------------------------------

def test_requeue_decision_reuses_active_jobs_and_requeues_only_the_parked_artifact_job():
    window = GenerationWindow("step_2", "step_3")
    ready = {"step_1", "step_2"}
    assert window_requeue_decision(window=window, ready_step_ids=ready, latest_job=_job(),
                                   artifact_job_id=JOB) == "requeue"
    assert window_requeue_decision(window=window, ready_step_ids=ready | {"step_3"}, latest_job=_job(),
                                   artifact_job_id=JOB) == "none"  # Next already ready.
    assert window_requeue_decision(window=window, ready_step_ids=ready, latest_job=_job("running", "generating_lessons"),
                                   artifact_job_id=JOB) == "reuse"
    assert window_requeue_decision(window=window, ready_step_ids=ready, latest_job=_job("failed", "error"),
                                   artifact_job_id=JOB) == "none"  # Today's error stays.
    assert window_requeue_decision(window=window, ready_step_ids=ready, latest_job=_job(job_id=OTHER_JOB),
                                   artifact_job_id=JOB) == "none"
    assert window_queue(window, ready) == "low_priority"
    assert window_queue(window, {"step_1"}) == "default"  # The learner is waiting.


def test_window_response_contract():
    steps = ["step_1", "step_2", "step_3"]
    assert window_response(step_ids=steps, ready_step_ids=["step_1", "step_2"], completed_step_ids=[],
                           job_active=False) == {
        "current_step_id": "step_1", "next_step_id": "step_2", "waiting_for_learner": True}
    assert window_response(step_ids=steps, ready_step_ids=["step_1", "step_2"], completed_step_ids=[],
                           job_active=True)["waiting_for_learner"] is False
    assert window_response(step_ids=steps, ready_step_ids=["step_1", "step_2"], completed_step_ids=["step_1"],
                           job_active=False) == {
        "current_step_id": "step_2", "next_step_id": "step_3", "waiting_for_learner": False}
    assert window_response(step_ids=steps, ready_step_ids=steps, completed_step_ids=["step_1", "step_2"],
                           job_active=False) == {
        "current_step_id": "step_3", "next_step_id": None, "waiting_for_learner": False}


# --- ensure (the completion trigger) --------------------------------------

def _ensure_db(item, latest, *, rowcount=1):
    db = AsyncMock()
    updates = []

    async def execute(statement):
        if isinstance(statement, Update):
            updates.append(statement.compile().params)
            return _Result(rowcount=rowcount)
        table = statement.get_final_froms()[0].name
        return _Result(scalar_one=item if table == "plan_items" else latest)

    db.execute.side_effect = execute
    return db, updates


async def _ensure(monkeypatch, item, latest, completed, *, publish_error=None, rowcount=1):
    db, updates = _ensure_db(item, latest, rowcount=rowcount)
    monkeypatch.setattr(plan_tasks, "_learner_completed_tutorial_ids", AsyncMock(return_value=set(completed)))
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async",
               side_effect=publish_error) as publish:
        result = await plan_tasks.ensure_tutorial_window_generation(db, item_id="mission-1", user_id="user-1")
    return result, updates, publish, db


@pytest.mark.asyncio
async def test_completing_t1_requeues_the_parked_job_for_t3(monkeypatch):
    result, updates, publish, _ = await _ensure(monkeypatch, _item(), _job(), {"step_1"})
    assert result == JOB
    assert updates[0]["status"] == "queued" and updates[0]["step"] == "background_queued"
    assert (updates[0]["status_1"], updates[0]["step_1"]) == ("completed", "waiting_for_learner")
    publish.assert_called_once_with(args=[JOB], queue="low_priority")


@pytest.mark.asyncio
async def test_completion_when_the_next_tutorial_is_ready_triggers_nothing(monkeypatch):
    item = _item(_details(ready=("step_1", "step_2", "step_3")))
    result, updates, publish, _ = await _ensure(monkeypatch, item, _job(), {"step_1"})
    assert result is None and updates == []
    publish.assert_not_called()


@pytest.mark.asyncio
async def test_an_active_job_is_reused_never_duplicated(monkeypatch):
    result, updates, publish, _ = await _ensure(
        monkeypatch, _item(), _job("running", "generating_lessons"), {"step_1"})
    assert result == JOB and updates == []
    publish.assert_not_called()


@pytest.mark.asyncio
async def test_a_lost_compare_and_set_publishes_nothing(monkeypatch):
    result, updates, publish, _ = await _ensure(monkeypatch, _item(), _job(), {"step_1"}, rowcount=0)
    assert result is None and len(updates) == 1
    publish.assert_not_called()


@pytest.mark.asyncio
async def test_a_missing_current_tutorial_uses_the_foreground_queue(monkeypatch):
    item = _item(_details(ready=("step_1",)))
    result, updates, publish, _ = await _ensure(monkeypatch, item, _job(), {"step_1"})
    assert result == JOB and updates[0]["step"] == "user_priority"
    publish.assert_called_once_with(args=[JOB], queue="default")


@pytest.mark.asyncio
async def test_a_publish_failure_parks_the_job_again(monkeypatch):
    result, updates, publish, _ = await _ensure(
        monkeypatch, _item(), _job(), {"step_1"}, publish_error=RuntimeError("broker down"))
    assert result is None
    assert (updates[1]["status"], updates[1]["step"]) == ("completed", "waiting_for_learner")


# --- toggle_step_complete --------------------------------------------------

def _toggle_patches(item, progress):
    return (
        patch.object(plans, "_lock_plan_item_toggle_state", AsyncMock(
            return_value=(SimpleNamespace(id="plan-1", completed_at=None, roadmap_json={}), item, None))),
        patch.object(plans, "_compute_item_progress", AsyncMock(return_value=(progress, False))),
        patch.object(plans, "_reconcile_plan_completion", AsyncMock(return_value=(False, 1))),
        patch.object(plans, "_require_completion_artifact_ready", AsyncMock()),
    )


class _HookSession:
    def __init__(self):
        self.db = AsyncMock()

    async def __aenter__(self):
        return self.db

    async def __aexit__(self, *exc):
        return False


@pytest.mark.asyncio
async def test_completing_a_tutorial_triggers_window_generation_after_commit():
    item = _item()
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.side_effect = [DONE_AT, 1]  # Completion time, then plan duration (no next week).
    db.execute.side_effect = [_Result(scalar_one=None), _Result(scalars=[])]
    progress = ItemProgress(completed_steps=1, total_steps=4, percent=25)
    order = []
    db.commit.side_effect = lambda: order.append("commit")
    ensure = AsyncMock(side_effect=lambda *a, **k: order.append("ensure"))
    hook = _HookSession()
    lock, compute, reconcile, ready = _toggle_patches(item, progress)
    with lock, compute, reconcile, ready, patch(
            "app.tasks.plans.ensure_tutorial_window_generation", ensure), patch(
            "app.core.db.async_session_maker", lambda: hook):
        response = await plans.toggle_step_complete(
            "mission-1", "step_1", db, SimpleNamespace(id="user-1"), artifact_job_id=JOB)

    assert response.completed is True
    # Its own session: the request session is never touched by the hook.
    ensure.assert_awaited_once_with(hook.db, item_id="mission-1", user_id="user-1")
    assert order == ["commit", "ensure"]


@pytest.mark.asyncio
async def test_a_trigger_failure_never_fails_the_completion_or_the_week_prefetch():
    item = _item()
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.side_effect = [DONE_AT, 3]  # Plan has a next week to prefetch.
    db.execute.side_effect = [_Result(scalar_one=None), _Result(scalars=[])]
    lock, compute, reconcile, ready = _toggle_patches(item, ItemProgress(completed_steps=1, total_steps=4, percent=25))
    with lock, compute, reconcile, ready, patch(
            "app.tasks.plans.ensure_tutorial_window_generation", AsyncMock(side_effect=RuntimeError("db"))), patch(
            "app.core.db.async_session_maker", lambda: _HookSession()), patch(
            "app.tasks.plans.prefetch_plan_week_details.apply_async") as prefetch:
        response = await plans.toggle_step_complete(
            "mission-1", "step_1", db, SimpleNamespace(id="user-1"), artifact_job_id=JOB)
    assert response.completed is True and response.step_id == "step_1"
    prefetch.assert_called_once_with(args=["plan-1", "user-1", 2], kwargs={"priority": "low"},
                                     queue="low_priority")
    db.rollback.assert_not_awaited()  # The request's loaded objects are never expired.


@pytest.mark.asyncio
async def test_last_step_completion_still_requires_the_full_artifact():
    item = _item(_details(ready=("step_1", "step_2", "step_3", "step_4")))
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.side_effect = [DONE_AT]
    db.execute.side_effect = [_Result(scalar_one=None), _Result(scalars=["step_1", "step_2", "step_3"])]
    lock, compute, reconcile, ready = _toggle_patches(item, ItemProgress())
    with lock, compute, reconcile, ready, patch.object(
            plans, "_lesson_details_meet_runtime_quality", AsyncMock(return_value=False)):
        with pytest.raises(plans.HTTPException) as raised:
            await plans.toggle_step_complete(
                "mission-1", "step_4", db, SimpleNamespace(id="user-1"), artifact_job_id=JOB)
    assert raised.value.status_code == 409


# --- detailed response -----------------------------------------------------

async def _read(item, job, *, peek, completed=(), ensure_result=None):
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=job)
    ensure = AsyncMock(return_value=ensure_result)
    with (
        patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)),
        patch.object(plans, "_item_progress_snapshot", AsyncMock(
            return_value=(ItemProgress(), False, list(completed)))),
        patch.object(plans, "_lesson_details_meet_runtime_quality", AsyncMock(return_value=False)),
        patch.object(plans, "_partial_lesson_details_available", lambda details: True),
        patch("app.tasks.plans.ensure_tutorial_window_generation", ensure),
    ):
        response = await plans.get_plan_item_detailed("mission-1", db, SimpleNamespace(id="user-1"), peek=peek)
    return response, db, ensure


@pytest.mark.asyncio
@pytest.mark.parametrize("peek", [True, False])
async def test_parked_job_reads_as_waiting_for_learner_and_is_never_marked_stale(peek):
    job = _job()  # Hours old: a running job this old would be failed as stale.
    response, db, ensure = await _read(_item(), job, peek=peek)

    assert response.details_status == DetailsStatus.PARTIAL
    assert response.job_id is None
    assert response.details_step == "waiting_for_learner"
    assert response.details_error is None
    assert response.artifact_job_id == JOB
    assert response.generation_window.model_dump() == {
        "current_step_id": "step_1", "next_step_id": "step_2", "waiting_for_learner": True}
    assert (job.status, job.step) == ("completed", "waiting_for_learner")
    if peek:
        ensure.assert_not_awaited()  # A peek never creates work.
        db.commit.assert_not_awaited()
    dumped = plans.PlanItemDetailedResponse.model_validate(response.model_dump()).model_dump(mode="json")
    assert dumped["generation_window"]["waiting_for_learner"] is True


@pytest.mark.asyncio
async def test_a_normal_read_heals_a_missed_trigger():
    job = _job()
    response, db, ensure = await _read(_item(), job, peek=False, completed=["step_1"], ensure_result=JOB)

    ensure.assert_awaited_once()
    assert response.job_id == JOB
    assert response.details_status == DetailsStatus.PARTIAL
    assert response.generation_window.model_dump() == {
        "current_step_id": "step_2", "next_step_id": "step_3", "waiting_for_learner": False}


@pytest.mark.asyncio
@pytest.mark.parametrize("peek", [True, False])
async def test_a_missing_window_tutorial_that_cannot_be_queued_offers_a_retry(peek):
    # The learner finished T1 and T2, T3 is missing and the trigger could not
    # queue (broker down / lost compare-and-set): never an endless "waiting".
    job = _job()
    response, _, _ = await _read(_item(), job, peek=peek, completed=["step_1", "step_2"], ensure_result=None)
    assert response.details_status == DetailsStatus.PARTIAL
    assert response.job_id is None
    assert response.details_error == "This lesson could not be prepared. Generate it again to retry."
    assert response.details_step != "waiting_for_learner"
    assert response.generation_window.model_dump() == {
        "current_step_id": "step_3", "next_step_id": "step_4", "waiting_for_learner": False}


@pytest.mark.asyncio
async def test_a_running_window_job_is_not_waiting_for_learner():
    job = _job("running", "generating_lessons", age=timedelta(0))
    response, _, _ = await _read(_item(_details(ready=("step_1",))), job, peek=True)
    assert response.job_id == JOB
    assert response.generation_window.model_dump() == {
        "current_step_id": "step_1", "next_step_id": "step_2", "waiting_for_learner": False}


@pytest.mark.asyncio
async def test_a_failed_window_tutorial_keeps_todays_error_shape():
    job = _job("failed", "error", age=timedelta(0))
    response, _, ensure = await _read(_item(_details(ready=("step_1",))), job, peek=False)
    assert response.details_status == DetailsStatus.PARTIAL
    assert response.details_error and response.job_id == JOB
    ensure.assert_not_awaited()


# --- prefetch / plan-creation enqueue --------------------------------------

def test_window_ready_tutorial_counts_as_ready_for_prefetch(monkeypatch):
    monkeypatch.setattr("app.services.planning.lesson_package.current_package_approval", lambda *a, **k: True)
    details = _details()
    assert plan_tasks._details_ready_for_prefetch(details) is True
    assert plan_tasks._details_ready_for_prefetch(details, completed_step_ids={"step_1"}) is False


@pytest.mark.asyncio
async def test_prefetch_skips_a_parked_mission_whose_window_is_ready(monkeypatch):
    monkeypatch.setattr("app.services.planning.lesson_package.current_package_approval", lambda *a, **k: True)
    monkeypatch.setattr(plan_tasks, "_learner_completed_tutorial_ids", AsyncMock(return_value=set()))
    db = AsyncMock()
    db.add = MagicMock()
    db.get.return_value = SimpleNamespace(roadmap_json={})
    db.scalar.return_value = JOB  # The artifact's job exists.
    db.execute.side_effect = [_Result(scalars=[_item()])]
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish:
        jobs = await plan_tasks._enqueue_plan_week_details_generation_async(
            db, plan_id="plan-1", user_id="user-1", week=1, priority="high")
    assert jobs == []
    db.add.assert_not_called()
    publish.assert_not_called()


@pytest.mark.asyncio
async def test_prefetch_requeues_the_parked_job_instead_of_a_new_artifact(monkeypatch):
    monkeypatch.setattr("app.services.planning.lesson_package.current_package_approval", lambda *a, **k: True)
    monkeypatch.setattr(plan_tasks, "_learner_completed_tutorial_ids", AsyncMock(return_value={"step_1"}))
    ensure = AsyncMock(return_value=JOB)
    monkeypatch.setattr(plan_tasks, "ensure_tutorial_window_generation", ensure)
    db = AsyncMock()
    db.add = MagicMock()
    db.get.return_value = SimpleNamespace(roadmap_json={})
    db.scalar.return_value = JOB
    db.execute.side_effect = [_Result(scalars=[_item()]), _Result(scalars=[]), _Result(scalar_one=_job())]
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish:
        jobs = await plan_tasks._enqueue_plan_week_details_generation_async(
            db, plan_id="plan-1", user_id="user-1", week=2, priority="low")
    assert jobs == [JOB]
    ensure.assert_awaited_once_with(db, item_id="mission-1", user_id="user-1")
    db.add.assert_not_called()
    publish.assert_not_called()


@pytest.mark.asyncio
async def test_regenerate_on_a_parked_mission_reuses_its_job():
    item = _item()
    db = AsyncMock()
    with (
        patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)),
        patch.object(plans, "_lesson_details_meet_runtime_quality", AsyncMock(return_value=False)),
        patch.object(plans, "_latest_active_detail_job", AsyncMock(return_value=None)),
        patch("app.tasks.plans._artifact_job_is_parked", AsyncMock(return_value=True)),
        patch("app.tasks.plans.ensure_tutorial_window_generation", AsyncMock(return_value=None)),
        patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish,
    ):
        response = await plans.regenerate_item_details("mission-1", db, SimpleNamespace(id="user-1"))
    assert response.job_id == ""  # Window ready: nothing to generate, no new artifact.
    publish.assert_not_called()
