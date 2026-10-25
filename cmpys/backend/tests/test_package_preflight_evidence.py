"""Verify private assertions before spending on lesson prose; no live calls."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_review import PackageReview, package_review_payload, review_package
from tests.lesson_package_fixtures import package_payload


def numeric_package(*, claimed=30, language="en", extra_sum=False):
    payload = package_payload()
    activity = payload["workbook"]["activities"][0]
    activity["data"] = [
        {"id": "cash_receipts", "label": "Cash receipts", "value": 110},
        {"id": "current_revenue", "label": "Current revenue", "value": 100},
        {"id": "prior_receipts", "label": "Prior receipts", "value": 30},
    ]
    activity["worked_solution"] = (
        f"Cash receipts (110) exceed current revenue (100) by {claimed}"
        if language == "en" else
        f"Դրամական մուտքը (110) գերազանցում է ընթացիկ հասույթը (100) {claimed} դրամով"
    ) + (", and their total is 210." if extra_sum else ".")
    return LessonPackage.model_validate(payload)


def evidence(*, claimed=10, extra_sum=False):
    checks = [{"claim_ids": ["n1"], "case_id": "practice.guided",
               "expression": "cash_receipts - current_revenue", "claimed_result": claimed}]
    if extra_sum:
        checks.append({"claim_ids": ["n1"], "case_id": "practice.guided",
                       "expression": "cash_receipts + current_revenue", "claimed_result": 210})
    return {"acceptable": True, "issues": [], "contains_calculations": True,
            "calculations": checks}


@pytest.fixture(autouse=True)
def telemetry(monkeypatch):
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    return record


def client_for(*verdicts):
    responses = [LLMResponse(data=copy.deepcopy(data)) for data in verdicts]
    client = SimpleNamespace(model="synthetic-preflight", generate_json=AsyncMock(side_effect=responses))
    return client, Mock(return_value=client), responses


@pytest.mark.asyncio
@pytest.mark.parametrize("language", ["en", "hy"])
@pytest.mark.parametrize("extra_sum", [False, True])
async def test_private_raw_value_collision_remains_rejected_after_semantic_evidence_correction(language, extra_sum, telemetry):
    package = numeric_package(language=language, extra_sum=extra_sum)
    before = package.model_dump(mode="json")
    issue = "The comparison confuses prior receipts with the current-period difference."
    client, factory, responses = client_for(evidence(claimed=30, extra_sum=extra_sum),
                                          {"package_issues": [issue]})
    failures, actual, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == [issue]
    assert actual is responses[1] and actual.error is None
    assert actual.data["acceptable"] is False and actual.data["issues"] == failures
    assert client.generate_json.await_count == 2
    assert package.model_dump(mode="json") == before
    assert telemetry.await_count == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("language", ["en", "hy"])
@pytest.mark.parametrize("extra_sum", [False, True])
async def test_exact_private_comparison_is_approved_with_bound_proof(language, extra_sum, telemetry):
    package = numeric_package(claimed=10, language=language, extra_sum=extra_sum)
    client, factory, responses = client_for(evidence(extra_sum=extra_sum))
    failures, actual, _ = await review_package(package, {}, {}, client_factory=factory)
    assert not failures and actual is responses[0] and actual.error is None
    assert client.generate_json.await_count == 1
    telemetry.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("language", ["en", "hy"])
@pytest.mark.parametrize("with_sum", [False, True])
async def test_false_comparison_cannot_hide_as_raw_fact_or_under_another_valid_check(language, with_sum, telemetry):
    package = numeric_package(language=language, extra_sum=with_sum)
    verdict = {"acceptable": True, "issues": [], "literal_facts": [
        {"claim_id": "n1", "case_id": "practice.guided",
         "datum_ids": ["cash_receipts", "current_revenue", "prior_receipts"]}]}
    if with_sum:
        verdict["calculations"] = evidence(extra_sum=True)["calculations"][1:]
    client, factory, responses = client_for(verdict, verdict)
    failures, actual, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == ["Lesson package numerical evidence unavailable; contract must not be used"]
    assert actual is responses[1] and actual.error
    assert client.generate_json.await_count == 2 and telemetry.await_count == 1
    assert actual.data["acceptable"] is True  # Bad proof is not a fabricated content verdict.


@pytest.mark.asyncio
async def test_missing_numeric_evidence_gets_one_same_package_correction(telemetry):
    package = numeric_package(claimed=10)
    client, factory, responses = client_for({"acceptable": True, "issues": []},
                                          {"calculations": evidence()["calculations"]})
    failures, actual, _ = await review_package(package, {}, {}, client_factory=factory)
    assert not failures and actual is responses[1]
    assert client.generate_json.await_count == 2 and telemetry.await_count == 1
    first, second = [call.kwargs for call in client.generate_json.call_args_list]
    first_payload, second_payload = json.loads(first["user_prompt"]), json.loads(second["user_prompt"])
    before, after = first_payload["package"], second_payload["package"]
    assert before.get("teaching_cases", []) == after.get("teaching_cases", [])
    assert before["workbook"]["title"] == after["workbook"]["title"]
    before_activities = {item["id"]: item for item in before["workbook"]["activities"]}
    after_activities = {item["id"]: item for item in after["workbook"]["activities"]}
    assert before_activities.keys() == after_activities.keys()
    assert after_activities["guided"] == before_activities["guided"]
    assert after_activities["transfer"] == {
        key: value for key, value in before_activities["transfer"].items()
        if key not in {"hint", "worked_solution"}}
    assert set(second_payload["evidence_cases"]) == {"practice.guided", "practice.transfer"}
    assert first_payload["numeric_spans"] == second_payload["numeric_spans"]
    assert second["output_model"].__name__ == "ReviewEvidencePatch"
    assert "SAME unchanged package" in second["system_prompt"]
    assert any("Numeric verification coverage is incomplete" in error
               for error in second_payload["verification_defects"])
    assert responses[0].error == "Lesson package numerical evidence unavailable; contract must not be used"


@pytest.mark.asyncio
async def test_known_wrong_arithmetic_is_terminal_despite_missing_coverage():
    package = numeric_package(extra_sum=True)
    package.workbook.activities[0].worked_solution += "\n110 - 100 = 30."
    incomplete = evidence(claimed=30)
    client, factory, _ = client_for(incomplete, evidence(claimed=30, extra_sum=True))
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures and response.error is None and response.data["acceptable"] is False
    assert client.generate_json.await_count == 1
    assert len(failures) == 1 and "explicit source equation is incorrect" in failures[0]


@pytest.mark.asyncio
async def test_unknown_schema_keys_are_not_echoed_in_diagnostics(telemetry):
    private = "DO_NOT_ECHO_PRIVATE_UNKNOWN_KEY"
    package = LessonPackage.model_validate(package_payload())
    client, factory, responses = client_for(
        {"acceptable": True, "issues": [], private: "private input"},
        {"acceptable": True, "issues": []},
    )
    failures, _, _ = await review_package(package, {}, {}, client_factory=factory)
    assert not failures and client.generate_json.await_count == 2
    assert private not in client.generate_json.call_args.kwargs["system_prompt"]
    assert "<unknown_field>: extra_forbidden" in client.generate_json.call_args.kwargs["system_prompt"]
    assert private not in responses[0].error


@pytest.mark.asyncio
@pytest.mark.parametrize("defect", ["unbound", "invented_span", "claimed_correct_instead", "self_proof"])
async def test_unverifiable_numeric_proof_never_becomes_a_content_correction(defect, telemetry):
    package = numeric_package()
    verdict = evidence(claimed=30)
    check = verdict["calculations"][0]
    if defect == "unbound":
        check["case_id"] = "practice.invented"
    elif defect == "invented_span":
        check["claim_ids"] = ["n999"]
    elif defect == "claimed_correct_instead":
        check["claimed_result"] = 10  # Correct answer absent from the actual claim.
    else:
        check["expression"] = "prior_receipts"  # The claimed raw value is not its own proof.
    client, factory, responses = client_for(verdict, verdict)
    failures, actual, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures and actual is responses[1] and actual.error
    assert actual.data["acceptable"] is True
    assert client.generate_json.await_count == 2 and telemetry.await_count == 1


@pytest.mark.asyncio
async def test_negative_semantic_verdict_is_terminal_even_without_numerical_evidence(telemetry):
    verdict = {"acceptable": False, "issues": ["The comparison mislabels prior receipts as the current-period difference."]}
    client, factory, responses = client_for(verdict)
    failures, actual, _ = await review_package(numeric_package(), {}, {}, client_factory=factory)
    assert failures == verdict["issues"] and actual is responses[0] and actual.error is None
    assert client.generate_json.await_count == 1
    telemetry.assert_not_awaited()


@pytest.mark.asyncio
async def test_issues_bearing_verdict_with_bad_evidence_cannot_retry_into_approval(telemetry):
    verdict = {"acceptable": True, "issues": ["The comparison is wrong."], "calculations": "invalid"}
    client, factory, responses = client_for(verdict, evidence())
    failures, actual, _ = await review_package(numeric_package(), {}, {}, client_factory=factory)
    assert failures and actual is responses[0] and actual.error
    assert client.generate_json.await_count == 1
    telemetry.assert_not_awaited()


def test_payload_has_exact_private_span_inventory_and_compact_provider_contract():
    package = numeric_package()
    payload = package_review_payload(package, {}, {})
    assert payload["numeric_spans"] == {"n1": package.workbook.activities[0].worked_solution}
    schema = PackageReview.model_json_schema()
    check = schema["$defs"]["PackagedCalculationCheck"]
    assert "location" not in check["properties"]
    assert set(check["required"]) == {"claim_ids", "case_id", "expression", "claimed_result"}


@pytest.mark.asyncio
@pytest.mark.parametrize("count,expected_cap", [(1, 2000), (20, 2900), (55, 6000)])
async def test_private_span_output_budget_is_bounded_without_raising_timeout(monkeypatch, count, expected_cap):
    package = LessonPackage.model_validate(package_payload())
    payload = package_review_payload(package, {}, {})
    payload["numeric_spans"] = {f"n{i}": "Private span" for i in range(count)}
    monkeypatch.setattr("app.services.planning.package_review.package_review_payload", lambda *args: payload)
    client, factory, _ = client_for({"acceptable": True, "issues": []})
    failures, _, _ = await review_package(package, {}, {}, client_factory=factory)
    assert not failures
    factory.assert_called_once_with(tier="balanced", timeout=60, max_tokens=expected_cap,
                                   thinking_level="low", allow_fallback=False)


@pytest.mark.asyncio
async def test_infeasible_workload_is_local_rejection_without_a_paid_call(telemetry):
    payload = package_payload()
    for activity in payload["workbook"]["activities"]:
        activity.update(minutes_min=1, minutes_max=1)
    package = LessonPackage.model_validate(payload)
    factory = Mock(side_effect=AssertionError("Impossible workload must not call a provider"))
    failures, response, client = await review_package(package, {}, {}, client_factory=factory)
    assert failures and "cannot meet" in failures[0]
    assert response.error is None and response.data["acceptable"] is False and client is None
    assert response.effective_parameters == {"synthetic_local_validation": True}
    assert response.prompt_tokens is None and response.completion_tokens is None
    factory.assert_not_called()
    telemetry.assert_not_awaited()


@pytest.mark.asyncio
async def test_pipeline_does_not_charge_either_local_preflight_rejection(monkeypatch):
    from tests.test_lesson_pipeline_reliability import Scenario, run_scenario

    payload = package_payload()
    for activity in payload["workbook"]["activities"]:
        activity.update(minutes_min=1, minutes_max=1)
    package = LessonPackage.model_validate(payload)
    # Keep this test at the orchestration boundary: both generated versions
    # remain infeasible, so neither local preflight invokes the provider.
    initial = AsyncMock(return_value=(package, LLMResponse(data=payload,
        effective_parameters={"synthetic_local_validation": True}), None))
    monkeypatch.setattr("app.services.planning.package_builder.generate_initial_package", initial)
    generated = AsyncMock(return_value=(package, LLMResponse(data=payload), SimpleNamespace(model="test")))
    monkeypatch.setattr("app.tasks.plans.generate_package", generated)
    case = Scenario("ordinary")
    _, calls, error = await run_scenario(case)
    assert error and initial.await_count == 2
    generated.assert_not_awaited()  # Aggregate scope cannot be fixed by private answer patches.
    assert case.counts["PackageSemanticReview"] == 0
    assert not any("preflight" in stage for stage, *_ in calls)
    # Both fixture assemblies and both local preflight rejections are synthetic;
    # no invented private-repair response belongs in paid call records.
    assert calls == []
    assert not any(key.startswith("LessonSectionGroup_") for key in case.counts)
