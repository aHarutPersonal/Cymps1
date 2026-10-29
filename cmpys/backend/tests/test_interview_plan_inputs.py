from types import SimpleNamespace

import pytest

from app.api.v1 import sessions
from app.models.chat import MessageRole
from app.services.interview_inputs import (
    INTERVIEW_ANSWER_KEYS_V1,
    INTERVIEW_ANSWER_KEYS_V2,
    INTERVIEW_QUESTION_FALLBACKS,
    INTERVIEW_ANSWER_KEY_INSTRUCTIONS,
    build_interview_plan_inputs,
    interview_key_set,
    missing_interview_answer_keys,
    next_interview_answer_key,
    parse_weekly_hours_answer,
    provider_interview_plan_inputs,
)


def _message(
    message_id: str,
    role: MessageRole,
    content: str,
    *,
    answer_key: str | None = None,
    reply_to: str | None = None,
):
    return SimpleNamespace(
        id=message_id,
        role=role,
        content=content,
        response_ui_json=(
            {"version": 1, "kind": "text", "answer_key": answer_key}
            if answer_key
            else None
        ),
        reply_to_message_id=reply_to,
    )


@pytest.mark.parametrize(
    ("answer", "expected"),
    [
        ("8 hours per week", 8),
        ("3 hours per week, in three 60-minute sessions.", 3),
        ("3 hours per week split into 3 60 minute sessions", 3),
        ("6 hours per week, across four 90-minute sessions.", 6),
        ("3 hours per week, in two 60-minute sessions.", None),
        ("3 hours per week, in three 30-60-minute sessions.", None),
        ("3 hours per week, in three 60-minute sessions or maybe four.", None),
        ("2 hours per week, in two 60-minute sessions.", None),
        ("8", 8),
        ("eight", 8),
        ("twenty-five", 25),
        ("15h per week", 15),
        ("7.5 hours each week", None),
        ("between 8 and 12 hours per week", None),
        ("12-8 hours per week", None),
        ("For the next 12 weeks, I can protect 6 hours", None),
        ("6 hours/week for the next 12 weeks", None),
        ("I am 25 and honestly unsure", None),
        ("2 hours per week", None),
        ("61", None),
        ("I do not know yet", None),
    ],
)
def test_parse_semantic_weekly_hours(answer, expected):
    assert parse_weekly_hours_answer(answer) == expected


def test_legacy_weekly_parser_requires_explicit_hours_and_week_context():
    assert (
        parse_weekly_hours_answer(
            "I slept 8 hours last night.",
            require_week_context=True,
            clamp_legacy=True,
        )
        is None
    )
    assert (
        parse_weekly_hours_answer(
            "I can do 95 hours a week.",
            require_week_context=True,
            clamp_legacy=True,
        )
        == 60
    )
    assert (
        parse_weekly_hours_answer(
            "8 hours/week for the next 12 weeks.",
            require_week_context=True,
            clamp_legacy=True,
        )
        == 8
    )
    assert (
        parse_weekly_hours_answer(
            "Between 8 and 12 weeks, with 6 hours/week.",
            require_week_context=True,
            clamp_legacy=True,
        )
        == 6
    )
    assert (
        parse_weekly_hours_answer(
            "15h per week",
            require_week_context=True,
            clamp_legacy=True,
        )
        == 15
    )
    assert (
        parse_weekly_hours_answer(
            "I am age 25 and can protect 8 hours/week.",
            require_week_context=True,
            clamp_legacy=True,
        )
        == 8
    )
    assert (
        parse_weekly_hours_answer(
            "Between 8 and 12 hours per week.",
            require_week_context=True,
            clamp_legacy=True,
        )
        == 10
    )


def test_answer_keys_bind_to_question_ids_not_incidental_numbers():
    messages = [
        _message(
            "q1",
            MessageRole.ASSISTANT,
            "What have you achieved?",
            answer_key="achievement_inventory",
        ),
        _message(
            "a1",
            MessageRole.USER,
            "At 25 I shipped an app after 300 hours of work.",
            reply_to="q1",
        ),
        _message(
            "q2",
            MessageRole.ASSISTANT,
            "How much time can you protect?",
            answer_key="weekly_hours",
        ),
        _message("a2", MessageRole.USER, "8", reply_to="q2"),
    ]

    plan_inputs = build_interview_plan_inputs(
        messages,
        session_goal="Launch a useful product",
    )

    assert plan_inputs["weekly_capacity_hours"] == 8
    assert plan_inputs["achievement_inventory"]["source_message_id"] == "a1"
    assert plan_inputs["achievement_baseline_status"] == "self_reported"
    # Only keys shared by both sets were asked, so this is a v3 (V2-key) intake.
    assert next_interview_answer_key(messages) == "work_sample"


