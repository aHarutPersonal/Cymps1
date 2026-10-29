"""The detail job parks at the learner's window, retries a window tutorial once, then fails."""
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from sqlalchemy.sql.dml import Update

from app.services.llm.client import LLMResponse
from app.tasks import plans
from tests.test_short_tutorial_pipeline import outline


def _harness(monkeypatch, *, result_json=None, completed=frozenset()):
    plan = SimpleNamespace(id=str(uuid4()), idol=None, roadmap_json={})
    item = SimpleNamespace(
        id=str(uuid4()), plan=plan, title="Practice a skill", description="One example",
        type=SimpleNamespace(value="project"), estimated_hours=1,
        success_metric="Explain the result", details_json={},
    )
    job = SimpleNamespace(
        id=str(uuid4()), user_id=str(uuid4()), plan_item=item,
        created_at=datetime.now(timezone.utc), status="running", result_json=result_json or {},
    )
    durable = {"status": "queued", "step": None, "result_json": None}
    reads = iter([job, None])
    db = AsyncMock()
    db.add = MagicMock()

    async def execute(statement):
        if not isinstance(statement, Update):
            return SimpleNamespace(scalar_one_or_none=lambda: next(reads))
        params = statement.compile().params
        if params.get("status") == "running":
            durable["status"] = "running"
            return SimpleNamespace(rowcount=1)
        matched = durable["status"] == params.get("status_1")
        if matched:
            durable.update(status=params["status"], step=params.get("step"),
                           result_json=params.get("result_json"))
        return SimpleNamespace(rowcount=int(matched))

    db.execute.side_effect = execute
    context = AsyncMock()
    context.__aenter__.return_value = db
    monkeypatch.setattr(plans, "async_session_maker", lambda: context)
    monkeypatch.setattr(plans.settings, "lesson_catalog_first_enabled", False)
    monkeypatch.setattr(plans, "_load_session_context", AsyncMock(return_value={}))
    monkeypatch.setattr(plans, "_learner_completed_tutorial_ids", AsyncMock(return_value=set(completed)))
    monkeypatch.setattr("app.services.llm.routing.choose_llm_tier", AsyncMock(
        return_value=SimpleNamespace(tier="balanced", reason="test")))
    usage = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_usage_records", usage)
    ensure = AsyncMock(return_value=None)
    monkeypatch.setattr(plans, "ensure_tutorial_window_generation", ensure)
    return job, durable, ensure, usage


def _payload(**marker):
    return {**outline(), **marker}


@pytest.mark.asyncio
async def test_job_parks_as_completed_waiting_for_learner_and_rechecks_the_window(monkeypatch):
    job, durable, ensure, usage = _harness(monkeypatch)
    seen = {}

    async def generator(**kwargs):
        seen["reader"] = kwargs["learner_completed_step_ids"]
        return _payload(_tutorial_waiting_for_learner=True), [], None

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", generator)
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish:
        result = await plans._regenerate_plan_item_details_async(job.id)

    assert result["status"] == "waiting_for_learner"
    assert (durable["status"], durable["step"]) == ("completed", "waiting_for_learner")
    assert durable["result_json"]["waiting_for_learner"] is True
    publish.assert_not_called()  # No continuation chaining beyond the window.
    ensure.assert_awaited_once()  # Closes the race with a late completion.
    assert await seen["reader"]() == set()
    usage.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize(("failed", "queue", "step"), [
    ("step_1", "default", "user_priority"),
    ("step_2", "low_priority", "background_queued"),
])
async def test_a_failed_window_tutorial_is_retried_once_in_the_background(monkeypatch, failed, queue, step):
    job, durable, ensure, usage = _harness(monkeypatch)

    payload = _payload(_window_step_failed=failed)
    if failed == "step_2":  # T1 is published; only the next tutorial failed.
        payload["steps"][0] = {**payload["steps"][0], "lesson_content": "ready"}

    async def generator(**kwargs):
        return payload, [], f"{failed}: Exercise contract rejected"

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", generator)
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish:
        result = await plans._regenerate_plan_item_details_async(job.id)

    assert result == {"status": "retrying"}
    assert (durable["status"], durable["step"]) == ("queued", step)
    assert durable["result_json"]["window_retries"] == {failed: 1}
    assert durable["result_json"]["last_window_error"].startswith(failed)
    publish.assert_called_once_with(args=[job.id], queue=queue)  # Same job, same artifact.
    usage.assert_awaited_once()


@pytest.mark.asyncio
async def test_a_window_tutorial_that_fails_again_surfaces_todays_error(monkeypatch):
    job, durable, ensure, usage = _harness(monkeypatch, result_json={"window_retries": {"step_2": 1}})

    async def generator(**kwargs):
        return _payload(_window_step_failed="step_2"), [], "step_2: Exercise contract rejected"

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", generator)
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish:
        result = await plans._regenerate_plan_item_details_async(job.id)

    assert result["status"] == "failed" and result["error"].startswith("step_2:")
    assert (durable["status"], durable["step"]) == ("failed", "error")
    publish.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize(("ready", "queue", "step"), [
    ((), "default", "user_priority"),               # The current tutorial is missing.
    (("step_1",), "low_priority", "background_queued"),
])
async def test_too_little_time_for_the_next_window_tutorial_requeues_the_same_job(monkeypatch, ready, queue, step):
    job, durable, ensure, usage = _harness(monkeypatch)
    payload = _payload(_tutorial_window_continuation=True)
    payload["steps"] = [{**s, "lesson_content": "ready"} if s["id"] in ready else s for s in payload["steps"]]

    async def generator(**kwargs):
        return payload, [], None

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", generator)
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish:
        result = await plans._regenerate_plan_item_details_async(job.id)

    assert result == {"status": "continuing"}
    assert (durable["status"], durable["step"]) == ("queued", step)
    publish.assert_called_once_with(args=[job.id], queue=queue)


@pytest.mark.asyncio
async def test_retry_queue_follows_the_learner_window(monkeypatch):
    # T2 failed while the learner is already on T2 (T1 completed): foreground.
    job, durable, ensure, usage = _harness(monkeypatch, completed={"step_1"})
    payload = _payload(_window_step_failed="step_2")
    payload["steps"][0] = {**payload["steps"][0], "lesson_content": "ready"}

    async def generator(**kwargs):
        return payload, [], "step_2: Exercise contract rejected"

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", generator)
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish:
        await plans._regenerate_plan_item_details_async(job.id)
    publish.assert_called_once_with(args=[job.id], queue="default")
    assert durable["step"] == "user_priority"


@pytest.mark.asyncio
async def test_generator_requeues_instead_of_starting_a_window_tutorial_near_the_deadline(monkeypatch):
    import asyncio
    from tests.test_one_ahead_generator import _pipeline

    state, common, _ = _pipeline(monkeypatch)
    deadline = asyncio.get_running_loop().time() + plans._WINDOW_STEP_MIN_REMAINING_SECONDS - 30
    payload, _, error = await plans._generate_plan_item_details_parallel(
        **common, lesson_format="tutorial_v1", deadline=deadline)
    assert error is None and payload.pop("_tutorial_window_continuation") is True
    assert state["built"] == ["step_1"]  # T1 is always attempted; T2 waits for a fresh run.
