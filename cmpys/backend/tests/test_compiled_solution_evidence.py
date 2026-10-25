"""Compiler ownership saves proof work without granting prose approval."""
import copy
import json
from dataclasses import replace
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning import lesson_review as review
from app.services.planning import package_preflight as preflight
from app.services.practice import solution_compiler as compiler
from tests.test_package_split_preflight import package as legacy_package


def typed_package(*, explanation=None, expression="receipts - revenue"):
    raw = legacy_package().model_dump(mode="json")
    for activity in raw["workbook"]["activities"]:
        activity["fields"][0]["expression"] = expression
        activity["worked_solution"] = {"version": 1, "steps": [{
            "field_id": "difference", "explanation": explanation or
            "Explain why this comparison is supported by the supplied case facts."}]}
    return LessonPackage.model_validate(raw)


def ids(evidence):
    return {key for check in evidence.calculations for key in check.claim_ids}


def whole_review(evidence, *, practice_minutes=40):
    return review.LessonReview.model_validate({"acceptable": True, "issues": [],
        "practice_minutes": practice_minutes, "contains_calculations": bool(evidence.calculations),
        "calculations": [{"location": ", ".join(check.claim_ids), **check.model_dump(mode="json")}
                         for check in evidence.calculations]})


@pytest.fixture(autouse=True)
def offline(monkeypatch):
    telemetry = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    return telemetry


@pytest.mark.parametrize("expression", ["receipts - revenue", "receipts * revenue / 2",
    "sqrt(receipts * receipts + revenue * revenue)", "receipts / revenue * 100"])
def test_exact_compiler_equations_pass_ordinary_full_grounding_and_math(expression):
    package = typed_package(expression=expression)
    context = package.review_context()
    original = copy.deepcopy(context)
    evidence = review.compiled_solution_evidence({}, context)
    assert len(evidence.calculations) == 2
    assert ids(evidence) == set(review.numeric_spans({}, context))
    verdict = whole_review(evidence)
    assert review.grounded_failures(verdict, {}, context) == []
    assert verdict.failures() == []
    assert context == original
    # The canonical typed source and its verified private projection agree.
    raw = {"private_workbook": package.workbook.model_dump(mode="json"), "teaching_cases": []}
    assert review.compiled_solution_evidence({}, raw) == evidence


def test_legacy_identical_equation_text_never_gains_compiler_provenance():
    context = typed_package().review_context()
    for activity in context["private_workbook"]["activities"]:
        activity.pop("worked_solution_document")
    assert review.numeric_spans({}, context)
    assert not review.compiled_solution_evidence({}, context).calculations


def test_final_inventory_ids_rebuild_after_unicode_lesson_and_substep_offsets():
    context = typed_package().review_context()
    lesson = {"lesson_content": "Արտաքին անհայտ թիվը 999 է։", "substeps": ["Another unsupported value is 888."]}
    evidence = review.compiled_solution_evidence(lesson, context)
    assert ids(evidence) == {"n3", "n4"}
    occurrences = {record.claim_id: record for record in review.numeric_span_occurrences(lesson, context)}
    for check in evidence.calculations:
        record = occurrences[check.claim_ids[0]]
        assert record.path[:3] == ("package", "private_workbook", "activities")
        assert record.source[record.start:record.end] == record.span
    verdict = whole_review(evidence)
    assert review.grounded_failures(verdict, lesson, context)
    assert not review.grounded_failures(verdict, lesson, context, expected_claim_ids=ids(evidence))


@pytest.mark.parametrize("where", ["label", "hint", "unit", "explanation"])
def test_authored_numbers_never_inherit_nearby_compiler_coverage(where):
    raw = typed_package().model_dump(mode="json")
    activity = raw["workbook"]["activities"][0]
    if where == "label": activity["fields"][0]["label"] = "Unsupported amount 999"
    elif where == "hint": activity["hint"] = "A separate unsupported amount is 999."
    elif where == "unit": activity["fields"][0]["unit"] = "unit 999"
    else: activity["worked_solution"]["steps"][0]["explanation"] += " An unsupported amount is 999."
    context = LessonPackage.model_validate(raw).review_context()
    evidence = review.compiled_solution_evidence({}, context)
    spans = review.numeric_spans({}, context)
    unproved = set(spans) - ids(evidence)
    assert unproved and all("999" in spans[key] for key in unproved)
    assert review.grounded_failures(whole_review(evidence), {}, context)