def test_full_plan_ready_profile_distinguishes_explicit_none_from_missing():
    values = {
        "achievement_inventory": "None yet",
        "current_capability": "I understand the basics but need guided practice.",
        "foundation_check": "I do not know",
        "application_check": "I do not know",
        "weekly_hours": "6 hours per week",
        "target_outcome": "Publish one working portfolio project.",
        "constraints_resources": "A laptop; limited weekday evenings.",
        "learning_habits_support": "Short readings, deliberate practice, and weekly peer feedback.",
    }
    messages = []
    for index, key in enumerate(INTERVIEW_ANSWER_KEYS_V1, start=1):
        question_id = f"q{index}"
        messages.extend(
            [
                _message(
                    question_id,
                    MessageRole.ASSISTANT,
                    key,
                    answer_key=key,
                ),
                _message(
                    f"a{index}",
                    MessageRole.USER,
                    values[key],
                    reply_to=question_id,
                ),
            ]
        )

    plan_inputs = build_interview_plan_inputs(messages)

    assert missing_interview_answer_keys(messages) == []
    assert plan_inputs["missing_keys"] == []
    assert plan_inputs["weekly_capacity_confirmed"] is True
    assert plan_inputs["achievement_baseline_status"] == "none_yet"

    provider_baseline = provider_interview_plan_inputs(plan_inputs)
    assert provider_baseline["achievement_inventory"] == {"answer": "None yet"}
    assert "source_message_id" not in str(provider_baseline)
    assert "question_id" not in str(provider_baseline)


def test_invalid_weekly_custom_answer_keeps_weekly_key_missing():
    messages = [
        _message(
            "q1",
            MessageRole.ASSISTANT,
            "How many hours?",
            answer_key="weekly_hours",
        ),
        _message("a1", MessageRole.USER, "Maybe later", reply_to="q1"),
    ]

    assert "weekly_hours" in missing_interview_answer_keys(messages)


def test_natural_explicit_none_is_not_mislabeled_as_an_achievement():
    messages = [
        _message(
            "q1",
            MessageRole.ASSISTANT,
            "What have you achieved?",
            answer_key="achievement_inventory",
        ),
        _message(
            "a1",
            MessageRole.USER,
            "I haven't achieved anything yet",
            reply_to="q1",
        ),
    ]

    assert build_interview_plan_inputs(messages)["achievement_baseline_status"] == (
        "none_yet"
    )


# ---------------------------------------------------------------------------
# Intake v3 question set (V2 answer keys)
# ---------------------------------------------------------------------------

V2_ANSWERS = {
    "achievement_inventory": "I’ve tried it on my own",
    "work_sample": "A one-page note on a local bakery’s margins.",
    "foundation_check": "I don't know yet",
    "application_check": "I don't know yet",
    "self_check_method": "I ask someone more experienced",
    "skill_confidence": "2 of 5",
    "practice_volume": "3 pieces of work",
    "resources_capital": "Prefer not to say",
    "network_support": "2 people",
    "learning_preferences": "Worked examples, Short daily sessions",
    "weekly_hours": "4 hours / week",
    "target_outcome": "Write one owner’s memo I can defend.",
}


def _answered(key: str, answer: str, index: int, *, missing_evidence=False):
    question = _message(f"q{index}", MessageRole.ASSISTANT, key, answer_key=key)
    reply = _message(f"a{index}", MessageRole.USER, answer, reply_to=f"q{index}")
    if missing_evidence:
        reply.response_ui_json = {"missing_evidence": True}
    return [question, reply]


