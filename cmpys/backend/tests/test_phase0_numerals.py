"""Phase 0.2-0.4 (near-zero rejections plan, 2026-11-04): one numeral policy,
the declared-numbers check on every activity, and exact-value binding in code.

Regression texts are quoted from the captured Haiku 5.5 benchmark responses in
run-tutorial-haiku-{prompts,confirm,fix2,fix3}-r{1,2,3}; each case names its
run/scenario. Every relaxation is paired with a nearby wrong value (an
off-by-one, a wrong operand, a wrong rounding) that must still be rejected or
left for the model binder.
"""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning import package_builder as builder
from app.services.planning.activity_draft import parse_activity_draft
from app.services.planning.evidence_resolver import server_bound_evidence
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import (
    _evidence_ids, numeric_spans, review_lesson, source_equation_failures,
)
from app.services.planning.numeric_metadata import is_quantity_numeral, quantity_numerals
from app.services.practice.contracts import calculate


def quantities(text, **kwargs):
    return [literal for _, _, literal in quantity_numerals(text, **kwargs)]


def bound_ids(patch):
    return ({fact.claim_id for fact in patch.literal_facts}
            | {key for check in patch.calculations for key in check.claim_ids})


# --- 0.2 One shared numeral policy -------------------------------------------

@pytest.mark.parametrize("text", [
    # confirm-r1 software_experienced_evidence (seed): identifier in a qualitative case.
    "A worker receives a message 'send receipt for order 418'.",
    # prompts-r2 software_experienced_missing (seed): a job record.
    "The handler named send_receipt receives the job {job_id: r-1042, order_ref: 88, attempt: 1}.",
    # fix2-r3 software_experienced_missing (seed): a key string.
    "Each job carries the key 'invoice-42-reminder-1'.",
    # fix3-r1 software_experienced_missing (seed): a message code.
    "A worker receives message m-17 with the fields job_id, account and amount.",
    # prompts-r2 software_experienced_evidence (seed): a step reference.
    "Worked analysis: the duplicate check in step 1 runs before the provider call.",
    # fix2-r3 philosophy_experienced_missing (seed): a bus route name.
    "Clinic attendance fell noticeably in the months after the number 9 bus route was shortened.",
    # confirm-r3 writing_novice_evidence (binder: "contain no numeric values").
    "Paragraph 1: Harbor Library has served our city for many years.",
    # fix2-r1 philosophy_novice_evidence (activity gate).
    "Reading 1: The notice is mainly about getting a garden plot.",
    # fix2-r1 philosophy_experienced_missing (activity gate): mid-sentence item label.
    "Two readings of item 2 are offered below.",
    # confirm-r2 accounting_novice_evidence (binder): "Line" was missing from the label list.
    "Line 2: Sales on account in April",
    # fix3-r1 accounting_novice_evidence (binder): a date.
    "The catering contract was signed in March, but the catering will be delivered on April 5.",
    # fix3-r3 project_design_experienced_missing (binder): date ranges.
    "Report on days outside November 20 to 24 and compare the November 10 to 30 window.",
    # prompts-r1 philosophy_experienced_missing (activity gate): clock times.
    "The Friday closing bell rings at 5 pm. At 6 pm on Friday, Ines asks to sign out a key.",
    # fix3-r3 philosophy_experienced_missing (activity gate): opening hours.
    "Tuesday: open 09:00 to 18:00.",
    # confirm-r2 software_experienced_missing (activity gate): a log line.
    "- 10:02:11 Delivery 1 received.",
    # confirm-r2 software_experienced_missing (activity gate): a clock time ending a log label.
    "- Monday 08:00: step 3 sent the notice, and the partner accepted it.",
    # fix3-r1 writing_experienced_evidence (activity gate): school years and a class name.
    "Audience note: parents of Year 5 children must decide. The scores are for Class 5B.",
    # fix3-r2 writing_novice_evidence (activity gate).
    "In the autumn term, the school asked only Year 8 students one question.",
    # fix2-r3 project_design_experienced_missing (activity gate): an inline enumeration.
    "It must name (1) the population of shoppers the test covers, (2) the comparison group and how it "
    "differs from the test group, (3) the measured outcome and how it is counted, and (4) the decision "
    "threshold the team sets before launch.",
    # confirm-r3 software_experienced_evidence (binder): a row id.
    "- batch_id B-417, source_row_no 1",
    # fix2-r2 software_experienced_missing (binder): a timeline label.
    "- Hour 0: the worker receives the job and calls the provider with the key.",
    # Versions and ISO dates.
    "Version 2.1 adds the retry, released 2026-03-10.",
])
def test_identifiers_dates_times_labels_and_versions_are_not_quantities(text):
    assert quantities(text) == []


