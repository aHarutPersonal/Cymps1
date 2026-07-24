from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import anyio
import pytest
from fastapi import HTTPException
from sqlalchemy.dialects import postgresql

from app.api.v1 import sessions
from app.models.chat import ChatMessage, ChatThread, MessageRole
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.user import User
from app.schemas.session import InterviewMessageRequest


class _Database:
    def __init__(self, thread: ChatThread):
        self.thread = thread
        self.added = []
        self.commits = 0
        self.statements = []

    def add(self, value):
        self.added.append(value)

    async def flush(self):
        return None

    async def commit(self):
        self.commits += 1

    async def rollback(self):
        return None

    async def execute(self, _statement):
        self.statements.append(_statement)
        return SimpleNamespace(scalar_one_or_none=lambda: self.thread)


def _session(
    *,
    turn: int = 1,
    phase: SessionPhase = SessionPhase.INTERVIEW,
) -> IntakeSession:
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        phase=phase,
        user_age=28,
        user_financial_status="employed",
        user_interests=["Technology"],
        user_goal="Build a useful product",
        interview_thread_id="thread-1",
        interview_turn_count=turn,
        idol_facts_json={"raw_facts": "verified"},
    )
    session.idol = Idol(id="idol-1", name="Elon Musk", domain="technology")
    return session


def _thread(messages: list[ChatMessage]) -> ChatThread:
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = messages
    return thread


def _message(
    index: int,
    role: MessageRole,
    content: str,
    response_ui_json: dict | None = None,
    *,
    reply_to_message_id: str | None = None,
    generation_status: str | None = None,
) -> ChatMessage:
    return ChatMessage(
        id=f"message-{index}",
        thread_id="thread-1",
        role=role,
        content=content,
        response_ui_json=response_ui_json,
        reply_to_message_id=reply_to_message_id,
        generation_status=generation_status,
    )


def _thread_awaiting_final_plan_input() -> ChatThread:
    keys = [
        "achievement_inventory",
        "current_capability",
        "weekly_hours",
        "target_outcome",
        "constraints_resources",
        "learning_habits_support",
    ]
    answers = [
        "I shipped a prototype used by five people.",
        "I can build and test a small app without a tutorial.",
        "8 hours per week",
        "A published product with ten active users.",
        "A laptop and test users help; weekday time is the constraint.",
    ]
    messages: list[ChatMessage] = []
    for index, key in enumerate(keys, start=1):
        question_id = f"message-{index * 2 - 1}"
        messages.append(
            _message(
                index * 2 - 1,
                MessageRole.ASSISTANT,
                f"Question for {key}",
                {"version": 1, "kind": "text", "answer_key": key},
            )
        )
        if index <= len(answers):
            messages.append(
                _message(
                    index * 2,
                    MessageRole.USER,
                    answers[index - 1],
                    reply_to_message_id=question_id,
                    generation_status="completed",
                )
            )
    return _thread(messages)


async def _body(response) -> str:
    chunks = [chunk async for chunk in response.body_iterator]
    return "".join(
        chunk.decode() if isinstance(chunk, bytes) else chunk for chunk in chunks
    )


def _patch_session(monkeypatch, session: IntakeSession) -> None:
    async def fake_get_session(*_args, **_kwargs):
        return session

    async def fake_lock(db, **_kwargs):
        return session, db.thread

    async def fake_session_lock(*_args, **_kwargs):
        return session

    monkeypatch.setattr(sessions, "_get_session", fake_get_session)
    monkeypatch.setattr(sessions, "_lock_interview_session_state", fake_session_lock)
    monkeypatch.setattr(sessions, "_lock_interview_completion_state", fake_lock)
    monkeypatch.setattr(sessions, "_persona_to_dict", lambda _persona: {})


@pytest.mark.asyncio
async def test_interview_retry_reuses_the_unanswered_user_turn(monkeypatch):
    answer = "I can commit ten hours each week."
    thread = _thread([_message(1, MessageRole.USER, answer)])
    session = _session()
    db = _Database(thread)
    captured = {}

    def fake_render(*_args, **kwargs):
        captured.update(kwargs)
        return "system", "question"

    async def successful_stream(*_args, **_kwargs):
        yield "What proof will you build first?"

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "_render_interview_prompts", fake_render)
    monkeypatch.setattr(sessions, "interview_stream", successful_stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content=answer),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    body = await _body(response)

    assert '"type": "done"' in body
    assert captured["user_message"] == answer
    assert answer not in captured["chat_history_json"]
    assert [message.role for message in db.added] == [MessageRole.ASSISTANT]
    assert db.commits == 2


