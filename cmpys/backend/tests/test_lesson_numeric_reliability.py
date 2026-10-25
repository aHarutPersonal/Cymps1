"""Observed multilingual and multi-claim review failures stay closed."""
import copy

import pytest

from app.services.planning.lesson_package import LessonPackage, validate_derivation
from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
from tests.lesson_package_fixtures import package_payload


PACKAGE = {"teaching_cases": [{"id": "case", "data": [
    {"id": "first", "label": "First input", "value": 10},
    {"id": "second", "label": "Second input", "value": 20},
]}]}


def review(**kwargs):
    return LessonReview(acceptable=True, issues=[], practice_minutes=30,
                        contains_calculations=bool(kwargs.get("calculations")), **kwargs)


def check(ids=None, value=30):
    return {"location": "total", "claim_ids": ids or ["n1"],
            "case_id": "teaching.case", "expression": "first + second", "claimed_result": value}


@pytest.mark.parametrize("text", [
    "Total is 30, and the other total is 99.",
    "Գումարը 30 է։ Մյուս գումարը 99 է։",
    "Total is 30; the other total is 99.",
])
def test_one_correct_calculation_cannot_approve_an_unchecked_result(text):
    verdict = review(calculations=[check()])
    assert grounded_failures(verdict, {"lesson_content": text}, copy.deepcopy(PACKAGE))


def test_armenian_full_stop_splits_claims_without_splitting_decimals():
    spans = numeric_spans({"lesson_content": "Առաջինը 3.50 է։Երկրորդը 4.25 է։"})
    assert list(spans.values()) == ["Առաջինը 3.50 է։", "Երկրորդը 4.25 է։"]


def test_financial_multiplier_is_not_omitted_from_numeric_inventory():
    assert numeric_spans({"lesson_content": "Debt coverage is 3.5x."}) == {"n1": "Debt coverage is 3.5x."}


def test_non_english_result_cannot_be_exempted_as_an_unknown_literal_fact():
    assert grounded_failures(review(calculations=[], literal_fact_ids=["n1"]),
                             {"lesson_content": "Գումարը 999 է։"}, copy.deepcopy(PACKAGE))


def test_armenian_definite_suffix_preserves_bound_fact_label():
    context = {"teaching_cases": [{"id": "cafe", "data": [
        {"label": "Կանխիկ վաճառք", "value": 900000}]}]}
    assert not grounded_failures(review(calculations=[], literal_fact_ids=["n1"]),
                                 {"lesson_content": "Կանխիկ վաճառքը 900000 դրամ է։"}, context)


def test_each_result_in_same_sentence_can_be_verified_and_inputs_remain_allowed():
    verdict = review(calculations=[check(), {**check(value=10), "expression": "second-first"}])
    text = "The total of 10 and 20 is 30, and the difference is 10."
    assert not grounded_failures(verdict, {"lesson_content": text}, copy.deepcopy(PACKAGE))
    assert not verdict.failures()


def test_field_ordinal_does_not_require_a_second_calculation():
    verdict = review(calculations=[check()])
    assert not grounded_failures(verdict, {"lesson_content": "Field 1: Total is 30."}, copy.deepcopy(PACKAGE))


@pytest.mark.parametrize("text", ["First input: 10.", "Budget about 20 minutes for practice.",
                                 "1. Budget about 8 minutes for practice.",
                                 "Spend 8–10 minutes on the supplied task.",
                                 "Spend 8-10 minutes on the supplied task.",
                                 "Write 80–120 words explaining your conclusion.",
                                 "Գրեք 80–120 բառանոց բացատրություն։",
                                 "Աշխատեք 15 րոպեի ընթացքում։",
                                 "Աշխատանքի համար հատկացրեք 20 րոպե։"])
def test_bound_inputs_and_narrow_workload_metadata_are_accepted(text):
    assert not grounded_failures(review(calculations=[], literal_fact_ids=["n1"]),
                                 {"lesson_content": text}, copy.deepcopy(PACKAGE))