def test_verb_like_label_at_a_sentence_start_needs_the_same_label_in_its_field():
    # fix2-r1 philosophy_experienced_missing: "Reading 1: Item 2 shifts only a due date ..."
    labelled = ("Reading 1: Item 2 shifts only a due date that falls on a closed day.\n"
                "Reading 1 fits the full policy. Reading 2 makes the due date later, so Reading 2 cannot work.")
    assert quantities(labelled) == []
    # Alone, a sentence-initial "Reading 1 fits" could be a count; it stays a quantity.
    assert quantities("Reading 1 fits the policy.") == ["1"]
    assert quantities("Reading 3 books takes an hour.") == ["3"]


@pytest.mark.parametrize("text,expected", [
    # confirm-r2 writing_experienced_missing (seed): the riders are counted, the route is named.
    ("Self-reported door-to-door times from 40 riders on Route 9, collected after the lane opened.", ["40"]),
    # prompts-r1 accounting_experienced_evidence: the date is not a quantity, the reduction is.
    ("On 28 March, the customer agreed to reduce this invoice by 300 credits.", ["300"]),
    # A capitalised word alone never makes an identifier.
    ("Revenue 400 and Sales 300 were recorded.", ["400", "300"]),
    ("Route 14 carried 40 riders.", ["40"]),
    # Counts, amounts and durations after or beside a label stay quantities.
    ("Step 2 costs $40.", ["40"]),
    ("Option 2 gives 41 cups.", ["41"]),
    ("We sold option 3 times.", ["3"]),
    ("A line 2 metres long.", ["2"]),
    ("Customers order 40 cups a day.", ["40"]),
    ("The shop claims 300 credits.", ["300"]),
    ("Each week 40 people came.", ["40"]),
    ("Train 40 staff before the launch.", ["40"]),
    ("The number 9 is odd.", ["9"]),
    ("In March 12 riders joined.", ["12"]),
    ("Mix them at a 3:15 ratio.", ["3", "15"]),
    ("The screen says 7:42 + 2 = 9.", ["7", "42", "2", "9"]),
    ("Repeated keys are honoured within 24 hours.", ["24"]),
    # fix2-r1 software_experienced_evidence: an amount in a record stays an amount.
    ("- refund_amount: 40.00 USD for the request", ["40.00"]),
    ("costs (1) 40 and (2) 50", ["1", "40", "2", "50"]),
    ("A 5th of the budget went to rent.", ["5"]),
    ("Only 40 returning users have opted in.", ["40"]),
])
def test_quantities_stay_quantities(text, expected):
    assert quantities(text) == expected


def test_one_decision_function_for_one_occurrence():
    text = "Route 14 carried 40 riders."
    assert not is_quantity_numeral(text, text.index("14"), text.index("14") + 2)
    assert is_quantity_numeral(text, text.index("40"), text.index("40") + 2)


def _seed(assumptions):
    raw = json.loads(next(line for line in resolve_prompt_text("tutorial_package_seed.txt").splitlines()
                          if line.startswith('{"workbook_title"')))
    raw["teaching_cases"] = [{"id": "case", "assumptions": assumptions, "data": [], "results": []}]
    return builder.LessonPackageSeed.model_validate(raw)


def _qualitative_activity(instructions):
    draft = json.loads(resolve_prompt_text("tutorial_exemplar_qualitative.txt").split("\n", 1)[1])
    return parse_activity_draft({**draft, "instructions": instructions + " Answer in your own words."})


