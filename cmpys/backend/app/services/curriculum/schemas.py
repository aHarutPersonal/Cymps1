"""Strict structured artifacts exchanged by curriculum agents."""

from __future__ import annotations

from enum import Enum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.services.tavily import is_direct_resource_url


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class SourceType(str, Enum):
    SYSTEMATIC_REVIEW = "systematic_review"
    META_ANALYSIS = "meta_analysis"
    PRACTICE_GUIDE = "practice_guide"
    PRIMARY_RESEARCH = "primary_research"
    PROFESSIONAL_STANDARD = "professional_standard"
    OFFICIAL_DOCUMENTATION = "official_documentation"
    PRIMARY_MENTOR_SOURCE = "primary_mentor_source"
    UNIVERSITY_RESOURCE = "university_resource"
    BOOK = "book"
    OTHER = "other"


class EvidenceTier(str, Enum):
    STRONG = "strong"
    MODERATE = "moderate"
    EMERGING = "emerging"


class RightsStatus(str, Enum):
    OPEN = "open"
    LICENSED = "licensed"
    CITATION_ONLY = "citation_only"
    UNKNOWN = "unknown"


class EvidenceSource(StrictModel):
    source_id: str = Field(pattern=r"^src_[a-z0-9][a-z0-9_-]{2,63}$")
    title: str = Field(min_length=3, max_length=500)
    url: str = Field(min_length=8, max_length=2048)
    source_type: SourceType
    evidence_tier: EvidenceTier
    rights_status: RightsStatus
    publisher: str | None = Field(default=None, max_length=300)
    author: str | None = Field(default=None, max_length=300)
    published_at: str | None = Field(default=None, max_length=40)
    checked_at: str | None = Field(default=None, max_length=40)
    provider_provenance_url: str | None = Field(default=None, max_length=2048)
    sanitized_support_text: str = Field(min_length=20, max_length=2500)
    source_text_kind: Literal[
        "provider_grounded_support", "approved_registry_summary"
    ]
    classification_provenance: Literal[
        "deterministic_url_rule", "approved_registry", "unverified"
    ]
    grounding_confidence: float | None = Field(default=None, ge=0, le=1)
    content_hash: str = Field(pattern=r"^[a-f0-9]{64}$")

    @field_validator("url")
    @classmethod
    def direct_public_url(cls, value: str) -> str:
        if not is_direct_resource_url(value):
            raise ValueError("source URL must be a direct public HTTP(S) page")
        return value

    @field_validator("provider_provenance_url")
    @classmethod
    def safe_provenance_url(cls, value: str | None) -> str | None:
        if value is not None and not is_direct_resource_url(value):
            raise ValueError("provider provenance URL must be a public HTTP(S) URL")
        return value


class EvidenceClaim(StrictModel):
    claim_id: str = Field(pattern=r"^claim_[a-z0-9][a-z0-9_-]{2,63}$")
    statement: str = Field(min_length=12, max_length=1200)
    claim_kind: Literal["domain", "pedagogy"] = "domain"
    source_ids: list[str] = Field(min_length=1, max_length=8)
    confidence: float = Field(ge=0, le=1)
    verification_score: float | None = Field(default=None, ge=0, le=1)
    verification_note: str | None = Field(default=None, max_length=800)

    @field_validator("source_ids")
    @classmethod
    def unique_source_ids(cls, value: list[str]) -> list[str]:
        if len(value) != len(set(value)):
            raise ValueError("claim source_ids must be unique")
        return value


