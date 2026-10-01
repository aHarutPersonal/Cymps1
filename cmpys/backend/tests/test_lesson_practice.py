from copy import deepcopy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.v1 import practice as api
from app.models.lesson_practice import LessonPractice
from app.services.practice.contracts import (
    Activity,
    DraftRequest,
    SubmitRequest,
    TextReview,
    Workbook,
    calculate,
    combine_review,
    grade_fixed,
    lesson_version,
    public_workbook,
    validate_answers,
)


def activity(*, aid="case_a", text=False):
    fields = [
        {
            "id": "length",
            "label": "Hypotenuse",
            "kind": "number",
            "expression": "sqrt(x*x+y*y)",
            "unit": "cm",
        }
    ]
    if text:
        fields.append(
            {
                "id": "reason",
                "label": "Explain the assumption",
                "kind": "text",
                "criteria": ["States that the triangle is right-angled"],
            }
        )
    return Activity.model_validate(
        {
            "id": aid,
            "title": "Calculate the missing side",
            "kind": "practice",
            "instructions": "A right triangle has legs x and y. Calculate its hypotenuse in cm.",
            "data": [
                {"id": "x", "label": "First leg", "value": 3},
                {"id": "y", "label": "Second leg", "value": 4},
            ],
            "fields": fields,
            "hint": "Think about the relationship between the squared lengths.",
            "worked_solution": "The sum of squares is 9 + 16 = 25, whose positive square root is 5 cm.",
            "minutes_min": 3,
            "minutes_max": 6,
            "diagram": {
                "caption": "Right triangle; leg lengths are specified in the data.",
                "points": [
                    {"label": "A", "x": 10, "y": 10},
                    {"label": "B", "x": 10, "y": 90},
                    {"label": "C", "x": 90, "y": 90},
                ],
            },
        }
    )


def workbook(text=False):
    a = activity(text=text)
    b = activity(aid="case_b").model_copy(update={"kind": "transfer"})
    b.data[0].value, b.data[1].value = 5, 12
    b.worked_solution = (
        "The sum of squares is 25 + 144 = 169; the positive square root is 13 cm."
    )
    return Workbook(title="Triangle practice", activities=[a, b])


@pytest.mark.parametrize(
    "expr,values,answer",
    [
        ("sqrt(x*x+y*y)", {"x": 3, "y": 4}, 5),
        (
            "profit+depreciation-maintenance-capital",
            {"profit": 40, "depreciation": 12, "maintenance": 18, "capital": 4},
            30,
        ),
        ("-x/2", {"x": 6}, -3),
    ],
)
def test_computable_answers(expr, values, answer):
    assert calculate(expr, values) == answer


@pytest.mark.parametrize(
    "expr",
    [
        "__import__('os')",
        "x.real",
        "[1][0]",
        "2**99999",
        "1/0",
        "sqrt(-1)",
        "1e999",
        "unknown+1",
        "True",
        "1+",
    ],
)
def test_expression_language_fails_closed(expr):
    with pytest.raises(ValueError):
        calculate(expr, {"x": 3})


@pytest.mark.parametrize(
    "answer,passed",
    [
        ("5", True),
        ("5,00", True),
        ("4", False),
        ("NaN", False),
        ("inf", False),
        ("5 cm", False),
    ],
)
def test_numeric_grading_does_not_trust_client(answer, passed):
    assert grade_fixed(activity(), {"case_a.length": answer})[0]["passed"] is passed


def test_private_answers_and_hints_are_not_in_public_definition():
    result = public_workbook(workbook())
    a = result["activities"][0]
    assert "hint" not in a and "worked_solution" not in a
    assert all("criteria" not in field for field in a["fields"])
    assert not {"expression", "correct_choice", "tolerance"} & set(a["fields"][0])


def test_reject_unknown_answers_and_oversized_work():
    with pytest.raises(ValueError):
        validate_answers(workbook(), {"forged.pass": "true"})
    with pytest.raises(ValidationError):
        DraftRequest(revision=0, answers={"a": "x" * 8001})


