"""Automatic post-interview comparison → blueprint → plan orchestration."""

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException
from sqlalchemy.dialects import postgresql

from app.api.v1 import sessions as sessions_api
from app.models.chat import ChatMessage, ChatThread, MessageRole
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.plan_job import PlanGenerationJob


class _Result:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


def _current_scores() -> dict:
    return {
        "version": 2,
        "methodology": "like_for_like_evidence",
        "overall": {"status": "insufficient_evidence"},
        "dimensions": [],
        "milestones": [],
    }


def _plan_ready_messages(weekly_hours: int = 8) -> list[ChatMessage]:
    values = {
        "achievement_inventory": "I shipped a prototype used by five people.",
        "current_capability": "I can build and test a small app independently.",
        "weekly_hours": f"{weekly_hours} hours per week",
        "target_outcome": "Publish a stable product with ten active users.",
        "constraints_resources": "I have a laptop; weekday time is limited.",
        "learning_habits_support": "Deliberate practice and weekly peer feedback work.",
    }
    messages: list[ChatMessage] = []
    for index, (answer_key, answer) in enumerate(values.items(), start=1):
        question_id = f"question-{index}"
        messages.extend(
            [
                ChatMessage(
                    id=question_id,
                    thread_id="thread-1",
                    role=MessageRole.ASSISTANT,
                    content=f"Question for {answer_key}",
                    response_ui_json={"answer_key": answer_key},
                ),
                ChatMessage(
                    id=f"answer-{index}",
                    thread_id="thread-1",
                    role=MessageRole.USER,
                    content=answer,
                    reply_to_message_id=question_id,
                ),
            ]
        )
    return messages


def _use_session_lock(monkeypatch, session: IntakeSession) -> None:
    async def lock_session(*args, **kwargs):
        return session

    monkeypatch.setattr(
        sessions_api,
        "_lock_interview_session_state",
        lock_session,
    )


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
async def test_session_lock_targets_only_intake_row_with_eager_outer_joins() -> None:
    session = IntakeSession(id="session-1", user_id="user-1")
    db = AsyncMock()
    db.execute.return_value = _Result(session)

    locked = await sessions_api._lock_interview_session_state(
        db,
        session_id="session-1",
        user_id="user-1",
    )

    statement = db.execute.await_args.args[0]
    sql = str(statement.compile(dialect=postgresql.dialect()))
    assert locked is session
    assert "LEFT OUTER JOIN" in sql
    assert "FOR UPDATE OF intake_sessions" in sql


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
        comparison_scores_json=_current_scores(),
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
    db.execute.side_effect = [_Result(thread), _Result(thread), _Result(plan_job)]

    async def fake_get_session(*args, **kwargs):
        return session

    async def forbidden_stream(*args, **kwargs):
        raise AssertionError("cached replay must not call an LLM")
        yield "unreachable"

    async def skip_profile_sync(*args, **kwargs):
        return None

    async def skip_claim_release(*args, **kwargs):
        return None

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    _use_session_lock(monkeypatch, session)
    monkeypatch.setattr(sessions_api, "comparison_stream", forbidden_stream)
    monkeypatch.setattr(sessions_api, "blueprint_stream", forbidden_stream)
    monkeypatch.setattr(
        sessions_api,
        "_sync_user_profile_from_interview",
        skip_profile_sync,
    )
    monkeypatch.setattr(
        sessions_api,
        "_release_owned_thread_claim",
        skip_claim_release,
    )

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
async def test_claim_waiter_refreshes_session_before_replaying_completed_artifacts(
    monkeypatch,
) -> None:
    """A waiter must not decide from the pre-claim session snapshot."""
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        idol_id="idol-1",
        phase=SessionPhase.COMPARISON,
        user_age=28,
        user_goal="build a product",
        interview_thread_id="thread-1",
    )
    session.idol = Idol(id="idol-1", name="Ada Lovelace", domain="technology")
    refreshed_session = IntakeSession(
        id="session-1",
        user_id="user-1",
        idol_id="idol-1",
        phase=SessionPhase.COMPLETED,
        user_age=28,
        user_goal="build a product",
        interview_thread_id="thread-1",
        comparison_output="Winner comparison",
        blueprint_output="Winner blueprint",
        comparison_scores_json=_current_scores(),
    )
    refreshed_session.idol = session.idol
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = []
    plan_job = SimpleNamespace(
        id="job-1",
        status="completed",
        step="done",
        weekly_hours=10,
    )
    db = AsyncMock()
    db.execute.side_effect = [_Result(thread), _Result(thread), _Result(plan_job)]

    async def fake_get_session(*args, **kwargs):
        return session

    async def refresh_after_previous_owner_committed(*args, **kwargs):
        assert kwargs["session_id"] == "session-1"
        assert kwargs["user_id"] == "user-1"
        return refreshed_session

    async def forbidden_stream(*args, **kwargs):
        raise AssertionError("refreshed artifacts must be replayed, not regenerated")
        yield "unreachable"

    async def skip_profile_sync(*args, **kwargs):
        return None

    async def skip_claim_release(*args, **kwargs):
        return None

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    monkeypatch.setattr(
        sessions_api,
        "_lock_interview_session_state",
        refresh_after_previous_owner_committed,
    )
    monkeypatch.setattr(sessions_api, "comparison_stream", forbidden_stream)
    monkeypatch.setattr(sessions_api, "blueprint_stream", forbidden_stream)
    monkeypatch.setattr(
        sessions_api,
        "_sync_user_profile_from_interview",
        skip_profile_sync,
    )
    monkeypatch.setattr(
        sessions_api,
        "_release_owned_thread_claim",
        skip_claim_release,
    )

    response = await sessions_api.generate_results(
        "session-1",
        db,
        SimpleNamespace(id="user-1"),
    )
    body = "".join([chunk async for chunk in response.body_iterator])

    assert "Winner comparison" in body
    assert "Winner blueprint" in body
    assert '"type": "done"' in body


