"""Novice geometry false alarms from the 2026-11-06 paid re-run.

Recorded attempts failed on "cm^2" read as a quantity, on the exponents of a
shown Pythagorean step, on "÷ 2 կանոնը" ("the ÷ 2 rule"), on a wrong quick-check
option with a multi-word unit and on a formula with powers that the solution
compiler could not render. Each rule has a wrong twin that must still fail.
"""
import ast

import pytest

from app.services.planning.lesson_review import (
    CalculationCheck, LessonReview, _coefficient_suffix_error, _declared_unit_spellings, _formula_constant_remainder,
    _unselected_option_ranges,
)
from app.services.planning.activity_draft import without_wire_noise
from app.services.planning.numeric_metadata import incidental_numeral_intervals, quantity_numerals
from app.services.practice.contracts import _TYPESET_OPERATORS
from app.services.practice.solution_compiler import _numeric_expression


def numerals(source):
    return [text for _, _, text in quantity_numerals(source)]


def test_an_exponent_after_a_unit_or_symbol_is_not_a_quantity():
    assert numerals("Write the area in cm^2.") == []
    assert numerals("For a right triangle, a^2 + b^2 = c^2.") == []
    # A power of a number still shows its base and result.
    assert numerals("Since 5^2 = 25, the square is 25 cm^2.") == ["5", "2", "25", "25"]
    assert numerals("The hall holds 10^3 seats.") == ["10", "3"]


def proof(expression, value):
    return CalculationCheck(location="n1", claim_ids=["n1"], expression=expression, claimed_result=value,
                            claimed_literal=str(value))


def remainder(span, expression):
    check = proof(expression, 13)  # in metres, like its operands
    return _formula_constant_remainder(span, [check], {id(check): _declared_unit_spellings("m")}, {})


def test_a_shown_square_is_the_proofs_own_squaring():
    assert remainder("giving PQ = sqrt(5^2 + 12^2) = 13 m and the rest.", "sqrt(5.0 * 5.0 + 12.0 * 12.0)") == \
        "giving PQ = sqrt(5^  + 12^ ) = 13 m and the rest."


@pytest.mark.parametrize("span,expression", [
    ("giving PQ = sqrt(5^2 + 12^3) = 13 m.", "sqrt(5.0 * 5.0 + 12.0 * 12.0)"),  # a cube the proof never takes
    ("giving PQ = sqrt(7^2 + 12^2) = 13 m.", "sqrt(5.0 * 5.0 + 12.0 * 12.0)"),  # a base the proof never squares
])
# Only the square of 12 is consumed in each twin.
def test_an_exponent_the_proof_does_not_take_keeps_its_evidence_requirement(span, expression):
    assert remainder(span, expression).count("^ ") == 1


def test_a_rule_noun_after_a_formula_constant_is_not_a_scale():
    for source in ("հիմք × բարձրություն ÷ 2 կանոնը", "base × height ÷ 2 rule"):
        assert _coefficient_suffix_error(source, source.index("2") + 1) is None
    for source in ("հիմք × բարձրություն ÷ 2 հազար", "base × height ÷ 2 thousand", "base × height ÷ 2 metres"):
        assert _coefficient_suffix_error(source, source.index("2") + 1)


def check_block(*options):
    return "```check\nQ: What is the area?\n" + "\n".join(options) + "\nWhy: Half the base times the height.\n```"


def test_a_wrong_option_with_a_multi_word_unit_names_a_choice():
    source = check_block("- [x] 30 square centimetres", "- [ ] 42 square centimetres", "- [ ] 60 cm²")
    covered = {source[start:end] for start, end in _unselected_option_ranges(source)}
    assert covered == {"42", "60"}


def test_a_keyed_or_explained_option_keeps_its_evidence_requirement():
    source = check_block("- [x] 30 square centimetres", "- [ ] 42 square centimetres because the base is 7")
    assert _unselected_option_ranges(source) == []


def rendered(expression, data):
    return _numeric_expression(ast.parse(expression.translate(_TYPESET_OPERATORS), mode="eval").body, data)


def test_squares_and_cubes_render_as_explicit_products():
    # Parsed as Python XOR, "a^2 - b^2" would be a ^ (2 - b) ^ 2; as a power it is (a*a) - (b*b).
    assert rendered("a^2 - b^2", {"a": 13, "b": 12}) == "((13 * 13) - (12 * 12))"
    assert rendered("sqrt(a ** 2 + b ** 2)", {"a": 5, "b": 12}) == "sqrt(((5 * 5) + (12 * 12)))"
    assert rendered("a^3", {"a": 2}) == "(2 * 2 * 2)"


@pytest.mark.parametrize("expression", ["a^4", "a ** b", "a ** 0.5"])
def test_other_powers_stay_unsupported(expression):
    with pytest.raises(ValueError, match="Unsupported private solution arithmetic"):
        rendered(expression, {"a": 2, "b": 3})


# --- Geometry round 3 (paid, 2026-11-06) -------------------------------------