@pytest.mark.parametrize("text,is_quantity", [
    # confirm-r2 software_experienced_missing (seed rejected for identifiers).
    ("Original fictional case: charge customer 418 for order 77 with idempotency key k-77-a at 17:00. "
     "Paragraph 1: the handler first looks up the key.", False),
    # confirm-r1 software_experienced_missing (seed): a real duration is a numeric fact.
    ("Original fictional case: the provider rejects repeated keys within 24 hours for order 418.", True),
])
def test_seed_gate_activity_gate_and_span_extractor_agree(text, is_quantity):
    seed = _seed(text)
    activity = _qualitative_activity(text)
    if is_quantity:
        with pytest.raises(builder.TutorialTeachingCaseError, match="quantities shown: 24"):
            builder.validate_tutorial_seed(seed, "tutorial_v1")
        with pytest.raises(builder.UndeclaredNumbersError) as raised:
            builder.require_declared_numbers(activity)
        assert raised.value.numbers == [("instructions", "24")]
    else:
        builder.validate_tutorial_seed(seed, "tutorial_v1")
        builder.require_declared_numbers(activity)
    spans = numeric_spans({}, {"private_workbook": {"activities": [activity.model_dump(mode="json")]}})
    assert bool(spans) is is_quantity


# --- 0.3 The declared-numbers check runs on every activity ---------------------

def _numeric_activity(instructions, data, expression, misconceptions=()):
    draft = json.loads(resolve_prompt_text("tutorial_exemplar_quantitative.txt").split("\n", 1)[1])
    field = {**draft["fields"][0], "id": "profit", "label": "Accrual profit (credits)", "unit": "credits",
             "expression": expression, "rubric_criterion": "Subtracts expenses from revenue earned",
             "misconceptions": [{"expression": item, "feedback": "That mixes cash with earned revenue."}
                                for item in misconceptions]}
    return builder.LessonPackageActivity.model_validate(parse_activity_draft({
        **draft, "instructions": instructions, "data": data, "fields": [field]}))


LEDGER = [{"id": "revenue_earned", "label": "Revenue earned", "value": 9000, "unit": "credits"},
          {"id": "cash_received", "label": "Cash received", "value": 7600, "unit": "credits"},
          {"id": "expenses_incurred", "label": "Expenses incurred", "value": 6200, "unit": "credits"}]


def test_an_undeclared_quantity_in_an_activity_with_data_is_flagged_with_its_location():
    # fix2-r3 accounting_experienced_evidence showed "of which 1400 is still owed" (9000 − 7600). Since
    # 2026-11-06 a one-step difference of two data passes here and the gate proves it with a
    # calculation; a breakdown fact no data pair gives (1100 from catering) is still flagged.
    activity = _numeric_activity(
        "Original fictional case. Its revenue earned is 9000 credits, of which 1100 came from catering "
        "clients, and cash received is 7600 credits. Expenses incurred are 6200 credits. Calculate accrual profit.",
        LEDGER, "revenue_earned - expenses_incurred")
    with pytest.raises(builder.UndeclaredNumbersError) as raised:
        builder.require_declared_numbers(activity)
    assert raised.value.numbers == [("instructions", "1100")] and raised.value.has_data
    [diagnostic] = builder._diagnostics(raised.value)
    assert diagnostic["type"] == "undeclared_numbers"
    assert "instructions shows 1100" in diagnostic["message"]


@pytest.mark.parametrize("shown,flagged", [
    ("2800", False),   # The field computes it (9000 - 6200).
    ("2801", True),    # Off by one.
    ("1400", False),   # The declared misconception computes it (7600 - 6200).
    ("3400", True),    # Computed from nothing declared (a wrong operand: 9600 - 6200).
])
def test_values_the_activity_computes_are_declared_and_nearby_values_are_not(shown, flagged):
    activity = _numeric_activity(
        f"Original fictional case. Revenue earned is 9000 credits, cash received is 7600 credits and expenses "
        f"incurred are 6200 credits. One answer was {shown} credits. Calculate accrual profit.",
        LEDGER, "revenue_earned - expenses_incurred", misconceptions=["cash_received - expenses_incurred"])
    if flagged:
        with pytest.raises(builder.UndeclaredNumbersError) as raised:
            builder.require_declared_numbers(activity)
        assert raised.value.numbers == [("instructions", shown)]
    else:
        builder.require_declared_numbers(activity)