@pytest.mark.asyncio
async def test_repeated_kickoff_replays_the_durable_opening_question(monkeypatch):
    opening = "What specific problem are you determined to solve?"
    response_ui = {
        "version": 1,
        "kind": "single_choice",
        "options": ["A product", "A service", "Still deciding"],
        "allow_custom": True,
    }
    thread = _thread([
        _message(1, MessageRole.ASSISTANT, opening, response_ui)
    ])
    session = _session(turn=1)
    db = _Database(thread)

    async def forbidden_stream(*_args, **_kwargs):
        raise AssertionError("a completed opening turn must not call the model")
        yield  # pragma: no cover

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "interview_stream", forbidden_stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(
            content="Hi — I’m ready. Ask me your first question.",
            is_kickoff=True,
        ),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    body = await _body(response)

    assert opening in body
    assert '"type": "done"' in body
    assert '"turn": 1' in body
    assert '"kind": "single_choice"' in body
    assert '"question_id": "message-1"' in body
    assert db.added == []
    assert db.commits == 1


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("phase", "transition"),
    [
        (SessionPhase.INTERVIEW, False),
        (SessionPhase.COMPARISON, True),
    ],
)
async def test_lost_done_retry_replays_committed_response_without_advancing(
    monkeypatch,
    phase,
    transition,
):
    answer = "I can commit ten hours each week."
    response_ui = {
        "version": 1,
        "kind": "number",
        "min": 2,
        "max": 60,
        "step": 1,
        "initial": 10,
        "unit": "hours per week",
    }
    thread = _thread([
        _message(1, MessageRole.ASSISTANT, "How much time can you commit?"),
        _message(
            2,
            MessageRole.USER,
            answer,
            reply_to_message_id="message-1",
            generation_status="completed",
        ),
        _message(
            3,
            MessageRole.ASSISTANT,
            "What will you build in those hours?",
            None if transition else response_ui,
            reply_to_message_id="message-2",
        ),
    ])
    session = _session(turn=5 if transition else 2, phase=phase)
    db = _Database(thread)

    async def forbidden_stream(*_args, **_kwargs):
        raise AssertionError("a committed response must not call the model")
        yield  # pragma: no cover

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "interview_stream", forbidden_stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(
            content=answer,
            question_id="message-1",
        ),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    body = await _body(response)

    assert "What will you build in those hours?" in body
    assert f'"phase_transition": {str(transition).lower()}' in body
    assert '"question_id": "message-3"' in body
    assert ('"response_ui"' in body) is (not transition)
    assert db.added == []
    assert db.commits == 1


@pytest.mark.asyncio
async def test_waiting_request_refreshes_phase_before_replaying_final_response(
    monkeypatch,
):
    answer = "I can commit ten hours each week."
    thread = _thread([
        _message(1, MessageRole.ASSISTANT, "How much time can you commit?"),
        _message(
            2,
            MessageRole.USER,
            answer,
            reply_to_message_id="message-1",
            generation_status="completed",
        ),
        _message(
            3,
            MessageRole.ASSISTANT,
            "I have enough to build your diagnosis.",
            reply_to_message_id="message-2",
        ),
    ])
    stale_session = _session(turn=4)
    current_session = _session(turn=5, phase=SessionPhase.COMPARISON)
    db = _Database(thread)
    _patch_session(monkeypatch, stale_session)

    async def lock_current_session(*_args, **_kwargs):
        return current_session

    monkeypatch.setattr(
        sessions,
        "_lock_interview_session_state",
        lock_current_session,
    )

    response = await sessions.interview(
        session_id=stale_session.id,
        data=InterviewMessageRequest(
            content=answer,
            question_id="message-1",
        ),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    body = await _body(response)

    assert '"phase_transition": true' in body
    assert '"response_ui"' not in body


@pytest.mark.asyncio
async def test_overlapping_answer_is_rejected_while_generation_is_pending(
    monkeypatch,
):
    answer = "I can commit ten hours each week."
    thread = _thread([
        _message(1, MessageRole.ASSISTANT, "How much time can you commit?"),
        _message(
            2,
            MessageRole.USER,
            answer,
            reply_to_message_id="message-1",
            generation_status="pending",
        ),
    ])
    thread.interview_claim_key = "message-1"
    thread.interview_claim_token = "00000000-0000-0000-0000-000000000001"
    thread.interview_claimed_at = datetime.now(timezone.utc)
    session = _session(turn=1)
    db = _Database(thread)

    async def forbidden_stream(*_args, **_kwargs):
        raise AssertionError("an in-flight answer must not call the model twice")
        yield  # pragma: no cover

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "interview_stream", forbidden_stream)

    with pytest.raises(HTTPException) as exc_info:
        await sessions.interview(
            session_id=session.id,
            data=InterviewMessageRequest(
                content=answer,
                question_id="message-1",
            ),
            db=db,
            current_user=User(
                id="user-1",
                email="learner@example.com",
                password_hash="hash",
            ),
        )

    error = exc_info.value
    assert getattr(error, "status_code", None) == 409
    assert error.detail["code"] == "interview_turn_in_progress"
    assert db.added == []
    assert "FOR UPDATE OF chat_threads" in str(
        db.statements[0].compile(dialect=postgresql.dialect())
    )


