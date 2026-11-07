"""The narrow second look at answer-leak findings (pilot 2026-11-05).

A finding resting on stated givens or the general rule becomes advisory only
when a valid check quotes learner-visible text; every other outcome, including
an unavailable check or a rejection that cannot be approved, keeps it blocking.
"""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.leak_check import (
    answer_key, downgraded_leak_claims, leak_claim_indexes, learner_view,
)
from app.services.planning.package_preflight import review_package
from tests.test_short_tutorial_pipeline import short_package
from tests.text_audit_fixtures import argument_text_audits, public_notice_teaching_audits


def issue(description, target="practice.transfer", severity="blocking"):
    return SimpleNamespace(description=description, target=target, severity=severity)


def test_only_blocking_practice_leak_claims_are_checked():
    issues = [issue("Public text leaks the transfer answer: it states the rule."),
              issue("The hint gives away the answer path.", severity="advisory"),
              issue("Public text leaks the answer.", target="teaching.public_notice"),
              issue("The rubric omits the profit figure the instructions ask for."),
              # Similarity and independence claims stay blocking without a check.
              issue("Transfer leak and non-independence: near-identical facts to the worked example."),
              issue("Public instructions state the answer to the choice field.")]
    assert leak_claim_indexes(issues) == [0, 5]


def test_learner_view_keeps_keys_private_and_answer_key_holds_them():
    package = short_package()
    view = json.dumps(learner_view(package))
    for private in ("criteria", "worked_solution", "expression", "correct_choice", "misconception"):
        assert private not in view
    key = answer_key(package, "transfer")
    assert key["activity_id"] == "transfer" and key["fields"][0]["criteria"] and key["worked_solution"]


def check(verdict, quote, index=0):
    return {"verdicts": [{"claim_index": index, "public_quote": quote, "verdict": verdict, "reason": "Stated fact."}]}


def test_only_a_given_or_rule_verdict_quoting_visible_text_downgrades():
    package = short_package()
    quote = package.workbook.activities[1].instructions.split(". ")[0]
    assert downgraded_leak_claims(package, [3], check("given_or_rule_only", quote)) == {3}
    assert downgraded_leak_claims(package, [3], check("given_or_rule_only", "Invented sentence nobody can see.")) == set()
    for verdict in ("states_answer", "states_case_decision", "unclear"):
        assert downgraded_leak_claims(package, [3], check(verdict, quote)) == set()
    duplicate = {"verdicts": check("given_or_rule_only", quote)["verdicts"] * 2}
    assert downgraded_leak_claims(package, [3], duplicate) == set()
    assert downgraded_leak_claims(package, [3], check("given_or_rule_only", quote, index=1)) == set()
    assert downgraded_leak_claims(package, [3], {"verdicts": "approve"}) == set()


async def preflight(leak_response, *, audits=True, lesson_format="tutorial_v1", monkeypatch):
    package = short_package()
    quote = package.workbook.activities[1].instructions.split(". ")[0]
    finding = {"severity": "blocking", "target": "practice.transfer",
               "description": f"Public text leaks the transfer answer: '{quote}' states what the learner must do."}
    verdict = {"acceptable": False, "issues": [finding]}
    if audits:
        verdict.update(text_audits=argument_text_audits(package),
                       teaching_case_audits=public_notice_teaching_audits(package))
    calls = []

    async def generate_json(**kwargs):
        calls.append(kwargs["output_model"].__name__)
        if kwargs["output_model"].__name__ == "LeakCheck":
            return leak_response(quote)
        return LLMResponse(data=copy.deepcopy(verdict), finish_reason="stop")

    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock(return_value=True))
    failures, response, _ = await review_package(package, {"lesson_format": lesson_format}, {},
        client_factory=lambda **kwargs: SimpleNamespace(generate_json=generate_json))
    return failures, response, calls


@pytest.mark.asyncio
async def test_a_stated_given_becomes_advisory_and_the_package_is_approved(monkeypatch):
    failures, response, calls = await preflight(
        lambda quote: LLMResponse(data=check("given_or_rule_only", quote), finish_reason="stop"), monkeypatch=monkeypatch)
    assert failures == [] and response.semantic_accepted
    assert calls.count("LeakCheck") == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("leak_response", [
    lambda quote: LLMResponse(data=check("states_case_decision", quote), finish_reason="stop"),
    lambda quote: LLMResponse(data={}, error="Package preflight request budget exhausted"),
])
async def test_a_case_decision_or_unavailable_check_keeps_the_finding_blocking(leak_response, monkeypatch):
    failures, response, calls = await preflight(leak_response, monkeypatch=monkeypatch)
    assert failures and "leaks the transfer answer" in failures[0] and not response.semantic_accepted
    assert response.effective_parameters["validated_repair_targets"] == ["practice.transfer"]


@pytest.mark.asyncio
async def test_a_rejection_without_audits_keeps_its_finding_instead_of_becoming_unavailable(monkeypatch):
    failures, response, _ = await preflight(
        lambda quote: LLMResponse(data=check("given_or_rule_only", quote), finish_reason="stop"),
        audits=False, monkeypatch=monkeypatch)
    assert failures and "leaks the transfer answer" in failures[0]
    assert response.effective_parameters["validated_repair_targets"] == ["practice.transfer"]


@pytest.mark.asyncio
async def test_non_tutorial_packages_get_no_leak_check(monkeypatch):
    _, _, calls = await preflight(lambda quote: pytest.fail("no leak check expected"),
                                  lesson_format="guided_v1", monkeypatch=monkeypatch)
    assert "LeakCheck" not in calls
