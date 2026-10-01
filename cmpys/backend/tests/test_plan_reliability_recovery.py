import asyncio
from copy import deepcopy
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.api.v1 import plans as plans_api, sessions as sessions_api
from app.services.planning import generator
from app.services.planning.checkpoints import PlanCheckpointStore
from app.tasks import plans as plan_tasks
from tests.test_plan_generation_performance import _backbone, _expanded_week_one


class _SessionContext:
    def __init__(self, db):
        self.db = db

    async def __aenter__(self):
        return self.db

    async def __aexit__(self, *_args):
        return None


@pytest.mark.asyncio
async def test_persisted_plan_resumes_publication_without_model_work(monkeypatch):
    db = AsyncMock()
    db.add = MagicMock()
    job = SimpleNamespace(id="job-1", user_id="user-1", idol_id="idol-1", plan_id="plan-1")
    plan = SimpleNamespace(id="plan-1", user_id="user-1", idol_id="idol-1", roadmap_json={})
    db.execute.side_effect = [
        SimpleNamespace(rowcount=1),
        SimpleNamespace(scalar_one_or_none=lambda: job),
    ]
    db.get.return_value = plan
    monkeypatch.setattr(plan_tasks, "async_session_maker", lambda: _SessionContext(db))
    generate = AsyncMock(side_effect=AssertionError("must reuse the persisted plan"))
    enqueue = AsyncMock()
    monkeypatch.setattr(plan_tasks, "generate_plan", generate)
    monkeypatch.setattr(plan_tasks, "_enqueue_all_details_generation_async", enqueue)

    result = await plan_tasks._run_plan_generation_async("job-1")

    assert result == {"status": "completed", "plan_id": "plan-1"}
    assert job.status == "completed" and job.progress_percent == 100
    enqueue.assert_awaited_once_with(db, plan, "user-1")
    generate.assert_not_awaited()


@pytest.mark.asyncio
async def test_deadline_cancels_stuck_plan_even_in_solo_worker(monkeypatch):
    cancelled = asyncio.Event()
    async def stuck(_job_id):
        try:
            await asyncio.Event().wait()
        finally:
            cancelled.set()
    monkeypatch.setattr(plan_tasks, "_run_plan_generation_async", stuck)
    monkeypatch.setattr(plan_tasks, "PLAN_PIPELINE_TIMEOUT_SECONDS", 0.01)
    with pytest.raises(TimeoutError):
        await plan_tasks._run_plan_generation_with_deadline("job-1")
    assert cancelled.is_set()


@pytest.mark.asyncio
async def test_failure_persistence_does_not_overwrite_completed_plan(monkeypatch):
    db = AsyncMock()
    monkeypatch.setattr(plan_tasks, "async_session_maker", lambda: _SessionContext(db))
    await plan_tasks._mark_plan_generation_failed("job-1", TimeoutError())
    statement = db.execute.await_args.args[0]
    assert "status IN" in str(statement)
    params = statement.compile().params
    assert ["pending", "running"] in params.values()
    assert any("took too long" in str(value) for value in params.values())
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_strategy_retry_keeps_same_job_and_committed_plan():
    checkpoint = {"identity": "same", "stages": {}}
    job = SimpleNamespace(
        status="failed", id="job-1", plan_id="plan-1", weekly_hours=6,
        generation_checkpoint_json=checkpoint, focus="original",
    )
    session = SimpleNamespace(id="session-1", idol_id="idol-1", user_goal="goal")
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: job)
    result = await sessions_api._get_or_create_session_plan_job(
        db, session=session, user_id="user-1", weekly_hours=8, focus="changed",
    )
    assert result is job
    assert job.status == "pending" and job.step == "waiting_for_strategy"
    assert job.plan_id == "plan-1" and job.weekly_hours == 6
    assert job.generation_checkpoint_json is checkpoint
    db.add.assert_not_called()


