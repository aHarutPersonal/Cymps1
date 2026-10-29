"""Fix 3a (smoke2 accounting_novice): normalize a private repair before scope checks.

Fixtures are verbatim: the package under repair (from the replayed repair request)
and both recorded PrivatePackageRepair responses for validated target practice.transfer.
Attempt 1 omitted worked_solution.version and sent the unchanged guided solution twice;
attempt 2 re-sent the unchanged guided solution. Both corrected only the transfer.
"""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import (
    LessonPackage, PrivatePackageRepair, _check_private_repair_scope, _validated_repair_scope,
    apply_private_package_repair, generate_package, normalize_private_repair,
)

PACKAGE = json.loads('{"teaching_cases":[{"id":"riverside_cafe_month","assumptions":"Fictional cafe, one calendar month, amounts in dollars. Accrual profit counts revenues earned and expenses incurred in the month regardless of cash movement; cash flow counts only cash received and paid. All credit sales and the unpaid utilities invoice are collected/paid next month. Rent paid covers exactly this month.","data":[{"id":"cash_sales","label":"Cash sales collected this month","value":4200.0,"unit":"dollars"},{"id":"credit_sales","label":"Catering sales invoiced this month, not yet collected","value":1500.0,"unit":"dollars"},{"id":"supplies_paid","label":"Cash paid for supplies used this month","value":900.0,"unit":"dollars"},{"id":"wages_paid","label":"Wages paid in cash this month","value":800.0,"unit":"dollars"},{"id":"rent_paid","label":"Rent paid in cash this month","value":600.0,"unit":"dollars"},{"id":"utilities_owed","label":"Utilities used this month, invoice unpaid","value":250.0,"unit":"dollars"}],"results":[{"id":"accrual_profit","label":"Accrual profit for the month","expression":"cash_sales + credit_sales - supplies_paid - wages_paid - rent_paid - utilities_owed","unit":"dollars","decimal_places":0},{"id":"net_cash_flow","label":"Net cash flow for the month","expression":"cash_sales - supplies_paid - wages_paid - rent_paid","unit":"dollars","decimal_places":0}]}],"workbook":{"title":"Accrual profit versus cash flow","activities":[{"id":"guided","title":"Sort Riverside Cafe\'s month by timing","kind":"practice","instructions":"Original fictional case. Riverside Cafe, one calendar month, all amounts in dollars. Accrual profit counts revenue earned and expenses incurred this month, regardless of when cash moves; net cash flow counts only cash actually received and paid. Credit sales and the unpaid utilities invoice settle next month; rent paid covers exactly this month.\\n\\nThis month\'s facts:\\n- Cash sales collected this month: 4200 dollars\\n- Catering sales invoiced this month, not yet collected: 1500 dollars\\n- Cash paid for supplies used this month: 900 dollars\\n- Wages paid in cash this month: 800 dollars\\n- Rent paid in cash this month: 600 dollars\\n- Utilities used this month, invoice unpaid: 250 dollars\\n\\nFirst decide which items belong in this month\'s accrual profit but not in its net cash flow. Then compute the month\'s accrual profit as a signed total over all six facts.","data":[{"id":"cash_sales","label":"Cash sales collected this month","value":4200.0,"unit":"dollars"},{"id":"credit_sales","label":"Catering sales invoiced this month, not yet collected","value":1500.0,"unit":"dollars"},{"id":"supplies_paid","label":"Cash paid for supplies used this month","value":900.0,"unit":"dollars"},{"id":"wages_paid","label":"Wages paid in cash this month","value":800.0,"unit":"dollars"},{"id":"rent_paid","label":"Rent paid in cash this month","value":600.0,"unit":"dollars"},{"id":"utilities_owed","label":"Utilities used this month, invoice unpaid","value":250.0,"unit":"dollars"}],"fields":[{"id":"accrual_only","label":"Which items belong in accrual profit but NOT in net cash flow this month?","kind":"multi_choice","unit":"","choices":[{"id":"credit_sales","label":"Catering sales invoiced, not yet collected"},{"id":"utilities_owed","label":"Utilities used, invoice unpaid"},{"id":"cash_sales","label":"Cash sales collected this month"},{"id":"rent_paid","label":"Rent paid this month"}],"expression":null,"correct_choice":null,"tolerance":0.01,"criteria":[],"rubric_criterion":"Classifies items by earning timing versus cash timing","correct_choices":["credit_sales","utilities_owed"]},{"id":"accrual_profit","label":"Accrual profit for the month (dollars)","kind":"number","unit":"dollars","choices":[],"expression":"cash_sales + credit_sales - supplies_paid - wages_paid - rent_paid - utilities_owed","correct_choice":null,"tolerance":0.01,"criteria":[],"rubric_criterion":"Totals earned revenue minus incurred expenses","hint":"Add both kinds of revenue, then subtract every expense incurred this month, whether or not it was paid in cash.","misconceptions":[{"expression":"cash_sales - supplies_paid - wages_paid - rent_paid","feedback":"You computed net cash flow: you dropped the uncollected catering sales and the unpaid utilities that still belong in accrual profit."},{"expression":"cash_sales + credit_sales - supplies_paid - wages_paid - rent_paid","feedback":"You omitted the unpaid utilities; an expense incurred this month reduces accrual profit even before it is paid."}]}],"hint":"For each item ask two questions: was it earned or incurred this month, and did cash actually move this month? An item counts in accrual profit if earned or incurred now, and in cash flow only if cash moved now.","worked_solution":{"version":1,"steps":[{"field_id":"accrual_only","explanation":"Catering sales were earned this month but no cash was collected, so they raise accrual profit while leaving cash flow unchanged. Utilities were used (incurred) this month but unpaid, so they reduce accrual profit without any cash leaving. Cash sales and rent appear in both measures: each was earned or incurred this month and its cash also moved this month, so neither separates the two."},{"field_id":"accrual_profit","explanation":"Accrual profit adds all revenue earned this month — cash sales plus invoiced catering sales — and subtracts all expenses incurred this month, whether or not cash moved: supplies, wages, rent and the unpaid utilities. The uncollected catering sales enter with a plus sign because earning, not collection, drives accrual revenue; the unpaid utilities enter with a minus sign because using them this month makes them an incurred expense. This resolves the common misconception that profit only tracks cash: the same month\'s net cash flow excludes both timing-difference items."}]},"minutes_min":1,"minutes_max":2,"diagram":null},{"id":"transfer","title":"A new month at Harbor Tea Room","kind":"transfer","instructions":"Original fictional case. Harbor Tea Room, one calendar month, amounts in dollars. The same rule applies: accrual profit counts revenues earned and expenses incurred in the month regardless of cash movement; net cash flow counts only cash received and paid this month.\\n\\nThis month\'s facts:\\n- Cash sales collected this month: $3,100\\n- Advertising paid in cash this month, for a campaign that runs next month: $400\\n- Wages paid in cash this month: $1,100\\n- Tea and pastry supplies from a supplier, used this month, invoice unpaid: $350\\n- Rent paid in cash this month: $700\\n\\nCompute this month\'s net cash flow, then explain what makes accrual profit differ from it.","data":[{"id":"cash_sales","label":"Cash sales collected this month","value":3100.0,"unit":"dollars"},{"id":"ad_paid_next_month","label":"Advertising paid in cash this month, campaign runs next month","value":400.0,"unit":"dollars"},{"id":"wages_paid","label":"Wages paid in cash this month","value":1100.0,"unit":"dollars"},{"id":"supplies_owed","label":"Supplies used this month, invoice unpaid","value":350.0,"unit":"dollars"},{"id":"rent_paid","label":"Rent paid in cash this month","value":700.0,"unit":"dollars"}],"fields":[{"id":"cash_flow","label":"Net cash flow for the month (dollars)","kind":"number","unit":"dollars","choices":[],"expression":"cash_sales - ad_paid_next_month - wages_paid - rent_paid","correct_choice":null,"tolerance":0.01,"criteria":[],"rubric_criterion":"Totals cash in minus cash out, ignoring non-cash items","hint":"Include every cash receipt and every cash payment; the unpaid supplier invoice never touched the bank account this month.","misconceptions":[{"expression":"cash_sales - ad_paid_next_month - wages_paid - rent_paid - supplies_owed","feedback":"You subtracted the unpaid supplier invoice, but that is an accrued expense, not cash out this month."},{"expression":"cash_sales - wages_paid - rent_paid","feedback":"You left out the advertising payment; cash left the account this month even though the campaign runs next month."},{"expression":"cash_sales - supplies_owed - wages_paid - rent_paid","feedback":"You swapped the unpaid invoice for the advertising bill; only the advertising cash actually left this month."}]},{"id":"difference","label":"Which items make accrual profit differ from net cash flow, and in which direction does each push it?","kind":"text","unit":"","choices":[],"expression":null,"correct_choice":null,"tolerance":0.01,"criteria":["Names the prepaid advertising as excluded from this month\'s accrual profit","States that the unpaid supplies invoice raises accrual profit\'s expenses (lowers profit) relative to cash flow","Uses timing of earning/expense versus timing of cash as the reason"],"rubric_criterion":"Explains both timing differences and their directions","hint":"Compare the two totals item by item: which items appear in profit but not cash, and which in cash but not profit?"}],"hint":"For net cash flow, follow the cash only: money in minus money out this month, no matter which month the work or the benefit belongs to.","worked_solution":{"version":1,"steps":[{"field_id":"cash_flow","explanation":"Net cash flow tracks only money that moved through the account this month. Cash in is the cash sales of $3,100. Cash out is advertising paid of $400, wages paid of $1,100 and rent paid of $700. The unpaid supplier invoice of $350 is an expense of this month under accrual accounting, but no cash has left yet, so it is excluded from cash flow; the advertising payment is included even though the campaign runs next month. This reverses the trap from the Riverside case: there, items belonged in profit but not in cash flow; here an item belongs in cash flow but not in this month\'s profit."},{"field_id":"difference","explanation":"Two timing items drive the difference. First, the $400 advertising was paid now but belongs to next month\'s campaign, so it sits in cash flow but not this month\'s accrual profit; leaving it out makes accrual profit $400 higher than cash flow. Second, the $350 supplies invoice covers goods used this month but is unpaid, so it sits in accrual profit but not cash flow, lowering profit by $350 relative to cash. A strong answer names both items and directions, e.g.: \\"The prepaid advertising boosts profit versus cash flow because the cash went out early, while the unpaid supplies invoice drags profit below cash flow because the expense is counted before the cash leaves.\\""}]},"minutes_min":1,"minutes_max":2,"diagram":null}]}}')
ATTEMPT_1 = json.loads('{"field_patches":[],"solution_patches":[{"activity_id":"transfer","worked_solution":{"steps":[{"field_id":"cash_flow","explanation":"Net cash flow tracks only money that actually moved through the account this month. Cash in is the cash sales collected. Cash out is the advertising paid in cash, the wages paid in cash, and the rent paid in cash. The unpaid supplies invoice is an expense of this month under accrual accounting, but no cash has left yet, so it is excluded from cash flow. The advertising payment is included even though the campaign runs next month, because the cash left this month. This reverses the trap from the Riverside case: there, items belonged in accrual profit but not in cash flow; here an item belongs in cash flow but not in this month\'s accrual profit."},{"field_id":"difference","explanation":"Two timing items drive the difference between accrual profit and net cash flow. First, the advertising was paid now but belongs to next month\'s campaign, so it sits in cash flow but not in this month\'s accrual profit; leaving that prepayment out of accrued expenses pushes accrual profit above cash flow by the amount of the advertising payment. Second, the supplies invoice covers goods used this month but is unpaid, so it sits in accrual profit but not in cash flow, dragging accrual profit below cash flow by the amount owed to the supplier. Combining the two opposing pushes gives the net gap between the measures. The underlying reason in both cases is the timing of earning or incurring versus the timing of cash movement: a strong answer names both items, states the direction each pushes accrual profit relative to cash flow, and attributes the gap to that timing mismatch rather than to any change in the underlying business results."}]}},{"activity_id":"guided","worked_solution":{"steps":[{"field_id":"accrual_only","explanation":"Catering sales were earned this month but no cash was collected, so they raise accrual profit while leaving cash flow unchanged. Utilities were used (incurred) this month but unpaid, so they reduce accrual profit without any cash leaving. Cash sales and rent appear in both measures: each was earned or incurred this month and its cash also moved this month, so neither separates the two."},{"field_id":"accrual_profit","explanation":"Accrual profit adds all revenue earned this month — cash sales plus invoiced catering sales — and subtracts all expenses incurred this month, whether or not cash moved: supplies, wages, rent and the unpaid utilities. The uncollected catering sales enter with a plus sign because earning, not collection, drives accrual revenue; the unpaid utilities enter with a minus sign because using them this month makes them an incurred expense. This resolves the common misconception that profit only tracks cash: the same month\'s net cash flow excludes both timing-difference items."}]}},{"activity_id":"guided","worked_solution":{"steps":[{"field_id":"accrual_only","explanation":"Catering sales were earned this month but no cash was collected, so they raise accrual profit while leaving cash flow unchanged. Utilities were used (incurred) this month but unpaid, so they reduce accrual profit without any cash leaving. Cash sales and rent appear in both measures: each was earned or incurred this month and its cash also moved this month, so neither separates the two."},{"field_id":"accrual_profit","explanation":"Accrual profit adds all revenue earned this month — cash sales plus invoiced catering sales — and subtracts all expenses incurred this month, whether or not cash moved: supplies, wages, rent and the unpaid utilities. The uncollected catering sales enter with a plus sign because earning, not collection, drives accrual revenue; the unpaid utilities enter with a minus sign because using them this month makes them an incurred expense. This resolves the common misconception that profit only tracks cash: the same month\'s net cash flow excludes both timing-difference items."}]}}],"public_defects":[]}')
ATTEMPT_2 = json.loads('{"field_patches":[],"solution_patches":[{"activity_id":"transfer","worked_solution":{"version":1,"steps":[{"field_id":"cash_flow","explanation":"Net cash flow tracks only money that actually moved through the account this month. Cash in is the cash sales collected. Cash out is the advertising paid in cash, the wages paid in cash, and the rent paid in cash. The unpaid supplies invoice is an expense of this month under accrual accounting, but no cash has left yet, so it is excluded from cash flow. The advertising payment is included even though the campaign runs next month, because the cash left this month. This reverses the trap from the Riverside case: there, items belonged in accrual profit but not in cash flow; here an item belongs in cash flow but not in this month\'s accrual profit."},{"field_id":"difference","explanation":"Two timing items drive the difference between accrual profit and net cash flow. First, the advertising was paid now but belongs to next month\'s campaign, so it sits in cash flow but not in this month\'s accrual profit; leaving that prepayment out of accrued expenses pushes accrual profit above cash flow by the amount of the advertising payment. Second, the supplies invoice covers goods used this month but is unpaid, so it sits in accrual profit but not in cash flow, dragging accrual profit below cash flow by the amount owed to the supplier. Combining the two opposing pushes gives the net gap between the measures. The underlying reason in both cases is the timing of earning or incurring versus the timing of cash movement: a strong answer names both items, states the direction each pushes accrual profit relative to cash flow, and attributes the gap to that timing mismatch rather than to any change in the underlying business results."}]}},{"activity_id":"guided","worked_solution":{"version":1,"steps":[{"field_id":"accrual_only","explanation":"Catering sales were earned this month but no cash was collected, so they raise accrual profit while leaving cash flow unchanged. Utilities were used (incurred) this month but unpaid, so they reduce accrual profit without any cash leaving. Cash sales and rent appear in both measures: each was earned or incurred this month and its cash also moved this month, so neither separates the two."},{"field_id":"accrual_profit","explanation":"Accrual profit adds all revenue earned this month — cash sales plus invoiced catering sales — and subtracts all expenses incurred this month, whether or not cash moved: supplies, wages, rent and the unpaid utilities. The uncollected catering sales enter with a plus sign because earning, not collection, drives accrual revenue; the unpaid utilities enter with a minus sign because using them this month makes them an incurred expense. This resolves the common misconception that profit only tracks cash: the same month\'s net cash flow excludes both timing-difference items."}]}}],"solution_step_patches":[],"public_defects":[]}')
TARGETS = ["practice.transfer"]