def test_a_restated_teaching_case_value_is_declared_data():
    # fix3-r3 geometry_experienced_evidence: the activity restated the pennant case's 12.0 and 5.0.
    activity = _numeric_activity(
        "Original fictional case. Like the pennant (12.0 m by 5.0 m), revenue earned is 9000 credits and "
        "expenses incurred are 6200 credits. Calculate accrual profit.",
        LEDGER, "revenue_earned - expenses_incurred")
    pennant = SimpleNamespace(model_dump=lambda mode=None: {
        "id": "pennant", "data": [{"id": "base", "value": 12.0}, {"id": "height", "value": 5.0}],
        "results": [{"id": "area", "expression": "base * height / 2", "decimal_places": 0}]})
    with pytest.raises(builder.UndeclaredNumbersError):
        builder.require_declared_numbers(activity)
    builder.require_declared_numbers(activity, [pennant])
    builder.require_component_checks(activity, [pennant])


# --- 0.4 Notation and exact-value binding --------------------------------------

@pytest.mark.parametrize("expression,value", [
    ("x ^ 2", 36), ("a ÷ 2", 4), ("a × b", 48), ("a − b", 2), ("x ** 3", 216), ("6^2 + 8^2", 100),
])
def test_calculate_evaluates_power_and_typeset_operators(expression, value):
    assert calculate(expression, {"x": 6, "a": 8, "b": 6}) == value


@pytest.mark.parametrize("expression", ["x ^ 4", "x ** 0.5", "x ^ y", "2 ** 1000", "x ^ -1"])
def test_calculate_keeps_other_powers_unsupported(expression):
    with pytest.raises(ValueError):
        calculate(expression, {"x": 6, "y": 2})


def test_power_notation_is_checked_by_the_source_equation_checker():
    # fix3-r3 geometry_novice_evidence: "6^2 + 8^2 = 36 + 64 = 100 = 10^2" (true).
    assert source_equation_failures({"lesson_content": "6^2 + 8^2 = 36 + 64 = 100 = 10^2."}) == []
    errors = source_equation_failures({"lesson_content": "6^2 + 8^2 = 101."})
    assert errors and "explicit source equation is incorrect" in errors[0]


def _practice_package(instructions, *, data, expression, teaching=()):
    payload = {"teaching_cases": list(teaching), "workbook": {"title": "Profit and cash", "activities": []}}
    for index, kind in enumerate(("practice", "transfer")):
        activity = _numeric_activity(instructions if index == 0 else
                                     "Original fictional case. Revenue earned is 500 credits and expenses incurred "
                                     "are 300 credits. Calculate accrual profit.",
                                     data if index == 0 else [
                                         {"id": "revenue_earned", "label": "Revenue earned", "value": 500, "unit": "credits"},
                                         {"id": "expenses_incurred", "label": "Expenses incurred", "value": 300, "unit": "credits"}],
                                     expression if index == 0 else "revenue_earned - expenses_incurred")
        raw = activity.model_dump(mode="json")
        raw.update(id=("guided", "transfer")[index], kind=kind)
        payload["workbook"]["activities"].append(raw)
    return LessonPackage.model_validate(payload)


def _bind(package, fragment):
    context = package.review_context()
    spans = numeric_spans({}, context)
    [claim] = [key for key, span in spans.items() if fragment in span]
    return claim, server_bound_evidence({}, context, {claim})


