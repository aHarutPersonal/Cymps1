from types import SimpleNamespace

import pytest

from app.api.v1 import sessions
from app.models.chat import MessageRole
from app.models.intake import SessionPhase
from app.schemas.session import GuidedLearningMessageRequest


class _FirstTurnThread:
    """Fail if the route touches an unloaded new-thread relationship."""

    def __init__(self, **kwargs):
        self.id = kwargs["id"]
        self.user_id = kwargs["user_id"]
        self.idol_id = kwargs["idol_id"]

    @property
    def messages(self):
        raise AssertionError("new thread messages must not be lazy-loaded")


class _Database:
    def __init__(self, *, result=None):
        self.added = []
        self.commits = 0
        self.result = result

    def add(self, value):
        self.added.append(value)

    async def flush(self):
        return None

    async def commit(self):
        self.commits += 1

    async def execute(self, _statement):
        return SimpleNamespace(scalar_one=lambda: self.result)


async def _response_body(response) -> str:
    chunks = [chunk async for chunk in response.body_iterator]
    return "".join(
        chunk.decode() if isinstance(chunk, bytes) else chunk
        for chunk in chunks
    )


def _session(*, learning_thread_id=None):
    return SimpleNamespace(
        phase=SessionPhase.COMPLETED,
        learning_thread_id=learning_thread_id,
        idol_id="idol-1",
        idol=SimpleNamespace(name="Mentor", persona=None),
        user_goal="Ship a useful product",
        blueprint_output="Validate one narrow customer problem first.",
    )


def _patch_session_dependencies(monkeypatch, session, stream):
    async def fake_get_session(*_args, **_kwargs):
        return session

    monkeypatch.setattr(sessions, "_get_session", fake_get_session)
    monkeypatch.setattr(sessions, "_persona_to_dict", lambda _persona: {})
    monkeypatch.setattr(sessions, "stream_learnlm", stream)


@pytest.mark.asyncio
async def test_first_guided_learning_turn_never_lazy_loads_empty_history(
    monkeypatch,
) -> None:
    session = _session()
    db = _Database()

    async def fake_stream_learnlm(*_args, **_kwargs):
        yield "Focus on the smallest useful proof."

    _patch_session_dependencies(monkeypatch, session, fake_stream_learnlm)
    monkeypatch.setattr(sessions, "ChatThread", _FirstTurnThread)

    response = await sessions.guided_learning(
        "session-1",
        GuidedLearningMessageRequest(content="What should I focus on first?"),
        db,
        SimpleNamespace(id="user-1"),
    )
    # Thread link and user turn are committed together before provider work.
    assert db.commits == 1
    body = await _response_body(response)

    assert session.learning_thread_id is not None
    assert '"type": "chunk"' in body
    assert '"type": "done"' in body
    messages = [value for value in db.added if hasattr(value, "role")]
    assert [message.role for message in messages] == [
        MessageRole.USER,
        MessageRole.ASSISTANT,
    ]
    assert db.commits == 2
    assert response.headers["x-accel-buffering"] == "no"
    assert response.headers["cache-control"] == "no-cache, no-transform"


@pytest.mark.asyncio
async def test_guided_learning_emits_status_before_starting_provider(
    monkeypatch,
) -> None:
    session = _session()
    db = _Database()
    provider_started = False

    async def blocked_stream(*_args, **_kwargs):
        nonlocal provider_started
        provider_started = True
        yield "later"

    _patch_session_dependencies(monkeypatch, session, blocked_stream)
    monkeypatch.setattr(sessions, "ChatThread", _FirstTurnThread)

    response = await sessions.guided_learning(
        "session-1",
        GuidedLearningMessageRequest(content="Help me prioritize."),
        db,
        SimpleNamespace(id="user-1"),
    )
    iterator = response.body_iterator.__aiter__()

    first = await anext(iterator)

    assert '"type": "status"' in first
    assert provider_started is False
    await iterator.aclose()


