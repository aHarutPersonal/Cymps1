"""The evidence binder's negative answer is a correction, not a verdict (pilot 2026-11-03).

native-luna accounting_experienced_evidence: the binder rejected "n4 incorrectly
states that net cash movement is $400" -- the $400 sits inside the deliberately
wrong quoted attempt the learner must correct. Such quoted numbers are exempt
only when every one also appears in the activity's data or checked worked
solution; any other number, inside or outside the quote, is still traced.
"""
import asyncio

import pytest

from tests.phase0_fixtures import model_binder_mechanics  # noqa: F401

# Phase 0.4 binds exact computed values in code; these tests exercise the model
# binder's mechanics, so they keep the earlier server bindings (tests/phase0_fixtures.py).
pytestmark = pytest.mark.usefixtures("model_binder_mechanics")

from app.services.planning import package_preflight as preflight
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import numeric_spans
from tests.lesson_package_fixtures import package_payload
from tests.test_package_split_preflight import Harness, isolate, run  # noqa: F401

NEGATIVE = {"issues": ["n1 incorrectly states the difference; recompute it."]}


@pytest.mark.asyncio
async def test_first_binder_negative_takes_the_correction_and_can_pass(isolate):
    harness = Harness({"a0": [NEGATIVE], "a1": ["good"]})
    (failures, response, _), snapshots = await asyncio.wait_for(run(harness), 2)
    assert failures == [] and response.error is None and response.data["acceptable"]
    assert harness.counts == {"semantic": 1, "a0": 2, "a1": 1}
    assert snapshots[-1]["correction_used"] and set(snapshots[-1]["scopes"]) == {"a0", "a1"}


@pytest.mark.asyncio
async def test_repeated_binder_negative_still_blocks_its_activity_with_server_text_only(isolate):
    harness = Harness({"a0": [NEGATIVE, NEGATIVE], "a1": ["good"]})
    (failures, response, _), snapshots = await asyncio.wait_for(run(harness), 2)
    [failure] = failures
    assert failure.startswith("practice.a0: ") and "evidence_model_rejected" in failure
    assert "recompute" not in failure and response.effective_parameters["validated_repair_targets"] == ["practice.a0"]
    assert [issue["target"] for issue in snapshots[-1]["rejection"]["issues"]] == ["practice.a0"]


# --- the quoted diagnostic attempt ------------------------------------------------------------

DATA = [{"id": "revenue_earned_current", "label": "Current-period revenue earned", "value": 1200, "unit": "USD"},
        {"id": "expenses_incurred_current", "label": "Current-period expenses incurred", "value": 800, "unit": "USD"},
        {"id": "cash_collected_current", "label": "Cash collected from current-period sales", "value": 900, "unit": "USD"},
        {"id": "cash_paid_current", "label": "Cash paid for current-period expenses", "value": 400, "unit": "USD"}]
ATTEMPT = ("A diagnostic attempt says:\n“Conclusion: Accrual profit and net cash movement are both $400 because they "
           "describe the cafe’s result for the period. Reason 1: Subtracting $800 of expenses from $1,200 of revenue "
           "gives $400.”\n\nIdentify the defect and give a corrected version.")
SOLUTION = ("Accrual profit is $1,200 − $800 = $400. Net cash movement is $900 − $400 = $500, so the measures differ.\n"
            "Explain why each timing difference follows from the supplied ledger.")


def spans(instructions, solution=SOLUTION):
    payload = package_payload()
    activity = payload["workbook"]["activities"][0]
    activity.update(data=DATA, instructions=instructions, worked_solution=solution)
    return list(numeric_spans({}, LessonPackage.model_validate(payload).review_context()).values())


def test_quoted_attempt_numbers_shown_elsewhere_are_not_claims():
    assert not any("diagnostic attempt" in span or "Reason 1" in span or "both $400" in span
                   for span in spans(ATTEMPT))


def test_the_same_number_outside_the_quote_is_still_a_claim():
    found = spans(ATTEMPT + " Note that net cash movement is $400.")
    assert "Note that net cash movement is $400." in found


def test_a_quoted_number_the_learner_never_meets_in_checked_content_keeps_the_whole_quote_traced():
    unknown = ATTEMPT.replace("both $400", "both $450")
    found = spans(unknown)
    assert any("$450" in span for span in found) and any("gives $400" in span for span in found)


def test_quotes_without_an_attempt_introduction_are_traced():
    found = spans("The owner says: “Accrual profit and net cash movement are both $400 this period.” Explain.")
    assert any("$400" in span for span in found)