@pytest.mark.parametrize("shown,bound", [("2800", True), ("2801", False), ("2799", False)])
def test_a_field_result_binds_in_code_and_an_off_by_one_does_not(shown, bound):
    package = _practice_package(
        f"Original fictional case. Revenue earned is 9000 credits and expenses incurred are 6200 credits, "
        f"so accrual profit is {shown} credits. Explain the timing.", data=LEDGER,
        expression="revenue_earned - expenses_incurred")
    claim, patch = _bind(package, "so accrual profit is")
    assert (claim in bound_ids(patch)) is bound
    if bound:
        [check] = patch.calculations
        assert check.case_id == "practice.guided" and check.expression == "revenue_earned - expenses_incurred"


@pytest.mark.parametrize("sentence,bound", [
    ("Revenue earned is 9000 credits and expenses incurred are 6200 credits.", True),
    ("Revenue earned minus expenses incurred gives 2800 credits.", True),
    ("Revenue earned is 6200 credits and expenses incurred are 9000 credits.", False),  # swapped
    ("Revenue earned is 7600 credits and expenses incurred are 6200 credits.", False),  # cash as revenue
    ("Revenue earned is 9000 credits; cash received is 2800 credits.", False),          # profit as cash
])
def test_a_value_under_another_declared_label_stays_with_the_model_binder(sentence, bound):
    # Equal values are not equal meanings: a correct number written under a
    # different declared label is never proven in code.
    package = _practice_package(f"Original fictional case. {sentence} Explain the timing.", data=LEDGER,
                                expression="revenue_earned - expenses_incurred")
    claim, patch = _bind(package, sentence)
    assert (claim in bound_ids(patch)) is bound


ROUNDING = {"id": "rounding", "assumptions": "Original fictional case: one hundred credits shared by three.",
            "data": [{"id": "total", "label": "Credits to share", "value": 100.0, "unit": "credits"},
                     {"id": "people", "label": "People sharing", "value": 3.0, "unit": "people"}],
            "results": [{"id": "share", "label": "Share per person", "expression": "total / people",
                         "unit": "credits", "decimal_places": 1}]}


@pytest.mark.parametrize("shown,bound", [("33.3", True), ("33.33", False), ("33.4", False), ("33", False)])
def test_a_teaching_result_binds_only_at_its_declared_rounding(shown, bound):
    lesson = {"lesson_content": f"## Worked Example\n\nEach person receives {shown} credits."}
    patch = server_bound_evidence(lesson, {"teaching_cases": [copy.deepcopy(ROUNDING)]})
    assert bool(bound_ids(patch)) is bound


PENNANT = {"id": "pennant", "assumptions": "Original fictional pennant with a 12 m base and 5 m height.",
           "data": [{"id": "base", "label": "Base of the pennant", "value": 12.0, "unit": "m"},
                    {"id": "height", "label": "Perpendicular height", "value": 5.0, "unit": "m"}],
           "results": [{"id": "area", "label": "Area of the pennant", "expression": "base * height / 2",
                        "unit": "m²", "decimal_places": 0}]}


@pytest.mark.parametrize("sentence,bound", [
    # fix3-r3 geometry_experienced_evidence: "the displayed operands 12.0 m and 5.0 m are raw data of
    # teaching.pennant, not of practice.practice, which owns this span".
    ("For the pennant, area = 12.0 m × 5.0 m ÷ 2 = 30 m².", True),
    ("For the pennant, area = 12.0 m × 5.0 m ÷ 2 = 31 m².", False),   # Off by one (and a false equation).
    ("For the pennant, area = 12.0 m × 6.0 m ÷ 2 = 36 m².", False),   # A wrong operand.
])
def test_a_restated_teaching_case_binds_to_that_case(sentence, bound):
    package = _practice_package(
        "Original fictional case. Revenue earned is 9000 credits and expenses incurred are 6200 credits. "
        + sentence + " Calculate accrual profit.", data=LEDGER,
        expression="revenue_earned - expenses_incurred", teaching=[copy.deepcopy(PENNANT)])
    claim, patch = _bind(package, "For the pennant")
    assert (claim in bound_ids(patch)) is bound
    if bound:
        assert {check.case_id for check in patch.calculations} == {"teaching.pennant"}


