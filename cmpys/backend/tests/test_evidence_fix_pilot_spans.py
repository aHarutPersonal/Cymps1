"""Numeric evidence checks on real pilot fragments (29 Oct 2026 smoke pilot).

Each fix has the recorded fragment that was wrongly rejected and a genuinely
wrong number in the same shape that must still be rejected.
"""
import copy
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.evidence_resolver import package_cases, resolve_literal_evidence
from app.services.planning.lesson_review import (
    LessonReview, grounded_failures, numeric_spans, review_lesson, source_equation_failures,
)


def review(*, calculations=(), literal_facts=(), literal_fact_ids=(), math_roles=()):
    return LessonReview.model_validate({
        "acceptable": True, "issues": [], "practice_minutes": 3,
        "contains_calculations": bool(calculations),
        "calculations": [{**check, "location": ", ".join(check["claim_ids"])} for check in calculations],
        "literal_facts": list(literal_facts), "literal_fact_ids": list(literal_fact_ids),
        "math_roles": list(math_roles)})


def claim_for(lesson, package, fragment):
    ids = [key for key, span in numeric_spans(lesson, package).items() if fragment in span]
    assert len(ids) == 1, (fragment, numeric_spans(lesson, package))
    return ids[0]


def failures(verdict, lesson, package, claim_id):
    """Gate failures for one span plus the verdict's own arithmetic checks."""
    return grounded_failures(verdict, lesson, package, expected_claim_ids={claim_id}) + verdict.failures()


# --- 2. Signed steps/waterfall rows ----------------------------------------

CORNER_CUP = {"id": "corner_cup_week", "data": [
    {"id": "cash_sales", "label": "Cash sales collected this week", "value": 300.0, "unit": "USD"},
    {"id": "credit_sales_unpaid", "label": "Credit sales earned this week, not yet collected", "value": 500.0, "unit": "USD"},
    {"id": "expenses_incurred_unpaid", "label": "Expenses incurred this week, not yet paid", "value": 200.0, "unit": "USD"},
    {"id": "expenses_paid_this_week", "label": "Cash paid this week for expenses incurred this week", "value": 150.0, "unit": "USD"},
], "results": [{"id": "accrual_profit", "expression": "(cash_sales + credit_sales_unpaid) - "
                "(expenses_incurred_unpaid + expenses_paid_this_week)", "unit": "USD"}]}
STEPS = """## Worked Example

```steps
title: Corner Cup week, accrual profit
unit: USD
Cash sales | 300 | Earned and collected, counts in both measures.
+ Credit sales earned, unpaid | 500 | Earned this week, so it is revenue even though no cash arrived.
− Expenses incurred, unpaid | {unpaid} | Incurred this week, so it cuts profit even though not yet paid.
− Expenses paid this week | −150 | Incurred and paid this week, so it cuts both profit and cash.
= Accrual profit | 450
```
"""
SUNRISE = {"id": "sunrise_cafe_month", "data": [
    {"id": "cash_collected", "label": "Cash actually collected from customers this month", "value": 6100.0},
    {"id": "supplies_paid", "label": "Cash paid to suppliers this month", "value": 2900.0},
    {"id": "wages_paid", "label": "Cash paid to staff this month", "value": 1900.0},
]}
WATERFALL = """```chart
type: {kind}
title: Cash view of the same month
unit: $
Collected | 6100
−Suppliers | −2900
−Staff | −1900
= Net cash | 1300
```
"""


def corner_cup(row_value="−200"):
    return {"lesson_content": STEPS.format(unpaid=row_value)}, {"teaching_cases": [CORNER_CUP]}


def unpaid_fact(claim_id, datum="expenses_incurred_unpaid"):
    return {"claim_id": claim_id, "case_id": "teaching.corner_cup_week", "datum_ids": [datum]}


@pytest.mark.parametrize("as_ids", [False, True])
def test_signed_steps_row_matches_its_positive_datum(as_ids):
    lesson, package = corner_cup()
    for fragment, datum in (("Expenses incurred, unpaid", "expenses_incurred_unpaid"),
                            ("Expenses paid this week", "expenses_paid_this_week")):
        claim_id = claim_for(lesson, package, fragment)
        # The repair round also listed the IDs as untyped literal_fact_ids.
        verdict = review(literal_facts=[unpaid_fact(claim_id, datum)],
                         literal_fact_ids=[claim_id] if as_ids else [])
        assert failures(verdict, lesson, package, claim_id) == []