def test_small_backbone_arithmetic_slips_are_corrected_without_changing_content():
    original = _backbone()
    original.weeks[1].tasks[0].estimated_hours = 2
    original.weeks[7].tasks[1].estimated_hours = 3
    corrected, changes = generator._normalize_backbone_workload(original, hours_per_week=5)
    assert len(changes) == 2
    assert not generator.validate_plan_backbone(corrected, duration_weeks=12, hours_per_week=5)
    assert original.weeks[1].tasks[0].estimated_hours == 2
    for before, after in zip(original.weeks, corrected.weeks):
        assert before.primary_mission == after.primary_mission
        assert [(t.title, t.type, t.success_metric) for t in before.tasks] == [(t.title, t.type, t.success_metric) for t in after.tasks]


def test_infeasible_task_count_and_large_workload_gaps_still_require_review():
    original = _backbone()
    original.weeks[1].tasks[0].estimated_hours = 7
    corrected, changes = generator._normalize_backbone_workload(original, hours_per_week=5)
    assert changes == []
    assert generator.validate_plan_backbone(corrected, duration_weeks=12, hours_per_week=5)
    corrected, changes = generator._normalize_backbone_workload(_backbone(), hours_per_week=6)
    assert changes == []  # A six-hour week needs two mission tasks.


@pytest.mark.asyncio
async def test_exhausted_checkpoint_with_only_arithmetic_error_recovers_without_llm(monkeypatch):
    candidate = _backbone()
    candidate.weeks[1].tasks[0].estimated_hours = 2
    store = PlanCheckpointStore(None, "identity", None)
    await store.put("backbone", candidate.model_dump(mode="json"), repair_attempts=1, issues=["old error"])
    monkeypatch.setattr(generator, "_plan_client", MagicMock(side_effect=AssertionError("no model needed")))
    result = await generator._checkpointed_backbone(
        store=store, system_prompt="system", user_prompt="goal",
        duration_weeks=12, hours_per_week=5, telemetry_context={},
    )
    assert not generator.validate_plan_backbone(result, duration_weeks=12, hours_per_week=5)
    assert store.load("backbone")["issues"] == []


@pytest.mark.asyncio
async def test_explicit_retry_replaces_exhausted_invalid_checkpoint(monkeypatch):
    saved = None
    async def persist(value):
        nonlocal saved
        saved = deepcopy(value)
    async def backbone(**kwargs):
        value = _backbone()
        await kwargs["candidate_callback"](value, SimpleNamespace(provider="dummy", model="test"), [])
        return value
    monkeypatch.setattr(generator, "_generate_plan_backbone", backbone)
    monkeypatch.setattr(generator, "generate_plan_week_from_backbone", AsyncMock(return_value=_expanded_week_one().weeks[0]))
    args = dict(idol_name="Ada", user_goal="Learn", hours_per_week=5, save_generation_checkpoint=persist)
    await generator._generate_llm_items(**args)
    store = PlanCheckpointStore(saved, saved["identity"], persist)
    invalid = _backbone()
    invalid.weeks[0].tasks[0].estimated_hours = 7
    await store.put("backbone", invalid.model_dump(mode="json"), repair_attempts=1)
    result = await generator._generate_llm_items(**args, generation_checkpoint=saved)
    assert result.items
    assert saved["stages"]["backbone"]["record"]["repair_attempts"] == 0
    assert saved["stages"]["week_one"]


@pytest.mark.asyncio
async def test_localized_backbone_error_skips_full_cycle_quality_rewrite(monkeypatch):
    candidate = _backbone()
    candidate.weeks[3].phase = "foundation"
    client = SimpleNamespace(
        model="test",
        generate_and_validate=AsyncMock(return_value=(candidate, SimpleNamespace(error=None, model="test"))),
    )
    factory = MagicMock(return_value=client)
    monkeypatch.setattr(generator, "_plan_client", factory)
    monkeypatch.setattr(generator, "record_llm_response", AsyncMock())
    remember = AsyncMock()
    with pytest.raises(ValueError, match="week 4"):
        await generator._generate_plan_backbone(
            system_prompt="system", user_prompt="goal", duration_weeks=12,
            hours_per_week=5, candidate_callback=remember,
        )
    factory.assert_called_once()
    remember.assert_awaited_once()
