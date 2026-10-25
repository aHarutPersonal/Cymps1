"""Focused model invariants for the evidence-based curriculum catalog."""

from datetime import datetime, timezone
from decimal import Decimal

import pytest
from sqlalchemy import CheckConstraint, UniqueConstraint, inspect
from sqlalchemy.orm import attributes

from app.models import Base
from app.models.curriculum import (
    AssignmentStatus,
    CanonicalModule,
    CanonicalModuleVersion,
    CurriculumGenerationJob,
    CurriculumSkill,
    CurriculumSkillStatus,
    EvidenceVerificationStatus,
    GenerationStage,
    GenerationState,
    LearnerMasteryStatus,
    LearnerSkillState,
    LearningTechniqueVersion,
    MentorClaimType,
    MentorEvidenceClaim,
    ModuleQualityReport,
    ModuleSession,
    PersonalizedLessonStatus,
    PersonalizedLessonVersion,
    PlanLessonAssignment,
    PYTHON_STRIP_CHARACTERS_SQL,
    SkillLevel,
    VersionStatus,
    _prevent_canonical_version_delete,
    _protect_finalized_mentor_claim_delete,
    _protect_published_canonical_content,
    _protect_published_module_session,
    _protect_published_technique_content,
    _protect_quality_report,
    _protect_ready_personalized_lesson,
    _protect_ready_personalized_lesson_delete,
    _protect_terminal_assignment_status,
    _protect_verified_mentor_claim,
)


HASH_A = "a" * 64
HASH_B = "b" * 64
AUDIT_AT = datetime(2026, 1, 1, tzinfo=timezone.utc)
LATER_AT = datetime(2026, 1, 2, tzinfo=timezone.utc)


def _mark_committed(instance) -> None:
    """Give an unflushed model the attribute history of a persisted row."""

    state = inspect(instance)
    for attribute in state.mapper.column_attrs:
        attributes.set_committed_value(
            instance,
            attribute.key,
            getattr(instance, attribute.key),
        )


def _canonical_version(*, status: VersionStatus = VersionStatus.DRAFT):
    return CanonicalModuleVersion(
        module_id="11111111-1111-1111-1111-111111111111",
        version_number=1,
        status=status,
        content_json={"title": "Margin of safety"},
        source_manifest_json={"sources": ["source-1"]},
        technique_plan_json={"bindings": ["retrieval-practice-v1"]},
        content_hash=HASH_A,
        source_hash=HASH_B,
        retrieval_metadata_json={},
        retrieval_metadata_hash=HASH_A,
        estimated_minutes=55,
        prompt_version="module-v1",
        model_name="quality-model",
        published_at=(
            AUDIT_AT
            if status in {VersionStatus.PUBLISHED, VersionStatus.REVOKED}
            else None
        ),
        revoked_at=AUDIT_AT if status is VersionStatus.REVOKED else None,
        revocation_reason=(
            "Source was withdrawn" if status is VersionStatus.REVOKED else None
        ),
    )


def _technique_version(*, status: VersionStatus = VersionStatus.DRAFT):
    from app.models.curriculum import EvidenceLevel

    return LearningTechniqueVersion(
        technique_key="retrieval_practice",
        version_number=1,
        title="Retrieval practice",
        summary="Recall before reviewing.",
        evidence_level=EvidenceLevel.STRONG,
        implementation_contract_json={"steps": ["recall", "check", "revise"]},
        source_manifest_json={"sources": ["source-1"]},
        content_hash=HASH_A,
        source_hash=HASH_B,
        status=status,
        published_at=(
            AUDIT_AT
            if status in {VersionStatus.PUBLISHED, VersionStatus.REVOKED}
            else None
        ),
        revoked_at=AUDIT_AT if status is VersionStatus.REVOKED else None,
        revocation_reason=(
            "Evidence was superseded" if status is VersionStatus.REVOKED else None
        ),
    )