def test_schema_rejects_non_finite_data_duplicate_ids_and_missing_transfer():
    raw = workbook().model_dump()
    for mutate in (
        lambda d: d["activities"][0]["data"][0].update(value=float("nan")),
        lambda d: d["activities"][1].update(id="case_a"),
        lambda d: d["activities"][-1].update(kind="practice"),
        lambda d: d["activities"][0].update(minutes_max=1),
    ):
        bad = deepcopy(raw)
        mutate(bad)
        with pytest.raises(ValidationError):
            Workbook.model_validate(bad)


def test_review_must_cover_exact_rubric_and_uncertainty_does_not_pass():
    a = activity(text=True)
    good = TextReview.model_validate(
        {
            "fields": [
                {
                    "field_id": "reason",
                    "criterion_met": [True],
                    "feedback": "Correctly identifies the right-angle assumption.",
                    "uncertain": True,
                }
            ]
        }
    )
    result = combine_review(a, [], good)[0]
    assert result["passed"] is False
    assert result["criteria"] == a.fields[-1].criteria
    with pytest.raises(ValueError):
        combine_review(a, [], None)
    with pytest.raises(ValueError):
        combine_review(a, [], good.model_copy(update={"fields": good.fields * 2}))


def test_version_changes_with_job_or_lesson_content():
    item = SimpleNamespace(details_json={"_generation": {"job_id": "one"}})
    step = {"id": "s1", "lesson_content": "original"}
    before = lesson_version(item, step)
    assert before != lesson_version(item, {**step, "lesson_content": "changed"})
    item.details_json["_generation"]["job_id"] = "two"
    assert before != lesson_version(item, step)


@pytest.fixture
def state(monkeypatch):
    w = workbook(text=True)
    step = {"id": "s1", "lesson_content": "A self-contained geometry lesson."}
    item = SimpleNamespace(
        id="item",
        title="Geometry",
        success_metric="Solve a new triangle",
        details_json={"steps": [step]},
        meta_json={},
    )
    version = lesson_version(item, step)
    row = LessonPractice(
        user_id="user",
        plan_item_id="item",
        step_id="s1",
        lesson_version=version,
        state="ready",
        revision=0,
        generation_attempts=1,
        review_calls=0,
        answers_json={
            "case_a.length": "5",
            "case_a.reason": "This is a right triangle.",
        },
        attempts_json=[],
        hints_json=[],
        workbook_json=w.model_dump(),
    )
    load = AsyncMock(return_value=(item, step, row, version))
    monkeypatch.setattr(api, "_load", load)
    review = AsyncMock(
        return_value=TextReview.model_validate(
            {
                "fields": [
                    {
                        "field_id": "reason",
                        "criterion_met": [True],
                        "feedback": "You correctly stated the necessary right-angle assumption.",
                    }
                ]
            }
        )
    )
    monkeypatch.setattr(api, "review_text", review)
    db = AsyncMock()
    db.add = Mock()
    return SimpleNamespace(
        item=item,
        step=step,
        row=row,
        version=version,
        db=db,
        user=SimpleNamespace(id="user"),
        load=load,
        review=review,
    )


def submission(revision=0, aid="case_a", request="request_001"):
    return SubmitRequest(revision=revision, activity_id=aid, request_id=request)


@pytest.mark.asyncio
async def test_submission_persists_snapshot_and_duplicate_is_free(state):
    result = await api.submit_practice("item", "s1", submission(), state.db, state.user)
    assert result["passed_activity_ids"] == ["case_a"] and not result["complete"]
    assert result["attempts"][0]["answers"]["length"] == "5"
    assert state.db.commit.await_count == 2  # release before review, then persist
    await api.submit_practice("item", "s1", submission(), state.db, state.user)
    await api.submit_practice(
        "item",
        "s1",
        submission(revision=1, request="request_002"),
        state.db,
        state.user,
    )
    assert state.review.await_count == 1


@pytest.mark.asyncio
async def test_failed_review_keeps_draft_and_consumes_bounded_call(state):
    state.review.side_effect = RuntimeError("provider unavailable")
    with pytest.raises(HTTPException) as exc:
        await api.submit_practice("item", "s1", submission(), state.db, state.user)
    assert exc.value.status_code == 503
    assert state.row.answers_json["case_a.length"] == "5"
    assert state.row.review_calls == 1 and state.row.attempts_json == []
    assert state.row.state == "ready" and state.row.lease_until is None