def test_a_wrong_formula_option_names_a_choice():
    source = check_block("- [x] base × height ÷ 2", "- [ ] base × slanted edge ÷ 2", "- [ ] 8 × 5 × 2")
    covered = [source[start:end] for start, end in _unselected_option_ranges(source)]
    assert covered == ["2", "8", "5", "2"]


@pytest.mark.parametrize("option", [
    "- [ ] base × height = 40",                 # states a result
    "- [ ] base × 2, because the height is 7",  # gives a reason with a value
    "- [ ] the 40 square metres of base × height",
])
def test_a_formula_option_with_a_claim_keeps_its_evidence_requirement(option):
    source = check_block("- [x] base × height ÷ 2", option)
    assert _unselected_option_ranges(source) == []


def test_turning_a_copy_half_way_is_an_angle_constant():
    source = "Two copies, one turned 180 degrees, form a parallelogram."
    assert [source[start:end] for start, end in incidental_numeral_intervals(source)] == ["180"]
    view = "A 180 degree view of the plot."
    assert incidental_numeral_intervals(view) == []


def test_an_empty_punctuation_key_is_a_placeholder():
    field = {"id": "pairing", "kind": "choice", "_": None, "__": ""}
    assert without_wire_noise({"fields": [field]})["fields"][0] == {"id": "pairing", "kind": "choice"}
    kept = {"id": "pairing", "kind": "choice", "_": "QR"}
    assert without_wire_noise({"fields": [kept]})["fields"][0] == kept


# --- The halving row the writer contract teaches (geometry round 3) ----------

def test_the_taught_halving_rows_validate_and_prove_one_value_per_row():
    from app.services.planning.lesson_review import grounded_failures, numeric_spans
    from app.services.planning.lesson_writer import _tutorial_contract
    from app.services.planning.tutorial_blocks import fence_errors
    from tests.test_derivation_steps_in_words import review

    contract = " ".join(_tutorial_contract().split())
    assert '"Base × height | | 6 × 4 = 24", then "Half of it | 12 | <why>"' in contract
    rows = ("title: Triangle area\nunit: cm²\nBase | | 6 cm along the bottom.\nHeight | | 4 cm, at a right angle.\n"
            "Base × height | | 6 × 4 = 24, the parallelogram two copies form.\n"
            "Half of it | 12 | The triangle is half of that parallelogram.\n= Area | 12\n")
    assert fence_errors("steps", rows, case_has_numbers=True) == []
    case = {"id": "tri", "data": [{"id": "base", "label": "Base", "value": 6.0, "unit": "cm"},
                                  {"id": "height", "label": "Perpendicular height", "value": 4.0, "unit": "cm"}],
            "results": [{"id": "area", "expression": "base * height / 2", "unit": "cm²"}]}
    lesson, package = {"lesson_content": "## Worked Example\n```steps\n" + rows + "```"}, {"teaching_cases": [case]}
    span = {text.split(" |")[0]: key for key, text in numeric_spans(lesson, package).items()}
    facts = [{"claim_id": span["Base"], "case_id": "teaching.tri", "datum_ids": ["base"]},
             {"claim_id": span["Height"], "case_id": "teaching.tri", "datum_ids": ["height"]}]
    proofs = [{"claim_ids": [span["Base × height"]], "expression": "base * height", "claimed_result": 24},
              {"claim_ids": [span["Half of it"], span["= Area"]], "expression": "base * height / 2", "claimed_result": 12}]
    assert grounded_failures(review(proofs, facts, case_id="teaching.tri"), lesson, package) == []


# --- Geometry round 4 (paid, 2026-11-06) -------------------------------------

BRACKET = {"id": "bracket", "data": [
    {"id": "base", "label": "Base", "value": 10.0, "unit": "cm"},
    {"id": "base_height", "label": "Height to the base", "value": 3.5, "unit": "cm"},
    {"id": "other_side", "label": "Other side", "value": 6.0, "unit": "cm"},
], "results": [{"id": "area", "expression": "base * base_height / 2", "unit": "cm2"}]}
SHOWN_AREA = "Area = base × base height ÷ 2 = 10 × 3.5 ÷ 2 = {result} cm²."


def bracket_failures(text, bindings, result=17.5):
    """The evidence gate's errors plus the review's own arithmetic check."""
    from app.services.planning.lesson_review import grounded_failures, numeric_spans
    from tests.test_derivation_steps_in_words import review

    lesson, package = {"lesson_content": text}, {"teaching_cases": [BRACKET]}
    assert list(numeric_spans(lesson, package)) == ["n1"]
    verdict = review([{"claim_ids": ["n1"], "expression": "base * base_height / 2", "claimed_result": result}],
                     [{"claim_id": "n1", "case_id": "teaching.bracket", "datum_ids": ["base", "base_height"]}],
                     case_id="teaching.bracket").model_dump(mode="json")
    verdict["math_roles"] = [{"claim_id": "n1", "case_id": "teaching.bracket", "field_id": "area",
                              "role": "symbolic_formula", "coefficient": 2,
                              "source_quote": "base × base height ÷ 2", "symbol_bindings": bindings}]
    verdict = LessonReview.model_validate(verdict)
    return grounded_failures(verdict, lesson, package) + verdict.failures()


