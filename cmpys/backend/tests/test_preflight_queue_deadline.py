"""Local admission waits cannot consume the private review's active budget."""
import asyncio
import copy
import json
from collections import Counter
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import PackageSemanticReview, review_package
from app.tasks.plans import PlanDetailDeadlineExceeded, _deadline_client_factory, settings
from tests.lesson_package_fixtures import package_payload


def numeric_package():
    data = package_payload()
    for activity, paid, unpaid in zip(data["workbook"]["activities"], (40, 70), (15, 20)):
        activity["data"] = [{"id": "paid", "label": "Paid expense", "value": paid},
                            {"id": "unpaid", "label": "Unpaid expense", "value": unpaid}]
        activity["fields"] = [{"id": "expense", "kind": "number", "label": "Total expense",
                                "expression": "paid + unpaid"}]
        activity["worked_solution"] = (
            f"Total expense is {paid + unpaid}. Include every expense incurred during this reporting period.")
    return LessonPackage.model_validate(data)


def answer(request):
    if issubclass(request["output_model"], PackageSemanticReview):
        data = {"acceptable": True, "issues": []}
    else:
        body = json.loads(request["user_prompt"])
        data = {"calculations": [{"claim_ids": [key], "case_id": body["numeric_span_owners"][key],
                  "expression": "paid + unpaid", "claimed_result": 55 if key == "n1" else 90}
                 for key in body["numeric_spans"]]}
    return LLMResponse(data=data, finish_reason="stop", prompt_tokens=10, completion_tokens=10)


@pytest.fixture
def local_limits(monkeypatch):
    # These are in-memory settings only. Every provider below is an offline fake.
    monkeypatch.setattr(settings, "llm_provider", "zai")
    monkeypatch.setattr(settings, "llm_admission_limits", {"zai:offline": 5})
    monkeypatch.setattr(settings, "llm_admission_per_user", 2)
    monkeypatch.setattr(settings, "llm_admission_foreground_reserve", 1)
    usage = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", usage)
    return usage


@pytest.mark.asyncio
async def test_three_lessons_waiting_in_shared_queue_keep_their_active_review_budget(monkeypatch, local_limits):
    monkeypatch.setattr("app.services.planning.package_preflight.STAGE_SECONDS", .15)
    monkeypatch.setattr("app.services.planning.package_preflight.REQUEST_SECONDS", .3)
    release = asyncio.Event()
    occupied = asyncio.Event()
    requested = asyncio.Event()
    counts = Counter()
    active = maximum = 0

    class Client:
        model = "offline-review"

        def __init__(self, holder=False):
            self.holder = holder

        async def generate_json(self, **request):
            nonlocal active, maximum
            active += 1
            maximum = max(maximum, active)
            counts["holders" if self.holder else "reviews"] += 1
            try:
                if self.holder:
                    if counts["holders"] == 2:
                        occupied.set()
                    await release.wait()
                    return LLMResponse(data={}, finish_reason="stop")
                return answer(request)
            finally:
                active -= 1

    def create(**kwargs):
        holder = kwargs.pop("holder", False)
        if not holder:
            counts["created_reviews"] += 1
            if counts["created_reviews"] == 3:
                requested.set()
        return Client(holder)

    factory = _deadline_client_factory(create, deadline=asyncio.get_running_loop().time() + 2)
    holders = [asyncio.create_task(factory(timeout=1, holder=True).generate_json()) for _ in range(2)]
    reviews = []
    try:
        await asyncio.wait_for(occupied.wait(), .5)
        package = numeric_package()
        reviews = [asyncio.create_task(review_package(package, {"id": f"lesson-{index}"}, {},
                       client_factory=factory)) for index in range(3)]
        await asyncio.wait_for(requested.wait(), .5)
        # The stage budget is intentionally exceeded solely in the local queue.
        # No review provider request has begun, so no active time was consumed.
        await asyncio.sleep(.22)
        assert counts["reviews"] == 0
        assert not any(task.done() for task in reviews)
        release.set()
        results = await asyncio.wait_for(asyncio.gather(*reviews), 1)
        assert all(not failures and response.error is None for failures, response, _ in results)
        assert counts["reviews"] == 9  # Three semantics and six independent activity scopes.
        assert maximum == 2 and active == 0
        assert local_limits.await_count == 9
        assert all(response.effective_parameters["request_count"] == 3 for _, response, _ in results)
        assert all(response.effective_parameters["stage_timeout_basis"] == "provider_active_union"
                   for _, response, _ in results)
    finally:
        release.set()
        for task in reviews + holders:
            if not task.done():
                task.cancel()
        await asyncio.gather(*reviews, *holders, return_exceptions=True)