def package():
    return LessonPackage.model_validate(PACKAGE)


def solutions(value: LessonPackage) -> dict:
    return {activity.id: activity.worked_solution.model_dump(mode="json")
            for activity in value.workbook.activities}


def test_recorded_attempts_are_rejected_without_normalization():
    with pytest.raises(ValueError):
        PrivatePackageRepair.model_validate(ATTEMPT_1)  # worked_solution.version missing
    repair = PrivatePackageRepair.model_validate(ATTEMPT_2)
    with pytest.raises(ValueError, match="exceeds the independently rejected scope"):
        _check_private_repair_scope(repair, _validated_repair_scope(package(), TARGETS))


@pytest.mark.parametrize("raw", [ATTEMPT_1, ATTEMPT_2], ids=["attempt_1", "attempt_2"])
def test_recorded_attempts_apply_after_normalization(raw):
    before = package()
    original = copy.deepcopy(raw)
    data, count = normalize_private_repair(raw, before, TARGETS)
    assert raw == original and count >= 1  # The provider object itself is untouched.
    assert [patch["activity_id"] for patch in data["solution_patches"]] == ["transfer"]
    assert data["solution_patches"][0]["worked_solution"]["version"] == 1
    corrected = apply_private_package_repair(before, PrivatePackageRepair.model_validate(data),
                                             repair_targets=TARGETS)
    assert corrected.writer_context() == before.writer_context()
    after, prior = solutions(corrected), solutions(before)
    assert after["guided"] == prior["guided"]
    expected = copy.deepcopy(ATTEMPT_2["solution_patches"][0]["worked_solution"])
    assert after["transfer"] == expected != prior["transfer"]


