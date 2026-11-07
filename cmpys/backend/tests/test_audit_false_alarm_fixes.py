"""False alarms and format failures from the 2026-11-06 benchmark audit.

Each recorded fragment rejected correct content (FAILURE-AUDIT-2026-11-06.md).
Every fix has a wrong twin in the same shape that must still be rejected.
"""
import pytest

from app.services.planning.activity_draft import parse_activity_draft, parse_activity_repair_draft
from app.services.planning.lesson_package import TeachingCase
from app.services.planning.lesson_review import (
    CalculationCheck, LessonReview, _armenian_operation_context_error, _closed_numeric_equation_side_details,
    _constant_units_hold, _declared_unit_spellings, _explicit_derivation, _formula_constant_remainder,
    _matching_result_units, _quoted_in, grounded_failures, numeric_spans,
)
from app.services.planning.numeric_metadata import incidental_numeral_intervals
from tests.test_activity_draft import draft_payload
from tests.test_derivation_steps_in_words import review
from tests.test_geometry_evidence_roles import check as triangle_check
from tests.test_geometry_evidence_roles import review as triangle_review
from tests.test_geometry_evidence_roles import triangle_package
from tests.test_review_quote_normalization import SECTIONS, section_errors
from tests.test_review_quote_normalization import audit as section_audit


def calculation(expression, value=0):
    return CalculationCheck(location="n1", claim_ids=["n1"], expression=expression, claimed_result=value,
                            claimed_literal=str(value))


def test_formula_constant_written_as_an_operand_is_the_proofs_own():
    # A05/A06/A14/A16: "÷ 2" inside a checked equation.
    assert _formula_constant_remainder("Area = AB × 4 ÷ 2 = 12", [calculation("6 * 4 / 2", 12)]) == \
        "Area = AB ×   ÷   = 12"
    assert _formula_constant_remainder("24-ը 2-ի բաժանելով ստանում ենք 12։", [calculation("6 * 4 / 2", 12)]) == \
        "24-ը  -ի բաժանելով ստանում ենք 12։"
    # A divisor the proof does not contain keeps its evidence requirement.
    assert "3" in _formula_constant_remainder("Area = AB × 4 ÷ 3 = 8", [calculation("6 * 4 / 2", 12)])
    assert _formula_constant_remainder("Area = AB × 4 ÷ 2 = 12", []) == "Area = AB × 4 ÷ 2 = 12"


SQUARE_CM, CM = _declared_unit_spellings("սմ²"), _declared_unit_spellings("սմ")


@pytest.mark.parametrize("span", [
    "Սխալ 1՝ 10 × 5 ÷ 2 = 25 սմ² օգտագործում է թեք կողմը։",  # prose after the unit
    "Թեք կողմը 10 × 5 ÷ 2 = 25 հաշվելը սխալ է։",              # no unit at all
    "Աշխատանքային օրինակ՝ հիմքը 10 սմ, մակերեսը 10 × 5 ÷ 2 = 25 քառ.",  # "քառ. սմ" cut by the split
])
def test_a_constant_is_consumed_when_the_spans_units_agree(span):
    assert _constant_units_hold(span, calculation("10 * 5 / 2", 25), SQUARE_CM, CM | SQUARE_CM, {"քառ. սմ"})


@pytest.mark.parametrize("span", [
    "10 × 5 ÷ 2 = 25 սմ։",                 # a length unit for an area
    "10 × 5 ÷ 2 = 25 սմ² հազար։",          # a scale after the unit
    "10 × 5 ÷ 2 = 25 square meters.",      # a known unit the case does not declare
    "(10 m × 5 սմ) ÷ 2 = 25 սմ²։",         # an undeclared operand unit
    "10 × 5 ÷ 2 = 25%.",
])
def test_a_wrong_unit_keeps_the_constant_unproven(span):
    assert not _constant_units_hold(span, calculation("10 * 5 / 2", 25), SQUARE_CM, CM | SQUARE_CM)


def triangle_role_failures(source, checks):
    verdict = triangle_review(*checks).model_dump(mode="json")
    verdict["math_roles"] = [{"claim_id": "n1", "case_id": "practice.guided", "field_id": "area",
                              "role": "divisor", "coefficient": 2, "source_quote": "÷ 2"}]
    return grounded_failures(LessonReview.model_validate(verdict), {},
                             triangle_package(source).review_context())


def test_a_redundant_divisor_role_defers_to_the_verified_proof():
    source = "The area is 18 × 9 ÷ 2, which is 81."
    assert triangle_role_failures(source, [triangle_check()]) == []
    # Without a proof that contains the constant, the role's own defect stands.
    assert triangle_role_failures(source, []) == [
        "n1: mathematical role invalid: quote must explicitly state the matching multiplication or division operation"]
    assert any("quote must explicitly state" in error for error in triangle_role_failures(
        source, [triangle_check(expression="base * height / 3 * 1.5")]))