@pytest.mark.parametrize("text", ["Profit is 999; write 80–120 words explaining it.",
                                 "Գումարը 999 է, գրեք 80–120 բառանոց բացատրություն։"])
def test_workload_unit_cannot_exempt_an_unrelated_result(text):
    assert grounded_failures(review(calculations=[], literal_fact_ids=["n1"]),
                             {"lesson_content": text}, copy.deepcopy(PACKAGE))


@pytest.mark.parametrize("text", [
    "### Քայլ 1 — Կարդացեք տվյալները", "**Փուլ 2**", "Հարց 3: Բացատրեք ընտրությունը",
    "Վարժություն 4. Կարդացեք հրահանգը", "### Step 1 — Read the inputs",
    "**Հարց 3․ Բացատրեք ընտրությունը**",
])
def test_explicit_localized_heading_ordinals_are_not_numeric_claims(text):
    assert numeric_spans({"lesson_content": text}) == {}


@pytest.mark.parametrize("text", [
    "### Քայլ 1 — Աշխատեք 8–10 րոպե", "**Փուլ 2** — 12-15 րոպե",
    "Հարց 3: Գրեք 2–3 նախադասությամբ պատասխան 8 րոպեի ընթացքում։",
    "Spend 10 minutes writing 80–120 words and 3 sentences.",
    "Spend 8 - 10 minutes explaining the difference in 2 - 3 sentences.",
    "Գրեք 3 նախադասությամբ պատասխան, օգտագործելով 8–10 րոպե։",
    "Փուլ 2 — Դեպքի տվյալների համեմատություն (12–15 րոպե)",
    "**Փուլ 2․ Դեպքի տվյալների համեմատություն (12–15 րոպե)**",
    "Գրավոր բացատրություն՝ 2–3 նախադասությամբ (մոտ 8 րոպե), ապա ստուգում։",
])
def test_structural_ordinals_and_multiple_bounded_workload_units_are_metadata(text):
    spans = numeric_spans({"lesson_content": text})
    assert spans
    assert not grounded_failures(review(calculations=[], literal_fact_ids=list(spans)),
                                 {"lesson_content": text}, copy.deepcopy(PACKAGE))


@pytest.mark.parametrize("text", [
    "### Քայլ 1 — Գումարը 999 է, աշխատեք 8–10 րոպե։",
    "Spend 10 minutes writing 80–120 words; profit is 999.",
    "Write 21 sentences in 8 minutes.", "Write 0 sentences in 8 minutes.",
    "Write 3 sentences in 181 minutes.", "Write 5001 words in 8 minutes.",
    "Write 120–80 words in 8 minutes.", "Write -3 sentences in 8 minutes.",
    "Spend 10 minutes and use 999.",
    "10 minutes + 20 minutes = 30 minutes.", "20 minutes - 10 minutes = 10 minutes.",
    "10 minutes therefore 40 minutes.", "10 minutes calculated as 40 minutes.",
])
def test_metadata_does_not_hide_extra_or_unbounded_quantities(text):
    spans = numeric_spans({"lesson_content": text})
    assert spans
    assert grounded_failures(review(calculations=[], literal_fact_ids=list(spans)),
                             {"lesson_content": text}, copy.deepcopy(PACKAGE))


def test_original_parenthesized_datum_label_is_a_valid_exact_alias():
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "receipts", "label": "Current (cash) receipts", "value": 700}]}]}
    assert not grounded_failures(review(calculations=[], literal_fact_ids=["n1"]),
                                 {"lesson_content": "Current (cash) receipts: 700."}, package)


def fact(claim_id="n1", case_id="teaching.case", datum_ids=None):
    return {"claim_id": claim_id, "case_id": case_id, "datum_ids": datum_ids or ["first", "second"]}


