"""Exact proof grouping shrinks requests without replacing source verification."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_review import PackagedCalculationCheck, ReviewEvidencePatch
from app.services.planning.package_review import (
    PackageReview, _SYSTEM_PROMPT, _compact_calculation_evidence,
    _evidence_patch_request, _merge_evidence_patch, _numeric_preflight_failures,
    package_review_payload, review_package,
)
from tests.test_geometry_evidence_roles import triangle_package, check


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def verdict(checks, **overrides):
    return PackageReview.model_validate({
        "acceptable": True, "issues": [], "contains_calculations": True,
        "calculations": checks, **overrides,
    })


def repeated_fixture(count=5):
    package = triangle_package("\n".join(["Area: 81."] * count))
    payload = package_review_payload(package, {}, {})
    ids = list(payload["numeric_spans"])
    return package, payload, ids, verdict([check(span=key) for key in ids])


def test_patch_groups_exact_copies_with_measured_smaller_request_and_unchanged_scope():
    package, payload, ids, original = repeated_fixture()
    before = copy.deepcopy(original.model_dump())
    payload_before = copy.deepcopy(payload)
    request, scope = _evidence_patch_request(original, payload, [
        f"{key}: numeric span contains additional unverified values" for key in ids])
    body = json.loads(request["user_prompt"])
    grouped = body["prior_evidence"]["calculations"]
    assert grouped == [{**check(), "claim_ids": ids}]
    ungrouped_body = copy.deepcopy(body)
    ungrouped_body["prior_evidence"]["calculations"] = [
        item.model_dump(exclude_none=True) for item in original.calculations]
    assert len(encoded(ungrouped_body)) - len(encoded(body)) == 396
    assert encoded(body).decode() == request["user_prompt"]
    assert scope == set(ids)
    assert body["numeric_spans"] == payload["numeric_spans"]
    assert original.model_dump() == before and payload == payload_before
    assert _numeric_preflight_failures(original, package) == ([], [])
    for prompt in (_SYSTEM_PROMPT, request["system_prompt"]):
        assert "Group identical calculations across source IDs" in prompt
        assert "every other evidence field is identical" in prompt
        assert "equal numeric values alone do not justify grouping" in prompt


def test_grouped_proof_still_verifies_every_source_and_preserves_semantic_rejection():
    package, payload, ids, original = repeated_fixture()
    grouped = _compact_calculation_evidence(original.calculations)
    patch = ReviewEvidencePatch.model_validate({"calculations": grouped})
    merged = _merge_evidence_patch(original, patch, set(ids), payload["numeric_spans"])
    assert _numeric_preflight_failures(merged, package) == ([], [])
    changed = package.model_copy(deep=True)
    changed.workbook.activities[0].worked_solution = changed.workbook.activities[0].worked_solution.replace(
        "Area: 81.", "Area: 80.", 1)
    source_errors, _ = _numeric_preflight_failures(merged, changed)
    assert len(source_errors) == 1 and "not 80" in source_errors[0]
    negative = original.model_copy(update={"acceptable": False, "issues": ["Transfer discloses the answer."]})
    retained = _merge_evidence_patch(negative, patch, set(ids), payload["numeric_spans"])
    assert not retained.acceptable and retained.issues == negative.issues


@pytest.mark.parametrize("changed", [
    {"case_id": "practice.transfer"},
    {"expression": "height * base / 2"},
    {"expression": "base*height/2"},
    {"claimed_result": 80},
    {"claimed_literal": "pass"},
])
def test_every_other_typed_field_must_match_exactly(changed):
    first = PackagedCalculationCheck.model_validate(check(span="n1"))
    second = PackagedCalculationCheck.model_validate({**check(span="n2"), **changed})
    compact = _compact_calculation_evidence([first, second])
    assert compact == [first.model_dump(exclude_none=True), second.model_dump(exclude_none=True)]


def test_grouping_preserves_first_occurrence_order_and_deduplicates_only_identical_claims():
    entries = [
        {**check(), "claim_ids": ["n3", "n1", "n3"]},
        check(span="n1", expression="base * height", value=162),
        {**check(), "claim_ids": ["n2", "n1"]},
    ]
    original = [PackagedCalculationCheck.model_validate(item) for item in entries]
    before = [item.model_dump() for item in original]
    compact = _compact_calculation_evidence(original)
    assert compact == [
        {**check(), "claim_ids": ["n3", "n1", "n2"]},
        check(span="n1", expression="base * height", value=162),
    ]
    assert [item.model_dump() for item in original] == before


def test_grouping_respects_existing_claim_id_limit_without_dropping_ids():
    ids = [f"n{index}" for index in range(1, 61)]
    original = [PackagedCalculationCheck.model_validate(check(span=key)) for key in ids]
    compact = _compact_calculation_evidence(original)
    assert [len(item["claim_ids"]) for item in compact] == [30, 30]
    assert [key for item in compact for key in item["claim_ids"]] == ids
    assert all(PackagedCalculationCheck.model_validate(item) for item in compact)


def test_request_scope_filter_and_partly_scoped_group_are_unchanged():
    _, payload, ids, _ = repeated_fixture(3)
    original = verdict([
        {**check(), "claim_ids": ids[:2]},
        check(span=ids[1]), check(span=ids[2]),
    ])
    request, scope = _evidence_patch_request(original, payload, [f"{ids[1]}: proof is incomplete"])
    body = json.loads(request["user_prompt"])
    assert scope == {ids[1]}
    assert set(body["numeric_spans"]) == scope
    # The copied proof agrees with the output scope. The merge retains the
    # original unaffected span separately, without asking the model to copy it.
    assert body["prior_evidence"]["calculations"] == [{**check(), "claim_ids": [ids[1]]}]


@pytest.mark.asyncio
async def test_actual_two_call_review_groups_request_and_accepts_only_correct_complete_patch(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    package, _, ids, _ = repeated_fixture()
    invalid = verdict([check(span=key, expression="base + height") for key in ids])
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=invalid.model_dump()),
        LLMResponse(data={"calculations": [{**check(), "claim_ids": ids}]}),
    ]))
    factory = Mock(return_value=client)
    failures, response, _ = await review_package(package, {}, {}, client_factory=factory)
    assert not failures and not response.error
    assert client.generate_json.await_count == 2
    factory.assert_called_once_with(tier="balanced", timeout=60, max_tokens=2000,
                                    thinking_level="low", allow_fallback=False)
    request = client.generate_json.call_args.kwargs
    prior = json.loads(request["user_prompt"])["prior_evidence"]["calculations"]
    assert prior == [{**check(expression="base + height"), "claim_ids": ids}]
    assert response.data["calculations"][0]["claim_ids"] == ids