def test_logical_connectives_and_the_accrued_label_are_not_arithmetic():
    assert not _explicit_derivation("Therefore the record shows 40 visits.")
    assert not _explicit_derivation("Հաշվարկված ծախսերը 4000 դրամ են։")
    assert _explicit_derivation("The computed total is 40 visits.")
    assert _explicit_derivation("12 + 28 makes 40 visits.")


def test_armenian_one_is_not_a_prohibition():
    # A16: "նրա մի կողմի" is "its one side's".
    assert _armenian_operation_context_error("Պատճենը՝ պտտված նրա մի կողմի միջնակետի շուրջ, ", "բաժանեք 2-ի") is None
    assert _armenian_operation_context_error("Արտադրյալը մի ", "բաժանիր 2-ի") == \
        "quoted operation is negated in its source clause"
    assert _armenian_operation_context_error("Արտադրյալը մի՛ ", "բաժանեք 2-ի") == \
        "quoted operation is negated in its source clause"


def angle_digits(source):
    return [source[start:end] for start, end in incidental_numeral_intervals(source)]


def test_a_half_turn_is_an_angle_constant():
    assert angle_digits("Rotate the copy 180° about the midpoint of a side.") == ["180"]
    assert angle_digits("Եռանկյան պատճենը՝ 180° պտտված նրա մի կողմի միջնակետի շուրջ։") == ["180"]
    assert angle_digits("The copy sits 180° from the label.") == []
    assert angle_digits("Rotate the copy 90° about the midpoint of a side.") == []  # a half-turn names 180 only


A01 = {"id": "cafe_march", "data": [
    {"id": "revenue", "label": "Sales earned in March", "value": 9000.0, "unit": "credits"},
    {"id": "cash_received", "label": "Cash collected from March sales", "value": 7400.0, "unit": "credits"},
    {"id": "expense_accrued", "label": "Supplier costs incurred in March", "value": 6400.0, "unit": "credits"},
    {"id": "cash_paid", "label": "Cash paid to suppliers in March", "value": 5600.0, "unit": "credits"},
], "results": [{"id": "accrual_profit", "expression": "revenue - expense_accrued", "unit": "credits"}]}


def a01_failures(text, datum_ids):
    lesson, package = {"lesson_content": text}, {"teaching_cases": [A01]}
    assert list(numeric_spans(lesson, package)) == ["n1"]
    fact = {"claim_id": "n1", "case_id": "teaching.cafe_march", "datum_ids": datum_ids}
    return grounded_failures(review(literal_facts=[fact]), lesson, package)


def test_a_conjunction_after_a_stated_value_opens_a_new_label_clause():
    assert a01_failures("Sales earned total 9000 credits, and supplier costs incurred total 6400 credits.",
                        ["revenue", "expense_accrued"]) == []


@pytest.mark.parametrize("text", [
    "Sales earned, and supplier costs incurred total 6400 credits.",  # no value before the conjunction
    "Sales earned total 9000 credits, and supplier costs plus wages total 6400 credits.",
])
def test_a_conjunction_does_not_hide_a_sum_of_labels(text):
    datums = ["revenue", "expense_accrued"] if "9000" in text else ["expense_accrued"]
    assert "n1: derived result cannot be classified as a literal fact" in a01_failures(text, datums)


RIGHT = {"id": "slope", "data": [
    {"id": "base_length", "label": "Base AB", "value": 10.0, "unit": "m"},
    {"id": "side_bc", "label": "Side BC", "value": 5.0, "unit": "m"},
    {"id": "foot_offset", "label": "Distance from B to the foot", "value": 3.0, "unit": "m"},
], "results": [{"id": "area", "expression": "base_length * sqrt(side_bc * side_bc - foot_offset * foot_offset) / 2",
                "unit": "m²"}]}
HEIGHT = {"claim_ids": ["n1"], "expression": "sqrt(side_bc * side_bc - foot_offset * foot_offset)",
          "claimed_result": 4, "case_id": "teaching.slope"}


def root_failures(text):
    lesson, package = {"lesson_content": text}, {"teaching_cases": [RIGHT]}
    assert list(numeric_spans(lesson, package)) == ["n1"]
    return grounded_failures(review([HEIGHT]), lesson, package)


def test_an_agreeing_square_root_chain_shows_its_own_intermediates():
    # A14: the height of an oblique triangle from its slanted side.
    assert root_failures("The height is h = √(5 × 5 − 3 × 3) = √(25 − 9) = √16 = 4 m.") == []


