"""Offline bounded preflight, durable scopes and unchanged numeric gates."""
import asyncio
import copy
import json
import re
from collections import defaultdict, deque
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning import package_preflight as preflight
from tests.lesson_package_fixtures import package_payload


def package(count=2, *, second_claim=False, numeric=True):
    payload = package_payload()
    template = payload["workbook"]["activities"][0]
    activities = []
    for index in range(count):
        activity = copy.deepcopy(template)
        activity.update(id=f"a{index}", kind="transfer" if index == count - 1 else "practice",
                        minutes_min=15, minutes_max=20)
        if numeric:
            receipts, revenue = 120 + index * 10, 100
            activity["data"] = [{"id": "receipts", "label": "Receipts", "value": receipts},
                                {"id": "revenue", "label": "Revenue", "value": revenue}]
            activity["fields"] = [{"id": "difference", "kind": "number", "label": "Difference",
                                   "expression": "receipts - revenue"}]
            activity["worked_solution"] = f"Difference: {receipts - revenue}.\n"
            if second_claim:
                activity["worked_solution"] += f"Their total is {receipts + revenue}.\n"
            activity["worked_solution"] += "Explain why this comparison is supported by the supplied case facts."
        activities.append(activity)
    payload["workbook"]["activities"] = activities
    return LessonPackage.model_validate(payload)


def good_evidence(body):
    checks = []
    for key, text in body["numeric_spans"].items():
        owner = body["numeric_span_owners"][key]
        activity = next(value for value in body["package"]["workbook"]["activities"]
                        if "practice." + value["id"] == owner)
        values = {item["id"]: item["value"] for item in activity["data"]}
        total = "total" in text
        checks.append({"claim_ids": [key], "case_id": owner,
                       "expression": "receipts + revenue" if total else "receipts - revenue",
                       "claimed_result": values["receipts"] + values["revenue"] if total else values["receipts"] - values["revenue"]})
    return {"calculations": checks}


class Harness:
    def __init__(self, outcomes=None, semantic=None):
        self.outcomes = {key: deque(values) for key, values in (outcomes or {}).items()}
        self.semantic = deque(semantic or ["good"])
        self.requests, self.factories = [], []
        self.counts = defaultdict(int)
        self.active = self.max_active = 0
        self.gate, self.two_active = asyncio.Event(), asyncio.Event()

    def factory(self, **kwargs):
        self.factories.append(kwargs)
        harness = self

        class Client:
            model = "offline"
            provider_name = "dummy"
            request_started = True
            last_attempt = LLMResponse(data={}, attempt_id="stale", total_tokens=999)

            async def generate_json(self, **request):
                body = json.loads(request["user_prompt"])
                semantic = request["output_model"].__name__ == "PackageSemanticReview"
                owner = "semantic" if semantic else next(iter(body["numeric_span_owners"].values())).removeprefix("practice.")
                harness.counts[owner] += 1
                harness.requests.append((owner, request))
                attempt_id = "attempt-" + str(len(harness.requests))
                self.last_attempt = LLMResponse(data={}, attempt_id=attempt_id)
                source = harness.semantic if semantic else harness.outcomes.get(owner, deque())
                outcome = source.popleft() if source else "good"
                harness.active += 1
                harness.max_active = max(harness.max_active, harness.active)
                if harness.active == 2:
                    harness.two_active.set()
                try:
                    if outcome == "block":
                        await harness.gate.wait()
                    elif outcome == "negative":
                        await harness.two_active.wait()
                        await asyncio.sleep(0)
                    else:
                        await asyncio.sleep(.001)
                    if outcome == "pre_send":
                        self.request_started = False
                        raise TimeoutError
                    if isinstance(outcome, dict):
                        data = outcome
                    elif outcome in ("timeout", "permanent", "retry_after"):
                        response = LLMResponse(data={}, error="zai request failed (TimeoutError; offline)",
                            retryable=outcome != "permanent", retry_after_seconds=1 if outcome == "retry_after" else None,
                            attempt_id=attempt_id, prompt_tokens=10, completion_tokens=20, total_tokens=30)
                        self.last_attempt = response
                        return response
                    else:
                        data = {"acceptable": True, "issues": []} if semantic else good_evidence(body)
                        if outcome == "bad_math":
                            data["calculations"][0]["expression"] = "receipts + revenue"
                        elif outcome == "partial":
                            data["calculations"] = data["calculations"][:1]
                        elif outcome == "outside":
                            data["calculations"][0]["claim_ids"] = ["n999"]
                        elif outcome == "wrong_case":
                            data["calculations"][0]["case_id"] = "practice.unknown"
                        elif outcome == "malformed":
                            data = {"calculations": "not an array"}
                        elif outcome == "negative":
                            data = {"issues": ["The stated constraints contradict this independent task and require revision."]}
                    self.last_attempt = LLMResponse(data=data, attempt_id=attempt_id,
                        prompt_tokens=10, completion_tokens=20, total_tokens=30)
                    return self.last_attempt
                finally:
                    harness.active -= 1

        return Client()


