"""An exact production approval remains readable without bypassing new gates."""
import copy

import pytest

from app.services.llm.schemas import PlanDetailStepOutput
from app.services.planning.lesson_package import (
    LessonPackage, current_package_approval, digest, validation_identity,
)
from tests.lesson_package_fixtures import package_payload
from tests.test_plan_detail_output_schema import _valid_payload


PRODUCTION_V7_IDENTITY = {
    "review_version": 7,
    "package_version": 1,
    "capability_hash": "1815a97ad0c7246f737c493fbec7b9217c6a5dd6a7d96cacd93c0c34b3afe48f",
    "prompt_hash": "194ab7d7fe815bbcd347d09eca046997dbb03f9ec4f0f2bcf3bdbef65bb51c20",
    "schema_hash": "69872a66dd96125909e6196f7257f85ad5242b0eefda87a9e266781858b57dc8",
}


def prior_approved_details():
    details = _valid_payload(lesson_count=1, material_count=1)
    step = PlanDetailStepOutput.model_validate(details["steps"][0]).model_dump(mode="json")
    package = LessonPackage.model_validate(package_payload())
    details["steps"] = [step]
    details["_generation"] = {
        "lesson_package_version": 1, "status": "partial",
        "job_id": "c5328b57-9d6b-4394-9dd6-4c01bdc11910",
        "ready_step_ids": ["step_1"],
        "validation_identity": copy.deepcopy(PRODUCTION_V7_IDENTITY),
        "lesson_validation": {"step_1": {
            **PRODUCTION_V7_IDENTITY,
            "content_hash": digest(step),
            "package_hash": digest(package.model_dump(mode="json")),
        }},
    }
    return details


def test_exact_production_v7_is_readable_but_never_current_generation_approval():
    from app.api.v1.plans import _partial_lesson_details_available

    assert digest(PRODUCTION_V7_IDENTITY) == "351f4940febd359405ca777cb9ab353ae48cedbe016de36c4732d07db269b3e9"
    details = prior_approved_details()
    assert validation_identity() != PRODUCTION_V7_IDENTITY
    assert current_package_approval(details, allow_compatible_read=True)
    assert _partial_lesson_details_available(details)
    assert not current_package_approval(details)
    assert not current_package_approval(details, allow_compatible_read=False)


@pytest.mark.parametrize("mutation", ["content", "unknown_v7", "approval_identity", "missing_package_hash", "missing_content_hash"])
def test_v7_read_compatibility_keeps_exact_identity_provenance_and_content_gates(mutation):
    details = prior_approved_details()
    generation = details["_generation"]
    approval = generation["lesson_validation"]["step_1"]
    if mutation == "content":
        details["steps"][0]["lesson_content"] += " Unapproved inserted teaching."
    elif mutation == "unknown_v7":
        generation["validation_identity"]["prompt_hash"] = "unknown-v7-contract"
        approval["prompt_hash"] = "unknown-v7-contract"
    elif mutation == "approval_identity":
        approval["review_version"] = 8
    elif mutation == "missing_package_hash":
        approval.pop("package_hash")
    else:
        approval.pop("content_hash")
    assert not current_package_approval(details, allow_compatible_read=True)
    assert not current_package_approval(details)


@pytest.mark.parametrize("status", ["partial", "ready"])
@pytest.mark.parametrize("mutation", [
    "details", "generation", "steps", "step", "step_id", "identity",
    "approvals", "approval", "missing_approval",
])
def test_malformed_package_provenance_fails_closed_before_api_readiness(status, mutation):
    from app.api.v1.plans import _lesson_details_meet_quality, _partial_lesson_details_available

    details = prior_approved_details()
    details["_generation"]["status"] = status
    if mutation == "details":
        details = ["malformed"]
    elif mutation == "generation":
        details["_generation"] = ["malformed"]
    elif mutation == "steps":
        details["steps"] = {"step_1": {}}
    elif mutation == "step":
        details["steps"][0] = ["malformed"]
    elif mutation == "step_id":
        details["steps"][0]["id"] = ["unhashable"]
    elif mutation == "identity":
        details["_generation"]["validation_identity"] = ["malformed"]
    elif mutation == "approvals":
        details["_generation"]["lesson_validation"] = ["malformed"]
    elif mutation == "approval":
        details["_generation"]["lesson_validation"]["step_1"] = []
    else:
        details["_generation"]["lesson_validation"].pop("step_1")
    original = copy.deepcopy(details)
    assert not current_package_approval(details, allow_compatible_read=True)
    assert not current_package_approval(details)
    assert not _lesson_details_meet_quality(details)
    assert not _partial_lesson_details_available(details)
    assert details == original