@pytest.mark.asyncio
async def test_comparison_cas_does_not_overwrite_a_completed_artifact(
    monkeypatch,
) -> None:
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        idol_id="idol-1",
        phase=SessionPhase.COMPARISON,
        user_age=28,
        user_goal="build a product",
        interview_thread_id="thread-1",
    )
    session.idol = Idol(id="idol-1", name="Ada Lovelace", domain="technology")
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = []
    plan_job = SimpleNamespace(
        id="job-1",
        status="pending",
        step="waiting_for_strategy",
        weekly_hours=10,
    )
    db = AsyncMock()
    db.execute.side_effect = [_Result(thread), _Result(thread), _Result(plan_job)]

    async def fake_get_session(*args, **kwargs):
        return session

    async def fake_comparison(*args, **kwargs):
        yield "Losing comparison"

    async def forbidden_blueprint(*args, **kwargs):
        raise AssertionError("a conflicting comparison must stop the pipeline")
        yield "unreachable"

    async def competing_completion(*args, **kwargs):
        session.phase = SessionPhase.COMPLETED
        session.comparison_output = "Winner comparison"
        session.blueprint_output = "Winner blueprint"
        return session, thread

    async def skip_profile_sync(*args, **kwargs):
        return None

    async def skip_claim_release(*args, **kwargs):
        return None

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    _use_session_lock(monkeypatch, session)
    monkeypatch.setattr(sessions_api, "comparison_stream", fake_comparison)
    monkeypatch.setattr(sessions_api, "blueprint_stream", forbidden_blueprint)
    monkeypatch.setattr(
        sessions_api,
        "_lock_interview_completion_state",
        competing_completion,
    )
    monkeypatch.setattr(
        sessions_api,
        "_sync_user_profile_from_interview",
        skip_profile_sync,
    )
    monkeypatch.setattr(
        sessions_api,
        "_release_owned_thread_claim",
        skip_claim_release,
    )

    response = await sessions_api.generate_results(
        "session-1",
        db,
        SimpleNamespace(id="user-1"),
    )
    body = "".join([chunk async for chunk in response.body_iterator])

    assert '"code": "results_artifact_conflict"' in body
    assert session.comparison_output == "Winner comparison"
    assert session.blueprint_output == "Winner blueprint"
    assert '"type": "done"' not in body


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
        comparison_scores_json=_current_scores(),
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
    db.execute.side_effect = [_Result(thread), _Result(thread), _Result(plan_job)]

    async def fake_get_session(*args, **kwargs):
        return session

    async def forbidden_comparison(*args, **kwargs):
        raise AssertionError("comparison must be reused")
        yield "unreachable"

    async def fake_blueprint(*args, **kwargs):
        yield "New blueprint"

    async def skip_profile_sync(*args, **kwargs):
        return None

    async def fake_lock(*args, **kwargs):
        return session, thread

    async def skip_claim_release(*args, **kwargs):
        return None

    delay = MagicMock()
    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    _use_session_lock(monkeypatch, session)
    monkeypatch.setattr(sessions_api, "comparison_stream", forbidden_comparison)
    monkeypatch.setattr(sessions_api, "blueprint_stream", fake_blueprint)
    monkeypatch.setattr(
        sessions_api,
        "_sync_user_profile_from_interview",
        skip_profile_sync,
    )
    monkeypatch.setattr(
        sessions_api,
        "_lock_interview_completion_state",
        fake_lock,
    )
    monkeypatch.setattr(
        sessions_api,
        "_release_owned_thread_claim",
        skip_claim_release,
    )
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


