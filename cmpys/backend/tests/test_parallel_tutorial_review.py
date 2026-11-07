"""Scheduling tests: synthetic approvals do not establish real content quality."""
import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.core.config import settings
from app.services.llm.client import LLMResponse
from app.services.planning import lesson_review as review
from tests.test_public_section_review import _conflict, _focused_review, _response


@pytest.fixture
def setup(monkeypatch):
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    captured = _conflict()
    return captured["lesson"], captured["context"], record


def client_factory(lesson, context, *, before_return=None):
    data = _focused_review(lesson, context)
    calls = []

    async def generate(**kwargs):
        alignment = kwargs["output_model"] is review.AlignmentOnlyReview
        name = "alignment" if alignment else "public"
        calls.append(name)
        if before_return:
            await before_return(name)
        key = "practice_alignment" if alignment else "public_sections"
        return LLMResponse(data={key: data[key]}, finish_reason="stop", prompt_tokens=17,
                           completion_tokens=23)

    client = SimpleNamespace(model="offline", generate_json=generate)
    return lambda **kwargs: client, calls


@pytest.mark.asyncio
async def test_full_public_and_alignment_overlap_but_every_verdict_is_required(setup, monkeypatch):
    lesson, context, record = setup
    started, release = set(), asyncio.Event()
    async def enter(name):
        started.add(name)
        if len(started) == 3:
            release.set()
        await asyncio.wait_for(release.wait(), 1)
    factory, calls = client_factory(lesson, context, before_return=enter)
    full = _response(lesson)
    async def full_review(*args, **kwargs):
        await enter("full")
        return [], full, SimpleNamespace(model="full")
    monkeypatch.setattr(review, "_review_lesson_full", full_review)
    failures, returned, _ = await review.review_lesson(lesson, client_factory=factory, context=context)
    assert not failures and not returned.error and returned is full
    assert started == {"full", "public", "alignment"}
    assert sorted(calls) == ["alignment", "public"]
    assert record.await_count == 2
    assert {c.kwargs["result_status"] for c in record.await_args_list} == {"approved"}


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["rejection", "unavailable", "exception", "cancel"])
async def test_full_failure_cancels_and_drains_critics_without_losing_unknown_usage(setup, monkeypatch, kind):
    lesson, context, record = setup
    started, entered, cancelled = set(), asyncio.Event(), set()
    async def hold(name):
        started.add(name)
        if len(started) == 2:
            entered.set()
        try:
            await asyncio.Event().wait()
        finally:
            cancelled.add(name)
    factory, calls = client_factory(lesson, context, before_return=hold)
    full = _response(lesson, acceptable=False, issues=["Full reviewer rejects this lesson"])
    if kind == "unavailable":
        full.error = "full review unavailable"
    async def full_review(*args, **kwargs):
        await entered.wait()
        if kind == "exception":
            raise RuntimeError("full review failed")
        if kind == "cancel":
            await asyncio.Event().wait()
        return ["Full reviewer rejects this lesson"], full, None
    monkeypatch.setattr(review, "_review_lesson_full", full_review)
    task = asyncio.create_task(review.review_lesson(lesson, client_factory=factory, context=context))
    await asyncio.wait_for(entered.wait(), 1)
    if kind == "cancel":
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    elif kind == "exception":
        with pytest.raises(RuntimeError, match="full review failed"):
            await task
    else:
        failures, returned, _ = await task
        assert failures == ["Full reviewer rejects this lesson"] and returned is full
    assert cancelled == {"public", "alignment"}
    assert sorted(calls) == ["alignment", "public"]
    assert record.await_count == 2
    for call in record.await_args_list:
        assert call.kwargs["result_status"] == "review_cancelled"
        assert call.kwargs["response"].total_tokens is None
        assert "unknown" in call.kwargs["response"].error


@pytest.mark.asyncio
async def test_completed_critic_accounting_finishes_once_when_full_review_rejects(setup, monkeypatch):
    lesson, context, _ = setup
    recording, release, finished = asyncio.Event(), asyncio.Event(), []
    async def record(**kwargs):
        recording.set()
        await release.wait()
        finished.append(kwargs)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    factory, _ = client_factory(lesson, context)
    full = _response(lesson, acceptable=False, issues=["Rejected"])
    async def full_review(*args, **kwargs):
        await recording.wait()
        return ["Rejected"], full, None
    monkeypatch.setattr(review, "_review_lesson_full", full_review)
    task = asyncio.create_task(review.review_lesson(lesson, client_factory=factory, context=context))
    await asyncio.wait_for(recording.wait(), 1)
    await asyncio.sleep(0)
    assert not task.done()
    release.set()
    failures, returned, _ = await asyncio.wait_for(task, 1)
    assert failures == ["Rejected"] and returned is full
    assert len(finished) == 2
    assert len({item["operation"] for item in finished}) == 2
    assert all(item["response"].prompt_tokens == 17 for item in finished)