def test_signed_waterfall_row_matches_its_positive_datum():
    lesson, package = {"lesson_content": WATERFALL.format(kind="waterfall")}, {"teaching_cases": [SUNRISE]}
    for fragment, datum in (("−Suppliers", "supplies_paid"), ("−Staff", "wages_paid")):
        claim_id = claim_for(lesson, package, fragment)
        verdict = review(literal_facts=[{"claim_id": claim_id, "case_id": "teaching.sunrise_cafe_month",
                                         "datum_ids": [datum]}])
        assert failures(verdict, lesson, package, claim_id) == []


def test_wrong_signed_row_value_is_still_rejected():
    lesson, package = corner_cup("−250")
    claim_id = claim_for(lesson, package, "Expenses incurred, unpaid")
    errors = failures(review(literal_facts=[unpaid_fact(claim_id)]), lesson, package, claim_id)
    assert f"{claim_id}: bound datum values are absent from the source span" in errors


def test_total_row_keeps_its_sign():
    lesson = {"lesson_content": STEPS.format(unpaid="−200").replace("= Accrual profit | 450", "= Accrual profit | −200")}
    package = {"teaching_cases": [CORNER_CUP]}
    claim_id = claim_for(lesson, package, "= Accrual profit")
    errors = failures(review(literal_facts=[unpaid_fact(claim_id)]), lesson, package, claim_id)
    assert f"{claim_id}: bound datum values are absent from the source span" in errors


@pytest.mark.parametrize("content", [
    "Unpaid expenses were −200 this week.",  # Prose keeps its sign.
    WATERFALL.format(kind="bars").replace("−Suppliers | −2900", "Expenses | −200"),  # Bars are not signed steps.
    "| Expenses | −200 |",  # A markdown table row is not a steps row.
])
def test_sign_outside_steps_or_waterfall_rows_is_unchanged(content):
    lesson, package = {"lesson_content": content}, {"teaching_cases": [CORNER_CUP]}
    claim_id = claim_for(lesson, package, "200")
    errors = failures(review(literal_facts=[unpaid_fact(claim_id)]), lesson, package, claim_id)
    assert f"{claim_id}: bound datum values are absent from the source span" in errors


def test_signed_row_cannot_hide_an_unbound_value():
    lesson, package = corner_cup()
    claim_id = claim_for(lesson, package, "Expenses incurred, unpaid")
    # A datum of 150 is in the case, but the row shows 200: binding the wrong datum fails.
    errors = failures(review(literal_facts=[unpaid_fact(claim_id, "expenses_paid_this_week")]),
                      lesson, package, claim_id)
    assert errors


# --- 3. Units in equations ---------------------------------------------------

def garden_activity(solution, *, area_unit="m²", data_unit="meters"):
    return {"id": "guided", "kind": "guided", "instructions": "Find the area.", "hint": "",
            "worked_solution": solution,
            "data": [{"id": "base", "label": "Length of the side chosen as the base", "value": 6.0, "unit": data_unit},
                     {"id": "height", "label": "Perpendicular distance from the opposite vertex to the base line",
                      "value": 4.0, "unit": data_unit}],
            "fields": [{"id": "area", "label": "Area of the garden plot (square meters)", "kind": "number",
                        "unit": area_unit, "expression": "(base * height) / 2"}]}


def garden(solution, **units):
    return {"teaching_cases": [], "private_workbook": {"activities": [garden_activity(solution, **units)]}}


def area_check(claim_id, expression="(6 * 4) / 2", result=12):
    return {"claim_ids": [claim_id], "case_id": "practice.guided", "expression": expression, "claimed_result": result}


GARDEN_SENTENCE = "So the area is (6 m × 4 m) / 2 = 12 square meters."


@pytest.mark.parametrize("evidence", ["calculation", "calculation_and_facts"])
def test_declared_operand_and_result_units_are_parsed(evidence):
    package = garden(GARDEN_SENTENCE)
    claim_id = claim_for({}, package, "(6 m × 4 m)")
    facts = [{"claim_id": claim_id, "case_id": "practice.guided", "datum_ids": ["base", "height"]}]
    verdict = (review(calculations=[area_check(claim_id)]) if evidence == "calculation" else
               review(calculations=[area_check(claim_id, "6.0 * 4.0 / 2")], literal_facts=facts,
                      literal_fact_ids=[claim_id]))
    assert failures(verdict, {}, package, claim_id) == []


