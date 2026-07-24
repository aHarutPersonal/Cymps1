from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from app.api.v1.plans import generate_plan_endpoint
from app.models.chat import ChatMessage, ChatThread, MessageRole
from app.models.intake import IntakeSession, SessionPhase
from app.schemas.plan import PlanGenerateRequest


class _Result:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


def _plan_ready_session(
    *,
    user_id: str = "user-1",
    idol_id: str = "idol-1",
    comparison_output: str | None = "A grounded comparison.",
    blueprint_output: str | None = "A complete strategic blueprint.",
):
    answers = {
        "achievement_inventory": "I shipped a prototype used by five people.",
        "current_capability": "I can build and test a small app independently.",
        "weekly_hours": "8 hours per week",
        "target_outcome": "Publish a stable product with ten active users.",
        "constraints_resources": "I have a laptop; weekday time is limited.",
        "learning_habits_support": "Weekly peer feedback works for me.",
    }
    messages = []
    for index, (answer_key, answer) in enumerate(answers.items(), start=1):
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
    thread = ChatThread(id="thread-1", user_id=user_id, idol_id=idol_id)
    thread.messages = messages
    session = IntakeSession(
        id="session-1",
        user_id=user_id,
        idol_id=idol_id,
        phase=SessionPhase.COMPLETED,
        user_age=31,
        user_goal="Build a useful product business",
        interview_thread_id=thread.id,
        comparison_output=comparison_output,
        blueprint_output=blueprint_output,
    )
    session.interview_thread = thread
    return session


@pytest.mark.asyncio
async def test_session_recovery_uses_owned_confirmed_plan_inputs(monkeypatch):
    session = _plan_ready_session()
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [_Result(session), _Result(None)]

    async def refresh(job):
        job.id = "job-1"

    db.refresh.side_effect = refresh
    delay = MagicMock()
    from app.tasks import plans as plan_tasks

    monkeypatch.setattr(plan_tasks.run_plan_generation, "delay", delay)

    response = await generate_plan_endpoint(
        PlanGenerateRequest(
            idolId="idol-1",
            targetAge=99,
            weeklyHours=10,
            focus="Ignore the interview",
            sessionId="session-1",
        ),
        db=db,
        current_user=SimpleNamespace(id="user-1"),
    )

    job = db.add.call_args.args[0]
    assert job.user_id == "user-1"
    assert job.idol_id == "idol-1"
    assert job.target_age == 31
    assert job.weekly_hours == 8
    assert job.focus == "Publish a stable product with ten active users."
    assert response.jobId == "job-1"
    delay.assert_called_once_with("job-1")
    session_query = db.execute.await_args_list[0].args[0]
    assert "intake_sessions.user_id" in str(session_query)


