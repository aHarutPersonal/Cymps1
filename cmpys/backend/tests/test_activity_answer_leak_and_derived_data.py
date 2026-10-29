"""Two live-run defects are caught when an activity is built, not in a later review.

F15: a public rubric_criterion stated the answer before the learner answered.
F18: a derived rate was declared as raw data beside the inputs it is computed from.
"""
import copy
import json
from unittest.mock import AsyncMock

import pytest

from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning import package_builder as builder
from app.services.planning.activity_draft import parse_activity_draft
from app.services.planning.package_builder import (
    AnswerLeakError, DerivedDataError, UndeclaredNumbersError, _diagnostics, _validation_failure_metadata,
    require_hidden_answers, require_raw_data,
)


def _draft(name: str) -> dict:
    return json.loads(resolve_prompt_text(name).split("\n", 1)[1])


def _multi(rubric: str, choices: dict, correct, label="Which sections does the quoted sentence belong to?"):
    draft = _draft("tutorial_exemplar_qualitative.txt")
    draft["fields"][0] = {
        "id": "sections", "label": label, "kind": "multi_choice",
        "choices": [{"id": key, "label": text} for key, text in choices.items()],
        "correct_choices": list(correct), "rubric_criterion": rubric,
        "explanation": "The sentence states a figure, names where it comes from and tests it against a record."}
    return draft


def _sections(rubric: str, correct=("numbers", "sources", "checks"), label="Which sections does the quoted sentence belong to?"):
    # The F15 guided field, as generated in the 09:05 regeneration.
    choices = {key: key.title() for key in ("numbers", "sources", "checks", "verdict", "reasoning")}
    return _multi(rubric, choices, correct, label)


def _choice(rubric: str, labels: dict, correct: str):
    draft = _draft("tutorial_exemplar_qualitative.txt")
    draft["fields"][0] = {
        "id": "pick", "label": "Which option fits the case best?", "kind": "choice",
        "choices": [{"id": key, "label": text} for key, text in labels.items()],
        "correct_choice": correct, "rubric_criterion": rubric,
        "explanation": "Only the correct option follows from the facts the case supplies."}
    return draft


def _numeric(rubric: str):
    draft = _draft("tutorial_exemplar_quantitative.txt")  # 27 / 30 * 100 = 90
    draft["fields"][0]["rubric_criterion"] = rubric
    return draft


def _ratio(rubric: str):
    draft = _draft("tutorial_exemplar_quantitative.txt")
    draft["data"] = [{"id": "assets", "label": "Current assets", "value": 300, "unit": "$"},
                     {"id": "liabilities", "label": "Current liabilities", "value": 150, "unit": "$"}]
    draft["fields"] = [{"id": "current_ratio", "label": "Current ratio", "kind": "number",
                        "expression": "assets / liabilities", "rubric_criterion": rubric,
                        "explanation": "Divide current assets by current liabilities to get the ratio."}]
    return draft


def _activity(draft):
    return parse_activity_draft(draft)


@pytest.mark.parametrize("draft", [
    # F15 verbatim: the row named the exact answer set {numbers, sources, checks}.
    _sections("Labels the sentence as numbers, sources and checks"),
    _sections("Tags it as Numbers + Sources + Checks."),
    _sections("Picks numbers, sources and checks over the verdict"),
    # A distinctive (3+ word) correct option quoted in the row.
    _choice("Prefers comparing against prior-year tax returns",
            {"tax": "Comparing against prior-year tax returns", "pitch": "Restating the owner's pitch"}, "tax"),
    # A correct option's machine key in the row.
    _multi("Selects para_c before the other paragraphs",
           {"para_b": "Paragraph B", "para_c": "Paragraph C", "para_d": "Paragraph D"}, ["para_c"]),
    # The expected numeric value, in any spelling.
    _numeric("Finds the 90% utilization"),
    _numeric("Reaches 90.0 percent of available hours"),
], ids=["f15", "f15-symbols", "f15-contrast", "long-option", "choice-key", "number", "number-decimal"])
def test_rubric_rows_that_state_the_answer_are_rejected(draft):
    with pytest.raises(AnswerLeakError) as caught:
        require_hidden_answers(_activity(draft))
    assert caught.value.leaks


