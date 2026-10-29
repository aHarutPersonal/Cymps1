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


def _thread_ready_for_weekly_question(*, include_diagnostics=True) -> ChatThread:
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
    if include_diagnostics:
        for key in ("foundation_check", "application_check"):
            thread.messages[0:0] = [
                ChatMessage(
                    id=f"q-{key}",
                    thread_id="thread-1",
                    role=MessageRole.ASSISTANT,
                    content="Diagnostic",
                    response_ui_json={"answer_key": key},
                ),
                ChatMessage(
                    id=f"a-{key}",
                    thread_id="thread-1",
                    role=MessageRole.USER,
                    content="I do not know",
                    reply_to_message_id=f"q-{key}",
                ),
            ]
    return thread


def _thread_awaiting_final_answer() -> ChatThread:
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    messages: list[ChatMessage] = []
    keys = [
        "achievement_inventory",
        "current_capability",
        "foundation_check",
        "application_check",
        "weekly_hours",
        "target_outcome",
        "constraints_resources",
        "learning_habits_support",
    ]
    answers = [
        "I shipped a prototype used by five people.",
        "I can build and test a small app without a tutorial.",
        "I do not know yet",
        "I do not know yet",
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
async def test_weekly_capacity_question_and_control_do_not_require_provider(
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
        raise AssertionError("The exact weekly-capacity question needs no model")
        yield trailer  # pragma: no cover

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

    assert visible == sessions.INTERVIEW_QUESTION_FALLBACKS["weekly_hours"]
    assert "CMPYS_RESPONSE_UI" not in visible
    assert assistant.content == visible
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
async def test_complete_profile_transitions_without_a_provider_closing_marker(
    monkeypatch,
):
    session = _session(turn=6)
    db = _Database(_thread_awaiting_final_answer())

    async def stream(*_args, **_kwargs):
        raise AssertionError("Complete evidence is sufficient to finish intake")
        yield  # pragma: no cover

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

    assert not any(event["type"] == "error" for event in events)
    assert any(event["type"] == "done" for event in events)
    assert session.phase == SessionPhase.COMPARISON
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

    assert visible == sessions.INTERVIEW_CLOSING_TEXT
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


@pytest.mark.asyncio
async def test_fixed_diagnostic_stream_persists_exact_case_without_model_call(
    monkeypatch,
):
    from app.services.intake_diagnostics import BANK

    session = _session(turn=2)
    session.user_goal = "Learn geometry"
    db = _Database(_thread_ready_for_weekly_question(include_diagnostics=False))
    _patch_session(monkeypatch, session)

    async def forbidden_stream(**kwargs):
        raise AssertionError("A fixed diagnostic must not call the model")
        yield ""

    monkeypatch.setattr(sessions, "interview_stream", forbidden_stream)
    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(content="I can calculate areas."),
        db=db,
        current_user=User(
            id="user-1", email="learner@example.com", password_hash="hash"
        ),
    )
    events = await _body_events(response)
    done = next(event for event in events if event["type"] == "done")
    assert done["response_ui"]["diagnostic_id"] == BANK["geometry"][0].id
    assert done["response_ui"]["answer_key"] == "foundation_check"
    assert not done["phase_transition"]
    assistant = next(
        item
        for item in db.added
        if isinstance(item, ChatMessage) and item.role == MessageRole.ASSISTANT
    )
    assert assistant.content == BANK["geometry"][0].question
    assert assistant.response_ui_json == done["response_ui"]


# ---------------------------------------------------------------------------
# v3 control kinds: multi_choice, scale, option details, suggestions, presets
# ---------------------------------------------------------------------------


def _v3(**fields) -> InterviewResponseInput:
    return InterviewResponseInput.model_validate({"version": 1, **fields})


def test_multi_choice_requires_2_to_6_unique_options():
    response_input = _v3(
        kind="multi_choice",
        options=["  Reading ", "Videos", "reading", "Practice"],
        min_selected=1,
        max_selected=3,
        allow_custom=False,
    )

    assert response_input.kind == "multi_choice"
    assert response_input.options == ["Reading", "Videos", "Practice"]
    assert response_input.min_selected == 1
    assert response_input.max_selected == 3
    assert response_input.allow_custom is True

    # No cap by default, and six options is the ceiling.
    open_ended = _v3(kind="multi_choice", options=[f"Mode {i}" for i in range(6)])
    assert len(open_ended.options) == 6
    assert open_ended.max_selected is None

    for options in (
        ["Only one"],
        ["Same", "same", "SAME"],
        ["Fine", "   "],
        ["Fine", "x" * 81],
        [f"Mode {i}" for i in range(7)],
    ):
        with pytest.raises(ValidationError):
            _v3(kind="multi_choice", options=options)

    # Selection limits must be satisfiable with the (deduplicated) options.
    for limits in (
        {"min_selected": 0},
        {"min_selected": 4},
        {"max_selected": 4},
        {"min_selected": 3, "max_selected": 2},
    ):
        with pytest.raises(ValidationError):
            _v3(kind="multi_choice", options=["A", "B", "C"], **limits)
    assert (
        _v3(
            kind="multi_choice",
            options=["A", "B", "C"],
            min_selected=2,
            max_selected=2,
        ).max_selected
        == 2
    )

    # Selection limits are multi-only: other kinds reset them.
    single = _v3(
        kind="single_choice",
        options=["A", "B"],
        min_selected=2,
        max_selected=2,
    )
    assert single.min_selected == 1
    assert single.max_selected is None
    text = _v3(kind="text", min_selected=1, max_selected=3)
    assert text.min_selected == 1
    assert text.max_selected is None


def test_scale_forces_one_to_five():
    scale = _v3(
        kind="scale",
        min=0,
        max=10,
        step=2,
        initial=7,
        unit="points",
        low_label="  Not at all ",
        high_label="Fluent",
        options=["A", "B"],
        suggestions=["x"],
        presets=[1],
        daily_hint=True,
    )

    assert scale.kind == "scale"
    assert (scale.min_value, scale.max_value, scale.step) == (1, 5, 1)
    assert scale.initial_value is None
    assert scale.unit is None
    assert scale.low_label == "Not at all"
    assert scale.high_label == "Fluent"
    assert scale.options == []
    assert scale.suggestions == []
    assert scale.presets == []
    assert scale.daily_hint is False

    payload = scale.model_dump(mode="json", by_alias=True, exclude_none=True)
    assert (payload["min"], payload["max"], payload["step"]) == (1, 5, 1)
    assert "initial" not in payload

    # Missing or unusable bounds are overwritten, not rejected.
    bare = _v3(kind="scale")
    assert (bare.min_value, bare.max_value, bare.step) == (1, 5, 1)
    assert bare.low_label is None and bare.high_label is None
    broken = _v3(kind="scale", min=5, max=1, step=0)
    assert (broken.min_value, broken.max_value, broken.step) == (1, 5, 1)

    with pytest.raises(ValidationError):
        _v3(kind="scale", low_label="x" * 41)
    with pytest.raises(ValidationError):
        _v3(kind="scale", high_label="x" * 41)

    # Labels belong to scale only.
    for kind, extra in (
        ("text", {}),
        ("single_choice", {"options": ["A", "B"]}),
        ("multi_choice", {"options": ["A", "B"]}),
        ("number", {"min": 0, "max": 10, "step": 1}),
    ):
        other = _v3(kind=kind, low_label="Low", high_label="High", **extra)
        assert other.low_label is None
        assert other.high_label is None


def test_option_details_length_must_match_options():
    details = [
        {"description": "  One at a time ", "icon": "book"},
        {"description": "Together", "icon": "users"},
        {"icon": "sparkle"},
    ]

    for kind in ("single_choice", "multi_choice"):
        response_input = _v3(
            kind=kind,
            options=["Solo", "Pair", "Group"],
            option_details=details,
        )
        assert [d.description for d in response_input.option_details] == [
            "One at a time",
            "Together",
            None,
        ]
        assert [d.icon for d in response_input.option_details] == [
            "book",
            "users",
            "sparkle",
        ]
        # Older clients keep reading plain option strings.
        assert response_input.options == ["Solo", "Pair", "Group"]

        with pytest.raises(ValidationError):
            _v3(
                kind=kind, options=["Solo", "Pair", "Group"], option_details=details[:2]
            )
        with pytest.raises(ValidationError):
            _v3(kind=kind, options=["Solo", "Pair"], option_details=details)

        empty = _v3(kind=kind, options=["Solo", "Pair"])
        assert empty.option_details == []

    # Details stay aligned when a duplicate option is dropped.
    deduped = _v3(
        kind="single_choice",
        options=["Solo", "solo", "Pair"],
        option_details=[{"icon": "list"}, {"icon": "clock"}, {"icon": "target"}],
    )
    assert deduped.options == ["Solo", "Pair"]
    assert [d.icon for d in deduped.option_details] == ["list", "target"]

    # Individual details are validated.
    for bad in ({"icon": "rocket"}, {"description": "x" * 91}):
        with pytest.raises(ValidationError):
            _v3(
                kind="single_choice",
                options=["A", "B"],
                option_details=[bad, {}],
            )

    # Details belong to the choice kinds only.
    assert _v3(kind="text", option_details=[{"icon": "list"}]).option_details == []
    assert (
        _v3(
            kind="number", min=0, max=10, step=1, option_details=[{"icon": "list"}]
        ).option_details
        == []
    )

    # A mismatch from the model degrades to the text composer.
    fallback = sessions._validated_interview_response_input(
        {
            "version": 1,
            "kind": "single_choice",
            "options": ["A", "B"],
            "option_details": [{"icon": "list"}],
        }
    )
    assert fallback.kind == "text"
    assert fallback.options == []
    assert fallback.option_details == []


def test_number_presets_must_align_to_step():
    hours = _v3(
        kind="number",
        min=1,
        max=15,
        step=0.5,
        initial=4,
        unit="hours / week",
        presets=[2, 4, 6.5, 8],
        daily_hint=True,
    )

    assert hours.presets == [2, 4, 6.5, 8]
    assert hours.daily_hint is True
    payload = hours.model_dump(mode="json", by_alias=True, exclude_none=True)
    assert payload["presets"] == [2, 4, 6.5, 8]
    assert payload["daily_hint"] is True

    defaults = _v3(kind="number", min=0, max=10, step=1)
    assert defaults.presets == []
    assert defaults.daily_hint is False

    for presets in (
        [2, 4.25],  # off the 0.5 step
        [0.5],  # below min
        [16],  # above max
        [1, 2, 3, 4, 5],  # too many
        [float("nan")],
    ):
        with pytest.raises(ValidationError):
            _v3(kind="number", min=1, max=15, step=0.5, presets=presets)

    # Alignment is measured from min, like the initial value.
    offset = _v3(kind="number", min=1, max=11, step=2, presets=[1, 3, 11])
    assert offset.presets == [1, 3, 11]
    with pytest.raises(ValidationError):
        _v3(kind="number", min=1, max=11, step=2, presets=[2])

    # Presets and the daily hint belong to number only.
    for kind, extra in (
        ("text", {}),
        ("single_choice", {"options": ["A", "B"]}),
        ("multi_choice", {"options": ["A", "B"]}),
        ("scale", {}),
    ):
        other = _v3(kind=kind, presets=[1, 2], daily_hint=True, **extra)
        assert other.presets == []
        assert other.daily_hint is False


def test_text_suggestions_dropped_for_choice_kinds():
    text = _v3(
        kind="text",
        suggestions=["  Built a landing page ", "Shipped an app"],
        missing_option="  I don’t have one yet ",
    )
    assert text.suggestions == ["Built a landing page", "Shipped an app"]
    assert text.missing_option == "I don’t have one yet"

    plain = _v3(kind="text")
    assert plain.suggestions == []
    assert plain.missing_option is None

    for kind, extra in (
        ("single_choice", {"options": ["A", "B"]}),
        ("multi_choice", {"options": ["A", "B"]}),
        ("scale", {}),
        ("number", {"min": 0, "max": 10, "step": 1}),
    ):
        other = _v3(
            kind=kind,
            suggestions=["One", "Two"],
            missing_option="I don’t have one yet",
            **extra,
        )
        assert other.suggestions == [], kind
        assert other.missing_option is None, kind

    # Text-only limits are still enforced on text.
    for bad in (
        {"suggestions": ["a", "b", "c", "d", "e"]},
        {"suggestions": ["fine", "  "]},
        {"suggestions": ["x" * 61]},
        {"missing_option": "x" * 61},
    ):
        with pytest.raises(ValidationError):
            _v3(kind="text", **bad)

    # Text drops every other kind's fields.
    leaked = _v3(
        kind="text",
        options=["A", "B"],
        option_details=[{"icon": "list"}, {"icon": "book"}],
        min=1,
        max=5,
        step=1,
        presets=[1],
        low_label="Low",
    )
    assert leaked.options == []
    assert leaked.option_details == []
    assert leaked.min_value is None
    assert leaked.presets == []
    assert leaked.low_label is None


def test_unknown_kind_falls_back_to_text():
    with pytest.raises(ValidationError):
        _v3(kind="carousel")

    fallback = sessions._validated_interview_response_input(
        {"version": 1, "kind": "carousel", "options": ["A", "B"]}
    )
    assert fallback.kind == "text"
    assert fallback.options == []
    assert (
        sessions._response_input_payload(
            {"version": 1, "kind": "ranking", "options": ["A", "B"]}
        )["kind"]
        == "text"
    )

    visible, from_trailer = sessions._split_interview_response(
        "Rank these.\n"
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"ranking","options":["A","B"]}'
        f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
    )
    assert visible == "Rank these."
    assert from_trailer.kind == "text"

    # The new kinds survive the same trailer path.
    _, multi = sessions._split_interview_response(
        "Pick any.\n"
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"multi_choice","options":["A","B"],"max_selected":2}'
        f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
    )
    assert multi.kind == "multi_choice"
    assert multi.max_selected == 2
    _, scale = sessions._split_interview_response(
        "Rate it.\n"
        f"{sessions.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"scale","low_label":"Lost","high_label":"Fluent"}'
        f"{sessions.INTERVIEW_RESPONSE_UI_CLOSE}"
    )
    assert scale.kind == "scale"
    assert scale.low_label == "Lost"

    # The protocol version is unchanged so older apps keep parsing.
    assert multi.version == 1
    with pytest.raises(ValidationError):
        _v3(kind="text", version=2)


