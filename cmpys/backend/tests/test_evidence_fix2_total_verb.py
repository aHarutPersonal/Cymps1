"""A bound datum's own label may be followed by "total(s)/came to/were" (smoke2, 29 Oct 2026).

Recorded fragment: accounting_experienced n1. The label must end immediately
before the verb and the value must equal that exact cited raw datum.
"""
import pytest

from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans


CAFE = {"id": "case_cafe_march", "data": [
    {"id": "sales_earned_march", "label": "Sales earned from meals served in March", "value": 9200.0, "unit": "USD"},
    {"id": "cash_from_march_sales", "label": "Cash collected in March for March meals", "value": 7100.0, "unit": "USD"},
    {"id": "cash_from_feb_meals", "label": "Cash collected in March for February meals", "value": 900.0, "unit": "USD"},
]}
PACKAGE = {"teaching_cases": [CAFE]}
RECORDED = "Sales earned from meals served in March total 9200, of which only 7100 was collected in March."
FACT = {"claim_id": "n1", "case_id": "teaching.case_cafe_march",
        "datum_ids": ["sales_earned_march", "cash_from_march_sales"]}


def gate(text, facts=(FACT,)):
    lesson = {"lesson_content": text}
    assert list(numeric_spans(lesson, PACKAGE)) == ["n1"]
    review = LessonReview.model_validate({
        "acceptable": True, "issues": [], "practice_minutes": 3, "contains_calculations": False,
        "calculations": [], "literal_facts": list(facts)})
    return grounded_failures(review, lesson, PACKAGE)


def test_recorded_total_sentence_with_recorded_evidence_passes():
    assert gate(RECORDED) == []


@pytest.mark.parametrize("verb", ["totals", "totaled", "totalled", "came to", "were", "total"])
def test_each_accepted_verb_after_the_exact_label_passes(verb):
    assert gate(RECORDED.replace(" total 9200", f" {verb} 9200")) == []


def test_total_with_a_different_value_still_fails():
    errors = gate(RECORDED.replace("total 9200", "total 9300"))
    assert errors and all(error.startswith("n1:") for error in errors)


def test_total_value_equal_to_datum_but_not_cited_still_fails():
    # 9200 is a datum of the case, but the evidence cites only the cash datum.
    errors = gate(RECORDED, facts=({**FACT, "datum_ids": ["cash_from_march_sales"]},))
    assert errors


def test_label_of_a_different_datum_before_total_still_fails():
    text = "Cash collected in March for March meals total 9200, of which only 7100 was collected in March."
    assert "n1: derived result cannot be classified as a literal fact" in gate(text)


def test_label_must_end_immediately_before_the_verb():
    text = "Sales earned from meals served in March and refunds total 9200, of which only 7100 was collected in March."
    assert "n1: derived result cannot be classified as a literal fact" in gate(text)



@pytest.mark.parametrize("text, ids", [
    ("Cash collected in March for February meals plus sales earned from meals served in March total 9200.",
     ["sales_earned_march"]),
    ("Cash collected in March for February meals and sales earned from meals served in March total 9200.",
     ["sales_earned_march"]),
    ("Cash collected in March for February meals and sales earned from meals served in March total 9200.",
     ["sales_earned_march", "cash_from_feb_meals"]),
    ("February and March sales earned from meals served in March total 9200.", ["sales_earned_march"]),
    ("Together, sales earned from meals served in March total 9200.", ["sales_earned_march"]),
    ("Combined with deposits, sales earned from meals served in March total 9200.", ["sales_earned_march"]),
])
def test_total_verb_requires_the_label_to_begin_its_clause(text, ids):
    assert gate(text, facts=({**FACT, "datum_ids": ids},))


def test_total_verb_after_article_and_new_sentence_passes():
    assert gate("The sales earned from meals served in March total 9200.",
                facts=({**FACT, "datum_ids": ["sales_earned_march"]},)) == []
    assert gate("Rent is separate. Sales earned from meals served in March total 9200.",
                facts=({**FACT, "datum_ids": ["sales_earned_march"]},)) == []