@pytest.mark.parametrize("sentence,result", [
    ("So the area is (6 m × 4 m) / 2 = 13 square meters.", 13),  # Wrong result.
    ("So the area is (6 m × 4 m) / 2 = 13 square meters.", 12),  # Reviewer claims the right answer.
    ("So the area is (6 cm × 4 m) / 2 = 12 square meters.", 12),  # Undeclared operand unit.
    ("So the area is (6 m × 4 m) / 2 = 12 m.", 12),  # Wrong result unit.
    ("So the area is (6 m × 4 m) / 2 = 12 square meters thousand.", 12),  # Scale after unit.
    ("So the area is (6 m × 4 m) / 3 = 12 square meters.", 12),  # Arithmetic does not hold.
])
def test_wrong_number_or_unit_in_unit_equation_is_rejected(sentence, result):
    package = garden(sentence)
    claim_id = claim_for({}, package, "(6 ")
    assert failures(review(calculations=[area_check(claim_id, result=result)]), {}, package, claim_id)


ARMENIAN = (
    "Հորինված ուսուցողական օրինակ։ Ուղիմանկյուն հովանոցի կողմնային երեսը եռանկյուն է՝ հիմքը 10 մ, "
    "հիմքին ուղղահայաց բարձրությունը 5 մ։ Քայլերով․\n"
    "1) Գտնում ենք հիմքին ուղղահայաց բարձրությունը՝ 5 մ (ոչ թե թեք կողմը)։\n"
    "2) Բազմապատկում ենք հիմքը բարձրությամբ՝ 10 × 5 = 50։\n"
    "3) Կիսում ենք, որովհետև եռանկյունը ուղղանկյան կեսն է՝ 50 / 2 = {half} քառակուսի մետր։\n\n"
    "Այս դեպքում հիմքը 6 մ է, իսկ ուղղահայաց բարձրությունը՝ 4 մ, ուստի մակերեսը (6 × 4) / 2 = {area} քառակուսի մետր է։"
)


def armenian(half=25, area=12):
    activity = {"id": "guided", "kind": "guided", "instructions": ARMENIAN.format(half=half, area=area),
                "worked_solution": "", "hint": "",
                "data": [{"id": "garden_base", "label": "Ծաղկանոցի եռանկյան հիմքը", "value": 6.0, "unit": "մ"},
                         {"id": "garden_height", "label": "Հիմքին ուղղահայաց բարձրությունը գագաթից", "value": 4.0, "unit": "մ"},
                         {"id": "umbrella_base", "label": "Օրինակի հովանոցի եռանկյան հիմքը", "value": 10.0, "unit": "մ"},
                         {"id": "umbrella_height", "label": "Օրինակի հովանոցի եռանկյան բարձրությունը", "value": 5.0, "unit": "մ"}],
                "fields": [{"id": "garden_area", "label": "Ծաղկանոցի եռանկյան մակերեսը", "kind": "number",
                            "unit": "քառակուսի մետր", "expression": "(garden_base * garden_height) / 2"}]}
    return {"teaching_cases": [], "private_workbook": {"activities": [activity]}}


def test_armenian_two_word_unit_results_are_parsed():
    package = armenian()
    halve = claim_for({}, package, "50 / 2")
    area = claim_for({}, package, "(6 × 4) / 2")
    halve_review = review(calculations=[
        {"claim_ids": [halve], "case_id": "practice.guided", "expression": "10.0 * 5.0", "claimed_result": 50},
        {"claim_ids": [halve], "case_id": "practice.guided", "expression": "10.0 * 5.0 / 2", "claimed_result": 25}])
    assert failures(halve_review, {}, package, halve) == []
    area_review = review(
        calculations=[{"claim_ids": [area], "case_id": "practice.guided", "expression": "6.0 * 4.0 / 2", "claimed_result": 12}],
        literal_facts=[{"claim_id": area, "case_id": "practice.guided", "datum_ids": ["garden_base", "garden_height"]}],
        literal_fact_ids=[area])
    assert failures(area_review, {}, package, area) == []


