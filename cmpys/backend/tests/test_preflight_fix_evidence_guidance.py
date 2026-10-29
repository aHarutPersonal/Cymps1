"""A negative evidence verdict still blocks, but its free text never reaches a repair."""
import asyncio

import pytest

from tests.test_package_split_preflight import Harness, isolate, package, run  # noqa: F401

# Verbatim free-text "issue" from the accounting_novice_evidence smoke run (span n7).
ARTIFACT_ISSUE = (
    "n7 (practice.transfer): the span is an instruction to 'compute net cash change' but displays no "
    "numeric result; the prior calculation with claimed_result 1300 cannot be bound to this span. "
    "The span needs to display the computed net cash change (or its operands) so the calculation "
    "can be bound to an exact source quote.")
SEMANTIC = {"acceptable": False, "issues": [{"target": "practice.a0",
    "description": "The chosen formula contradicts the supplied task assumptions."}]}


def forbidden(text: str) -> bool:
    return any(token in text for token in ("1300", "display the computed", "net cash change", "claimed_result"))


@pytest.mark.asyncio
@pytest.mark.parametrize("field", ["issues", "package_issues"])
async def test_evidence_negative_blocks_with_coded_guidance_only(isolate, field):
    harness = Harness({"a0": [{field: [ARTIFACT_ISSUE]}], "a1": ["good"]})
    (failures, response, _), snapshots = await asyncio.wait_for(run(harness), 2)
    # Still a rejection of exactly the owning activity, repairable.
    assert failures and response.error is None and not response.data["acceptable"]
    assert response.effective_parameters["validated_repair_targets"] == ["practice.a0"]
    forwarded = "\n".join(failures) + "\n" + "\n".join(map(str, response.data["issues"]))
    assert not forbidden(forwarded)
    assert failures[0].startswith("practice.a0: ") and "n1" in failures[0]
    assert "evidence_model_rejected" in failures[0]
    saved = snapshots[-1]["rejection"]
    assert not saved["unavailable"] and [i["target"] for i in saved["issues"]] == ["practice.a0"]
    assert not forbidden(" ".join(i["description"] for i in saved["issues"]))
    # Resume reproduces the same coded rejection without another call.
    repeated = Harness()
    (again, _, _), _ = await run(repeated, existing=snapshots[-1])
    assert again == failures and repeated.requests == []


@pytest.mark.asyncio
async def test_semantic_guidance_is_still_forwarded_verbatim(isolate):
    harness = Harness({"a0": ["good"], "a1": ["good"]}, semantic=[("after_done", ["a0", "a1"], SEMANTIC)])
    (failures, _, _), _ = await asyncio.wait_for(run(harness), 2)
    assert failures == ["practice.a0: The chosen formula contradicts the supplied task assumptions."]
