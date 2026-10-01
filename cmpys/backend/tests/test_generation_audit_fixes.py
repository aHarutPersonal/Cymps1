from types import SimpleNamespace
from unittest.mock import AsyncMock
import pytest
from fastapi import HTTPException
from app.services.planning.lesson_review import LessonReview, review_lesson
from app.services.intake_diagnostics import reports_no_achievements, has_established_habit_evidence
from app.schemas.auth import RegisterRequest


def test_wrong_case_answers_are_rejected_even_if_reviewer_approves():
    review = LessonReview(practice_minutes=40, acceptable=True, issues=[], contains_calculations=True, calculations=[
        {"location": "cash", "expression": "475-150-90+55", "claimed_result": 555},
        {"location": "profit", "expression": "475+260-150-70+55", "claimed_result": 610},
        {"location": "gap", "expression": "260+90-70", "claimed_result": 55},
    ])
    assert len(review.failures()) == 3
    for check, corrected in zip(review.calculations, (290, 570, 280)):
        check.claimed_result = corrected
    assert review.failures() == []


def test_numeric_review_cannot_skip_calculations():
    assert LessonReview(practice_minutes=40, acceptable=True, issues=[], contains_calculations=True, calculations=[]).failures()


def test_approved_review_keeps_nonblocking_editorial_advice_separate():
    review = LessonReview(
        acceptable=True, issues=[], practice_minutes=46,
        contains_calculations=False, calculations=[],
        advisories=[
            "Approximate phase budgets differ by one minute; this is not material.",
            "Step two appropriately builds on the saved draft from step one.",
            "An optional external clock is a useful convenience.",
        ],
    )
    assert review.failures() == []


@pytest.mark.parametrize("issue", [
    "The promised ten classification questions supply only two; eight are missing.",
    "The transfer case promises an answer key below but none is supplied.",
    "The required in-app spreadsheet editor does not exist.",
])
def test_blocking_review_issues_fail_even_with_contradictory_approval(issue):
    review = LessonReview(acceptable=True, issues=[issue], practice_minutes=46,
                          contains_calculations=False, calculations=[])
    assert review.failures() == [issue]


def test_rejected_review_without_reason_fails_closed():
    review = LessonReview(acceptable=False, issues=[], practice_minutes=46,
                          contains_calculations=False, calculations=[])
    assert review.failures() == ["Reviewer did not approve this lesson"]


@pytest.mark.asyncio
async def test_reviewer_receives_real_work_not_provisional_duration():
    import json
    response = SimpleNamespace(error=None, data={
        "acceptable": True, "issues": [], "advisories": ["Harmless one-minute rounding."],
        "practice_minutes": 46, "contains_calculations": False, "calculations": [],
    })
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    prose = "Phase budgets: 10+12+8+10+6 minutes. " + "reading " * 2400
    lesson = {"lesson_content": prose, "estimate_minutes": 60,
              "practice_minutes": 47, "reading_minutes": 99, "substeps": ["Keep the actual work."]}
    failures, _, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context={})
    assert failures == []
    sent = json.loads(client.generate_json.call_args.kwargs["user_prompt"])["lesson"]
    assert "practice_minutes" not in sent and "estimate_minutes" not in sent
    assert sent["reading_minutes"] == round(len(prose.split()) / 200)
    assert sent["lesson_content"] == prose
    assert lesson["practice_minutes"] == 47


def test_reviewed_timing_is_not_padded_to_minimum():
    from app.tasks.plans import _validate_plan_detail_step_response
    from tests.test_plan_detail_output_schema import _valid_payload
    step = _valid_payload()["steps"][0]
    step.update(reading_minutes=13, practice_minutes=10, estimate_minutes=23)
    response = SimpleNamespace(error=None, data=step)
    _validate_plan_detail_step_response(response, expected_step_id="step_1",
        material_titles={"Resource 1"}, normalize_timing=False)
    assert response.error
    assert response.data["practice_minutes"] == 10
    assert response.data["estimate_minutes"] == 23


def test_reviewed_timing_keeps_supported_duration_exactly():
    from app.tasks.plans import _validate_plan_detail_step_response
    from tests.test_plan_detail_output_schema import _valid_payload
    step = _valid_payload()["steps"][0]
    step.update(reading_minutes=13, practice_minutes=46, estimate_minutes=59)
    response = SimpleNamespace(error=None, data=step)
    _validate_plan_detail_step_response(response, expected_step_id="step_1",
        material_titles={"Resource 1"}, normalize_timing=False)
    assert response.error is None
    assert response.data["practice_minutes"] == 46
    assert response.data["estimate_minutes"] == 59