# Read-only production probe on 2026-10-23. This is the full server-computed
# contract, not the differing local v23 checkout or an arbitrary old version.
PRODUCTION_V23_IDENTITY = {
    "review_version": 23,
    "package_version": 1,
    "capability_hash": "1815a97ad0c7246f737c493fbec7b9217c6a5dd6a7d96cacd93c0c34b3afe48f",
    "prompt_hash": "c971af6e2e3353ba6baa08a8659937a47907c800ac4eaf0f35177747a72bc089",
    "generation_contract_hash": "51554b53590b55a0fcc8f4db238707a427816aca705edbfc4a9e8eb360faffea",
    "schema_hash": "3898967e9bf8814c14a4b9c9daae02cd492e069a0ae27ebcde887d9fa818d93b",
}


def production_v23_approved_details():
    details = prior_approved_details()
    details["_generation"]["validation_identity"] = copy.deepcopy(PRODUCTION_V23_IDENTITY)
    details["_generation"]["lesson_validation"]["step_1"].update(PRODUCTION_V23_IDENTITY)
    return details


def test_exact_observed_production_v23_is_readable_but_cannot_approve_new_generation():
    from app.api.v1.plans import _partial_lesson_details_available

    assert digest(PRODUCTION_V23_IDENTITY) == "8aeec01071281cfd7dc41791b5187dd36a9630ec64742c54365a8a8b7a718df9"
    details = production_v23_approved_details()
    before = copy.deepcopy(details)
    assert validation_identity() != PRODUCTION_V23_IDENTITY
    assert current_package_approval(details, allow_compatible_read=True)
    assert _partial_lesson_details_available(details)
    assert not current_package_approval(details)
    assert details == before


@pytest.mark.parametrize("mutation", [
    "content", "unknown_contract", "approval_identity", "missing_package_hash", "missing_content_hash",
])
def test_production_v23_pin_preserves_exact_approval_and_content_boundaries(mutation):
    details = production_v23_approved_details()
    generation = details["_generation"]
    approval = generation["lesson_validation"]["step_1"]
    if mutation == "content":
        details["steps"][0]["lesson_content"] += " Unapproved inserted teaching."
    elif mutation == "unknown_contract":
        generation["validation_identity"]["generation_contract_hash"] = "unobserved-v23-contract"
        approval["generation_contract_hash"] = "unobserved-v23-contract"
    elif mutation == "approval_identity":
        approval["generation_contract_hash"] = "different-approval-contract"
    elif mutation == "missing_package_hash":
        approval.pop("package_hash")
    else:
        approval.pop("content_hash")
    assert not current_package_approval(details, allow_compatible_read=True)
    assert not current_package_approval(details)


def test_production_v23_compatibility_never_approves_a_relabelled_tutorial():
    from app.services.llm.schemas import plan_detail_step_model

    details = production_v23_approved_details()
    step = details["steps"][0]
    step.update(lesson_format="tutorial_v1", reading_minutes=3, practice_minutes=3, estimate_minutes=6,
                lesson_content=" ".join(step["lesson_content"].split()[:600]))
    canonical = plan_detail_step_model(step).model_validate(step).model_dump(mode="json")
    details["steps"] = [canonical]
    details["lesson_format"] = "tutorial_v1"
    # Even a matching content digest cannot extend the old contract's authority
    # to the new format; tutorials require the current full validation identity.
    details["_generation"]["lesson_validation"]["step_1"]["content_hash"] = digest(canonical)
    assert not current_package_approval(details, allow_compatible_read=True)
    assert not current_package_approval(details)
