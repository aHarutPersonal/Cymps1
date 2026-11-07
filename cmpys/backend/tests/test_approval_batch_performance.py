"""Reuse immutable contract work within a decision, never prior approvals."""
import copy

from app.services.llm.schemas import PlanDetailStepOutput
from app.services.planning import lesson_package as contracts
from app.tasks import plans
from tests.lesson_package_fixtures import package_payload
from tests.test_plan_detail_output_schema import _valid_payload


def artifacts():
    package = contracts.LessonPackage.model_validate(package_payload())
    payload = _valid_payload(lesson_count=4, material_count=1)
    payload["steps"] = [PlanDetailStepOutput.model_validate(step).model_dump(mode="json")
                        for step in payload["steps"]]
    packages = {step["id"]: package for step in payload["steps"]}
    approvals = {step["id"]: contracts.provenance(step, package) for step in payload["steps"]}
    return payload, packages, approvals


def test_batch_uses_one_contract_and_preserves_per_lesson_hashes(monkeypatch):
    payload, packages, approvals = artifacts()
    identity = contracts.validation_identity()
    calls = []
    monkeypatch.setattr(plans, "validation_identity", lambda: calls.append(True) or copy.deepcopy(identity))
    payload["steps"][1]["lesson_content"] += " Unapproved change."
    before = copy.deepcopy((payload, approvals))
    assert plans._approved_candidate_step_ids(payload, packages, approvals) == {
        "step_1", "step_3", "step_4"}
    assert len(calls) == 1
    assert (payload, approvals) == before


def test_next_batch_observes_changed_contract(monkeypatch):
    payload, packages, approvals = artifacts()
    identity = contracts.validation_identity()
    monkeypatch.setattr(plans, "validation_identity", lambda: copy.deepcopy(identity))
    assert plans._approved_candidate_step_ids(payload, packages, approvals) == set(packages)
    identity["schema_hash"] = "0" * 64
    assert not plans._approved_candidate_step_ids(payload, packages, approvals)


def test_batch_rejects_changed_package_even_with_unchanged_prose():
    payload, packages, approvals = artifacts()
    replacement = packages["step_1"].model_copy(deep=True)
    replacement.workbook.title += " Changed"
    packages["step_1"] = replacement
    assert plans._approved_candidate_step_ids(payload, packages, approvals) == {
        "step_2", "step_3", "step_4"}


def test_empty_batch_does_no_contract_work(monkeypatch):
    def unexpected():
        raise AssertionError("An empty approval batch has no contract work")
    monkeypatch.setattr(plans, "validation_identity", unexpected)
    assert not plans._approved_candidate_step_ids({"steps": []}, {}, {})


def test_published_reuse_has_no_cross_call_cache(monkeypatch):
    payload, packages, approvals = artifacts()
    step = payload["steps"][0]
    package = packages[step["id"]]
    approval = approvals[step["id"]]
    identity = contracts.validation_identity()
    calls = []
    monkeypatch.setattr(contracts, "validation_identity", lambda: calls.append(True) or copy.deepcopy(identity))
    assert contracts.reusable_published_approval(step, package, approval)
    assert len(calls) == 1
    identity["schema_hash"] = "0" * 64
    assert not contracts.reusable_published_approval(step, package, approval)
    assert len(calls) == 2


def test_published_reuse_still_rejects_content_mutation():
    payload, packages, approvals = artifacts()
    step = payload["steps"][0]
    step["lesson_content"] += " Unapproved mutation."
    assert not contracts.reusable_published_approval(step, packages[step["id"]], approvals[step["id"]])
