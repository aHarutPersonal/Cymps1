"""Repair copying aids narrow requests without changing source or proof gates."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning import lesson_review as review
from app.services.planning.package_review import (
    PackageReview, _evidence_patch_request, package_review_payload, review_package,
)
from tests.test_package_preflight_patch import package_with_spans, approved, check
from tests.test_math_role_evidence import package_for, role, failures as role_failures
from tests.test_compiled_solution_evidence import typed_package, whole_review


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


@pytest.fixture(autouse=True)
def offline(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())


def test_shared_copy_filters_all_evidence_bindings_without_mutating_retained_original():
    grouped = {**check(), "claim_ids": ["n1", "n2", "invented", "n2"]}
    original = PackageReview.model_validate(approved(grouped,
        literal_facts=[{"claim_id": key, "case_id": "practice.guided", "datum_ids": ["revenue"]}
                       for key in ("n1", "n2", "invented")],
        literal_fact_ids=["n1", "n2", "invented"],
        math_roles=[role(span=key) for key in ("n1", "n2", "invented")]))
    before = original.model_dump(mode="json")
    scoped = review._scoped_prior_evidence(original, {"n2"})
    assert scoped["calculations"] == [{**check("n2")}]
    assert [item["claim_id"] for item in scoped["literal_facts"]] == ["n2"]
    assert scoped["literal_fact_ids"] == ["n2"]
    assert [item["claim_id"] for item in scoped["math_roles"]] == ["n2"]
    scoped["calculations"][0]["expression"] = "untrusted replacement"
    scoped["math_roles"][0]["symbol_bindings"]["b"] = "other"
    assert original.model_dump(mode="json") == before


def test_grouped_package_copy_and_schema_agree_and_no_source_or_budget_changes():
    package = package_with_spans("Receipts exceed revenue by 20.", "Their difference is 20 and total is 220.")
    grouped = {**check(), "claim_ids": ["n1", "n2"]}
    original = PackageReview.model_validate(approved(grouped))
    payload = package_review_payload(package, {}, {})
    before = copy.deepcopy(payload), original.model_dump(mode="json")
    request, scope = _evidence_patch_request(original, payload, ["n2: numeric span contains additional unverified values"])
    body = json.loads(request["user_prompt"])
    assert scope == {"n2"}
    assert body["prior_evidence"]["calculations"] == [check("n2")]
    assert request["output_model"].model_json_schema()["$defs"]["SourceClaimId"]["enum"] == ["n2"]
    assert body["numeric_spans"] == {"n2": payload["numeric_spans"]["n2"]}
    assert (payload, original.model_dump(mode="json")) == before
    previous = copy.deepcopy(body)
    previous["prior_evidence"]["calculations"][0]["claim_ids"] = ["n1", "n2"]
    assert len(encoded(previous)) - len(encoded(body)) == 5
    assert "prior_evidence_copy_aids" not in body  # No new lexical facts needed here.


@pytest.mark.asyncio
@pytest.mark.parametrize("extra_id", [None, "n1"])
async def test_package_copy_fix_preserves_unaffected_proof_and_still_rejects_unsolicited_id(extra_id):
    package = package_with_spans("Receipts exceed revenue by 20.", "Their difference is 20 and total is 220.")
    grouped = {**check(), "claim_ids": ["n1", "n2"]}
    initial = approved(grouped)
    patch = [check("n2"), check("n2", expression="receipts + revenue", result=220)]
    if extra_id:
        patch[0]["claim_ids"].append(extra_id)
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=copy.deepcopy(initial)), LLMResponse(data={"calculations": patch})]))
    factory = Mock(return_value=client)
    errors, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert bool(errors) is bool(extra_id)
    assert bool(response.error) is bool(extra_id)
    assert client.generate_json.await_count == 2
    factory.assert_called_once_with(tier="balanced", timeout=60, max_tokens=2000,
                                    thinking_level="low", allow_fallback=False)
    if not extra_id:
        assert response.data["calculations"][0] == {**check("n1"), "claimed_literal": None}
    assert initial == approved(grouped)


@pytest.mark.asyncio
@pytest.mark.parametrize("unsolicited", [False, True])
async def test_final_request_never_copies_compiler_protected_id_and_merge_retains_it(unsolicited):
    package = typed_package().review_context()
    lesson = {"lesson_content": "The difference is 20 and total is 220."}
    compiled = review.compiled_solution_evidence(lesson, package)
    original = whole_review(compiled)
    original.calculations[0].claim_ids.insert(0, "n1")
    before = original.model_dump(mode="json")
    protected = compiled.calculations[0].claim_ids[0]
    first = {**compiled.calculations[0].model_dump(exclude_none=True), "claim_ids": ["n1"]}
    second = {**first, "expression": "receipts + revenue", "claimed_result": 220, "claimed_literal": "220"}
    if unsolicited:
        first["claim_ids"].append(protected)
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data={"calculations": [first, second]})))
    factory = Mock(return_value=client)
    errors, response, _ = await review._repair_packaged_evidence(original, lesson,
        context={"lesson_package": package}, grounding_errors=["Unrecognized diagnostic"],
        workload_error=None, client_factory=factory)
    assert bool(errors) is unsolicited
    assert bool(response.error) is unsolicited
    body = json.loads(client.generate_json.call_args.kwargs["user_prompt"])
    assert set(body["numeric_spans"]) == {"n1"}
    assert [entry["claim_ids"] for entry in body["prior_evidence"]["calculations"]] == [["n1"]]
    schema = client.generate_json.call_args.kwargs["output_model"].model_json_schema()
    assert schema["$defs"]["SourceClaimId"]["enum"] == ["n1"]
    for entry in body["prior_evidence"]["calculations"]:
        assert review.PackagedCalculationCheck.model_validate(entry)
        assert "location" not in entry and "source_quote" not in entry and "absolute_tolerance" not in entry
    assert original.model_dump(mode="json") == before
    if not unsolicited:
        kept = response.data["calculations"][:len(compiled.calculations)]
        assert [item["claim_ids"] for item in kept] == [item.claim_ids for item in compiled.calculations]
    factory.assert_called_once_with(tier="balanced", timeout=90, max_tokens=4000,
                                    thinking_level="low", allow_fallback=False)
    assert client.generate_json.await_count == 1


def test_missing_ids_are_unassigned_only_not_a_verdict_about_existing_evidence():
    prior = review._scoped_prior_evidence(PackageReview.model_validate(approved(check(result=999))), {"n1", "n9"})
    aids = review._evidence_copy_aids(prior, {"n1": "The difference is 20.", "n9": "Write 5 sentences."})
    assert aids == {"missing_claim_ids": ["n9"]}
    assert prior["calculations"][0]["claimed_result"] == 999  # No corrected proof synthesized.


def test_unbound_legacy_calculation_is_diagnostic_only_and_never_an_invalid_copy_template():
    original = review.LessonReview(acceptable=True, issues=[], practice_minutes=40,
        contains_calculations=True, calculations=[
            {"location": "n1", "claim_ids": ["n1"], "expression": "120 - 100", "claimed_result": 20},
            {"location": "unbound private quotation", "expression": "120 - 100", "claimed_result": 20}])
    before = original.model_dump(mode="json")
    assert review._scoped_prior_evidence(original, {"n1"})["calculations"] == []
    assert original.model_dump(mode="json") == before


@pytest.mark.parametrize("quote,source,count,numerals,matching", [
    ("divide by 2", "Divide then divide by 2.", 1, 1, 1),
    ("divide by", "Please divide by 2.", 1, 0, 0),
    ("divide by 2", "divide by 2 then divide by 2", 2, 1, 1),
    ("divide by 2", "Divide by 2.", 0, 1, 1),
    ("divide by 2 or 100", "divide by 2 or 100", 1, 2, 1),
    ("բաժանիր 2-ի", "Խնդրում ենք բաժանիր 2-ի։", 1, 1, 1),
])
def test_quote_aids_report_only_exact_counts_and_preserve_original_quote(quote, source, count, numerals, matching):
    original = PackageReview.model_validate(approved(math_roles=[role(quote=quote, kind="divisor")]))
    prior = review._scoped_prior_evidence(original, {"n1"})
    aids = review._evidence_copy_aids(prior, {"n1": source})
    assert aids == {"math_role_quote_checks": [{"prior_math_role_index": 0, "claim_id": "n1",
        "quote_occurrences_in_span": count, "quote_numerals": numerals, "matching_coefficient_numerals": matching}]}
    assert prior["math_roles"][0]["source_quote"] == original.math_roles[0].source_quote == quote


def test_lexically_valid_quote_aid_cannot_approve_wrong_role_owner_or_scaled_coefficient():
    for source, evidence in [
        ("Please divide by 2.", role(quote="divide by 2", kind="inverse_multiplier")),
        ("Please divide by 2.", role(quote="divide by 2", kind="divisor", case="practice.transfer")),
        ("Please divide by 2%.", role(quote="divide by 2", kind="divisor")),
    ]:
        original = PackageReview.model_validate(approved(math_roles=[evidence]))
        aids = review._evidence_copy_aids(review._scoped_prior_evidence(original, {"n1"}), {"n1": source})
        assert aids["math_role_quote_checks"][0]["matching_coefficient_numerals"] == 1
        assert role_failures(package_for(source), [evidence])


def test_copy_aids_have_aggregate_utf8_bound_and_omit_whole_oversize_missing_list():
    roles = [role(span=f"n{i}", quote="բաժանիր 2-ի", kind="divisor") for i in range(80)]
    original = PackageReview.model_validate(approved(math_roles=roles))
    spans = {f"n{i}": "Խնդրում ենք բաժանիր 2-ի։" for i in range(80)}
    prior = review._scoped_prior_evidence(original, set(spans))
    aids = review._evidence_copy_aids(prior, spans)
    assert len(aids["math_role_quote_checks"]) == review.MAX_MATH_ROLE_QUOTE_CHECKS == 16
    assert len(encoded({"prior_evidence_copy_aids": aids})) <= review.MAX_EVIDENCE_COPY_AID_BYTES == 4096
    oversized = {f"n{i}" + "ա" * 100: "A reference." for i in range(80)}
    omitted = review._evidence_copy_aids(review._scoped_prior_evidence(original, set()), oversized)
    assert omitted == {}  # No partial missing-ID list or truncated exact source text.


def test_first_evidence_request_has_no_redundant_copy_aids_or_schema_fields():
    package = package_with_spans("Receipts exceed revenue by 20.")
    payload = package_review_payload(package, {}, {})
    request, _ = _evidence_patch_request(PackageReview.model_validate(approved()), payload, [])
    body = json.loads(request["user_prompt"])
    assert "prior_evidence_copy_aids" not in body
    assert "prior_evidence_copy_aids" not in request["output_model"].model_json_schema()["properties"]
