"""Offline regressions for scoped preflight proof correction, not provider quality."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import ReviewEvidencePatch
from app.services.planning.package_review import (
    PackageReview, _evidence_patch_request, package_review_payload, review_package,
)
from tests.lesson_package_fixtures import package_payload


def package_with_spans(*sentences):
    payload = package_payload()
    activity = payload["workbook"]["activities"][0]
    activity["data"] = [{"id": "receipts", "label": "Receipts", "value": 120},
                        {"id": "revenue", "label": "Revenue", "value": 100}]
    activity["worked_solution"] = "\n".join(sentences) + "\nExplain how the supplied inputs support this interpretation."
    return LessonPackage.model_validate(payload)


def check(span="n1", *, expression="receipts - revenue", result=20):
    return {"claim_ids": [span], "case_id": "practice.guided",
            "expression": expression, "claimed_result": result}


def approved(*checks, **extra):
    return {"acceptable": True, "issues": [], "contains_calculations": bool(checks),
            "calculations": list(checks), **extra}


@pytest.fixture(autouse=True)
def telemetry(monkeypatch):
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    return record


def client_for(*data):
    responses = [value if isinstance(value, LLMResponse) else LLMResponse(data=copy.deepcopy(value)) for value in data]
    client = SimpleNamespace(model="offline", generate_json=AsyncMock(side_effect=responses))
    return client, Mock(return_value=client), responses


@pytest.mark.asyncio
async def test_missing_proof_patch_retains_valid_calculation_and_original_semantic_verdict(telemetry):
    package = package_with_spans("Receipts exceed revenue by 20.", "Their total is 220.")
    initial = approved(check())
    replacement = check("n2", expression="receipts + revenue", result=220)
    client, factory, responses = client_for(initial, {"calculations": [replacement]})
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == [] and response is responses[1] and response.error is None
    assert response.data["acceptable"] is True and response.data["issues"] == []
    assert response.data["calculations"][0] == {**check(), "claimed_literal": None}
    first, second = [call.kwargs for call in client.generate_json.call_args_list]
    assert issubclass(first["output_model"], PackageReview) and issubclass(second["output_model"], ReviewEvidencePatch)
    payload = json.loads(second["user_prompt"])
    assert set(payload["numeric_spans"]) == {"n2"}
    assert payload["prior_evidence"]["calculations"] == []
    assert "Numeric verification coverage" in payload["verification_defects"][0]
    factory.assert_called_once_with(tier="balanced", timeout=60, max_tokens=2000,
                                    thinking_level="low", allow_fallback=False)
    assert client.generate_json.await_count == 2 and telemetry.await_count == 1
    assert telemetry.call_args.kwargs["response"] is responses[0]
    assert telemetry.call_args.kwargs["result_status"] == "evidence_failed"


@pytest.mark.asyncio
async def test_invented_teaching_id_is_explicitly_removed_without_value_based_remapping():
    package = package_with_spans("Receipts exceed revenue by 20.")
    fake = check("case_result_same_value")
    client, factory, _ = client_for(approved(check(), fake), {})
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert not failures and response.data["calculations"] == [{**check(), "claimed_literal": None}]
    patch_payload = json.loads(client.generate_json.call_args.kwargs["user_prompt"])
    assert patch_payload["numeric_spans"] == {}
    assert patch_payload["invalid_claim_ids"] == ["case_result_same_value"]
    assert patch_payload["prior_evidence"]["calculations"] == []


@pytest.mark.asyncio
@pytest.mark.parametrize("invented", [False, True])
async def test_grounded_wrong_arithmetic_cannot_be_erased_by_unrelated_missing_or_unknown_proof(invented):
    package = package_with_spans("120 - 100 = 30.", "Their total is 220.")
    bad = check(result=30)
    extras = [check("case_result_same_value")] if invented else []
    client, factory, _ = client_for(approved(bad, *extras))
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == ["n1: explicit source equation is incorrect (120 - 100 = 20, not 30)"]
    assert response.error is None and response.data["acceptable"] is False
    assert client.generate_json.await_count == 1


@pytest.mark.asyncio
async def test_wrong_arithmetic_survives_invented_companion_id_on_same_check():
    package = package_with_spans("120 - 100 = 30.")
    bad = check(result=30)
    bad["claim_ids"].append("invented_result")
    client, factory, _ = client_for(approved(bad))
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures and "= 20, not 30" in failures[0]
    assert response.error is None and client.generate_json.await_count == 1


@pytest.mark.asyncio
async def test_wrong_arithmetic_is_terminal_even_when_unknown_fact_forces_full_repair_scope():
    package = package_with_spans("120 - 100 = 30.")
    initial = approved(check(result=30), literal_facts=[
        {"claim_id": "fake_fact", "case_id": "practice.guided", "datum_ids": ["receipts"]}])
    client, factory, _ = client_for(initial)
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == ["n1: explicit source equation is incorrect (120 - 100 = 20, not 30)"]
    assert response.error is None and client.generate_json.await_count == 1


@pytest.mark.asyncio
async def test_unknown_fact_is_removed_without_regenerating_valid_proofs():
    package = package_with_spans("Receipts exceed revenue by 20.", "Their total is 220.")
    good_checks = [check(), check("n2", expression="receipts + revenue", result=220)]
    bad_fact = {"claim_id": "fake_fact", "case_id": "practice.guided", "datum_ids": ["receipts"]}
    client, factory, _ = client_for(approved(*good_checks, literal_facts=[bad_fact]), {})
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == [] and response.error is None
    assert response.data["calculations"] == [{**entry, "claimed_literal": None} for entry in good_checks]
    assert response.data["literal_facts"] == []
    payload = json.loads(client.generate_json.call_args.kwargs["user_prompt"])
    assert payload["numeric_spans"] == {} and payload["invalid_claim_ids"] == ["fake_fact"]
    assert payload["prior_evidence"]["calculations"] == []
    assert payload["prior_evidence"]["literal_facts"] == []


@pytest.mark.asyncio
async def test_partly_scoped_group_retains_proof_for_unaffected_id():
    package = package_with_spans("Receipts exceed revenue by 20.", "Their difference is 20 and total is 220.")
    grouped = check()
    grouped["claim_ids"] = ["n1", "n2"]
    patch_checks = [check("n2"), check("n2", expression="receipts + revenue", result=220)]
    client, factory, _ = client_for(approved(grouped), {"calculations": patch_checks})
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == [] and response.error is None
    assert response.data["calculations"][0] == {**check(), "claimed_literal": None}
    payload = json.loads(client.generate_json.call_args.kwargs["user_prompt"])
    assert set(payload["numeric_spans"]) == {"n2"}
    assert payload["prior_evidence"]["calculations"] == [check("n2")]


@pytest.mark.asyncio
@pytest.mark.parametrize("extra", [
    {"practice_minutes": 45}, {"affected_sections": ["worked_example"]},
    {"acceptable": True}, {"source": "replacement private prose"},
    {"literal_fact_ids": ["n999"]},
])
async def test_patch_cannot_change_workload_source_semantic_verdict_or_unsolicited_ids(extra):
    package = package_with_spans("Receipts exceed revenue by 20.")
    client, factory, _ = client_for(approved(), {"calculations": [check()], **extra})
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == ["Lesson package numerical evidence unavailable; contract must not be used"]
    assert response.error and client.generate_json.await_count == 2
    assert "replacement private prose" not in str(failures)


@pytest.mark.asyncio
async def test_patch_can_add_blocking_source_issue_without_rewriting_initial_verdict():
    package = package_with_spans("Receipts exceed revenue by 30.")
    client, factory, _ = client_for(approved(), {"package_issues": ["The stated difference contradicts the raw facts."]})
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == ["The stated difference contradicts the raw facts."]
    assert response.error is None and response.data["acceptable"] is False
    assert client.generate_json.await_count == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("reply", [
    {"calculations": [check(result=10)]},  # Undisplayed corrected answer.
    {"literal_facts": [{"claim_id": "n1", "case_id": "practice.guided", "datum_ids": ["revenue"]}]},
    {},  # Coverage is still mandatory after merge.
    LLMResponse(data={}, finish_reason="length"),
    LLMResponse(data={}, error="zai request failed (TimeoutError; private text)", retryable=True),
])
async def test_invalid_or_unavailable_patch_stops_after_second_call(reply, telemetry):
    package = package_with_spans("Receipts exceed revenue by 20.")
    client, factory, _ = client_for(approved(), reply)
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures and response.error and client.generate_json.await_count == 2
    assert "private text" not in str(failures)
    assert telemetry.await_count == 1


def test_complete_diagnostics_are_supplied_or_repair_is_declined_without_truncation():
    package = package_with_spans("Receipts exceed revenue by 20.")
    verdict = PackageReview.model_validate(approved())
    payload = package_review_payload(package, {}, {})
    errors = [f"n1: synthetic diagnostic {index}" for index in range(20)]
    request, _ = _evidence_patch_request(verdict, payload, errors)
    assert json.loads(request["user_prompt"])["verification_defects"] == errors
    assert _evidence_patch_request(verdict, payload, ["n1: " + "x" * 32_000]) is None


@pytest.mark.asyncio
async def test_initial_and_patch_prompts_distinguish_visible_claims_from_reference_values():
    package = package_with_spans("Receipts exceed revenue by 20.")
    client, factory, _ = client_for(approved(), {"calculations": [check()]})
    await review_package(package, {}, {}, client_factory=factory)
    first, second = [call.kwargs["system_prompt"] for call in client.generate_json.call_args_list]
    assert "ONLY the supplied numeric_spans" in first
    assert "never invent IDs for numerical_evidence" in first
    assert "EVERY cited result span" in first
    for prompt in (first, second):
        assert "A+B=C then D-C=E" in prompt
        assert "(120 > 100)" in prompt
        assert "exceeds by 20" in prompt
        assert "never" in prompt and "undisplayed" in prompt