CAFE = {"id": "cafe_month", "assumptions": "Original fictional cafe month with earned and received amounts.",
        "data": [{"id": "earned_revenue", "label": "Revenue earned", "value": 9000.0, "unit": "credits"},
                 {"id": "unpaid_sales", "label": "Current sales still unpaid", "value": 2000.0, "unit": "credits"},
                 {"id": "prior_receivable_collected", "label": "Previous-month receivable collected", "value": 1500.0, "unit": "credits"},
                 {"id": "expenses_incurred", "label": "Expenses incurred", "value": 6000.0, "unit": "credits"},
                 {"id": "unpaid_bills", "label": "Supplier bills still unpaid", "value": 1000.0, "unit": "credits"}],
        "results": [{"id": "cash_net_flow", "label": "Cash net flow", "unit": "credits", "decimal_places": 0,
                     "expression": "(earned_revenue - unpaid_sales + prior_receivable_collected)"
                                   " - (expenses_incurred - unpaid_bills)"}]}


@pytest.mark.parametrize("sentence,bound", [
    # confirm-r1 accounting_experienced_evidence: the run ended on "n6: numeric span contains
    # additional unverified values: 5000, 8500"; every value was correct.
    ("Receipts are 9000 minus the 2000 unpaid sales, plus the 1500 previous-month receivable collected, giving 8500.", True),
    ("Payments are 6000 minus the 1000 unpaid bills, giving 5000.", True),
    ("Cash net flow is 8500 minus 5000, which equals 3500 credits.", True),
    ("Receipts are 9000 minus the 2000 unpaid sales, plus the 1500 previous-month receivable collected, giving 8600.", False),
    ("Cash net flow is 8500 plus 5000, which equals 3500 credits.", False),      # The wrong operator.
    ("Cash net flow is 8400 minus 5000, which equals 3500 credits.", False),     # A wrong operand.
    # An intermediate value never binds from prose alone: it is often the very mistake.
    ("Receipts come to 8500 credits.", False),
])
def test_intermediate_values_bind_only_where_their_operation_is_shown(sentence, bound):
    lesson = {"lesson_content": "## Worked Example\n\n" + sentence}
    patch = server_bound_evidence(lesson, {"teaching_cases": [copy.deepcopy(CAFE)]})
    assert bool(bound_ids(patch)) is bound


PLOT = {"id": "triangle_plot", "assumptions": "Original fictional triangular plot with its base and height.",
        "data": [{"id": "base_length", "label": "Length of the base edge", "value": 8.0, "unit": "m"},
                 {"id": "perp_height", "label": "Perpendicular height to the base line", "value": 5.0, "unit": "m"}],
        "results": [{"id": "plot_area", "label": "Area of the triangular plot", "unit": "square metres",
                     "expression": "base_length * perp_height / 2", "decimal_places": 0}]}
# fix3-r2 geometry_novice_evidence: the binder could not verify the what-if option 80
# ("No raw datum, derived result, or workbook value ... produces 80").
WHAT_IF = ("## Check Your Understanding\n\n```check\n"
           "Q: The plot base doubles to 16 m, with perpendicular height still 5 m. What is the area in square metres?\n"
           "- [ ] 20\n- [x] {key}\n- [ ] 80\n- [ ] 160\n"
           "Why: 16 × 5 = 80, and half of 80 is 40.\n```\n")


def _check_bindings(content):
    lesson = {"lesson_content": content}
    spans = numeric_spans(lesson, {"teaching_cases": [copy.deepcopy(PLOT)]})
    patch = server_bound_evidence(lesson, {"teaching_cases": [copy.deepcopy(PLOT)]})
    return spans, bound_ids(patch)


def test_quick_check_what_if_and_distractor_values_bind_from_declared_formulas():
    spans, bound = _check_bindings(WHAT_IF.format(key="40"))
    by_text = {span: key in bound for key, span in spans.items()}
    # Wrong options ("- [ ] 20", "- [ ] 80", "- [ ] 160") are choice names, not
    # numeric claims, since the 2026-11-05 tutorial iteration; the keyed option
    # and the Why derivation keep their proofs.
    assert by_text == {
        "Q: The plot base doubles to 16 m, with perpendicular height still 5 m.": True,  # 2 × base
        "- [x] 40": True,     # The what-if area, recomputed from the declared formula.
        "Why: 16 × 5 = 80, and half of 80 is 40.": True,
    }


