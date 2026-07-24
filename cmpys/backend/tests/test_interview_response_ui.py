import json
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.v1 import sessions
from app.models.chat import ChatMessage, ChatThread, MessageRole
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.user import User
from app.schemas.session import InterviewMessageRequest, InterviewResponseInput


def test_response_input_validates_choice_and_forces_custom_answer():
    response_input = InterviewResponseInput.model_validate(
        {
            "version": 1,
            "kind": "single_choice",
            "options": ["  None yet  ", "A peer", "a peer", "A mentor"],
            "allow_custom": False,
        }
    )

    assert response_input.options == ["None yet", "A peer", "A mentor"]
    assert response_input.allow_custom is True


@pytest.mark.parametrize(
    "payload",
    [
        {"version": 1, "kind": "unknown"},
        {"version": 1, "kind": "single_choice", "options": ["Only one"]},
        {
            "version": 1,
            "kind": "number",
            "min": 10,
            "max": 2,
            "step": 1,
        },
        {
            "version": 1,
            "kind": "number",
            "min": 0,
            "max": 1000,
            "step": 1,
        },
        {
            "version": 1,
            "kind": "number",
            "min": 0,
            "max": 10,
            "step": 20,
        },
        {
            "version": 1,
            "kind": "number",
            "min": 0,
            "max": 10,
            "step": 3,
        },
        {
            "version": 1,
            "kind": "number",
            "min": 0,
            "max": 1,
            "step": 0.00001,
        },
        {
            "version": 1,
            "kind": "number",
            "min": 0,
            "max": 10,
            "step": 2,
            "initial": 1,
        },
    ],
)
def test_response_input_rejects_unsupported_or_unsafe_controls(payload):
    with pytest.raises(ValidationError):
        InterviewResponseInput.model_validate(payload)


def test_split_interview_response_extracts_valid_trailer():
    raw = (
        "How many hours can you honestly commit each week?\n"
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"number","min":2,"max":60,'
        '"step":1,"initial":8,"unit":"hours per week"}'
        f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
    )

    visible, response_input = sessions._split_interview_response(raw)

    assert visible == "How many hours can you honestly commit each week?"
    assert response_input.kind == "number"
    assert response_input.initial_value == 8
    assert response_input.unit == "hours per week"


def test_split_uses_first_opening_tag_like_the_stream_filter():
    raw = (
        "Choose one."
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"single_choice","options":["A","B"]}'
        f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
        "hidden duplicate text"
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"text"}'
        f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
    )

    visible, response_input = sessions._split_interview_response(raw)

    assert visible == "Choose one."
    assert response_input.kind == "single_choice"


@pytest.mark.parametrize(
    "trailer",
    [
        "",
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}not json",
        (
            f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
            '{"version":1,"kind":"single_choice","options":["one"]}'
            f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
        ),
    ],
)
def test_missing_or_invalid_trailer_falls_back_to_text(trailer):
    visible, response_input = sessions._split_interview_response(
        f"Tell me what you have built.{trailer}"
    )

    assert visible == "Tell me what you have built."
    assert response_input.kind == "text"


def test_stream_filter_hides_trailer_at_every_chunk_boundary():
    # The non-ASCII prefix guards against index drift from Unicode case-folding
    # (for example, ß expands to "ss" under casefold()).
    visible = "Straße? Choose the constraint that is most real for you.\n"
    trailer = (
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"single_choice","options":["Time","Money"]}'
        f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
    )
    full = visible + trailer

    for split_at in range(len(full) + 1):
        response_filter = sessions._InterviewResponseUiStreamFilter()
        output = response_filter.push(full[:split_at])
        output += response_filter.push(full[split_at:])
        output += response_filter.finish()
        assert output == visible
        assert sessions.INTERVIEW_RESPONSE_UI_OPEN not in output


@pytest.mark.parametrize(
    "marker",
    [sessions.INTERVIEW_COMPLETE_MARKER, "[interview_complete]"],
)
def test_stream_filter_hides_completion_marker_at_every_chunk_boundary(marker):
    visible = "I have enough to build your diagnosis.\n"
    full = visible + marker

    for split_at in range(len(full) + 1):
        response_filter = sessions._InterviewResponseUiStreamFilter()
        output = response_filter.push(full[:split_at])
        output += response_filter.push(full[split_at:])
        output += response_filter.finish()
        assert output == visible
        assert sessions.INTERVIEW_COMPLETE_MARKER not in output