def _personalized_version(
    *, status: PersonalizedLessonStatus = PersonalizedLessonStatus.QUEUED
):
    return PersonalizedLessonVersion(
        user_id="11111111-1111-1111-1111-111111111111",
        module_session_id="22222222-2222-2222-2222-222222222222",
        module_version_id="33333333-3333-3333-3333-333333333333",
        version_number=1,
        status=status,
        learner_state_snapshot_json={"level": "beginner"},
        learner_state_hash=HASH_A,
        mentor_evidence_snapshot_json={"claim_ids": []},
        mentor_evidence_hash=HASH_B,
        personalization_brief_json={"goal": "value a real company"},
        input_hash="c" * 64,
        content_json={"why_now": "Your next decision requires this."},
        content_hash="d" * 64,
        estimated_minutes=55,
        prompt_version="personal-v1",
        model_name="quality-model",
        ready_at=(
            AUDIT_AT
            if status
            in {PersonalizedLessonStatus.READY, PersonalizedLessonStatus.REVOKED}
            else None
        ),
        revoked_at=AUDIT_AT if status is PersonalizedLessonStatus.REVOKED else None,
        revocation_reason=(
            "Pinned evidence was revoked"
            if status is PersonalizedLessonStatus.REVOKED
            else None
        ),
    )


def _mentor_claim(
    *,
    status: EvidenceVerificationStatus = EvidenceVerificationStatus.PENDING,
):
    return MentorEvidenceClaim(
        idol_id="11111111-1111-1111-1111-111111111111",
        claim_type=MentorClaimType.RECOMMENDED_BOOK,
        claim_text="The Intelligent Investor is a recommended foundation.",
        normalized_hash=HASH_A,
        source_title="Annual meeting transcript",
        source_url="https://example.test/source",
        evidence_excerpt="Read the classic value-investing text.",
        source_hash=HASH_B,
        confidence=0.95,
        verification_status=status,
        verified_at=(
            AUDIT_AT
            if status
            in {
                EvidenceVerificationStatus.VERIFIED,
                EvidenceVerificationStatus.REVOKED,
            }
            else None
        ),
        revoked_at=AUDIT_AT if status is EvidenceVerificationStatus.REVOKED else None,
        revocation_reason=(
            "Source was withdrawn"
            if status is EvidenceVerificationStatus.REVOKED
            else None
        ),
    )


def test_curriculum_enums_and_python_defaults_are_stable():
    assert [level.value for level in SkillLevel] == [
        "unknown",
        "beginner",
        "intermediate",
        "advanced",
    ]
    assert [state.value for state in GenerationState] == [
        "queued",
        "running",
        "retry_wait",
        "completed",
        "failed",
        "flagged",
        "cancelled",
    ]
    assert GenerationStage.SOURCE_RESEARCH.value == "source_research"

    skill = CurriculumSkill(
        key="investing.margin_of_safety",
        domain="investing",
        name="Margin of safety",
        description="Estimate downside before committing capital.",
        skill_type="procedural",
    )
    assert skill.status is CurriculumSkillStatus.DRAFT
    assert skill.taxonomy_version == 1
    assert skill.tags_json == []

    other_skill = CurriculumSkill(
        key="investing.valuation",
        domain="investing",
        name="Valuation",
        description="Estimate a defensible value range.",
        skill_type="procedural",
    )
    skill.tags_json.append("finance")
    assert other_skill.tags_json == []

    job = CurriculumGenerationJob(
        skill_id="11111111-1111-1111-1111-111111111111",
        input_hash=HASH_A,
        input_json={"skill": skill.key},
        pipeline_version="curriculum-pipeline-v1",
    )
    assert job.stage is GenerationStage.TAXONOMY
    assert job.state is GenerationState.QUEUED
    assert job.max_attempts == 3
    assert job.max_repairs == 2
    assert job.budget_limit_usd == Decimal("0")
    assert job.cost_usd == Decimal("0")
    assert job.checkpoints_json == {}

    state = LearnerSkillState(
        user_id="11111111-1111-1111-1111-111111111111",
        skill_id="22222222-2222-2222-2222-222222222222",
    )
    assert state.current_level is SkillLevel.UNKNOWN
    assert state.mastery_status is LearnerMasteryStatus.UNASSESSED

    assignment = PlanLessonAssignment(
        plan_id="11111111-1111-1111-1111-111111111111",
        module_session_id="22222222-2222-2222-2222-222222222222",
        week_number=1,
        position=1,
        allocated_minutes=55,
        comparison_gap_json={"skill_id": "margin-of-safety"},
        match_reason="Exact compatible outcome.",
    )
    assert assignment.status is AssignmentStatus.SCHEDULED


