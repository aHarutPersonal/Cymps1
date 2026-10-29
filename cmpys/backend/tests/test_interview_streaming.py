import json
import re

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

    assert [call["grounded"] for call in calls] == [False, False, False]
    assert calls[2]["max_output_tokens"] == gemini.BLUEPRINT_MAX_OUTPUT_TOKENS


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

    async def fake_lock_interview_session(*_args, **_kwargs):
        return session

    async def forbidden_grounding(*args, **kwargs):
        raise AssertionError("missing idol facts should not block SSE start")

    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    monkeypatch.setattr(
        sessions_api,
        "_lock_interview_session_state",
        fake_lock_interview_session,
    )
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

@pytest.mark.asyncio
@pytest.mark.parametrize('partial', [False, True])
async def test_tutor_recovers_outage_only_before_first_text(monkeypatch, partial):
    from app.services.llm.openlux import OpenLuxStreamError
    monkeypatch.setattr(gemini.settings, 'llm_provider', 'openlux')
    monkeypatch.setattr(gemini.settings, 'gemini_api_key', 'test-only')
    captured = []
    class Gateway:
        async def stream_text(self, *args, **kwargs):
            if partial:
                yield 'partial'
            raise OpenLuxStreamError(TimeoutError())
    def gateway(**kwargs):
        assert kwargs['timeout'] == 20
        return Gateway()
    monkeypatch.setattr('app.services.llm.client.get_llm_client', gateway)
    class Models:
        def generate_content_stream(self, **kwargs):
            captured.append(kwargs)
            async def chunks():
                yield SimpleNamespace(text='recovered')
            return chunks()
    monkeypatch.setattr(gemini, '_gemini_client', lambda: SimpleNamespace(
        aio=SimpleNamespace(models=Models())))
    stream = gemini.stream_learnlm(system_prompt='tutor', user_message='question')
    if partial:
        with pytest.raises(OpenLuxStreamError):
            async for _ in stream:
                pass
        assert not captured
    else:
        assert [chunk async for chunk in stream] == ['recovered']
        assert len(captured) == 1
        assert captured[0]['config'].http_options.timeout == 35000


def test_interview_system_prompt_has_no_history_slot():
    """History lives only in the per-turn prompt; an always-empty slot misleads."""
    from pathlib import Path

    prompts = Path(__file__).resolve().parents[2] / "prompts"
    system = (prompts / "interview_system.xml").read_text()
    question = (prompts / "interview_question.txt").read_text()
    assert "{chat_history_json}" not in system and "Previous Conversation" not in system
    assert "{chat_history_json}" in question
    # The per-turn prompt keeps the AI-portrayal boundary of the system prompt.
    assert "100% in character" not in question
    assert not question.startswith("You are {idol_name}")


# ---------------------------------------------------------------------------
# Intake v3 question set: per-session turn budget and the weekly-hours control
# ---------------------------------------------------------------------------


def _v2_thread_through(last_key: str):
    """A v3 intake with every key up to and including ``last_key`` asked and
    every key before it answered; ``last_key`` awaits its answer."""
    from app.models.chat import ChatMessage, MessageRole
    from app.services.interview_inputs import INTERVIEW_ANSWER_KEYS_V2

    answers = {
        "achievement_inventory": "Nothing yet",
        "work_sample": "I don’t have one yet",
        "foundation_check": "I don't know yet",
        "application_check": "I don't know yet",
        "self_check_method": "I don’t really check",
        "skill_confidence": "2 of 5",
        "practice_volume": "0 pieces of work",
        "resources_capital": "Prefer not to say",
        "network_support": "1 people",
    }
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    messages = []
    for index, key in enumerate(INTERVIEW_ANSWER_KEYS_V2, start=1):
        messages.append(
            ChatMessage(
                id=f"question-{index}",
                thread_id="thread-1",
                role=MessageRole.ASSISTANT,
                content=f"Question for {key}",
                response_ui_json={"version": 1, "kind": "text", "answer_key": key},
            )
        )
        if key == last_key:
            break
        messages.append(
            ChatMessage(
                id=f"answer-{index}",
                thread_id="thread-1",
                role=MessageRole.USER,
                content=answers[key],
                reply_to_message_id=f"question-{index}",
            )
        )
    thread.messages = messages
    return thread


async def _answer_active_question(monkeypatch, thread, content, *, turn):
    from tests.test_interview_response_ui import (
        _Database,
        _body_events,
        _patch_session,
        _session,
    )

    session = _session(turn=turn)
    db = _Database(thread)

    async def forbidden_stream(*_args, **_kwargs):
        raise AssertionError("This turn must not call the model")
        yield  # pragma: no cover

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions_api, "interview_stream", forbidden_stream)
    response = await sessions_api.interview(
        session_id=session.id,
        data=InterviewMessageRequest(
            content=content,
            question_id=thread.messages[-1].id,
        ),
        db=db,
        current_user=User(id="user-1", email="learner@example.com", password_hash="hash"),
    )
    return session, db, await _body_events(response)