@pytest.mark.parametrize("text", [
    "The opening amount is 10 and the following amount is 20.",
    "Սկզբնական արժեքը 10 է, իսկ հաջորդ արժեքը՝ 20։",
    "Inputs: (1) opening amount 10, (2) following amount 20, (3) compare both amounts.",
    "(1) opening amount 10, (2) following amount 20, (3) compare both amounts.",
    "### Քայլ 1 — Սկզբնական արժեքը 10 է, իսկ հաջորդը՝ 20; գրեք 2–3 նախադասությամբ։",
    "Opening amount 10, following amount 20; explain the difference in 2 - 3 sentences and 8 - 10 minutes.",
])
def test_explicit_fact_evidence_binds_paraphrases_and_ordered_inline_lists(text):
    verdict = review(calculations=[], literal_facts=[fact()])
    assert not grounded_failures(verdict, {"lesson_content": text}, copy.deepcopy(PACKAGE))
    assert not verdict.failures()


@pytest.mark.parametrize("proof", [
    fact(case_id="teaching.unknown"), fact(datum_ids=["first", "unknown"]),
    fact(claim_id="n999"), fact(datum_ids=["first"]),
])
def test_fact_evidence_requires_exact_known_ids_and_all_values(proof):
    assert grounded_failures(review(calculations=[], literal_facts=[proof]),
                             {"lesson_content": "Opening amount 10 and following amount 20."}, copy.deepcopy(PACKAGE))


def test_fact_evidence_cannot_read_a_datum_from_another_known_case():
    package = copy.deepcopy(PACKAGE)
    package["teaching_cases"].append({"id": "other", "data": [
        {"id": "first", "label": "First input", "value": 100},
        {"id": "second", "label": "Second input", "value": 200}]})
    assert grounded_failures(review(calculations=[], literal_facts=[fact(case_id="teaching.other")]),
                             {"lesson_content": "Opening amount 10 and following amount 20."}, package)


def test_facts_and_calculation_cannot_bind_different_cases_with_coincident_results():
    package = copy.deepcopy(PACKAGE)
    package["teaching_cases"].append({"id": "other", "data": [
        {"id": "first", "label": "Other first", "value": 12},
        {"id": "second", "label": "Other second", "value": 18}]})
    verdict = review(literal_facts=[fact()], calculations=[{**check(), "case_id": "teaching.other"}])
    assert grounded_failures(verdict, {"lesson_content": "Opening amount 10 and following amount 20 make 30."}, package)


def test_qualitative_package_does_not_exempt_an_unsupported_numeric_fact():
    assert grounded_failures(review(calculations=[], literal_fact_ids=["n1"]),
                             {"lesson_content": "Գումարը 999 է։"}, {"teaching_cases": []})


@pytest.mark.parametrize("text", [
    "Opening amount 10 and following amount 20; extra amount 999.",
    "Opening amount 10 and following amount 20 (+30).",
    "Opening amount 10 and following amount 20 (+10).",
    "Opening amount 10 and following amount 20; difference 10.",
    "Opening amount 10 and following amount 20; the difference is 10.",
    "Opening amount 10 and following amount 20: 10 + 20 = 30.",
    "Inputs: (1) opening amount 10, (3) following amount 20.",
    "Inputs: (2) opening amount 10, (3) following amount 20.",
    "Opening amount 10, following amount 20, and an unexplained amount (3).",
])
def test_raw_fact_proof_cannot_hide_results_or_arbitrary_parenthesized_numbers(text):
    assert grounded_failures(review(calculations=[], literal_facts=[fact()]),
                             {"lesson_content": text}, copy.deepcopy(PACKAGE))


def test_fact_evidence_cannot_claim_an_absent_datum_or_cover_another_span():
    verdict = review(calculations=[], literal_facts=[fact()])
    assert grounded_failures(verdict, {"lesson_content": "Opening amount 10. Following amount 20."}, copy.deepcopy(PACKAGE))


