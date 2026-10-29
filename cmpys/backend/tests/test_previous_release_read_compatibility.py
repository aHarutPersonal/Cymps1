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


# Production identity at 657463d, before the layered tutorial_v1 prompt contract.
DEPLOYED_657463D_IDENTITY = {
    "review_version": 23,
    "package_version": 1,
    "capability_hash": "1815a97ad0c7246f737c493fbec7b9217c6a5dd6a7d96cacd93c0c34b3afe48f",
    "prompt_hash": "fc899f550b96b760a700da1f5bac50b0118b87b2e615c8106a6b0e4d47ef69eb",
    "generation_contract_hash": "05cbaecec4f940c1e7e2f30bd9f664f51d85412a98bd74312b6dd9eacd100c67",
    "schema_hash": "6c9911659a81cbd8598269be5181940c1bd27d828843305fabac7de560b91a01",
}


def test_tutorials_published_before_the_prompt_rebuild_stay_readable():
    from tests.test_short_tutorial_pipeline import complete_step, outline, short_package

    assert digest(DEPLOYED_657463D_IDENTITY) == "03b5bc34c799d4e71d291cb95909cfb36135e303d4108bc56863e7d986e888c1"
    assert validation_identity() != DEPLOYED_657463D_IDENTITY
    step = complete_step()
    details = {**outline(1), "steps": [step]}
    details["_generation"] = {
        "lesson_package_version": 1, "status": "partial", "ready_step_ids": [step["id"]],
        "validation_identity": copy.deepcopy(DEPLOYED_657463D_IDENTITY),
        "lesson_validation": {step["id"]: {
            **DEPLOYED_657463D_IDENTITY, "content_hash": digest(step),
            "package_hash": digest(short_package().model_dump(mode="json")),
        }},
    }
    assert current_package_approval(details, allow_compatible_read=True)
    assert not current_package_approval(details)
    details["steps"][0]["lesson_content"] += " Unapproved inserted teaching."
    assert not current_package_approval(details, allow_compatible_read=True)


# ---------------------------------------------------------------------------
# Intake sessions started on the 8-key question set (before intake v3)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_legacy_session_keeps_v1_key_set_and_completes(monkeypatch):
    """Review Focus 1: an 8-key intake finishes, reaches results, never 409s."""
    from types import SimpleNamespace
    from unittest.mock import AsyncMock

    from app.api.v1 import sessions
    from app.models.chat import ChatMessage, MessageRole
    from app.models.intake import SessionPhase
    from app.schemas.session import InterviewMessageRequest
    from app.models.user import User
    from app.services.interview_inputs import (
        INTERVIEW_ANSWER_KEYS_V1,
        build_interview_plan_inputs,
        interview_key_set,
        next_interview_answer_key,
        provider_interview_plan_inputs,
    )
    from tests.test_interview_response_ui import (
        _Database,
        _body_events,
        _patch_session,
        _session,
        _thread_awaiting_final_answer,
    )

    thread = _thread_awaiting_final_answer()
    assert interview_key_set(thread.messages) == INTERVIEW_ANSWER_KEYS_V1
    assert next_interview_answer_key(thread.messages) == "learning_habits_support"

    # 1. The last legacy answer closes the interview on the legacy budget.
    session = _session(turn=8)
    db = _Database(thread)

    async def forbidden_stream(*_args, **_kwargs):
        raise AssertionError("Closing a complete intake needs no model call")
        yield  # pragma: no cover

    _patch_session(monkeypatch, session)
    monkeypatch.setattr(sessions, "interview_stream", forbidden_stream)
    response = await sessions.interview(
        session_id=session.id,
        data=InterviewMessageRequest(
            content="Weekly peer feedback has worked for me.",
            question_id=thread.messages[-1].id,
        ),
        db=db,
        current_user=User(id="user-1", email="learner@example.com", password_hash="hash"),
    )
    events = await _body_events(response)
    done = next(event for event in events if event["type"] == "done")
    assert done["phase_transition"] is True
    assert done["max_turns"] == 9
    assert session.phase == SessionPhase.COMPARISON

    # 2. The completed legacy transcript is plan-ready under its own key set.
    answer = next(
        item for item in db.added
        if isinstance(item, ChatMessage) and item.role == MessageRole.USER
    )
    messages = [*thread.messages, answer]
    assert interview_key_set(messages) == INTERVIEW_ANSWER_KEYS_V1
    baseline = build_interview_plan_inputs(
        messages, session_goal="Build a useful product", require_diagnostics=True
    )
    assert baseline["interview_key_set"] == "v1"
    assert baseline["missing_keys"] == []
    assert baseline["answered_keys"] == list(INTERVIEW_ANSWER_KEYS_V1)
    assert baseline["weekly_capacity_hours"] == 8
    assert baseline["weekly_capacity_minutes"] == 480
    provider = provider_interview_plan_inputs(baseline)
    assert provider["constraints_resources"]["answer"].startswith("A laptop")
    assert provider["learning_habits_support"] == {
        "answer": "Weekly peer feedback has worked for me."
    }
    assert "work_sample" not in provider

    # A stored pre-v3 baseline (no key-set marker) still projects its 8 keys.
    stored = {key: value for key, value in baseline.items() if key != "interview_key_set"}
    assert provider_interview_plan_inputs(stored)["learning_habits_support"] == {
        "answer": "Weekly peer feedback has worked for me."
    }

    # 3. Results generation accepts the legacy session (no 409
    #    interview_profile_incomplete) and confirms its weekly hours.
    session.phase = SessionPhase.COMPLETED
    session.idol_id = "idol-1"
    session.comparison_output = "Cached comparison"
    session.blueprint_output = "Cached blueprint"
    session.comparison_scores_json = {
        "version": 2,
        "methodology": "like_for_like_evidence",
        "overall": {"status": "insufficient_evidence"},
        "dimensions": [],
        "milestones": [],
    }
    thread.messages = messages
    results_db = AsyncMock()
    results_db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: thread)
    captured = {}

    async def capture_job(db, *, session, user_id, weekly_minutes, focus=None):
        captured["weekly_minutes"] = weekly_minutes
        return SimpleNamespace(id="job-1", status="completed", step="done",
                               weekly_hours=weekly_minutes // 60, weekly_minutes=weekly_minutes)

    async def capture_profile(db, *, session, user_id, plan_inputs):
        captured["plan_inputs"] = plan_inputs

    monkeypatch.setattr(
        sessions,
        "catalog_mentor_facts",
        AsyncMock(return_value={"origin": "published_catalog", "facts": []}),
    )
    monkeypatch.setattr(sessions, "_get_or_create_session_plan_job", capture_job)
    monkeypatch.setattr(sessions, "_sync_user_profile_from_interview", capture_profile)

    results = await sessions.generate_results(
        "session-1", results_db, SimpleNamespace(id="user-1")
    )
    body = "".join([chunk async for chunk in results.body_iterator])
    assert "interview_profile_incomplete" not in body
    assert '"type": "done"' in body
    # The legacy 3-60 whole-hour answer is stored as minutes (Task A4).
    assert captured["weekly_minutes"] == 480
    assert captured["plan_inputs"]["missing_keys"] == []
    assert captured["plan_inputs"]["interview_key_set"] == "v1"

    # Legacy sessions that are mid-intake keep the legacy weekly control.
    legacy_weekly = sessions._response_input_for_answer_key(
        None, "weekly_hours", key_set=interview_key_set(messages)
    )
    assert (legacy_weekly.min_value, legacy_weekly.max_value) == (3, 60)
