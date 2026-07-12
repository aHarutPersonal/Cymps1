"""Automatic post-interview comparison → blueprint → plan orchestration."""

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.api.v1 import sessions as sessions_api
from app.models.chat import ChatThread
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.plan_job import PlanGenerationJob


class _Result:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


@pytest.mark.asyncio
async def test_stages_plan_job_immediately_and_reuses_active_work() -> None:
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        idol_id="idol-1",
        phase=SessionPhase.COMPARISON,
        user_age=28,
    )
    existing = PlanGenerationJob(
        id="job-1",
        user_id="user-1",
        idol_id="idol-1",
        session_id="session-1",
        target_age=28,
        weekly_hours=10,
        status="pending",
        step="waiting_for_strategy",
    )
    db = AsyncMock()
    db.execute.return_value = _Result(existing)

    job = await sessions_api._get_or_create_session_plan_job(
        db,
        session=session,
        user_id="user-1",
        weekly_hours=7,
    )

    assert job is existing
    assert job.weekly_hours == 7
    db.add.assert_not_called()
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_stages_a_new_plan_job_before_strategy_is_ready() -> None:
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        idol_id="idol-1",
        phase=SessionPhase.COMPARISON,
        user_age=28,
    )
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result(None)

    job = await sessions_api._get_or_create_session_plan_job(
        db,
        session=session,
        user_id="user-1",
        weekly_hours=8,
    )

    assert job is not None
    assert job.status == "pending"
    assert job.step == "waiting_for_strategy"
    assert job.weekly_hours == 8
    db.add.assert_called_once_with(job)
    db.commit.assert_awaited_once()
    db.refresh.assert_awaited_once_with(job)


@pytest.mark.asyncio
async def test_dispatches_staged_plan_job_only_once(monkeypatch) -> None:
    from app.tasks import plans as plan_tasks

    delay = MagicMock()
    monkeypatch.setattr(plan_tasks.run_plan_generation, "delay", delay)
    job = SimpleNamespace(
        id="job-1",
        status="pending",
        step="waiting_for_strategy",
        progress_percent=0,
        error_message=None,
    )
    db = AsyncMock()

    await sessions_api._dispatch_session_plan_job(db, job)
    await sessions_api._dispatch_session_plan_job(db, job)

    assert job.step == "analyzing_gaps"
    delay.assert_called_once_with("job-1")
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_completed_results_replay_without_repeating_llm_calls(monkeypatch) -> None:
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        idol_id="idol-1",
        phase=SessionPhase.COMPLETED,
        user_age=28,
        user_financial_status="employed",
        user_interests=["technology"],
        user_goal="build a product",
        interview_thread_id="thread-1",
        comparison_output="Cached comparison",
        blueprint_output="Cached blueprint",
        comparison_scores_json={"dimensions": []},
    )
    session.idol = Idol(id="idol-1", name="Ada Lovelace", domain="technology")
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = []
    plan_job = SimpleNamespace(
        id="job-1",
        status="completed",
        step="done",
        weekly_hours=10,
    )
    db = AsyncMock()
    db.execute.side_effect = [_Result(thread), _Result(plan_job)]

    async def fake_get_session(*args, **kwargs):
        return session

    async def forbidden_stream(*args, **kwargs):
        raise AssertionError("cached replay must not call an LLM")
        yield "unreachable"

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    monkeypatch.setattr(sessions_api, "comparison_stream", forbidden_stream)
    monkeypatch.setattr(sessions_api, "blueprint_stream", forbidden_stream)

    response = await sessions_api.generate_results(
        "session-1",
        db,
        SimpleNamespace(id="user-1"),
    )
    body = "".join([chunk async for chunk in response.body_iterator])

    assert '"job_id": "job-1"' in body
    assert "Cached comparison" in body
    assert "Cached blueprint" in body
    assert '"type": "done"' in body
    assert body.index('"type": "plan_job"') < body.index(
        '"section": "comparison"'
    )


@pytest.mark.asyncio
async def test_blueprint_retry_reuses_finished_comparison(monkeypatch) -> None:
    from app.tasks import plans as plan_tasks

    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        idol_id="idol-1",
        phase=SessionPhase.BLUEPRINT,
        user_age=28,
        user_financial_status="employed",
        user_interests=["technology"],
        user_goal="build a product",
        interview_thread_id="thread-1",
        comparison_output="Keep this comparison",
        blueprint_output=None,
        comparison_scores_json={"dimensions": []},
    )
    session.idol = Idol(id="idol-1", name="Ada Lovelace", domain="technology")
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = []
    plan_job = SimpleNamespace(
        id="job-1",
        status="pending",
        step="waiting_for_strategy",
        progress_percent=0,
        error_message=None,
        weekly_hours=10,
    )
    db = AsyncMock()
    db.execute.side_effect = [_Result(thread), _Result(plan_job)]

    async def fake_get_session(*args, **kwargs):
        return session

    async def forbidden_comparison(*args, **kwargs):
        raise AssertionError("comparison must be reused")
        yield "unreachable"

    async def fake_blueprint(*args, **kwargs):
        yield "New blueprint"

    delay = MagicMock()
    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    monkeypatch.setattr(sessions_api, "comparison_stream", forbidden_comparison)
    monkeypatch.setattr(sessions_api, "blueprint_stream", fake_blueprint)
    monkeypatch.setattr(plan_tasks.run_plan_generation, "delay", delay)

    response = await sessions_api.generate_results(
        "session-1",
        db,
        SimpleNamespace(id="user-1"),
    )
    body = "".join([chunk async for chunk in response.body_iterator])

    assert "Keep this comparison" in body
    assert "New blueprint" in body
    assert session.phase == SessionPhase.COMPLETED
    delay.assert_called_once_with("job-1")