@pytest.mark.parametrize("mutation", ["sign", "whitespace", "document", "unknown_key", "other_activity"])
def test_projection_bytes_and_canonical_document_must_both_match(mutation):
    context = typed_package().review_context()
    activity = context["private_workbook"]["activities"][0]
    if mutation == "sign": activity["worked_solution"] = activity["worked_solution"].replace(" = 20", " = -20")
    elif mutation == "whitespace": activity["worked_solution"] += " "
    elif mutation == "document": activity["worked_solution_document"]["steps"][0]["explanation"] += " Altered explanation."
    elif mutation == "unknown_key": activity["unknown_manifest"] = {}
    else: activity["worked_solution"] = context["private_workbook"]["activities"][1]["worked_solution"]
    evidence = review.compiled_solution_evidence({}, context)
    assert {check.case_id for check in evidence.calculations} == {"practice.a1"}


@pytest.mark.parametrize("mutation", ["source_hash", "rendered_hash", "renderer_version", "source_path", "offset", "owner",
    "field", "step", "expression", "datum_ids", "unit", "result", "literal"])
def test_record_metadata_cannot_supply_an_alternate_source_or_derivation(monkeypatch, mutation):
    context = typed_package().review_context()
    actual = compiler.compile_worked_solution
    def corrupt(activity):
        result = actual(activity)
        if mutation == "source_hash": return replace(result, source_hash="0" * 64)
        if mutation == "rendered_hash": return replace(result, rendered_hash="0" * 64)
        if mutation == "renderer_version": return replace(result, renderer_version=999)
        record = result.records[0]
        values = {"source_path": {"source_path": ("hint",)}, "offset": {"start": record.start + 1},
            "owner": {"case_id": "practice.other"}, "field": {"field_id": "other"},
            "step": {"step_index": 8}, "expression": {"expression": "receipts + revenue"},
            "datum_ids": {"datum_ids": ("unknown",)}, "unit": {"unit": "other"},
            "result": {"result": record.result + 1}, "literal": {"literal": "999"}}
        return replace(result, records=(replace(record, **values[mutation]),))
    monkeypatch.setattr(compiler, "compile_worked_solution", corrupt)
    assert not review.compiled_solution_evidence({}, context).calculations


def test_tiny_unrepresentable_literal_and_unary_math_keep_ordinary_proof_obligation():
    raw = typed_package(expression="receipts / revenue").model_dump(mode="json")
    for activity in raw["workbook"]["activities"]:
        activity["data"][0]["value"] = 1e-100 if activity["id"] == "a0" else 2e-100
        activity["data"][1]["value"] = 2
    context = LessonPackage.model_validate(raw).review_context()
    assert review.numeric_spans({}, context)
    assert not review.compiled_solution_evidence({}, context).calculations
    unary = typed_package(expression="-receipts").review_context()
    assert review.numeric_spans({}, unary)
    assert not review.compiled_solution_evidence({}, unary).calculations


def test_one_unsupported_unary_does_not_discard_an_independent_binary_seed():
    raw = typed_package().model_dump(mode="json")
    raw["workbook"]["activities"][0]["fields"][0]["expression"] = "-receipts"
    context = LessonPackage.model_validate(raw).review_context()
    evidence = review.compiled_solution_evidence({}, context)
    assert {check.case_id for check in evidence.calculations} == {"practice.a1"}
    assert set(review.numeric_spans({}, context)) - ids(evidence) == {"n1"}


def test_generated_candidates_use_one_full_source_gate(monkeypatch):
    raw = typed_package().model_dump(mode="json")
    for activity in raw["workbook"]["activities"]:
        first = activity["fields"][0]
        activity["fields"] = [{**first, "id": f"difference{index}", "label": "Named comparison"}
                              for index in range(10)]
        activity["worked_solution"]["steps"] = [{"field_id": field["id"],
            "explanation": "Explain the comparison using the provided case facts."} for field in activity["fields"]]
    context = LessonPackage.model_validate(raw).review_context()
    actual = review.grounded_failures
    calls = []
    def count(*args, **kwargs):
        calls.append(kwargs.get("expected_claim_ids"))
        return actual(*args, **kwargs)
    monkeypatch.setattr(review, "grounded_failures", count)
    evidence = review.compiled_solution_evidence({}, context)
    assert len(evidence.calculations) == 20
    assert calls == [ids(evidence)]


