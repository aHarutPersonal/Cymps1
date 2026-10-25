from types import SimpleNamespace as Message

import pytest

from app.services.intake_diagnostics import BANK, diagnostic_summary, select_diagnostic
from app.services.interview_inputs import (
    INTERVIEW_ANSWER_KEYS,
    build_interview_plan_inputs,
    provider_interview_plan_inputs,
)
from app.services.comparison.scoring import normalize_comparison_scores
from app.schemas.session import InterviewResponseInput


def messages_for(values):
    result = []
    for key, (answer, diagnostic_id) in values.items():
        result.extend(
            [
                Message(
                    id=f"q-{key}",
                    role="assistant",
                    content="Question",
                    response_ui_json={
                        "answer_key": key,
                        "diagnostic_id": diagnostic_id,
                    },
                ),
                Message(
                    id=f"a-{key}",
                    role="user",
                    content=answer,
                    reply_to_message_id=f"q-{key}",
                ),
            ]
        )
    return result


def test_unknown_answers_finish_collection_but_never_establish_competence():
    baseline = build_interview_plan_inputs(
        messages_for(
            {
                key: ("8" if key == "weekly_hours" else "не знаю", None)
                for key in INTERVIEW_ANSWER_KEYS
            }
        )
    )
    assert baseline["missing_keys"] == []
    assert baseline["achievement_baseline_status"] == "missing"
    assert baseline["answer_evidence_status"]["current_capability"] == "unknown"
    assert all(
        item["status"] == "not_assessed" for item in baseline["skill_diagnostics"]
    )


@pytest.mark.parametrize("domain", BANK)
def test_every_fixed_question_has_valid_client_controls_without_solution_key(domain):
    for key, item in zip(("foundation_check", "application_check"), BANK[domain]):
        ui = item.response_ui(key)
        InterviewResponseInput.model_validate(ui)
        assert "correct" not in ui
        assert item.question


@pytest.mark.parametrize("domain", ["investing", "geometry", "reasoning"])
def test_checked_scope_and_uncertainty_survive_provider_projection(domain):
    first, second = BANK[domain]
    baseline = build_interview_plan_inputs(
        messages_for(
            {
                "foundation_check": (first.correct, first.id),
                "application_check": ("I don't know yet", second.id),
                "current_capability": (
                    "I have no portfolio but studied this subject.",
                    None,
                ),
            }
        )
    )
    provider = provider_interview_plan_inputs(baseline)
    checks = provider["skill_diagnostics"]
    assert [check["status"] for check in checks] == ["correct_on_item", "unknown"]
    assert "not proof of mastery" in checks[0]["scope"]
    assert "source_message_id" not in str(provider)
    assert provider["achievement_baseline_status"] == "missing"


def test_wrong_option_and_alternative_answer_are_not_conflated():
    item = BANK["geometry"][0]

    def grade(answer):
        return diagnostic_summary(
            {"foundation_check": [{"diagnostic_id": item.id, "answer": answer}]}
        )[0]["status"]

    assert grade("7 cm") == "needs_practice_on_item"
    assert grade("sqrt(3²+4²) = 5") == "needs_review"
    assert grade("5 cm") == "correct_on_item"


def test_sign_in_a_custom_answer_cannot_be_discarded_by_grading():
    item = BANK["investing"][0]
    result = diagnostic_summary(
        {
            "foundation_check": [
                {
                    "diagnostic_id": item.id,
                    "answer": "Profit 40; cash change +60",
                }
            ]
        }
    )
    assert result[0]["status"] == "needs_review"


def test_goal_takes_priority_over_mentor_name_and_unknown_domains_stay_ungraded():
    assert (
        select_diagnostic("foundation_check", "Learn geometry", "Warren Buffett")
        == BANK["geometry"][0]
    )
    assert (
        select_diagnostic("application_check", "Learn poetry", "Warren Buffett")
        == BANK["general"][1]
    )
    assert select_diagnostic("weekly_hours", "investing", "Warren Buffett") is None


def test_model_cannot_score_missing_knowledge_even_with_money_and_job_title():
    raw = {
        "dimensions": [
            {
                "id": "knowledge",
                "status": "comparable",
                "you_level": 4,
                "idol_level": 4,
                "you_evidence": "verified",
                "idol_evidence": "verified",
                "you_note": "Professional investor with money",
                "idol_note": "Evidence",
            }
        ]
    }
    baseline = {
        "current_capability": {"answer": "не знаю"},
        "constraints_resources": {"answer": "I have a large portfolio"},
    }
    value = normalize_comparison_scores(raw, learner_baseline=baseline)
    knowledge = next(d for d in value["dimensions"] if d["id"] == "knowledge")
    assert knowledge["you"] is None
    assert knowledge["you_evidence"] == "none"
    baseline["current_capability"] = {
        "answer": "I can reconcile cash and profit; no invested capital."
    }
    value = normalize_comparison_scores(raw, learner_baseline=baseline)
    knowledge = next(d for d in value["dimensions"] if d["id"] == "knowledge")
    assert knowledge["you_evidence"] == "self_reported"


def test_russian_explicit_no_achievements_is_distinct_from_unknown_knowledge():
    baseline = build_interview_plan_inputs(
        messages_for(
            {
                "achievement_inventory": ("Пока нет", None),
                "current_capability": ("Не знаю", None),
            }
        )
    )
    assert baseline["achievement_baseline_status"] == "none_yet"
    assert baseline["answer_evidence_status"]["current_capability"] == "unknown"


@pytest.mark.parametrize(
    ("answer", "expected"),
    [
        ("8 часов в неделю", 8),
        ("восемь часов в неделю", 8),
        ("двадцать пять", 25),
        ("два часа в неделю", None),
        ("8–12 часов в неделю", None),
        ("7,5 часов в неделю", None),
        ("Мне 25 лет, могу 8 часов в неделю", None),
    ],
)
def test_russian_capacity_does_not_require_an_english_answer(answer, expected):
    from app.services.interview_inputs import parse_weekly_hours_answer

    assert parse_weekly_hours_answer(answer) == expected


def test_completed_legacy_intake_keeps_diagnostics_explicitly_unassessed():
    records = {
        key: ("8" if key == "weekly_hours" else "A concrete answer", None)
        for key in INTERVIEW_ANSWER_KEYS
        if key not in {"foundation_check", "application_check"}
    }
    messages = messages_for(records)
    legacy = build_interview_plan_inputs(messages)
    assert legacy["missing_keys"] == []
    assert all(
        check["status"] == "not_assessed" for check in legacy["skill_diagnostics"]
    )
    active = build_interview_plan_inputs(messages, require_diagnostics=True)
    assert active["missing_keys"] == ["foundation_check", "application_check"]


def test_lesson_context_preserves_checks_before_long_self_report():
    from app.services.interview_inputs import compact_placement_context

    text = compact_placement_context(
        {
            "current_capability": {"answer": "long text " * 1000},
            "skill_diagnostics": [
                {
                    "skill_id": "profit_vs_cash",
                    "status": "needs_practice_on_item",
                    "scope": "one item",
                }
            ],
        }
    )
    assert len(text) < 2000
    assert "needs_practice_on_item" in text
    assert text.index("needs_practice_on_item") < text.index("long text")