class ResearchManifest(StrictModel):
    research_question: str = Field(min_length=12, max_length=1000)
    sources: list[EvidenceSource] = Field(min_length=2, max_length=30)
    claims: list[EvidenceClaim] = Field(min_length=2, max_length=80)
    limitations: list[str] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def references_existing_sources(self) -> "ResearchManifest":
        source_ids = [source.source_id for source in self.sources]
        claim_ids = [claim.claim_id for claim in self.claims]
        if len(source_ids) != len(set(source_ids)):
            raise ValueError("source_id values must be unique")
        if len(claim_ids) != len(set(claim_ids)):
            raise ValueError("claim_id values must be unique")
        missing = sorted(
            {
                source_id
                for claim in self.claims
                for source_id in claim.source_ids
                if source_id not in source_ids
            }
        )
        if missing:
            raise ValueError(f"claims reference missing sources: {missing}")
        if not any(
            source.source_type
            in {
                SourceType.SYSTEMATIC_REVIEW,
                SourceType.META_ANALYSIS,
                SourceType.PRACTICE_GUIDE,
                SourceType.PRIMARY_RESEARCH,
                SourceType.PROFESSIONAL_STANDARD,
                SourceType.OFFICIAL_DOCUMENTATION,
            }
            for source in self.sources
        ):
            raise ValueError("manifest requires at least one authoritative source")
        domain_claims = [claim for claim in self.claims if claim.claim_kind == "domain"]
        if len(domain_claims) < 2:
            raise ValueError("manifest requires at least two domain claims")
        source_by_id = {source.source_id: source for source in self.sources}
        registry_grounded = [
            claim.claim_id
            for claim in domain_claims
            if not any(
                source_by_id[source_id].source_text_kind
                == "provider_grounded_support"
                for source_id in claim.source_ids
            )
        ]
        if registry_grounded:
            raise ValueError(
                "domain claims require live provider grounding; registry-only claims: "
                f"{registry_grounded}"
            )
        qualified_live_ids = {
            source.source_id
            for source in self.sources
            if source.source_text_kind == "provider_grounded_support"
            and source.classification_provenance == "deterministic_url_rule"
            and source.source_type
            in {
                SourceType.PRIMARY_RESEARCH,
                SourceType.PRACTICE_GUIDE,
                SourceType.PROFESSIONAL_STANDARD,
                SourceType.OFFICIAL_DOCUMENTATION,
                SourceType.UNIVERSITY_RESOURCE,
            }
        }
        if not any(
            qualified_live_ids.intersection(claim.source_ids)
            for claim in domain_claims
        ):
            raise ValueError(
                "at least one domain claim requires a deterministically qualified live source"
            )
        return self


class ResearchSourceAnnotation(StrictModel):
    """LLM classification of a server-owned, provider-grounded source."""

    source_id: str = Field(pattern=r"^src_[a-z0-9][a-z0-9_-]{2,63}$")
    publisher: str | None = Field(default=None, max_length=300)
    author: str | None = Field(default=None, max_length=300)
    published_at: str | None = Field(default=None, max_length=40)


class ResearchCuration(StrictModel):
    research_question: str = Field(min_length=12, max_length=1000)
    source_annotations: list[ResearchSourceAnnotation] = Field(
        min_length=2, max_length=30
    )
    claims: list[EvidenceClaim] = Field(min_length=2, max_length=80)
    limitations: list[str] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def unique_annotations(self) -> "ResearchCuration":
        ids = [item.source_id for item in self.source_annotations]
        if len(ids) != len(set(ids)):
            raise ValueError("source annotations must be unique")
        return self


class ClaimVerification(StrictModel):
    claim_id: str = Field(pattern=r"^claim_[a-z0-9][a-z0-9_-]{2,63}$")
    passed: bool
    confidence: float = Field(ge=0, le=1)
    supported_source_ids: list[str] = Field(default_factory=list, max_length=8)
    reasoning: str = Field(min_length=8, max_length=800)


class ClaimVerificationBundle(StrictModel):
    verifications: list[ClaimVerification] = Field(min_length=2, max_length=80)

    @model_validator(mode="after")
    def unique_claims(self) -> "ClaimVerificationBundle":
        ids = [item.claim_id for item in self.verifications]
        if len(ids) != len(set(ids)):
            raise ValueError("claim verifications must be unique")
        return self


class TechniqueId(str, Enum):
    RETRIEVAL_PRACTICE = "retrieval_practice"
    SPACED_PRACTICE = "spaced_practice"
    WORKED_EXAMPLES = "worked_examples"
    GUIDANCE_FADING = "guidance_fading"
    SELF_EXPLANATION = "self_explanation"
    INTERLEAVING = "interleaving"
    ACTIVE_APPLICATION = "active_application"
    FEEDBACK_REVISION = "feedback_revision"
    MASTERY_CHECKS = "mastery_checks"
    CONCRETE_ABSTRACT_LINKING = "concrete_abstract_linking"
    VISUAL_VERBAL = "visual_verbal"


class TechniqueApplication(StrictModel):
    technique_id: TechniqueId
    rationale: str = Field(min_length=12, max_length=800)
    implementation_steps: list[str] = Field(min_length=1, max_length=12)
    implementation_block_ids: list[str] = Field(min_length=1, max_length=20)
    evidence_source_ids: list[str] = Field(min_length=1, max_length=8)
    limitations: list[str] = Field(default_factory=list, max_length=8)


