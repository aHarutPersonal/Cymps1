"""Structured artifact validation for generated curriculum content."""

from copy import deepcopy
from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.models.curriculum import MentorClaimType
from app.schemas.curriculum import (
    CanonicalModuleArtifact,
    CanonicalModuleVersionCreate,
    MentorEvidenceClaimCreate,
    PersonalizedLessonArtifact,
    PersonalizedLessonVersionRead,
    SourceManifest,
    TechniquePlan,
)
from app.services.curriculum.schemas import (
    CanonicalModuleDraft,
    ResearchManifest,
    TechniquePlan as InternalTechniquePlan,
)


HASH_A = "a" * 64


def _source_manifest() -> dict:
    return {
        "research_question": "Which methods best teach a novice to build a valuation range?",
        "sources": [
            {
                "source_id": "src_guide",
                "title": "Evidence-based practice guide",
                "url": "https://ies.ed.gov/ncee/wwc/PracticeGuide/1",
                "source_type": "practice_guide",
                "evidence_tier": "strong",
                "rights_status": "citation_only",
                "publisher": "Institute of Education Sciences",
                "sanitized_support_text": (
                    "Use complete worked examples before independent problem solving."
                ),
                "source_text_kind": "provider_grounded_support",
                "classification_provenance": "deterministic_url_rule",
                "content_hash": HASH_A,
            },
            {
                "source_id": "src_research",
                "title": "Retrieval practice primary research",
                "url": "https://doi.org/10.1126/science.1152408",
                "source_type": "primary_research",
                "evidence_tier": "strong",
                "rights_status": "citation_only",
                "sanitized_support_text": (
                    "An attempt to retrieve is followed by corrective feedback."
                ),
                "source_text_kind": "provider_grounded_support",
                "classification_provenance": "deterministic_url_rule",
                "content_hash": "b" * 64,
            },
        ],
        "claims": [
            {
                "claim_id": "claim_worked",
                "statement": "Novices benefit from a fully reasoned worked example.",
                "source_ids": ["src_guide"],
                "confidence": 0.9,
            },
            {
                "claim_id": "claim_retrieval",
                "statement": "Retrieval should be attempted before corrective feedback.",
                "source_ids": ["src_research"],
                "confidence": 0.9,
            },
        ],
        "limitations": ["Transfer to investing must be evaluated in the pilot."],
    }


def _technique_plan() -> dict:
    return {
        "learning_outcome": "Build and defend a downside-aware valuation range.",
        "learner_level": "beginner",
        "applications": [
            {
                "technique_id": "worked_examples",
                "rationale": "The learner is new to this multi-step analytical procedure.",
                "implementation_steps": [
                    "Show a complete solution with reasoning.",
                    "Connect every step to the general valuation principle.",
                ],
                "implementation_block_ids": ["block_example"],
                "evidence_source_ids": ["src_guide"],
            },
            {
                "technique_id": "active_application",
                "rationale": "The target performance is a defensible real-world artifact.",
                "implementation_steps": [
                    "Require an independent valuation range for a real company."
                ],
                "implementation_block_ids": ["block_practice"],
                "evidence_source_ids": ["src_research"],
            },
        ],
        "assessment_strategy": (
            "Evaluate the independent valuation against explicit assumptions, "
            "downside tests, and a revision rubric."
        ),
    }


def _module_artifact() -> dict:
    blocks = []
    block_specs = (
        ("block_explain", "explanation", "Explain uncertainty"),
        ("block_example", "worked_example", "Work a valuation example"),
        ("block_recall", "retrieval", "Recall the decision steps"),
        ("block_practice", "guided_practice", "Build a real range"),
        ("block_revision", "revision", "Revise against the rubric"),
    )
    for block_id, block_type, title in block_specs:
        blocks.append(
            {
                "block_id": block_id,
                "block_type": block_type,
                "title": title,
                "minutes": 10,
                "content_markdown": (
                    "This block explains the reasoning, asks for an observable action, "
                    "and connects the result to a general principle."
                ),
                "learner_instructions": ["Complete the stated action."],
                "success_criteria": ["The reasoning is explicit and testable."],
                "source_ids": ["src_guide"],
                "technique_ids": ["active_application"],
            }
        )
    return {
        "skill_key": "investing.margin_of_safety",
        "domain": "investing",
        "level": "beginner",
        "locale": "en",
        "title": "Use a margin of safety",
        "summary": "Build a downside-aware valuation range and defend every assumption.",
        "learning_outcome": "Produce and defend a downside-aware value range.",
        "prerequisites": ["investing.intrinsic_value"],
        "artifact_type": "valuation_range",
        "blocks": blocks,
        "artifact_description": "A valuation range with assumptions and downside tests.",
        "rubric": [
            {
                "criterion": "Assumptions",
                "evidence_required": "Every material assumption is visible.",
                "passing_standard": "A reviewer can reproduce the range.",
            },
            {
                "criterion": "Downside",
                "evidence_required": "At least two downside scenarios are tested.",
                "passing_standard": "The decision threshold responds to uncertainty.",
            },
        ],
        "estimated_minutes": 50,
    }