def test_fact_evidence_does_not_allow_mixing_case_values_to_cover_a_span():
    package = copy.deepcopy(PACKAGE)
    package["teaching_cases"].append({"id": "other", "data": [
        {"id": "third", "label": "Third input", "value": 999}]})
    verdict = review(calculations=[], literal_facts=[
        fact(), fact(case_id="teaching.other", datum_ids=["third"])])
    assert grounded_failures(verdict, {"lesson_content": "Opening amount 10 and following amount 20; extra 999."}, package)


@pytest.mark.parametrize("expression,expected_failure", [("second-first", False), ("first+second", True)])
def test_fact_and_calculation_evidence_jointly_verify_delta_without_weakening_math(expression, expected_failure):
    verdict = review(literal_facts=[fact()], calculations=[{**check(value=10), "expression": expression}])
    failures = grounded_failures(verdict, {"lesson_content": "Opening amount 10 and following amount 20 (+10)."}, copy.deepcopy(PACKAGE))
    assert not failures
    assert bool(verdict.failures()) == expected_failure


def test_partial_calculation_plus_facts_still_rejects_unchecked_extra_result():
    verdict = review(literal_facts=[fact()], calculations=[check()])
    assert grounded_failures(verdict,
                             {"lesson_content": "Opening amount 10 and following amount 20 make 30, with extra 999."}, copy.deepcopy(PACKAGE))


@pytest.mark.parametrize("text", [
    "Opening amount 10 and following amount 20 (+10), with total 30.",
    "Opening amount 10 and following amount 20; difference is 10 and total is 30.",
    "Opening amount 10 and following amount 20; profit is 10 and total is 30.",
])
def test_one_valid_result_cannot_conceal_a_derived_value_equal_to_a_raw_input(text):
    verdict = review(literal_facts=[fact()], calculations=[check()])
    assert grounded_failures(verdict, {"lesson_content": text}, copy.deepcopy(PACKAGE))


@pytest.mark.parametrize("label", ["profit", "margin", "total", "result", "net cash", "discount", "premium"])
def test_typed_fact_cannot_mislabel_a_derived_result_as_an_input_with_the_same_value(label):
    verdict = review(calculations=[], literal_facts=[fact(datum_ids=["first"])])
    assert grounded_failures(verdict, {"lesson_content": f"The {label} is 10."}, copy.deepcopy(PACKAGE))


def test_derived_signaling_retains_the_entire_decimal_value():
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "first", "label": "First input", "value": 33.3}]}]}
    verdict = review(calculations=[], literal_facts=[fact(datum_ids=["first"])])
    assert grounded_failures(verdict, {"lesson_content": "The margin is 33.3%."}, package)


@pytest.mark.parametrize("label", ["Profit", "Operating profit", "Gross margin", "Discount"])
def test_typed_raw_profit_requires_the_bound_datum_label_not_another_cases_label(label):
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "first", "label": label, "value": 10},
        {"id": "second", "label": "Revenue", "value": 10}]}]}
    assert not grounded_failures(review(calculations=[], literal_facts=[fact(datum_ids=["first"])]),
                                 {"lesson_content": f"The {label} is 10."}, package)
    assert grounded_failures(review(calculations=[], literal_facts=[fact(datum_ids=["second"])]),
                             {"lesson_content": f"The {label} is 10."}, package)


def test_an_earlier_raw_label_cannot_exempt_an_unrelated_later_result_signal():
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "first", "label": "Operating profit", "value": 10}]}]}
    assert grounded_failures(review(calculations=[], literal_facts=[fact(datum_ids=["first"])]),
                             {"lesson_content": "Operating profit is 10; the result is 10."}, package)


COMPARATIVE_PACKAGE = {"teaching_cases": [{"id": "case", "data": [
    {"id": "receipts", "label": "Cash receipts", "value": 110},
    {"id": "revenue", "label": "Current revenue", "value": 100},
    {"id": "prior_receipts", "label": "Prior-period receipts", "value": 30},
]}]}