@pytest.fixture(autouse=True)
def isolate(monkeypatch):
    record = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    monkeypatch.setattr(preflight, "validation_identity", lambda: {"contract": "offline-v1"})
    return record


async def run(harness, value=None, *, existing=None, context=None):
    snapshots = []

    async def save(state):
        snapshots.append(copy.deepcopy(state))

    result = await preflight.review_package(value or package(), {}, context or {},
        client_factory=harness.factory, existing_review=existing, on_review=save)
    return result, snapshots


@pytest.mark.asyncio
async def test_full_semantic_then_parallel_scopes_and_union_records_each_real_call_once(isolate):
    harness = Harness()
    (failures, response, client), snapshots = await run(harness)
    assert not failures and not response.error and response.data["acceptable"] and client is None
    assert harness.counts == {"semantic": 1, "a0": 1, "a1": 1}
    assert harness.max_active == 2 and isolate.await_count == 3
    assert {call.kwargs["response"].attempt_id for call in isolate.await_args_list} == {"attempt-1", "attempt-2", "attempt-3"}
    assert all(call.kwargs["response"].total_tokens == 30 for call in isolate.await_args_list)
    assert snapshots[0]["semantic"]["acceptable"] and snapshots[0]["scopes"] == {}
    assert len(snapshots[-1]["scopes"]) == 2
    assert response.effective_parameters["synthetic_local_validation"] is True
    semantic = json.loads(harness.requests[0][1]["user_prompt"])
    assert set(semantic) == {"outline", "context", "capabilities", "package", "numerical_evidence", "workload_contract"}
    for _, request in harness.requests[1:]:
        body = json.loads(request["user_prompt"])
        assert set(body["evidence_cases"]) == {"practice.a0", "practice.a1"}
        assert len(body["package"]["workbook"]["activities"]) == 2


@pytest.mark.asyncio
async def test_partial_failure_saves_good_scope_then_resume_calls_only_failed_activity(isolate):
    failed = Harness({"a1": ["bad_math", "bad_math"]})
    (failures, response, _), snapshots = await run(failed)
    # F18: exhausted evidence corrections are a repairable activity defect.
    assert failures and not response.error and failed.counts == {"semantic": 1, "a0": 1, "a1": 2}
    assert response.effective_parameters["validated_repair_targets"] == ["practice.a1"]
    saved = snapshots[-1]
    assert set(saved["scopes"]) == {"a0"} and saved["correction_used"]
    before = copy.deepcopy(saved)
    resumed = Harness()
    (failures, response, _), new = await run(resumed, existing=saved)
    assert not failures and not response.error and resumed.counts == {"a1": 1}
    assert new[-1]["scopes"]["a0"] == saved["scopes"]["a0"]
    assert saved == before and isolate.await_count == 5


@pytest.mark.asyncio
async def test_partial_scope_correction_keeps_prior_valid_proof_and_requests_only_missing_id():
    harness = Harness({"a0": ["partial", "good"]})
    (failures, response, _), snapshots = await run(harness, package(second_claim=True))
    assert not failures and not response.error
    requests = [json.loads(request["user_prompt"]) for owner, request in harness.requests if owner == "a0"]
    assert set(requests[0]["numeric_spans"]) == {"n1", "n2"}
    assert set(requests[1]["numeric_spans"]) == {"n2"}
    assert {key for check in snapshots[-1]["scopes"]["a0"]["evidence"]["calculations"] for key in check["claim_ids"]} == {"n1", "n2"}


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["bad_math", "outside", "wrong_case", "malformed"])
async def test_wrong_math_scope_binding_and_schema_never_become_approved(kind):
    """F18: exhausting the evidence corrections for one owner is a scoped,
    repairable defect on that activity (never "preflight unavailable"), named
    by span ids and error codes/paths only, never by source text."""
    harness = Harness({"a0": [kind, kind]})
    (failures, response, _), snapshots = await run(harness)
    assert failures and not response.data["acceptable"]
    assert response.error is None
    assert response.effective_parameters["validated_repair_targets"] == ["practice.a0"]
    (failure,) = failures
    assert failure.startswith("practice.a0: Numeric evidence for spans n1 ")
    assert "derived results as expressions" in failure
    for source_text in ("Receipts", "Difference", "receipts + revenue", "practice.unknown", "not an array"):
        assert source_text not in failure
    assert harness.counts["a0"] == 2
    saved = snapshots[-1]
    assert "a0" not in saved["scopes"] and saved["rejection"] is None
    diagnosis = saved["evidence_failures"]["a0"]
    assert diagnosis["claim_ids"] == ["n1"] and diagnosis["codes"]
    assert all(re.fullmatch(r"[a-z][a-z0-9_]*", code) for code in diagnosis["codes"])
    if kind == "malformed":
        assert "calculations" in diagnosis["paths"] and "list_type" in diagnosis["codes"]


