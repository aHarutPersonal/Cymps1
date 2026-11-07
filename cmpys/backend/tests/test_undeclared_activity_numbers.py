"""An activity that shows numbers must declare them as case data before review."""
import json

import pytest

from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning.activity_draft import parse_activity_draft
from app.services.planning.package_builder import (
    LessonPackageActivity, UndeclaredNumbersError, _diagnostics, require_declared_numbers,
)


def _activity(name: str, extra_instructions: str = "") -> LessonPackageActivity:
    draft = json.loads(resolve_prompt_text(name).split("\n", 1)[1])
    draft["instructions"] += extra_instructions
    return LessonPackageActivity.model_validate(parse_activity_draft(draft))


def test_numbers_without_case_data_are_rejected():
    # Live run: four regenerations quoted "$82,000" in a sample memo with
    # data: []; the evidence review rejected every package after its full cost.
    activity = _activity("tutorial_exemplar_qualitative.txt",
                         " The memo says owner earnings were $82,000 last year.")
    assert activity.data == []
    with pytest.raises(UndeclaredNumbersError):
        require_declared_numbers(activity)


@pytest.mark.parametrize("name", ["tutorial_exemplar_qualitative.txt", "tutorial_exemplar_quantitative.txt"])
def test_exemplars_declare_what_they_show(name):
    require_declared_numbers(_activity(name))


def test_correction_names_the_missing_data_without_echoing_source_text():
    [diagnostic] = _diagnostics(UndeclaredNumbersError(2))
    assert diagnostic["type"] == "undeclared_numbers"
    assert "data" in diagnostic["message"] and "$" not in diagnostic["message"]
    # A corrected draft once declared rates beside their inputs; the evidence
    # check could not bind them, so derived results must stay expressions.
    assert "Derived results" in diagnostic["message"] and "never data" in diagnostic["message"]


# 2026-11-06 replay: 55 of 136 failing drafts showed only correct one-step numbers
# ("900 earned, 600 paid, so 300 still owed"); the evidence gate still proves them.
def test_a_number_one_exact_step_from_two_declared_values_is_declared():
    # open_hours 30, booked_hours 27: 30 − 27 = 3 and 30 + 27 = 57.
    require_declared_numbers(_activity("tutorial_exemplar_quantitative.txt", " The other 3 hours stayed free."))
    require_declared_numbers(_activity("tutorial_exemplar_quantitative.txt", " Together that is 57 hours of entries."))


@pytest.mark.parametrize("sentence", [
    " That left 4 hours free.",                  # no relation to the data
    " Twice the free time is 6 hours.",          # two steps: (30 − 27) × 2
    " Doubling the open time gives 60 hours.",   # a datum never pairs with itself
])
def test_unrelated_two_step_or_rounded_numbers_stay_undeclared(sentence):
    with pytest.raises(UndeclaredNumbersError):
        require_declared_numbers(_activity("tutorial_exemplar_quantitative.txt", sentence))


def test_an_accepted_one_step_number_still_needs_its_calculation_at_the_gate():
    from app.services.planning.lesson_review import grounded_failures
    from tests.test_derivation_steps_in_words import review

    case = {"id": "ledger", "data": [
        {"id": "revenue_earned", "label": "Revenue earned", "value": 9000.0, "unit": "credits"},
        {"id": "cash_received", "label": "Cash received", "value": 7600.0, "unit": "credits"}],
        "results": [{"id": "uncollected", "expression": "revenue_earned - cash_received", "unit": "credits"}]}
    lesson = {"lesson_content": "Revenue earned is 9000 credits, of which 1400 is still owed, so cash received "
                                "is 7600 credits."}
    facts = [{"claim_id": "n1", "case_id": "teaching.ledger", "datum_ids": ["revenue_earned", "cash_received"]}]
    proof = [{"claim_ids": ["n1"], "expression": "revenue_earned - cash_received", "claimed_result": 1400}]
    assert grounded_failures(review(proof, facts, case_id="teaching.ledger"), lesson, {"teaching_cases": [case]}) == []
    assert grounded_failures(review([], facts, case_id="teaching.ledger"), lesson, {"teaching_cases": [case]}) == [
        "n1: numeric span contains additional unverified values: 1400"]
