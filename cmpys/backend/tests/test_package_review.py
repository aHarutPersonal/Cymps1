"""Regression contracts for the inexpensive private-package preflight.

Provider verdicts are mocked: these tests prove evidence and gate behavior,
not that a live model consistently finds every semantic defect.
"""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest
from pydantic import ValidationError

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage, parse_package_response
from app.services.planning.package_review import PackageReview, package_review_payload, review_package
from app.services.practice.contracts import calculate
from tests.lesson_package_fixtures import package_payload


@pytest.fixture
def package():
    return LessonPackage.model_validate(package_payload())


@pytest.fixture
def recorded_accounting_package():
    payload = json.loads((Path(__file__).parent / "fixtures/accounting_package_misnested_tail.json").read_text())
    return parse_package_response(payload)


@pytest.fixture
def telemetry(monkeypatch):
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    return record


def client_for(*responses):
    client = SimpleNamespace(model="test-model", generate_json=AsyncMock(side_effect=list(responses)))
    return client, Mock(return_value=client)


@pytest.mark.parametrize("payload", [
    {"acceptable": "true", "issues": []},
    {"acceptable": 1, "issues": []},
    {"acceptable": True},
    {"acceptable": True, "issues": [""]},
    {"acceptable": True, "issues": ["   "]},
    {"acceptable": True, "issues": [1]},
    {"acceptable": True, "issues": [], "extra": "must not be ignored"},
    {"acceptable": False, "issues": ["x" * 1201]},
    {"acceptable": False, "issues": ["defect"] * 13},
])
def test_review_schema_rejects_coercion_missing_fields_and_unbounded_output(payload):
    with pytest.raises(ValidationError):
        PackageReview.model_validate(payload)


def test_accounting_evidence_uses_raw_values_and_keeps_all_semantic_defects_visible(recorded_accounting_package):
    package = recorded_accounting_package
    original = package.model_dump(mode="json")
    payload = package_review_payload(package, {"title": "Accrual and cash flow"}, {"language": "hy"})
    values = {entry["target"]: entry["value"] for entry in payload["numerical_evidence"]}
    assert values["teaching_cases[cafe_arev_month].results[accrual_profit]"] == 700000
    assert values["teaching_cases[cafe_arev_month].results[cash_flow]"] == 650000
    prefix = "workbook.activities[guided_practice_arev].fields"
    assert values[f"{prefix}[accrual_revenue_field]"] == 1200000
    assert values[f"{prefix}[accrual_profit_field]"] == 700000
    assert values[f"{prefix}[cash_flow_field]"] == 650000
    activity = payload["package"]["workbook"]["activities"][0]
    data = {datum["id"]: datum["value"] for datum in activity["data"]}
    # The misleading saved solution calls 150000 uncollected current sales.
    # The data actually label it a collection of prior debts. Check all three
    # signed causes, not just 150000 - 100000, which coincidentally equals 50000.
    assert data["a_credit_sales"] == 300000
    assert data["a_cash_collected"] == 150000
    assert calculate("a_expenses_incurred - a_expenses_paid", data) == 100000
    gap = calculate("a_credit_sales - a_cash_collected - (a_expenses_incurred - a_expenses_paid)", data)
    assert gap == 50000
    assert values[f"{prefix}[accrual_profit_field]"] - values[f"{prefix}[cash_flow_field]"] == gap
    assert activity["worked_solution"] == package.workbook.activities[0].worked_solution
    assert activity["data"][2]["label"] == "Նախկին պարտքերից ստացված կանխիկ"
    assert payload["package"]["teaching_cases"][0]["data"][1]["label"] == package.teaching_cases[0].data[1].label
    assert package.model_dump(mode="json") == original


def test_evidence_does_not_duplicate_public_or_private_package(package):
    stale = "STALE_PUBLIC_COPY"
    context = {"goal": "Write an argument", "learner_context": "Beginner", "lesson_package": stale,
               "private_workbook": stale, "practice": stale, "teaching_cases": stale, "package": stale}
    before = copy.deepcopy(context)
    payload = package_review_payload(package, {"id": "step_1"}, context)
    serialized = json.dumps(payload)
    assert stale not in serialized
    assert payload["context"] == {"goal": "Write an argument", "learner_context": "Beginner"}
    assert set(payload["package"]) == {"workbook"}
    assert serialized.count('"worked_solution":') == len(package.workbook.activities)
    assert payload["numerical_evidence"] == []
    assert context == before


@pytest.mark.asyncio
async def test_preflight_is_bounded_private_and_requires_later_independent_review(package, telemetry, caplog):
    response = LLMResponse(data={"acceptable": True, "issues": []}, finish_reason="stop")
    client, factory = client_for(response)
    failures, actual, actual_client = await review_package(package, {"id": "step_1"}, {}, client_factory=factory)
    assert failures == [] and actual is response and actual_client is client
    factory.assert_called_once_with(tier="balanced", timeout=60, max_tokens=2000,
                                    thinking_level="low", allow_fallback=False)
    request = client.generate_json.call_args.kwargs
    assert issubclass(request["output_model"], PackageReview)
    assert "EVERY signed term" in request["system_prompt"]
    assert "prior-period debt" in request["system_prompt"]
    assert "raw fact labels" in request["system_prompt"]
    assert "learner's requested language" in request["system_prompt"]
    assert "does not replace final lesson review" in request["system_prompt"]
    assert "untrusted reference data" in request["system_prompt"]
    assert client.generate_json.await_count == 1
    assert not telemetry.called
    for activity in package.workbook.activities:
        assert activity.worked_solution not in caplog.text


