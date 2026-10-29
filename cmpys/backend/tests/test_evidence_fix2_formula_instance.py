"""Formula instantiations with no shown result (smoke2, 29 Oct 2026).

(a) Armenian article/case suffixes after a numeral ("2-ն") are not a minus sign.
(b) A displayed distractor/misconception/question formula is accepted only when
its whole expression tree, with every number mapped to bound data and declared
constants of ONE case, equals a declared canonical or misconception expression
of that case (or the quote is exactly a declared choice label). Nothing else in
the span is excused; the prose claim about the formula stays unchecked, exactly
as for canonical roles.

Recorded fragments: geometry_novice n7 and geometry_experienced n12.
"""
import copy

import pytest

from app.services.planning.lesson_review import (
    LessonReview, _symbolic_quote_is_complete, grounded_failures, numeric_spans,
)


def review(*, math_roles=(), calculations=(), literal_facts=()):
    return LessonReview.model_validate({
        "acceptable": True, "issues": [], "practice_minutes": 3,
        "contains_calculations": bool(calculations),
        "calculations": [{**check, "location": ", ".join(check["claim_ids"])} for check in calculations],
        "literal_facts": list(literal_facts), "math_roles": list(math_roles)})


def claim_for(lesson, package, fragment):
    ids = [key for key, span in numeric_spans(lesson, package).items() if fragment in span]
    assert len(ids) == 1, (fragment, numeric_spans(lesson, package))
    return ids[0]


# --- geometry_novice n7 (Armenian, private transfer activity) ---------------

N7 = ("b × h-ն ուղղանկյան մակերեսն է և կկրկնապատկի արդյունքը, (b + h) ÷ 2-ն չափերի միջինն է, "
      "իսկ b + h-ն պարզապես երկու երկարությունների գումար է՝ ոչ մակերես։")
TRANSFER = {
    "id": "independent_transfer", "title": "Տանիք", "kind": "transfer",
    "instructions": "Ընտրիր ճիշտ արտահայտությունը։",
    "data": [{"id": "roof_base", "label": "Տանիքի եռանկյան հիմքը", "value": 9.0, "unit": "մ"},
             {"id": "roof_height", "label": "Հիմքին ուղղահայաց բարձրությունը", "value": 4.0, "unit": "մ"}],
    "fields": [
        {"id": "formula", "label": "Որ արտահայտությունն է ճիշտ", "kind": "multi_choice", "unit": "",
         "choices": [{"id": "bh2", "label": "b × h ÷ 2"}, {"id": "bh", "label": "b × h"},
                     {"id": "bh_sum", "label": "(b + h) ÷ 2"}, {"id": "bh_sum2", "label": "b + h"}],
         "expression": None, "correct_choices": ["bh2"]},
        {"id": "area", "label": "Տանիքի եռանկյան մակերեսը (քառ․ մ)", "kind": "number", "unit": "քառ․ մ",
         "choices": [], "expression": "(roof_base * roof_height) / 2",
         "misconceptions": [{"expression": "roof_base * roof_height", "feedback": "ուղղանկյուն"},
                            {"expression": "(roof_base + roof_height) / 2", "feedback": "գումար"}]},
    ],
    "worked_solution": N7, "hint": "", "minutes_min": 1, "minutes_max": 2,
}
NOVICE = {"teaching_cases": [], "private_workbook": {"activities": [TRANSFER]}}
LESSON = {}
N7_ROLE = {"claim_id": "n1", "case_id": "practice.independent_transfer", "field_id": "area",
           "coefficient": 2, "symbol_bindings": {}}


def novice_gate(role, text=N7, package=NOVICE):
    package = copy.deepcopy(package)
    package["private_workbook"]["activities"][0]["worked_solution"] = text
    assert list(numeric_spans(LESSON, package)) == ["n1"]
    return grounded_failures(review(math_roles=[role]), LESSON, package)


def test_armenian_suffix_after_numeral_is_not_a_minus_sign_in_completeness_check():
    quote = "(b + h) ÷ 2"
    start = N7.index(quote)
    assert _symbolic_quote_is_complete(N7, start, start + len(quote))
    for suffix in ("-ն", "-ը", "-ում", "-ի", "-ով"):
        text = f"Այսինքն, {quote}{suffix} է։"
        assert _symbolic_quote_is_complete(text, text.index(quote), text.index(quote) + len(quote)), suffix
    # A real minus after the quote still makes it a subexpression.
    for tail in (" - 1", "-1", "-b", " − h"):
        text = f"Այսինքն, {quote}{tail} է։"
        assert not _symbolic_quote_is_complete(text, text.index(quote), text.index(quote) + len(quote)), tail


