from types import SimpleNamespace

import pytest

from app.models.chat import MessageRole
from app.services.interview_inputs import (
    INTERVIEW_ANSWER_KEYS,
    build_interview_plan_inputs,
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
    assert next_interview_answer_key(messages) == "current_capability"


def test_full_plan_ready_profile_distinguishes_explicit_none_from_missing():
    values = {
        "achievement_inventory": "None yet",
        "current_capability": "I understand the basics but need guided practice.",
        "weekly_hours": "6 hours per week",
        "target_outcome": "Publish one working portfolio project.",
        "constraints_resources": "A laptop; limited weekday evenings.",
        "learning_habits_support": "Short readings, deliberate practice, and weekly peer feedback.",
    }
    messages = []
    for index, key in enumerate(INTERVIEW_ANSWER_KEYS, start=1):
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
