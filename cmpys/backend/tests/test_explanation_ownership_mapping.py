"""One explicit, content-preserving ownership decision after a seed retry."""
import asyncio
import copy
import hashlib
import json
from collections import Counter
from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError

from app.services.llm.client import LLMResponse
from app.services.planning import package_builder as builder
from app.services.planning.activity_draft import (
    ExplanationOwnershipVerdict, LessonActivityDraft, explanation_ownership_candidate,
)
from tests.section_client_fixture import activity_draft_fixture
from tests.test_staged_package_builder import components, run


def misplaced(activity):
    value = activity_draft_fixture(activity)
    value["explanation"] = value["fields"][-1].pop("explanation")
    return value


def protocol_error():
    return LLMResponse(data={}, error="zai request failed (JSONProtocolError; details redacted)",
        finish_reason="stop", prompt_tokens=10, completion_tokens=20, total_tokens=30)


def approve(payload):
    return {"acceptable": True, "target_field_id": payload["candidate_target_field_id"],
            "source_sha256": payload["source_sha256"]}


class Factory:
    def __init__(self, responses, *, provider="zai"):
        self.responses = {key: list(values) for key, values in responses.items()}
        self.provider = provider
        self.requests, self.options = [], []
        self.counts = Counter()
        self.active = self.max_active = 0

    def __call__(self, **options):
        factory = self
        self.options.append(options)

        class Client:
            model = "glm-5.3"
            provider_name = factory.provider
            request_started = True
            last_attempt = None

            async def generate_json(self, **request):
                payload = json.loads(request["user_prompt"])
                key = ("seed" if request["output_model"] is builder.LessonPackageSeed else
                       "ownership" if request["output_model"] is ExplanationOwnershipVerdict else
                       payload["activity_brief"]["id"])
                factory.requests.append((key, request, payload))
                factory.counts[key] += 1
                factory.active += 1
                factory.max_active = max(factory.max_active, factory.active)
                self.last_attempt = LLMResponse(data={}, provider=factory.provider,
                    attempt_id=f"{key}-{factory.counts[key]}")
                try:
                    item = factory.responses[key].pop(0)
                    if callable(item):
                        item = item(payload)
                        if asyncio.iscoroutine(item):
                            item = await item
                    if isinstance(item, BaseException):
                        raise item
                    response = item if isinstance(item, LLMResponse) else LLMResponse(
                        data=copy.deepcopy(item), finish_reason="stop", provider=factory.provider,
                        prompt_tokens=10, completion_tokens=20, total_tokens=30)
                    response.attempt_id = self.last_attempt.attempt_id
                    self.last_attempt = response
                    return response
                finally:
                    factory.active -= 1

        return Client()


@pytest.fixture
def usage(monkeypatch):
    recorder = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", recorder)
    return recorder


def scenario(*, count=2, verdict=approve):
    seed, activities = components(count)
    drafts = {key: activity_draft_fixture(value) for key, value in activities.items()}
    drafts["transfer"] = misplaced(activities["transfer"])
    factory = Factory({"seed": [protocol_error(), seed],
        **{key: [draft] for key, draft in drafts.items()}, "ownership": [verdict]})
    return seed, activities, drafts, factory