class TechniquePlan(StrictModel):
    learning_outcome: str = Field(min_length=12, max_length=1000)
    learner_level: Literal["beginner", "intermediate", "advanced"]
    applications: list[TechniqueApplication] = Field(min_length=2, max_length=8)
    assessment_strategy: str = Field(min_length=20, max_length=1500)
    spacing_follow_up_days: list[int] = Field(default_factory=list, max_length=8)

    @model_validator(mode="after")
    def unique_techniques(self) -> "TechniquePlan":
        technique_ids = [item.technique_id for item in self.applications]
        if len(technique_ids) != len(set(technique_ids)):
            raise ValueError("technique applications must be unique")
        if TechniqueId.SPACED_PRACTICE in technique_ids:
            if not self.spacing_follow_up_days:
                raise ValueError("spaced practice requires follow-up day offsets")
            if self.spacing_follow_up_days != sorted(set(self.spacing_follow_up_days)):
                raise ValueError("spacing offsets must be unique and ascending")
            if any(day <= 0 for day in self.spacing_follow_up_days):
                raise ValueError("spacing offsets must be positive")
        return self


class LessonBlockType(str, Enum):
    EXPLANATION = "explanation"
    VISUAL_EXPLANATION = "visual_explanation"
    WORKED_EXAMPLE = "worked_example"
    RETRIEVAL = "retrieval"
    GUIDED_PRACTICE = "guided_practice"
    INDEPENDENT_PRACTICE = "independent_practice"
    REFLECTION = "reflection"
    FEEDBACK = "feedback"
    REVISION = "revision"
    ASSESSMENT = "assessment"
    TRANSFER = "transfer"


class LessonBlock(StrictModel):
    block_id: str = Field(pattern=r"^block_[a-z0-9][a-z0-9_-]{2,63}$")
    block_type: LessonBlockType
    title: str = Field(min_length=3, max_length=220)
    minutes: int = Field(ge=2, le=60)
    content_markdown: str = Field(min_length=80, max_length=30000)
    learner_instructions: list[str] = Field(default_factory=list, max_length=20)
    success_criteria: list[str] = Field(default_factory=list, max_length=20)
    source_ids: list[str] = Field(default_factory=list, max_length=12)
    claim_ids: list[str] = Field(default_factory=list, max_length=20)
    technique_ids: list[TechniqueId] = Field(default_factory=list, max_length=8)
    follow_up_day: int | None = Field(default=None, ge=1, le=365)

    @model_validator(mode="after")
    def follow_up_requires_spacing(self) -> "LessonBlock":
        if (
            self.follow_up_day is not None
            and TechniqueId.SPACED_PRACTICE not in self.technique_ids
        ):
            raise ValueError("follow_up_day requires spaced_practice technique binding")
        return self


class OutlineBlock(StrictModel):
    block_id: str = Field(pattern=r"^block_[a-z0-9][a-z0-9_-]{2,63}$")
    block_type: LessonBlockType
    title: str = Field(min_length=3, max_length=220)
    purpose: str = Field(min_length=12, max_length=1000)
    minutes: int = Field(ge=2, le=60)
    source_ids: list[str] = Field(default_factory=list, max_length=12)
    claim_ids: list[str] = Field(default_factory=list, max_length=20)
    technique_ids: list[TechniqueId] = Field(default_factory=list, max_length=8)
    follow_up_day: int | None = Field(default=None, ge=1, le=365)

    @model_validator(mode="after")
    def follow_up_requires_spacing(self) -> "OutlineBlock":
        if (
            self.follow_up_day is not None
            and TechniqueId.SPACED_PRACTICE not in self.technique_ids
        ):
            raise ValueError("follow_up_day requires spaced_practice technique binding")
        return self