def test_public_persistence_contracts_are_exact_internal_artifact_aliases():
    assert CanonicalModuleArtifact is CanonicalModuleDraft
    assert SourceManifest is ResearchManifest
    assert TechniquePlan is InternalTechniquePlan

    create = CanonicalModuleVersionCreate.model_validate(
        {
            "module_id": "module-1",
            "version_number": 1,
            "content": _module_artifact(),
            "source_manifest": _source_manifest(),
            "technique_plan": _technique_plan(),
            "content_hash": HASH_A,
            "source_hash": "b" * 64,
            "retrieval_metadata": {"skill_key": "investing.intrinsic_value"},
            "retrieval_metadata_hash": "c" * 64,
            "estimated_minutes": 50,
            "prompt_version": "curriculum-prompts-v1",
            "model_name": "quality-model",
        }
    )
    assert create.content.blocks[0].block_id == "block_explain"
    assert create.source_manifest.claims[0].source_ids == ["src_guide"]
    assert create.technique_plan.applications[0].technique_id.value == "worked_examples"


def test_canonical_artifact_rejects_duplicate_blocks_and_inconsistent_minutes():
    artifact = CanonicalModuleArtifact.model_validate(_module_artifact())
    assert artifact.estimated_minutes == 50

    invalid = _module_artifact()
    invalid["blocks"][1]["block_id"] = invalid["blocks"][0]["block_id"]
    with pytest.raises(ValidationError, match="block_id values must be unique"):
        CanonicalModuleArtifact.model_validate(invalid)

    invalid = _module_artifact()
    invalid["estimated_minutes"] = 100
    with pytest.raises(ValidationError, match="block-time sum"):
        CanonicalModuleArtifact.model_validate(invalid)

    invalid = _module_artifact()
    invalid["level"] = "unknown"
    with pytest.raises(ValidationError, match="literal_error"):
        CanonicalModuleArtifact.model_validate(invalid)


def test_source_manifest_rejects_duplicate_ids_and_missing_source_bindings():
    duplicate_source = _source_manifest()
    duplicate_source["sources"].append(deepcopy(duplicate_source["sources"][0]))
    with pytest.raises(ValidationError, match="source_id values must be unique"):
        SourceManifest.model_validate(duplicate_source)

    missing_source = _source_manifest()
    missing_source["claims"][0]["source_ids"] = ["src_missing"]
    with pytest.raises(ValidationError, match="claims reference missing sources"):
        SourceManifest.model_validate(missing_source)


def test_mentor_claim_requires_sha256_and_concrete_source_provenance():
    base = {
        "idol_id": "idol-1",
        "claim_type": MentorClaimType.RECOMMENDED_BOOK,
        "claim_text": "The mentor recommended this book.",
        "normalized_hash": HASH_A,
        "evidence_excerpt": "The primary source names the book.",
        "source_hash": "b" * 64,
        "confidence": 0.9,
    }
    with pytest.raises(ValidationError, match="source_chunk_id or source_url"):
        MentorEvidenceClaimCreate.model_validate(base)

    claim = MentorEvidenceClaimCreate.model_validate(
        {**base, "source_url": "https://example.com/primary-source"}
    )
    assert claim.claim_type is MentorClaimType.RECOMMENDED_BOOK

    with pytest.raises(ValidationError, match="string_pattern_mismatch"):
        MentorEvidenceClaimCreate.model_validate(
            {
                **base,
                "normalized_hash": "not-a-sha256",
                "source_url": "https://example.com/primary-source",
            }
        )


def test_personalized_reader_artifact_limits_mentor_callouts_to_sourced_claims():
    payload = {
        "canonical_module_version_id": "version-1",
        "module_session_id": "session-1",
        "title": "Your downside-aware valuation",
        "why_now": "This directly supports the company you are evaluating.",
        "adapted_explanation_markdown": "A" * 120,
        "worked_example_markdown": "B" * 120,
        "guided_practice_markdown": "C" * 80,
        "artifact_spec": {"type": "valuation_range"},
        "assessment": {
            "instructions": "Defend the range.",
            "success_criteria": ["Assumptions are explicit"],
            "rubric": {"assumptions": "explicit"},
        },
        "personalized_rubric": {"project": "the learner's company"},
        "mentor_callouts": [
            {
                "evidence_claim_id": "claim-1",
                "connection_to_skill": "The claim demonstrates conservative reasoning.",
                "practical_application": "Stress-test the learner's assumptions.",
            }
        ],
        "estimated_minutes": 55,
    }
    artifact = PersonalizedLessonArtifact.model_validate(payload)
    assert artifact.mentor_callouts[0].evidence_claim_id == "claim-1"

    payload["mentor_callouts"] *= 4
    with pytest.raises(ValidationError, match="too_long"):
        PersonalizedLessonArtifact.model_validate(payload)


def test_personalized_version_read_matches_the_persisted_composer_payload():
    persisted = {
        "step": {
            "id": "step_1",
            "title": "Apply the method to your company",
            "lesson_content": "A deeply personalized lesson body.",
            "estimate_minutes": 55,
        },
        "materials": [{"title": "Primary source", "url": "https://example.com"}],
        "catalog": {"module_version_id": "version-1", "session_id": "session-1"},
        "personalization": {
            "status": "ready",
            "mentor_evidence_ids": ["claim-1"],
        },
        "retrieval_follow_ups": [{"day_offset": 7, "prompt": "Defend the choice."}],
    }
    row = SimpleNamespace(
        id="personal-1",
        user_id="user-1",
        module_session_id="session-1",
        module_version_id="version-1",
        version_number=1,
        status="ready",
        content_json=persisted,
        content_hash=HASH_A,
        estimated_minutes=55,
        ready_at=datetime.now(UTC),
        last_error=None,
        revoked_at=None,
        revocation_reason=None,
        created_at=datetime.now(UTC),
    )
    response = PersonalizedLessonVersionRead.model_validate(row)
    assert response.content is not None
    assert response.content.step["id"] == "step_1"
    assert response.content.retrieval_follow_ups[0]["day_offset"] == 7