@pytest.mark.asyncio
async def test_empty_guided_reply_is_retryable_and_never_persisted(
    monkeypatch,
) -> None:
    session = _session()
    db = _Database()

    async def empty_stream(*_args, **_kwargs):
        if False:
            yield ""

    _patch_session_dependencies(monkeypatch, session, empty_stream)
    monkeypatch.setattr(sessions, "ChatThread", _FirstTurnThread)

    response = await sessions.guided_learning(
        "session-1",
        GuidedLearningMessageRequest(content="Help me prioritize."),
        db,
        SimpleNamespace(id="user-1"),
    )
    body = await _response_body(response)

    assert '"type": "error"' in body
    assert '"type": "done"' not in body
    messages = [value for value in db.added if hasattr(value, "role")]
    assert [message.role for message in messages] == [MessageRole.USER]
    assert db.commits == 1


@pytest.mark.asyncio
async def test_provider_error_is_safe_and_never_persists_an_assistant(
    monkeypatch,
) -> None:
    session = _session()
    db = _Database()

    async def failed_stream(*_args, **_kwargs):
        raise RuntimeError("private provider diagnostics")
        yield  # pragma: no cover - makes this an async generator

    _patch_session_dependencies(monkeypatch, session, failed_stream)
    monkeypatch.setattr(sessions, "ChatThread", _FirstTurnThread)

    response = await sessions.guided_learning(
        "session-1",
        GuidedLearningMessageRequest(content="Help me prioritize."),
        db,
        SimpleNamespace(id="user-1"),
    )
    body = await _response_body(response)

    assert '"type": "error"' in body
    assert '"type": "done"' not in body
    assert "private provider diagnostics" not in body
    messages = [value for value in db.added if hasattr(value, "role")]
    assert [message.role for message in messages] == [MessageRole.USER]
    assert db.commits == 1


@pytest.mark.asyncio
async def test_retry_reuses_the_pending_user_turn(monkeypatch) -> None:
    content = "What should I focus on first?"
    pending_user = SimpleNamespace(role=MessageRole.USER, content=content)
    thread = SimpleNamespace(id="thread-1", messages=[pending_user])
    session = _session(learning_thread_id="thread-1")
    db = _Database(result=thread)
    captured = {}

    async def successful_stream(*, system_prompt, user_message):
        captured["system_prompt"] = system_prompt
        captured["user_message"] = user_message
        yield "Build one proof."

    _patch_session_dependencies(monkeypatch, session, successful_stream)

    response = await sessions.guided_learning(
        "session-1",
        GuidedLearningMessageRequest(content=content),
        db,
        SimpleNamespace(id="user-1"),
    )
    body = await _response_body(response)

    assert '"type": "done"' in body
    assert captured["user_message"] == content
    assert content not in captured["system_prompt"]
    messages = [value for value in db.added if hasattr(value, "role")]
    assert [message.role for message in messages] == [MessageRole.ASSISTANT]


@pytest.mark.asyncio
async def test_new_question_omits_an_abandoned_pending_turn(monkeypatch) -> None:
    abandoned = "An unanswered old question"
    pending_user = SimpleNamespace(role=MessageRole.USER, content=abandoned)
    thread = SimpleNamespace(id="thread-1", messages=[pending_user])
    session = _session(learning_thread_id="thread-1")
    db = _Database(result=thread)
    captured = {}

    async def successful_stream(*, system_prompt, user_message):
        captured["system_prompt"] = system_prompt
        captured["user_message"] = user_message
        yield "Take the next small step."

    _patch_session_dependencies(monkeypatch, session, successful_stream)

    response = await sessions.guided_learning(
        "session-1",
        GuidedLearningMessageRequest(content="A different question"),
        db,
        SimpleNamespace(id="user-1"),
    )
    body = await _response_body(response)

    assert '"type": "done"' in body
    assert abandoned not in captured["system_prompt"]
    assert captured["user_message"] == "A different question"
    messages = [value for value in db.added if hasattr(value, "role")]
    assert [message.role for message in messages] == [
        MessageRole.USER,
        MessageRole.ASSISTANT,
    ]


def test_guided_history_cap_keeps_the_newest_context() -> None:
    messages = [
        SimpleNamespace(
            role=MessageRole.ASSISTANT,
            content=f"message-{index}-" + ("x" * 70),
        )
        for index in range(4)
    ]

    serialized = sessions._build_chat_history_json(messages, max_chars=130)

    assert len(serialized) <= 130
    assert "message-3" in serialized
    assert "message-0" not in serialized