@pytest.mark.asyncio
async def test_future_activity_and_concurrent_review_blocked(state):
    with pytest.raises(HTTPException):
        await api.submit_practice(
            "item", "s1", submission(aid="case_b"), state.db, state.user
        )
    state.row.lease_until = datetime.now(timezone.utc) + timedelta(seconds=30)
    with pytest.raises(HTTPException):
        await api.submit_practice("item", "s1", submission(), state.db, state.user)
    state.review.assert_not_awaited()


@pytest.mark.asyncio
async def test_save_uses_revision_and_rejects_unknown_fields(state):
    with pytest.raises(HTTPException) as exc:
        await api.save_draft(
            "item", "s1", DraftRequest(revision=99, answers={}), state.db, state.user
        )
    assert exc.value.status_code == 409
    with pytest.raises(HTTPException) as exc:
        await api.save_draft(
            "item",
            "s1",
            DraftRequest(revision=0, answers={"forged": "true"}),
            state.db,
            state.user,
        )
    assert exc.value.status_code == 422
    result = await api.save_draft(
        "item",
        "s1",
        DraftRequest(revision=0, answers={"case_a.length": "4"}),
        state.db,
        state.user,
    )
    assert result["revision"] == 1 and result["answers"]["case_a.length"] == "4"


@pytest.mark.asyncio
async def test_hint_is_recorded_and_solution_requires_attempt(state):
    with pytest.raises(HTTPException):
        await api.get_hint(
            "item", "s1", submission(), state.db, state.user, solution=True
        )
    result = await api.get_hint("item", "s1", submission(), state.db, state.user)
    assert result["hints"][0]["kind"] == "hint"
    result = await api.submit_practice(
        "item", "s1", submission(revision=1), state.db, state.user
    )
    assert result["attempts"][0]["assisted"] is True


@pytest.mark.asyncio
async def test_preparation_is_cached_and_pending_does_not_fan_out(state, monkeypatch):
    generate = AsyncMock()
    monkeypatch.setattr(api, "generate_workbook", generate)
    await api.prepare_practice("item", "s1", state.db, state.user)
    generate.assert_not_awaited()
    state.row.workbook_json = None
    state.row.lease_until = datetime.now(timezone.utc) + timedelta(seconds=30)
    await api.prepare_practice("item", "s1", state.db, state.user)
    generate.assert_not_awaited()


@pytest.mark.asyncio
async def test_preparation_failure_and_generation_limit(state, monkeypatch):
    state.row.workbook_json = None
    generate = AsyncMock(side_effect=ValueError("invalid response"))
    monkeypatch.setattr(api, "generate_workbook", generate)
    result = await api.prepare_practice("item", "s1", state.db, state.user)
    assert result["state"] == "failed"
    assert state.item.meta_json["practice_versions"]["s1"] == state.version
    state.row.generation_attempts = 3
    with pytest.raises(HTTPException) as exc:
        await api.prepare_practice("item", "s1", state.db, state.user)
    assert exc.value.status_code == 429 and generate.await_count == 1


@pytest.mark.asyncio
async def test_stale_lesson_cannot_accept_finished_review(state):
    state.load.side_effect = [
        (state.item, state.step, state.row, state.version),
        (state.item, state.step, None, "new-version"),
    ]
    with pytest.raises(HTTPException) as exc:
        await api.submit_practice("item", "s1", submission(), state.db, state.user)
    assert exc.value.status_code == 409 and not state.row.attempts_json


@pytest.mark.asyncio
async def test_bulk_completion_cannot_bypass_required_practice(state):
    state.item.meta_json = {"practice_versions": {"s1": state.version}}
    result = Mock()
    result.scalar_one_or_none.return_value = state.row
    state.db.execute.return_value = result
    with pytest.raises(HTTPException) as exc:
        await api.require_practice_complete(state.db, state.item, "user")
    assert exc.value.status_code == 409
    # Old artifacts remain compatible; changed content cannot inherit old work.
    state.item.meta_json = {}
    await api.require_practice_complete(state.db, state.item, "user")


def test_mutating_draft_invalidates_previous_pass(state):
    state.row.attempts_json = [
        {
            "activity_id": "case_a",
            "passed": True,
            "answers": {"length": "5", "reason": "This is a right triangle."},
        }
    ]
    assert api.view(state.row)["passed_activity_ids"] == ["case_a"]
    state.row.answers_json = {**state.row.answers_json, "case_a.length": "4"}
    assert not api.view(state.row)["passed_activity_ids"]


