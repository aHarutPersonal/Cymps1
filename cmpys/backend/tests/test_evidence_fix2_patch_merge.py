"""Final-review evidence patch merge (smoke2, 29 Oct 2026).

Fix 6: a patch calculation whose claimed result is absent from its span can
only fail; it is dropped before the merge when the span has other evidence,
and the normal gate still runs on everything else. The remaining-values error
names the unverified values (geometry_experienced n8: 216; n16: absent 216).
Fix 1: when every requested span is lesson prose (no package owner), patch
package_issues are reclassified as issues. The lesson stays blocked.
"""
import copy
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_review import (
    LessonReview, grounded_failures, numeric_spans, review_lesson,
)


@pytest.fixture(autouse=True)
def no_telemetry(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())


FLAG = {"id": "tri_case_flag", "data": [
    {"id": "flag_base", "label": "Base of the triangular flag", "value": 24.0, "unit": "centimeters"},
    {"id": "flag_height", "label": "Perpendicular height from the base", "value": 9.0, "unit": "centimeters"},
], "results": [{"id": "flag_area", "label": "Area of the triangular flag",
                "expression": "(flag_base * flag_height) / 2", "unit": "square centimeters", "decimal_places": 1}]}
PACKAGE = {"teaching_cases": [FLAG]}
N8 = ("The signed rows total the area: start from the rectangle's 216 square centimeters, subtract the 108 "
      "that belongs to the other half-triangle, and what remains is the flag itself.")
N16 = "Step 3: multiply them: 24 × 9 gives the rectangle's area in square centimeters."
FACT_N16 = {"claim_id": "n1", "case_id": "teaching.tri_case_flag", "datum_ids": ["flag_base", "flag_height"]}
ABSENT_216 = {"claim_ids": ["n1"], "case_id": "teaching.tri_case_flag",
              "expression": "flag_base * flag_height", "claimed_result": 216}


def review(**changes):
    data = {"acceptable": True, "issues": [], "practice_minutes": 3, "contains_calculations": False,
            "calculations": [], "literal_facts": [], **changes}
    data["calculations"] = [{**check, "location": ", ".join(check["claim_ids"])} for check in data["calculations"]]
    data["contains_calculations"] = bool(data["calculations"])
    return LessonReview.model_validate(data)


def verdict(**changes):
    return {"acceptable": True, "issues": [], "package_issues": [], "practice_minutes": 3,
            "contains_calculations": False, "calculations": [], **changes}


async def run(first, patch, lesson, package=PACKAGE):
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=copy.deepcopy(first)), LLMResponse(data=copy.deepcopy(patch))]))
    result = await review_lesson(lesson, client_factory=lambda **kw: client,
                                 context={"lesson_package": copy.deepcopy(package)})
    assert client.generate_json.await_count == 2
    return result


# --- Fix 6: name the unverified values --------------------------------------

def test_remaining_values_error_names_the_unverified_values():
    lesson = {"lesson_content": N8}
    assert list(numeric_spans(lesson, PACKAGE)) == ["n1"]
    proof = review(calculations=[{"claim_ids": ["n1"], "case_id": "teaching.tri_case_flag",
                                  "expression": "flag_base * flag_height - flag_base * flag_height / 2",
                                  "claimed_result": 108}])
    assert grounded_failures(proof, lesson, PACKAGE) == [
        "n1: numeric span contains additional unverified values: 216"]
    # Proving the 216 as well clears it.
    proof = review(calculations=[
        {"claim_ids": ["n1"], "case_id": "teaching.tri_case_flag",
         "expression": "flag_base * flag_height - flag_base * flag_height / 2", "claimed_result": 108},
        {"claim_ids": ["n1"], "case_id": "teaching.tri_case_flag",
         "expression": "flag_base * flag_height", "claimed_result": 216}])
    assert grounded_failures(proof, lesson, PACKAGE) == []


def test_several_unverified_values_are_listed_in_order():
    lesson = {"lesson_content": "The flag uses 24 and 9, so 216 and 1,080 follow."}
    errors = grounded_failures(review(literal_facts=[FACT_N16]), lesson, PACKAGE)
    assert "n1: numeric span contains additional unverified values: 216, 1080" in errors


# --- Fix 6: drop patch calculations whose result is absent ------------------

@pytest.mark.asyncio
async def test_absent_result_patch_calculation_is_dropped_and_span_passes():
    lesson = {"lesson_content": N16}
    first = verdict(literal_facts=[FACT_N16], calculations=[ABSENT_216])
    patch = {"literal_facts": [FACT_N16], "calculations": [ABSENT_216]}
    failures, response, _ = await run(first, patch, lesson)
    assert failures == [] and response.error is None
    assert response.data["calculations"] == []
    assert response.data["literal_facts"] == [FACT_N16]


@pytest.mark.asyncio
async def test_dropping_does_not_excuse_remaining_values():
    lesson = {"lesson_content": N16.replace("24 × 9 gives", "24 × 9 gives 216, i.e.")}
    first = verdict(literal_facts=[FACT_N16])
    # The 216 is present here, so this calculation is kept and proves it.
    patch = {"literal_facts": [FACT_N16], "calculations": [ABSENT_216]}
    failures, response, _ = await run(first, patch, lesson)
    assert failures == [] and len(response.data["calculations"]) == 1
    # A wrong value is never dropped into approval: 217 stays unverified.
    lesson = {"lesson_content": N16.replace("24 × 9 gives", "24 × 9 gives 217, i.e.")}
    failures, response, _ = await run(first, patch, lesson)
    assert "n1: numeric span contains additional unverified values: 217" in failures
    assert response.error == "Lesson review evidence patch validation failed"