@pytest.mark.parametrize("half,area,claimed", [(26, 12, "half"), (25, 13, "area")])
def test_armenian_wrong_result_with_unit_is_rejected(half, area, claimed):
    package = armenian(half, area)
    if claimed == "half":
        claim_id = claim_for({}, package, "50 / 2")
        verdict = review(calculations=[{"claim_ids": [claim_id], "case_id": "practice.guided",
                                        "expression": "10.0 * 5.0 / 2", "claimed_result": 26}])
    else:
        claim_id = claim_for({}, package, "(6 × 4) / 2")
        verdict = review(calculations=[{"claim_ids": [claim_id], "case_id": "practice.guided",
                                        "expression": "6.0 * 4.0 / 2", "claimed_result": 13}],
                         literal_facts=[{"claim_id": claim_id, "case_id": "practice.guided",
                                         "datum_ids": ["garden_base", "garden_height"]}])
    assert failures(verdict, {}, package, claim_id)


def test_named_formula_with_a_different_unit_contract_stays_ambiguous():
    # A named proof binds the units of its own field only; an unrelated unit is not accepted.
    package = garden("So the area is (6 m × 4 m) / 2 = 12 square meters.", area_unit="hectares")
    claim_id = claim_for({}, package, "(6 m × 4 m)")
    verdict = review(calculations=[area_check(claim_id, "(base * height) / 2")])
    assert failures(verdict, {}, package, claim_id)


# --- 4a. "the difference: 3 − 1 = 2" --------------------------------------

def email_package(solution):
    activity = {"id": "guided", "kind": "guided", "instructions": "Count the emails.", "hint": "",
                "worked_solution": solution,
                "data": [{"id": "redelivery_count", "label": "Queue redeliveries after timeout", "value": 2.0},
                         {"id": "emails_per_run", "label": "Emails per run", "value": 1.0},
                         {"id": "first_execution", "label": "First executions", "value": 1.0}],
                "fields": [{"id": "duplicates_prevented", "label": "Duplicate emails prevented by the key",
                            "kind": "number", "unit": "emails",
                            "expression": "((1 + redelivery_count) * emails_per_run) - (first_execution * emails_per_run)"}]}
    return {"teaching_cases": [], "private_workbook": {"activities": [activity]}}


def test_operand_after_difference_is_not_an_explicit_result():
    package = email_package("The duplicates prevented are the difference: 3 − 1 = 2 emails.")
    claim_id = claim_for({}, package, "the difference")
    verdict = review(calculations=[{"claim_ids": [claim_id], "case_id": "practice.guided",
                                    "expression": "(1 + 2.0) * 1.0 - 1.0 * 1.0", "claimed_result": 2}])
    assert failures(verdict, {}, package, claim_id) == []


@pytest.mark.parametrize("sentence,claimed", [
    ("The duplicates prevented are the difference: 3 − 1 = 3 emails.", 3),
    ("The duplicates prevented are the difference: 3 − 1 = 3 emails.", 2),
    ("The duplicates prevented are the difference: 3 emails.", 2),
])
def test_wrong_difference_is_still_rejected(sentence, claimed):
    package = email_package(sentence)
    claim_id = claim_for({}, package, "the difference")
    verdict = review(calculations=[{"claim_ids": [claim_id], "case_id": "practice.guided",
                                    "expression": "(1 + 2.0) * 1.0 - 1.0 * 1.0", "claimed_result": claimed}])
    assert failures(verdict, {}, package, claim_id) or source_equation_failures({}, package)


# --- 4b. "twice" -------------------------------------------------------------

NORDKLEDD = {"id": "nordkledd_email_job", "data": [
    {"id": "redelivery_count", "label": "Queue redeliveries after timeout", "value": 2.0, "unit": "retries"},
    {"id": "emails_per_run", "label": "Confirmation emails sent per non-idempotent run", "value": 1.0},
    {"id": "first_execution", "label": "First (successful) executions", "value": 1.0},
], "results": [{"id": "total_executions", "expression": "1 + redelivery_count", "unit": "executions"}]}
TWICE = ("The job runs once and succeeds, but a network timeout causes the queue to redeliver "
         "the same message {count}, so the handler executes 3 times in total.")


def twice_review(claim_id):
    return review(
        calculations=[{"claim_ids": [claim_id], "case_id": "teaching.nordkledd_email_job",
                       "expression": "1 + 2.0", "claimed_result": 3}],
        literal_facts=[{"claim_id": claim_id, "case_id": "teaching.nordkledd_email_job",
                        "datum_ids": ["redelivery_count"]}])