@pytest.mark.asyncio
async def test_load_enforces_ownership_before_reading_work(monkeypatch):
    from app.api.v1 import plans

    owned = AsyncMock(side_effect=HTTPException(404, "Plan item not found"))
    monkeypatch.setattr(plans, "_get_item_for_user", owned)
    db = AsyncMock()
    with pytest.raises(HTTPException) as exc:
        await api._load(db, "other-user", "item", "s1", None)
    assert exc.value.status_code == 404
    owned.assert_awaited_once_with(db, "item", "other-user", for_update=False)
    db.execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_load_scopes_query_to_owner_step_and_content_version(monkeypatch):
    from app.api.v1 import plans

    item = SimpleNamespace(
        details_json={
            "steps": [
                {
                    "id": "s1",
                    "title": "Geometry",
                    "lesson_content": "A self-contained lesson.",
                }
            ]
        }
    )
    monkeypatch.setattr(plans, "_get_item_for_user", AsyncMock(return_value=item))
    result = Mock()
    result.scalar_one_or_none.return_value = None
    db = AsyncMock()
    db.execute.return_value = result
    _, step, row, version = await api._load(db, "user", "item", "s1", None, lock=True)
    assert row is None and version == lesson_version(item, step)
    values = set(db.execute.call_args.args[0].compile().params.values())
    assert {"user", "item", "s1", version} <= values


@pytest.mark.asyncio
async def test_completed_work_cannot_be_overwritten(state):
    w = Workbook.model_validate(state.row.workbook_json)
    state.row.answers_json["case_b.length"] = "13"
    state.row.attempts_json = [
        {
            "activity_id": a.id,
            "passed": True,
            "answers": api._activity_answers(a, state.row.answers_json),
        }
        for a in w.activities
    ]
    with pytest.raises(HTTPException) as exc:
        await api.save_draft(
            "item", "s1", DraftRequest(revision=0, answers={}), state.db, state.user
        )
    assert exc.value.status_code == 409
    assert api.view(state.row)["complete"]


@pytest.mark.asyncio
async def test_new_lessons_require_practice_even_before_first_prepare(state):
    state.item.details_json["_generation"] = {"practice_required": True}
    result = Mock()
    result.scalar_one_or_none.return_value = None
    state.db.execute.return_value = result
    for selected in (None, state.step):
        with pytest.raises(HTTPException) as exc:
            await api.require_practice_complete(state.db, state.item, "user", selected)
        assert exc.value.status_code == 409


@pytest.mark.asyncio
async def test_generation_uses_registered_prompts_without_live_provider(monkeypatch):
    from app.services.practice import generation

    client = SimpleNamespace(
        generate_and_validate=AsyncMock(return_value=(workbook(), SimpleNamespace(error=None)))
    )
    monkeypatch.setattr(generation, "get_llm_client", Mock(return_value=client))
    monkeypatch.setattr(generation, "record_llm_response", AsyncMock())
    result = await generation.generate_workbook({"lesson_content": "lesson"}, {})
    assert result.activities[-1].kind == "transfer"
    call = client.generate_and_validate.call_args.kwargs
    assert call["repair_on_failure"] is False
    assert "untrusted" in call["system_prompt"]
    assert call["output_model"] is Workbook


@pytest.mark.asyncio
async def test_workbook_uses_balanced_route_with_budget_below_its_lease(monkeypatch):
    from app.services.practice import generation

    client = SimpleNamespace(generate_and_validate=AsyncMock(
        return_value=(workbook(), SimpleNamespace(error=None))
    ))
    factory = Mock(return_value=client)
    monkeypatch.setattr(generation.settings, "llm_provider", "zai")
    monkeypatch.setattr(generation, "get_llm_client", factory)
    monkeypatch.setattr(generation, "record_llm_response", AsyncMock())
    await generation.generate_workbook({"lesson_content": "lesson"}, {})
    config = factory.call_args.kwargs
    assert config["tier"] == "balanced"
    assert config["thinking_level"] == "low"
    assert config["max_tokens"] == 4000
    assert config["timeout"] == 90
    assert config["timeout"] + 6 < generation.PRACTICE_GENERATION_BUDGET_SECONDS
    assert generation.PRACTICE_GENERATION_BUDGET_SECONDS < api.PRACTICE_GENERATION_LEASE_SECONDS
    assert generation.PRACTICE_REVIEW_BUDGET_SECONDS < 60


