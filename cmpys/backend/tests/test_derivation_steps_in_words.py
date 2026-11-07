"""Derivation steps written in words, and hints for unproven values (accounting pilot, 4 Nov 2026).

Approved readings failed the numeric gate because a sentence showed a step of
its own verified result in words, or a correct derived value no evidence
correction would prove. Each recorded fragment has a genuinely unproven value
in the same shape that must still be rejected.
"""
from app.services.planning.lesson_review import (
    LessonReview, _unverified_value_hints, grounded_failures, numeric_spans,
)
from tests.test_geometry_evidence_roles import check as triangle_check
from tests.test_geometry_evidence_roles import review as triangle_review
from tests.test_geometry_evidence_roles import triangle_package

CAFE = {"id": "cafe_month", "data": [
    {"id": "sales_earned", "label": "Sales earned this month", "value": 1000.0},
    {"id": "cash_from_customers", "label": "Cash from customers", "value": 700.0},
    {"id": "supplies_used", "label": "Supplies used", "value": 450.0},
    {"id": "supplies_paid", "label": "Supplies paid", "value": 600.0},
], "results": [{"id": "timing_gap",
                "expression": "(sales_earned - supplies_used) - (cash_from_customers - supplies_paid)"}]}
LEDGER = {"id": "ledger", "data": [
    {"id": "sales_made", "label": "Sales made", "value": 1240.0, "unit": "credits"},
    {"id": "supplies_used", "label": "Supplies used", "value": 470.0, "unit": "credits"},
    {"id": "cash_from_sales", "label": "Cash from sales", "value": 905.0, "unit": "credits"},
    {"id": "cash_paid_supplies", "label": "Cash paid for supplies", "value": 560.0, "unit": "credits"},
], "results": [{"id": "gap", "expression": "(sales_made - supplies_used) - (cash_from_sales - cash_paid_supplies)",
                "unit": "credits"}]}
GAP = {"claim_ids": ["n1"], "expression": "1240 - 470 - (905 - 560)", "claimed_result": 425}


def review(calculations=(), literal_facts=(), case_id="teaching.ledger"):
    return LessonReview.model_validate({
        "acceptable": True, "issues": [], "practice_minutes": 3, "contains_calculations": bool(calculations),
        "calculations": [{**check, "case_id": check.get("case_id", case_id), "location": ", ".join(check["claim_ids"])}
                         for check in calculations],
        "literal_facts": list(literal_facts), "literal_fact_ids": [], "math_roles": []})


def ledger_failures(text):
    lesson, package = {"lesson_content": text}, {"teaching_cases": [LEDGER]}
    assert list(numeric_spans(lesson, package)) == ["n1"]
    return grounded_failures(review([GAP]), lesson, package)


def test_operands_of_the_spans_own_proof_step_in_words_are_proven():
    assert ledger_failures("The gap is 425 credits (770 minus 345).") == []
    assert ledger_failures("770 minus 345 gives 425 credits.") == []


def test_other_operands_and_equal_values_elsewhere_stay_unproven():
    assert ledger_failures("The gap is 425 credits (780 minus 355).") == [
        "n1: numeric span contains additional unverified values: 355, 780"]
    # Only the shown operation is consumed; a separate 770 keeps its own evidence requirement.
    assert ledger_failures("The gap is 425 credits (770 minus 345), not the 770 target.") == [
        "n1: numeric span contains additional unverified values: 770"]


def test_prose_step_keeps_the_equation_unit_boundary():
    for source, accepted in (("162 divided by 2 is 81 cm².", True), ("162 divided by 2 is 81.", True),
                             ("The area is 81 cm² (162 divided by 2).", True),
                             ("162 divided by 2 is 81 cm.", False), ("162 divided by 2 is 81 mm².", False),
                             ("The area is 81 mm² (162 divided by 2).", False)):
        package = triangle_package(source)
        package.workbook.activities[0].fields[-1].unit = "cm²"
        errors = grounded_failures(triangle_review(triangle_check()), {}, package.review_context())
        assert (errors == []) is accepted, (source, errors)


REGROUP = "Unpaid sales add {first} to the profit side, and prepaid stock takes {second} out of cash only, so the gap is 450."
GAP_PROOF = {"claim_ids": ["n1"], "expression": "1000 - 450 - (700 - 600)", "claimed_result": 450}