@pytest.mark.asyncio
@pytest.mark.parametrize("count,reserve", [(2, 0), (2, 1024), (2, 2048), (2, 8192), (6, 2048)])
async def test_only_mapping_moves_exact_string_and_reports_honest_request_and_wire_envelopes(count, reserve, monkeypatch, usage):
    from app.core.config import settings
    monkeypatch.setattr(settings, "zai_reasoning_token_reserve", reserve)
    seed, activities, drafts, factory = scenario(count=count)
    drafts["transfer"]["explanation"] += "\n  Պահպանիր այս բացատրությունը։  "
    factory.responses["transfer"] = [copy.deepcopy(drafts["transfer"])]
    original = copy.deepcopy(drafts)
    snapshots = []

    async def save(value):
        snapshots.append(value)

    package, response, _ = await run(factory, on_parts=save)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 2, **{key: 1 for key in activities}, "ownership": 1}
    assert factory.max_active <= 2 and usage.await_count == count + 3
    assert factory.requests[-1][0] == "ownership"
    request = factory.requests[-1][2]
    assert request["rejected_activity"] == original["transfer"]
    assert request["source_sha256"] == hashlib.sha256(original["transfer"]["explanation"].encode()).hexdigest()
    assert drafts == original
    assert package.workbook.activities[-1].worked_solution.steps[-1].explanation.encode() == original["transfer"]["explanation"].encode()
    expected = copy.deepcopy(original["transfer"])
    expected["fields"][-1]["explanation"] = expected.pop("explanation")
    from app.services.planning.activity_draft import parse_activity_draft
    assert package.workbook.activities[-1].model_dump(mode="json") == parse_activity_draft(expected).model_dump(mode="json")
    assert [activity.id for activity in package.workbook.activities] == list(activities)
    assert len(snapshots) == count + 1
    assert all("transfer" not in state["activities"] for state in snapshots[:-1])
    assert all("explanation" not in activity for state in snapshots for activity in state["activities"].values())
    assert "preflight_passed" not in json.dumps(snapshots)
    metadata = response.effective_parameters
    requested = 2 * 2200 + count * 4000 + 1000
    old_requested = 2200 + count * 4000 + 4000
    old_wire = old_requested + (count + 2) * reserve
    assert metadata["max_component_requests"] == count + 3
    assert metadata["previous_max_component_requests"] == count + 2
    assert metadata["requested_output_tokens"] == requested
    assert metadata["output_token_budget"] == old_requested
    assert metadata["requested_combined_output_tokens"] == requested + (count + 3) * reserve
    assert metadata["previous_combined_output_token_budget"] == old_wire
    assert metadata["combined_output_token_budget"] == max(old_wire, requested + (count + 3) * reserve)
    assert metadata["combined_output_token_budget"] - old_wire == max(0, reserve - 800)
    assert metadata["stage_timeout_seconds"] == 240 and metadata["stage_timeout_basis"] == "provider_active_union"
    assert factory.options[-1] == dict(tier="balanced", timeout=90, max_tokens=1000,
                                      thinking_level="low", allow_fallback=False)
    assert all("rejected_activity" not in call.kwargs.get("metadata", {}) for call in usage.await_args_list)


@pytest.mark.parametrize("defect", ["earlier_field", "two_missing", "null_explanation", "empty_root",
    "whitespace_root", "long_root", "root_not_string", "extra_property", "missing_rubric", "empty_rubric",
    "missing_root", "already_owned", "invalid_field_id", "object_kind", "list_kind", "invalid_utf8"])
def test_only_exact_two_error_last_field_shape_is_candidate(defect):
    from tests.test_activity_draft import draft_payload
    draft = draft_payload()
    draft["explanation"] = draft["fields"][-1].pop("explanation")
    if defect == "earlier_field":
        draft["fields"][-1]["explanation"] = draft["explanation"]
        del draft["fields"][0]["explanation"]
    elif defect == "two_missing":
        del draft["fields"][0]["explanation"]
    elif defect == "null_explanation":
        draft["fields"][-1]["explanation"] = None
    elif defect == "empty_root":
        draft["explanation"] = ""
    elif defect == "whitespace_root":
        draft["explanation"] = " " * 40
    elif defect == "long_root":
        draft["explanation"] = "x" * 4001
    elif defect == "root_not_string":
        draft["explanation"] = {"text": draft["explanation"]}
    elif defect == "extra_property":
        draft["surprise"] = "untrusted"
    elif defect == "missing_rubric":
        del draft["fields"][-1]["criteria"]
    elif defect == "empty_rubric":
        draft["fields"][-1]["criteria"].append("")
    elif defect == "missing_root":
        del draft["explanation"]
    elif defect == "already_owned":
        draft["fields"][-1]["explanation"] = draft["explanation"]
    elif defect == "object_kind":
        draft["fields"][-1]["kind"] = {}
    elif defect == "list_kind":
        draft["fields"][-1]["kind"] = []
    elif defect == "invalid_utf8":
        draft["explanation"] += "\ud800"
    else:
        # Canonical-only errors are additionally checked by the caller's
        # validation preview before any mapping request (tested below).
        draft["fields"][-1]["id"] = "UPPERCASE_INVALID"
    original = copy.deepcopy(draft)
    assert explanation_ownership_candidate(draft) is None
    assert draft == original


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["decline", "wrong_hash", "wrong_target", "string_bool", "missing", "extra",
                                      "length", "transport", "protocol"])
