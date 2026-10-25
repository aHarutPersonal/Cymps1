"""Grouping typography must preserve exact numeric proof and its boundaries."""
from decimal import Decimal

import pytest

from app.services.planning.lesson_review import (
    LessonReview, _numeric_values, _source_literal, grounded_failures, numeric_spans,
)


def verdict(**evidence):
    return LessonReview(acceptable=True, issues=[], practice_minutes=30,
                        contains_calculations=bool(evidence.get("calculations")), **evidence)


@pytest.mark.parametrize("separator", [",", " ", "\u00a0", "\u202f"])
@pytest.mark.parametrize("sign", ["", "+", "-", "−"])
def test_grouped_amounts_keep_exact_sign_and_decimal_precision(separator, sign):
    literal = f"{sign}125{separator}000.00"
    expected = f"{sign.replace('−', '-')}125000.00"
    assert _source_literal(f"Amount: {literal} AMD.", float(expected)) == expected
    assert _numeric_values(f"Amount: {literal} AMD.") == {Decimal(expected)}


@pytest.mark.parametrize("separator", [",", " ", "\u00a0", "\u202f"])
def test_multiple_groups_and_most_precise_source_spelling_are_preserved(separator):
    text = f"Amount is 1{separator}234{separator}567.0, repeated as 1{separator}234{separator}567.000."
    assert _source_literal(text, 1234567) == "1234567.000"
    assert _numeric_values(text) == {Decimal("1234567")}


@pytest.mark.parametrize("text,expected", [
    ("Values: 125, 000", {125, 0}),
    ("Values: 125; 000", {125, 0}),
    ("Values: 125\n000", {125, 0}),
    ("Values: 125\t000", {125, 0}),
    ("Values: 125  000", {125, 0}),
    ("Values: 125 + 000", {125, 0}),
    ("Values: 125 - 234", {125, 234}),
    ("Values: 125 -234", {125, 234}),
    ("Values: 125 * 000", {125, 0}),
    ("Values: 125 / 000", {125, 0}),
    ("Values: 12.5 000", {Decimal("12.5"), 0}),
    ("Values: 12 34", {12, 34}),
    ("Values: 0 123", {0, 123}),
    ("Values: 000 123", {0, 123}),
    ("Values: 125 000, 250 000", {125000, 250000}),
    ("Values: 125 000; 250 000", {125000, 250000}),
    ("Values: 125 000 + 250 000", {125000, 250000}),
    ("Values: 125 000 5", {125000, 5}),
])
def test_grouping_never_consumes_list_delimiters_operators_or_decimal_boundaries(text, expected):
    assert _numeric_values(text) == {Decimal(str(value)) for value in expected}


@pytest.mark.parametrize("separator", [" ", "\u00a0", "\u202f"])
def test_private_raw_fact_and_field_label_bind_to_grouped_amount(separator):
    package = {"private_workbook": {"activities": [{
        "id": "case", "data": [{"id": "cash", "label": "Available cash", "value": 125000}],
        "worked_solution": f"Available cash is 125{separator}000 AMD.",
        "fields": [{"label": f"Explain the use of 125{separator}000 AMD"}],
    }]}}
    spans = numeric_spans({}, package)
    review = verdict(calculations=[], literal_facts=[
        {"claim_id": key, "case_id": "practice.case", "datum_ids": ["cash"]} for key in spans
    ])
    assert len(spans) == 2
    assert grounded_failures(review, {}, package) == []


@pytest.mark.parametrize("separator", [",", " ", "\u00a0", "\u202f"])
@pytest.mark.parametrize("correct", [True, False])
def test_grouped_derived_values_still_require_correct_arithmetic(separator, correct):
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "first", "label": "First amount", "value": 125000},
        {"id": "second", "label": "Second amount", "value": 250000},
    ]}]}
    value = 375000 if correct else 385000
    formatted = f"{value:,}".replace(",", separator)
    lesson = {"lesson_content": f"The total is {formatted}."}
    review = verdict(calculations=[{
        "location": "n1", "claim_ids": ["n1"], "case_id": "teaching.case",
        "expression": "first + second", "claimed_result": value,
    }])
    assert grounded_failures(review, lesson, package) == []
    assert bool(review.failures()) is (not correct)


def test_comparative_raw_value_collision_cannot_hide_behind_grouping():
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "receipts", "label": "Cash receipts", "value": 110000},
        {"id": "revenue", "label": "Current revenue", "value": 100000},
        {"id": "prior", "label": "Prior receipts", "value": 30000},
    ]}]}
    lesson = {"lesson_content": "Cash receipts (110 000) exceed current revenue (100 000) by 30 000."}
    review = verdict(calculations=[], literal_facts=[{
        "claim_id": "n1", "case_id": "teaching.case", "datum_ids": ["receipts", "revenue", "prior"],
    }])
    assert any("derived" in issue for issue in grounded_failures(review, lesson, package))


@pytest.mark.parametrize("text,allowed", [
    ("Write 1 000 words explaining the conclusion.", True),
    ("Write 1\u00a0000–1\u00a0200 words explaining the conclusion.", True),
    ("Write 1\u202f000 words explaining the conclusion.", True),
    ("Write 12 000 words explaining the conclusion.", False),
    ("Write 125 000 words explaining the conclusion.", False),
    ("Spend 1 000 minutes explaining the conclusion.", False),
    ("Total is 125 000; write 1 000 words explaining it.", False),
])
def test_workload_grouping_keeps_original_bounds_and_does_not_exempt_domain_values(text, allowed):
    package = {"teaching_cases": [{"id": "case", "data": [{"id": "raw", "value": 10}]}]}
    review = verdict(calculations=[], literal_fact_ids=list(numeric_spans({"lesson_content": text})))
    assert (not grounded_failures(review, {"lesson_content": text}, package)) is allowed


