"""Intake evidence must survive assessment, retry and lesson-context budgets."""
import json

import pytest

from app.api.v1 import sessions
from app.models.chat import ChatMessage, ChatThread, MessageRole
from app.models.intake import SessionPhase
from app.models.user import User
from app.schemas.session import InterviewMessageRequest, InterviewResponseInput
from app.services.intake_diagnostics import BANK, GENERAL_CURRENT, diagnostic_summary, select_diagnostic
from app.services.interview_inputs import (
    INTERVIEW_ANSWER_KEYS_V2, build_interview_plan_inputs, compact_placement_context,
    is_vague_target, next_interview_answer_key, provider_interview_plan_inputs,
)
from tests.test_intake_diagnostics import messages_for
from tests.test_interview_plan_inputs import V2_ANSWERS
from tests.test_interview_response_ui import _Database, _body_events, _patch_session, _session


@pytest.mark.parametrize("goal,domain", [
    ("Learn Python", "programming"), ("Учиться программированию", "programming"),
    ("Improve business writing", "writing"), ("Write clearer emails", "writing"),
    ("Learn data analysis", "data"), ("Изучить статистику", "data"),
])
def test_goal_routes_to_two_scoped_checks_with_executable_keys(goal, domain):
    for key, item in zip(("foundation_check", "application_check"), BANK[domain]):
        assert select_diagnostic(key, goal, "Warren Buffett") == item
        ui = InterviewResponseInput.model_validate(item.response_ui(key)).model_dump()
        assert "correct" not in ui and "option_feedback" not in ui
        for index, answer in enumerate(item.options):
            result = diagnostic_summary({key: [{"diagnostic_id": item.id, "answer": answer}]})
            check = next(value for value in result if value["check"] == key)
            assert check["criterion"] == item.criterion
            if answer == item.correct:
                assert check["status"] == "correct_on_item"
                assert check["observed_issue"] is None
            else:
                assert check["status"] == "needs_practice_on_item"
                assert check["observed_issue"] == item.option_feedback[index]
            assert check["next_check"]


def test_old_and_new_general_tasks_remain_ungraded_and_versioned():
    item = select_diagnostic("foundation_check", "Write a sonnet", "Ada Lovelace")
    assert item.id == GENERAL_CURRENT[0].id
    assert "Write a sonnet" in item.question
    for diagnostic in (item, BANK["general"][0]):
        check = diagnostic_summary({"foundation_check": [{
            "diagnostic_id": diagnostic.id, "answer": "My attempted solution",
            "question": diagnostic.question,
        }]})[0]
        assert check["question"] == diagnostic.question
        assert check["criterion"]
        assert check["status"] == "needs_review"
        assert check["observed_issue"] is None


def test_generic_question_stays_short_even_with_a_long_goal():
    for key in ("foundation_check", "application_check"):
        item = select_diagnostic(key, "practice poetry " * 100, "Ada Lovelace")
        assert len(item.question) <= 450
        assert len(item.question.split()) <= 55


def test_catalog_diagnostic_budget_accounts_for_json_escaping():
    from app.services.interview_inputs import compact_diagnostic_evidence
    check = diagnostic_summary({"foundation_check": [{
        "diagnostic_id": BANK["programming"][0].id,
        "answer": '"\\\n' * 1000 + "This is where I get stuck.",
    }]})[0]
    evidence = compact_diagnostic_evidence(check)
    encoded = json.dumps(evidence, ensure_ascii=False, separators=(",", ":"))
    assert len(encoded) <= 1000
    assert json.loads(encoded)["status"] == "needs_review"
    assert "get stuck." in evidence["answer"]


def test_custom_correct_looking_prose_does_not_inherit_an_option_assessment():
    item = BANK["programming"][0]
    check = diagnostic_summary({"foundation_check": [{
        "diagnostic_id": item.id, "answer": "2, because assignment copies its value.",
    }]})[0]
    assert check["status"] == "needs_review"
    assert check["observed_issue"] is None