def test_recorded_n7_divisor_entry_passes_as_declared_choice_label():
    # The recorded reviewer entry: role divisor, no bindings, quote equal to
    # the declared choice label "(b + h) ÷ 2" of the same case.
    assert novice_gate({**N7_ROLE, "role": "divisor", "source_quote": "(b + h) ÷ 2"}) == []


def test_n7_symbolic_entry_passes_as_declared_misconception():
    role = {**N7_ROLE, "role": "symbolic_formula", "source_quote": "(b + h) ÷ 2",
            "symbol_bindings": {"b": "roof_base", "h": "roof_height"}}
    assert novice_gate(role) == []


def test_n7_numeric_instantiation_of_misconception_passes():
    text = N7.replace("(b + h) ÷ 2-ն", "(9 + 4) ÷ 2-ն")
    assert novice_gate({**N7_ROLE, "role": "divisor", "source_quote": "(9 + 4) ÷ 2"}, text) == []


@pytest.mark.parametrize("text, quote", [
    # Not a declared expression (no such choice, canonical or misconception).
    (N7.replace("(b + h) ÷ 2-ն", "(b - h) ÷ 2-ն"), "(b - h) ÷ 2"),
    (N7.replace("(b + h) ÷ 2-ն", "(b + h) ÷ 3-ն"), "(b + h) ÷ 3"),
    # A number that is not in the case.
    (N7.replace("(b + h) ÷ 2-ն", "(9 + 5) ÷ 2-ն"), "(9 + 5) ÷ 2"),
    # Same tree but swapped operands is a different declared expression.
    (N7.replace("(b + h) ÷ 2-ն", "2 ÷ (b + h)-ն"), "2 ÷ (b + h)"),
    # A real minus continues the expression: the quote is only a subexpression.
    (N7.replace("(b + h) ÷ 2-ն", "(b + h) ÷ 2 - 1-ն"), "(b + h) ÷ 2"),
    # An equation side shows a result; that needs calculation evidence.
    (N7.replace("(b + h) ÷ 2-ն", "(b + h) ÷ 2 = 6.5-ն"), "(b + h) ÷ 2"),
])
def test_undeclared_or_incomplete_instantiations_still_fail(text, quote):
    for role in ({**N7_ROLE, "role": "divisor", "source_quote": quote},
                 {**N7_ROLE, "role": "symbolic_formula", "source_quote": quote,
                  "symbol_bindings": {"b": "roof_base", "h": "roof_height"}}):
        if "b" not in quote:
            role["symbol_bindings"] = {}
        assert novice_gate(role, text), (text, role)


def test_symbolic_misconception_requires_exact_one_to_one_bindings():
    role = {**N7_ROLE, "role": "symbolic_formula", "source_quote": "(b + h) ÷ 2"}
    package = copy.deepcopy(NOVICE)
    # Remove the declared choice so only the misconception path could apply.
    package["private_workbook"]["activities"][0]["fields"][0]["choices"] = []
    assert novice_gate({**role, "symbol_bindings": {"b": "roof_base", "h": "roof_height"}}, package=package) == []
    for bindings in ({}, {"b": "roof_base"}, {"b": "roof_base", "h": "roof_base"},
                     {"b": "roof_base", "h": "roof_height", "x": "roof_height"},
                     {"b": "roof_base", "h": "missing_datum"}):
        assert novice_gate({**role, "symbol_bindings": bindings}, package=package), bindings


def test_instantiation_from_another_case_fails():
    other = copy.deepcopy(TRANSFER)
    other["id"] = "other"
    other["data"] = [{"id": "roof_base", "label": "x", "value": 5.0}, {"id": "roof_height", "label": "y", "value": 3.0}]
    other["fields"][0]["choices"] = []
    other["worked_solution"] = ""
    package = {"teaching_cases": [], "private_workbook": {"activities": [copy.deepcopy(TRANSFER), other]}}
    package["private_workbook"]["activities"][0]["worked_solution"] = N7.replace("(b + h) ÷ 2-ն", "(9 + 4) ÷ 2-ն")
    role = {**N7_ROLE, "role": "divisor", "source_quote": "(9 + 4) ÷ 2"}
    assert grounded_failures(review(math_roles=[role]), LESSON, package) == []
    # The span belongs to the transfer activity; another case cannot license it.
    assert grounded_failures(review(math_roles=[{**role, "case_id": "practice.other"}]), LESSON, package)