def test_v2_key_order_and_next_key():
    assert INTERVIEW_ANSWER_KEYS_V2 == (
        "achievement_inventory",
        "work_sample",
        "foundation_check",
        "application_check",
        "self_check_method",
        "skill_confidence",
        "practice_volume",
        "resources_capital",
        "network_support",
        "learning_preferences",
        "weekly_hours",
        "target_outcome",
    )
    assert INTERVIEW_ANSWER_KEYS_V1 == (
        "achievement_inventory",
        "current_capability",
        "foundation_check",
        "application_check",
        "weekly_hours",
        "target_outcome",
        "constraints_resources",
        "learning_habits_support",
    )
    # A brand-new session starts on the v3 question set.
    assert interview_key_set([]) == INTERVIEW_ANSWER_KEYS_V2

    messages = []
    for index, key in enumerate(INTERVIEW_ANSWER_KEYS_V2, start=1):
        assert next_interview_answer_key(messages) == key
        messages.extend(_answered(key, V2_ANSWERS[key], index))
    assert next_interview_answer_key(messages) is None
    assert interview_key_set(messages) == INTERVIEW_ANSWER_KEYS_V2

    baseline = build_interview_plan_inputs(messages, require_diagnostics=True)
    assert baseline["interview_key_set"] == "v2"
    assert baseline["missing_keys"] == []
    assert baseline["answered_keys"] == list(INTERVIEW_ANSWER_KEYS_V2)
    assert baseline["missing_evidence_keys"] == []
    assert baseline["weekly_capacity_hours"] == 4
    assert baseline["weekly_capacity_minutes"] == 240
    assert "current_capability" not in baseline

    provider = provider_interview_plan_inputs(baseline)
    assert provider["interview_key_set"] == "v2"
    assert provider["weekly_capacity_minutes"] == 240
    assert isinstance(provider["weekly_capacity_hours"], float)
    assert provider["weekly_capacity_hours"] == 4.0
    assert provider["work_sample"] == {"answer": V2_ANSWERS["work_sample"]}
    assert provider["learning_preferences"] == ["Worked examples", "Short daily sessions"]
    assert "constraints_resources" not in provider
    assert "source_message_id" not in str(provider)

    # Every V2 key the model or an outage can phrase has an instruction and a
    # complete one-question fallback.
    for key in INTERVIEW_ANSWER_KEYS_V2:
        assert INTERVIEW_ANSWER_KEY_INSTRUCTIONS[key]
        if key in {"foundation_check", "application_check"}:
            continue
        fallback = INTERVIEW_QUESTION_FALLBACKS[key]
        assert len(fallback.split()) <= 55, key
        assert fallback.count("?") == 1, key


def test_work_sample_missing_option_records_missing_evidence():
    control = sessions._response_input_for_answer_key(None, "work_sample")
    assert control.kind == "text"
    assert control.answer_key == "work_sample"
    assert control.missing_option == "I don’t have one yet"

    messages = _answered("achievement_inventory", "Nothing yet", 1) + _answered(
        "work_sample", "I don’t have one yet", 2, missing_evidence=True
    )

    # Missing evidence is an answer: the intake moves on rather than re-asking.
    assert next_interview_answer_key(messages) == "foundation_check"
    baseline = build_interview_plan_inputs(messages)
    assert baseline["missing_evidence_keys"] == ["work_sample"]
    assert "work_sample" in baseline["answered_keys"]
    assert baseline["answer_evidence_status"]["work_sample"] == "missing"
    assert baseline["work_sample"]["missing_evidence"] is True
    assert baseline["achievement_baseline_status"] == "none_yet"

    provider = provider_interview_plan_inputs(baseline)
    assert provider["missing_evidence_keys"] == ["work_sample"]
    assert provider["work_sample"] == {"answer": "I don’t have one yet"}


def test_learning_preferences_multi_parsed_from_comma_list():
    control = sessions._response_input_for_answer_key(None, "learning_preferences")
    assert control.kind == "multi_choice"
    assert control.answer_key == "learning_preferences"
    assert control.options == [
        "Worked examples",
        "Reading deeply",
        "Doing exercises",
        "Listening",
        "Short daily sessions",
    ]
    assert [detail.icon for detail in control.option_details] == [
        "list",
        "book",
        "edit",
        "headphones",
        "clock",
    ]
    assert control.min_selected == 1

    messages = _answered(
        "learning_preferences",
        "Worked examples,  short daily sessions, Podcasts on the bus, worked examples",
        1,
    )
    baseline = build_interview_plan_inputs(messages)
    # Known options keep their canonical label; custom text survives; no dupes.
    assert baseline["learning_preferences"] == [
        "Worked examples",
        "Short daily sessions",
        "Podcasts on the bus",
    ]

    unknown = build_interview_plan_inputs(
        _answered("learning_preferences", "I don't know", 1)
    )
    assert unknown["learning_preferences"] == []
    assert build_interview_plan_inputs([])["learning_preferences"] == []


UNSURE_TARGETS = [
    "I’m not sure yet",
    "not sure",
    "don’t know",
    "Not sure yet.",
    "I have no idea",
    "I haven't decided yet",
]