class CurriculumOutline(StrictModel):
    skill_key: str = Field(min_length=3, max_length=180)
    domain: str = Field(min_length=2, max_length=120)
    level: Literal["beginner", "intermediate", "advanced"]
    locale: str = Field(min_length=2, max_length=20)
    learning_outcome: str = Field(min_length=12, max_length=1000)
    prerequisites: list[str] = Field(default_factory=list, max_length=20)
    artifact_type: str = Field(min_length=3, max_length=100)
    blocks: list[OutlineBlock] = Field(min_length=5, max_length=40)
    artifact_description: str = Field(min_length=20, max_length=1200)
    estimated_minutes: int = Field(ge=40, le=1200)

    @model_validator(mode="after")
    def consistent_outline(self) -> "CurriculumOutline":
        block_ids = [block.block_id for block in self.blocks]
        if len(block_ids) != len(set(block_ids)):
            raise ValueError("outline block ids must be unique")
        actual_minutes = sum(block.minutes for block in self.blocks)
        if abs(actual_minutes - self.estimated_minutes) > max(10, actual_minutes // 10):
            raise ValueError("outline estimated_minutes must match block-time sum")
        return self


class RubricCriterion(StrictModel):
    criterion: str = Field(min_length=5, max_length=500)
    evidence_required: str = Field(min_length=5, max_length=800)
    passing_standard: str = Field(min_length=5, max_length=800)


class CanonicalModuleDraft(StrictModel):
    skill_key: str = Field(min_length=3, max_length=180)
    domain: str = Field(min_length=2, max_length=120)
    level: Literal["beginner", "intermediate", "advanced"]
    locale: str = Field(min_length=2, max_length=20)
    title: str = Field(min_length=5, max_length=220)
    summary: str = Field(min_length=30, max_length=1500)
    learning_outcome: str = Field(min_length=12, max_length=1000)
    prerequisites: list[str] = Field(default_factory=list, max_length=20)
    artifact_type: str = Field(min_length=3, max_length=100)
    blocks: list[LessonBlock] = Field(min_length=5, max_length=40)
    artifact_description: str = Field(min_length=20, max_length=1200)
    rubric: list[RubricCriterion] = Field(min_length=2, max_length=12)
    estimated_minutes: int = Field(ge=40, le=1200)

    @model_validator(mode="after")
    def consistent_blocks(self) -> "CanonicalModuleDraft":
        block_ids = [block.block_id for block in self.blocks]
        if len(block_ids) != len(set(block_ids)):
            raise ValueError("block_id values must be unique")
        actual_minutes = sum(block.minutes for block in self.blocks)
        if abs(actual_minutes - self.estimated_minutes) > max(10, actual_minutes // 10):
            raise ValueError("estimated_minutes must match the block-time sum")
        return self


class ReviewSeverity(str, Enum):
    WARNING = "warning"
    BLOCKING = "blocking"
    CRITICAL = "critical"


class ReviewIssue(StrictModel):
    code: str = Field(pattern=r"^[a-z][a-z0-9_]{2,80}$")
    severity: ReviewSeverity
    block_id: str | None = None
    description: str = Field(min_length=8, max_length=1200)
    repair_instruction: str = Field(min_length=8, max_length=1200)
    source_ids: list[str] = Field(default_factory=list, max_length=8)


class QualityReview(StrictModel):
    reviewer: Literal["structure", "factual", "pedagogy", "originality"]
    passed: bool
    score: float = Field(ge=0, le=1)
    issues: list[ReviewIssue] = Field(default_factory=list, max_length=30)
    evidence: list[str] = Field(default_factory=list, max_length=30)

    @model_validator(mode="after")
    def pass_matches_issues(self) -> "QualityReview":
        blocking = any(
            issue.severity in {ReviewSeverity.BLOCKING, ReviewSeverity.CRITICAL}
            for issue in self.issues
        )
        if self.passed and blocking:
            raise ValueError("a passing review cannot contain blocking issues")
        return self


class ReviewBundle(StrictModel):
    reviews: list[QualityReview] = Field(min_length=4, max_length=4)

    @model_validator(mode="after")
    def contains_independent_reviews(self) -> "ReviewBundle":
        expected = {"structure", "factual", "pedagogy", "originality"}
        actual = {review.reviewer for review in self.reviews}
        if actual != expected or len(actual) != len(self.reviews):
            raise ValueError(f"review bundle must contain exactly {sorted(expected)}")
        return self


class RepairResult(StrictModel):
    repaired_draft: CanonicalModuleDraft
    addressed_issue_codes: list[str] = Field(min_length=1, max_length=40)
    change_summary: list[str] = Field(min_length=1, max_length=30)


class MentorClaimCandidate(StrictModel):
    claim_type: Literal[
        "recommended_book",
        "habit",
        "decision_method",
        "principle",
        "failure",
        "learning_method",
        "preference",
    ]
    normalized_claim: str = Field(min_length=12, max_length=1200)
    source_chunk_ids: list[str] = Field(min_length=1, max_length=8)
    related_skill_keys: list[str] = Field(default_factory=list, max_length=20)
    confidence: float = Field(ge=0, le=1)
    pedagogical_use: str = Field(min_length=12, max_length=800)


class MentorClaimCuration(StrictModel):
    claims: list[MentorClaimCandidate] = Field(default_factory=list, max_length=20)


class MentorClaimVerification(StrictModel):
    candidate_id: str = Field(pattern=r"^mentor_[a-f0-9]{24}$")
    passed: bool
    supported_source_chunk_ids: list[str] = Field(default_factory=list, max_length=8)
    confidence: float = Field(ge=0, le=1)
    reasoning: str = Field(min_length=8, max_length=800)


class MentorClaimVerificationBundle(StrictModel):
    verifications: list[MentorClaimVerification] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def unique_candidates(self) -> "MentorClaimVerificationBundle":
        ids = [item.candidate_id for item in self.verifications]
        if len(ids) != len(set(ids)):
            raise ValueError("mentor claim verifications must be unique")
        return self