@pytest.mark.asyncio
@pytest.mark.parametrize("acceptable,issues", [
    (False, ["workbook.activities[guided].worked_solution: explanation contradicts the raw facts"]),
    (True, ["workbook.activities[guided].worked_solution: explanation contradicts the raw facts"]),
    (False, []),
])
async def test_negative_verdict_is_final_without_reasking_for_approval(package, telemetry, acceptable, issues):
    data = {"acceptable": acceptable, "issues": issues}
    response = LLMResponse(data=copy.deepcopy(data))
    client, factory = client_for(response)
    failures, actual, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == (issues or ["Package reviewer did not approve this contract"])
    assert actual is response and actual.data == data and actual.error is None
    assert client.generate_json.await_count == 1
    assert not telemetry.called


@pytest.mark.asyncio
async def test_exact_recorded_accounting_rejection_reaches_repair_unchanged(recorded_accounting_package, telemetry):
    issues = [
        "workbook.activities[guided_practice_arev].worked_solution: 150000 is collection of prior debts, not uncollected current sales; explain 300000 - 150000 - 100000 = 50000.",
        "teaching_cases[cafe_arev_month].data[credit_sales].label: subtracting the prior-debt collection from current credit sales mislabels the raw fact.",
    ]
    response = LLMResponse(data={"acceptable": False, "issues": issues})
    client, factory = client_for(response)
    failures, actual, _ = await review_package(recorded_accounting_package, {}, {}, client_factory=factory)
    assert failures == issues and actual is response
    assert client.generate_json.await_count == 1
    assert not telemetry.called


@pytest.mark.asyncio
@pytest.mark.parametrize("error", [
    "zai request failed (TimeoutError; finish=missing)",
    "OpenLux request failed (APIConnectionError; finish=missing)",
    "zai request failed (RateLimitError; finish=missing)",
    "zai request failed (JSONDecodeError; finish=stop)",
])
async def test_transient_or_malformed_review_retries_same_package_once(package, telemetry, error):
    first = LLMResponse(data={}, error=error)
    second = LLMResponse(data={"acceptable": True, "issues": []})
    client, factory = client_for(first, second)
    failures, actual, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == [] and actual is second
    assert client.generate_json.await_count == 2 and telemetry.await_count == 1
    initial, retry = [call.kwargs for call in client.generate_json.call_args_list]
    assert initial["user_prompt"] == retry["user_prompt"]
    assert "SAME unchanged package" in retry["system_prompt"]


@pytest.mark.asyncio
async def test_two_unavailable_reviews_stop_and_sanitize_private_error(package, telemetry, caplog):
    private = package.workbook.activities[0].worked_solution
    errors = [LLMResponse(data={}, error=f"zai request failed (TimeoutError; {private})") for _ in range(2)]
    client, factory = client_for(*errors)
    failures, actual, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures == ["Lesson package review unavailable; contract must not be used"]
    assert actual is errors[-1]
    assert client.generate_json.await_count == 2 and telemetry.await_count == 1
    assert all(private not in response.error for response in errors)
    assert private not in caplog.text


@pytest.mark.asyncio
async def test_permanent_error_does_not_spend_retry(package, telemetry):
    response = LLMResponse(data={}, error="zai request failed (AuthenticationError; finish=missing)")
    client, factory = client_for(response)
    failures, _, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures and client.generate_json.await_count == 1 and not telemetry.called


@pytest.mark.asyncio
@pytest.mark.parametrize("next_data,passes", [
    ({"acceptable": True, "issues": []}, True),
    ({"acceptable": "yes", "issues": []}, False),
])
async def test_invalid_schema_has_one_strict_retry_without_echoing_private_input(package, telemetry, next_data, passes):
    private = package.workbook.activities[0].worked_solution
    first = LLMResponse(data={"acceptable": private, "issues": []})
    second = LLMResponse(data=next_data)
    client, factory = client_for(first, second)
    failures, actual, _ = await review_package(package, {}, {}, client_factory=factory)
    assert (not failures) is passes and actual is second
    assert client.generate_json.await_count == 2 and telemetry.await_count == 1
    correction = client.generate_json.call_args.kwargs["system_prompt"]
    assert "acceptable: bool_type" in correction
    assert private not in correction and private not in first.error


@pytest.mark.asyncio
async def test_valid_looking_truncated_verdict_is_never_accepted(package, telemetry):
    responses = [LLMResponse(data={"acceptable": True, "issues": []}, finish_reason="length") for _ in range(2)]
    client, factory = client_for(*responses)
    failures, _, _ = await review_package(package, {}, {}, client_factory=factory)
    assert failures and client.generate_json.await_count == 2 and telemetry.await_count == 1