async def test_mapping_refusal_or_bad_response_is_terminal_with_original_checkpoints(failure, usage):
    def verdict(payload):
        value = approve(payload)
        if failure == "decline":
            value.update(acceptable=False, target_field_id=None)
        elif failure == "wrong_hash":
            value["source_sha256"] = "0" * 64
        elif failure == "wrong_target":
            value["target_field_id"] = "another_field"
        elif failure == "string_bool":
            value["acceptable"] = "true"
        elif failure == "missing":
            del value["source_sha256"]
        elif failure == "extra":
            value["explanation"] = "A provider may not rewrite the original content."
        elif failure == "length":
            return LLMResponse(data=value, finish_reason="length")
        elif failure == "transport":
            return TimeoutError()
        elif failure == "protocol":
            return protocol_error()
        return value
    _, _, drafts, factory = scenario(verdict=verdict)
    original = copy.deepcopy(drafts["transfer"])
    snapshots = []

    async def save(value):
        snapshots.append(value)

    package, response, _ = await run(factory, on_parts=save)
    assert package is None and response.error
    assert factory.counts["ownership"] == 1 and sum(factory.counts.values()) == 5
    assert usage.await_count == 5
    assert set(snapshots[-1]["activities"]) == {"guided"}
    assert len(snapshots) == 2 and drafts["transfer"] == original
    assert response.data == {} and original["explanation"] not in json.dumps(response.effective_parameters)


@pytest.mark.asyncio
@pytest.mark.parametrize("defect", ["no_seed_retry", "activity_retry", "two_candidates", "other_activity_invalid",
                                   "wrong_assigned_id", "wrong_formula", "transfer_copy", "object_kind", "list_kind"])
async def test_no_mapping_without_all_eligibility_and_full_canonical_checks(defect, usage):
    seed, activities = components(numeric=defect in {"wrong_formula", "transfer_copy"})
    drafts = {key: activity_draft_fixture(value) for key, value in activities.items()}
    candidate = misplaced(activities["transfer"])
    responses = {"seed": [protocol_error(), seed], "guided": [drafts["guided"]], "transfer": [candidate]}
    if defect == "no_seed_retry":
        responses["seed"] = [seed]
        responses["transfer"].append(candidate)
    elif defect == "activity_retry":
        responses["seed"] = [seed]
        responses["guided"] = [{"invalid": True}, drafts["guided"]]
    elif defect == "two_candidates":
        responses["guided"] = [misplaced(activities["guided"])]
    elif defect == "other_activity_invalid":
        # Return the candidate first so the valid-looking mapping cannot be
        # started before the other activity's later failure is known.
        async def invalid(_):
            await asyncio.sleep(.005)
            return {"invalid": True}
        responses["guided"] = [invalid]
    elif defect == "wrong_assigned_id":
        candidate["id"] = "different_activity"
    elif defect == "wrong_formula":
        candidate["fields"][0]["expression"] = "unknown * 2"
    elif defect == "transfer_copy":
        candidate["data"][0]["value"] = 10
    else:
        candidate["fields"][-1]["kind"] = {} if defect == "object_kind" else []
    factory = Factory(responses)
    package, response, _ = await run(factory)
    assert package is None and response.error
    assert factory.counts["ownership"] == 0
    assert sum(factory.counts.values()) <= 4
    assert usage.await_count == sum(factory.counts.values())


@pytest.mark.asyncio
@pytest.mark.parametrize("external", [False, True])
async def test_mapping_stage_timeout_or_external_cancel_preserves_completed_work_and_bills_once(external, monkeypatch, usage):
    entered = asyncio.Event()

    async def blocked(_):
        entered.set()
        await asyncio.Event().wait()

    _, _, _, factory = scenario(verdict=blocked)
    snapshots = []

    async def save(value):
        snapshots.append(value)

    if not external:
        monkeypatch.setattr(builder, "_STAGE_SECONDS", .03)
    task = asyncio.create_task(run(factory, on_parts=save))
    await entered.wait()
    if external:
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    else:
        package, response, _ = await task
        assert package is None and "deadline" in response.error
    assert factory.active == 0 and factory.counts["ownership"] == 1
    assert usage.await_count == 5
    recorded = usage.await_args_list[-1].kwargs["response"]
    assert recorded.attempt_id == "ownership-1" and recorded.total_tokens is None
    assert set(snapshots[-1]["activities"]) == {"guided"}