def test_number_word_satisfies_a_literal_binding():
    lesson, package = {"lesson_content": TWICE.format(count="twice")}, {"teaching_cases": [NORDKLEDD]}
    claim_id = claim_for(lesson, package, "redeliver")
    assert failures(twice_review(claim_id), lesson, package, claim_id) == []


@pytest.mark.parametrize("count", ["three times", "thrice", "once more"])
def test_wrong_number_word_does_not_satisfy_a_literal_binding(count):
    lesson, package = {"lesson_content": TWICE.format(count=count)}, {"teaching_cases": [NORDKLEDD]}
    claim_id = claim_for(lesson, package, "redeliver")
    errors = failures(twice_review(claim_id), lesson, package, claim_id)
    assert f"{claim_id}: bound datum values are absent from the source span" in errors


# --- 4c. Division glyph ------------------------------------------------------

PLOT = {"id": "garden_plot", "data": [
    {"id": "base", "label": "Length of the side chosen as the base", "value": 6.0, "unit": "meters"},
    {"id": "height", "label": "Perpendicular distance", "value": 4.0, "unit": "meters"},
], "results": [{"id": "area", "label": "Area of the triangular plot", "expression": "(base * height) / 2",
                "unit": "square meters"}]}
FORMULA = """## Core Framework

```formula
title: Triangle area
= Base × height
{term}
```
"""


def role(claim_id, quote, coefficient=2, role_name="divisor", field_id="area"):
    return {"claim_id": claim_id, "case_id": "teaching.garden_plot", "field_id": field_id,
            "role": role_name, "coefficient": coefficient, "source_quote": quote, "symbol_bindings": {}}


@pytest.mark.parametrize("term", ["÷ 2", "/ 2"])
def test_bare_division_glyph_term_is_an_explicit_divisor(term):
    lesson, package = {"lesson_content": FORMULA.format(term=term)}, {"teaching_cases": [PLOT]}
    claim_id = claim_for(lesson, package, term)
    assert failures(review(math_roles=[role(claim_id, term)]), lesson, package, claim_id) == []


@pytest.mark.parametrize("row,claimed", [("÷ 2 | −12", -12), ("÷ 2 | −13", -13)])
def test_division_glyph_label_of_a_waterfall_row(row, claimed):
    lesson = {"lesson_content": "```chart\ntype: waterfall\ntitle: Garden plot area\nunit: m²\n"
                                f"Base × height | 24\n{row}\n= Area | 12\n```\n"}
    package = {"teaching_cases": [PLOT]}
    claim_id = claim_for(lesson, package, "÷ 2")
    verdict = review(math_roles=[role(claim_id, "÷ 2")], calculations=[
        {"claim_ids": [claim_id], "case_id": "teaching.garden_plot", "expression": "-(base * height) / 2",
         "claimed_result": claimed}])
    assert (failures(verdict, lesson, package, claim_id) == []) is (claimed == -12)


@pytest.mark.parametrize("term,quote,role_name,expression", [
    ("÷ 3", "÷ 3", "divisor", "(base * height) / 2"),  # Not the canonical divisor.
    ("÷ 2", "÷ 2", "divisor", "base * height * 2"),  # The formula never divides by 2.
    ("÷ 2", "÷ 2", "multiplier", "(base * height) / 2"),  # Glyph says divide, role says multiply.
    ("× 2", "× 2", "divisor", "(base * height) / 2"),
    ("24 ÷ 2", "÷ 2", "divisor", "(base * height) / 2"),  # Has an operand before it.
    ("÷ 2 = 12", "÷ 2", "divisor", "(base * height) / 2"),  # Part of another expression.
])
def test_division_glyph_keeps_the_canonical_divisor_check(term, quote, role_name, expression):
    case = copy.deepcopy(PLOT)
    case["results"][0]["expression"] = expression
    lesson, package = {"lesson_content": FORMULA.format(term=term)}, {"teaching_cases": [case]}
    claim_id = claim_for(lesson, package, term)
    assert failures(review(math_roles=[role(claim_id, quote, role_name=role_name)]), lesson, package, claim_id)


# --- 4d. Deterministic literal binding in the final review ----------------------