@pytest.mark.asyncio
async def test_provider_timeout_preserves_failure_classification(monkeypatch):
    from app.services.practice import generation
    from app.services.llm import recovery
    from app.services.llm.client import LLMResponse

    client = SimpleNamespace(generate_and_validate=AsyncMock(return_value=(
        None, LLMResponse(data={}, provider="zai", error="zai request failed (TimeoutError; finish=missing)")
    )))
    recorder = AsyncMock()
    monkeypatch.setattr(generation, "get_llm_client", lambda **kwargs: client)
    monkeypatch.setattr(recovery, "operational_recovery_client", lambda *args, **kwargs: None)
    monkeypatch.setattr(generation, "record_llm_response", recorder)
    with pytest.raises(TimeoutError):
        await generation.generate_workbook({}, {})
    assert recorder.call_args.kwargs["metadata"]["failure_kind"] == "provider_timeout"


@pytest.mark.asyncio
async def test_operation_deadline_cancels_work_before_the_lease_expires(monkeypatch):
    import asyncio
    from app.services.practice import generation

    cancelled = asyncio.Event()

    async def never_finishes(*args, **kwargs):
        try:
            await asyncio.Event().wait()
        finally:
            cancelled.set()

    monkeypatch.setattr(generation, "PRACTICE_GENERATION_BUDGET_SECONDS", 0.01)
    monkeypatch.setattr(generation, "_structured_request", never_finishes)
    with pytest.raises(TimeoutError):
        await generation.generate_workbook({}, {})
    assert cancelled.is_set()


@pytest.mark.asyncio
async def test_exhausted_preparation_recovers_only_after_cooldown(state, monkeypatch):
    state.row.workbook_json = None
    state.row.state = "failed"
    state.row.generation_attempts = 3
    state.row.updated_at = datetime.now(timezone.utc)
    generate = AsyncMock(return_value=workbook())
    monkeypatch.setattr(api, "generate_workbook", generate)
    assert not api.view(state.row)["can_retry_preparation"]
    assert api.view(state.row)["retry_after_seconds"] > 1700
    with pytest.raises(HTTPException) as error:
        await api.prepare_practice("item", "s1", state.db, state.user)
    assert error.value.status_code == 429
    assert int(error.value.headers["Retry-After"]) > 1700
    generate.assert_not_awaited()
    assert state.row.generation_attempts == 3

    state.row.updated_at -= api.PREPARATION_RETRY_COOLDOWN + timedelta(seconds=1)
    assert api.view(state.row)["can_retry_preparation"]
    result = await api.prepare_practice("item", "s1", state.db, state.user)
    assert result["state"] == "ready"
    assert state.row.generation_attempts == 1
    generate.assert_awaited_once()


@pytest.mark.asyncio
async def test_new_window_preserves_active_lease_and_prevents_fanout(state, monkeypatch):
    state.row.workbook_json = None
    state.row.state = "failed"
    state.row.generation_attempts = 3
    state.row.updated_at = datetime.now(timezone.utc) - timedelta(hours=1)

    async def generate(*args):
        assert 115 < (state.row.lease_until - datetime.now(timezone.utc)).total_seconds() <= 120
        overlap = await api.prepare_practice("item", "s1", state.db, state.user)
        assert overlap["state"] == "preparing"
        assert state.row.generation_attempts == 1
        return workbook()

    generate_mock = AsyncMock(side_effect=generate)
    monkeypatch.setattr(api, "generate_workbook", generate_mock)
    result = await api.prepare_practice("item", "s1", state.db, state.user)
    assert result["state"] == "ready"
    generate_mock.assert_awaited_once()


def test_expired_worker_waits_for_cooldown_after_lease_not_claim_time(state):
    state.row.workbook_json = None
    state.row.state = "preparing"
    state.row.generation_attempts = 3
    state.row.updated_at = datetime.now(timezone.utc) - timedelta(hours=1)
    state.row.lease_until = datetime.now(timezone.utc) - timedelta(seconds=1)
    result = api.view(state.row)
    assert result["state"] == "failed"
    assert not result["can_retry_preparation"]
    assert result["retry_after_seconds"] > 1700