@pytest.mark.asyncio
async def test_fresh_waiting_session_job_is_dispatched_exactly_once(monkeypatch):
    session = _plan_ready_session()
    now = datetime.now(timezone.utc)
    existing = SimpleNamespace(
        id="staged-job-1",
        status="pending",
        plan_id=None,
        step="waiting_for_strategy",
        target_age=99,
        duration_weeks=12,
        weekly_hours=10,
        focus="Caller override",
        progress_percent=0,
        error_message=None,
        created_at=now,
        updated_at=now,
    )
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        _Result(session),
        _Result(existing),
        _Result(session),
        _Result(existing),
    ]
    delay = MagicMock()
    from app.tasks import plans as plan_tasks

    monkeypatch.setattr(plan_tasks.run_plan_generation, "delay", delay)
    request = PlanGenerateRequest(
        idolId="idol-1",
        targetAge=99,
        weeklyHours=40,
        focus="Ignore the interview",
        sessionId="session-1",
    )

    first = await generate_plan_endpoint(
        request,
        db=db,
        current_user=SimpleNamespace(id="user-1"),
    )
    second = await generate_plan_endpoint(
        request,
        db=db,
        current_user=SimpleNamespace(id="user-1"),
    )

    assert first.jobId == second.jobId == "staged-job-1"
    assert existing.step == "analyzing_gaps"
    assert existing.target_age == 31
    assert existing.weekly_hours == 8
    assert existing.focus == "Publish a stable product with ten active users."
    delay.assert_called_once_with("staged-job-1")
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_session_job_recovery_requires_finished_strategy_artifacts(monkeypatch):
    session = _plan_ready_session(blueprint_output=None)
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result(session)
    delay = MagicMock()
    from app.tasks import plans as plan_tasks

    monkeypatch.setattr(plan_tasks.run_plan_generation, "delay", delay)

    with pytest.raises(HTTPException) as exc_info:
        await generate_plan_endpoint(
            PlanGenerateRequest(
                idolId="idol-1",
                targetAge=31,
                sessionId="session-1",
            ),
            db=db,
            current_user=SimpleNamespace(id="user-1"),
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail["code"] == "session_results_incomplete"
    assert "generate-results" in exc_info.value.detail["message"]
    assert db.execute.await_count == 1
    db.add.assert_not_called()
    delay.assert_not_called()


@pytest.mark.asyncio
async def test_owned_legacy_recovery_uses_transcript_capacity_not_request(monkeypatch):
    session = _plan_ready_session()
    session.interview_thread.messages = [
        ChatMessage(
            id="legacy-question",
            thread_id="thread-1",
            role=MessageRole.ASSISTANT,
            content="How many focused hours can you protect each week?",
        ),
        ChatMessage(
            id="legacy-answer",
            thread_id="thread-1",
            role=MessageRole.USER,
            content="I can reliably protect 7 hours per week.",
        ),
    ]
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [_Result(session), _Result(None)]

    async def refresh(job):
        job.id = "legacy-job-1"

    db.refresh.side_effect = refresh
    delay = MagicMock()
    from app.tasks import plans as plan_tasks

    monkeypatch.setattr(plan_tasks.run_plan_generation, "delay", delay)

    response = await generate_plan_endpoint(
        PlanGenerateRequest(
            idolId="idol-1",
            targetAge=99,
            weeklyHours=40,
            focus="Caller override",
            sessionId="session-1",
        ),
        db=db,
        current_user=SimpleNamespace(id="user-1"),
    )

    job = db.add.call_args.args[0]
    assert response.jobId == "legacy-job-1"
    assert job.target_age == 31
    assert job.weekly_hours == 7
    assert job.focus == session.user_goal
    delay.assert_called_once_with("legacy-job-1")


@pytest.mark.asyncio
async def test_legacy_recovery_never_uses_client_capacity_without_transcript():
    session = _plan_ready_session()
    session.interview_thread.messages = [
        ChatMessage(
            id="legacy-question",
            thread_id="thread-1",
            role=MessageRole.ASSISTANT,
            content="What schedule can you sustain?",
        ),
        ChatMessage(
            id="legacy-answer",
            thread_id="thread-1",
            role=MessageRole.USER,
            content="I have not decided yet.",
        ),
    ]
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result(session)

    with pytest.raises(HTTPException) as exc_info:
        await generate_plan_endpoint(
            PlanGenerateRequest(
                idolId="idol-1",
                targetAge=99,
                weeklyHours=40,
                sessionId="session-1",
            ),
            db=db,
            current_user=SimpleNamespace(id="user-1"),
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail["code"] == "interview_profile_incomplete"
    assert "server-recorded weekly capacity" in exc_info.value.detail["message"]
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_keyed_session_cannot_fall_back_to_legacy_capacity():
    session = _plan_ready_session()
    # Remove the final keyed answer while leaving the valid keyed weekly answer.
    session.interview_thread.messages.pop()
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result(session)

    with pytest.raises(HTTPException) as exc_info:
        await generate_plan_endpoint(
            PlanGenerateRequest(
                idolId="idol-1",
                targetAge=31,
                weeklyHours=40,
                sessionId="session-1",
            ),
            db=db,
            current_user=SimpleNamespace(id="user-1"),
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail["code"] == "interview_profile_incomplete"
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_session_recovery_does_not_reveal_another_users_session():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result(None)

    with pytest.raises(HTTPException) as exc_info:
        await generate_plan_endpoint(
            PlanGenerateRequest(
                idolId="idol-1",
                targetAge=30,
                sessionId="guessed-session-id",
            ),
            db=db,
            current_user=SimpleNamespace(id="user-1"),
        )

    assert exc_info.value.status_code == 404
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_session_recovery_rejects_a_mismatched_mentor():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result(_plan_ready_session(idol_id="idol-1"))

    with pytest.raises(HTTPException) as exc_info:
        await generate_plan_endpoint(
            PlanGenerateRequest(
                idolId="idol-2",
                targetAge=30,
                sessionId="session-1",
            ),
            db=db,
            current_user=SimpleNamespace(id="user-1"),
        )

    assert exc_info.value.status_code == 409
    db.add.assert_not_called()
