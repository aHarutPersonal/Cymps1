"""A transfer replay gets one precise correction without changing its facts locally."""
import copy
import json
from unittest.mock import AsyncMock

import pytest

from app.services.planning import package_builder as builder
from app.services.planning.lesson_package import TeachingCase, TransferIndependenceError, validate_transfer_independence
from app.services.practice.contracts import Activity
from tests.section_client_fixture import activity_draft_fixture, structured_activity_fixture
from tests.test_staged_package_builder import Factory
from tests.test_transfer_independence import independent_transfer, payload, seed_for


def rejected_activity(data, *, unused=False):
    activity = copy.deepcopy(data["workbook"]["activities"][-1])
    if unused:
        activity["data"].append({"id": "unused", "label": "Unrelated amount", "value": 123,
                                 "unit": "credits"})
    return activity


@pytest.mark.parametrize("unused,reason", [
    (False, "complete_inputs_subset"), (True, "numeric_operands_subset"),
])
def test_replay_error_reports_only_safe_category_ordinal_and_counts(unused, reason):
    data = payload()
    rejected = rejected_activity(data, unused=unused)
    before = copy.deepcopy(rejected)
    original_case = TeachingCase.model_validate(data["teaching_cases"][0])
    unrelated_case = copy.deepcopy(data["teaching_cases"][0])
    unrelated_case["id"] = "unrelated"
    for datum in unrelated_case["data"]:
        datum["value"] += 1000
    cases = [TeachingCase.model_validate(unrelated_case), original_case]
    with pytest.raises(TransferIndependenceError) as raised:
        validate_transfer_independence(Activity.model_validate(rejected), cases)
    assert builder._diagnostics(raised.value) == [{
        "type": "transfer_independence", "reason": reason, "public_case_ordinal": 2,
        "overlapping_input_count": 3, "checked_input_count": 3, "public_input_count": 7,
    }]
    assert rejected == before
    encoded = json.dumps(builder._diagnostics(raised.value))
    assert all(datum["id"] not in encoded for datum in original_case.model_dump()["data"])
    assert "credits" not in encoded and "public_case" not in encoded.replace("public_case_ordinal", "")


def test_unrelated_contract_failure_cannot_trigger_transfer_rebuild():
    diagnostics = builder._diagnostics(ValueError("PRIVATE arbitrary provider expression"))
    assert diagnostics[0]["type"] == "component_contract"
    assert "PRIVATE" not in json.dumps(diagnostics)


@pytest.mark.asyncio
@pytest.mark.parametrize("unused", [False, True])
async def test_retry_payload_rebuilds_synthetic_transfer_only_and_preserves_inputs(monkeypatch, unused):
    record = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", record)
    data = payload()
    seed = seed_for(data)
    seed_before = copy.deepcopy(seed)
    bad = rejected_activity(data, unused=unused)
    bad["worked_solution"] = "PRIVATE_REJECTED_EXPLANATION supplied only to the bounded private correction."
    bad = structured_activity_fixture(bad)
    bad_before = copy.deepcopy(bad)
    good = structured_activity_fixture(independent_transfer(data))
    guided = structured_activity_fixture(data["workbook"]["activities"][0])
    factory = Factory({"seed": [seed], "guided": [guided], "transfer": [bad, good]})
    saved = []

    async def save(parts):
        saved.append(copy.deepcopy(parts))

    outline = {"title": "Apply the timing distinction", "required_skill": "Explain and reconcile"}
    context = {"locale": "hy", "user_constraints": "Retain the learner's actual work context"}
    package, response, _ = await builder.generate_initial_package(
        outline, context, client_factory=factory, on_parts=save)
    assert package is not None and response.error is None
    requests = [request[2] for request in factory.requests if request[0] == "transfer"]
    first, corrected = requests
    assert {key: value for key, value in corrected.items() if key != "correction"} == first
    assert corrected["outline"] == outline and corrected["context"] == context
    assert corrected["activity_brief"] == seed["activity_briefs"][-1]
    assert corrected["public_seed"] == first["public_seed"]
    correction = corrected["correction"]
    assert correction["validation_errors"][0]["reason"] == (
        "numeric_operands_subset" if unused else "complete_inputs_subset")
    instruction = correction["instruction"]
    assert "actual user-provided facts/constraints" in instruction
    assert "including values suggested in the activity brief" in instruction
    assert "unused new data" in instruction and "Recompute all dependent" in instruction
    assert "Preserve all required facts" not in instruction
    assert correction["rejected_component"] == activity_draft_fixture(bad)
    assert "untrusted reference data" in instruction
    assert "PRIVATE_REJECTED_EXPLANATION" not in json.dumps(response.effective_parameters)
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 2}
    assert response.effective_parameters["max_component_requests"] == 4
    assert response.effective_parameters["output_token_budget"] == 14200
    assert response.effective_parameters["shared_correction_used"] is True
    assert record.await_count == 4
    assert seed == seed_before and bad == bad_before
    assert saved[-1]["seed"] == builder.LessonPackageSeed.model_validate(seed).model_dump(mode="json")
    assert saved[-1]["activities"]["guided"] == Activity.model_validate(guided).model_dump(mode="json")
    assert saved[-1]["activities"]["transfer"] == Activity.model_validate(good).model_dump(mode="json")
    assert all("PRIVATE_REJECTED_EXPLANATION" not in json.dumps(parts) for parts in saved)


@pytest.mark.asyncio
@pytest.mark.parametrize("unused", [False, True])
async def test_repeated_replay_remains_terminal_without_an_extra_request(monkeypatch, unused):
    record = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", record)
    data = payload()
    bad = structured_activity_fixture(rejected_activity(data, unused=unused))
    factory = Factory({"seed": [seed_for(data)], "guided": [structured_activity_fixture(data["workbook"]["activities"][0])],
                       "transfer": [bad, copy.deepcopy(bad)]})
    saved = []

    async def save(parts):
        saved.append(copy.deepcopy(parts))

    package, response, _ = await builder.generate_initial_package({}, {}, client_factory=factory, on_parts=save)
    assert package is None and response.error and response.data == {}
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 2}
    assert record.await_count == 4
    assert all("transfer" not in parts["activities"] for parts in saved)
    assert set(saved[-1]["activities"]) == {"guided"}