@pytest.mark.asyncio
async def test_prepare_classifies_timeout_and_rejects_a_late_lease_owner(state, monkeypatch):
    state.row.workbook_json = None
    monkeypatch.setattr(api, "generate_workbook", AsyncMock(side_effect=TimeoutError()))
    result = await api.prepare_practice("item", "s1", state.db, state.user)
    assert result["state"] == "failed"
    assert state.item.meta_json["practice_preparation_failures"]["s1"]["code"] == "provider_timeout"

    async def replaced(*args):
        state.row.lease_token = "a-newer-owner"
        return workbook()

    monkeypatch.setattr(api, "generate_workbook", replaced)
    with pytest.raises(HTTPException) as error:
        await api.prepare_practice("item", "s1", state.db, state.user)
    assert error.value.status_code == 409
    assert state.row.workbook_json is None


def _evidence_row(*, assisted=False):
    w = workbook()
    row = SimpleNamespace(
        answers_json={"case_a.length": "5", "case_b.length": "13"}, attempts_json=[]
    )
    for a in w.activities:
        row.attempts_json.append(
            {
                "activity_id": a.id,
                "answers": {f.id: row.answers_json[f"{a.id}.{f.id}"] for f in a.fields},
                "passed": True,
                "assisted": assisted if a.kind == "transfer" else True,
                "feedback": [],
                "submitted_at": "2026-09-09T10:00:00+00:00",
            }
        )
    return row, w


def test_learning_evidence_distinguishes_supported_and_unhinted_transfer():
    from app.services.practice.evidence import practice_summary

    row, w = _evidence_row()
    assert practice_summary(row, w)["status"] == "transfer_without_hint"
    row.attempts_json[-1]["assisted"] = True
    assert practice_summary(row, w)["status"] == "completed_with_support"
    row.attempts_json[-1].pop("assisted")
    assert practice_summary(row, w)["status"] == "completed_with_support"


def test_changed_draft_and_uncertain_review_do_not_become_failed_knowledge():
    from app.services.practice.evidence import practice_summary

    row, w = _evidence_row()
    row.answers_json["case_b.length"] = "14"
    assert practice_summary(row, w)["activities"][-1]["status"] == "not_assessed"
    row.attempts_json.append(
        {
            "activity_id": "case_b",
            "answers": {"length": "14"},
            "passed": False,
            "feedback": [{"uncertain": True}],
            "assisted": False,
        }
    )
    assert practice_summary(row, w)["status"] == "needs_review"
    row.attempts_json[-1]["feedback"] = [{"passed": False}]
    assert practice_summary(row, w)["status"] == "needs_practice"


def test_evidence_excludes_private_answers_solutions_and_feedback_text():
    from app.services.practice.evidence import practice_summary

    row, w = _evidence_row()
    row.attempts_json[-1]["feedback"] = [{"feedback": "private explanation"}]
    result = str(practice_summary(row, w))
    assert "private explanation" not in result
    assert "answers" not in result and "expression" not in result
    assert "13" not in result


@pytest.mark.asyncio
async def test_cached_review_still_works_when_review_budget_is_exhausted(state):
    data = SubmitRequest(revision=0, activity_id="case_a", request_id="first_call")
    await api.submit_practice("item", "s1", data, state.db, state.user)
    state.row.review_calls = 40
    result = await api.submit_practice(
        "item",
        "s1",
        data.model_copy(
            update={"revision": state.row.revision, "request_id": "duplicate_call"}
        ),
        state.db,
        state.user,
    )
    assert result["passed_activity_ids"] == ["case_a"]
    assert state.row.review_calls == 40
    assert state.review.await_count == 1