def test_regrouped_terms_of_the_spans_own_proof_are_proven():
    # (sales - cash from customers) + (supplies paid - supplies used) is the proof's own formula.
    lesson = {"lesson_content": REGROUP.format(first=300, second=150)}
    assert grounded_failures(review([GAP_PROOF], case_id="teaching.cafe_month"), lesson,
                             {"teaching_cases": [CAFE]}) == []


def test_parts_that_only_add_up_numerically_stay_unproven():
    # 250 = cash from customers - supplies used and 200 = supplies paid - a deposit also total 450,
    # but they are not the proof's formula.
    case = {**CAFE, "data": [*CAFE["data"], {"id": "deposit", "label": "Deposit held", "value": 400.0}]}
    lesson = {"lesson_content": REGROUP.format(first=250, second=200)}
    assert grounded_failures(review([GAP_PROOF], case_id="teaching.cafe_month"), lesson,
                             {"teaching_cases": [case]}) == [
        "n1: numeric span contains additional unverified values: 200, 250"]


def test_hints_name_an_existing_proof_or_the_one_case_derivation():
    package = {"teaching_cases": [CAFE]}
    unpaid = {"claim_ids": ["n7"], "case_id": "teaching.cafe_month",
              "expression": "sales_earned - cash_from_customers", "claimed_result": 300}
    fact = {"claim_id": "n1", "case_id": "teaching.cafe_month", "datum_ids": ["sales_earned"]}
    errors = ["n1: numeric span contains additional unverified values: 150, 300"]
    hints = _unverified_value_hints(review([unpaid], [fact]), errors, package, {"n1"})
    assert hints == [
        {"claim_id": "n1", "value": "150", "candidate_derivation": {
            "case_id": "teaching.cafe_month", "expression": "supplies_paid - supplies_used"}},
        {"claim_id": "n1", "value": "300", "existing_calculation": {
            "case_id": "teaching.cafe_month", "claim_ids": ["n7"], "expression": "sales_earned - cash_from_customers"}}]
    # Spans outside the correction's scope get no hints.
    assert _unverified_value_hints(review([unpaid], [fact]), errors, package, {"n2"}) == []


CAFE7 = {"id": "cafe7", "data": [
    {"id": "sales_cash", "label": "Cash sales received at the counter this month", "value": 800.0, "unit": "credits"},
    {"id": "sales_credit", "label": "Credit sales earned this month and not yet collected", "value": 300.0,
     "unit": "credits"},
    {"id": "costs_incurred", "label": "Costs incurred this month, paid or unpaid", "value": 650.0, "unit": "credits"},
    {"id": "costs_paid", "label": "Cash paid out this month for costs", "value": 500.0, "unit": "credits"},
], "results": [{"id": "accrual_profit", "expression": "sales_cash + sales_credit - costs_incurred", "unit": "credits"}]}
PROFIT = ("Earned sales total {sales} credits, and subtracting the 650 credits of incurred costs gives an "
          "accrual profit of 450 credits.")


def test_grouped_operand_and_subtracting_wording_are_a_shown_step():
    lesson, package = {"lesson_content": PROFIT.format(sales="1,100")}, {"teaching_cases": [CAFE7]}
    profit = {"claim_ids": ["n1"], "expression": "800 + 300 - 650", "claimed_result": 450}
    assert grounded_failures(review([profit], case_id="teaching.cafe7"), lesson, package) == []
    lesson = {"lesson_content": PROFIT.format(sales="1,200")}
    assert grounded_failures(review([profit], case_id="teaching.cafe7"), lesson, package) == [
        "n1: numeric span contains additional unverified values: 1200"]


def test_leading_label_words_with_a_sum_verb_name_their_datum():
    lesson, package = {"lesson_content": "Costs incurred total 650, whether paid or unpaid."}, {"teaching_cases": [CAFE7]}
    fact = {"claim_id": "n1", "case_id": "teaching.cafe7", "datum_ids": ["costs_incurred"]}
    assert grounded_failures(review(literal_facts=[fact]), lesson, package) == []


def test_an_inserted_phrase_does_not_break_the_label():
    case = {**CAFE7, "data": [{"id": "sales_earned", "label": "Sales earned in the month", "value": 5000.0,
                               "unit": "credits"}, *CAFE7["data"][2:]],
            "results": [{"id": "accrual_profit", "expression": "sales_earned - costs_incurred", "unit": "credits"}]}
    lesson = {"lesson_content": "Sales earned, including unpaid catering invoices, total 5000 credits."}
    fact = {"claim_id": "n1", "case_id": "teaching.cafe7", "datum_ids": ["sales_earned"]}
    assert grounded_failures(review(literal_facts=[fact]), lesson, {"teaching_cases": [case]}) == []