@pytest.mark.parametrize("text", [
    "Cash receipts (110) exceed current revenue (100) by 30.",
    "Դրամական մուտքը (110) գերազանցում է ընթացիկ հասույթը (100) 30 դրամով։",
    "Դրամական մուտքերը (110) գերազանցում են ընթացիկ հասույթը (100) 30 AMD-ով։",
])
@pytest.mark.parametrize("proof_kind", ["literal_ids", "typed_facts", "typed_and_other_calc", "other_calc_only"])
def test_comparative_excess_equal_to_raw_fact_still_requires_its_own_calculation(text, proof_kind):
    # The raw prior-period collection is 30; the actual net excess is 10.
    # This was a real private-solution failure, hidden by a plausible raw value.
    text = text.rstrip(".։")
    facts = [fact(datum_ids=["receipts", "revenue", "prior_receipts"])]
    kwargs = {"calculations": []}
    if proof_kind == "literal_ids":
        kwargs["literal_fact_ids"] = ["n1"]
    elif proof_kind != "other_calc_only":
        kwargs["literal_facts"] = facts
    if proof_kind in {"typed_and_other_calc", "other_calc_only"}:
        text += "; another verified sum is 210"
        kwargs["calculations"] = [{"location": "sum", "claim_ids": ["n1"],
            "case_id": "teaching.case", "expression": "receipts + revenue", "claimed_result": 210}]
    assert grounded_failures(review(**kwargs), {"lesson_content": text}, copy.deepcopy(COMPARATIVE_PACKAGE))


@pytest.mark.parametrize("language", ["en", "hy"])
@pytest.mark.parametrize("claimed", [10, 30])
def test_comparative_excess_requires_recomputed_difference(language, claimed):
    text = (f"Cash receipts (110) exceed current revenue (100) by {claimed}." if language == "en" else
            f"Դրամական մուտքը (110) գերազանցում է ընթացիկ հասույթը (100) {claimed} դրամով։")
    verdict = review(calculations=[{"location": "excess", "claim_ids": ["n1"],
        "case_id": "teaching.case", "expression": "receipts - revenue", "claimed_result": claimed}],
        literal_facts=[fact(datum_ids=["receipts", "revenue"])])
    assert not grounded_failures(verdict, {"lesson_content": text}, copy.deepcopy(COMPARATIVE_PACKAGE))
    assert bool(verdict.failures()) == (claimed == 30)


def test_comparative_vocabulary_without_an_asserted_amount_does_not_invent_a_result():
    text = "Cash receipts (110) exceed current revenue (100); explain why using prior receipts (30)."
    verdict = review(calculations=[], literal_facts=[fact(datum_ids=["receipts", "revenue", "prior_receipts"])])
    assert not grounded_failures(verdict, {"lesson_content": text}, copy.deepcopy(COMPARATIVE_PACKAGE))


def test_bound_duration_facts_remain_visible_even_though_they_use_time_units():
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "first", "label": "Initial interval", "value": 10},
        {"id": "second", "label": "Following interval", "value": 20}]}]}
    assert not grounded_failures(review(calculations=[], literal_facts=[fact()]),
                                 {"lesson_content": "The first interval lasts 10 minutes and the second lasts 20 minutes."}, package)


@pytest.mark.parametrize("text", [
    "The pump empties the tank in 10 minutes.",
    "Step 1: The pump empties the tank in 10 minutes.",
    "Write 20 words explaining why the pump empties the tank in 10 minutes.",
    "Spend 5 minutes explaining why the pump empties the tank in 10 minutes.",
])
def test_domain_duration_is_not_workload_metadata(text):
    package = {"teaching_cases": [{"id": "tank", "data": [
        {"id": "tank_volume", "label": "Tank volume", "value": 100},
        {"id": "pump_rate", "label": "Pump rate", "value": 4}]}]}
    assert grounded_failures(review(calculations=[], literal_fact_ids=["n1"]),
                             {"lesson_content": text}, package)


def test_disguised_literal_answers_are_rejected_but_unit_constants_are_allowed():
    with pytest.raises(ValueError, match="named facts"):
        validate_derivation("cash * 0 + 999", {"cash": 900000})
    assert validate_derivation("profit / receipts * 100", {"profit": 20, "receipts": 80}) == 25


