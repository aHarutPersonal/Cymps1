"""Scoped proofs retain the complete source inventory and its exact ownership."""
import copy
import itertools

import pytest

from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import (
    LessonReview, _has_numeric_quantity, _metadata_units, _numeric_content,
    _numeric_role_remainder, _numeric_span_occurrences, _numeric_span_records,
    grounded_failures, numeric_span_occurrences, numeric_span_owners, numeric_spans,
)
from app.services.planning.numeric_metadata import mask_structural_ordinals
from tests.lesson_package_fixtures import package_payload


def numeric_package():
    payload = package_payload()
    for activity, paid, unpaid in zip(payload["workbook"]["activities"], (40, 70), (15, 20)):
        activity["data"] = [
            {"id": "paid", "label": "Paid expense", "value": paid},
            {"id": "unpaid", "label": "Unpaid expense", "value": unpaid},
        ]
        activity["fields"] = [{"id": "expense", "kind": "number", "label": "Total expense",
                               "expression": "paid + unpaid"}]
        activity["worked_solution"] = f"Total expense is {paid + unpaid}. Include paid and unpaid expenses in the same period."
    return LessonPackage.model_validate(payload).review_context()


def calculation(claim="n1", case="practice.guided", result=55, expression="paid + unpaid"):
    return {"claim_ids": [claim], "case_id": case, "location": claim,
            "expression": expression, "claimed_result": result}


def review(**evidence):
    return LessonReview.model_validate({"acceptable": True, "issues": [], "practice_minutes": 40,
        "contains_calculations": False, "calculations": [], **evidence})


def checked(verdict, lesson, package, **kwargs):
    return grounded_failures(verdict, lesson, package, **kwargs) + verdict.failures()


def legacy_records(lesson, package):
    """Pre-path inventory algorithm; independent reference for ordering/bytes."""
    blocks = [(str(lesson.get("lesson_content") or ""), None)]
    blocks.extend((str(step), None) for step in lesson.get("substeps", []))
    for activity in package.get("private_workbook", {}).get("activities", []):
        blocks.extend((str(activity.get(key) or ""), activity)
                      for key in ("instructions", "worked_solution", "hint"))
        blocks.extend((str(field.get("label") or ""), activity) for field in activity.get("fields", []))
    cases = package.get("teaching_cases", []) + package.get("private_workbook", {}).get("activities", [])
    all_units = set().union(*(_metadata_units(case) for case in cases)) if cases else set()
    records = []
    for source, activity in blocks:
        units = _metadata_units(activity) if activity else all_units
        for start, span in _numeric_span_occurrences(source, units):
            view = mask_structural_ordinals(span, source=source, start=start, units=units)
            if _has_numeric_quantity(_numeric_content(_numeric_role_remainder(view, activity), units=units)):
                records.append((f"n{len(records) + 1}", span, start, source, activity))
    return records


def test_paths_preserve_old_inventory_for_mixed_unicode_duplicate_and_structural_sources():
    sources = ["", "  Նույն գումարը 10։\nՀաջորդ գումարը 20։", "Value 1\u202f234.50. Value −7.",
               "(1) Read the supplied claim։ (2) Revise the main claim։",
               "**Heading.** (1) «Opening 10» is given։ (2) «Following 20» is given։",
               'A learner writes "\n40 + 15 = 60.\n"', "(1) widgets, (2) widgets"]
    for public, private in itertools.product(sources, repeat=2):
        lesson = {"lesson_content": public, "substeps": [private, public]}
        package = numeric_package()
        activity = package["private_workbook"]["activities"][0]
        activity.update(instructions=private, worked_solution=public, hint=private)
        activity["data"][0]["unit"] = "widgets"
        activity["fields"][0]["label"] = public
        expected = legacy_records(lesson, package)
        records = numeric_span_occurrences(lesson, package)
        assert list(_numeric_span_records(lesson, package)) == expected
        assert [(r.claim_id, r.span, r.start, r.source, r.owner) for r in records] == expected
        assert numeric_spans(lesson, package) == {item[0]: item[1] for item in expected}
        for record in records:
            value = {"lesson": lesson, "package": package}
            for key in record.path:
                value = value[key]
            assert value == record.source
            assert record.source[record.start:record.end] == record.span


def test_identical_source_text_has_distinct_authoritative_paths_and_same_owner_objects():
    text = "  Գումարը 55։"
    lesson = {"lesson_content": text, "substeps": [text, text]}
    package = numeric_package()
    for activity in package["private_workbook"]["activities"]:
        activity.update(instructions=text, worked_solution=text, hint=text)
        activity["fields"][0]["label"] = text
    records = numeric_span_occurrences(lesson, package)
    assert len(records) == 11 and len({record.path for record in records}) == 11
    assert {record.span for record in records} == {text.strip()}
    assert {record.start for record in records} == {2}
    assert records[0].path == ("lesson", "lesson_content")
    assert records[2].path == ("lesson", "substeps", 1)
    assert records[6].path == ("package", "private_workbook", "activities", 0, "fields", 0, "label")
    assert records[6].owner is package["private_workbook"]["activities"][0]
    assert numeric_span_owners(lesson, package)["n11"] == "practice.transfer"