@pytest.mark.asyncio
@pytest.mark.parametrize("unsure", UNSURE_TARGETS)
async def test_unsure_target_outcome_never_becomes_the_plan_goal(unsure):
    from app.models.intake import IntakeSession
    from app.models.user_profile import UserProfile
    from app.services.comparison.scoring import normalize_comparison_scores
    from app.tasks.plans import _load_session_context
    from tests.test_interview_profile_persistence import _Database as _ProfileDb
    from tests.test_plan_session_trigger import _FakeDB

    onboarding_goal = "Learn to judge businesses"
    messages = []
    for index, key in enumerate(INTERVIEW_ANSWER_KEYS_V2, start=1):
        answer = unsure if key == "target_outcome" else V2_ANSWERS[key]
        messages.extend(_answered(key, answer, index))

    # The question was answered, so the intake completes (no 409 later)...
    assert next_interview_answer_key(messages) is None
    baseline = build_interview_plan_inputs(
        messages, session_goal=onboarding_goal, require_diagnostics=True
    )
    assert baseline["missing_keys"] == []
    assert "target_outcome" in baseline["answered_keys"]
    # ...but the unsure answer is no evidence and no target.
    assert baseline["target_outcome"] is None
    assert baseline["answer_evidence_status"]["target_outcome"] == "unknown"
    provider = provider_interview_plan_inputs(baseline)
    assert provider["target_outcome"] is None

    # Plan job focus: no target answer, so the job falls back to the session goal.
    assert sessions._plan_input_answer(baseline, "target_outcome") is None

    # Plan generation context: no execution goal; the onboarding goal leads.
    session = SimpleNamespace(
        interview_thread_id="thread-1",
        comparison_output="Comparison",
        blueprint_output="Blueprint",
        user_goal=onboarding_goal,
    )
    ctx = await _load_session_context(
        _FakeDB([session, SimpleNamespace(messages=messages)]),
        user_id="u1",
        idol_id="i1",
    )
    assert "execution_goal" not in ctx
    assert ctx["north_star_goal"] == onboarding_goal

    # Reusable profile goals: the unsure text is never stored as a goal.
    profile = UserProfile(id="p1", user_id="user-1", goals=None, interests=None)
    await sessions._sync_user_profile_from_interview(
        _ProfileDb(profile),
        session=IntakeSession(id="session-1", user_id="user-1", user_goal=onboarding_goal),
        user_id="user-1",
        plan_inputs=baseline,
    )
    assert profile.goals == [onboarding_goal]

    # Comparison: the v2 target is bound to no dimension, so an unsure target
    # changes no score (the 8-key target binding is tested in
    # test_comparison_scoring).
    concrete = provider_interview_plan_inputs(
        build_interview_plan_inputs(
            [
                message
                for index, key in enumerate(INTERVIEW_ANSWER_KEYS_V2, start=1)
                for message in _answered(key, V2_ANSWERS[key], index)
            ],
            session_goal=onboarding_goal,
        )
    )
    raw_scores = {
        "dimensions": [
            {
                "id": dimension_id,
                "status": "comparable",
                "you_level": 3,
                "you_evidence": "self_reported",
                "idol_evidence": "documented",
            }
            for dimension_id in ("knowledge", "practice", "network", "judgment")
        ]
    }
    unsure_scores = normalize_comparison_scores(raw_scores, learner_baseline=provider)
    concrete_scores = normalize_comparison_scores(raw_scores, learner_baseline=concrete)
    assert unsure_scores["dimensions"] == concrete_scores["dimensions"]


@pytest.mark.asyncio
async def test_concrete_target_outcome_still_becomes_the_execution_goal():
    from app.tasks.plans import _load_session_context
    from tests.test_plan_session_trigger import _FakeDB

    messages = []
    for index, key in enumerate(INTERVIEW_ANSWER_KEYS_V2, start=1):
        messages.extend(_answered(key, V2_ANSWERS[key], index))
    baseline = build_interview_plan_inputs(messages, session_goal="Learn investing")
    assert baseline["target_outcome"]["answer"] == V2_ANSWERS["target_outcome"]
    assert baseline["answer_evidence_status"]["target_outcome"] == "self_reported"
    session = SimpleNamespace(
        interview_thread_id="thread-1",
        comparison_output="Comparison",
        blueprint_output="Blueprint",
        user_goal="Learn investing",
    )
    ctx = await _load_session_context(
        _FakeDB([session, SimpleNamespace(messages=messages)]),
        user_id="u1",
        idol_id="i1",
    )
    assert ctx["execution_goal"] == V2_ANSWERS["target_outcome"]
