"""Unsupported persona history must not be published during evidence collection."""
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.api.v1 import sessions
from app.models.chat import ChatThread
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase


@pytest.mark.parametrize("text", [
    "A shrewd test — an outside eye, like the serial reader whose letters I watched for. Beyond asking a friend, how do you judge your own drafts yourself?",
    "When Pickwick began in 1836, I was writing instalments month after month. How many finished essays have you completed?",
    "A free library — excellent foundations, which I never scorned. How many people could give you feedback?",
    "Two honest readers — cherish them, for I built Pickwick on watching how real readers took each instalment. How would you like to learn?",
    "Pickwick taught me that steady instalments beat grand bursts. What result would prove success?",
    "My readers helped shape every chapter. How do you review your own essays?",
    "We learned from our readers. How do you review your essays?",
    "I suggest asking my old publisher. How do you review your work?",
    # Past tense is the mentor's own history, not present coaching.
    "Apple gave us the freedom to fail. What would you try first?",
    "Our early customers gave us honest feedback. How do you review your work?",
])
@pytest.mark.asyncio
async def test_autobiographical_question_uses_same_key_fallback_without_retry(monkeypatch, text):
    calls = []

    async def stream(**kwargs):
        calls.append(kwargs)
        # Chunk boundaries must not hide the first-person claim from the gate.
        yield text[:len(text) // 2]
        yield text[len(text) // 2:]
        yield '<CMPYS_RESPONSE_UI>{"kind":"single_choice","options":["A friend","My old publisher"]}</CMPYS_RESPONSE_UI>'

    monkeypatch.setattr(sessions, "interview_stream", stream)
    visible, control = await sessions._generate_concise_interview_question(
        system_prompt="system", user_prompt="question", answer_key="self_check_method")
    assert visible == sessions.INTERVIEW_QUESTION_FALLBACKS["self_check_method"]
    assert control.kind == "text"
    assert not control.options
    assert len(calls) == 1


@pytest.mark.parametrize("text", [
    "I suggest one concrete example. What have you completed so far?",
    "I recommend a short answer. What have you completed so far?",
    "I want to know where you stand. What have you completed so far?",
    "I'd like to understand your process. How do you check your work?",
    "I can help with the next step. What have you completed so far?",
    "Show me one example. What have you completed so far?",
    "We can use that example. What part did you finish without help?",
    "By week twelve, what result would prove success, and how would we see it?",
    "My next question is about your work. What did you complete?",
    "How many finished essays have you completed? Exclude abandoned drafts.",
    # gpt-6-luna's shared-planning voice (simulator run 2026-11-07).
    "Weekly reports and six blog posts give us real material to work with. Could you paste or briefly describe one short piece of your writing? Mark what you wrote without help and where you got stuck.",
    "Six finished pieces give us a useful base. What money, tools, or access can you already put toward writing clearer, more persuasive essays?",
    "Four focused hours a week gives us a workable rhythm. What specific result do you want by week twelve, and what visible evidence would prove your essays are clearer and more persuasive?",
    "Your answer helps us pick the first exercise. How do you check whether your argument is clear?",
    "That lets us plan around your evenings. What result would make these twelve weeks worthwhile?",
])
@pytest.mark.asyncio
async def test_present_coaching_and_learner_context_keep_the_adapted_question(monkeypatch, text):
    async def stream(**_kwargs):
        yield text

    monkeypatch.setattr(sessions, "interview_stream", stream)
    visible, _ = await sessions._generate_concise_interview_question(
        system_prompt="system", user_prompt="question", answer_key="practice_volume")
    assert visible == text


def test_intake_prompt_does_not_supply_biography_to_extend():
    params = sessions._interview_question_params(
        SimpleNamespace(user_age=24, user_financial_status=None, user_interests=["Writing"],
                        user_goal="Write essays", idol_facts_json={"facts": [{"description": "Published Pickwick"}]}),
        idol_name="Charles Dickens", chat_history_json="[]", current_turn=4,
        user_message="I ask a friend", required_answer_key="self_check_method")
    assert params["idol_facts_json"] == "{}"


@pytest.mark.asyncio
async def test_both_strategy_artifacts_use_evidence_review_not_persona(monkeypatch):
    from app.tasks import plans as plan_tasks
    from tests.test_automatic_results_pipeline import _Result, _use_session_lock

    session = IntakeSession(id="session-1", user_id="user-1", idol_id="idol-1",
        phase=SessionPhase.COMPARISON, user_age=24, user_interests=["writing"],
        user_goal="Write clearer essays", interview_thread_id="thread-1",
        idol_facts_json={"facts": [{"description": "Published Pickwick in 1836"}]})
    session.idol = Idol(id="idol-1", name="Charles Dickens", domain="literature")
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = []
    plan_job = SimpleNamespace(id="job-1", status="pending", step="waiting_for_strategy",
        progress_percent=0, error_message=None, weekly_hours=2)
    db = AsyncMock()
    db.execute.side_effect = [_Result(thread), _Result(thread), _Result(plan_job)]
    captured = {}

    async def comparison(**kwargs):
        captured["comparison"] = kwargs
        yield "Your short revision supplies evidence for one narrow skill."

    async def blueprint(**kwargs):
        captured["blueprint"] = kwargs
        yield "Use an in-app rubric review to check the next revision."

    async def lock(*_args, **_kwargs):
        return session, thread

    def forbidden_persona(*_args, **_kwargs):
        raise AssertionError("Factual strategy artifacts must not load an autobiographical persona")

    monkeypatch.setattr(sessions, "_get_session", AsyncMock(return_value=session))
    _use_session_lock(monkeypatch, session)
    monkeypatch.setattr(sessions, "_render_persona_system", forbidden_persona)
    monkeypatch.setattr(sessions, "comparison_stream", comparison)
    monkeypatch.setattr(sessions, "blueprint_stream", blueprint)
    monkeypatch.setattr(sessions, "generate_comparison_scores", AsyncMock(return_value={"version": 3, "placement_version": 1, "methodology": "like_for_like_evidence", "overall": {}, "dimensions": []}))
    monkeypatch.setattr(sessions, "_lock_interview_completion_state", lock)
    monkeypatch.setattr(sessions, "_sync_user_profile_from_interview", AsyncMock())
    monkeypatch.setattr(sessions, "_release_owned_thread_claim", AsyncMock())
    monkeypatch.setattr(plan_tasks.run_plan_generation, "delay", MagicMock())

    response = await sessions.generate_results("session-1", db, SimpleNamespace(id="user-1"))
    body = "".join([chunk async for chunk in response.body_iterator])
    assert '"type": "done"' in body
    assert set(captured) == {"comparison", "blueprint"}
    for call in captured.values():
        assert call["system_prompt"] == sessions._STRATEGY_EVIDENCE_SYSTEM
        assert "third person" in call["system_prompt"]
        assert "Published Pickwick in 1836" in call["user_message"]
    assert "most learners" not in session.comparison_output
    assert "in-app rubric review" in session.blueprint_output
