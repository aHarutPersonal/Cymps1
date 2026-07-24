import pytest
from fastapi.responses import StreamingResponse
from types import SimpleNamespace

from app.api.v1 import sessions as sessions_api
from app.models.chat import ChatThread
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.user import User
from app.schemas.session import InterviewMessageRequest
from app.services import gemini


@pytest.mark.asyncio
async def test_interview_stream_uses_provider_streaming(monkeypatch):
    class ResponseChunk:
        def __init__(self, text: str):
            self.text = text

    class FakeModels:
        async def generate_content(self, **kwargs):
            raise AssertionError("interview_stream should not wait for full content")

        def generate_content_stream(self, **kwargs):
            async def stream():
                yield ResponseChunk("Hel")
                yield ResponseChunk("lo")

            return stream()

    class FakeClient:
        class Aio:
            models = FakeModels()

        aio = Aio()

    monkeypatch.setattr(gemini, "_gemini_client", lambda: FakeClient())

    chunks = [
        chunk
        async for chunk in gemini.interview_stream(
            system_prompt="system",
            user_message="question",
        )
    ]

    assert chunks == ["Hel", "lo"]


@pytest.mark.asyncio
async def test_interview_stream_awaits_coroutine_provider_stream(monkeypatch):
    class ResponseChunk:
        def __init__(self, text: str):
            self.text = text

    class FakeModels:
        async def generate_content_stream(self, **kwargs):
            async def stream():
                yield ResponseChunk("Async")
                yield ResponseChunk(" stream")

            return stream()

    class FakeClient:
        class Aio:
            models = FakeModels()

        aio = Aio()

    monkeypatch.setattr(gemini, "_gemini_client", lambda: FakeClient())

    chunks = [
        chunk
        async for chunk in gemini.interview_stream(
            system_prompt="system",
            user_message="question",
        )
    ]

    assert chunks == ["Async", " stream"]


@pytest.mark.asyncio
async def test_agentic_streams_have_a_bounded_provider_timeout(monkeypatch):
    captured = {}

    class FakeModels:
        def generate_content_stream(self, **kwargs):
            captured["config"] = kwargs["config"]

            async def stream():
                yield SimpleNamespace(text="ok")

            return stream()

    client = SimpleNamespace(aio=SimpleNamespace(models=FakeModels()))
    monkeypatch.setattr(gemini, "_gemini_client", lambda: client)

    chunks = [
        chunk
        async for chunk in gemini.interview_stream(
            system_prompt="system",
            user_message="question",
        )
    ]

    assert chunks == ["ok"]
    assert captured["config"].http_options.timeout == 60_000


@pytest.mark.asyncio
async def test_guided_stream_has_a_short_response_budget(monkeypatch):
    captured = {}

    class FakeModels:
        def generate_content_stream(self, **kwargs):
            captured["config"] = kwargs["config"]

            async def stream():
                yield SimpleNamespace(text="A focused answer.")

            return stream()

    client = SimpleNamespace(aio=SimpleNamespace(models=FakeModels()))
    monkeypatch.setattr(gemini, "_gemini_client", lambda: client)

    chunks = [
        chunk
        async for chunk in gemini.stream_learnlm(
            system_prompt="system",
            user_message="question",
        )
    ]

    assert chunks == ["A focused answer."]
    assert captured["config"].max_output_tokens == 900


@pytest.mark.asyncio
async def test_stream_rejects_an_explicit_non_stop_finish_reason(monkeypatch):
    class FakeModels:
        def generate_content_stream(self, **_kwargs):
            async def stream():
                yield SimpleNamespace(
                    text="A truncated answer",
                    candidates=[
                        SimpleNamespace(
                            finish_reason=SimpleNamespace(name="MAX_TOKENS")
                        )
                    ],
                )

            return stream()

    client = SimpleNamespace(aio=SimpleNamespace(models=FakeModels()))
    monkeypatch.setattr(gemini, "_gemini_client", lambda: client)

    with pytest.raises(RuntimeError, match="ended incompletely"):
        _ = [
            chunk
            async for chunk in gemini.stream_learnlm(
                system_prompt="system",
                user_message="question",
            )
        ]


@pytest.mark.asyncio
async def test_agentic_streams_use_expected_grounding_policy(monkeypatch):
    calls = []

    async def fake_stream_generate(**kwargs):
        calls.append(kwargs)
        yield "ok"

    monkeypatch.setattr(gemini, "_stream_generate", fake_stream_generate)

    assert [
        chunk
        async for chunk in gemini.interview_stream(
            system_prompt="system",
            user_message="interview",
        )
    ] == ["ok"]
    assert [
        chunk
        async for chunk in gemini.comparison_stream(
            system_prompt="system",
            user_message="comparison",
        )
    ] == ["ok"]
    assert [
        chunk
        async for chunk in gemini.blueprint_stream(
            system_prompt="system",
            user_message="blueprint",
        )
    ] == ["ok"]

    assert [call["grounded"] for call in calls] == [False, True, False]


def test_interview_prompts_include_chat_history_exactly_once():
    marker = "HISTORY_SENTINEL_8f31"
    session = SimpleNamespace(
        user_age=24,
        user_financial_status="student",
        user_interests=["technology"],
        user_goal="build useful software",
        idol_facts_json={"raw_facts": "verified fact"},
    )

    system_prompt, user_prompt = sessions_api._render_interview_prompts(
        session,
        idol_name="Ada Lovelace",
        idol_persona={},
        chat_history_json=f'[{marker}]',
        current_turn=2,
        user_message="I practice every morning.",
    )

    assert marker not in system_prompt
    assert marker in user_prompt
    assert (system_prompt + user_prompt).count(marker) == 1


@pytest.mark.asyncio
async def test_interview_returns_sse_before_fetching_missing_idol_facts(monkeypatch):
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        phase=SessionPhase.INTERVIEW,
        user_age=24,
        user_financial_status="student",
        user_interests=["Technology"],
        interview_thread_id="thread-1",
        interview_turn_count=0,
        idol_facts_json=None,
    )
    session.idol = Idol(id="idol-1", name="Bill Gates", domain="technology")

    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = []

    class FakeResult:
        def scalar_one_or_none(self):
            return thread

        def scalar_one(self):
            return 0

    class FakeDb:
        def add(self, item):
            pass

        async def flush(self):
            pass

        async def commit(self):
            pass

        async def execute(self, stmt):
            return FakeResult()

    async def fake_get_session(session_id, user_id, db):
        return session

    async def forbidden_grounding(*args, **kwargs):
        raise AssertionError("missing idol facts should not block SSE start")

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    monkeypatch.setattr(sessions_api, "generate_with_grounding", forbidden_grounding)

    response = await sessions_api.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content="I am a QA engineer"),
        db=FakeDb(),
        current_user=User(id="user-1", email="coder@example.com", password_hash="hash"),
    )

    assert isinstance(response, StreamingResponse)


@pytest.mark.asyncio
async def test_sync_interview_turn_count_uses_persisted_assistant_messages():
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        phase=SessionPhase.INTERVIEW,
        user_age=24,
        user_financial_status="student",
        user_interests=["Technology"],
        interview_thread_id="thread-1",
        interview_turn_count=3,
    )

    class FakeResult:
        def scalar_one(self):
            return 1

    class FakeDb:
        async def execute(self, stmt):
            return FakeResult()

    await sessions_api._sync_interview_turn_count(session, FakeDb())

    assert session.interview_turn_count == 1