def test_completion_marker_after_trailer_counts_but_marker_inside_json_does_not():
    trailer = (
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"text","placeholder":"[INTERVIEW_COMPLETE]"}'
        f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
    )

    assert not sessions._INTERVIEW_COMPLETE_RE.search(
        sessions._interview_completion_text("Keep going." + trailer)
    )
    assert sessions._INTERVIEW_COMPLETE_RE.search(
        sessions._interview_completion_text(
            "We are done." + trailer + "[interview_complete]"
        )
    )


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

    async def rollback(self):
        return None

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
    session.idol = Idol(id="idol-1", name="Ada Lovelace", domain="technology")
    return session


def _thread() -> ChatThread:
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = [
        ChatMessage(
            id="message-1",
            thread_id="thread-1",
            role=MessageRole.ASSISTANT,
            content="What have you already made?",
            response_ui_json={
                "version": 1,
                "kind": "text",
                "answer_key": "achievement_inventory",
            },
        )
    ]
    return thread


def _thread_ready_for_weekly_question() -> ChatThread:
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = [
        ChatMessage(
            id="question-1",
            thread_id="thread-1",
            role=MessageRole.ASSISTANT,
            content="What have you achieved?",
            response_ui_json={"answer_key": "achievement_inventory"},
        ),
        ChatMessage(
            id="answer-1",
            thread_id="thread-1",
            role=MessageRole.USER,
            content="I shipped a working prototype for five users.",
            reply_to_message_id="question-1",
        ),
        ChatMessage(
            id="question-2",
            thread_id="thread-1",
            role=MessageRole.ASSISTANT,
            content="What can you do without help?",
            response_ui_json={"answer_key": "current_capability"},
        ),
    ]
    return thread


def _thread_awaiting_final_answer() -> ChatThread:
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    messages: list[ChatMessage] = []
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
    for index, key in enumerate(keys, start=1):
        question_id = f"question-{index}"
        messages.append(
            ChatMessage(
                id=question_id,
                thread_id="thread-1",
                role=MessageRole.ASSISTANT,
                content=f"Question for {key}",
                response_ui_json={"answer_key": key},
            )
        )
        if index <= len(answers):
            messages.append(
                ChatMessage(
                    id=f"answer-{index}",
                    thread_id="thread-1",
                    role=MessageRole.USER,
                    content=answers[index - 1],
                    reply_to_message_id=question_id,
                )
            )
    thread.messages = messages
    return thread


def _thread_awaiting_weekly_answer() -> ChatThread:
    thread = _thread_ready_for_weekly_question()
    thread.messages.extend(
        [
            ChatMessage(
                id="answer-2",
                thread_id="thread-1",
                role=MessageRole.USER,
                content="I can build and test a small app.",
                reply_to_message_id="question-2",
            ),
            ChatMessage(
                id="question-3",
                thread_id="thread-1",
                role=MessageRole.ASSISTANT,
                content="How many focused hours can you protect each week?",
                response_ui_json={
                    "version": 1,
                    "kind": "number",
                    "min": 3,
                    "max": 60,
                    "step": 1,
                    "initial": 8,
                    "unit": "hours per week",
                    "answer_key": "weekly_hours",
                },
            ),
        ]
    )
    return thread


async def _body_events(response) -> list[dict]:
    chunks = [chunk async for chunk in response.body_iterator]
    body = "".join(
        chunk.decode() if isinstance(chunk, bytes) else chunk for chunk in chunks
    )
    return [
        json.loads(line.removeprefix("data: "))
        for line in body.splitlines()
        if line.startswith("data: ")
    ]


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
    monkeypatch.setattr(
        sessions,
        "_render_interview_prompts",
        lambda *_args, **_kwargs: ("system", "question"),
    )