@pytest.mark.asyncio
async def test_transport_exhaustion_of_an_evidence_scope_stays_unavailable():
    harness = Harness({"a0": ["timeout", "timeout"]})
    (failures, response, _), snapshots = await run(harness)
    assert response.error == preflight._UNAVAILABLE and failures == [preflight._UNAVAILABLE]
    assert "validated_repair_targets" not in response.effective_parameters
    assert snapshots[-1]["evidence_failures"] == {}


@pytest.mark.asyncio
@pytest.mark.parametrize("negative", [
    {"acceptable": False, "issues": [{"target": "practice.a0", "description": "The chosen formula contradicts the supplied task assumptions."}]},
    {"acceptable": True, "issues": [{"target": "practice.a0", "description": "The chosen formula contradicts the supplied task assumptions."}]},
    {"acceptable": False, "issues": [{"field": False, "message": "placeholder"}]},
    {"acceptable": False, "issues": []},
    {"acceptable": False, "issues": [{"target": "unknown", "description": "The chosen formula contradicts the supplied task assumptions."}]},
])
async def test_known_negative_is_terminal_and_cached_without_favorable_retry(negative):
    harness = Harness(semantic=[negative])
    (failures, response, _), snapshots = await run(harness)
    assert failures and not response.data["acceptable"] and harness.counts == {"semantic": 1}
    assert snapshots[-1]["rejection"] is not None
    repeated = Harness()
    (again, _, _), _ = await run(repeated, existing=snapshots[-1])
    assert again == failures and repeated.requests == []
    actionable = bool(negative["issues"]) and negative["issues"][0].get("target") == "practice.a0"
    assert bool(response.error) is not actionable


@pytest.mark.asyncio
async def test_one_shared_correction_is_atomic_for_six_concurrent_activity_failures(isolate):
    harness = Harness({"a0": ["bad_math", "good"], "a1": ["bad_math", "good"]})
    (failures, response, _), snapshots = await run(harness, package(6))
    # The owner left without the shared correction becomes a scoped defect.
    assert failures and not response.error
    assert len(response.effective_parameters["validated_repair_targets"]) == 1
    assert len(harness.requests) == 8 and harness.max_active == 2
    assert sum(harness.counts[key] == 2 for key in ("a0", "a1")) == 1
    assert isolate.await_count == 8
    assert len(snapshots[-1]["scopes"]) == 5 and snapshots[-1]["correction_used"]
    meta = response.effective_parameters
    assert meta["request_count"] == meta["max_requests"] == 8
    assert meta["requested_output_tokens"] == meta["output_token_budget"] == 16000


@pytest.mark.asyncio
async def test_semantic_retry_consumes_same_correction_as_numerical_scopes():
    harness = Harness({"a0": ["bad_math"]}, semantic=["timeout", "good"])
    (failures, response, _), snapshots = await run(harness)
    assert failures and not response.error
    assert response.effective_parameters["validated_repair_targets"] == ["practice.a0"]
    assert harness.counts == {"semantic": 2, "a0": 1, "a1": 1}
    assert snapshots[-1]["correction_used"]


@pytest.mark.asyncio
async def test_two_simultaneous_negatives_are_preserved_as_terminal_content_failures():
    harness = Harness({"a0": ["negative"], "a1": ["negative"]})
    (failures, response, _), snapshots = await run(harness)
    assert len(failures) == 2 and response.error is None
    assert {issue["target"] for issue in snapshots[-1]["rejection"]["issues"]} == {"practice.a0", "practice.a1"}
    assert not snapshots[-1]["correction_used"]
    assert len(harness.requests) == 3