@pytest.mark.parametrize("key", ["80", "41"])
def test_a_wrong_quick_check_key_is_never_bound_in_code(key):
    spans, bound = _check_bindings(WHAT_IF.format(key=key))
    [claim] = [claim for claim, span in spans.items() if span == f"- [x] {key}"]
    assert claim not in bound


def test_a_what_if_that_is_not_an_exact_double_binds_nothing_new():
    spans, bound = _check_bindings(WHAT_IF.format(key="42.5").replace("doubles to 16 m", "doubles to 17 m")
                                   .replace("16 × 5 = 80", "17 × 5 = 85").replace("half of 80 is 40", "half of 85 is 42.5"))
    # Only the wrong option "- [ ] 20" was bound before; wrong options are no longer claims.
    assert {spans[key] for key in bound} == set() and "- [x] 42.5" in spans.values()


def test_a_span_with_a_false_displayed_equation_is_never_bound_in_code():
    # Every number is a correct declared value, but "8 × 5 = 20" is false.
    lesson = {"lesson_content": "## Worked Example\n\nThe plot covers 8 × 5 = 20 square metres."}
    assert not bound_ids(server_bound_evidence(lesson, {"teaching_cases": [copy.deepcopy(PLOT)]}))
    lesson = {"lesson_content": "## Worked Example\n\nThe plot covers 8 × 5 ÷ 2 = 20 square metres."}
    assert bound_ids(server_bound_evidence(lesson, {"teaching_cases": [copy.deepcopy(PLOT)]}))


def test_a_span_shared_by_two_teaching_cases_stays_with_the_binder():
    twin = {**copy.deepcopy(PLOT), "id": "other_plot"}
    lesson = {"lesson_content": "## Worked Example\n\nThe base edge is 8 m long."}
    assert not bound_ids(server_bound_evidence(lesson, {"teaching_cases": [copy.deepcopy(PLOT), twin]}))


# --- Integration: preflight and final review ---------------------------------

def test_preflight_binds_computed_spans_without_a_model_scope():
    from app.services.planning import package_preflight as preflight
    from app.services.planning.package_review import package_review_payload
    package = _practice_package(
        "Original fictional case. Revenue earned is 9000 credits and expenses incurred are 6200 credits, "
        "so accrual profit is 2800 credits. Explain the timing.", data=LEDGER,
        expression="revenue_earned - expenses_incurred")
    payload = package_review_payload(package, {}, {})
    groups = {activity.id: [key for key, owner in payload["numeric_span_owners"].items()
                            if owner == "practice." + activity.id] for activity in package.workbook.activities}
    accepted = preflight._accepted_literal_facts(package, payload, groups, set())
    guided = [key for key in groups["guided"] if "accrual profit is" in payload["numeric_spans"][key]]
    assert guided and set(guided) <= {key for check in accepted["guided"].calculations for key in check.claim_ids}
    assert not preflight._scope_failures(accepted["guided"], _evidence_ids(
        preflight._evidence_review(preflight._patch_verdict(accepted["guided"]))), package)


@pytest.mark.asyncio
async def test_final_review_sends_only_unbound_spans_and_keeps_the_server_evidence(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    lesson = {"lesson_content": "## Worked Example\n\nPayments are 6000 minus the 1000 unpaid bills, giving 5000.\n\n"
                                "The cafe also sold 77 muffins."}
    package = {"teaching_cases": [copy.deepcopy(CAFE)]}
    spans = numeric_spans(lesson, package)
    unbound = [key for key, span in spans.items() if "muffins" in span]
    verdict = {"acceptable": False, "issues": ["The muffin count has no supplied data."], "package_issues": [],
               "practice_minutes": 3, "contains_calculations": False, "calculations": []}
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=verdict)))
    failures, response, _ = await review_lesson(lesson, client_factory=lambda **kw: client,
                                                context={"lesson_package": package})
    sent = json.loads(client.generate_json.await_args.kwargs["user_prompt"])["numeric_spans"]
    assert list(sent) == unbound
    assert failures == ["The muffin count has no supplied data."]
    assert {check["expression"] for check in response.data["calculations"]} == {"expenses_incurred - unpaid_bills"}