def test_binding_rejects_a_changed_original_and_never_accepts_rewritten_output():
    _, activities = components()
    candidate = explanation_ownership_candidate(misplaced(activities["transfer"]))
    verdict = {"acceptable": True, "target_field_id": candidate.target_field_id,
               "source_sha256": candidate.source_sha256}
    candidate.draft["explanation"] += "Changed"
    with pytest.raises(ValueError):
        candidate.bind(verdict)
    assert set(ExplanationOwnershipVerdict.model_json_schema()["properties"]) == {
        "acceptable", "target_field_id", "source_sha256"}
    assert ExplanationOwnershipVerdict.model_json_schema()["additionalProperties"] is False


@pytest.mark.asyncio
async def test_saved_seed_does_not_restore_a_seed_retry_privilege(usage):
    from tests.test_staged_package_builder import snapshot
    seed, activities = components()
    candidate = misplaced(activities["transfer"])
    factory = Factory({"transfer": [candidate, candidate]})
    package, response, _ = await run(factory, existing_parts=snapshot(seed, {"guided": activities["guided"]}))
    assert package is None and response.error
    assert factory.counts == {"transfer": 2} and usage.await_count == 2
    assert "ownership_mapping_slot_reserved" not in response.effective_parameters


@pytest.mark.asyncio
@pytest.mark.parametrize("finish,error", [("length", None), ("stop", "zai request failed (JSONProtocolError; redacted)")])
async def test_partial_or_protocol_rejected_draft_never_becomes_a_mapping_candidate(finish, error, usage):
    _, _, drafts, factory = scenario()
    factory.responses["transfer"] = [LLMResponse(data=copy.deepcopy(drafts["transfer"]),
        finish_reason=finish, error=error)]
    package, response, _ = await run(factory)
    assert package is None and response.error and factory.counts["ownership"] == 0
    assert sum(factory.counts.values()) == 4 and usage.await_count == 4


@pytest.mark.asyncio
async def test_successful_mapping_still_receives_and_preserves_downstream_semantic_rejection(monkeypatch, usage):
    from app.services.planning import package_preflight
    from tests.test_package_split_preflight import Harness
    _, _, _, factory = scenario()
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    original = package.model_dump(mode="json")
    negative = {"acceptable": False, "issues": [{"target": "practice.transfer",
        "description": "The explanation does not justify this task's inference; clarify the reasoning before publication."}]}
    review = Harness(semantic=[negative])
    recorder = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", recorder)
    failures, reviewed, _ = await package_preflight.review_package(package, {}, {}, client_factory=review.factory)
    assert failures and reviewed.effective_parameters["validated_repair_targets"] == ["practice.transfer"]
    assert review.counts == {"semantic": 1} and recorder.await_count == 1
    assert package.model_dump(mode="json") == original


@pytest.mark.asyncio
async def test_mapping_checkpoint_conflict_propagates_without_repeating_any_call(usage):
    _, _, _, factory = scenario()
    saved = []

    async def save(value):
        if "transfer" in value["activities"]:
            raise ValueError("checkpoint superseded")
        saved.append(value)

    with pytest.raises(ValueError, match="checkpoint superseded"):
        await run(factory, on_parts=save)
    assert factory.counts["ownership"] == 1 and usage.await_count == 5
    assert set(saved[-1]["activities"]) == {"guided"}


def test_ownership_prompt_and_verdict_are_part_of_generation_identity():
    from pathlib import Path
    from app.services.planning.lesson_package import validation_identity
    from app.services.llm.prompt_loader import PROMPTS_DIR
    source = Path(builder.__file__).with_name("lesson_package.py").read_text()
    assert "lesson_explanation_ownership.txt" in source
    assert "ExplanationOwnershipVerdict.model_json_schema()" in source
    assert len(validation_identity()["prompt_hash"]) == 64
    prompt = (PROMPTS_DIR / "lesson_explanation_ownership.txt").read_text()
    assert "structural coincidence does not establish ownership" in prompt
    assert "acceptable to false" in prompt and "untrusted reference data" in prompt