def test_max_turns_is_v2_len_plus_one():
    from app.services.interview_inputs import (
        INTERVIEW_ANSWER_KEYS_V1,
        INTERVIEW_ANSWER_KEYS_V2,
    )
    from tests.test_interview_response_ui import _thread_awaiting_final_answer

    assert len(INTERVIEW_ANSWER_KEYS_V2) == 12
    assert sessions_api.MAX_INTERVIEW_TURNS == len(INTERVIEW_ANSWER_KEYS_V2) + 1 == 13
    # The budget is per session: new intakes get 13, legacy intakes keep 9.
    assert sessions_api.interview_max_turns([]) == 13
    assert sessions_api.interview_max_turns(_v2_thread_through("work_sample").messages) == 13
    legacy = _thread_awaiting_final_answer().messages
    assert sessions_api.interview_max_turns(legacy) == len(INTERVIEW_ANSWER_KEYS_V1) + 1 == 9

    # The per-turn prompt receives the same budget the client is shown.
    session = SimpleNamespace(
        user_age=24,
        user_financial_status="student",
        user_interests=["technology"],
        user_goal="build useful software",
        idol_facts_json={},
    )
    params = sessions_api._interview_question_params(
        session,
        idol_name="Ada Lovelace",
        chat_history_json="[]",
        current_turn=1,
        user_message="hi",
    )
    assert params["max_turns"] == "13"
    assert params["missing_keys_json"] == json.dumps(list(INTERVIEW_ANSWER_KEYS_V2))


@pytest.mark.asyncio
async def test_max_turns_reported_per_session_in_done_events(monkeypatch):
    from tests.test_interview_response_ui import _thread_awaiting_final_answer

    _, _, v2_events = await _answer_active_question(
        monkeypatch,
        _v2_thread_through("learning_preferences"),
        "Worked examples, Listening",
        turn=10,
    )
    assert next(e for e in v2_events if e["type"] == "done")["max_turns"] == 13

    legacy_session, _, legacy_events = await _answer_active_question(
        monkeypatch,
        _thread_awaiting_final_answer(),
        "Weekly peer feedback has worked for me.",
        turn=8,
    )
    done = next(e for e in legacy_events if e["type"] == "done")
    assert done["max_turns"] == 9
    assert done["phase_transition"] is True
    assert legacy_session.phase == SessionPhase.COMPARISON


@pytest.mark.asyncio
async def test_weekly_hours_v2_control_bounds(monkeypatch):
    from app.services.interview_inputs import (
        INTERVIEW_ANSWER_KEYS_V1,
        INTERVIEW_QUESTION_FALLBACKS,
    )
    from app.schemas.session import InterviewResponseInput

    expected = {
        "kind": "number",
        "min": 1,
        "max": 15,
        "step": 0.5,
        "initial": 4,
        "presets": [2, 4, 6, 8],
        "unit": "hours / week",
        "daily_hint": True,
        "answer_key": "weekly_hours",
    }

    control = sessions_api._response_input_payload(
        sessions_api._response_input_for_answer_key(None, "weekly_hours")
    )
    assert {key: control.get(key) for key in expected} == expected

    # A model-proposed number cannot widen or narrow the server-owned control.
    model = InterviewResponseInput(kind="number", min=0, max=100, step=1, initial=50)
    overridden = sessions_api._response_input_for_answer_key(model, "weekly_hours")
    assert (overridden.min_value, overridden.max_value, overridden.step) == (1, 15, 0.5)

    # Legacy (8-key) sessions keep the control their parser was built for.
    legacy = sessions_api._response_input_for_answer_key(
        None, "weekly_hours", key_set=INTERVIEW_ANSWER_KEYS_V1
    )
    assert (legacy.min_value, legacy.max_value, legacy.step) == (3, 60, 1)

    # End to end: after learning preferences, a v3 intake asks the fixed
    # weekly question with the v3 control and no model call.
    _, db, events = await _answer_active_question(
        monkeypatch,
        _v2_thread_through("learning_preferences"),
        "Worked examples, Short daily sessions",
        turn=10,
    )
    done = next(e for e in events if e["type"] == "done")
    assert {key: done["response_ui"].get(key) for key in expected} == expected
    visible = "".join(e.get("content", "") for e in events if e["type"] == "chunk")
    assert visible == INTERVIEW_QUESTION_FALLBACKS["weekly_hours"]