@pytest.mark.parametrize("answer,vague", [
    ("Get better at Python", True), ("Improve my knowledge", True),
    ("Learn Python", True), ("Научиться программированию", True),
    ("A finished piece of work I can show", True),
    ("Build a calculator", False), ("Write a sonnet", False),
    ("Explain derivatives using a new example", False),
    ("Learn how to write a tested CSV parser", False),
])
def test_target_clarification_is_conservative(answer, vague):
    assert is_vague_target(answer) is vague


def target_thread(*, allow_clarification=True):
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = []
    for index, key in enumerate(INTERVIEW_ANSWER_KEYS_V2):
        question = ChatMessage(
            id=f"q-{index}", thread_id=thread.id, role=MessageRole.ASSISTANT,
            content=f"Question for {key}", response_ui_json={
                "version": 1, "kind": "text", "answer_key": key,
                "clarification_allowed": allow_clarification and key == "target_outcome",
            },
        )
        thread.messages.append(question)
        if key != "target_outcome":
            thread.messages.append(ChatMessage(
                id=f"a-{index}", thread_id=thread.id, role=MessageRole.USER,
                content=V2_ANSWERS[key], reply_to_message_id=question.id,
                generation_status="completed",
            ))
    return thread


@pytest.mark.asyncio
@pytest.mark.parametrize("final_answer", ["Build a calculator", "Get better", "I’m not sure yet"])
async def test_one_target_clarification_persists_replays_and_then_completes(monkeypatch, final_answer):
    thread = target_thread()
    session = _session(turn=12)
    db = _Database(thread)
    _patch_session(monkeypatch, session)

    async def forbidden(**_kwargs):
        raise AssertionError("Clarification, replay and closing need no provider call")
        yield

    monkeypatch.setattr(sessions, "interview_stream", forbidden)
    user = User(id="user-1", email="learner@example.com", password_hash="hash")

    async def submit(data):
        before = len(db.added)
        response = await sessions.interview(session.id, data, db, user)
        events = await _body_events(response)
        assert not [event for event in events if event["type"] == "error"], events
        thread.messages.extend(db.added[before:])
        return next(event for event in events if event["type"] == "done")

    original = InterviewMessageRequest(content="Get better at Python", question_id=thread.messages[-1].id)
    done = await submit(original)
    assert done["max_turns"] == 14 and done["turn"] == 13
    assert not done["phase_transition"]
    assert done["response_ui"]["is_clarification"] is True
    assert done["response_ui"]["suggestions"] == []
    assert session.phase == SessionPhase.INTERVIEW
    question_id = done["question_id"]
    count = len(thread.messages)
    assert (await submit(original))["question_id"] == question_id
    resumed = await submit(InterviewMessageRequest(content="Ready", is_kickoff=True))
    assert resumed["max_turns"] == 14 and resumed["question_id"] == question_id
    assert len(thread.messages) == count

    closed = await submit(InterviewMessageRequest(content=final_answer, question_id=question_id))
    assert closed["phase_transition"] and closed["turn"] == closed["max_turns"] == 14
    assert session.phase == SessionPhase.COMPARISON
    baseline = build_interview_plan_inputs(thread.messages, session_goal="Learn Python")
    assert baseline["missing_keys"] == []
    if final_answer == "Build a calculator":
        assert baseline["target_outcome"]["answer"] == final_answer
    else:
        assert baseline["target_outcome"] is None
        assert baseline["planning_readiness"]["target"] == "needs_confirmation"


@pytest.mark.parametrize("answer,allow_clarification", [
    ("Get better", False), ("I’m not sure yet", True), ("Build a calculator", True),
])
def test_old_questions_concrete_targets_and_honest_unknowns_do_not_reopen(answer, allow_clarification):
    thread = target_thread(allow_clarification=allow_clarification)
    thread.messages.append(ChatMessage(
        id="last-answer", thread_id=thread.id, role=MessageRole.USER,
        content=answer, reply_to_message_id=thread.messages[-1].id,
    ))
    assert next_interview_answer_key(thread.messages) is None
    assert sessions.interview_max_turns(thread.messages) == 13