def test_alias_normalization_requires_exact_valid_projection():
    context = typed_package().review_context()
    data = {"literal_facts": [{"claim_id": "n2", "case_id": "transfer.a1", "datum_ids": ["receipts"]}]}
    normalized, count = review.normalize_evidence_case_aliases(data, context)
    assert count == 1 and normalized["literal_facts"][0]["case_id"] == "practice.a1"
    context["private_workbook"]["activities"][1]["worked_solution"] += " altered"
    assert review.normalize_evidence_case_aliases(data, context) == (data, 0)


class Reviewer:
    def __init__(self, *, semantic_negative=False, residual=False, wrong_first=False, patch_negative=False):
        self.calls = []
        self.semantic_negative, self.residual = semantic_negative, residual
        self.wrong_first, self.patch_negative = wrong_first, patch_negative

    def factory(self, **kwargs):
        return SimpleNamespace(generate_json=self.generate, model="offline", provider_name="dummy")

    async def generate(self, **request):
        body = json.loads(request["user_prompt"])
        name = request["output_model"].__name__
        self.calls.append((name, body))
        if name == "PackageSemanticReview":
            data = {"acceptable": not self.semantic_negative, "issues": [{
                "target": "practice.a0.difference", "description": "This task's formula does not represent the intended comparison."}]
                if self.semantic_negative else []}
        else:
            data = {"calculations": [], "literal_facts": []}
            if self.patch_negative and name == "ReviewEvidencePatch":
                data = {"issues": ["The authored explanation contradicts its task and must be revised."]}
            else:
                for key, span in body["numeric_spans"].items():
                    owners = body.get("numeric_span_owners", body.get("context", {}).get("numeric_span_owners", {}))
                    owner = owners.get(key, "practice.a0")
                    data["literal_facts"].append({"claim_id": key, "case_id": owner, "datum_ids": ["receipts"]})
                if self.wrong_first and name == "PackagedLessonReview":
                    data["literal_facts"] = []
            if name == "PackagedLessonReview":
                data.update(acceptable=not self.semantic_negative, issues=["The whole lesson has a material teaching contradiction."]
                            if self.semantic_negative else [], practice_minutes=40, contains_calculations=False)
        return LLMResponse(data=data)


@pytest.mark.asyncio
async def test_preflight_compiled_only_still_requires_semantics_then_default_union(offline):
    package, client, snapshots = typed_package(), Reviewer(), []
    async def save(value): snapshots.append(copy.deepcopy(value))
    errors, response, _ = await preflight.review_package(package, {}, {}, client_factory=client.factory, on_review=save)
    assert not errors and not response.error
    assert [name for name, _ in client.calls] == ["PackageSemanticReview"]
    assert offline.await_count == 1
    assert response.effective_parameters["compiled_arithmetic_claim_count"] == 2
    assert len(response.data["calculations"]) == 2
    assert set(snapshots[-1]["scopes"]) == {"a0", "a1"}
    body = client.calls[0][1]
    assert all(isinstance(a["worked_solution"], str) for a in body["package"]["workbook"]["activities"])
    preflight.validate_preflight_state(snapshots[-1], package=package, outline={}, context={})
    # Exact resume makes no second semantic call and rechecks persisted proofs.
    client.calls.clear()
    errors, response, _ = await preflight.review_package(package, {}, {}, client_factory=client.factory,
        existing_review=snapshots[-1])
    assert not errors and not client.calls


@pytest.mark.asyncio
async def test_negative_preflight_blocks_compiler_evidence_and_exposes_only_typed_targets():
    client = Reviewer(semantic_negative=True)
    errors, response, _ = await preflight.review_package(typed_package(), {}, {}, client_factory=client.factory)
    assert errors and not response.data["acceptable"] and len(client.calls) == 1
    assert response.effective_parameters["validated_repair_targets"] == ["practice.a0.difference"]
    assert not response.data.get("calculations")


@pytest.mark.asyncio
async def test_preflight_requests_only_authored_residual_and_keeps_complete_seed_union():
    raw = typed_package().model_dump(mode="json")
    raw["workbook"]["activities"][0]["worked_solution"]["steps"][0]["explanation"] += " Receipts are 120."
    package, client = LessonPackage.model_validate(raw), Reviewer()
    snapshots = []
    async def save(value): snapshots.append(copy.deepcopy(value))
    errors, response, _ = await preflight.review_package(package, {}, {}, client_factory=client.factory, on_review=save)
    assert not errors and not response.error
    assert [name for name, _ in client.calls] == ["PackageSemanticReview", "ReviewEvidencePatch"]
    assert list(client.calls[1][1]["numeric_spans"].values()) == ["Receipts are 120."]
    assert len(response.data["calculations"]) == 2 and len(response.data["literal_facts"]) == 1
    saved = snapshots[-1]
    preflight.validate_preflight_state(saved, package=package, outline={}, context={})
    assert len(saved["scopes"]["a0"]["claim_ids"]) == 2
    client.calls.clear()
    errors, response, _ = await preflight.review_package(package, {}, {}, client_factory=client.factory,
        existing_review=saved)
    assert not errors and not client.calls