async def _post_answer(monkeypatch, **request_fields) -> _Database:
    session = _session(turn=1)
    db = _Database(_thread())

    async def stream(*_args, **_kwargs):
        yield "What can you do without help today?"

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "interview_stream", stream)

    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(question_id="message-1", **request_fields),
        db=db,
        current_user=User(
            id="user-1",
            email="learner@example.com",
            password_hash="hash",
        ),
    )
    events = await _body_events(response)
    assert any(event["type"] == "done" for event in events)
    return db


def _user_answer(db: _Database) -> ChatMessage:
    return next(
        item
        for item in db.added
        if isinstance(item, ChatMessage) and item.role == MessageRole.USER
    )


@pytest.mark.asyncio
async def test_missing_evidence_flag_persisted_on_answer(monkeypatch):
    assert InterviewMessageRequest(content="x").missing_evidence is False

    flagged = await _post_answer(
        monkeypatch,
        content="I don’t have one yet",
        missing_evidence=True,
    )
    answer = _user_answer(flagged)
    assert answer.content == "I don’t have one yet"
    assert answer.reply_to_message_id == "message-1"
    assert answer.response_ui_json == {"missing_evidence": True}

    # Anything else leaves the stored answer exactly as before.
    for fields in ({}, {"missing_evidence": False}):
        plain = await _post_answer(
            monkeypatch,
            content="I built a prototype for five users.",
            **fields,
        )
        assert _user_answer(plain).response_ui_json is None