def test_grouped_wrong_precision_is_still_rejected():
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "first", "value": 125000}, {"id": "second", "value": 3},
    ]}]}
    lesson = {"lesson_content": "The result is 41 666.67, repeated as 41 666.670."}
    review = verdict(calculations=[{
        "location": "n1", "claim_ids": ["n1"], "case_id": "teaching.case",
        "expression": "first / second", "claimed_result": 41666.67,
    }])
    assert grounded_failures(review, lesson, package) == []
    assert review.calculations[0].claimed_literal == "41666.670"
    assert review.failures()  # The more precise spelling falsely claims a third decimal place.


def test_unicode_unary_minus_cannot_match_a_positive_raw_datum():
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "balance", "label": "Balance", "value": 25000},
    ]}]}
    lesson = {"lesson_content": "Balance is −25 000."}
    review = verdict(calculations=[], literal_facts=[{
        "claim_id": "n1", "case_id": "teaching.case", "datum_ids": ["balance"],
    }])
    assert _numeric_values(lesson["lesson_content"]) == {Decimal("-25000")}
    assert grounded_failures(review, lesson, package)


@pytest.mark.parametrize("text", ["100−200", "100 − 200", "100 000−200 000", "100 000 − 200 000"])
def test_unicode_binary_minus_keeps_two_positive_operands_and_requires_proof(text):
    numbers = {100000, 200000} if "000" in text else {100, 200}
    assert _numeric_values(text) == {Decimal(value) for value in numbers}
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "first", "value": min(numbers)}, {"id": "second", "value": max(numbers)},
    ]}]}
    review = verdict(calculations=[], literal_facts=[{
        "claim_id": "n1", "case_id": "teaching.case", "datum_ids": ["first", "second"],
    }])
    assert grounded_failures(review, {"lesson_content": text}, package)


@pytest.mark.parametrize("text", [
    "Intro․ 1) Explain the distinction, 2) Apply it, 3) Check your reasoning։",
    "Intro․1) Explain the distinction,2) Apply it,3) Check your reasoning։",
    "Intro: (1) Explain the distinction, (2) Apply it, (3) Check your reasoning.",
])
def test_complete_inline_ordered_instructions_are_structural(text):
    assert numeric_spans({"lesson_content": text}) == {}


@pytest.mark.parametrize("text,expected", [
    ("Intro: 1) Read 125 000 AMD, 2) Explain the 20% risk.", {125000, 20}),
    ("Intro: 1) Compute the total 375 000, 2) Explain the difference 125 000.", {375000, 125000}),
    ("Intro: 1) Read the account, 3) Compare the result.", {1, 3}),
    ("Intro: 2) Read the account, 3) Compare the result.", {2, 3}),
    ("Intro: 1) Read the account, (2) Compare the result.", {1, 2}),
    ("Intro: 1)20kg", {1, 20}),
    ("Intro: 1) 20kg, 2) 30kg", {1, 20, 2, 30}),
    ("Prices: $1) apple, $2) pear", {1, 2}),
    ("Values: 0.1) item, 0.2) item", {Decimal("0.1"), Decimal("0.2")}),
])
def test_inline_ordinal_normalization_never_erases_domain_values_or_arbitrary_sequences(text, expected):
    assert _numeric_values(text) == {Decimal(str(value)) for value in expected}


def test_inline_list_cannot_exempt_an_unsupported_derived_value():
    text = "Intro: 1) Record total 999, 2) Explain the conclusion."
    package = {"teaching_cases": [{"id": "case", "data": [{"id": "raw", "value": 10}]}]}
    review = verdict(calculations=[], literal_fact_ids=list(numeric_spans({"lesson_content": text})))
    assert grounded_failures(review, {"lesson_content": text}, package)


@pytest.mark.parametrize("operator", ["-", "−"])
@pytest.mark.parametrize("spacing", ["", " ", "\u00a0", "\u202f"])
def test_same_line_binary_minus_is_not_a_negative_raw_operand(operator, spacing):
    text = f"The result is 100{spacing}{operator}200 = −100."
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "first", "value": 100}, {"id": "second", "value": 200},
    ]}]}
    review = verdict(calculations=[{
        "location": "n1", "claim_ids": ["n1"], "case_id": "teaching.case",
        "expression": "first - second", "claimed_result": -100,
    }])
    assert _numeric_values(text) == {Decimal(100), Decimal(200), Decimal(-100)}
    assert grounded_failures(review, {"lesson_content": text}, package) == []
    assert review.failures() == []


@pytest.mark.parametrize("delimiter", [", ", "; ", "\t", "\n", "\n ", "\r\n"])
@pytest.mark.parametrize("sign", ["-", "−"])
def test_negative_list_entry_retains_sign_across_delimiters(delimiter, sign):
    text = f"100{delimiter}{sign}200"
    assert _numeric_values(text) == {Decimal(100), Decimal(-200)}
    assert _source_literal(text, -200) == "-200"
    assert _source_literal(text, 200) is None


@pytest.mark.parametrize("sign", ["-", "−"])
@pytest.mark.parametrize("unit", ["words", "sentences", "minutes"])
def test_negative_workload_cannot_be_exempted_as_valid_metadata(sign, unit):
    text = f"Write {sign}20 {unit} explaining the result."
    package = {"teaching_cases": [{"id": "case", "data": [{"id": "raw", "value": 10}]}]}
    review = verdict(calculations=[], literal_fact_ids=["n1"])
    assert grounded_failures(review, {"lesson_content": text}, package)