def test_leading_label_words_shared_by_another_datum_stay_derived():
    case = {**CAFE7, "data": [*CAFE7["data"], {"id": "costs_planned", "label": "Costs incurred next month, planned",
                                               "value": 700.0, "unit": "credits"}]}
    lesson, package = {"lesson_content": "Costs incurred total 650, whether paid or unpaid."}, {"teaching_cases": [case]}
    fact = {"claim_id": "n1", "case_id": "teaching.cafe7", "datum_ids": ["costs_incurred"]}
    assert "n1: derived result cannot be classified as a literal fact" in grounded_failures(
        review(literal_facts=[fact]), lesson, package)


def test_teaching_patch_hears_only_its_own_findings():
    from app.tasks.plans import _teaching_patch_defects
    preflight = ["teaching.cafe_ledger: the gap wording omits the month", "practice.practice_month: labels say only month",
                 "teaching.cafe_ledger.cash_net: sign convention"]
    assert _teaching_patch_defects(preflight, None, {"cafe_ledger"}) == [preflight[0], preflight[2]]
    review_issues = ["The case calls unpaid supplies a cash cost.", "The guided rubric omits the profit figure."]
    assert _teaching_patch_defects(review_issues, ["teaching.cafe_ledger", "practice.guided"], {"cafe_ledger"}) == [
        review_issues[0]]
    # Unpaired or unmatched findings are all kept, never dropped.
    assert _teaching_patch_defects(review_issues, ["teaching.cafe_ledger"], {"cafe_ledger"}) == review_issues


MARCH = {"id": "cafe_march", "data": [
    {"id": "sales_earned", "label": "Sales earned", "value": 1200.0}, {"id": "cash_received", "label": "Cash received", "value": 900.0},
    {"id": "supplies_used", "label": "Supplies used", "value": 400.0}, {"id": "cash_paid", "label": "Cash paid", "value": 350.0}],
    "results": [{"id": "cash_flow", "expression": "cash_received - cash_paid"}]}
CHECK = """```check
Q: Which figure is net cash flow for March?
- [ ] 500
- [ ] 800
- [x] 550
Why: Cash flow is cash received minus cash paid, so 900 − 350 = 550. 500 subtracts supplies used instead of cash paid. The 800 option is accrual profit.
```"""


def test_wrong_quick_check_options_are_choice_names_not_claims():
    spans = list(numeric_spans({"lesson_content": CHECK}, {"teaching_cases": [MARCH]}).values())
    assert spans == ["- [x] 550", "Why: Cash flow is cash received minus cash paid, so 900 − 350 = 550.",
                     "500 subtracts supplies used instead of cash paid."]


def test_keyed_options_and_lists_outside_a_check_keep_their_evidence_requirement():
    keyed = CHECK.replace("- [ ] 500", "- [ ] 550")  # A wrong option equal to the key is not exempt.
    assert "- [ ] 550" in numeric_spans({"lesson_content": keyed}, {"teaching_cases": [MARCH]}).values()
    assert list(numeric_spans({"lesson_content": "Options:\n- [ ] 500\n- [ ] 800"}, {"teaching_cases": [MARCH]}).values()) == [
        "- [ ] 500", "- [ ] 800"]


def test_ambiguous_or_unbound_values_get_no_hint():
    case = {"id": "pairs", "data": [{"id": "a", "label": "A", "value": 10.0}, {"id": "b", "label": "B", "value": 7.0},
                                    {"id": "c", "label": "C", "value": 5.0}, {"id": "d", "label": "D", "value": 2.0}],
            "results": [{"id": "total", "expression": "a + b + c + d"}]}
    fact = {"claim_id": "n1", "case_id": "teaching.pairs", "datum_ids": ["a"]}
    errors = ["n1: numeric span contains additional unverified values: 3"]  # 10 - 7 and 5 - 2.
    assert _unverified_value_hints(review(literal_facts=[fact]), errors, {"teaching_cases": [case]}, {"n1"}) == []
    # A span with no case binding has no case data to derive from.
    assert _unverified_value_hints(review(), errors, {"teaching_cases": [case]}, {"n1"}) == []