@pytest.mark.asyncio
async def test_negative_cancels_blocked_sibling_and_records_unknown_attempt_once(isolate):
    harness = Harness({"a0": ["negative"], "a1": ["block"]})
    (failures, response, _), snapshots = await run(harness)
    assert failures and response.error is None and snapshots[-1]["rejection"]
    assert len(harness.requests) == isolate.await_count == 3
    records = [call.kwargs["response"] for call in isolate.await_args_list]
    assert len({record.attempt_id for record in records}) == 3
    assert sorted(record.total_tokens or 0 for record in records) == [0, 30, 30]


@pytest.mark.asyncio
async def test_known_negative_stops_all_queued_scopes_before_usage_finalization(isolate):
    async def delayed_record(**kwargs):
        if preflight._known_negative(kwargs["response"].data):
            await asyncio.sleep(.03)
        return True

    isolate.side_effect = delayed_record
    harness = Harness({"a0": ["negative"], "a1": ["block"]})
    (failures, response, _), snapshots = await run(harness, package(6))
    assert failures and response.error is None and snapshots[-1]["rejection"]
    assert harness.counts == {"semantic": 1, "a0": 1, "a1": 1}
    assert isolate.await_count == 3
    assert not snapshots[-1]["correction_used"]


@pytest.mark.asyncio
async def test_invalid_saved_math_is_revalidated_and_never_approved_or_mutated():
    (_, _, _), snapshots = await run(Harness())
    saved = copy.deepcopy(snapshots[-1])
    saved["scopes"]["a0"]["evidence"]["calculations"][0]["expression"] = "receipts + revenue"
    before = copy.deepcopy(saved)
    harness = Harness()
    (failures, response, _), _ = await run(harness, existing=saved)
    assert failures and response.error and harness.requests == [] and saved == before


@pytest.mark.asyncio
async def test_context_change_invalidates_cached_semantic_and_scopes():
    (_, _, _), snapshots = await run(Harness())
    harness = Harness()
    (failures, response, _), newer = await run(harness, existing=snapshots[-1], context={"goal": "Changed learner goal"})
    assert not failures and not response.error and len(harness.requests) == 3
    assert newer[-1]["identity_hash"] != snapshots[-1]["identity_hash"]


@pytest.mark.asyncio
async def test_timing_context_recovers_only_exact_inputs_and_preserves_negative():
    value = package()
    timing = [{"activity_id": "a0", "previous_minutes": [13, 18],
               "revised_minutes": [15, 20], "unchanged_task": True}]
    context = {"goal": "Study this skill", "activity_timing_changes": timing}
    negative = {"acceptable": False, "issues": [{"target": "practice.a0",
        "description": "The unchanged work does not justify these increased time estimates."}]}
    (_, _, _), snapshots = await run(Harness(semantic=[negative]), value, context=context)
    saved = copy.deepcopy(snapshots[-1])
    recovered = preflight.recover_preflight_context(saved, package=value, outline={}, context={"goal": "Study this skill"})
    assert recovered == context
    harness = Harness()
    (failures, response, _), _ = await run(harness, value, existing=saved, context=recovered)
    assert failures and not response.error and harness.requests == []
    for wrong in ({"goal": "Different skill"}, {"goal": "Study this skill", "activity_timing_changes": []}):
        assert preflight.recover_preflight_context(saved, package=value, outline={}, context=wrong) == wrong
    changed = copy.deepcopy(saved)
    changed["activity_timing_changes"][0]["unchanged_task"] = False
    assert preflight.recover_preflight_context(changed, package=value, outline={}, context={"goal": "Study this skill"}) == {"goal": "Study this skill"}
    assert snapshots[-1] == saved


@pytest.mark.asyncio
async def test_checkpoint_failure_propagates_without_paid_retry(isolate):
    harness = Harness()

    async def broken(_):
        raise ValueError("Storage compare-and-swap failed")

    with pytest.raises(ValueError, match="compare-and-swap"):
        await preflight.review_package(package(), {}, {}, client_factory=harness.factory, on_review=broken)
    assert len(harness.requests) == isolate.await_count == 1