def test_curriculum_tables_have_hash_provenance_pinning_and_retrieval_shape():
    expected_tables = {
        "curriculum_skills",
        "curriculum_skill_prerequisites",
        "learning_technique_versions",
        "canonical_modules",
        "canonical_module_versions",
        "module_sessions",
        "curriculum_generation_jobs",
        "module_quality_reports",
        "mentor_evidence_claims",
        "mentor_evidence_claim_skills",
        "learner_skill_states",
        "personalized_lesson_versions",
        "plan_lesson_assignments",
    }
    assert expected_tables.issubset(Base.metadata.tables)

    version_columns = CanonicalModuleVersion.__table__.columns
    assert {
        "content_json",
        "source_manifest_json",
        "technique_plan_json",
        "content_hash",
        "source_hash",
        "embedding",
        "retrieval_metadata_json",
        "retrieval_metadata_hash",
        "published_at",
        "revoked_at",
        "revocation_reason",
    }.issubset(version_columns.keys())
    assert version_columns.embedding.type.dim == 1024

    job_columns = CurriculumGenerationJob.__table__.columns
    assert {
        "stage",
        "state",
        "lease_owner",
        "lease_expires_at",
        "input_hash",
        "checkpoints_json",
        "budget_limit_usd",
        "estimated_cost_usd",
        "cost_usd",
        "cached_input_tokens",
    }.issubset(job_columns.keys())
    assert not job_columns.budget_limit_usd.nullable

    current_fk = next(
        constraint
        for constraint in CanonicalModule.__table__.foreign_key_constraints
        if constraint.name == "fk_canonical_modules_current_published_version"
    )
    assert [element.parent.name for element in current_fk.elements] == [
        "current_published_version_id",
        "id",
    ]
    assert [element.column.name for element in current_fk.elements] == [
        "id",
        "module_id",
    ]

    supersedes_fk = next(
        constraint
        for constraint in CanonicalModuleVersion.__table__.foreign_key_constraints
        if constraint.name == "fk_canonical_module_versions_supersedes_same_module"
    )
    assert [element.parent.name for element in supersedes_fk.elements] == [
        "supersedes_version_id",
        "module_id",
    ]
    assert [element.column.name for element in supersedes_fk.elements] == [
        "id",
        "module_id",
    ]

    assignment_checks = {
        constraint.name
        for constraint in PlanLessonAssignment.__table__.constraints
        if isinstance(constraint, CheckConstraint)
    }
    assert "ck_plan_lesson_assignments_personalized_visibility" in assignment_checks
    assert "ck_plan_lesson_assignments_available_at" in assignment_checks
    personalized_session_fk = next(
        constraint
        for constraint in PlanLessonAssignment.__table__.foreign_key_constraints
        if constraint.name == "fk_plan_lesson_assignments_personalized_session"
    )
    assert [element.parent.name for element in personalized_session_fk.elements] == [
        "personalized_lesson_version_id",
        "module_session_id",
    ]
    assert [element.column.name for element in personalized_session_fk.elements] == [
        "id",
        "module_session_id",
    ]
    assert personalized_session_fk.ondelete == "CASCADE"

    assignment_unique = next(
        index
        for index in PlanLessonAssignment.__table__.indexes
        if index.name == "uq_plan_lesson_assignments_plan_session"
    )
    assert assignment_unique.unique
    assert str(assignment_unique.dialect_options["postgresql"]["where"]) == (
        "status NOT IN ('skipped', 'replaced')"
    )

    mentor_snapshot_index = next(
        index
        for index in PersonalizedLessonVersion.__table__.indexes
        if index.name == "ix_personalized_lessons_ready_mentor_evidence"
    )
    assert mentor_snapshot_index.dialect_options["postgresql"]["using"] == "gin"
    assert mentor_snapshot_index.dialect_options["postgresql"]["ops"] == {
        "content_json": "jsonb_path_ops"
    }
    assert str(mentor_snapshot_index.dialect_options["postgresql"]["where"]) == (
        "status = 'ready' AND revoked_at IS NULL"
    )

    module_uniques = {
        constraint.name
        for constraint in CanonicalModule.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    assert "uq_canonical_modules_compatibility_key" not in module_uniques

    mentor_evidence_unique = next(
        constraint
        for constraint in MentorEvidenceClaim.__table__.constraints
        if constraint.name == "uq_mentor_evidence_claims_idol_claim_source"
    )
    assert [column.name for column in mentor_evidence_unique.columns] == [
        "idol_id",
        "normalized_hash",
        "source_hash",
    ]


def test_lifecycle_audit_shape_constraints_cover_inserted_terminal_rows():
    assert r"\000B" in PYTHON_STRIP_CHARACTERS_SQL
    assert r"\00A0" in PYTHON_STRIP_CHARACTERS_SQL
    assert r"\3000" in PYTHON_STRIP_CHARACTERS_SQL
    assert r"\v" not in PYTHON_STRIP_CHARACTERS_SQL

    expected = {
        LearningTechniqueVersion: (
            "ck_learning_technique_versions_audit_shape",
            ("published_at IS NULL", "published_at IS NOT NULL", "btrim"),
        ),
        CanonicalModuleVersion: (
            "ck_canonical_module_versions_audit_shape",
            ("published_at IS NULL", "published_at IS NOT NULL", "btrim"),
        ),
        MentorEvidenceClaim: (
            "ck_mentor_evidence_claims_audit_shape",
            ("verified_at IS NULL", "verified_at IS NOT NULL", "btrim"),
        ),
        PersonalizedLessonVersion: (
            "ck_personalized_lessons_audit_shape",
            (
                "ready_at IS NULL",
                "ready_at IS NOT NULL",
                "content_json IS NOT NULL",
                "content_hash IS NOT NULL",
                "btrim",
            ),
        ),
    }

    for model, (constraint_name, fragments) in expected.items():
        constraint = next(
            candidate
            for candidate in model.__table__.constraints
            if candidate.name == constraint_name
        )
        rendered = str(constraint.sqltext)
        for fragment in fragments:
            assert fragment in rendered
        assert "revoked_at IS NULL" in rendered
        assert "revocation_reason IS NULL" in rendered


def test_terminal_plan_lesson_assignment_status_is_immutable():
    def assignment(status: AssignmentStatus) -> PlanLessonAssignment:
        return PlanLessonAssignment(
            plan_id="11111111-1111-1111-1111-111111111111",
            plan_item_id="22222222-2222-2222-2222-222222222222",
            module_session_id="33333333-3333-3333-3333-333333333333",
            week_number=1,
            position=1,
            allocated_minutes=55,
            status=status,
            comparison_gap_json={"skill_id": "margin-of-safety"},
            match_reason="Exact compatible outcome.",
        )

    skipped = assignment(AssignmentStatus.SKIPPED)
    _mark_committed(skipped)
    skipped.status = AssignmentStatus.SCHEDULED
    with pytest.raises(ValueError, match="status is immutable"):
        _protect_terminal_assignment_status(None, None, skipped)

    replaced = assignment(AssignmentStatus.REPLACED)
    _mark_committed(replaced)
    replaced.status = AssignmentStatus.AVAILABLE
    with pytest.raises(ValueError, match="status is immutable"):
        _protect_terminal_assignment_status(None, None, replaced)

    # The plan-item FK owns this nullable pointer. Terminal history may still
    # receive its ON DELETE SET NULL action because status itself is unchanged.
    skipped = assignment(AssignmentStatus.SKIPPED)
    _mark_committed(skipped)
    skipped.plan_item_id = None
    _protect_terminal_assignment_status(None, None, skipped)


def test_published_canonical_content_is_immutable_but_embedding_can_be_backfilled():
    version = _canonical_version(status=VersionStatus.PUBLISHED)
    _mark_committed(version)
    version.content_json = {"title": "silently changed"}
    with pytest.raises(ValueError, match="append-only"):
        _protect_published_canonical_content(None, None, version)

    version = _canonical_version(status=VersionStatus.PUBLISHED)
    _mark_committed(version)
    version.embedding = [0.0] * 1024
    _protect_published_canonical_content(None, None, version)

    version = _canonical_version(status=VersionStatus.PUBLISHED)
    _mark_committed(version)
    version.retrieval_metadata_json = {"skill_key": "changed"}
    version.retrieval_metadata_hash = HASH_B
    with pytest.raises(ValueError, match="append-only"):
        _protect_published_canonical_content(None, None, version)

    version = _canonical_version(status=VersionStatus.PUBLISHED)
    _mark_committed(version)
    version.quality_score = 0.99
    with pytest.raises(ValueError, match="append-only"):
        _protect_published_canonical_content(None, None, version)

    draft = _canonical_version(status=VersionStatus.DRAFT)
    _mark_committed(draft)
    draft.content_json = {"title": "review repair"}
    _protect_published_canonical_content(None, None, draft)


def test_canonical_version_lifecycle_and_deletion_are_guarded():
    version = _canonical_version(status=VersionStatus.PUBLISHED)
    _mark_committed(version)
    version.status = VersionStatus.IN_REVIEW
    with pytest.raises(ValueError, match="Invalid canonical version transition"):
        _protect_published_canonical_content(None, None, version)

    version = _canonical_version(status=VersionStatus.PUBLISHED)
    _mark_committed(version)
    version.status = VersionStatus.REVOKED
    version.revoked_at = LATER_AT
    version.revocation_reason = "Source was withdrawn"
    _protect_published_canonical_content(None, None, version)

    with pytest.raises(ValueError, match="cannot be deleted"):
        _prevent_canonical_version_delete(None, None, version)


def test_published_techniques_sessions_and_ready_personalized_lessons_are_immutable():
    technique = _technique_version(status=VersionStatus.PUBLISHED)
    _mark_committed(technique)
    technique.implementation_contract_json = {"steps": ["skip practice"]}
    with pytest.raises(ValueError, match="append-only"):
        _protect_published_technique_content(None, None, technique)

    parent = _canonical_version(status=VersionStatus.PUBLISHED)
    session = ModuleSession(
        module_version_id="33333333-3333-3333-3333-333333333333",
        position=1,
        title="Apply the method",
        learning_objective="Produce a valuation range.",
        estimated_minutes=55,
        content_json={"explanation": "..."},
        assessment_json={"rubric": {}},
        artifact_spec_json={"type": "valuation"},
        technique_plan_json={"bindings": []},
        content_hash=HASH_A,
    )
    session.module_version = parent
    with pytest.raises(ValueError, match="immutable"):
        _protect_published_module_session(None, None, session)

    lesson = _personalized_version(status=PersonalizedLessonStatus.READY)
    _mark_committed(lesson)
    lesson.content_json = {"generic": True}
    with pytest.raises(ValueError, match="immutable"):
        _protect_ready_personalized_lesson(None, None, lesson)
    with pytest.raises(ValueError, match="revoke"):
        _protect_ready_personalized_lesson_delete(None, None, lesson)


def test_personalized_lesson_rejects_invalid_ready_transition():
    lesson = _personalized_version(status=PersonalizedLessonStatus.READY)
    _mark_committed(lesson)
    lesson.status = PersonalizedLessonStatus.GENERATING
    with pytest.raises(ValueError, match="Invalid personalized lesson transition"):
        _protect_ready_personalized_lesson(None, None, lesson)


def test_lifecycle_audit_fields_are_set_once_on_exact_transitions():
    canonical = _canonical_version(status=VersionStatus.DRAFT)
    _mark_committed(canonical)
    canonical.status = VersionStatus.PUBLISHED
    canonical.published_at = AUDIT_AT
    _protect_published_canonical_content(None, None, canonical)
    _mark_committed(canonical)
    canonical.published_at = LATER_AT
    with pytest.raises(ValueError, match="lifecycle audit fields are immutable"):
        _protect_published_canonical_content(None, None, canonical)

    technique = _technique_version(status=VersionStatus.PUBLISHED)
    _mark_committed(technique)
    technique.reviewed_at = LATER_AT
    with pytest.raises(ValueError, match="append-only"):
        _protect_published_technique_content(None, None, technique)

    technique = _technique_version(status=VersionStatus.PUBLISHED)
    _mark_committed(technique)
    technique.status = VersionStatus.REVOKED
    technique.revoked_at = LATER_AT
    technique.revocation_reason = "Evidence was superseded"
    _protect_published_technique_content(None, None, technique)
    _mark_committed(technique)
    technique.revocation_reason = "Rewritten audit history"
    with pytest.raises(ValueError, match="lifecycle audit fields are immutable"):
        _protect_published_technique_content(None, None, technique)

    lesson = _personalized_version(status=PersonalizedLessonStatus.READY)
    _mark_committed(lesson)
    lesson.ready_at = LATER_AT
    with pytest.raises(ValueError, match="lifecycle audit fields are immutable"):
        _protect_ready_personalized_lesson(None, None, lesson)

    claim = _mentor_claim(status=EvidenceVerificationStatus.VERIFIED)
    _mark_committed(claim)
    claim.verified_at = LATER_AT
    with pytest.raises(ValueError, match="lifecycle audit fields are immutable"):
        _protect_verified_mentor_claim(None, None, claim)


def test_learner_state_deletion_delegates_set_null_to_database():
    relationship = inspect(LearnerSkillState).relationships.personalized_lessons

    assert relationship.passive_deletes == "all"


def test_quality_reports_are_append_only():
    report = ModuleQualityReport(
        module_version_id="11111111-1111-1111-1111-111111111111",
        review_type="factual",
        verdict="passed",
        reviewed_content_hash=HASH_A,
    )
    with pytest.raises(ValueError, match="append-only"):
        _protect_quality_report(None, None, report)


def test_generation_job_deletion_delegates_report_unlinking_to_database():
    relationship = inspect(CurriculumGenerationJob).relationships.quality_reports

    assert relationship.passive_deletes == "all"


def test_finalized_mentor_evidence_is_immutable_and_has_explicit_lifecycle():
    claim = _mentor_claim(status=EvidenceVerificationStatus.VERIFIED)
    _mark_committed(claim)
    claim.claim_text = "Silently rewritten evidence"
    with pytest.raises(ValueError, match="immutable"):
        _protect_verified_mentor_claim(None, None, claim)
    with pytest.raises(ValueError, match="append-only"):
        _protect_finalized_mentor_claim_delete(None, None, claim)

    claim = _mentor_claim(status=EvidenceVerificationStatus.VERIFIED)
    _mark_committed(claim)
    claim.verification_status = EvidenceVerificationStatus.REVOKED
    claim.revoked_at = LATER_AT
    claim.revocation_reason = "Source was withdrawn"
    _protect_verified_mentor_claim(None, None, claim)

    claim = _mentor_claim(status=EvidenceVerificationStatus.REJECTED)
    _mark_committed(claim)
    claim.verification_status = EvidenceVerificationStatus.VERIFIED
    claim.verified_at = LATER_AT
    with pytest.raises(ValueError, match="Invalid mentor evidence transition"):
        _protect_verified_mentor_claim(None, None, claim)