def test_model_proposed_controls_keep_their_kind_or_use_server_defaults():
    from app.schemas.session import InterviewResponseInput

    def control(answer_key, **fields):
        return sessions_api._response_input_for_answer_key(
            InterviewResponseInput.model_validate({"version": 1, **fields}),
            answer_key,
        )

    # Wrong kind (or a provider outage's text default) -> server default.
    for wrong in ({"kind": "scale"}, {"kind": "text"}):
        default = control("self_check_method", **wrong)
        assert default.kind == "single_choice"
        assert default.answer_key == "self_check_method"
        assert default.options[-1] == "I don’t really check"
        assert len(default.option_details) == len(default.options)
    resources = control("resources_capital", kind="text")
    assert resources.kind == "single_choice"
    assert resources.options[-1] == "Prefer not to say"
    confidence = control("skill_confidence", kind="text")
    assert confidence.kind == "scale"
    assert confidence.low_label and confidence.high_label

    # The right kind keeps the model's domain wording.
    model_check = control(
        "self_check_method",
        kind="single_choice",
        options=["I run the tests", "A reviewer reads it", "I don't know yet"],
        option_details=[{"description": "Automated"}, {}, {}],
    )
    assert model_check.options == ["I run the tests", "A reviewer reads it", "I don't know yet"]
    # ...and gains an honest option when the model forgot one.
    no_honest = control(
        "self_check_method",
        kind="single_choice",
        options=["I run the tests", "A reviewer reads it"],
        option_details=[{"description": "Automated"}, {"description": "Peer review"}],
    )
    assert no_honest.options[-1] == "I don’t really check"
    assert no_honest.option_details[-1].description == "Honest answers help most"

    # "Prefer not to say" is always offered for resources, replacing a 6th option.
    six = [f"Level {n}" for n in range(1, 7)]
    full = control("resources_capital", kind="single_choice", options=six)
    assert full.options == six[:5] + ["Prefer not to say"]
    kept = control(
        "resources_capital",
        kind="single_choice",
        options=["A laptop", "prefer not to say"],
    )
    assert kept.options == ["A laptop", "prefer not to say"]

    labelled = control("skill_confidence", kind="scale", low_label="Can’t read a score", high_label="Sight-read")
    assert (labelled.low_label, labelled.high_label) == ("Can’t read a score", "Sight-read")

    outcome = control("target_outcome", kind="text", missing_option="Not sure")
    assert outcome.suggestions  # server suggestions fill an empty set
    assert outcome.missing_option is None  # only a work sample records missing evidence
    chosen = control("target_outcome", kind="text", suggestions=["Play one piece start to finish"])
    assert chosen.suggestions == ["Play one piece start to finish"]

    # Legacy keys keep their open control behaviour.
    legacy = control("constraints_resources", kind="single_choice", options=["Time", "Money"])
    assert legacy.kind == "single_choice"
    assert legacy.answer_key == "constraints_resources"

    # Server-owned keys ignore whatever the model proposed.
    owned = control("practice_volume", kind="text")
    assert (owned.kind, owned.min_value, owned.max_value, owned.step, owned.unit) == (
        "number", 0, 50, 1, "pieces of work",
    )
    network = control("network_support", kind="scale")
    assert (network.kind, network.min_value, network.max_value, network.unit) == (
        "number", 0, 20, "people",
    )
    achievement = control("achievement_inventory", kind="single_choice", options=["A", "B"])
    assert achievement.kind == "text"
    assert len(achievement.suggestions) == 3
    assert "Nothing yet" in achievement.suggestions


def test_one_bad_icon_or_long_detail_does_not_erase_a_choice_control():
    payload = {
        "version": 1,
        "kind": "single_choice",
        "options": ["Option one", "Option two", "Option three", "Four", "Five", "Six", "Seven"],
        "option_details": [
            {"description": "Fine", "icon": "rocket"},
            {"description": "word " * 40, "icon": "book"},
            "A bare string description",
            42,
            {},
            {"icon": "clock"},
            {"icon": "list"},
        ],
        "answer_key": "self_check_method",
    }
    _, control = sessions_api._split_interview_response(
        "How do you check yourself?\n"
        f"{sessions_api.INTERVIEW_RESPONSE_UI_OPEN}{json.dumps(payload)}"
        f"{sessions_api.INTERVIEW_RESPONSE_UI_CLOSE}"
    )
    assert control.kind == "single_choice"
    assert len(control.options) == 6
    assert len(control.option_details) == 6
    assert control.option_details[0].icon is None
    assert control.option_details[1].icon == "book"
    assert len(control.option_details[1].description) <= 90
    assert control.option_details[1].description.endswith("…")
    assert control.option_details[2].description == "A bare string description"

    # Misaligned details are dropped instead of failing the whole control.
    _, misaligned = sessions_api._split_interview_response(
        "Which?\n"
        f"{sessions_api.INTERVIEW_RESPONSE_UI_OPEN}"
        '{"version":1,"kind":"single_choice","options":["A","B","C"],"option_details":[{"icon":"list"}]}'
        f"{sessions_api.INTERVIEW_RESPONSE_UI_CLOSE}"
    )
    assert misaligned.kind == "single_choice"
    assert misaligned.option_details == []

    # Over-long text suggestions and scale labels are shortened, not fatal.
    _, text = sessions_api._split_interview_response(
        "What result?\n"
        f"{sessions_api.INTERVIEW_RESPONSE_UI_OPEN}"
        + json.dumps({"version": 1, "kind": "text", "suggestions": ["x " * 50, "a", "b", "c", "d"]})
        + f"{sessions_api.INTERVIEW_RESPONSE_UI_CLOSE}"
    )
    assert text.kind == "text"
    assert len(text.suggestions) == 4
    assert all(len(item) <= 60 for item in text.suggestions)
    _, scale = sessions_api._split_interview_response(
        "How sure?\n"
        f"{sessions_api.INTERVIEW_RESPONSE_UI_OPEN}"
        + json.dumps({"version": 1, "kind": "scale", "low_label": "very " * 20, "high_label": "Fluent"})
        + f"{sessions_api.INTERVIEW_RESPONSE_UI_CLOSE}"
    )
    assert scale.kind == "scale"
    assert len(scale.low_label) <= 40


