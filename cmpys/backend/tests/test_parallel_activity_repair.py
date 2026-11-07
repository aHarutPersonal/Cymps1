"""Independent repairs overlap without publishing partial or unreviewed packages."""
import asyncio
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning import lesson_package as module
from tests.section_client_fixture import activity_draft_fixture
from tests.test_scoped_activity_repair import structured_package


def drafts(package):
    result = {}
    for activity in package.workbook.activities:
        data = activity.model_dump(mode="json")
        data["instructions"] += " Explain how the changed evidence affects this conclusion."
        result[activity.id] = activity_draft_fixture(data)
    return result


class Harness:
    def __init__(self, package, *, failure=None, stale=False, queued=False):
        self.drafts = drafts(package)
        self.failure, self.stale, self.queued = failure, stale, queued
        self.started, self.cancelled = [], []
        self.both_started = asyncio.Event()
        self.release = asyncio.Event()
        self.responses = {}
        self.options = []
        self.active = self.peak = 0

    def factory(self, **options):
        self.options.append(options)
        harness = self

        class Client:
            model = "offline"
            request_started = False
            last_attempt = LLMResponse(data={}, attempt_id="old", prompt_tokens=999)

            async def generate_json(self, **request):
                key = json.loads(request["user_prompt"])["previous_activity"]["id"]
                harness.started.append(key)
                self.request_started = not (harness.queued and key == "transfer")
                if not harness.stale:
                    self.last_attempt = LLMResponse(data={}, attempt_id=key, prompt_tokens=20)
                harness.active += 1
                harness.peak = max(harness.peak, harness.active)
                if len(harness.started) >= 2:
                    harness.both_started.set()
                try:
                    await harness.release.wait()
                    if harness.failure and key == "transfer":
                        await asyncio.Event().wait()
                    response = LLMResponse(data=copy.deepcopy(harness.drafts[key]), attempt_id=key,
                                           prompt_tokens=20, completion_tokens=30)
                    if harness.failure == "malformed" and key == "guided":
                        response.data["id"] = "wrong"
                    if harness.failure == "transport" and key == "guided":
                        response.error = "Provider unavailable"
                    harness.responses[key] = response
                    return response
                except asyncio.CancelledError:
                    harness.cancelled.append(key)
                    raise
                finally:
                    harness.active -= 1

        return Client()


@pytest.fixture
def telemetry(monkeypatch):
    record = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    return record


async def start(harness, package):
    pending = asyncio.create_task(module._repair_public_activities(
        {}, {}, package, {activity.id: None for activity in package.workbook.activities},
        ["Independently rejected activity task"], client_factory=harness.factory))
    await asyncio.wait_for(harness.both_started.wait(), 2)
    return pending


@pytest.mark.asyncio
async def test_two_repairs_overlap_and_merge_atomically_in_original_order(telemetry):
    original = structured_package()
    snapshot = original.model_dump(mode="json")
    harness = Harness(original)
    pending = await start(harness, original)
    assert harness.peak == 2 and not pending.done()
    assert original.model_dump(mode="json") == snapshot
    harness.release.set()
    repaired, response, _ = await pending
    assert repaired is not None and not response.error
    assert response is harness.responses["transfer"]
    assert response.semantic_accepted is None  # Independent whole-package preflight remains required.
    assert original.model_dump(mode="json") == snapshot
    assert repaired.teaching_cases == original.teaching_cases
    assert repaired.workbook.title == original.workbook.title
    assert [row.id for row in repaired.workbook.activities] == ["guided", "transfer"]
    for old, new in zip(original.workbook.activities, repaired.workbook.activities):
        assert new.instructions != old.instructions and new.fields == old.fields
    assert telemetry.await_count == 1
    assert telemetry.await_args.kwargs["response"] is harness.responses["guided"]
    assert all(options == dict(tier="balanced", timeout=90, max_tokens=4000,
                              thinking_level="low", allow_fallback=False) for options in harness.options)


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["malformed", "transport"])
async def test_invalid_repair_cancels_sibling_and_returns_no_partial_package(telemetry, failure):
    original = structured_package()
    before = original.model_dump(mode="json")
    harness = Harness(original, failure=failure)
    pending = await start(harness, original)
    harness.release.set()
    repaired, response, _ = await asyncio.wait_for(pending, 2)
    assert repaired is None and response.error
    assert response is harness.responses["guided"]
    assert harness.cancelled == ["transfer"] and harness.active == 0
    assert original.model_dump(mode="json") == before
    records = [call.kwargs for call in telemetry.await_args_list]
    # A malformed correction is rejected once, recorded, and corrected once more.
    assert len(records) == (2 if failure == "malformed" else 1)
    cancelled = next(record for record in records if record["result_status"] == "component_cancelled")
    assert cancelled["response"].attempt_id == "transfer"
    assert cancelled["response"].prompt_tokens == 20
    if failure == "malformed":
        assert [record["result_status"] for record in records if record is not cancelled] == ["rejected"]


