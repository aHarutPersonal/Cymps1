"""Structured artifact and API schemas for the curriculum factory."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

from pydantic import AliasChoices, BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel

from app.models.curriculum import (
    AssignmentStatus,
    CurriculumSkillStatus,
    EvidenceLevel,
    EvidenceVerificationStatus,
    GenerationStage,
    GenerationState,
    LearnerMasteryStatus,
    MentorClaimType,
    PersonalizedLessonStatus,
    QualityReviewType,
    QualityVerdict,
    SkillLevel,
    VersionStatus,
)
from app.services.curriculum.schemas import (
    CanonicalModuleDraft as CanonicalModuleArtifact,
    ResearchManifest as SourceManifest,
    TechniquePlan,
)


SHA256_PATTERN = r"^[0-9a-f]{64}$"


class CurriculumSchema(BaseModel):
    """Shared casing and ORM conversion behavior for public curriculum schemas."""

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        from_attributes=True,
        extra="forbid",
    )


class AssessmentArtifact(CurriculumSchema):
    instructions: str = Field(min_length=1)
    success_criteria: list[str] = Field(min_length=1)
    rubric: dict[str, Any]
    retrieval_prompts: list[str] = Field(default_factory=list)
    revision_required: bool = True


class LearnerLessonBrief(CurriculumSchema):
    """Frozen learner/mentor inputs used to compose a personalized reader lesson."""

    learner_skill_state_id: str | None = None
    learner_state_hash: str = Field(pattern=SHA256_PATTERN)
    goal: str = Field(min_length=1)
    real_project: str = Field(min_length=1)
    weekly_minutes: int = Field(ge=30, le=10080)
    current_level: SkillLevel
    strengths: list[str] = Field(default_factory=list)
    gaps: list[str] = Field(min_length=1)
    misconceptions: list[str] = Field(default_factory=list)
    prior_outcomes: list[str] = Field(default_factory=list)
    preferences: list[str] = Field(default_factory=list)
    constraints: list[str] = Field(default_factory=list)
    mentor_id: str | None = None
    mentor_evidence_ids: list[str] = Field(default_factory=list)


class MentorCallout(CurriculumSchema):
    """A relevant mentor parallel backed by a stored evidence claim."""

    evidence_claim_id: str
    connection_to_skill: str = Field(min_length=1)
    practical_application: str = Field(min_length=1)
    quote_excerpt: str | None = Field(default=None, max_length=400)


class PersonalizedLessonArtifact(CurriculumSchema):
    """Complete reader content; canonical-only content cannot satisfy this schema."""

    schema_version: int = Field(default=1, ge=1)
    canonical_module_version_id: str
    module_session_id: str
    title: str = Field(min_length=1, max_length=240)
    why_now: str = Field(min_length=1)
    adapted_explanation_markdown: str = Field(min_length=100)
    worked_example_markdown: str = Field(min_length=100)
    guided_practice_markdown: str = Field(min_length=50)
    artifact_spec: dict[str, Any]
    assessment: AssessmentArtifact
    personalized_rubric: dict[str, Any]
    mentor_callouts: list[MentorCallout] = Field(default_factory=list, max_length=3)
    estimated_minutes: int = Field(ge=10, le=240)


class PersistedPersonalizedLessonContent(CurriculumSchema):
    """Exact per-session payload persisted by the catalog personalizer."""

    step: dict[str, Any]
    materials: list[dict[str, Any]] = Field(default_factory=list)
    catalog: dict[str, Any]
    personalization: dict[str, Any]
    retrieval_follow_ups: list[dict[str, Any]] = Field(default_factory=list)


class CurriculumSkillCreate(CurriculumSchema):
    key: str = Field(pattern=r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$", max_length=160)
    domain: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1)
    skill_type: str = Field(min_length=1, max_length=50)
    taxonomy_version: int = Field(default=1, ge=1)
    tags: list[str] = Field(
        default_factory=list,
        validation_alias=AliasChoices("tags", "tags_json"),
    )
    prerequisite_skill_ids: list[str] = Field(default_factory=list)


class CurriculumSkillRead(CurriculumSkillCreate):
    id: str
    status: CurriculumSkillStatus
    created_at: datetime
    updated_at: datetime


class LearningTechniqueVersionCreate(CurriculumSchema):
    technique_key: str = Field(min_length=1, max_length=120)
    version_number: int = Field(ge=1)
    title: str = Field(min_length=1, max_length=200)
    summary: str = Field(min_length=1)
    evidence_level: EvidenceLevel
    appropriate_for: dict[str, Any] = Field(default_factory=dict)
    conditions: dict[str, Any] = Field(default_factory=dict)
    implementation_contract: dict[str, Any]
    limitations: dict[str, Any] = Field(default_factory=dict)
    source_manifest: dict[str, Any]
    content_hash: str = Field(pattern=SHA256_PATTERN)
    source_hash: str = Field(pattern=SHA256_PATTERN)


class CanonicalModuleVersionCreate(CurriculumSchema):
    module_id: str
    version_number: int = Field(ge=1)
    supersedes_version_id: str | None = None
    content: CanonicalModuleArtifact
    source_manifest: SourceManifest
    technique_plan: TechniquePlan
    content_hash: str = Field(pattern=SHA256_PATTERN)
    source_hash: str = Field(pattern=SHA256_PATTERN)
    retrieval_metadata: dict[str, Any]
    retrieval_metadata_hash: str = Field(pattern=SHA256_PATTERN)
    estimated_minutes: int = Field(gt=0)
    prompt_version: str = Field(min_length=1, max_length=100)
    gate_version: str | None = Field(default=None, max_length=100)
    model_name: str = Field(min_length=1, max_length=120)


class CurriculumGenerationJobCreate(CurriculumSchema):
    skill_id: str
    module_id: str | None = None
    input_hash: str = Field(pattern=SHA256_PATTERN)
    input: dict[str, Any]
    pipeline_version: str = Field(min_length=1, max_length=100)
    priority: int = 0
    max_attempts: int = Field(default=3, ge=1, le=10)
    max_repairs: int = Field(default=2, ge=0, le=5)
    budget_limit_usd: Decimal | None = Field(default=None, ge=0)


class CurriculumGenerationJobRead(CurriculumSchema):
    id: str
    skill_id: str
    module_id: str | None = None
    module_version_id: str | None = None
    stage: GenerationStage
    state: GenerationState
    priority: int
    input_hash: str = Field(pattern=SHA256_PATTERN)
    checkpoints: dict[str, Any] = Field(
        default_factory=dict,
        validation_alias=AliasChoices("checkpoints", "checkpointsJson", "checkpoints_json"),
    )
    attempts: int
    max_attempts: int
    repair_attempts: int
    max_repairs: int
    lease_owner: str | None = None
    lease_expires_at: datetime | None = None
    next_attempt_at: datetime | None = None
    last_error: str | None = None
    estimated_cost_usd: Decimal
    cost_usd: Decimal
    input_tokens: int
    cached_input_tokens: int
    output_tokens: int
    created_at: datetime
    updated_at: datetime


class ModuleQualityReportCreate(CurriculumSchema):
    module_version_id: str
    generation_job_id: str | None = None
    review_type: QualityReviewType
    verdict: QualityVerdict
    score: float | None = Field(default=None, ge=0, le=1)
    attempt: int = Field(default=1, ge=1)
    reviewed_content_hash: str = Field(pattern=SHA256_PATTERN)
    issues: list[dict[str, Any]] = Field(default_factory=list)
    evidence: dict[str, Any] = Field(
        default_factory=dict,
        validation_alias=AliasChoices("evidence", "evidenceJson", "evidence_json"),
    )
    deterministic_checks: dict[str, Any] = Field(default_factory=dict)
    repair_instructions: dict[str, Any] | None = None
    reviewer_model: str | None = Field(default=None, max_length=120)
    prompt_version: str | None = Field(default=None, max_length=100)


class MentorEvidenceClaimCreate(CurriculumSchema):
    idol_id: str
    claim_type: MentorClaimType
    claim_text: str = Field(min_length=1)
    normalized_hash: str = Field(pattern=SHA256_PATTERN)
    source_chunk_id: str | None = None
    source_title: str | None = Field(default=None, max_length=500)
    source_url: str | None = Field(default=None, pattern=r"^https?://", max_length=2048)
    evidence_excerpt: str = Field(min_length=1, max_length=4000)
    evidence: dict[str, Any] = Field(
        default_factory=dict,
        validation_alias=AliasChoices("evidence", "evidenceJson", "evidence_json"),
    )
    source_hash: str = Field(pattern=SHA256_PATTERN)
    skill_tags: list[str] = Field(
        default_factory=list,
        validation_alias=AliasChoices("skill_tags", "skillTags", "skill_tags_json"),
    )
    skill_ids: list[str] = Field(default_factory=list)
    confidence: float = Field(ge=0, le=1)
    valid_from: date | None = None
    valid_to: date | None = None

    @model_validator(mode="after")
    def require_source_provenance(self) -> "MentorEvidenceClaimCreate":
        if self.source_chunk_id is None and self.source_url is None:
            raise ValueError("source_chunk_id or source_url is required")
        if self.valid_from and self.valid_to and self.valid_to < self.valid_from:
            raise ValueError("valid_to cannot precede valid_from")
        return self


class MentorEvidenceClaimRead(MentorEvidenceClaimCreate):
    id: str
    verification_status: EvidenceVerificationStatus
    verified_at: datetime | None = None
    revoked_at: datetime | None = None
    revocation_reason: str | None = None
    created_at: datetime
    updated_at: datetime


class LearnerSkillStateUpsert(CurriculumSchema):
    skill_id: str
    current_level: SkillLevel = SkillLevel.UNKNOWN
    mastery_status: LearnerMasteryStatus = LearnerMasteryStatus.UNASSESSED
    mastery_score: float | None = Field(default=None, ge=0, le=1)
    strengths: list[str] = Field(default_factory=list)
    gaps: list[str] = Field(default_factory=list)
    misconceptions: list[str] = Field(default_factory=list)
    evidence: dict[str, Any] = Field(
        default_factory=dict,
        validation_alias=AliasChoices("evidence", "evidenceJson", "evidence_json"),
    )
    state_hash: str | None = Field(default=None, pattern=SHA256_PATTERN)
    assessed_at: datetime | None = None


class PersonalizedLessonVersionRead(CurriculumSchema):
    id: str
    user_id: str
    module_session_id: str
    module_version_id: str
    version_number: int
    status: PersonalizedLessonStatus
    content: PersistedPersonalizedLessonContent | None = Field(
        default=None,
        validation_alias=AliasChoices("content", "contentJson", "content_json"),
    )
    content_hash: str | None = Field(default=None, pattern=SHA256_PATTERN)
    estimated_minutes: int
    ready_at: datetime | None = None
    last_error: str | None = None
    revoked_at: datetime | None = None
    revocation_reason: str | None = None
    created_at: datetime


class PlanLessonAssignmentRead(CurriculumSchema):
    id: str
    plan_id: str
    plan_item_id: str | None = None
    module_session_id: str
    personalized_lesson_version_id: str | None = None
    week_number: int
    position: int
    allocated_minutes: int
    status: AssignmentStatus
    comparison_gap: dict[str, Any] = Field(
        validation_alias=AliasChoices(
            "comparison_gap",
            "comparisonGap",
            "comparison_gap_json",
        )
    )
    match_score: float | None = None
    match_reason: str
    available_at: datetime | None = None
    completed_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class VersionLifecycleRead(CurriculumSchema):
    """Small reusable API view for append-only publish/revoke state."""

    status: VersionStatus
    published_at: datetime | None = None
    revoked_at: datetime | None = None
    revocation_reason: str | None = None