@pytest.mark.asyncio
async def test_recent_evidence_is_scoped_and_rejects_stale_or_revoked_lessons(
    monkeypatch,
):
    from app.api.v1 import plans as plans_api
    from app.services.practice.evidence import load_recent_practice_evidence
    from app.services.planning import catalog_lessons

    row, w = _evidence_row()
    step = {"id": "s1", "title": "Triangle", "lesson_content": "Lesson"}
    item = SimpleNamespace(id="item", title="Geometry", details_json={"steps": [step]})
    row.workbook_json = w.model_dump()
    row.step_id = "s1"
    row.lesson_version = lesson_version(item, step)
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(all=lambda: [(row, item)])
    monkeypatch.setattr(
        plans_api, "_validated_lesson_steps", lambda details: details["steps"]
    )
    monkeypatch.setattr(
        plans_api, "_progress_eligible_step_ids", lambda details: {"s1"}
    )
    availability = AsyncMock(return_value=True)
    monkeypatch.setattr(
        catalog_lessons, "catalog_details_are_ready_in_database", availability
    )
    result = await load_recent_practice_evidence(
        db, user_id="u", idol_id="i", session_id="s"
    )
    assert result[0]["status"] == "transfer_without_hint"
    statement = db.execute.await_args.args[0]
    sql = str(statement)
    assert (
        "lesson_practices.user_id" in sql
        and "plans.user_id" in sql
        and "plans.idol_id" in sql
    )
    assert "source_session_id" in statement.compile().params.values()
    assert 8 in statement.compile().params.values()
    row.lesson_version = "stale"
    assert (
        await load_recent_practice_evidence(
            db, user_id="u", idol_id="i", session_id="s"
        )
        == []
    )
    row.lesson_version = lesson_version(item, step)
    availability.return_value = False
    assert (
        await load_recent_practice_evidence(
            db, user_id="u", idol_id="i", session_id="s"
        )
        == []
    )
    db.execute.reset_mock()
    assert (
        await load_recent_practice_evidence(db, user_id="u", idol_id="", session_id="s")
        == []
    )
    db.execute.assert_not_awaited()


def test_small_prompt_budget_keeps_the_unresolved_skill_and_transfer():
    from app.services.practice.evidence import compact_practice_evidence
    result = compact_practice_evidence([{
        'lesson': 'Geometry', 'status': 'needs_practice',
        'activities': [
            {'title': 'Right-angle condition', 'status': 'needs_practice', 'kind': 'practice'},
            {'title': 'Arithmetic', 'status': 'passed_without_hint', 'kind': 'practice'},
            {'title': 'Another drill', 'status': 'passed_without_hint', 'kind': 'practice'},
            {'title': 'New case', 'status': 'passed_with_support', 'kind': 'transfer'},
        ],
    }])
    assert [check['title'] for check in result[0]['checks']] == ['Right-angle condition', 'New case']


@pytest.mark.asyncio
async def test_prepared_catalog_workbook_is_reused_without_generation(state, monkeypatch):
    prepared = workbook(text=True)
    state.row.workbook_json = None
    state.row.generation_attempts = 3
    monkeypatch.setattr(api, '_canonical_workbook', AsyncMock(return_value=prepared))
    generate = AsyncMock(side_effect=AssertionError('canonical practice must not regenerate'))
    monkeypatch.setattr(api, 'generate_workbook', generate)
    result = await api.prepare_practice('item', 's1', state.db, state.user)
    assert result['state'] == 'ready'
    assert state.row.workbook_json == prepared.model_dump()
    assert state.row.generation_attempts == 3
    assert 'worked_solution' not in result['workbook']['activities'][0]
    assert 'expression' not in result['workbook']['activities'][0]['fields'][0]
    generate.assert_not_awaited()


@pytest.mark.asyncio
async def test_canonical_workbook_hash_and_version_are_required():
    from app.services.curriculum.hashing import sha256_json
    payload = workbook().model_dump(mode='json')
    item = SimpleNamespace(details_json={'catalog': {'module_version_id': 'version'}})
    db = AsyncMock()
    db.scalar.return_value = SimpleNamespace(content_json={'practice_workbook': payload, 'practice_workbook_hash': sha256_json(payload)})
    result = await api._canonical_workbook(db, item, {'catalog_session_id': 'session'})
    assert result == workbook()
    assert {'session', 'version'} <= set(db.scalar.call_args.args[0].compile().params.values())
    db.scalar.return_value.content_json['practice_workbook']['activities'][0]['data'][0]['value'] = 999
    with pytest.raises(HTTPException) as exc:
        await api._canonical_workbook(db, item, {'catalog_session_id': 'session'})
    assert exc.value.status_code == 409