@pytest.mark.parametrize("expression", ["cash * 0 + 100", "cash-cash+1", "cash/cash*100", "0/cash+2"])
def test_source_fact_cannot_be_cancelled_to_disguise_a_constant(expression):
    with pytest.raises(ValueError, match="meaningfully"):
        validate_derivation(expression, {"cash": 900000})


def test_compact_review_context_keeps_all_private_evidence_once():
    package = LessonPackage.model_validate(package_payload())
    context = package.review_context()
    assert "practice" not in context
    assert context["private_workbook"] == package.workbook.model_dump(mode="json")
    assert context["teaching_cases"] == package.writer_context()["teaching_cases"]


@pytest.mark.asyncio
async def test_package_transport_timeout_uses_existing_retry_without_changing_prompt(monkeypatch):
    from types import SimpleNamespace
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_package import generate_package
    from tests.section_client_fixture import structured_package_fixture
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    monkeypatch.setattr("app.services.planning.lesson_package.asyncio.sleep", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data={}, error="zai request failed (TimeoutError; finish=missing)"),
        LLMResponse(data=structured_package_fixture(package_payload())),
    ]))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kw: client)
    assert package is not None and response.error is None
    first, second = client.generate_json.await_args_list
    assert first.kwargs == second.kwargs


@pytest.mark.asyncio
@pytest.mark.parametrize("error,attempts", [
    ("zai request failed (TimeoutError; finish=missing)", 2),
    ("zai request failed (AuthenticationError; finish=missing)", 1),
])
async def test_package_transport_recovery_is_bounded_and_skips_permanent_errors(monkeypatch, error, attempts):
    from types import SimpleNamespace
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_package import generate_package
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    monkeypatch.setattr("app.services.planning.lesson_package.asyncio.sleep", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data={}, error=error)))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kw: client)
    assert package is None and response.error
    assert client.generate_json.await_count == attempts


@pytest.mark.asyncio
async def test_invalid_review_proof_is_not_misclassified_as_a_content_rewrite(monkeypatch):
    from types import SimpleNamespace
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_review import review_lesson
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    invalid = review(calculations=[{**check(value=1), "expression": "1"}]).model_dump()
    invalid_patch = {"calculations": [{key: value for key, value in invalid["calculations"][0].items()
                                      if key in {"claim_ids", "case_id", "expression", "claimed_result"}}]}
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=copy.deepcopy(invalid)), LLMResponse(data=invalid_patch)]))
    failures, response, _ = await review_lesson(
        {"lesson_content": "Heading 1: examine the inputs."},
        client_factory=lambda **kw: client, context={"lesson_package": copy.deepcopy(PACKAGE)})
    assert client.generate_json.await_count == 2
    assert failures
    assert response.error == "Lesson review evidence patch validation failed"
    first, second = client.generate_json.await_args_list
    assert "Heading 1: examine the inputs." in second.kwargs["user_prompt"]
    assert second.kwargs["output_model"].__name__ == "ReviewEvidencePatch"


@pytest.mark.asyncio
@pytest.mark.parametrize("semantic_issue", [None, "The explanation contradicts the supplied facts."])
async def test_typed_fact_evidence_preserves_the_independent_semantic_verdict(semantic_issue):
    from types import SimpleNamespace
    from unittest.mock import AsyncMock
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_review import review_lesson
    payload = review(calculations=[], literal_facts=[fact()]).model_dump()
    if semantic_issue:
        payload.update(acceptable=False, issues=[semantic_issue])
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=payload)))
    failures, response, _ = await review_lesson(
        {"lesson_content": "Opening amount 10 and following amount 20."},
        client_factory=lambda **kw: client, context={"lesson_package": copy.deepcopy(PACKAGE)})
    assert failures == ([semantic_issue] if semantic_issue else [])
    assert response.data["literal_facts"] == [fact()]
    assert response.error is None
    client.generate_json.assert_awaited_once()