@pytest.mark.parametrize("draft", [
    # Generic skill words that merely share a word with a short option.
    _choice("Weighs the cost against the benefit", {"cost": "Cost", "time": "Time", "risk": "Risk"}, "cost"),
    # Naming every option discriminates nothing.
    _sections("Distinguishes checks from numbers, sources, verdicts and reasoning", correct=("checks", "verdict")),
    # Only part of a multi-select set (one short word) is named.
    _sections("Separates checked numbers from bare claims", correct=("numbers", "checks")),
    # The question itself already names the options.
    _sections("Finds the checks and the verdict", correct=("checks", "verdict"),
              label="Which two paragraphs are the checks and the verdict?"),
    # A raw input value, not the expected result.
    _numeric("Divides the 27 booked hours by available hours"),
    _numeric("Divides booked hours by available hours"),
    # The shipped exemplars.
    _draft("tutorial_exemplar_qualitative.txt"),
    _draft("tutorial_exemplar_quantitative.txt"),
    # Review: a row naming every option, by id or by a long label, reveals nothing.
    _choice("Compares Q3 against Q4 demand", {"q3": "Q3", "q4": "Q4"}, "q4"),
    _choice("Separates fixed cost per unit from variable cost per unit",
            {"fixed": "Fixed cost per unit", "variable": "Variable cost per unit"}, "variable"),
    # Review: a precision instruction is not the answer (300 / 150 = 2).
    _ratio("Computes the current ratio to 2 decimal places"),
    _ratio("Rounds to 2 dp in 2 steps"),
], ids=["cost-benefit", "all-options", "partial-set", "question-names-options", "raw-input", "plain", "qualitative",
        "quantitative", "every-option-by-id", "every-option-long", "precision", "precision-dp"])
def test_skill_rows_that_share_words_with_options_pass(draft):
    require_hidden_answers(_activity(draft))


def _with_data(*data):
    draft = _draft("tutorial_exemplar_quantitative.txt")
    draft["data"] += [{"id": key, "label": label, "value": value, "unit": unit} for key, label, value, unit in data]
    return _activity(draft)


def test_f18_derived_rate_declared_as_data_is_rejected():
    # Attempt 6: an implied return (about 11% = 86,000 / 780,000) sat in data
    # beside the earnings and price it is computed from.
    activity = _with_data(
        ("car_wash_earnings", "Blue Ribbon Car Wash owner earnings", 86000, "dollars"),
        ("car_wash_price", "Blue Ribbon Car Wash asking price", 780000, "dollars"),
        ("car_wash_return", "Implied return on the car wash asking price", 11, "percent"),
        ("car_wash_alt_return", "Owner's Treasury-linked alternative return", 9, "percent"))
    with pytest.raises(DerivedDataError) as caught:
        require_raw_data(activity)
    assert [(item[0], item[1], item[3]) for item in caught.value.derived] == [
        ("car_wash_return", "car_wash_earnings", "car_wash_price")]


@pytest.mark.parametrize("extra,expected", [
    ((("total_hours", "Total hours across both weeks", 57, "hours"),), ("total_hours", "open_hours", "+", "booked_hours")),
    ((("hours_difference", "Unbooked hours", 3, "hours"),), ("hours_difference", "open_hours", "-", "booked_hours")),
    ((("booked_share_pct", "Booked share of available hours", 90, "%"),), ("booked_share_pct", "booked_hours", "/", "open_hours")),
])
def test_named_totals_differences_and_rates_are_rejected(extra, expected):
    with pytest.raises(DerivedDataError) as caught:
        require_raw_data(_with_data(*extra))
    assert tuple(caught.value.derived[0][:4]) == expected


def test_only_the_derived_datum_of_a_saved_memo_is_named():
    # Saved 09:05 guided activity: the stated valuation is earnings * multiple,
    # while a 10% reasonableness band only coincides with 78,000 / 774,000.
    activity = _with_data(
        ("owner_earnings", "Owner earnings figure cited in the memo excerpt", 86000, "$"),
        ("avg_earnings", "Three-year average owner earnings in the check sentence", 78000, "$"),
        ("tolerance_pct", "Reasonableness band stated in the check sentence", 10, "%"),
        ("multiple", "Earnings multiple applied in the excerpt", 9, "times earnings"),
        ("implied_value", "Valuation stated in the excerpt", 774000, "$"))
    with pytest.raises(DerivedDataError) as caught:
        require_raw_data(activity)
    assert [item[4] for item in caught.value.derived] == ["owner_earnings * multiple"]