@pytest.mark.asyncio
async def test_cancelled_detail_generation_stops_all_siblings_and_keeps_outline():
    import asyncio
    from copy import deepcopy
    from app.tasks.plans import _generate_plan_item_details_parallel
    from app.services.llm.schemas import PlanItemDetailsOutlineOutput
    from tests.test_plan_detail_output_schema import _outline_payload
    started = 0
    cancelled = 0
    all_started = asyncio.Event()
    checkpoints = []
    async def generate_json(**kwargs):
        nonlocal started, cancelled
        if kwargs["output_model"] is PlanItemDetailsOutlineOutput:
            return SimpleNamespace(error=None, data=_outline_payload())
        started += 1
        if started == 3:
            all_started.set()
        try:
            await asyncio.Event().wait()
        finally:
            cancelled += 1
    async def checkpoint(payload, stage):
        checkpoints.append((deepcopy(payload), stage))
    client = SimpleNamespace(model="test", generate_json=generate_json)
    task = asyncio.create_task(_generate_plan_item_details_parallel(
        system_prompt="test", task_title="Lesson", mission_hours=5, user_goal="Learn",
        learning_preferences="practice", idol_name="Mentor", idol_domain="business",
        idol_evidence={}, session_context="", active_tier="balanced", routing_reason="test",
        client_factory=lambda **kw: client, on_checkpoint=checkpoint,
    ))
    await asyncio.wait_for(all_started.wait(), timeout=1)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert cancelled == started == 3
    assert len(checkpoints) == 1 and checkpoints[0][1] == "outline_ready"
    assert checkpoints[0][0]["steps"]


@pytest.mark.asyncio
async def test_detail_deadline_is_enforced_without_celery_signals(monkeypatch):
    import asyncio
    from app.tasks import plans
    stopped = asyncio.Event()
    async def stuck(_job_id):
        try:
            await asyncio.Event().wait()
        finally:
            stopped.set()
    monkeypatch.setattr(plans, "_regenerate_plan_item_details_async", stuck)
    monkeypatch.setattr(plans, "PLAN_DETAIL_PIPELINE_TIMEOUT_SECONDS", 0.01)
    with pytest.raises(TimeoutError):
        await plans._regenerate_plan_item_details_with_deadline("job-1")
    assert stopped.is_set()


@pytest.mark.asyncio
async def test_failed_review_cannot_publish():
    client = SimpleNamespace(generate_json=AsyncMock(return_value=SimpleNamespace(error="timeout", data={})))
    failures, _, _ = await review_lesson({}, client_factory=lambda **kw: client, context={})
    assert failures


def test_no_achievements_explanation_and_planned_habits():
    assert reports_no_achievements("None yet. I have never invested and have no portfolio.")
    assert not reports_no_achievements("None except a portfolio I have managed for three years")
    assert not has_established_habit_evidence("This is a new habit, no past study habit is established.")
    assert has_established_habit_evidence("I have studied for an hour every Tuesday for six months.")


def test_registration_accepts_mobile_name_field():
    assert RegisterRequest(email="qa@example.com", password="synthetic", full_name="QA Learner").full_name == "QA Learner"
    assert RegisterRequest(email="qa@example.com", password="synthetic", fullName="QA Learner").full_name == "QA Learner"


@pytest.mark.asyncio
async def test_history_checks_owner_before_reading_messages(monkeypatch):
    from app.api.v1 import sessions
    load = AsyncMock(side_effect=HTTPException(404, "Session not found"))
    monkeypatch.setattr(sessions, "_get_session", load)
    db = SimpleNamespace(execute=AsyncMock())
    with pytest.raises(HTTPException):
        await sessions.guided_learning_messages("other-session", db, SimpleNamespace(id="viewer"))
    db.execute.assert_not_called()
    load.assert_awaited_once_with("other-session", "viewer", db)


@pytest.mark.asyncio
async def test_history_restores_chronological_messages(monkeypatch):
    from app.api.v1 import sessions
    from app.models.chat import MessageRole
    rows = [SimpleNamespace(id="b", role=MessageRole.ASSISTANT, content="Reply"), SimpleNamespace(id="a", role=MessageRole.USER, content="Question")]
    monkeypatch.setattr(sessions, "_get_session", AsyncMock(return_value=SimpleNamespace(learning_thread_id="thread")))
    db = SimpleNamespace(execute=AsyncMock(return_value=SimpleNamespace(scalars=lambda: SimpleNamespace(all=lambda: rows))))
    out = await sessions.guided_learning_messages("session", db, SimpleNamespace(id="viewer"))
    assert [m['content'] for m in out['messages']] == ['Question', 'Reply']
    assert 'chat_threads.user_id' in str(db.execute.call_args.args[0])


@pytest.mark.asyncio
async def test_daily_reflection_does_not_claim_completion(monkeypatch):
    from app.api.v1 import plans
    from app.models.plan import PlanItemType
    item = SimpleNamespace(type=PlanItemType.HABIT, meta_json={"practice_versions": {"a": "b"}})
    monkeypatch.setattr(plans, "_get_item_for_user", AsyncMock(return_value=item))
    db = SimpleNamespace(commit=AsyncMock())
    result = await plans.save_daily_reflection("item", plans.DailyReflectionRequest(text="I tested the difference between profit and cash."), db, SimpleNamespace(id="viewer"))
    assert item.meta_json['daily_reflections'][result['date']] == result['text']
    assert item.meta_json['practice_versions'] == {'a': 'b'}
    db.commit.assert_awaited_once()