@pytest.mark.asyncio
@pytest.mark.parametrize("stale,queued,expected_records", [(False,False,2),(True,False,2),(False,True,1)])
async def test_caller_cancellation_drains_and_records_only_started_attempts(telemetry, stale, queued, expected_records):
    original = structured_package()
    harness = Harness(original, stale=stale, queued=queued)
    pending = await start(harness, original)
    pending.cancel()
    with pytest.raises(asyncio.CancelledError):
        await pending
    assert set(harness.cancelled) == {"guided", "transfer"} and harness.active == 0
    assert telemetry.await_count == expected_records
    if stale:
        for call in telemetry.await_args_list:
            assert call.kwargs["response"].attempt_id != "old"
            assert call.kwargs["response"].prompt_tokens is None


@pytest.mark.asyncio
async def test_at_most_two_chains_start_and_queued_sibling_stops_after_rejection(telemetry):
    data = structured_package().model_dump(mode="json")
    third = copy.deepcopy(data["workbook"]["activities"][1])
    third["id"] = "another_transfer"
    data["workbook"]["activities"].append(third)
    original = module.LessonPackage.model_validate(data)
    harness = Harness(original, failure="transport")
    pending = await start(harness, original)
    assert harness.peak == 2 and harness.started == ["guided", "transfer"]
    harness.release.set()
    repaired, response, _ = await pending
    assert repaired is None and response.error
    assert harness.started == ["guided", "transfer"]


@pytest.mark.asyncio
async def test_scope_review_precedes_its_draft_while_sibling_can_run(telemetry, monkeypatch):
    original = structured_package()
    replies = drafts(original)
    scope_started, sibling_started, release_scope = (asyncio.Event() for _ in range(3))
    events = []
    monkeypatch.setattr(module, "_needs_activity_scope_review",
                        lambda step, activity, fields: activity.id == "guided")

    async def decide(step, activity, field_ids, defects, *, client_factory):
        client = client_factory(tier="balanced", timeout=45, max_tokens=1000,
                                thinking_level="low", allow_fallback=False)
        response = await client.generate_json(output_model=module.ActivityRepairScopeReview,
                                               user_prompt="{}", system_prompt="scope")
        return module.ActivityRepairScopeReview.model_validate(response.data), response, client

    monkeypatch.setattr(module, "_review_activity_repair_scope", decide)

    async def generate(**request):
        if request["output_model"] is module.ActivityRepairScopeReview:
            events.append("scope_started"); scope_started.set()
            await release_scope.wait()
            events.append("scope_finished")
            return LLMResponse(data=dict(target="practice.guided", scope="activity",
                explanation="The independent decision allows correcting this entire activity."))
        key = json.loads(request["user_prompt"])["previous_activity"]["id"]
        events.append(key)
        if key == "transfer":
            sibling_started.set()
        return LLMResponse(data=replies[key])

    pending = asyncio.create_task(module._repair_public_activities(
        {}, {}, original, {"guided": {"argument"}, "transfer": None}, [],
        client_factory=lambda **kw: SimpleNamespace(generate_json=generate, model="offline")))
    await asyncio.wait_for(scope_started.wait(), 2)
    await asyncio.wait_for(sibling_started.wait(), 2)
    assert "guided" not in events
    release_scope.set()
    repaired, response, _ = await pending
    assert repaired is not None and not response.error
    assert events.index("scope_finished") < events.index("guided")
    assert telemetry.await_count == 2
    assert {call.kwargs["operation"] for call in telemetry.await_args_list} == {
        "lesson_package_activity_scope_review", "lesson_package_scoped_activity_repair"}


