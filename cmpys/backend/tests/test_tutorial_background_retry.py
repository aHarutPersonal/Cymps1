"""A failed tutorial's next fresh attempt re-queues the same job (plan Phase 4.1, D1(b))."""
from unittest.mock import patch

import pytest

from app.tasks import plans
from tests.test_one_ahead_job import _harness, _payload


@pytest.mark.asyncio
async def test_a_tutorial_retry_requeues_the_same_job_with_its_next_attempt(monkeypatch):
    job, durable, ensure, usage = _harness(monkeypatch)
    seen = {}

    async def generator(**kwargs):
        seen["attempts"] = kwargs["tutorial_attempts"]
        return _payload(_tutorial_retry={"step_id": "step_1", "next_attempt": 1}), [], "step_1: Exercise contract rejected"

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", generator)
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish:
        result = await plans._regenerate_plan_item_details_async(job.id)

    assert seen["attempts"] is None
    assert result == {"status": "retrying"}
    # Still active, so the learner keeps seeing the tutorial being prepared.
    assert (durable["status"], durable["step"]) == ("queued", "user_priority")
    assert durable["result_json"]["tutorial_attempts"] == {"step_1": 1}
    assert durable["result_json"]["last_tutorial_error"].startswith("step_1")
    publish.assert_called_once_with(args=[job.id], queue="default")
    usage.assert_awaited_once()


@pytest.mark.asyncio
async def test_the_next_run_starts_at_the_saved_attempt(monkeypatch):
    job, durable, ensure, usage = _harness(monkeypatch, result_json={"tutorial_attempts": {"step_1": 1}})
    seen = {}

    async def generator(**kwargs):
        seen["attempts"] = kwargs["tutorial_attempts"]
        return _payload(_tutorial_retry={"step_id": "step_1", "next_attempt": 2}), [], "step_1: Exercise contract rejected"

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", generator)
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async"):
        result = await plans._regenerate_plan_item_details_async(job.id)
    assert seen["attempts"] == {"step_1": 1}
    assert result == {"status": "retrying"} and durable["result_json"]["tutorial_attempts"] == {"step_1": 2}


@pytest.mark.asyncio
async def test_a_retry_that_does_not_advance_its_attempt_fails_as_today(monkeypatch):
    job, durable, ensure, usage = _harness(monkeypatch, result_json={"tutorial_attempts": {"step_1": 2}})

    async def generator(**kwargs):
        return _payload(_tutorial_retry={"step_id": "step_1", "next_attempt": 2}), [], "step_1: Exercise contract rejected"

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", generator)
    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as publish:
        result = await plans._regenerate_plan_item_details_async(job.id)
    assert result["status"] == "failed"
    publish.assert_not_called()