@pytest.mark.asyncio
async def test_shared_outer_deadline_still_expires_unsent_review_in_local_queue(monkeypatch, local_limits):
    monkeypatch.setattr("app.services.planning.package_preflight.STAGE_SECONDS", 1)
    occupied = asyncio.Event()
    counts = Counter()

    class Client:
        model = "offline-review"

        def __init__(self, holder=False):
            self.holder = holder

        async def generate_json(self, **request):
            counts["holders" if self.holder else "reviews"] += 1
            if counts["holders"] == 2:
                occupied.set()
            try:
                await asyncio.Event().wait()
            finally:
                counts["cancelled"] += 1

    factory = _deadline_client_factory(lambda **kwargs: Client(kwargs.get("holder", False)),
        deadline=asyncio.get_running_loop().time() + .15)
    holders = [asyncio.create_task(factory(timeout=1, holder=True).generate_json()) for _ in range(2)]
    try:
        await asyncio.wait_for(occupied.wait(), .1)
        with pytest.raises(PlanDetailDeadlineExceeded):
            await asyncio.wait_for(review_package(numeric_package(), {}, {}, client_factory=factory), .5)
        assert counts["reviews"] == 0 and counts["holders"] == 2
        local_limits.assert_not_awaited()  # Queued, unsent calls cannot become paid records.
    finally:
        for task in holders:
            if not task.done():
                task.cancel()
        await asyncio.gather(*holders, return_exceptions=True)
    assert counts["cancelled"] == 2


@pytest.mark.asyncio
async def test_provider_request_timeout_and_single_shared_retry_remain_bounded(monkeypatch, local_limits):
    monkeypatch.setattr("app.services.planning.package_preflight.STAGE_SECONDS", .5)
    monkeypatch.setattr("app.services.planning.package_preflight.REQUEST_SECONDS", .025)
    counts = Counter()

    class Client:
        model = "offline-review"

        async def generate_json(self, **request):
            counts["started"] += 1
            try:
                await asyncio.Event().wait()
            finally:
                counts["cancelled"] += 1

    factory = _deadline_client_factory(lambda **kwargs: Client(),
        deadline=asyncio.get_running_loop().time() + 1)
    failures, response, _ = await asyncio.wait_for(
        review_package(numeric_package(), {}, {}, client_factory=factory), .4)
    assert failures and response.error
    assert counts == {"started": 2, "cancelled": 2}
    assert response.effective_parameters["shared_correction_used"] is True
    assert local_limits.await_count == 2


@pytest.mark.asyncio
async def test_caller_cancellation_cleans_active_request_and_records_one_unknown_attempt(monkeypatch, local_limits):
    monkeypatch.setattr("app.services.planning.package_preflight.STAGE_SECONDS", 1)
    entered = asyncio.Event()
    stopped = asyncio.Event()
    counts = Counter()

    class Client:
        model = "offline-review"

        async def generate_json(self, **request):
            counts["started"] += 1
            entered.set()
            try:
                await asyncio.Event().wait()
            finally:
                stopped.set()

    factory = _deadline_client_factory(lambda **kwargs: Client(),
        deadline=asyncio.get_running_loop().time() + 1)
    task = asyncio.create_task(review_package(numeric_package(), {}, {}, client_factory=factory))
    await asyncio.wait_for(entered.wait(), .3)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await asyncio.wait_for(task, .3)
    assert stopped.is_set() and counts["started"] == 1
    local_limits.assert_awaited_once()
    record = local_limits.await_args.kwargs
    assert record["result_status"] == "preflight_cancelled"
    assert record["response"].completion_tokens is None


