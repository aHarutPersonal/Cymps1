"""Scoped reviewer correction preserves verified work and fails closed."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_review import (
    LessonReview, PackagedLessonReview, ReviewEvidencePatch, review_lesson,
    _canonical_review_data, _repair_scope, numeric_spans,
)


PACKAGE = {"teaching_cases": [{"id": "case", "data": [
    {"id": "first", "label": "First amount", "value": 10},
    {"id": "second", "label": "Second amount", "value": 20},
]}]}
LESSON = {"lesson_content": "The combined amount is 30. The difference is 10."}


def calculation(ids, expression="first + second", result=30):
    return {"case_id": "teaching.case", "claim_ids": ids,
            "expression": expression, "claimed_result": result}


def verdict(**changes):
    return {"acceptable": True, "issues": [], "package_issues": [],
            "advisories": ["An optional editorial suggestion."],
            "practice_minutes": 30, "contains_calculations": True,
            "calculations": [calculation(["n1"])], **changes}


@pytest.fixture(autouse=True)
def no_telemetry(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())


async def run(first, patch, *, lesson=None, package=None):
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=copy.deepcopy(first)), LLMResponse(data=copy.deepcopy(patch))]))
    factory = lambda **kw: client
    result = await review_lesson(lesson or LESSON, client_factory=factory,
                                 context={"lesson_package": copy.deepcopy(package or PACKAGE)})
    return result, client


def test_packaged_wire_schema_omits_redundant_source_scaffolding():
    schema = PackagedLessonReview.model_json_schema()
    fields = schema["$defs"]["PackagedCalculationCheck"]["properties"]
    assert set(fields) == {"claim_ids", "case_id", "expression", "claimed_result", "claimed_literal"}
    assert "source_quote" in LessonReview.model_json_schema()["$defs"]["CalculationCheck"]["properties"]


@pytest.mark.asyncio
async def test_only_missing_evidence_is_requested_and_valid_proof_is_retained():
    (failures, response, _), client = await run(
        verdict(), {"calculations": [calculation(["n2"], "second-first", 10)]})
    assert failures == [] and response.error is None
    assert len(response.data["calculations"]) == 2
    assert response.data["advisories"] == verdict()["advisories"]
    first, second = client.generate_json.await_args_list
    assert issubclass(first.kwargs["output_model"], PackagedLessonReview)
    assert issubclass(second.kwargs["output_model"], ReviewEvidencePatch)
    payload = json.loads(second.kwargs["user_prompt"])
    assert payload["numeric_spans"] == {"n2": "The difference is 10."}
    assert payload["prior_evidence"]["calculations"] == []
    assert "lesson_for_workload_audit" not in payload
    assert "advisories" not in payload


@pytest.mark.asyncio
@pytest.mark.parametrize("patch", [
    {},
    {"calculations": [calculation(["n2"], "second-first", 11)]},
    {"calculations": [calculation(["n2"], "other-first", 10)]},
    {"literal_fact_ids": ["n2"]},
    {"literal_facts": [{"claim_id": "n2", "case_id": "teaching.case", "datum_ids": ["first"]}]},
    {"calculations": [calculation(["n999"], "second-first", 10)]},
    {"calculations": [calculation(["n1", "n2"], "second-first", 10)]},
    {"calculations": [calculation(["n2"], "second-first", 10)], "practice_minutes": 40},
    {"acceptable": True, "calculations": [calculation(["n2"], "second-first", 10)]},
])
async def test_incomplete_wrong_or_out_of_scope_patch_never_publishes(patch):
    (failures, response, _), client = await run(verdict(), patch)
    assert failures and response.error
    assert client.generate_json.await_count == 2


@pytest.mark.asyncio
async def test_patch_can_report_real_source_defect_without_a_third_call():
    (failures, response, _), client = await run(verdict(), {
        "package_issues": ["The private solution names the wrong accounting period."],
    })
    assert failures == ["The private solution names the wrong accounting period."]
    assert not response.data["acceptable"] and response.error is None
    assert response.data["advisories"] == verdict()["advisories"]
    assert client.generate_json.await_count == 2


@pytest.mark.asyncio
async def test_arithmetic_mismatch_is_included_when_other_evidence_is_missing():
    source = {"lesson_content": "The combined amount is 20. The difference is 10."}
    first = verdict(calculations=[calculation(["n1"], result=20)])
    (failures, response, _), client = await run(first, {
        "issues": ["The combined amount must be 30, not 20."],
        "affected_sections": ["worked_example"],
    }, lesson=source)
    assert failures == ["The combined amount must be 30, not 20."]
    assert response.error is None and not response.data["acceptable"]
    payload = json.loads(client.generate_json.await_args_list[1].kwargs["user_prompt"])
    assert set(payload["numeric_spans"]) == {"n1", "n2"}
    assert any("not 20" in error for error in payload["verification_defects"])


@pytest.mark.asyncio
async def test_wrong_reviewer_expression_and_missing_proof_can_be_corrected_together():
    first = verdict(calculations=[calculation(["n1"], expression="second-first", result=30)])
    (failures, response, _), _ = await run(first, {"calculations": [
        calculation(["n1"]), calculation(["n2"], "second-first", 10)]})
    assert not failures and response.error is None
    assert len(response.data["calculations"]) == 2


@pytest.mark.asyncio
async def test_negative_whole_lesson_verdict_is_never_overridden_by_patch():
    (failures, response, _), client = await run(
        verdict(acceptable=False, issues=["Missing independent practice."]), {})
    assert failures == ["Missing independent practice."]
    assert not response.data["acceptable"]
    assert client.generate_json.await_count == 1


@pytest.mark.asyncio
async def test_grouped_check_removes_only_failed_ids_not_all_previous_proof():
    first = verdict(calculations=[calculation(["n1", "n999"])])
    (failures, response, _), client = await run(first, {"calculations": [
        calculation(["n1"]), calculation(["n2"], "second-first", 10)]})
    assert failures == [] and response.error is None
    assert {key for check in response.data["calculations"] for key in check["claim_ids"]} == {"n1", "n2"}


@pytest.mark.asyncio
async def test_fabricated_fact_is_removed_without_reasking_valid_calculations():
    first = verdict(
        calculations=[calculation(["n1"]), calculation(["n2"], "second-first", 10)],
        literal_facts=[{"claim_id": "fake_fact", "case_id": "teaching.case", "datum_ids": ["first"]}],
    )
    (failures, response, _), client = await run(first, {})
    assert failures == [] and response.error is None
    assert {key for check in response.data["calculations"] for key in check["claim_ids"]} == {"n1", "n2"}
    assert response.data["literal_facts"] == []
    assert client.generate_json.await_count == 2
    payload = json.loads(client.generate_json.await_args_list[1].kwargs["user_prompt"])
    assert payload["numeric_spans"] == {}
    assert payload["prior_evidence"]["calculations"] == []
    assert payload["prior_evidence"]["literal_facts"] == []
    assert payload["invalid_claim_ids"] == ["fake_fact"]


def test_unknown_diagnostic_still_requires_full_evidence_repair():
    first = verdict(
        calculations=[calculation(["n1"]), calculation(["n2"], "second-first", 10)],
        literal_facts=[{"claim_id": "fake_fact", "case_id": "teaching.case", "datum_ids": ["first"]}],
    )
    review = LessonReview.model_validate(_canonical_review_data(first, packaged=True))
    spans = numeric_spans(LESSON)
    assert _repair_scope(review, spans, ["fake_fact: fabricated literal-fact ID"]) == {"fake_fact"}
    assert _repair_scope(review, spans, ["Unrecognized diagnostic"]) == {"n1", "n2", "fake_fact"}


@pytest.mark.asyncio
async def test_workload_correction_retains_all_numerical_proof_and_advisories():
    package = {**PACKAGE, "private_workbook": {"activities": [
        {"id": "practice", "minutes_min": 30, "minutes_max": 40}]}}
    first = verdict(practice_minutes=80, calculations=[calculation(["n1"]), calculation(["n2"], "second-first", 10)])
    lesson = {"lesson_content": LESSON["lesson_content"] + " Teaching rationale." * 1000}
    (failures, response, _), client = await run(first, {"practice_minutes": 35}, package=package, lesson=lesson)
    assert failures == [] and response.data["practice_minutes"] == 35
    assert len(response.data["calculations"]) == 2
    payload = json.loads(client.generate_json.await_args_list[1].kwargs["user_prompt"])
    assert payload["numeric_spans"] == {}
    assert payload["workload_contract"]["practice_minutes_range"] == [30, 40]


@pytest.mark.asyncio
async def test_in_range_activity_time_cannot_approve_an_underfilled_session():
    package = {**PACKAGE, "private_workbook": {"activities": [
        {"id": "practice", "minutes_min": 24, "minutes_max": 35}]}}
    first = verdict(practice_minutes=24, calculations=[calculation(["n1"]), calculation(["n2"], "second-first", 10)])
    lesson = {"lesson_content": LESSON["lesson_content"] + " Teaching rationale." * 1000}
    (failures, response, _), client = await run(first, {"practice_minutes": 24}, package=package, lesson=lesson)
    assert failures and response.error
    assert any("actual total=34" in error for error in failures)
    payload = json.loads(client.generate_json.await_args_list[1].kwargs["user_prompt"])
    assert "actual total=34" in payload["workload_error"]
    assert "force" in client.generate_json.await_args_list[1].kwargs["system_prompt"]


@pytest.mark.asyncio
async def test_exhausted_patch_keeps_uncertain_evidence_out_of_content_repairs():
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=verdict()), LLMResponse(data={}, error="zai request failed (TimeoutError; finish=missing)")]))
    failures, response, _ = await review_lesson(LESSON, client_factory=lambda **kw: client,
                                               context={"lesson_package": PACKAGE})
    assert failures and response.error
    assert client.generate_json.await_count == 2
