"""Fix 3b: an exhausted evidence defect carries the server's own facts to the repair.

The repair hears the span id, its field path (never source text, per F18) and the
server-computed mismatch from the deterministic checks; the evidence model's free text is still never
forwarded. Accounting fixtures are the verbatim smoke2 accounting_novice package under
repair and its two recorded evidence responses for span n17 (practice.transfer).
"""
import asyncio
import copy
import json

import pytest

from tests.phase0_fixtures import model_binder_mechanics  # noqa: F401

# Phase 0.4 binds exact computed values in code; these tests exercise the model
# binder's mechanics, so they keep the earlier server bindings (tests/phase0_fixtures.py).
pytestmark = pytest.mark.usefixtures("model_binder_mechanics")

from app.services.planning import package_preflight as preflight
from app.services.planning.lesson_package import LessonPackage
from tests.test_package_fix2_repair_normalization import PACKAGE
from tests.test_package_split_preflight import Harness, isolate, package, run  # noqa: F401

EVIDENCE_1 = json.loads('{"calculations":[{"claim_ids":["n17"],"case_id":"practice.transfer","expression":"(cash_sales - wages_paid - rent_paid - supplies_owed) - (cash_sales - ad_paid_next_month - wages_paid - rent_paid)","claimed_result":400}],"literal_facts":[{"claim_id":"n17","case_id":"practice.transfer","datum_ids":["ad_paid_next_month"]}],"literal_fact_ids":["n17"],"issues":[],"package_issues":[]}')
EVIDENCE_2 = json.loads('{"calculations":[{"claim_ids":["n17"],"case_id":"practice.transfer","expression":"(cash_sales - wages_paid - rent_paid - supplies_owed) - (cash_sales - ad_paid_next_month - wages_paid - rent_paid)","claimed_result":400.0}],"issues":["n17 (practice.transfer): The span asserts that excluding the $400 prepaid advertising makes accrual profit $400 higher than cash flow. The correct comparison is accrual profit (3100 - 1100 - 700 - 350 = 950) versus net cash flow (3100 - 400 - 1100 - 700 = 900), a difference of $50, not $400, because the unpaid $350 supplies invoice also separates the two totals and works in the opposite direction. The text\'s directional attribution of the full $400 gap is numerically wrong and needs correction before approval."],"literal_facts":[{"claim_id":"n17","case_id":"practice.transfer","datum_ids":["ad_paid_next_month"]}],"literal_fact_ids":["n17"],"package_issues":[]}')
SPAN = ("First, the $400 advertising was paid now but belongs to next month's campaign, so it sits in cash "
        "flow but not this month's accrual profit; leaving it out makes accrual profit $400 higher than cash flow.")
SERVER_CHECK = "3100 - 1100 - 700 - 350 - (3100 - 400 - 1100 - 700) = 50"
# Evidence-model free text (its negative verdict) that must never reach the repair.
MODEL_TEXT = ("950", "900", "directional attribution", "opposite direction", "needs correction")


OUTLINE = {"id": "step_1", "title": "Distinguish accrual profit from cash", "lesson_format": "tutorial_v1",
           "description": "Learn one concept, apply it to a supplied case, then transfer it to a new case."}
CONTEXT = {"lesson_format": "tutorial_v1", "allotted_lesson_minutes": None, "target_practice_minutes": 3,
           "goal": "Distinguish accrual profit from cash using a fictional cafe ledger"}


def accounting():
    return LessonPackage.model_validate(PACKAGE)


async def run_accounting(harness, existing=None):
    snapshots = []

    async def save(state):
        snapshots.append(copy.deepcopy(state))

    result = await preflight.review_package(accounting(), OUTLINE, CONTEXT, client_factory=harness.factory,
                                            existing_review=existing, on_review=save)
    return result, snapshots