def test_rest_of_span_is_not_excused():
    text = N7.replace("չափերի միջինն է", "չափերի միջինն է, այսինքն 7")
    assert novice_gate({**N7_ROLE, "role": "divisor", "source_quote": "(b + h) ÷ 2"}, text)


# --- geometry_experienced n12 (English lesson question) ---------------------

FLAG = {"id": "tri_case_flag", "data": [
    {"id": "flag_base", "label": "Base of the triangular flag", "value": 24.0, "unit": "centimeters"},
    {"id": "flag_height", "label": "Perpendicular height from the base", "value": 9.0, "unit": "centimeters"},
], "results": [{"id": "flag_area", "label": "Area of the triangular flag",
                "expression": "(flag_base * flag_height) / 2", "unit": "square centimeters", "decimal_places": 1}]}
GUIDED = {"id": "guided", "title": "Flag", "kind": "guided", "instructions": "Find the area.",
          "data": copy.deepcopy(FLAG["data"]),
          "fields": [{"id": "flag_area", "label": "Area of the flag (square centimeters)", "kind": "number",
                      "unit": "square centimeters", "choices": [], "expression": "(flag_base * flag_height) / 2",
                      "misconceptions": [{"expression": "flag_base * flag_height", "feedback": "rectangle"},
                                         {"expression": "flag_base + flag_height", "feedback": "sum"}]}],
          "worked_solution": "", "hint": "", "minutes_min": 1, "minutes_max": 2}
EXPERIENCED = {"teaching_cases": [FLAG], "private_workbook": {"activities": [GUIDED]}}
N12 = "Can you still use 24 × 9 ÷ 2?"
N12_ROLE = {"case_id": "teaching.tri_case_flag", "field_id": "flag_area", "role": "divisor",
            "coefficient": 2, "symbol_bindings": {}}


def experienced_gate(text, **role):
    lesson = {"lesson_content": text}
    claim = claim_for(lesson, EXPERIENCED, text.split()[-1].rstrip("?"))
    return grounded_failures(review(math_roles=[{**N12_ROLE, "claim_id": claim, **role}]),
                             lesson, EXPERIENCED, expected_claim_ids={claim})


def test_recorded_n12_question_passes_with_whole_formula_quote():
    assert experienced_gate(N12, source_quote="24 × 9 ÷ 2") == []
    assert experienced_gate(N12, source_quote="24 × 9 ÷ 2", role="symbolic_formula") == []
    # The practice case declares the same data and expressions; it is one case too.
    assert experienced_gate(N12, source_quote="24 × 9 ÷ 2", case_id="practice.guided") == []


def test_misconception_instantiation_without_result_passes():
    assert experienced_gate("Can you still use 24 × 9?", source_quote="24 × 9", case_id="practice.guided") == []


def test_recorded_n12_operator_only_quote_still_fails():
    assert experienced_gate(N12, source_quote="÷ 2?")


@pytest.mark.parametrize("text, quote", [
    ("Can you still use 24 × 8 ÷ 2?", "24 × 8 ÷ 2"),       # 8 is not case data
    ("Can you still use 24 + 9 ÷ 2?", "24 + 9 ÷ 2"),       # not a declared tree
    ("Can you still use 24 × 9 ÷ 3?", "24 × 9 ÷ 3"),       # undeclared constant
    ("Can you still use 9 × 24 ÷ 2?", "9 × 24 ÷ 2"),       # different tree order
    ("Can you still use 24 × 9 ÷ 2 = 108?", "24 × 9 ÷ 2"),  # shows a result: needs a calculation
    ("Can you still use 24 × 9 ÷ 2 × 3?", "24 × 9 ÷ 2"),   # only a subexpression
    ("Can you still use 124 × 9 ÷ 2?", "24 × 9 ÷ 2"),      # clipped numeral
    ("Can you still use 24 × 9 ÷ 2 thousand?", "24 × 9 ÷ 2"),  # scaled last numeral
    ("Can you still use 24 × 9 ÷ 2 (twice)?", "24 × 9 ÷ 2"),  # parenthetical qualifier
])
def test_wrong_or_partial_formulas_still_fail(text, quote):
    assert experienced_gate(text, source_quote=quote)