def test_weekly_total_accepts_an_explanatory_schedule():
    from app.services.interview_inputs import parse_weekly_hours_answer
    assert parse_weekly_hours_answer("4 hours per week: Tuesday 1 hour, Thursday 1 hour, Saturday 2 hours") == 4
    assert parse_weekly_hours_answer("4 hours per week or maybe 8 on Saturday") is None


@pytest.mark.asyncio
async def test_outline_publication_failure_returns_already_paid_call(monkeypatch):
    from app.tasks.plans import _generate_plan_item_details_parallel
    from tests.test_plan_detail_output_schema import _outline_payload
    response = SimpleNamespace(error=None, data=_outline_payload())
    client = SimpleNamespace(model="fake", generate_json=AsyncMock(return_value=response))
    async def broken_checkpoint(*args):
        raise ValueError("storage conversion failed")
    payload, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="test", task_title="Lesson", mission_hours=5, user_goal="Learn",
        learning_preferences="practice", idol_name="Mentor", idol_domain="business",
        idol_evidence={}, session_context="", active_tier="balanced", routing_reason="test",
        client_factory=lambda **kw: client, on_checkpoint=broken_checkpoint,
    )
    assert error == "Outline checkpoint failed: ValueError"
    assert len(calls) == 1 and calls[0][1] is response
    assert payload["definition_of_done"]


def test_material_normalization_does_not_mutate_outline_checkpoint():
    from copy import deepcopy
    from app.tasks.plans import _normalized_outline_materials
    from app.services.llm.schemas import PlanItemDetailsOutlineOutput
    from tests.test_plan_detail_output_schema import _outline_payload
    original = _outline_payload()
    expected = deepcopy(original)
    materials = _normalized_outline_materials(original)
    assert materials and original == expected
    PlanItemDetailsOutlineOutput.model_validate(original)


def test_checkpoint_keeps_cached_book_content_out_of_outline_schema():
    from copy import deepcopy
    from app.tasks.plans import _plan_detail_checkpoint_payload
    from app.services.llm.schemas import PlanItemDetailsOutlineOutput
    from tests.test_plan_detail_output_schema import _outline_payload
    original = _outline_payload()
    before = deepcopy(original)
    materials = deepcopy(original["materials"])
    materials[0].update(
        content_resource_id="reviewed-book",
        content_markdown="A fully reviewed long-form book guide.",
        ideas=[{"title": "A practical idea", "description": "Apply the framework."}],
        url="https://example.org/book",
    )
    if len(materials) > 1:
        materials[1]["duration_minutes"] = None
    outline, delivery = _plan_detail_checkpoint_payload(original, materials)
    assert original == before
    assert outline == PlanItemDetailsOutlineOutput.model_validate(before).model_dump(mode="json")
    assert delivery["materials"][0]["content_markdown"]
    assert delivery["materials"][0]["content_resource_id"] == "reviewed-book"
    assert outline["materials"][0]["content_markdown"] is None
    assert outline["materials"][0]["ideas"] == []
    PlanItemDetailsOutlineOutput.model_validate(outline)


def test_new_study_schedule_does_not_prove_daily_discipline():
    assert not has_established_habit_evidence("Worked examples help. My study schedule is new, so start with manageable sessions.")


def test_daily_weekly_minutes_must_match_allocation():
    from app.services.planning.generator import daily_workload_issues
    from app.services.llm.schemas import BinaryTask
    task = BinaryTask(title="Reflection", type="habit", estimated_hours=1,
                      description="This habit takes about 30 minutes per week total.")
    assert daily_workload_issues(task)
    task.description = "Three twenty-minute sessions take 60 minutes per week."
    assert not daily_workload_issues(task)


@pytest.mark.parametrize('answer', [
    'Nothing yet', 'None', 'Nothing', 'Not yet', 'I do not have a routine',
    'Пока ничего', 'Worked examples help me understand', 'I want to study every day',
    'I will study every day', "I'm going to practice weekly",
    "I don't study consistently", 'I cannot study every day',
    'I could practice daily', 'A weekly study partner would help',
])
def test_missing_or_planned_habits_are_not_discipline_evidence(answer):
    assert not has_established_habit_evidence(answer)


def test_no_habit_answer_removes_unsupported_model_score():
    from app.services.comparison.scoring import normalize_comparison_scores
    raw = {'dimensions': [{'id':'habits','status':'comparable',
        'comparison_basis':'daily practice','you_level':3,'idol_level':3,
        'you_evidence':'self_reported','idol_evidence':'documented',
        'you_note':'Routine','idol_note':'Routine'}]}
    result = normalize_comparison_scores(raw, learner_baseline={
        'learning_habits_support': {'answer':'Nothing yet'}})
    habits = next(d for d in result['dimensions'] if d['id']=='habits')
    assert habits['you'] is None
    assert habits['status'] == 'insufficient_user_evidence'