@pytest.mark.parametrize("text,unproven", [
    ("The height is h = √(5 × 5 − 3 × 3) = √(25 − 8) = √16 = 4 m.", "8, 25"),       # a wrong link
    ("The height is h = √(5 × 5 − 3 × 3) = √(25 − 9) = √16 = 4 km.", "9, 16, 25"),  # another unit
    ("The height is h = √(5 × 5 − 3 × 3) = √(25 − 9) = √16 = 4 m².", "9, 16, 25"),  # the area's unit
])
def test_a_disagreeing_or_mis_united_chain_keeps_its_values_unproven(text, unproven):
    assert f"n1: numeric span contains additional unverified values: {unproven}" in root_failures(text)


def test_square_roots_parse_only_as_their_own_operation():
    assert _closed_numeric_equation_side_details("√(25 − 9) = 4", 10, left=True)[0] == "sqrt(25 - 9)"
    assert _closed_numeric_equation_side_details("x = √16", 3, left=False)[0] == "sqrt(16)"
    assert _closed_numeric_equation_side_details("2√3 = 3.46", 5, left=True) is None


def test_an_unnamed_intermediate_takes_its_operands_one_unit_to_its_dimension():
    def units(expression, case=RIGHT):
        return _matching_result_units(calculation(expression), case, None)
    assert "m" in units("sqrt(side_bc * side_bc - foot_offset * foot_offset)")
    assert "m" in units("side_bc - foot_offset")
    assert "m²" in units("side_bc * foot_offset") and "m" not in units("side_bc * foot_offset")
    assert units("side_bc / foot_offset") == set()       # dimensionless
    assert units("side_bc + 2") == set()                 # a dimensionless constant added
    mixed = {**RIGHT, "data": [*RIGHT["data"][:2], {**RIGHT["data"][2], "unit": "cm"}]}
    assert units("side_bc - foot_offset", mixed) == set()


def test_data_without_a_result_is_told_how_to_recover():
    case = {"id": "library_hours", "assumptions": "A branch opened 15 percent longer; nothing citywide doubled.",
            "data": [{"id": "rise", "label": "Rise at one branch", "value": 15, "unit": "%"}], "results": []}
    with pytest.raises(ValueError, match="Add a result derived from the data, or remove every number"):
        TeachingCase.model_validate(case)


def test_a_quote_that_differs_only_in_letter_case_is_its_sections_own():
    section = "The key idea: the effect and the record of the effect must succeed or fail together."
    assert _quoted_in("The effect and the record of the effect must succeed or fail together.", section) == \
        "the effect and the record of the effect must succeed or fail together."
    assert _quoted_in("The effect and its record must succeed or fail together.", section) is None


def test_an_unquoted_section_is_named_in_the_retry():
    others = [section_audit(key, text) for key, text in SECTIONS.items() if key != "core_framework"]
    errors, _ = section_errors(*others, section_audit("core_framework", "A sentence that is not there."))
    assert errors == ["Each public section audit must quote its own section exactly (not found in: core_framework)"]


def test_an_over_long_optional_text_rubric_is_dropped_never_truncated():
    raw = draft_payload()
    raw["fields"][2]["rubric_criterion"] = "Explains the full model answer: " + "x" * 560
    for parsed in (parse_activity_draft(raw), parse_activity_repair_draft(raw)):
        assert parsed.fields[2].rubric_criterion is None
        assert parsed.fields[2].label == "Explain why sales and collections differ."
    assert raw["fields"][2]["rubric_criterion"].startswith("Explains the full model answer")  # no mutation
    raw["fields"][2]["rubric_criterion"] = "Separates the sale from its cash receipt"
    assert parse_activity_draft(raw).fields[2].rubric_criterion == "Separates the sale from its cash receipt"


def test_a_required_rubric_over_its_limit_is_still_rejected():
    raw = draft_payload()
    raw["fields"][0]["rubric_criterion"] = "x" * 501
    with pytest.raises(ValueError):
        parse_activity_draft(raw)
    with pytest.raises(ValueError):
        parse_activity_repair_draft(raw)


def test_an_unevaluated_sum_of_bound_data_shows_no_result_to_prove():
    # Pilot 2026-11-07 (gpt-6-luna, accounting): "April cash collected totals 700 + 100 credits"
    # was bound to its four raw data and still called a derived result.
    assert a01_failures("Cash collected and paid in March: 7400 + 5600 credits.", ["cash_received", "cash_paid"]) == []


@pytest.mark.parametrize("text", [
    "Cash collected less cash paid: 7400 − 5600 gives 1800 credits.",  # a shown result
    "Cash collected and paid in March: 7400 + 5600 = 13000 credits.",  # an equation
])
def test_an_expression_with_a_shown_result_still_needs_its_calculation(text):
    assert "n1: derived result cannot be classified as a literal fact" in a01_failures(text, ["cash_received", "cash_paid"])