@pytest.mark.asyncio
async def test_expired_answer_claim_is_safely_reclaimed(monkeypatch):
    answer = "I can commit ten hours each week."
    pending_answer = _message(
        2,
        MessageRole.USER,
        answer,
        reply_to_message_id="message-1",
        generation_status="pending",
    )
    thread = _thread([
        _message(1, MessageRole.ASSISTANT, "How much time can you commit?"),
        pending_answer,
    ])
    thread.interview_claim_key = "message-1"
    thread.interview_claim_token = "00000000-0000-0000-0000-000000000001"
    thread.interview_claimed_at = (
        datetime.now(timezone.utc)
        - sessions.INTERVIEW_GENERATION_LEASE
        - timedelta(seconds=1)
    )
    session = _session(turn=1)
    db = _Database(thread)

    async def successful_stream(*_args, **_kwargs):
        yield "What will you build first?"

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(
        sessions,
        "_render_interview_prompts",
        lambda *_args, **_kwargs: ("system", "question"),
    )
    monkeypatch.setattr(sessions, "interview_stream", successful_stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(
            content=answer,
            question_id="message-1",
        ),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    body = await _body(response)

    assert '"type": "done"' in body
    assert pending_answer.generation_status == "completed"
    assert thread.interview_claim_token is None
    assert [message.role for message in db.added] == [MessageRole.ASSISTANT]


@pytest.mark.asyncio
async def test_overlapping_kickoff_is_rejected_by_the_thread_lease(monkeypatch):
    thread = _thread([])
    thread.interview_claim_key = "kickoff"
    thread.interview_claim_token = "00000000-0000-0000-0000-000000000001"
    thread.interview_claimed_at = datetime.now(timezone.utc)
    session = _session(turn=0)
    db = _Database(thread)
    _patch_session(monkeypatch, session)

    with pytest.raises(HTTPException) as exc_info:
        await sessions.interview(
            session_id=session.id,
            data=InterviewMessageRequest(
                content="Hi — I’m ready. Ask me your first question.",
                is_kickoff=True,
            ),
            db=db,
            current_user=User(
                id="user-1",
                email="learner@example.com",
                password_hash="hash",
            ),
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail["code"] == "interview_turn_in_progress"
    assert db.added == []


@pytest.mark.asyncio
async def test_failed_answer_claim_can_be_retried_without_duplicate_user_row(
    monkeypatch,
):
    answer = "I can commit ten hours each week."
    pending_answer = _message(
        2,
        MessageRole.USER,
        answer,
        reply_to_message_id="message-1",
        generation_status="failed",
    )
    thread = _thread([
        _message(1, MessageRole.ASSISTANT, "How much time can you commit?"),
        pending_answer,
    ])
    session = _session(turn=1)
    db = _Database(thread)

    async def successful_stream(*_args, **_kwargs):
        yield "What will you build first?"

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(
        sessions,
        "_render_interview_prompts",
        lambda *_args, **_kwargs: ("system", "question"),
    )
    monkeypatch.setattr(sessions, "interview_stream", successful_stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(
            content=answer,
            question_id="message-1",
        ),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    body = await _body(response)
    assistant = next(
        message
        for message in db.added
        if message.role == MessageRole.ASSISTANT
    )

    assert '"type": "done"' in body
    assert [message.role for message in db.added] == [MessageRole.ASSISTANT]
    assert pending_answer.generation_status == "completed"
    assert assistant.reply_to_message_id == "message-2"


@pytest.mark.asyncio
async def test_abandoned_nonfinal_response_is_not_replayed_as_completion(monkeypatch):
    answer = "I can commit ten hours each week."
    thread = _thread([
        _message(1, MessageRole.ASSISTANT, "How much time can you commit?"),
        _message(
            2,
            MessageRole.USER,
            answer,
            reply_to_message_id="message-1",
            generation_status="completed",
        ),
        _message(
            3,
            MessageRole.ASSISTANT,
            "What will you build next?",
            {"version": 1, "kind": "text"},
            reply_to_message_id="message-2",
        ),
    ])
    session = _session(turn=2, phase=SessionPhase.COMPLETED)
    db = _Database(thread)
    _patch_session(monkeypatch, session)

    with pytest.raises(HTTPException) as exc_info:
        await sessions.interview(
            session_id=session.id,
            data=InterviewMessageRequest(
                content=answer,
                question_id="message-1",
            ),
            db=db,
            current_user=User(
                id="user-1",
                email="learner@example.com",
                password_hash="hash",
            ),
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail["code"] == "interview_session_changed"


@pytest.mark.asyncio
async def test_abandon_during_final_generation_cannot_restore_comparison(monkeypatch):
    thread = _thread_awaiting_final_plan_input()
    starting_session = _session(turn=6)
    abandoned_session = _session(turn=6, phase=SessionPhase.COMPLETED)
    db = _Database(thread)

    async def successful_stream(*_args, **_kwargs):
        yield "I have enough to build your diagnosis. [INTERVIEW_COMPLETE]"

    async def lock_abandoned_state(db, **_kwargs):
        return abandoned_session, db.thread

    _patch_session(monkeypatch, starting_session)
    monkeypatch.setattr(
        sessions,
        "_render_interview_prompts",
        lambda *_args, **_kwargs: ("system", "question"),
    )
    monkeypatch.setattr(
        sessions,
        "_lock_interview_completion_state",
        lock_abandoned_state,
    )
    monkeypatch.setattr(sessions, "interview_stream", successful_stream)

    response = await sessions.interview(
        session_id=starting_session.id,
        data=InterviewMessageRequest(content="My final answer"),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    body = await _body(response)

    assert '"code": "interview_session_changed"' in body
    assert '"type": "done"' not in body
    assert abandoned_session.phase == SessionPhase.COMPLETED
    assert [message.role for message in db.added] == [MessageRole.USER]
    assert db.added[0].generation_status == "failed"
    assert thread.interview_claim_token is None


@pytest.mark.asyncio
async def test_interview_provider_failure_is_safe_and_retryable(monkeypatch):
    thread = _thread([_message(1, MessageRole.ASSISTANT, "Opening question")])
    session = _session(turn=1)
    db = _Database(thread)

    def fake_render(*_args, **_kwargs):
        return "system", "question"

    async def failed_stream(*_args, **_kwargs):
        raise RuntimeError("private provider diagnostics")
        yield  # pragma: no cover

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "_render_interview_prompts", fake_render)
    monkeypatch.setattr(sessions, "interview_stream", failed_stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content="My answer"),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    body = await _body(response)

    assert '"type": "error"' in body
    assert '"type": "done"' not in body
    assert "private provider diagnostics" not in body
    assert [message.role for message in db.added] == [MessageRole.USER]
    assert db.added[0].generation_status == "failed"
    assert db.commits == 2


@pytest.mark.asyncio
async def test_stream_cancellation_shields_claim_cleanup(monkeypatch):
    thread = _thread([_message(1, MessageRole.ASSISTANT, "Opening question")])
    session = _session(turn=1)

    class CancellableDatabase(_Database):
        async def commit(self):
            await anyio.sleep(0)
            self.commits += 1

        async def rollback(self):
            await anyio.sleep(0)

    db = CancellableDatabase(thread)
    stream_started = anyio.Event()

    async def cancelled_stream(*_args, **_kwargs):
        stream_started.set()
        await anyio.sleep_forever()
        yield  # pragma: no cover

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(
        sessions,
        "_render_interview_prompts",
        lambda *_args, **_kwargs: ("system", "question"),
    )
    monkeypatch.setattr(sessions, "interview_stream", cancelled_stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content="My answer"),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )

    async def consume_stream() -> None:
        async for _ in response.body_iterator:
            pass

    async with anyio.create_task_group() as task_group:
        task_group.start_soon(consume_stream)
        await stream_started.wait()
        task_group.cancel_scope.cancel()

    assert [message.role for message in db.added] == [MessageRole.USER]
    assert db.added[0].generation_status == "failed"
    assert thread.interview_claim_token is None
    assert db.commits == 2