SAIL = {"id": "transfer", "kind": "transfer", "hint": "", "worked_solution": "",
        "instructions": "Identify which length can serve as the height for the 12 m base, "
                        "then calculate the sail's area in square meters.",
        "data": [{"id": "sail_side_short", "label": "Shorter stated side length of the sail", "value": 7.0, "unit": "meters"},
                 {"id": "sail_base_side", "label": "Longer stated side length used as the base", "value": 12.0, "unit": "meters"},
                 {"id": "sail_perp_distance", "label": "Perpendicular distance to the 12 m side", "value": 3.5, "unit": "meters"}],
        "fields": [{"id": "sail_area", "label": "Area of the sail (square meters)", "kind": "number",
                    "unit": "square meters", "expression": "(sail_base_side * sail_perp_distance) / 2"}]}
GEOMETRY_LESSON = {"lesson_content": "Why does the 4 m measurement qualify as the height?"}


def geometry_package(*teaching):
    return {"teaching_cases": list(teaching) or [copy.deepcopy(PLOT)],
            "private_workbook": {"activities": [copy.deepcopy(SAIL)]}}


def test_resolver_binds_ownerless_lesson_span_to_its_one_teaching_case():
    package = geometry_package()
    spans = numeric_spans(GEOMETRY_LESSON, package)
    facts, resolved = resolve_literal_evidence(spans, {"n2": "practice.transfer"}, package_cases(package),
                                               ownerless_teaching=True)
    assert resolved == ["n1", "n2"]
    assert (facts[0].case_id, facts[0].datum_ids) == ("teaching.garden_plot", ["height"])
    assert (facts[1].case_id, facts[1].datum_ids) == ("practice.transfer", ["sail_base_side"])


def test_resolver_leaves_ownerless_span_matching_two_teaching_cases_to_the_reviewer():
    other = {"id": "fence", "data": [{"id": "post_gap", "label": "Gap between posts", "value": 4.0}]}
    package = geometry_package(copy.deepcopy(PLOT), other)
    spans = {"n1": numeric_spans(GEOMETRY_LESSON, package)["n1"]}
    assert resolve_literal_evidence(spans, {}, package_cases(package), ownerless_teaching=True) == ([], [])
    # Without the opt-in, preflight behaviour is unchanged: ownerless spans are skipped.
    assert resolve_literal_evidence(spans, {}, package_cases(geometry_package()), ) == ([], [])


@pytest.fixture
def no_telemetry(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())


def final_verdict(**evidence):
    return {"acceptable": True, "issues": [], "package_issues": [], "advisories": [],
            "practice_minutes": 30, "contains_calculations": False, "calculations": [], **evidence}


async def run_review(package, first, *later):
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=copy.deepcopy(item)) for item in (first, *later)]))
    result = await review_lesson(GEOMETRY_LESSON, client_factory=lambda **kw: client,
                                 context={"lesson_package": copy.deepcopy(package)})
    return result, client


@pytest.mark.asyncio
async def test_final_review_binds_unbound_literal_spans_without_a_repair_call(no_telemetry):
    # Recorded first verdict: both spans listed as untyped literal_fact_ids only.
    (errors, response, _), client = await run_review(geometry_package(), final_verdict(literal_fact_ids=["n1", "n2"]))
    assert errors == [] and response.error is None
    assert client.generate_json.await_count == 1
    facts = {fact["claim_id"]: (fact["case_id"], fact["datum_ids"]) for fact in response.data["literal_facts"]}
    assert facts == {"n1": ("teaching.garden_plot", ["height"]), "n2": ("practice.transfer", ["sail_base_side"])}


@pytest.mark.asyncio
async def test_repair_patch_with_wrong_datums_is_rebound_from_the_source(no_telemetry):
    # Recorded repair: n2 bound sail_perp_distance, whose 3.5 is not in the span.
    first = final_verdict(
        literal_facts=[{"claim_id": "n1", "case_id": "teaching.garden_plot", "datum_ids": ["height"]}],
        contains_calculations=True, calculations=[
            {"claim_ids": ["n2"], "case_id": "practice.transfer", "expression": "sail_base_side * 2",
             "claimed_result": 12}])
    patch = {"literal_facts": [
        {"claim_id": "n2", "case_id": "practice.transfer", "datum_ids": ["sail_base_side", "sail_perp_distance"]}],
        "literal_fact_ids": ["n2"]}
    (errors, response, _), client = await run_review(geometry_package(), first, patch)
    assert errors == [] and response.error is None
    facts = {fact["claim_id"]: fact["datum_ids"] for fact in response.data["literal_facts"]}
    assert facts["n2"] == ["sail_base_side"]


