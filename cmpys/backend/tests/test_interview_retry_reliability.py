from types import SimpleNamespace

import pytest

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

    def add(self, value):
        self.added.append(value)

    async def flush(self):
        return None

    async def commit(self):
        self.commits += 1

    async def execute(self, _statement):
        return SimpleNamespace(scalar_one_or_none=lambda: self.thread)


def _session(*, turn: int = 1) -> IntakeSession:
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        phase=SessionPhase.INTERVIEW,
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


def _message(index: int, role: MessageRole, content: str) -> ChatMessage:
    return ChatMessage(
        id=f"message-{index}",
        thread_id="thread-1",
        role=role,
        content=content,
    )


async def _body(response) -> str:
    chunks = [chunk async for chunk in response.body_iterator]
    return "".join(
        chunk.decode() if isinstance(chunk, bytes) else chunk for chunk in chunks
    )


def _patch_session(monkeypatch, session: IntakeSession) -> None:
    async def fake_get_session(*_args, **_kwargs):
        return session

    monkeypatch.setattr(sessions, "_get_session", fake_get_session)
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
    thread = _thread([_message(1, MessageRole.ASSISTANT, opening)])
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
    assert db.added == []
    assert db.commits == 1


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
    assert db.commits == 1