def test_question_prompt_states_control_ownership_for_every_key():
    from app.services.interview_inputs import (
        INTERVIEW_ANSWER_KEYS_V1,
        INTERVIEW_ANSWER_KEYS_V2,
        MODEL_CONTROL_KINDS,
        SERVER_OWNED_CONTROL_KEYS,
    )

    session = SimpleNamespace(
        user_age=24,
        user_financial_status="not_specified",
        user_interests=["music"],
        user_goal="play jazz piano",
        idol_facts_json={},
    )
    for key in {*INTERVIEW_ANSWER_KEYS_V1, *INTERVIEW_ANSWER_KEYS_V2, None}:
        _, user_prompt = sessions_api._render_interview_prompts(
            session,
            idol_name="Ada Lovelace",
            idol_persona={},
            chat_history_json="[]",
            current_turn=2,
            user_message="hi",
            required_answer_key=key,
        )
        if key is None:
            assert "this is the closing turn" in user_prompt
        elif key in SERVER_OWNED_CONTROL_KEYS:
            assert "the app attaches this control" in user_prompt, key
        elif key in MODEL_CONTROL_KINDS:
            assert f'kind "{MODEL_CONTROL_KINDS[key]}"' in user_prompt, key

    # The ownership the prompt states is the ownership the server enforces.
    for key in INTERVIEW_ANSWER_KEYS_V2:
        built = sessions_api._server_owned_control(key, INTERVIEW_ANSWER_KEYS_V2)
        assert (built is not None) == (key in SERVER_OWNED_CONTROL_KEYS), key


def test_target_outcome_suggestions_never_offer_an_unsure_chip():
    from pathlib import Path

    from app.schemas.session import InterviewResponseInput
    from app.services.interview_inputs import (
        INTERVIEW_CONTROL_CONTRACTS,
        is_noncommittal_answer,
    )

    # The server default (every provider fallback, every empty model set).
    default = sessions_api._response_input_for_answer_key(None, "target_outcome")
    assert default.kind == "text"
    assert len(default.suggestions) == 3
    assert not any(is_noncommittal_answer(item) for item in default.suggestions)
    assert not any(
        re.search(r"\b(?:sure|know|idea)\b", item, re.IGNORECASE)
        for item in default.suggestions
    )

    # Unsure chips the model proposes are dropped; concrete ones are kept.
    def suggestions_for(*items):
        model = InterviewResponseInput(kind="text", suggestions=list(items))
        return sessions_api._response_input_for_answer_key(
            model, "target_outcome"
        ).suggestions

    assert suggestions_for(
        "Play one tune start to finish", "I’m not sure yet", "Not sure"
    ) == ["Play one tune start to finish"]
    assert suggestions_for("I’m not sure yet", "Don’t know") == default.suggestions

    # The prompt teaches concrete outcomes: its text example and the per-turn
    # contract carry no unsure chip.
    prompt = (
        Path(__file__).resolve().parents[2] / "prompts" / "interview_system.xml"
    ).read_text()
    text_example = next(
        line for line in prompt.splitlines()
        if line.startswith('<CMPYS_RESPONSE_UI>{"version":1,"kind":"text"')
    )
    example = json.loads(
        text_example.removeprefix("<CMPYS_RESPONSE_UI>").removesuffix("</CMPYS_RESPONSE_UI>")
    )
    assert example["answer_key"] == "target_outcome"
    assert not any(is_noncommittal_answer(item) for item in example["suggestions"])
    assert "never an unsure starting point" in INTERVIEW_CONTROL_CONTRACTS["target_outcome"]