@pytest.mark.asyncio
async def test_stage_deadline_cancels_only_started_calls_and_retains_fresh_unknown_usage(monkeypatch, isolate):
    monkeypatch.setattr(preflight, "STAGE_SECONDS", .03)
    harness = Harness({f"a{i}": ["block"] for i in range(6)})
    (failures, response, _), snapshots = await run(harness, package(6))
    assert failures and "deadline" in response.error
    assert len(harness.requests) == isolate.await_count == 3
    records = [call.kwargs["response"] for call in isolate.await_args_list]
    assert {value.attempt_id for value in records} == {"attempt-1", "attempt-2", "attempt-3"}
    assert sorted(value.total_tokens or 0 for value in records) == [0, 0, 30]
    assert all(value.total_tokens != 999 for value in records)
    assert snapshots[-1]["semantic"]["acceptable"] and not snapshots[-1]["scopes"]


@pytest.mark.asyncio
async def test_external_cancellation_propagates_and_bills_active_requests_once(isolate):
    harness = Harness({"a0": ["block"], "a1": ["block"]})
    pending = asyncio.create_task(run(harness))
    await asyncio.wait_for(harness.two_active.wait(), 1)
    pending.cancel()
    with pytest.raises(asyncio.CancelledError):
        await pending
    assert isolate.await_count == len(harness.requests) == 3


@pytest.mark.asyncio
@pytest.mark.parametrize("stage", ["semantic", "evidence"])
async def test_external_cancellation_preserves_received_negative_and_still_propagates(isolate, stage):
    recording, release = asyncio.Event(), asyncio.Event()

    async def hold_usage(**kwargs):
        if preflight._known_negative(kwargs["response"].data):
            recording.set()
            await release.wait()
        return True

    isolate.side_effect = hold_usage
    snapshots = []

    async def save(state):
        snapshots.append(copy.deepcopy(state))

    harness = (Harness(semantic=[{"acceptable": False, "issues": [{"target": "package",
        "description": "The supplied assumptions contradict the required independent learning objective."}]}])
        if stage == "semantic" else Harness({"a0": ["negative"], "a1": ["block"]}))
    pending = asyncio.create_task(preflight.review_package(package(), {}, {},
        client_factory=harness.factory, on_review=save))
    await asyncio.wait_for(recording.wait(), 1)
    pending.cancel()
    release.set()
    with pytest.raises(asyncio.CancelledError):
        await pending
    assert snapshots[-1]["rejection"]
    assert snapshots[-1]["semantic"]["acceptable"] is (stage == "evidence")
    assert len(harness.requests) == isolate.await_count == (1 if stage == "semantic" else 3)


@pytest.mark.asyncio
async def test_external_cancellation_during_internal_negative_drain_keeps_both_negatives(isolate):
    saving_second, release = asyncio.Event(), asyncio.Event()
    snapshots = []

    async def save(state):
        if state["rejection"] and len(state["rejection"]["issues"]) == 2:
            saving_second.set()
            await release.wait()
        snapshots.append(copy.deepcopy(state))

    harness = Harness({"a0": ["negative"], "a1": ["negative"]})
    pending = asyncio.create_task(preflight.review_package(package(), {}, {},
        client_factory=harness.factory, on_review=save))
    await asyncio.wait_for(saving_second.wait(), 1)
    await asyncio.sleep(.01)  # The first rejection has begun sibling draining.
    pending.cancel()
    release.set()
    with pytest.raises(asyncio.CancelledError):
        await pending
    assert len(snapshots[-1]["rejection"]["issues"]) == 2
    assert isolate.await_count == 3


@pytest.mark.asyncio
@pytest.mark.parametrize("negative", [False, True])
async def test_finalizer_timeout_never_hides_cancellation_or_starts_more_requests(monkeypatch, isolate, negative):
    monkeypatch.setattr(preflight, "FINALIZATION_SECONDS", .025)
    recording = asyncio.Event()

    async def stalled_usage(**kwargs):
        recording.set()
        await asyncio.Event().wait()

    isolate.side_effect = stalled_usage
    snapshots = []

    async def save(state):
        snapshots.append(copy.deepcopy(state))

    response = {"acceptable": False, "issues": [{"target": "package",
        "description": "The supplied assumptions contradict the required independent learning objective."}]}
    harness = Harness(semantic=[response] if negative else None)
    pending = asyncio.create_task(preflight.review_package(package(), {}, {},
        client_factory=harness.factory, on_review=save))
    await asyncio.wait_for(recording.wait(), 1)
    pending.cancel()
    with pytest.raises(asyncio.CancelledError):
        await asyncio.wait_for(pending, 1)
    assert len(harness.requests) == isolate.await_count == 1
    if negative:
        assert snapshots[-1]["rejection"] and not snapshots[-1]["semantic"]["acceptable"]
    else:
        assert snapshots == []