@pytest.mark.asyncio
async def test_received_negative_stops_globally_queued_scope_before_usage_record_finishes(monkeypatch, local_limits):
    monkeypatch.setattr(settings, "llm_admission_per_user", 1)
    queued_created = asyncio.Event()
    queued_finished = asyncio.Event()
    negative_recording = asyncio.Event()
    release_recording = asyncio.Event()
    provider_operations = []
    wrapped_clients = []
    snapshots = []
    defect = "The supplied result contradicts the required scenario assumptions."

    async def record(**kwargs):
        if kwargs["response"].data.get("issues"):
            negative_recording.set()
            await release_recording.wait()
        return True

    local_limits.side_effect = record

    class Client:
        model = "offline-review"

        async def generate_json(self, **request):
            if issubclass(request["output_model"], PackageSemanticReview):
                provider_operations.append("semantic")
                return answer(request)
            body = json.loads(request["user_prompt"])
            owner = next(iter(body["numeric_span_owners"].values()))
            provider_operations.append(owner)
            if owner == "practice.guided":
                # The second scope must already be waiting on the real shared
                # semaphore when this provider returns its known negative.
                await queued_created.wait()
                return LLMResponse(data={"issues": [defect]}, finish_reason="stop",
                                   prompt_tokens=10, completion_tokens=10)
            return answer(request)

    shared_factory = _deadline_client_factory(lambda **kwargs: Client(),
        deadline=asyncio.get_running_loop().time() + 2)

    class ObservedClient:
        def __init__(self, wrapped, ordinal):
            self.wrapped, self.ordinal = wrapped, ordinal

        def __getattr__(self, key):
            return getattr(self.wrapped, key)

        async def generate_json(self, **request):
            try:
                return await self.wrapped.generate_json(**request)
            finally:
                if self.ordinal == 3:
                    queued_finished.set()

    def factory(**kwargs):
        wrapped = shared_factory(**kwargs)
        wrapped_clients.append(wrapped)
        if len(wrapped_clients) == 3:
            queued_created.set()
        return ObservedClient(wrapped, len(wrapped_clients))

    async def save(state):
        snapshots.append(copy.deepcopy(state))
        return True

    task = asyncio.create_task(review_package(numeric_package(), {}, {}, client_factory=factory, on_review=save))
    try:
        await asyncio.wait_for(negative_recording.wait(), .5)
        await asyncio.wait_for(queued_finished.wait(), .5)
        assert not task.done()  # The received negative's usage record is still pending.
        assert provider_operations == ["semantic", "practice.guided"]
        assert len(wrapped_clients) == 3 and wrapped_clients[2].request_started is False
        assert local_limits.await_count == 2  # No paid/cancelled record for the unsent scope.
        release_recording.set()
        failures, response, _ = await asyncio.wait_for(task, .5)
        assert response.error is None and response.data["acceptable"] is False
        assert failures == ["practice.guided: " + defect]
        assert response.effective_parameters["shared_correction_used"] is False
        assert snapshots[-1]["rejection"]["issues"] == [{"target": "practice.guided", "description": defect}]
        assert [call.kwargs["operation"] for call in local_limits.await_args_list] == [
            "package_preflight_semantic", "package_preflight_evidence_guided"]
    finally:
        release_recording.set()
        if not task.done():
            task.cancel()
        await asyncio.gather(task, return_exceptions=True)