@pytest.mark.parametrize("extra", [
    # Review: a percentage margin never matches a dollar difference (50 - 30).
    (("price", "Unit price", 50, "$"), ("variable_cost", "Variable cost per unit", 30, "$"),
     ("target_margin", "Target margin", 20, "%")),
    # Review: an average is a division, never a product (8 * 5 = 40).
    (("avg_order", "Average order value", 40, "$"), ("orders", "Orders this month", 120, ""),
     ("staff", "Staff on shift", 8, ""), ("hours", "Hours per shift", 5, "")),
    # Review: a rate is a division, never a product (5 * 5 = 25).
    (("hourly_rate", "Hourly rate", 25, ""), ("hours", "Hours worked", 5, ""), ("workers", "Workers", 5, "")),
    # A raw threshold rate that only nearly equals a ratio (90.4 vs 90).
    (("target_rate", "Target utilization rate", 90.4, "%"),),
    # A coincidence of numbers alone: 3 = 30 - 27, but nothing marks it derived.
    (("crew_size", "People on the repair crew", 3, "people"),),
    # Derived-sounding name with no matching pair: a reported net income.
    (("net_income", "Owner-reported net income for last year", 40000, "USD"),
     ("revenue", "Owner-reported revenue for last year", 210000, "USD")),
    # Attempt 6's raw alternative return (9%) sits near 780,000 / 86,000 = 9.07,
    # but it is neither marked derived nor a percentage of that ratio.
    (("car_wash_earnings", "Owner earnings", 86000, "dollars"), ("car_wash_price", "Asking price", 780000, "dollars"),
     ("alt_return", "Owner's Treasury-linked alternative return", 9, "percent")),
    # A rate marked derived whose match would need an identity operation.
    (("unit_rate", "Hourly rate", 30, "USD"), ("multiplier", "Crew multiplier", 1, "")),
])
def test_raw_data_that_merely_coincides_passes(extra):
    require_raw_data(_with_data(*extra))


@pytest.mark.parametrize("name", ["tutorial_exemplar_qualitative.txt", "tutorial_exemplar_quantitative.txt"])
def test_exemplars_declare_only_raw_data(name):
    require_raw_data(_activity(_draft(name)))


def test_corrections_name_the_defect_and_what_to_change():
    [leak] = _diagnostics(AnswerLeakError([("sections", "choices", ["numbers", "sources", "checks"])]))
    assert leak["type"] == "answer_leak"
    assert "sections" in leak["message"] and "numbers, sources, checks" in leak["message"]
    assert "never the answer itself" in leak["message"] and "rubric_criterion" in leak["message"]
    [derived] = _diagnostics(DerivedDataError([
        ("car_wash_return", "car_wash_earnings", "/", "car_wash_price", "car_wash_earnings / car_wash_price * 100")]))
    assert derived["type"] == "derived_data"
    assert "car_wash_return" in derived["message"]
    assert "car_wash_earnings / car_wash_price * 100" in derived["message"]
    assert "expression" in derived["message"]
    for exc, code in ((AnswerLeakError([("f", "value", [])]), "answer_leak"),
                      (DerivedDataError([("a", "b", "+", "c", "b + c")]), "derived_data")):
        assert _validation_failure_metadata(exc, None) == {"errors": [{"type": code, "loc": []}], "total_errors": 1}


def test_all_findings_are_reported_in_one_correction():
    error = builder.ActivityChecksError([UndeclaredNumbersError(1), DerivedDataError([("a", "b", "+", "c", "b + c")])])
    assert [item["type"] for item in _diagnostics(error)] == ["undeclared_numbers", "derived_data"]
    assert _validation_failure_metadata(error, None) == {
        "errors": [{"type": "undeclared_numbers", "loc": []}, {"type": "derived_data", "loc": []}], "total_errors": 2}


@pytest.mark.asyncio
@pytest.mark.parametrize("defect,code", [("leak", "answer_leak"), ("derived", "derived_data")])
async def test_builder_spends_one_activity_correction_on_the_defect(monkeypatch, defect, code):
    from tests.test_staged_package_builder import Factory, components

    record = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", record)
    seed, activities = components(numeric=True)
    key, good = next(iter(activities.items()))  # amount = 12, expected amount * 2 = 24
    bad = copy.deepcopy(good)
    if defect == "leak":
        bad["fields"][0]["rubric_criterion"] = "Reaches 24 m by doubling"
    else:
        bad["data"] += [{"id": "extra", "label": "Added quantity", "value": 3, "unit": "m"},
                        {"id": "total_amount", "label": "Total quantity", "value": 15, "unit": "m"}]
    responses = {"seed": [seed], **{name: [value] for name, value in activities.items()}}
    responses[key] = [bad, good]
    factory = Factory(responses)
    package, _, _ = await builder.generate_initial_package({"id": "step_1", "title": "Learn"},
        {"component_recovery": "bounded_per_component", "target_practice_minutes": 35}, client_factory=factory)
    assert package is not None
    assert factory.counts[key] == 2
    correction = [data for name, _, data in factory.requests if name == key][1]["correction"]
    assert [item["type"] for item in correction["validation_errors"]] == [code]
    rejected = [call.kwargs for call in record.await_args_list
                if call.kwargs.get("metadata", {}).get("component") == "activity_" + key
                and not call.kwargs["metadata"]["correction"]]
    assert rejected and rejected[0]["response"].effective_parameters["component_validation"] == {
        "errors": [{"type": code, "loc": []}], "total_errors": 1}
