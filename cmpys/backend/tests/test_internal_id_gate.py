"""Internal identifiers never reach learner-visible activity text (pilot 2026-11-03).

Evidence corrections wrote raw datum IDs into public content: native-luna
6dca3632 criteria ("revenue_earned_current − expenses_incurred_current = $400"),
luna 54f42516 guided instructions ("earned_sales − incurred_expenses"), luna
3026a818 solution ("represented by the raw datum base_length"), haiku-12
c67f590e instructions ("from the quiet_lane case"). A fresh draft gets one
correction; a repair that introduces a leak is rejected.
"""
import copy
import json

import pytest

from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning.activity_draft import parse_activity_draft
from app.services.planning.lesson_package import (
    InternalIdLeakError, LessonPackage, PrivatePackageRepair, _replace_public_activity,
    apply_private_package_repair, internal_id_leaks, require_no_internal_ids,
)
from app.services.planning.package_builder import _diagnostics, require_component_checks
from tests.lesson_package_fixtures import package_payload

DATA = [{"id": "revenue_earned_current", "label": "Current-period revenue earned", "value": 1200, "unit": "USD"},
        {"id": "expenses_incurred_current", "label": "Current-period expenses incurred", "value": 800, "unit": "USD"},
        {"id": "base", "label": "Base", "value": 8, "unit": "cm"}]
SOLUTION = "Accrual profit is current-period revenue earned less expenses incurred: $1,200 − $800 = $400."


def payload(**changes):
    value = package_payload()
    activity = value["workbook"]["activities"][0]
    activity.update(data=copy.deepcopy(DATA), worked_solution=SOLUTION, **changes)
    activity["fields"][0]["criteria"] = ["Calculates accrual profit as revenue earned minus expenses incurred, $400.",
                                         "Explains the timing difference."]
    return value


def package(**changes):
    return LessonPackage.model_validate(payload(**changes))


def guided(pkg):
    return pkg.workbook.activities[0]


@pytest.mark.parametrize("location,text,leak", [
    ("criteria", "Calculates accrual profit as revenue_earned_current − expenses_incurred_current = $400.",
     "revenue_earned_current"),
    ("instructions", "Subtract the expenses from the sales: revenue_earned_current − expenses_incurred_current. "
                     "Then compare the result with the cash movement.", "revenue_earned_current"),
    ("worked_solution", "Here the stated base is BC, represented by the raw datum base, and AD is the matching altitude.",
     "raw datum"),
    ("worked_solution", "A response that uses the declared base-length datum but omits the halving is incomplete.",
     "declared base-length datum"),
])
def test_real_leaks_are_found(location, text, leak):
    value = payload()
    activity = value["workbook"]["activities"][0]
    if location == "criteria":
        activity["fields"][0]["criteria"][0] = text
    else:
        activity[location] = text
    found = internal_id_leaks(guided(LessonPackage.model_validate(value)))
    assert leak in [name for _, name in found]


def test_teaching_case_ids_count_as_internal():
    pkg = LessonPackage.model_validate({**payload(instructions=(
        "Original fictional example from the quiet_lane case: compare earned revenue with cash collected.")),
        "teaching_cases": [{"id": "quiet_lane", "assumptions": "A quiet street cafe sells coffee on account.",
                            "data": [], "results": []}]})
    assert ("instructions", "quiet_lane") in internal_id_leaks(guided(pkg), pkg.teaching_cases)


@pytest.mark.parametrize("text", [
    "Use the base and the height of the triangle; the data in the table are fictional.",   # one-word ID "base"
    "The config sets `revenue_earned_current` to the ledger total before the report runs.",   # inline code
    "Compare the revenue earned in the current period with the expenses incurred in it.",
])
def test_plain_labels_one_word_ids_and_code_spans_are_fine(text):
    assert internal_id_leaks(guided(package(instructions=text))) == []


def test_a_fresh_draft_gets_a_correction_naming_the_leak():
    draft = json.loads(resolve_prompt_text("tutorial_exemplar_qualitative.txt").split("\n", 1)[1])
    leaked = parse_activity_draft({**draft, "instructions": draft["instructions"] + " Write it as the raw datum."})
    with pytest.raises(InternalIdLeakError) as caught:
        require_component_checks(leaked)
    [diagnostic] = _diagnostics(caught.value)
    assert diagnostic["type"] == "internal_ids" and "instructions shows 'raw datum'" in diagnostic["message"]
    require_component_checks(parse_activity_draft(draft))   # the exemplar itself is clean


def test_public_repair_ids_are_written_as_labels_and_datum_wording_is_rejected():
    # Phase 0.5 (2026-11-04): a named id is relabelled instead of failing the repair.
    pkg = package()
    replacement = guided(pkg).model_copy(update={"instructions": guided(pkg).instructions
                                                 + " Compute revenue_earned_current − expenses_incurred_current."})
    corrected = guided(_replace_public_activity(pkg, {"guided": None}, replacement))
    assert "Compute current-period revenue earned − current-period expenses incurred." in corrected.instructions
    assert internal_id_leaks(corrected) == []
    worded = guided(pkg).model_copy(update={"instructions": guided(pkg).instructions + " Use the raw datum here."})
    with pytest.raises(InternalIdLeakError):
        _replace_public_activity(pkg, {"guided": None}, worded)
    clean = guided(pkg).model_copy(update={"instructions": guided(pkg).instructions + " Compare both totals."})
    assert _replace_public_activity(pkg, {"guided": None}, clean) != pkg


def test_private_repair_ids_in_criteria_are_written_as_labels():
    pkg = package()
    repair = PrivatePackageRepair.model_validate({"field_patches": [{"activity_id": "guided", "field_id": "argument",
        "criteria": ["Calculates accrual profit as revenue_earned_current − expenses_incurred_current = $400.",
                     "Explains the timing difference."]}]})
    criteria = guided(apply_private_package_repair(pkg, repair)).fields[0].criteria
    assert criteria[0] == ("Calculates accrual profit as current-period revenue earned − "
                           "current-period expenses incurred = $400.")


def test_a_leak_already_in_the_original_does_not_block_an_unrelated_repair():
    original = guided(package(instructions="Older stored text names revenue_earned_current in its instructions here."))
    changed = original.model_copy(update={"hint": "Separate earning from collecting before you compare."})
    require_no_internal_ids(changed, original=original)
    with pytest.raises(InternalIdLeakError):
        require_no_internal_ids(changed)