@pytest.mark.asyncio
async def test_prepared_availability_does_not_expose_answers_or_write(state, monkeypatch):
    state.load.return_value = (state.item, state.step, None, state.version)
    monkeypatch.setattr(api, '_canonical_workbook', AsyncMock(return_value=workbook()))
    result = await api.get_practice('item', 's1', state.db, state.user)
    assert result == {'state': 'not_started', 'prepared_available': True}
    state.db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_practice_operational_recovery_records_both_attempts(monkeypatch):
    from app.services.practice import generation
    from app.services.llm import recovery
    from app.services.llm.client import LLMResponse
    primary = SimpleNamespace(generate_and_validate=AsyncMock(return_value=(
        None, LLMResponse(data={}, provider='openlux', error='timeout'))))
    result = workbook()
    secondary = SimpleNamespace(generate_and_validate=AsyncMock(return_value=(
        result, LLMResponse(data={}, provider='gemini', finish_reason='STOP'))))
    monkeypatch.setattr(generation, 'get_llm_client', lambda **kw: primary)
    monkeypatch.setattr(recovery, 'operational_recovery_client', lambda *a, **kw: secondary)
    recorder = AsyncMock()
    monkeypatch.setattr(generation, 'record_llm_response', recorder)
    assert await generation.generate_workbook({}, {}) == result
    assert recorder.await_count == 2
    assert primary.generate_and_validate.await_count == 1
    assert secondary.generate_and_validate.await_count == 1


@pytest.mark.asyncio
async def test_wrong_calculation_returns_immediate_feedback_without_model(state):
    state.row.answers_json['case_a.length'] = '7'
    result = await api.submit_practice('item', 's1', submission(), state.db, state.user)
    state.review.assert_not_awaited()
    assert not result['complete'] and result['passed_activity_ids'] == []
    feedback = result['attempts'][-1]['feedback']
    assert not feedback[0]['passed']
    assert feedback[1]['pending'] and not feedback[1]['passed']
    assert state.row.answers_json['case_a.reason'] == 'This is a right triangle.'
    state.row.answers_json['case_a.length'] = '5'
    corrected = await api.submit_practice('item', 's1', submission(revision=1, request='corrected_001'), state.db, state.user)
    assert state.review.await_count == 1
    assert corrected['passed_activity_ids'] == ['case_a']


@pytest.mark.asyncio
async def test_practice_scoped_outage_avoids_second_gateway_call(monkeypatch):
    from app.services.practice import generation
    from app.services.llm import recovery
    from app.services.llm.client import LLMResponse
    proof = object()
    primary = Mock(side_effect=AssertionError('The audited pilot must not call the gateway again'))
    native = SimpleNamespace(generate_and_validate=AsyncMock(return_value=(workbook(),
        LLMResponse(data={}, provider='gemini', finish_reason='STOP'))))
    monkeypatch.setattr(generation, 'get_llm_client', primary)
    monkeypatch.setattr(recovery, 'operational_recovery_client', lambda response, **kw: native if response is proof else None)
    monkeypatch.setattr(generation, 'record_llm_response', AsyncMock())
    result = await generation._structured('lesson_practice_generate.txt', {}, Workbook,
        'lesson_practice_review', recovery_response=proof)
    assert result == workbook()
    native.generate_and_validate.assert_awaited_once()
    primary.assert_not_called()


@pytest.mark.asyncio
async def test_practice_pilot_rejects_wrong_owner_and_expired_evidence(monkeypatch):
    from app.tasks import plans as tasks
    plan = SimpleNamespace(id='plan', user_id='user', roadmap_json={'operator_catalog_pilot_job_id': 'job'})
    job = SimpleNamespace(user_id='user', plan_id='plan')
    db = AsyncMock()
    db.get.side_effect = lambda model, key: plan if key == 'plan' else job
    check = AsyncMock(return_value=object())
    monkeypatch.setattr(tasks, '_validated_plan_recovery', check)
    item = SimpleNamespace(plan_id='plan')
    assert await api._practice_pilot_recovery(db, item, 'user') is check.return_value
    job.user_id = 'other'
    with pytest.raises(ValueError, match='does not belong'):
        await api._practice_pilot_recovery(db, item, 'user')
    job.user_id = 'user'
    check.return_value = None
    with pytest.raises(ValueError, match='expired'):
        await api._practice_pilot_recovery(db, item, 'user')