def test_misconception_of_teaching_case_is_not_borrowed_from_practice_case():
    # "24 × 9" is a misconception of practice.guided only; the teaching case
    # declares just the canonical (24 × 9) / 2.
    assert experienced_gate("Can you still use 24 × 9?", source_quote="24 × 9")


# --- Review round 2: an instance must be the only numeric content of its clause/row ---

def instance_gate(text, facts=(), calculations=(), package=EXPERIENCED, **role):
    lesson = {"lesson_content": text}
    spans = numeric_spans(lesson, package)
    claim = list(spans)[0]
    roles = [{**N12_ROLE, "claim_id": claim, "source_quote": "24 × 9 ÷ 2", **role}]
    return grounded_failures(review(math_roles=roles, literal_facts=[{"claim_id": claim, **f} for f in facts],
                                    calculations=[{**c, "claim_ids": [claim]} for c in calculations]),
                             lesson, package)


AREA_216 = {"case_id": "teaching.tri_case_flag", "expression": "flag_base * flag_height", "claimed_result": 216}
HEIGHT = {"case_id": "teaching.tri_case_flag", "datum_ids": ["flag_height"]}
BASE = {"case_id": "teaching.tri_case_flag", "datum_ids": ["flag_base"]}
PERIMETER_PACKAGE = copy.deepcopy(EXPERIENCED)
PERIMETER_PACKAGE["teaching_cases"][0]["data"].append(
    {"id": "flag_perimeter", "label": "Perimeter of the flag", "value": 216.0, "unit": "centimeters"})
PERIMETER = {"case_id": "teaching.tri_case_flag", "datum_ids": ["flag_perimeter"]}


@pytest.mark.parametrize("text, kwargs", [
    ("For the flag, 24 × 9 ÷ 2 gives 216 square centimeters.", {"calculations": [AREA_216]}),
    ("So the flag's area, 24 × 9 ÷ 2, gives 9 square centimeters.", {"facts": [HEIGHT]}),
    ("Area: 24 × 9 ÷ 2 → 216", {"facts": [PERIMETER], "package": PERIMETER_PACKAGE}),
    ("```steps\n24 × 9 ÷ 2 | 216 | area\n```", {"facts": [PERIMETER], "package": PERIMETER_PACKAGE}),
    ("The area is 24 × 9 ÷ 2, that is 216.", {"facts": [PERIMETER], "package": PERIMETER_PACKAGE}),
    ("Using 24 × 9 ÷ 2 we get 216.", {"facts": [PERIMETER], "package": PERIMETER_PACKAGE}),
    ("So 24 × 9 ÷ 2 gives 24 square centimeters.", {"facts": [BASE]}),
    ("```steps\nArea of the flag | 24 × 9 ÷ 2 | 24\n```", {"facts": [BASE]}),
    ("So 24 × 9 ÷ 2 gives the area.", {}),          # result verb right after the formula
    ("So 24 × 9 ÷ 2 is the area.", {}),
    ("So 24 × 9 ÷ 2 makes the area.", {}),
    ("So 24 × 9 ÷ 2 → area.", {}),
])
def test_instance_with_a_shown_result_or_other_numeral_in_its_clause_fails(text, kwargs):
    assert instance_gate(text, **kwargs)


def test_using_misconception_with_wrong_result_fails():
    assert instance_gate("Using 24 × 9 we get 9.", source_quote="24 × 9", case_id="practice.guided",
                         facts=[{"case_id": "practice.guided", "datum_ids": ["flag_height"]}])


def test_other_sentence_numerals_do_not_block_a_question_instance():
    text = "The flag is 24 centimeters wide. Can you still use 24 × 9 ÷ 2?"
    lesson = {"lesson_content": text}
    claim = claim_for(lesson, EXPERIENCED, "24 × 9 ÷ 2")
    assert grounded_failures(review(math_roles=[{**N12_ROLE, "claim_id": claim, "source_quote": "24 × 9 ÷ 2"}]),
                             lesson, EXPERIENCED, expected_claim_ids={claim}) == []
