"""Recover misplaced JSON envelopes without rewriting lessons or verdicts."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage, generate_package, parse_package_response
from app.services.planning.package_review import parse_package_review_response, review_package
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import structured_package_fixture


def misplaced_title():
    payload = package_payload()
    payload["workbook"]["activities"][1]["workbook_title"] = payload["workbook"].pop("title")
    return payload


def test_unique_misplaced_title_moves_verbatim_without_mutating_response():
    expected = package_payload()
    expected["workbook"]["title"] = "  Վարժությունների գիրք — practice  "
    raw = copy.deepcopy(expected)
    raw["workbook"]["activities"][1]["workbook_title"] = raw["workbook"].pop("title")
    before = copy.deepcopy(raw)
    assert parse_package_response(raw) == LessonPackage.model_validate(expected)
    assert raw == before


@pytest.mark.parametrize("defect", [
    "existing_title", "null_title", "empty_title", "duplicate_same", "duplicate_different",
    "empty_misplaced", "whitespace_misplaced", "nonstring_misplaced", "oversized_misplaced",
    "unknown_property", "invalid_answer", "missing_answer",
])
def test_title_relocation_never_resolves_ambiguity_or_other_contract_defects(defect):
    raw = misplaced_title()
    wb = raw["workbook"]
    activity = wb["activities"][1]
    if defect in {"existing_title", "null_title", "empty_title"}:
        wb["title"] = {"existing_title": "Existing title", "null_title": None, "empty_title": ""}[defect]
    elif defect.startswith("duplicate_"):
        wb["activities"][0]["workbook_title"] = (
            activity["workbook_title"] if defect == "duplicate_same" else "Competing title")
    elif defect == "empty_misplaced":
        activity["workbook_title"] = ""
    elif defect == "whitespace_misplaced":
        activity["workbook_title"] = "  \n"
    elif defect == "nonstring_misplaced":
        activity["workbook_title"] = {"title": "Not a string"}
    elif defect == "oversized_misplaced":
        activity["workbook_title"] = "x" * 161
    elif defect == "unknown_property":
        activity["unexpected"] = "Preserve and reject this content"
    elif defect == "invalid_answer":
        activity["fields"][0].update(kind="number", expression="invented / 0")
    else:
        activity["fields"][0].pop("criteria")
    before = copy.deepcopy(raw)
    with pytest.raises(ValueError):
        parse_package_response(raw)
    assert raw == before


@pytest.mark.asyncio
async def test_title_relocation_avoids_another_provider_request(monkeypatch):
    telemetry = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    raw = structured_package_fixture(misplaced_title())
    response = LLMResponse(data=raw)
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    package, actual, _ = await generate_package({}, {}, client_factory=lambda **kwargs: client)
    assert package == LessonPackage.model_validate(structured_package_fixture(package_payload()))
    assert actual is response and actual.error is None and actual.data == raw
    assert client.generate_json.await_count == 1
    telemetry.assert_not_awaited()


def test_structured_issue_preserves_all_json_meaning_and_source():
    issue = {"field": "workbook.activities[transfer].worked_solution",
             "reason": "Բացատրությունը չի համապատասխանում տվյալներին։",
             "evidence": {"claimed": 10, "expected": 6, "blocking": True, "note": None},
             "actions": ["Recompute the difference", "Correct its explanation"]}
    raw = {"acceptable": False, "issues": ["Another defect", issue]}
    original = copy.deepcopy(raw)
    review = parse_package_review_response(raw)
    assert review.acceptable is False and review.issues[0] == "Another defect"
    assert json.loads(review.issues[1]) == issue
    assert review.issues[1] == json.dumps(issue, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    assert raw == original


@pytest.mark.parametrize("issue", [
    {}, {"reason": ""}, {"reason": "  "}, {"reason": None}, {"reason": {}},
    {"reason": "x" * 1201}, {"reason": "x" * 1190, "target": "exceeds the total limit"},
    {"value": float("nan")}, {"value": float("inf")}, {"value": {1, 2}},
    {"value": ("not", "JSON")}, {1: "Nonstring key"}, {" ": "Empty key"},
    {"reason": "invalid\x00text"}, {"items": [0] * 65},
    {"one": {"two": {"three": {"four": {"five": "Too deep"}}}}},
])
def test_structured_issue_normalization_rejects_empty_malformed_or_unbounded_objects(issue):
    with pytest.raises(ValueError):
        parse_package_review_response({"acceptable": False, "issues": [issue]})


@pytest.mark.parametrize("defect", ["string_verdict", "missing_verdict", "unknown_root", "empty_peer", "too_many"])
def test_structured_issues_do_not_weaken_other_review_constraints(defect):
    raw = {"acceptable": False, "issues": [{"reason": "Incorrect explanation"}]}
    if defect == "string_verdict":
        raw["acceptable"] = "false"
    elif defect == "missing_verdict":
        raw.pop("acceptable")
    elif defect == "unknown_root":
        raw["unexpected"] = "Do not discard"
    elif defect == "empty_peer":
        raw["issues"].append("")
    else:
        raw["issues"] *= 13
    with pytest.raises(ValueError):
        parse_package_review_response(raw)


@pytest.mark.asyncio
@pytest.mark.parametrize("acceptable", [False, True])
async def test_structured_negative_issue_is_final_without_another_paid_review(monkeypatch, acceptable):
    telemetry = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    issue = {"target": "workbook.activities[transfer].worked_solution", "issue": "The reason contradicts the raw facts"}
    response = LLMResponse(data={"acceptable": acceptable, "issues": [issue]})
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, actual, _ = await review_package(
        LessonPackage.model_validate(package_payload()), {}, {}, client_factory=lambda **kwargs: client)
    assert len(failures) == 1 and json.loads(failures[0]) == issue
    assert actual is response and actual.error is None
    assert actual.data["acceptable"] is acceptable
    assert actual.data["issues"] == failures
    assert client.generate_json.await_count == 1
    telemetry.assert_not_awaited()


@pytest.mark.parametrize("length", [847, 1188])
def test_captured_length_and_maximum_structured_issue_preserve_the_entire_defect(length):
    issue = {"issue": "x" * length}
    verdict = parse_package_review_response({"acceptable": False, "issues": [issue]})
    assert not verdict.acceptable
    assert len(verdict.issues[0]) == length + 12
    assert json.loads(verdict.issues[0]) == issue


def test_structured_issue_one_character_over_total_limit_is_rejected():
    with pytest.raises(ValueError):
        parse_package_review_response({"acceptable": False, "issues": [{"issue": "x" * 1189}]})


@pytest.mark.asyncio
@pytest.mark.parametrize("issue", [{}, {"issue": "x" * 1201}, {"issue": None}])
async def test_malformed_negative_verdict_cannot_be_reasked_into_approval(monkeypatch, issue):
    telemetry = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    negative = LLMResponse(data={"acceptable": False, "issues": [issue]})
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        negative, LLMResponse(data={"acceptable": True, "issues": []})]))
    failures, response, _ = await review_package(
        LessonPackage.model_validate(package_payload()), {}, {}, client_factory=lambda **kwargs: client)
    assert failures and response is negative and response.error
    assert client.generate_json.await_count == 1
    telemetry.assert_not_awaited()