@pytest.mark.asyncio
async def test_full_rejection_keeps_precedence_over_completed_critic_exception(setup, monkeypatch):
    lesson, context, _ = setup
    raised = asyncio.Event()
    async def generate(**kwargs):
        raised.set()
        raise TimeoutError("focused timeout")
    full = _response(lesson, acceptable=False, issues=["Full rejection"])
    async def full_review(*args, **kwargs):
        await raised.wait()
        await asyncio.sleep(0)
        return ["Full rejection"], full, None
    monkeypatch.setattr(review, "_review_lesson_full", full_review)
    failures, returned, _ = await review.review_lesson(lesson,
        client_factory=lambda **kw: SimpleNamespace(generate_json=generate), context=context)
    assert failures == ["Full rejection"] and returned is full


@pytest.mark.asyncio
@pytest.mark.parametrize("defect", ["malformed", "timeout", "truncated", "rejected"])
async def test_overlapped_critic_failure_never_publishes(setup, monkeypatch, defect):
    lesson, context, record = setup
    data = _focused_review(lesson, context)
    full = _response(lesson)
    monkeypatch.setattr(review, "_review_lesson_full", AsyncMock(return_value=([], full, None)))
    async def generate(**kwargs):
        key = "practice_alignment" if kwargs["output_model"] is review.AlignmentOnlyReview else "public_sections"
        response = LLMResponse(data={key: data[key]}, finish_reason="stop")
        if key == "public_sections":
            if defect == "malformed": response.data = {}
            elif defect == "timeout": response.error = "request timed out"
            elif defect == "truncated": response.finish_reason = "length"
            else: response.data[key][0].update(domain_valid=False, reason="Rejected teaching")
        return response
    failures, returned, _ = await review.review_lesson(lesson,
        client_factory=lambda **kw: SimpleNamespace(generate_json=generate), context=context)
    assert failures
    assert returned.error or returned.data["acceptable"] is False
    assert record.await_count == 2


@pytest.mark.asyncio
async def test_cancelled_unsent_critic_does_not_record_billable_usage(setup):
    lesson, context, record = setup
    entered = asyncio.Event()
    async def generate(**kwargs):
        entered.set()
        await asyncio.Event().wait()
    client = SimpleNamespace(request_started=False, generate_json=generate)
    task = asyncio.create_task(review._focused_accuracy_call(client_factory=lambda **kw: client,
        payload=review._public_teaching_payload(lesson, context), alignment=False))
    await entered.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    record.assert_not_awaited()


@pytest.mark.asyncio
async def test_cancelled_sent_critic_retains_partial_usage(setup):
    lesson, context, record = setup
    entered = asyncio.Event()
    partial = LLMResponse(data={}, prompt_tokens=51, completion_tokens=9, attempt_id="partial-attempt")
    async def generate(**kwargs):
        client.last_attempt = partial
        entered.set()
        await asyncio.Event().wait()
    client = SimpleNamespace(request_started=True, last_attempt=None, generate_json=generate)
    task = asyncio.create_task(review._focused_accuracy_call(client_factory=lambda **kw: client,
        payload=review._public_teaching_payload(lesson, context), alignment=False))
    await entered.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    response = record.await_args.kwargs["response"]
    assert response.prompt_tokens == 51 and response.completion_tokens == 9
    assert response.attempt_id == "partial-attempt" and partial.error is None
    record.assert_awaited_once()


@pytest.mark.asyncio
async def test_stalled_usage_finalization_is_bounded_and_drained(setup, monkeypatch):
    lesson, context, _ = setup
    monkeypatch.setattr(review, "_FOCUSED_FINALIZATION_SECONDS", .02)
    recording, drained = asyncio.Event(), []
    async def record(**kwargs):
        recording.set()
        try:
            await asyncio.Event().wait()
        finally:
            drained.append(kwargs["operation"])
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    factory, _ = client_factory(lesson, context)
    full = _response(lesson, acceptable=False, issues=["Rejected"])
    async def full_review(*args, **kwargs):
        await recording.wait()
        return ["Rejected"], full, None
    monkeypatch.setattr(review, "_review_lesson_full", full_review)
    async with asyncio.timeout(1):
        failures, returned, _ = await review.review_lesson(lesson, client_factory=factory, context=context)
    assert failures == ["Rejected"] and returned is full
    assert len(drained) == 2 and len(set(drained)) == 2


@pytest.mark.asyncio
async def test_cancelled_retry_never_reuses_previous_attempt_usage_or_identity(setup):
    lesson, context, record = setup
    entered = asyncio.Event()
    first = LLMResponse(data={}, error="transient", error_code="generation_failed", retryable=True,
        transport_success=False, prompt_tokens=31, completion_tokens=3, attempt_id="first-bill")
    calls = 0
    async def generate(**kwargs):
        nonlocal calls
        calls += 1
        if calls == 1:
            client.last_attempt = first
            return first
        # Cancellation before the adapter installs the retry's last_attempt.
        entered.set()
        await asyncio.Event().wait()
    client = SimpleNamespace(request_started=True, last_attempt=None, generate_json=generate)
    task = asyncio.create_task(review._focused_accuracy_call(client_factory=lambda **kw: client,
        payload=review._public_teaching_payload(lesson, context), alignment=False))
    await entered.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    records = [call.kwargs for call in record.await_args_list]
    assert len(records) == 2
    assert records[0]["response"] is first and records[0]["response"].attempt_id == "first-bill"
    cancelled = records[1]["response"]
    assert cancelled.attempt_id is None and cancelled.prompt_tokens is None
    assert cancelled.completion_tokens is None and "unknown" in cancelled.error