@pytest.mark.asyncio
async def test_confirmed_interview_hours_reach_the_staged_plan_job(monkeypatch) -> None:
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
        comparison_scores_json=_current_scores(),
    )
    session.idol = Idol(id="idol-1", name="Ada Lovelace", domain="technology")
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = _plan_ready_messages(weekly_hours=8)
    db = AsyncMock()
    db.execute.return_value = _Result(thread)
    captured = {}
    plan_job = SimpleNamespace(
        id="job-1",
        status="completed",
        step="done",
        weekly_hours=8,
    )

    async def fake_get_session(*args, **kwargs):
        return session

    async def capture_job(db, *, session, user_id, weekly_hours, focus=None):
        captured["job_weekly_hours"] = weekly_hours
        captured["job_focus"] = focus
        return plan_job

    async def capture_profile(db, *, session, user_id, plan_inputs):
        captured["plan_inputs"] = plan_inputs

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    _use_session_lock(monkeypatch, session)
    monkeypatch.setattr(
        sessions_api,
        "_get_or_create_session_plan_job",
        capture_job,
    )
    monkeypatch.setattr(
        sessions_api,
        "_sync_user_profile_from_interview",
        capture_profile,
    )

    response = await sessions_api.generate_results(
        "session-1",
        db,
        SimpleNamespace(id="user-1"),
    )
    body = "".join([chunk async for chunk in response.body_iterator])

    assert '"type": "done"' in body
    assert captured["job_weekly_hours"] == 8
    assert captured["job_focus"] == "Publish a stable product with ten active users."
    assert captured["plan_inputs"]["weekly_capacity_hours"] == 8
    assert captured["plan_inputs"]["weekly_capacity_source"] == (
        "confirmed_interview_answer"
    )
    assert captured["plan_inputs"]["achievement_inventory"]["answer"].startswith(
        "I shipped"
    )


@pytest.mark.asyncio
async def test_active_results_generation_claim_rejects_a_concurrent_retry(
    monkeypatch,
) -> None:
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        idol_id="idol-1",
        phase=SessionPhase.COMPARISON,
        user_age=28,
        user_goal="build a product",
        interview_thread_id="thread-1",
    )
    session.idol = Idol(id="idol-1", name="Ada Lovelace", domain="technology")
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = _plan_ready_messages()
    thread.interview_claim_key = "results"
    thread.interview_claim_token = "another-request"
    thread.interview_claimed_at = datetime.now(timezone.utc)
    db = AsyncMock()
    db.execute.side_effect = [_Result(thread), _Result(thread)]

    async def fake_get_session(*args, **kwargs):
        return session

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)

    with pytest.raises(HTTPException) as exc_info:
        await sessions_api.generate_results(
            "session-1",
            db,
            SimpleNamespace(id="user-1"),
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail["code"] == "results_generation_in_progress"