@pytest.mark.asyncio
async def test_absent_result_calculation_that_is_the_only_evidence_keeps_its_diagnostic():
    lesson = {"lesson_content": N16}
    first = verdict(calculations=[ABSENT_216])
    failures, response, _ = await run(first, {"calculations": [ABSENT_216]}, lesson)
    assert "n1: claimed result is absent from its source quote" in failures
    assert response.error == "Lesson review evidence patch validation failed"


@pytest.mark.asyncio
async def test_multi_span_calculation_keeps_spans_that_show_its_result():
    lesson = {"lesson_content": N16 + "\n\nThe rectangle is 216 square centimeters."}
    assert list(numeric_spans(lesson, PACKAGE)) == ["n1", "n2"]
    both = {**ABSENT_216, "claim_ids": ["n1", "n2"]}
    first = verdict(literal_facts=[FACT_N16], calculations=[both])
    failures, response, _ = await run(first, {"literal_facts": [FACT_N16], "calculations": [both]}, lesson)
    assert failures == [] and response.error is None
    assert [check["claim_ids"] for check in response.data["calculations"]] == [["n2"]]


# --- Fix 1: lesson-owned spans reclassify package_issues ---------------------

PHILOSOPHY = {"teaching_cases": [{"id": "closure", "data": []}], "private_workbook": {"activities": [
    {"id": "guided", "title": "Readings", "kind": "guided", "instructions": "Compare readings A and B.",
     "data": [], "fields": [{"id": "reading", "label": "Which reading?", "kind": "text", "criteria": ["Names A"]}],
     "worked_solution": "Reading A is better supported.", "hint": "", "minutes_min": 40, "minutes_max": 60}]}}
SCORES = "```steps\ntitle: Phrase scores\n\"Renovations\" | 1 | Favors A.\n= Phrases supporting A | 3\n```"
PACKAGE_ISSUE = ("practice.guided: the lesson's claimed numeric evidence table is not present in the "
                 "workbook's public data, fields, or instructions.")


@pytest.mark.asyncio
async def test_lesson_owned_patch_package_issues_become_issues():
    lesson = {"lesson_content": SCORES}
    assert numeric_spans(lesson, PHILOSOPHY)
    first = verdict(literal_fact_ids=list(numeric_spans(lesson, PHILOSOPHY)), practice_minutes=45)
    patch = {"issues": ["The 1/0 scores are invented."], "package_issues": [PACKAGE_ISSUE],
             "affected_sections": ["worked_example"]}
    failures, response, _ = await run(first, patch, lesson, PHILOSOPHY)
    assert response.data["acceptable"] is False
    assert response.data["package_issues"] == []
    assert response.data["issues"] == ["The 1/0 scores are invented.", PACKAGE_ISSUE]
    assert response.data["affected_sections"] == ["worked_example"]
    assert failures == ["The 1/0 scores are invented.", PACKAGE_ISSUE]


@pytest.mark.asyncio
async def test_package_owned_span_keeps_package_issues():
    package = copy.deepcopy(PHILOSOPHY)
    activity = package["private_workbook"]["activities"][0]
    activity["data"] = [{"id": "phrases", "label": "Phrases", "value": 4}]
    activity["worked_solution"] = "There are 5 phrases."
    lesson = {"lesson_content": "Compare the readings."}
    first = verdict(literal_facts=[{"claim_id": "n1", "case_id": "practice.guided", "datum_ids": ["phrases"]}],
                    practice_minutes=45)
    patch = {"package_issues": ["practice.guided: the worked solution says 5 phrases, but the data has 4."]}
    failures, response, _ = await run(first, patch, lesson, package)
    assert response.data["package_issues"] == patch["package_issues"]
    assert response.data["issues"] == []


@pytest.mark.asyncio
async def test_workload_correction_keeps_package_issues_even_for_lesson_spans():
    # With a workload error the patch may reject activity ranges in package_issues.
    lesson = {"lesson_content": SCORES}
    first = verdict(literal_fact_ids=list(numeric_spans(lesson, PHILOSOPHY)), practice_minutes=3)
    patch = {"package_issues": ["practice.guided: the 40-60 minute range is materially wrong."]}
    failures, response, _ = await run(first, patch, lesson, PHILOSOPHY)
    assert response.data["package_issues"] == patch["package_issues"]


@pytest.mark.asyncio
async def test_lesson_span_bound_to_teaching_case_keeps_package_issues():
    # Prose spans bound to teaching-case data: a case-expression defect stays a package issue.
    lesson = {"lesson_content": N16}
    first = verdict(literal_facts=[{**FACT_N16, "datum_ids": ["flag_base"]}])
    patch = {"package_issues": ["package: the flag_area expression should halve the product."]}
    failures, response, _ = await run(first, patch, lesson)
    assert response.data["package_issues"] == patch["package_issues"]
    assert response.data["issues"] == []
    # Same when only the patch carries the binding.
    first = verdict()
    patch = {"package_issues": ["package: wrong case formula."], "literal_facts": [FACT_N16]}
    failures, response, _ = await run(first, patch, lesson)
    assert response.data["package_issues"] == patch["package_issues"]