def test_model_cannot_mark_a_question_as_an_already_used_clarification():
    control = sessions._response_input_for_answer_key({
        "kind": "text", "is_clarification": True, "clarification_allowed": False,
        "diagnostic_id": BANK["geometry"][0].id,
    }, "target_outcome")
    assert control.clarification_allowed is True
    assert control.is_clarification is False and control.diagnostic_id is None


def evidence_baseline():
    first, second = BANK["investing"]
    messages = messages_for({
        "work_sample": ("Independent work starts here. " + "My notes. " * 200
                        + "I get stuck distinguishing maintenance from expansion.", None),
        "foundation_check": (first.correct, first.id),
        "application_check": (second.options[0], second.id),
        "target_outcome": ("Write an owner earnings memo", None),
    })
    for message in messages:
        if message.id == "q-foundation_check":
            message.content = first.question
        elif message.id == "q-application_check":
            message.content = second.question
    return build_interview_plan_inputs(messages)


def test_real_attempt_and_specific_error_reach_provider_and_lesson_prompts():
    baseline = evidence_baseline()
    provider = provider_interview_plan_inputs(baseline)
    assert "source_message_id" not in json.dumps(provider)
    assert provider["planning_readiness"]["placement"] == "narrow_evidence"
    text = compact_placement_context(provider)
    facts = json.loads(text.split("\n", 1)[1])
    check = facts["skill_diagnostics"][1]
    assert check["answer"] == "40"
    assert "optional expansion" in check["observed_issue"]
    assert "before expansion" in check["question"]
    assert check["criterion"] and check["next_check"]
    assert "Independent work starts here" in facts["work_sample"]
    assert "I get stuck distinguishing maintenance from expansion" in facts["work_sample"]
    assert "[excerpt]" in facts["work_sample"]
    assert len(text) <= 3800


@pytest.mark.parametrize("prose", ["long evidence ", '"\\\n'])
def test_maximum_context_stays_parseable_without_losing_status_or_newer_practice(prose):
    baseline = evidence_baseline()
    for check in baseline["skill_diagnostics"]:
        for key in ("question", "answer", "criterion", "observed_issue", "next_check"):
            check[key] = prose * 1000 + "final obstacle"
    for key in INTERVIEW_ANSWER_KEYS_V2:
        baseline["answer_evidence_status"][key] = "self_reported"
        if key not in {"foundation_check", "application_check", "weekly_hours", "learning_preferences"}:
            baseline[key] = {"answer": prose * 1000 + "final obstacle"}
    baseline["learning_preferences"] = ["preference " * 100] * 5
    baseline["practice_evidence"] = [{
        "lesson": "lesson title " * 50, "status": "needs_review", "activities": [{
            "title": "activity title " * 50, "kind": "transfer", "status": "needs_review",
            "checked_at": "2026-10-30T12:00:00+00:00",
        }] * 2,
    }] * 2
    text = compact_placement_context(baseline)
    assert len(text) <= 3800
    facts = json.loads(text.split("\n", 1)[1])
    assert len(facts["skill_diagnostics"]) == 2
    assert facts["skill_diagnostics"][1]["status"] == "needs_practice_on_item"
    assert "final obstacle" in facts["skill_diagnostics"][1]["answer"]
    assert len(facts["recent_practice"]) == 2


@pytest.mark.asyncio
async def test_catalog_brief_also_receives_attempt_and_observed_error():
    from tests.test_session_context import _brief_for
    brief = await _brief_for(evidence_baseline())
    facts = brief.fact_map()
    check = json.loads(facts["learner.intake_check.2"].value)
    assert "optional expansion" in check["observed_issue"]
    assert check["answer"] == "40"
    assert "I get stuck" in facts["learner.work_sample"].value
    assert "narrow_evidence" in facts["learner.planning_readiness"].value