@pytest.mark.asyncio
async def test_accounting_negative_after_server_mismatch_forwards_server_facts_only(isolate):
    # The semantic stage explicitly audits this independent fixed-ledger choice
    # before this test exercises its separate numerical evidence rejection.
    audit = {"target": "practice.guided.accrual_only", "depends_on_learner_response": False,
        "dependency_reason": "Classification uses the supplied ledger, not another learner response.",
        "options": [
            {"option_id": "credit_sales", "defensible": True, "reason": "Earned sales are recognized before collection."},
            {"option_id": "utilities_owed", "defensible": True, "reason": "Used utilities are expensed before payment."},
            {"option_id": "cash_sales", "defensible": False, "reason": "Cash sales already affect both cash and accrual."},
            {"option_id": "rent_paid", "defensible": False, "reason": "Current rent already affects both cash and accrual."},
        ]}
    # Intentionally positive semantic evidence: the independent numeric gate
    # must still reject its wrong arithmetic and forward only server facts.
    text_audit = {"target": "practice.transfer.difference",
        "alternative_response": "Prepaid advertising affects cash now but accrual expense later; unpaid supplies affect expense now but cash later. The opposing timing differences must both enter the comparison.",
        "criteria": [{"criterion_index": index, "required_by_task": True, "accepts_alternative": True,
            "reason": "The answer explains both cash-versus-accrual timing differences."} for index in range(3)],
        "model_answer_valid": True, "model_answer_reason": "Synthetic semantic approval intentionally leaves arithmetic to the independent numeric gate.",
        "requires_activity_repair": False}
    harness = Harness({"transfer": [copy.deepcopy(EVIDENCE_1), copy.deepcopy(EVIDENCE_2)]},
                      semantic=[{"acceptable": True, "issues": [], "choice_audits": [audit],
                                 "text_audits": [text_audit],
                                 "teaching_case_audits": [{"target": "teaching.riverside_cafe_month",
                                     "core_inference": "Profit recognizes earning/incurrence; cash flow recognizes cash movements.",
                                     "quantities_and_units": "All revenue and expense inputs are dollars for this month.",
                                     "decision_rule": "Profit includes credit sales and owed utilities; cash flow excludes both.",
                                     "semantically_valid": True,
                                     "reason": "Both formulas use consistent currency, periods and recognition rules."}]}])
    (failures, response, _), snapshots = await asyncio.wait_for(run_accounting(harness), 2)
    assert harness.counts["transfer"] == 2 and response.error is None
    assert response.effective_parameters["validated_repair_targets"] == ["practice.transfer"]
    [failure] = failures
    assert failure.startswith("practice.transfer: ") and "evidence_model_rejected" in failure
    assert "n17 at practice.transfer.worked_solution.difference" in failure
    assert json.dumps(SPAN) not in failure  # Source text stays out of defects (F18).
    assert "states 400" in failure and SERVER_CHECK in failure
    assert not any(token in failure for token in MODEL_TEXT)
    saved = snapshots[-1]["rejection"]["issues"]
    assert [issue["target"] for issue in saved] == ["practice.transfer"]
    assert "practice.transfer: " + saved[0]["description"] == failure
    repeated = Harness()
    (again, _, _), _ = await run_accounting(repeated, existing=snapshots[-1])
    assert again == failures and repeated.requests == []


@pytest.mark.asyncio
async def test_exhausted_wrong_arithmetic_names_span_path_and_server_values(isolate):
    harness = Harness({"a1": ["bad_math", "bad_math"]})
    (failures, response, _), _ = await asyncio.wait_for(run(harness), 2)
    assert response.effective_parameters["validated_repair_targets"] == ["practice.a1"]
    [failure] = failures
    assert failure.startswith("practice.a1: ") and "wrong_arithmetic" in failure
    # a1: receipts 130, revenue 100; the bound formula was receipts + revenue for "Difference: 30".
    # The span is named by path and quoted by the server (repair path R7), once.
    assert 'at practice.a1.worked_solution quoting "Difference: 30."' in failure
    assert failure.count("Difference: 30") == 1
    assert "states 30" in failure and "130 + 100 = 230" in failure


@pytest.mark.asyncio
async def test_negative_without_server_check_still_forwards_no_model_text(isolate):
    issue = "n1 (practice.a0): the span needs to display the computed net cash change of 1300."
    harness = Harness({"a0": [{"issues": [issue]}, {"issues": [issue]}], "a1": ["good"]})
    (failures, _, _), _ = await asyncio.wait_for(run(harness), 2)
    assert harness.counts["a0"] == 2  # The first negative took the shared correction.
    [failure] = failures
    assert "evidence_model_rejected" in failure and "n1 at practice.a0.worked_solution" in failure
    assert not any(token in failure for token in ("1300", "display the computed", "net cash change"))
    assert "server evaluated" not in failure