def test_default_and_explicit_full_scope_keep_results_and_bound_formulas_identical():
    package = numeric_package()
    data = {"calculations": [calculation(), calculation("n2", "practice.transfer", 90)]}
    original, explicit_none, full = (review(**copy.deepcopy(data)) for _ in range(3))
    assert checked(original, {}, package) == []
    assert checked(explicit_none, {}, package, expected_claim_ids=None) == []
    assert checked(full, {}, package, expected_claim_ids={"n1", "n2"}) == []
    assert original.model_dump() == explicit_none.model_dump() == full.model_dump()


def test_each_scope_keeps_original_ids_and_union_still_requires_every_claim():
    package = numeric_package()
    first = review(calculations=[calculation()])
    second = review(calculations=[calculation("n2", "practice.transfer", 90)])
    assert checked(first, {}, package, expected_claim_ids={"n1"}) == []
    assert checked(second, {}, package, expected_claim_ids={"n2"}) == []
    assert checked(review(calculations=[calculation()]), {}, package)
    assert checked(review(calculations=[calculation(), calculation("n2", "practice.transfer", 90)]), {}, package) == []


@pytest.mark.parametrize("expected", [{"unknown"}, {"n1", "n999"}])
def test_unknown_scope_ids_fail_closed(expected):
    errors = grounded_failures(review(), {}, numeric_package(), expected_claim_ids=expected)
    assert "Numeric verification scope contains unknown span IDs" in errors


@pytest.mark.parametrize("evidence", [
    {"calculations": [calculation("n2", "practice.transfer", 90)]},
    {"literal_fact_ids": ["n2"]},
    {"literal_facts": [{"claim_id": "n2", "case_id": "practice.transfer", "datum_ids": ["paid"]}]},
    {"math_roles": [{"claim_id": "n2", "case_id": "practice.transfer", "field_id": "expense",
                     "role": "divisor", "coefficient": 2, "source_quote": "divide by 2"}]},
    {"calculations": [{**calculation(), "claim_ids": ["n1", "n2"]}]},
])
def test_every_evidence_kind_rejects_cross_scope_claims(evidence):
    errors = grounded_failures(review(**evidence), {}, numeric_package(), expected_claim_ids={"n1"})
    assert "Numeric evidence contains span IDs outside the requested scope" in errors


def test_empty_scope_is_valid_only_with_empty_evidence_and_missing_scope_coverage_fails():
    package = numeric_package()
    assert checked(review(), {}, package, expected_claim_ids=set()) == []
    assert checked(review(calculations=[calculation()]), {}, package, expected_claim_ids=set())
    assert "Numeric verification coverage is incomplete or contains fabricated span IDs" in grounded_failures(
        review(), {}, package, expected_claim_ids={"n2"})


def test_scoped_validation_keeps_other_case_inputs_available_without_renumbering():
    package = numeric_package()
    lesson = {"lesson_content": "The other scenario yields 90."}
    verdict = review(calculations=[calculation("n1", "practice.transfer", 90)])
    assert checked(verdict, lesson, package, expected_claim_ids={"n1"}) == []
    assert numeric_span_owners(lesson, package) == {"n2": "practice.guided", "n3": "practice.transfer"}


@pytest.mark.parametrize("expression,result", [("paid - unpaid", 55), ("unknown + unpaid", 55), ("paid + unpaid", 54)])
def test_scope_never_weakens_calculation_grounding_or_arithmetic(expression, result):
    verdict = review(calculations=[calculation(expression=expression, result=result)])
    assert checked(verdict, {}, numeric_package(), expected_claim_ids={"n1"})


@pytest.mark.parametrize("change", [{}, {"case_id": "practice.transfer"},
                                     {"symbol_bindings": {"b": "height", "h": "base"}}])
def test_scope_keeps_exact_math_role_owner_and_symbol_checks(change):
    package = numeric_package()
    activity = package["private_workbook"]["activities"][0]
    activity["data"] = [{"id": "base", "label": "Base", "value": 40},
                        {"id": "height", "label": "Height", "value": 15}]
    activity["fields"][0]["expression"] = "base * height / 2"
    activity["worked_solution"] = "Use (b × h) / 2 for this scenario."
    evidence = {"claim_id": "n1", "case_id": "practice.guided", "field_id": "expense",
                "role": "symbolic_formula", "coefficient": 2, "source_quote": "(b × h) / 2",
                "symbol_bindings": {"b": "base", "h": "height"}, **change}
    errors = checked(review(math_roles=[evidence]), {}, package, expected_claim_ids={"n1"})
    assert bool(errors) == bool(change)


def test_scope_preserves_a_negative_semantic_verdict():
    verdict = review(acceptable=False, issues=["The task is unusable."], calculations=[calculation()])
    assert checked(verdict, {}, numeric_package(), expected_claim_ids={"n1"}) == ["The task is unusable."]