@pytest.mark.parametrize("raw", [ATTEMPT_1, ATTEMPT_2], ids=["attempt_1", "attempt_2"])
def test_a_real_out_of_scope_change_is_still_rejected(raw):
    changed = copy.deepcopy(raw)
    guided = next(patch for patch in changed["solution_patches"] if patch["activity_id"] == "guided")
    guided["worked_solution"]["steps"][0]["explanation"] += " Utilities are a cash item."
    data, _ = normalize_private_repair(changed, package(), TARGETS)
    assert "guided" in {patch["activity_id"] for patch in data["solution_patches"]}
    with pytest.raises(ValueError, match="exceeds the independently rejected scope"):
        apply_private_package_repair(package(), PrivatePackageRepair.model_validate(data), repair_targets=TARGETS)


def test_out_of_scope_field_and_step_patches_drop_only_when_identical():
    before = package()
    guided = before.workbook.activities[0]
    number = next(field for field in guided.fields if field.kind == "number")
    step = guided.worked_solution.steps[0]
    transfer = ATTEMPT_2["solution_patches"][0]
    same = {"field_patches": [{"activity_id": "guided", "field_id": number.id, "expression": number.expression}],
            "solution_step_patches": [{"activity_id": "guided", "field_id": step.field_id,
                                       "explanation": step.explanation}],
            "solution_patches": [transfer]}
    data, count = normalize_private_repair(same, before, TARGETS)
    assert count == 2 and data["field_patches"] == [] and data["solution_step_patches"] == []
    apply_private_package_repair(before, PrivatePackageRepair.model_validate(data), repair_targets=TARGETS)
    for key, change in (("field_patches", {"expression": number.expression + " + 1"}),
                        ("solution_step_patches", {"explanation": step.explanation + " Changed."})):
        edited = copy.deepcopy(same)
        edited[key][0].update(change)
        data, _ = normalize_private_repair(edited, before, TARGETS)
        assert len(data[key]) == 1
        with pytest.raises(ValueError, match="exceeds the independently rejected scope"):
            apply_private_package_repair(before, PrivatePackageRepair.model_validate(data), repair_targets=TARGETS)