@pytest.mark.asyncio
async def test_pre_send_failure_has_no_usage_event(isolate):
    harness = Harness(semantic=["pre_send"])
    with pytest.raises(TimeoutError):
        await run(harness)
    assert isolate.await_count == 0


@pytest.mark.asyncio
async def test_exhausted_stage_returns_unavailable_without_starting_or_billing(monkeypatch, isolate):
    monkeypatch.setattr(preflight, "STAGE_SECONDS", 0)
    harness = Harness()
    (failures, response, _), _ = await run(harness)
    assert failures and response.error and not response.data["acceptable"]
    assert harness.requests == [] and isolate.await_count == 0


@pytest.mark.asyncio
async def test_retry_after_is_honored_inside_stage_budget():
    harness = Harness(semantic=["retry_after", "good"])
    started = asyncio.get_running_loop().time()
    (failures, response, _), _ = await run(harness)
    assert not failures and not response.error
    assert asyncio.get_running_loop().time() - started >= 1


@pytest.mark.asyncio
async def test_package_without_numeric_spans_needs_semantic_call_only():
    harness = Harness()
    (failures, response, _), snapshots = await run(harness, package(numeric=False))
    assert not failures and not response.error and harness.counts == {"semantic": 1}
    assert snapshots[-1]["scopes"] == {}


@pytest.mark.asyncio
async def test_union_cardinality_failure_is_controlled_and_never_approved():
    value = package()
    payload = preflight.package_review_payload(value, {}, {})
    responses = {}
    for owner in ("a0", "a1"):
        scoped = {**payload, "numeric_spans": {key: text for key, text in payload["numeric_spans"].items()
            if payload["numeric_span_owners"][key] == "practice." + owner}}
        evidence = good_evidence(scoped)
        evidence["calculations"] *= 40
        responses[owner] = [evidence]
    (failures, response, _), snapshots = await run(Harness(responses), value)
    assert failures and "canonical review contract" in response.error
    assert len(snapshots[-1]["scopes"]) == 2


@pytest.mark.asyncio
async def test_detailed_negative_remains_actionable_and_is_never_retried_favorably():
    description = "The field contradicts the shared case and must be corrected. " * 23
    assert 1200 < len(description) <= 2000
    harness = Harness(semantic=[{"acceptable": False, "issues": [{
        "target": "practice.a0", "description": description}]}])
    (failures, response, _), snapshots = await run(harness)
    assert failures and response.error is None and not response.data["acceptable"]
    assert response.effective_parameters["validated_repair_targets"] == ["practice.a0"]
    assert snapshots[-1]["rejection"]["issues"][0]["description"] == description
    assert harness.counts == {"semantic": 1}
    repeated = Harness()
    (again, _, _), _ = await run(repeated, existing=snapshots[-1])
    assert again == failures and not repeated.requests


def test_semantic_diagnostic_remains_bounded():
    from pydantic import ValidationError
    with pytest.raises(ValidationError):
        preflight.SemanticIssue(target="package", description="x" * 2001)


def restated_inputs_package():
    """a0 only restates its declared inputs; a1 also states a computed result."""
    value = package()
    raw = value.model_dump(mode="json")
    first = raw["workbook"]["activities"][0]
    first["worked_solution"] = ("Receipts were 120 and revenue was 100 in the supplied case. "
                                "Explain why this comparison is supported by the supplied case facts.")
    return LessonPackage.model_validate(raw)


@pytest.mark.asyncio
async def test_literal_input_spans_are_bound_in_code_without_an_evidence_call(isolate):
    harness = Harness()
    (failures, response, _), snapshots = await run(harness, restated_inputs_package())
    assert not failures and not response.error and response.data["acceptable"]
    # a0's spans are all declared inputs: no model evidence request for it.
    assert harness.counts == {"semantic": 1, "a1": 1}
    a0 = snapshots[-1]["scopes"]["a0"]["evidence"]
    assert a0["literal_facts"] and {fact["case_id"] for fact in a0["literal_facts"]} == {"practice.a0"}
    # a1 still asks the reviewer, and only about its computed span.
    a1_body = json.loads(next(request for owner, request in harness.requests if owner == "a1")["user_prompt"])
    assert all("practice.a1" == owner for owner in a1_body["numeric_span_owners"].values())