@pytest.mark.asyncio
async def test_final_review_does_not_bind_an_ambiguous_or_derived_span(no_telemetry):
    other = {"id": "fence", "data": [{"id": "post_gap", "label": "Gap between posts", "value": 4.0}]}
    package = geometry_package(copy.deepcopy(PLOT), other)
    still_wrong = {"literal_fact_ids": ["n1"]}
    (errors, _, _), client = await run_review(package, final_verdict(literal_fact_ids=["n1", "n2"]), still_wrong)
    assert any(error.startswith("n1:") for error in errors)
    assert client.generate_json.await_count == 2


@pytest.mark.asyncio
async def test_final_review_never_replaces_a_reviewer_calculation_with_a_literal_fact(no_telemetry):
    # The reviewer called n2 derived; a wrong calculation is not overridden by data matching.
    first = final_verdict(literal_fact_ids=["n1"], contains_calculations=True, calculations=[
        {"claim_ids": ["n2"], "case_id": "practice.transfer", "expression": "sail_side_short + 4", "claimed_result": 12}])
    (errors, _, _), client = await run_review(geometry_package(), first, {"literal_fact_ids": []})
    assert errors and client.generate_json.await_count == 2


# --- Review follow-ups -------------------------------------------------------

def test_rebinding_never_replaces_reviewer_cited_datums_by_value():
    # 300 is cash_sales, but the sentence claims credit sales; the reviewer cited
    # credit_sales_unpaid (500). Value matching must not swap in cash_sales.
    package = {"teaching_cases": [CORNER_CUP]}
    lesson = {"lesson_content": "Corner Cup earned credit sales of 300 USD this week that customers have not yet paid."}
    claim_id = claim_for(lesson, package, "credit sales")
    verdict = review(literal_facts=[{"claim_id": claim_id, "case_id": "teaching.corner_cup_week",
                                     "datum_ids": ["credit_sales_unpaid"]}])
    errors = grounded_failures(verdict, lesson, package)
    assert errors
    from app.services.planning.lesson_review import _deterministic_literal_facts
    assert _deterministic_literal_facts(verdict, lesson, package, errors) == []


def test_value_only_binding_requires_a_unique_datum():
    # Untyped literal_fact_ids: 1200 is both rent and fee, so the value alone
    # cannot say which datum the sentence states.
    from app.services.planning.lesson_review import _deterministic_literal_facts
    case = {"id": "shop", "data": [{"id": "rent", "label": "Monthly rent", "value": 1200},
                                   {"id": "fee", "label": "Platform fee", "value": 1200}]}
    package, lesson = {"teaching_cases": [case]}, {"lesson_content": "The shop pays 1200 each month."}
    claim_id = claim_for(lesson, package, "1200")
    verdict = review(literal_fact_ids=[claim_id])
    errors = grounded_failures(verdict, lesson, package)
    assert errors and _deterministic_literal_facts(verdict, lesson, package, errors) == []


def test_unsigned_label_row_keeps_its_negative_value():
    lesson = {"lesson_content": "## Worked Example\n\n```steps\ntitle: Corner Cup week\nunit: USD\n"
                                "Cash sales | −300 | Collected this week.\n"
                                "+ Credit sales earned, unpaid | 500 | Earned this week.\n```\n"}
    package = {"teaching_cases": [CORNER_CUP]}
    claim_id = claim_for(lesson, package, "Cash sales")
    verdict = review(literal_facts=[{"claim_id": claim_id, "case_id": "teaching.corner_cup_week",
                                     "datum_ids": ["cash_sales"]}])
    assert failures(verdict, lesson, package, claim_id)


@pytest.mark.parametrize("sentence", [
    "Sales exceed last year by 3× this spring.",
    "The difference is 30 - a strong margin.",
    "Revenue exceeds the target by 30 + change.",
])
def test_operator_without_equation_keeps_an_explicit_result(sentence):
    from app.services.planning.lesson_review import _EXPLICIT_RESULT
    assert _EXPLICIT_RESULT.search(sentence)
    assert not _EXPLICIT_RESULT.search("The duplicates prevented are the difference: 3 − 1 = 2 emails.")