def test_only_exact_duplicates_collapse_and_other_versions_stay_invalid():
    transfer = copy.deepcopy(ATTEMPT_2["solution_patches"][0])
    data, count = normalize_private_repair({"solution_patches": [transfer, copy.deepcopy(transfer)]},
                                           package(), TARGETS)
    assert count == 1 and data["solution_patches"] == [transfer]
    variant = copy.deepcopy(transfer)
    variant["worked_solution"]["steps"][0]["explanation"] += " Different."
    data, _ = normalize_private_repair({"solution_patches": [transfer, variant]}, package(), TARGETS)
    with pytest.raises(ValueError, match="duplicate"):
        apply_private_package_repair(package(), PrivatePackageRepair.model_validate(data), repair_targets=TARGETS)
    wrong = copy.deepcopy(transfer)
    wrong["worked_solution"]["version"] = 2
    data, _ = normalize_private_repair({"solution_patches": [wrong]}, package(), TARGETS)
    with pytest.raises(ValueError):
        PrivatePackageRepair.model_validate(data)


def test_without_validated_targets_nothing_is_dropped():
    data, _ = normalize_private_repair(ATTEMPT_2, package(), None)
    assert [patch["activity_id"] for patch in data["solution_patches"]] == ["transfer", "guided"]


@pytest.mark.asyncio
async def test_generate_package_applies_recorded_first_attempt_in_one_call(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[LLMResponse(data=copy.deepcopy(ATTEMPT_1))]))
    before = package()
    corrected, response, _ = await generate_package({}, {}, client_factory=lambda **kwargs: client,
        prior_package=before, defects=["practice.transfer: wrong net gap"], repair_targets=TARGETS)
    assert response.error is None and client.generate_json.await_count == 1
    assert solutions(corrected)["guided"] == solutions(before)["guided"]
    assert solutions(corrected)["transfer"] == ATTEMPT_2["solution_patches"][0]["worked_solution"]
    assert response.effective_parameters["normalized_private_repair_count"] >= 1