@pytest.mark.asyncio
async def test_interview_persists_and_emits_response_ui_without_leaking_trailer(
    monkeypatch,
):
    session = _session(turn=2)
    db = _Database(_thread_ready_for_weekly_question())
    trailer = (
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"number","min":2,"max":60,'
        '"step":1,"initial":8,"unit":"hours per week"}'
        f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
    )

    async def stream(*_args, **_kwargs):
        yield "How many hours can you "
        yield "honestly commit?\n<CMPYS_RESP"
        yield "ONSE_UI>" + trailer.split(">", 1)[1]

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "interview_stream", stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content="I can build and test a small app."),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    events = await _body_events(response)

    visible = "".join(
        event.get("content", "") for event in events if event["type"] == "chunk"
    )
    done = next(event for event in events if event["type"] == "done")
    assistant = next(
        item
        for item in db.added
        if isinstance(item, ChatMessage) and item.role == MessageRole.ASSISTANT
    )

    assert visible == "How many hours can you honestly commit?\n"
    assert "CMPYS_RESPONSE_UI" not in visible
    assert assistant.content == "How many hours can you honestly commit?"
    assert assistant.response_ui_json["kind"] == "number"
    assert assistant.response_ui_json["answer_key"] == "weekly_hours"
    assert assistant.response_ui_json["min"] == 3
    assert done["response_ui"]["initial"] == 8
    assert done["question_id"] == assistant.id


@pytest.mark.asyncio
async def test_transitioning_turn_omits_response_ui(monkeypatch):
    session = _session(turn=6)
    db = _Database(_thread_awaiting_final_answer())

    async def stream(*_args, **_kwargs):
        yield "I have enough to build your diagnosis."
        yield (
            f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
            '{"version":1,"kind":"text"}'
            f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
        )
        yield sessions.INTERVIEW_COMPLETE_MARKER

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "interview_stream", stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content="That is the full picture."),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    events = await _body_events(response)
    done = next(event for event in events if event["type"] == "done")
    assistant = next(
        item
        for item in db.added
        if isinstance(item, ChatMessage) and item.role == MessageRole.ASSISTANT
    )

    assert done["phase_transition"] is True
    assert "response_ui" not in done
    assert assistant.response_ui_json is None


@pytest.mark.asyncio
async def test_complete_profile_does_not_transition_without_closing_marker(
    monkeypatch,
):
    session = _session(turn=6)
    db = _Database(_thread_awaiting_final_answer())

    async def stream(*_args, **_kwargs):
        yield "Good. What would you like to clarify next?"

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "interview_stream", stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content="That is the full picture."),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    events = await _body_events(response)

    assert any(event["type"] == "error" for event in events)
    assert not any(event["type"] == "done" for event in events)
    assert session.phase == SessionPhase.INTERVIEW
    assert not any(
        isinstance(item, ChatMessage)
        and item.role == MessageRole.ASSISTANT
        and "clarify" in item.content
        for item in db.added
    )


@pytest.mark.asyncio
async def test_marker_after_accidental_trailer_still_transitions_and_never_leaks(
    monkeypatch,
):
    session = _session(turn=6)
    db = _Database(_thread_awaiting_final_answer())

    async def stream(*_args, **_kwargs):
        yield "I have enough to build your diagnosis."
        yield (
            f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
            '{"version":1,"kind":"text"}'
            f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
        )
        yield "[interview_complete]"

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "interview_stream", stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content="That is the full picture."),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    events = await _body_events(response)
    visible = "".join(
        event.get("content", "") for event in events if event["type"] == "chunk"
    )
    done = next(event for event in events if event["type"] == "done")
    assistant = next(
        item
        for item in db.added
        if isinstance(item, ChatMessage) and item.role == MessageRole.ASSISTANT
    )

    assert visible == "I have enough to build your diagnosis."
    assert done["phase_transition"] is True
    assert "response_ui" not in done
    assert assistant.content == visible


@pytest.mark.asyncio
async def test_invalid_custom_weekly_hours_replays_the_same_question(monkeypatch):
    session = _session(turn=3)
    db = _Database(_thread_awaiting_weekly_answer())
    _patch_session(monkeypatch, session)

    with pytest.raises(HTTPException) as exc_info:
        await sessions.interview(
            session_id=session.id,
            data=InterviewMessageRequest(
                content="I am not sure",
                question_id="question-3",
            ),
            db=db,
            current_user=User(
                id="user-1",
                email="learner@example.com",
                password_hash="hash",
            ),
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail["code"] == "invalid_interview_answer"