@pytest.mark.asyncio
@pytest.mark.parametrize("malicious", [False, True])
async def test_concurrent_field_scopes_preserve_all_unowned_content(telemetry, malicious):
    original = structured_package()
    before = original.model_dump(mode="json")
    started, release = asyncio.Event(), asyncio.Event()
    requests = []

    async def generate(**request):
        body = json.loads(request["user_prompt"])
        key = body["previous_activity"]["id"]
        requests.append(key)
        if len(requests) == 2:
            started.set()
        await release.wait()
        activity = next(row for row in original.workbook.activities if row.id == key)
        replacement = activity.model_dump(mode="json")
        replacement["fields"][0]["label"] += " with evidence"
        if malicious and key == "transfer":
            replacement["fields"][1]["label"] += " unowned change"
        return LLMResponse(data=activity_draft_fixture(replacement))

    pending = asyncio.create_task(module._repair_public_activities(
        {}, {}, original, {row.id: {row.fields[0].id} for row in original.workbook.activities}, [],
        client_factory=lambda **kw: SimpleNamespace(generate_json=generate, model="offline")))
    await asyncio.wait_for(started.wait(), 2)
    release.set()
    corrected, response, _ = await pending
    assert original.model_dump(mode="json") == before
    if malicious:
        assert corrected is None and response.error
    else:
        assert corrected is not None and not response.error
        for previous, current in zip(original.workbook.activities, corrected.workbook.activities):
            assert current.fields[0].label != previous.fields[0].label
            assert current.fields[1:] == previous.fields[1:]
            assert current.instructions == previous.instructions
            assert current.title == previous.title
            assert current.data == previous.data
            assert current.worked_solution == previous.worked_solution


@pytest.mark.asyncio
async def test_stalled_telemetry_has_one_bounded_finalization_budget(monkeypatch):
    monkeypatch.setattr(module, "_ACTIVITY_REPAIR_FINALIZATION_SECONDS", 0.02)
    async def hang(**kwargs):
        await asyncio.Event().wait()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", hang)
    original = structured_package()
    harness = Harness(original)
    pending = await start(harness, original)
    harness.release.set()
    corrected, response, _ = await asyncio.wait_for(pending, 0.5)
    assert corrected is not None and not response.error
    assert response.effective_parameters["usage_records_incomplete"] == 1
    assert harness.active == 0


@pytest.mark.asyncio
async def test_cancellation_during_finalization_accounts_the_no_longer_returned_response(monkeypatch):
    original = structured_package()
    harness = Harness(original)
    recording, release_record = asyncio.Event(), asyncio.Event()
    captured = []
    async def record(**kwargs):
        recording.set()
        await release_record.wait()
        captured.append(kwargs["response"].attempt_id)
        return True
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    pending = await start(harness, original)
    harness.release.set()
    await asyncio.wait_for(recording.wait(), 2)
    pending.cancel()
    await asyncio.sleep(0)
    pending.cancel()  # Repeated cancellation cannot abandon usage finalization.
    release_record.set()
    with pytest.raises(asyncio.CancelledError):
        await pending
    assert sorted(captured) == ["guided", "transfer"]


@pytest.mark.asyncio
async def test_scope_finishing_after_sibling_rejection_preserves_rejection(telemetry, monkeypatch):
    original = structured_package()
    scope_started = asyncio.Event()
    events = []
    rejection = LLMResponse(data={}, error="Original independent activity rejection", attempt_id="guided")
    scope_response = LLMResponse(data=dict(target="practice.transfer", scope="activity",
        explanation="This independent correction requires activity scope."), attempt_id="scope")
    monkeypatch.setattr(module, "_needs_activity_scope_review",
                        lambda step, activity, fields: activity.id == "transfer")

    async def decide(step, activity, field_ids, defects, *, client_factory):
        client = client_factory(tier="balanced", timeout=45, max_tokens=1000,
                                thinking_level="low", allow_fallback=False)
        response = await client.generate_json(output_model=module.ActivityRepairScopeReview,
                                               user_prompt="{}", system_prompt="scope")
        return module.ActivityRepairScopeReview.model_validate(response.data), response, client
    monkeypatch.setattr(module, "_review_activity_repair_scope", decide)

    async def generate(**request):
        if request["output_model"] is module.ActivityRepairScopeReview:
            events.append("scope")
            scope_started.set()
            await asyncio.sleep(0)  # Let the first activity reject before scope finishes.
            return scope_response
        key = json.loads(request["user_prompt"])["previous_activity"]["id"]
        events.append(key)
        assert key == "guided", "A stopped sibling must not start another provider request"
        await scope_started.wait()
        return rejection

    corrected, response, _ = await module._repair_public_activities(
        {}, {}, original, {"guided": None, "transfer": {"argument"}}, [],
        client_factory=lambda **kw: SimpleNamespace(generate_json=generate, model="offline"))
    assert corrected is None and response is rejection
    assert events == ["guided", "scope"]
    assert telemetry.await_count == 1
    assert telemetry.await_args.kwargs["response"] is scope_response