@pytest.mark.asyncio
async def test_preflight_residual_correction_preserves_seed_and_budget():
    raw = typed_package().model_dump(mode="json")
    raw["workbook"]["activities"][0]["worked_solution"]["steps"][0]["explanation"] += " Receipts are 120."
    package, client = LessonPackage.model_validate(raw), Reviewer()
    actual = client.generate
    async def missing_first(**request):
        response = await actual(**request)
        if len(client.calls) == 2:
            response.data = {"calculations": []}
        return response
    client.generate = missing_first
    errors, response, _ = await preflight.review_package(package, {}, {}, client_factory=client.factory)
    assert not errors and len(client.calls) == 3
    assert client.calls[1][1]["numeric_spans"] == client.calls[2][1]["numeric_spans"]
    assert len(response.data["calculations"]) == 2
    assert response.effective_parameters["shared_correction_used"]
    assert response.effective_parameters["request_count"] == response.effective_parameters["max_requests"] == 3


@pytest.mark.asyncio
async def test_final_semantic_review_omits_compiler_ids_but_retains_all_evidence():
    client = Reviewer()
    context = {"lesson_package": typed_package().review_context()}
    errors, response, _ = await review.review_lesson({"lesson_content": "Explain the comparison in clear terms."},
        client_factory=client.factory, context=context)
    assert not errors and not response.error and len(client.calls) == 1
    assert client.calls[0][1]["numeric_spans"] == {}
    request_activities = client.calls[0][1]["context"]["lesson_package"]["private_workbook"]["activities"]
    assert all("worked_solution_document" not in activity for activity in request_activities)
    assert all(isinstance(activity["worked_solution"], str) for activity in request_activities)
    assert all("worked_solution_document" in activity for activity in context["lesson_package"]["private_workbook"]["activities"])
    assert len(response.data["calculations"]) == 2
    assert response.data["contains_calculations"] is True


@pytest.mark.asyncio
@pytest.mark.parametrize("negative", [False, True])
async def test_final_scoped_correction_keeps_seed_and_cannot_erase_negative(negative):
    client = Reviewer(wrong_first=True, patch_negative=negative)
    context = {"lesson_package": typed_package().review_context()}
    lesson = {"lesson_content": "Receipts are 120."}
    errors, response, _ = await review.review_lesson(lesson, client_factory=client.factory, context=context)
    assert len(client.calls) == 2
    assert client.calls[0][1]["numeric_spans"] == client.calls[1][1]["numeric_spans"] == {"n1": "Receipts are 120."}
    assert len(response.data["calculations"]) == 2
    assert {key for check in response.data["calculations"] for key in check["claim_ids"]} == {"n2", "n3"}
    assert bool(errors) is negative
    assert response.data["acceptable"] is not negative


@pytest.mark.asyncio
async def test_final_negative_whole_lesson_review_is_not_promoted_by_compiler():
    client = Reviewer(semantic_negative=True)
    errors, response, _ = await review.review_lesson({"lesson_content": "A complete explanation."},
        client_factory=client.factory, context={"lesson_package": typed_package().review_context()})
    assert errors and not response.data["acceptable"] and len(client.calls) == 1


@pytest.mark.asyncio
async def test_model_cannot_replace_compiler_owned_final_evidence():
    response = LLMResponse(data={"acceptable": True, "issues": [], "practice_minutes": 40,
        "contains_calculations": True, "calculations": [{"claim_ids": ["n1"], "case_id": "practice.a0",
            "expression": "receipts - revenue", "claimed_result": 20}]})
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    errors, result, _ = await review.review_lesson({"lesson_content": "A complete explanation."},
        client_factory=lambda **kwargs: client, context={"lesson_package": typed_package().review_context()})
    assert errors and result.error == "Lesson review included unrequested compiler-owned evidence"
    assert client.generate_json.await_count == 1