def _geometry_package(sentence):
    payload = {"teaching_cases": [], "workbook": {"title": "Triangle areas", "activities": []}}
    for index, kind in enumerate(("practice", "transfer")):
        draft = json.loads(resolve_prompt_text("tutorial_exemplar_quantitative.txt").split("\n", 1)[1])
        base, height = (9, 8) if index == 0 else (14, 6)
        field = {**draft["fields"][0], "id": "area", "label": "Area (square centimetres)", "unit": "cm²",
                 "expression": "base * height / 2", "rubric_criterion": "Halves base times perpendicular height",
                 "misconceptions": [{"expression": "base * height", "feedback": "That is the rectangle, not the triangle."}]}
        activity = builder.LessonPackageActivity.model_validate(parse_activity_draft({
            **draft, "id": ("guided", "transfer")[index], "kind": kind,
            "instructions": ("Original fictional case. The base is 9 cm and the perpendicular height is 8 cm. "
                             + sentence + " Calculate the area.") if index == 0 else
                            "Original fictional case. The base is 14 cm and the height is 6 cm. Calculate the area.",
            "data": [{"id": "base", "label": "Base", "value": base, "unit": "cm"},
                     {"id": "height", "label": "Perpendicular height", "value": height, "unit": "cm"}],
            "fields": [field]}))
        payload["workbook"]["activities"].append(activity.model_dump(mode="json"))
    return LessonPackage.model_validate(payload)


@pytest.mark.parametrize("sentence,bound", [
    # fix3-r3 geometry_novice_evidence: "9 x 8 / 2 = 36 square centimetres" (spaced letter x).
    ("Area is half the product: 9 x 8 / 2 = 36 square centimetres.", True),
    ("Area is half the product: 9 x 8 / 2 = 37 square centimetres.", False),
    # fix3-r3 geometry_novice_evidence: "... would give 10 x 8 / 2 = 40, which is wrong" names a misconception.
    ("Using the rectangle instead would give 72, which is wrong.", True),
    ("The area is 72 square centimetres.", False),   # The misconception value asserted as the answer.
])
def test_misconception_values_bind_only_where_the_sentence_calls_them_wrong(sentence, bound):
    claim, patch = _bind(_geometry_package(sentence), sentence.split(":")[0].split(" would")[0][:20])
    assert (claim in bound_ids(patch)) is bound


def test_empty_data_diagnostic_names_each_number_and_where_it_is():
    activity = _qualitative_activity("The memo says owner earnings were $82,000 last year.")
    with pytest.raises(builder.UndeclaredNumbersError) as raised:
        builder.require_declared_numbers(activity)
    [diagnostic] = builder._diagnostics(raised.value)
    assert "but data is []" in diagnostic["message"]
    assert "instructions shows 82000" in diagnostic["message"]


@pytest.mark.parametrize("shown,flagged", [("2", False), ("100", True)])
def test_a_constant_counts_as_declared_only_where_a_declared_formula_uses_it(shown, flagged):
    # confirm-r3 accounting_novice_evidence: "... including 100 credits for stock delivered in the previous
    # month" was never declared; 100 is a formula constant only in percentage formulas.
    activity = _numeric_activity(
        f"Original fictional case. Revenue earned is 9000 credits, expenses incurred are 6200 credits, and "
        f"{shown} credits were paid for stock delivered in the previous month. Calculate accrual profit.",
        LEDGER, "(revenue_earned - expenses_incurred) * 2 / 2")
    if flagged:
        with pytest.raises(builder.UndeclaredNumbersError) as raised:
            builder.require_declared_numbers(activity)
        assert raised.value.numbers == [("instructions", "100")]
    else:
        builder.require_declared_numbers(activity)