def test_a_formula_with_a_two_word_symbol_and_an_ascii_square_unit_is_proven():
    assert bracket_failures(SHOWN_AREA.format(result="17.5"), {"base": "base", "base height": "base_height"}) == []


@pytest.mark.parametrize("bindings", [
    {"base": "base_height", "base height": "base"},   # swapped meanings
    {"base": "base", "height": "base_height"},        # a symbol that is not the quote's own
    {"base": "base", "base height": "other_side"},    # a datum the formula does not use
])
def test_a_wrong_symbol_binding_is_still_rejected(bindings):
    assert any("mathematical role invalid" in error
               for error in bracket_failures(SHOWN_AREA.format(result="17.5"), bindings))


def test_a_chain_operand_is_not_a_result_but_a_wrong_result_still_is():
    bindings = {"base": "base", "base height": "base_height"}
    # 18 would be 17.5 correctly rounded to its displayed precision; 19 is not.
    errors = bracket_failures(SHOWN_AREA.format(result="19"), bindings, result=19)
    assert "n1: 10.0 * 3.5 / 2 = 17.5, not 19" in errors
    assert "n1: numeric span contains additional unverified values: 2" in errors  # no proof covers the ÷ 2
    assert not any("additional unverified values: 10" in error for error in errors)
    errors = bracket_failures("Area = base × base height ÷ 2 = 10 cm².", bindings, result=17.5)
    assert errors


def test_ascii_and_caret_square_units_spell_the_same_unit():
    from app.services.planning.lesson_review import _declared_unit_spellings
    assert {"cm²", "cm2", "cm^2"} <= _declared_unit_spellings("cm2")
    assert {"m²", "m2", "m^2"} <= _declared_unit_spellings("m2")
    assert "cm²" not in _declared_unit_spellings("cm3")


# --- Quick checks change a condition in words (owner decision, 2026-11-06) ----

TRIANGLE = {"id": "tri", "data": [{"id": "base", "label": "Base", "value": 6.0, "unit": "cm"},
                                  {"id": "height", "label": "Perpendicular height", "value": 4.0, "unit": "cm"}],
            "results": [{"id": "area", "expression": "base * height / 2", "unit": "cm²"}]}


def quick_check(question, why):
    return (f"## Check Your Understanding\n```check\nQ: {question}\n- [x] It doubles\n- [ ] It stays the same\n"
            f"- [ ] It halves\nWhy: {why}\n```")


def test_the_contract_teaches_a_words_only_condition_change():
    import re
    from app.services.planning.lesson_writer import _tutorial_contract
    from app.services.planning.tutorial_blocks import fence_errors

    contract = _tutorial_contract()
    assert "change one condition in words, never with new numbers" in " ".join(contract.split())
    [example] = re.findall(r"```check\n(.*?)```", contract, re.S)
    assert fence_errors("check", example) == []
    assert not re.search(r"\d", example)  # the example itself adds no numbers


def test_a_words_only_check_needs_no_numeric_evidence_but_new_numbers_do():
    from app.services.planning.lesson_review import numeric_spans

    package = {"teaching_cases": [TRIANGLE]}
    words = quick_check("If the perpendicular height doubled and the base stayed the same, what would happen to the area?",
                        "The area is half of base times height, so twice the height gives twice the area.")
    assert numeric_spans({"lesson_content": words}, package) == {}
    numbers = quick_check("If the perpendicular height were 8 cm with the same 6 cm base, what would the area be?",
                          "Half of 6 × 8 is 24 square centimetres.")
    assert numeric_spans({"lesson_content": numbers}, package)  # new numbers still need proof


# --- Check only numbers that need proof (owner decision, 2026-11-06) ----------

def test_a_small_count_of_things_the_case_does_not_measure_needs_no_proof():
    assert numerals("Place 2 copies side by side; the shape has 4 sides.") == []


@pytest.mark.parametrize("source,labels,values,kept", [
    ("It took 3 hours.", (), (), ["3"]),                                   # a unit of time
    ("Revenue rose 3 times.", (), (), ["3"]),                              # a ratio
    ("2 of the 5 invoices are unpaid.", ("Unpaid invoices",), (), ["2", "5"]),  # the case measures invoices
    ("The triangle has 3 sides.", (), (3.0,), ["3"]),                      # equals a case value
    ("The bakery sold 40 loaves.", (), (), ["40"]),                        # not a small count
    ("In March 12 riders joined.", (), (), ["12"]),                        # the case's own people
    ("Add 12 units of stock to the order.", (), (), ["12"]),               # the case's own items
    ("Of its 3 sides, two are equal.", ("Sides measured",), (), ["3"]),    # a datum label names sides
])
def test_measured_counts_units_values_and_years_stay_claims(source, labels, values, kept):
    assert [text for _, _, text in quantity_numerals(source, labels=labels, values=values)] == kept
