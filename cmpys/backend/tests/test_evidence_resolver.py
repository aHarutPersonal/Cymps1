"""Deterministic literal-fact evidence for numeric spans (Phase 2.5, unwired)."""
from app.services.planning.evidence_resolver import package_cases, resolve_literal_evidence

CASES = {"practice.guided": {"open_hours": 30, "booked_hours": 27, "threshold_percent": 85},
         "practice.transfer": {"rent": 1200, "fee": 1200}}


def test_span_made_only_of_owner_data_is_bound():
    spans = {"n1": "The stand is open 30 hours and 27 hours are booked."}
    facts, resolved = resolve_literal_evidence(spans, {"n1": "practice.guided"}, CASES)
    assert resolved == ["n1"]
    assert facts[0].case_id == "practice.guided"
    assert set(facts[0].datum_ids) == {"open_hours", "booked_hours"}


def test_span_with_any_unbound_value_is_left_to_the_reviewer():
    spans = {"n1": "Booked hours are 27 of 30, which is 90 percent."}
    facts, resolved = resolve_literal_evidence(spans, {"n1": "practice.guided"}, CASES)
    assert facts == [] and resolved == []


def test_values_are_never_borrowed_from_another_case():
    spans = {"n1": "Rent is 1200 this month."}
    facts, resolved = resolve_literal_evidence(spans, {"n1": "practice.guided"}, CASES)
    assert resolved == []


def test_derived_result_wording_is_left_to_the_reviewer():
    spans = {"n1": "The result is 27 hours.", "n2": "So 30 = 30 hours open."}
    owners = {"n1": "practice.guided", "n2": "practice.guided"}
    assert resolve_literal_evidence(spans, owners, CASES) == ([], [])


def test_equal_valued_data_are_all_cited():
    spans = {"n1": "Rent and the fee are both 1200."}
    facts, _ = resolve_literal_evidence(spans, {"n1": "practice.transfer"}, CASES)
    assert set(facts[0].datum_ids) == {"rent", "fee"}


def test_unknown_owner_and_numberless_spans_are_skipped():
    spans = {"n1": "Thirty hours.", "n2": "Open 30 hours."}
    facts, resolved = resolve_literal_evidence(spans, {"n2": "teaching.missing"}, CASES)
    assert resolved == []


def test_package_cases_use_the_gate_case_names():
    package = {"teaching_cases": [{"id": "cafe", "data": [{"id": "sales", "value": 900}]}],
               "private_workbook": {"activities": [{"id": "guided", "data": [{"id": "hours", "value": 3}]},
                                                   {"id": "transfer", "data": []}]}}
    assert package_cases(package) == {"teaching.cafe": {"sales": 900}, "practice.guided": {"hours": 3}}
