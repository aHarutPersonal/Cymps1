"""A completed provider failure cannot overwrite a cancelled predecessor."""
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from sqlalchemy.sql.dml import Update

from app.services.llm.client import LLMResponse
from app.tasks import plans


@pytest.mark.asyncio
@pytest.mark.parametrize("durable_status", ["running", "cancelled", "completed"])
async def test_terminal_provider_failure_uses_status_cas_and_keeps_usage(monkeypatch, durable_status):
    plan = SimpleNamespace(id=str(uuid4()), idol=None, roadmap_json={})
    item = SimpleNamespace(
        id=str(uuid4()), plan=plan, title="Practice a skill", description="One example",
        type=SimpleNamespace(value="project"), estimated_hours=3,
        success_metric="Explain the result", details_json={},
    )
    job = SimpleNamespace(
        id=str(uuid4()), user_id=str(uuid4()), plan_item=item,
        created_at=datetime.now(timezone.utc), status="running", result_json={},
    )
    durable = {"status": "queued"}
    terminal_statements = []
    reads = iter([job, None])
    db = AsyncMock()
    db.add = MagicMock()

    async def execute(statement):
        if not isinstance(statement, Update):
            return SimpleNamespace(scalar_one_or_none=lambda: next(reads))
        params = statement.compile().params
        if params["status"] == "running":
            durable["status"] = "running"
            return SimpleNamespace(rowcount=1)
        terminal_statements.append(statement)
        assert params["status_1"] == "running"
        assert params["id_1"] == job.id
        matched = durable["status"] == params["status_1"]
        if matched:
            durable["status"] = params["status"]
        return SimpleNamespace(rowcount=int(matched))

    db.execute.side_effect = execute
    context = AsyncMock()
    context.__aenter__.return_value = db
    monkeypatch.setattr(plans, "async_session_maker", lambda: context)
    monkeypatch.setattr(plans.settings, "lesson_catalog_first_enabled", False)
    monkeypatch.setattr(plans, "_load_session_context", AsyncMock(return_value={}))
    monkeypatch.setattr("app.services.llm.routing.choose_llm_tier", AsyncMock(
        return_value=SimpleNamespace(tier="balanced", reason="test")))
    usage = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_usage_records", usage)
    response = LLMResponse(data={}, error="Provider request timed out")

    async def provider_finished_after_status_change(**kwargs):
        # The worker's ORM snapshot still says running; a successor may have
        # cancelled it in another session while its paid request was in flight.
        durable["status"] = durable_status
        return None, [("parallel_lesson_step_1_draft_1_framing_attempt_1", response,
                       "balanced", "lesson_section_draft", "synthetic")], "Provider unavailable"

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", provider_finished_after_status_change)
    result = await plans._regenerate_plan_item_details_async(job.id)
    assert len(terminal_statements) == 1
    if durable_status == "running":
        assert result["status"] == durable["status"] == "failed"
    else:
        assert result == {"status": "skipped", "reason": "job_superseded"}
        assert durable["status"] == durable_status
    usage.assert_awaited_once()
    record = usage.call_args.args[0][0]
    assert record.model == "synthetic" and record.result_status == "quality_failed"
    assert record.prompt_tokens is None and record.completion_tokens is None
    assert record.metadata["plan_item_id"] == item.id
    assert db.commit.await_count >= 1
    assert not item.details_json


@pytest.mark.asyncio
async def test_terminal_failure_bounds_diagnostic_and_commits_lost_race():
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(rowcount=0)
    assert not await plans._fail_running_plan_detail_job(db, job_id=str(uuid4()), error="x" * 5000)
    assert len(db.execute.call_args.args[0].compile().params["error_message"]) == 4000
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize("durable_status", ["pending", "queued", "running", "cancelled", "completed", "failed"])
async def test_outer_timeout_does_not_overwrite_terminal_job(monkeypatch, durable_status):
    durable = {"status": durable_status}
    db = AsyncMock()
    async def execute(statement):
        params = statement.compile().params
        active = params["status_1"]
        assert set(active) == {"pending", "queued", "running"}
        if durable["status"] in active:
            durable["status"] = params["status"]
        return SimpleNamespace(rowcount=int(durable_status in active))
    db.execute.side_effect = execute
    context = AsyncMock()
    context.__aenter__.return_value = db
    monkeypatch.setattr(plans, "async_session_maker", lambda: context)
    await plans._mark_plan_detail_job_failed(str(uuid4()), "Deadline exceeded")
    assert durable["status"] == ("failed" if durable_status in {"pending", "queued", "running"} else durable_status)
    db.commit.assert_awaited_once()
