"""Persistence foundation for the evidence-based lesson factory.

The catalog keeps immutable, source-backed module versions separate from the
learner-specific reader artifact.  Plans pin exact session and personalized
lesson versions so ordinary catalog updates cannot silently change an active
plan.
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import TYPE_CHECKING

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    CheckConstraint,
    Column,
    Date,
    DateTime,
    Enum as SQLEnum,
    Float,
    ForeignKey,
    ForeignKeyConstraint,
    Index,
    Integer,
    Numeric,
    String,
    Table,
    Text,
    UniqueConstraint,
    event,
    inspect as sa_inspect,
    select,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, TimestampUpdateMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.idol import Idol
    from app.models.plan import Plan, PlanItem
    from app.models.source_chunk import SourceChunk
    from app.models.user import User


SHA256_PATTERN = r"^[0-9a-f]{64}$"
PYTHON_STRIP_CHARACTERS_SQL = (
    "U&'\\0009\\000A\\000B\\000C\\000D\\001C\\001D\\001E\\001F\\0020"
    "\\0085\\00A0\\1680\\2000\\2001\\2002"
    "\\2003\\2004\\2005\\2006\\2007\\2008\\2009\\200A\\2028\\2029"
    "\\202F\\205F\\3000'"
)


class SkillLevel(str, Enum):
    UNKNOWN = "unknown"
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"


class CurriculumSkillStatus(str, Enum):
    DRAFT = "draft"
    ACTIVE = "active"
    RETIRED = "retired"


class EvidenceLevel(str, Enum):
    STRONG = "strong"
    MODERATE = "moderate"
    EMERGING = "emerging"


class VersionStatus(str, Enum):
    DRAFT = "draft"
    IN_REVIEW = "in_review"
    PUBLISHED = "published"
    REVOKED = "revoked"


class GenerationStage(str, Enum):
    TAXONOMY = "taxonomy"
    SOURCE_RESEARCH = "source_research"
    TECHNIQUE_DESIGN = "technique_design"
    OUTLINE = "outline"
    WRITING = "writing"
    FACTUAL_REVIEW = "factual_review"
    PEDAGOGY_REVIEW = "pedagogy_review"
    ORIGINALITY_REVIEW = "originality_review"
    PUBLISH = "publish"


class GenerationState(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    RETRY_WAIT = "retry_wait"
    COMPLETED = "completed"
    FAILED = "failed"
    FLAGGED = "flagged"
    CANCELLED = "cancelled"


class QualityReviewType(str, Enum):
    SCHEMA = "schema"
    SOURCE_ATTRIBUTION = "source_attribution"
    FACTUAL = "factual"
    PEDAGOGY = "pedagogy"
    ORIGINALITY = "originality"
    EDITORIAL = "editorial"


class QualityVerdict(str, Enum):
    PASSED = "passed"
    NEEDS_REPAIR = "needs_repair"
    REJECTED = "rejected"


class MentorClaimType(str, Enum):
    RECOMMENDED_BOOK = "recommended_book"
    HABIT = "habit"
    DECISION_METHOD = "decision_method"
    PRINCIPLE = "principle"
    FAILURE = "failure"
    LEARNING_METHOD = "learning_method"
    PREFERENCE = "preference"


class EvidenceVerificationStatus(str, Enum):
    PENDING = "pending"
    VERIFIED = "verified"
    REJECTED = "rejected"
    REVOKED = "revoked"


class LearnerMasteryStatus(str, Enum):
    UNASSESSED = "unassessed"
    DEVELOPING = "developing"
    DEMONSTRATED = "demonstrated"
    MASTERED = "mastered"


class PersonalizedLessonStatus(str, Enum):
    QUEUED = "queued"
    GENERATING = "generating"
    READY = "ready"
    FAILED = "failed"
    REVOKED = "revoked"


class AssignmentStatus(str, Enum):
    SCHEDULED = "scheduled"
    AVAILABLE = "available"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    SKIPPED = "skipped"
    REPLACED = "replaced"


def _db_enum(enum_type: type[Enum], name: str) -> SQLEnum:
    return SQLEnum(
        enum_type,
        name=name,
        values_callable=lambda values: [value.value for value in values],
    )


curriculum_skill_prerequisites = Table(
    "curriculum_skill_prerequisites",
    Base.metadata,
    Column(
        "skill_id",
        UUID(as_uuid=False),
        ForeignKey("curriculum_skills.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "prerequisite_skill_id",
        UUID(as_uuid=False),
        ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
        primary_key=True,
    ),
    CheckConstraint(
        "skill_id <> prerequisite_skill_id",
        name="ck_curriculum_skill_prerequisite_not_self",
    ),
)


mentor_evidence_claim_skills = Table(
    "mentor_evidence_claim_skills",
    Base.metadata,
    Column(
        "claim_id",
        UUID(as_uuid=False),
        ForeignKey("mentor_evidence_claims.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "skill_id",
        UUID(as_uuid=False),
        ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
        primary_key=True,
    ),
)


class CurriculumSkill(Base, UUIDMixin, TimestampUpdateMixin):
    """A stable node in the versioned curriculum taxonomy."""

    __tablename__ = "curriculum_skills"
    __table_args__ = (
        UniqueConstraint("key", name="uq_curriculum_skills_key"),
        Index("ix_curriculum_skills_domain_status", "domain", "status"),
        CheckConstraint(
            "taxonomy_version > 0", name="ck_curriculum_skills_taxonomy_version"
        ),
    )

    key: Mapped[str] = mapped_column(String(160), nullable=False)
    domain: Mapped[str] = mapped_column(String(100), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    skill_type: Mapped[str] = mapped_column(String(50), nullable=False)
    taxonomy_version: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=1,
        server_default="1",
    )
    tags_json: Mapped[list] = mapped_column(
        JSONB,
        nullable=False,
        default=list,
        server_default=text("'[]'::jsonb"),
    )
    status: Mapped[CurriculumSkillStatus] = mapped_column(
        _db_enum(CurriculumSkillStatus, "curriculum_skill_status"),
        nullable=False,
        default=CurriculumSkillStatus.DRAFT,
        server_default=CurriculumSkillStatus.DRAFT.value,
    )

    prerequisites: Mapped[list[CurriculumSkill]] = relationship(
        "CurriculumSkill",
        secondary=curriculum_skill_prerequisites,
        primaryjoin=lambda: CurriculumSkill.id
        == curriculum_skill_prerequisites.c.skill_id,
        secondaryjoin=lambda: CurriculumSkill.id
        == curriculum_skill_prerequisites.c.prerequisite_skill_id,
        back_populates="dependents",
        lazy="selectin",
    )
    dependents: Mapped[list[CurriculumSkill]] = relationship(
        "CurriculumSkill",
        secondary=curriculum_skill_prerequisites,
        primaryjoin=lambda: CurriculumSkill.id
        == curriculum_skill_prerequisites.c.prerequisite_skill_id,
        secondaryjoin=lambda: CurriculumSkill.id
        == curriculum_skill_prerequisites.c.skill_id,
        back_populates="prerequisites",
        lazy="selectin",
    )
    modules: Mapped[list[CanonicalModule]] = relationship(
        "CanonicalModule",
        back_populates="skill",
        lazy="selectin",
    )
    mentor_claims: Mapped[list[MentorEvidenceClaim]] = relationship(
        "MentorEvidenceClaim",
        secondary=mentor_evidence_claim_skills,
        back_populates="skills",
        lazy="selectin",
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("taxonomy_version", 1)
        kwargs.setdefault("tags_json", [])
        kwargs.setdefault("status", CurriculumSkillStatus.DRAFT)
        super().__init__(**kwargs)


class LearningTechniqueVersion(Base, UUIDMixin, TimestampMixin):
    """Append-only evidence review of a concrete learning technique."""

    __tablename__ = "learning_technique_versions"
    __table_args__ = (
        UniqueConstraint(
            "technique_key",
            "version_number",
            name="uq_learning_technique_versions_key_version",
        ),
        UniqueConstraint(
            "technique_key",
            "content_hash",
            name="uq_learning_technique_versions_key_content_hash",
        ),
        Index(
            "ix_learning_technique_versions_key_status",
            "technique_key",
            "status",
        ),
        CheckConstraint(
            "version_number > 0", name="ck_learning_technique_version_number"
        ),
        CheckConstraint(
            f"content_hash ~ '{SHA256_PATTERN}'",
            name="ck_learning_technique_content_hash_sha256",
        ),
        CheckConstraint(
            f"source_hash ~ '{SHA256_PATTERN}'",
            name="ck_learning_technique_source_hash_sha256",
        ),
        CheckConstraint(
            "(status <> 'published' OR published_at IS NOT NULL) AND "
            "(status <> 'revoked' OR (revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))",
            name="ck_learning_technique_version_lifecycle",
        ),
        CheckConstraint(
            f"((status IN ('draft', 'in_review') AND published_at IS NULL) OR "
            "(status IN ('published', 'revoked') AND published_at IS NOT NULL)) AND "
            "((status <> 'revoked' AND revoked_at IS NULL AND revocation_reason IS NULL) OR "
            "(status = 'revoked' AND revoked_at IS NOT NULL AND "
            "NULLIF(btrim(COALESCE(revocation_reason, ''), "
            f"{PYTHON_STRIP_CHARACTERS_SQL}), '') IS NOT NULL))",
            name="ck_learning_technique_versions_audit_shape",
        ),
    )

    technique_key: Mapped[str] = mapped_column(String(120), nullable=False)
    version_number: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    evidence_level: Mapped[EvidenceLevel] = mapped_column(
        _db_enum(EvidenceLevel, "learning_evidence_level"),
        nullable=False,
    )
    appropriate_for_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )
    conditions_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )
    implementation_contract_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    limitations_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )
    source_manifest_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    source_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[VersionStatus] = mapped_column(
        _db_enum(VersionStatus, "curriculum_version_status"),
        nullable=False,
        default=VersionStatus.DRAFT,
        server_default=VersionStatus.DRAFT.value,
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    published_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    revocation_reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("appropriate_for_json", {})
        kwargs.setdefault("conditions_json", {})
        kwargs.setdefault("limitations_json", {})
        kwargs.setdefault("status", VersionStatus.DRAFT)
        super().__init__(**kwargs)


class CanonicalModule(Base, UUIDMixin, TimestampUpdateMixin):
    """Stable catalog identity for one skill, level, locale, and outcome."""

    __tablename__ = "canonical_modules"
    __table_args__ = (
        ForeignKeyConstraint(
            ["current_published_version_id", "id"],
            ["canonical_module_versions.id", "canonical_module_versions.module_id"],
            name="fk_canonical_modules_current_published_version",
            ondelete="RESTRICT",
            use_alter=True,
        ),
        UniqueConstraint("key", name="uq_canonical_modules_key"),
        Index(
            "ix_canonical_modules_match",
            "skill_id",
            "level",
            "language",
            "status",
        ),
        CheckConstraint(
            "level <> 'unknown'",
            name="ck_canonical_modules_known_level",
        ),
        CheckConstraint(
            "estimated_total_minutes > 0",
            name="ck_canonical_modules_estimated_minutes",
        ),
        CheckConstraint(
            "status <> 'active' OR current_published_version_id IS NOT NULL",
            name="ck_canonical_modules_active_version",
        ),
    )

    skill_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
        nullable=False,
    )
    key: Mapped[str] = mapped_column(String(200), nullable=False)
    level: Mapped[SkillLevel] = mapped_column(
        _db_enum(SkillLevel, "curriculum_skill_level"),
        nullable=False,
    )
    language: Mapped[str] = mapped_column(
        String(12), nullable=False, default="en", server_default="en"
    )
    title: Mapped[str] = mapped_column(String(240), nullable=False)
    learning_outcome: Mapped[str] = mapped_column(Text, nullable=False)
    artifact_type: Mapped[str] = mapped_column(String(100), nullable=False)
    estimated_total_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[CurriculumSkillStatus] = mapped_column(
        _db_enum(CurriculumSkillStatus, "curriculum_skill_status"),
        nullable=False,
        default=CurriculumSkillStatus.DRAFT,
        server_default=CurriculumSkillStatus.DRAFT.value,
    )
    current_published_version_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        nullable=True,
    )

    skill: Mapped[CurriculumSkill] = relationship(
        "CurriculumSkill",
        back_populates="modules",
    )
    versions: Mapped[list[CanonicalModuleVersion]] = relationship(
        "CanonicalModuleVersion",
        back_populates="module",
        foreign_keys="CanonicalModuleVersion.module_id",
        order_by="CanonicalModuleVersion.version_number",
        lazy="selectin",
    )
    current_published_version: Mapped[CanonicalModuleVersion | None] = relationship(
        "CanonicalModuleVersion",
        foreign_keys=[current_published_version_id],
        primaryjoin=lambda: CanonicalModule.current_published_version_id
        == CanonicalModuleVersion.id,
        post_update=True,
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("language", "en")
        kwargs.setdefault("status", CurriculumSkillStatus.DRAFT)
        super().__init__(**kwargs)


class CanonicalModuleVersion(Base, UUIDMixin, TimestampMixin):
    """Immutable canonical content plus mutable publish/revoke lifecycle."""

    __tablename__ = "canonical_module_versions"
    __table_args__ = (
        ForeignKeyConstraint(
            ["supersedes_version_id", "module_id"],
            ["canonical_module_versions.id", "canonical_module_versions.module_id"],
            name="fk_canonical_module_versions_supersedes_same_module",
            ondelete="RESTRICT",
        ),
        UniqueConstraint(
            "id",
            "module_id",
            name="uq_canonical_module_versions_id_module",
        ),
        UniqueConstraint(
            "module_id",
            "version_number",
            name="uq_canonical_module_versions_module_version",
        ),
        UniqueConstraint(
            "module_id",
            "content_hash",
            name="uq_canonical_module_versions_module_content_hash",
        ),
        Index(
            "ix_canonical_module_versions_module_status",
            "module_id",
            "status",
        ),
        Index(
            "ix_canonical_module_versions_embedding_hnsw",
            "embedding",
            postgresql_using="hnsw",
            postgresql_ops={"embedding": "vector_cosine_ops"},
            postgresql_where=text("embedding IS NOT NULL"),
        ),
        CheckConstraint(
            "version_number > 0", name="ck_canonical_module_version_number"
        ),
        CheckConstraint(
            "estimated_minutes > 0", name="ck_canonical_module_version_minutes"
        ),
        CheckConstraint(
            "quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)",
            name="ck_canonical_module_version_quality_score",
        ),
        CheckConstraint(
            f"content_hash ~ '{SHA256_PATTERN}'",
            name="ck_canonical_module_version_content_hash_sha256",
        ),
        CheckConstraint(
            f"source_hash ~ '{SHA256_PATTERN}'",
            name="ck_canonical_module_version_source_hash_sha256",
        ),
        CheckConstraint(
            f"retrieval_metadata_hash ~ '{SHA256_PATTERN}'",
            name="ck_canonical_module_version_retrieval_hash_sha256",
        ),
        CheckConstraint(
            "(status <> 'published' OR published_at IS NOT NULL) AND "
            "(status <> 'revoked' OR (revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))",
            name="ck_canonical_module_version_lifecycle",
        ),
        CheckConstraint(
            f"((status IN ('draft', 'in_review') AND published_at IS NULL) OR "
            "(status IN ('published', 'revoked') AND published_at IS NOT NULL)) AND "
            "((status <> 'revoked' AND revoked_at IS NULL AND revocation_reason IS NULL) OR "
            "(status = 'revoked' AND revoked_at IS NOT NULL AND "
            "NULLIF(btrim(COALESCE(revocation_reason, ''), "
            f"{PYTHON_STRIP_CHARACTERS_SQL}), '') IS NOT NULL))",
            name="ck_canonical_module_versions_audit_shape",
        ),
    )

    module_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("canonical_modules.id", ondelete="RESTRICT"),
        nullable=False,
    )
    version_number: Mapped[int] = mapped_column(Integer, nullable=False)
    supersedes_version_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        nullable=True,
    )
    status: Mapped[VersionStatus] = mapped_column(
        _db_enum(VersionStatus, "curriculum_version_status"),
        nullable=False,
        default=VersionStatus.DRAFT,
        server_default=VersionStatus.DRAFT.value,
    )
    content_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    source_manifest_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    technique_plan_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    source_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    embedding: Mapped[list[float] | None] = mapped_column(Vector(1024), nullable=True)
    retrieval_metadata_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )
    retrieval_metadata_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    estimated_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    quality_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    prompt_version: Mapped[str] = mapped_column(String(100), nullable=False)
    gate_version: Mapped[str | None] = mapped_column(String(100), nullable=True)
    model_name: Mapped[str] = mapped_column(String(120), nullable=False)
    published_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    revocation_reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    module: Mapped[CanonicalModule] = relationship(
        "CanonicalModule",
        back_populates="versions",
        foreign_keys=[module_id],
    )
    supersedes_version: Mapped[CanonicalModuleVersion | None] = relationship(
        "CanonicalModuleVersion",
        remote_side="CanonicalModuleVersion.id",
        foreign_keys=[supersedes_version_id],
        primaryjoin=lambda: CanonicalModuleVersion.supersedes_version_id
        == CanonicalModuleVersion.id,
        viewonly=True,
    )
    sessions: Mapped[list[ModuleSession]] = relationship(
        "ModuleSession",
        back_populates="module_version",
        order_by="ModuleSession.position",
        lazy="selectin",
    )
    quality_reports: Mapped[list[ModuleQualityReport]] = relationship(
        "ModuleQualityReport",
        back_populates="module_version",
        order_by="ModuleQualityReport.created_at",
        lazy="selectin",
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("status", VersionStatus.DRAFT)
        kwargs.setdefault("retrieval_metadata_json", {})
        super().__init__(**kwargs)


class ModuleSession(Base, UUIDMixin, TimestampMixin):
    """One honest, sequential learning session within an immutable module version."""

    __tablename__ = "module_sessions"
    __table_args__ = (
        UniqueConstraint(
            "module_version_id",
            "position",
            name="uq_module_sessions_version_position",
        ),
        UniqueConstraint(
            "id",
            "module_version_id",
            name="uq_module_sessions_id_version",
        ),
        CheckConstraint("position > 0", name="ck_module_sessions_position"),
        CheckConstraint("estimated_minutes > 0", name="ck_module_sessions_minutes"),
        CheckConstraint(
            f"content_hash ~ '{SHA256_PATTERN}'",
            name="ck_module_sessions_content_hash_sha256",
        ),
    )

    module_version_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("canonical_module_versions.id", ondelete="RESTRICT"),
        nullable=False,
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(String(240), nullable=False)
    learning_objective: Mapped[str] = mapped_column(Text, nullable=False)
    estimated_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    content_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    assessment_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    artifact_spec_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    technique_plan_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)

    module_version: Mapped[CanonicalModuleVersion] = relationship(
        "CanonicalModuleVersion",
        back_populates="sessions",
    )
    personalized_versions: Mapped[list[PersonalizedLessonVersion]] = relationship(
        "PersonalizedLessonVersion",
        back_populates="module_session",
        lazy="selectin",
    )


class CurriculumGenerationJob(Base, UUIDMixin, TimestampUpdateMixin):
    """Idempotent, leased database job for the bounded curriculum pipeline."""

    __tablename__ = "curriculum_generation_jobs"
    __table_args__ = (
        UniqueConstraint("input_hash", name="uq_curriculum_generation_jobs_input_hash"),
        Index(
            "ix_curriculum_generation_jobs_eligible",
            "state",
            "next_attempt_at",
            "priority",
        ),
        Index(
            "ix_curriculum_generation_jobs_lease",
            "state",
            "lease_expires_at",
        ),
        CheckConstraint(
            f"input_hash ~ '{SHA256_PATTERN}'",
            name="ck_curriculum_generation_jobs_input_hash_sha256",
        ),
        CheckConstraint(
            "attempts >= 0 AND max_attempts > 0 AND attempts <= max_attempts",
            name="ck_curriculum_generation_jobs_attempts",
        ),
        CheckConstraint(
            "repair_attempts >= 0 AND max_repairs >= 0 AND repair_attempts <= max_repairs",
            name="ck_curriculum_generation_jobs_repairs",
        ),
        CheckConstraint(
            "budget_limit_usd >= 0",
            name="ck_curriculum_generation_jobs_budget",
        ),
        CheckConstraint(
            "estimated_cost_usd >= 0 AND cost_usd >= 0",
            name="ck_curriculum_generation_jobs_cost",
        ),
        CheckConstraint(
            "input_tokens >= 0 AND cached_input_tokens >= 0 AND output_tokens >= 0",
            name="ck_curriculum_generation_jobs_tokens",
        ),
        CheckConstraint(
            "state <> 'running' OR (lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL)",
            name="ck_curriculum_generation_jobs_running_lease",
        ),
    )

    skill_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
        nullable=False,
    )
    module_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("canonical_modules.id", ondelete="RESTRICT"),
        nullable=True,
    )
    module_version_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("canonical_module_versions.id", ondelete="RESTRICT"),
        nullable=True,
    )
    target_version_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    stage: Mapped[GenerationStage] = mapped_column(
        _db_enum(GenerationStage, "curriculum_generation_stage"),
        nullable=False,
        default=GenerationStage.TAXONOMY,
        server_default=GenerationStage.TAXONOMY.value,
    )
    state: Mapped[GenerationState] = mapped_column(
        _db_enum(GenerationState, "curriculum_generation_state"),
        nullable=False,
        default=GenerationState.QUEUED,
        server_default=GenerationState.QUEUED.value,
    )
    priority: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    input_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    input_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    checkpoints_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )
    pipeline_version: Mapped[str] = mapped_column(String(100), nullable=False)
    attempts: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    max_attempts: Mapped[int] = mapped_column(
        Integer, nullable=False, default=3, server_default="3"
    )
    repair_attempts: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    max_repairs: Mapped[int] = mapped_column(
        Integer, nullable=False, default=2, server_default="2"
    )
    lease_owner: Mapped[str | None] = mapped_column(String(160), nullable=True)
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    heartbeat_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_error_code: Mapped[str | None] = mapped_column(String(100), nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    budget_limit_usd: Mapped[Decimal] = mapped_column(
        Numeric(12, 6),
        nullable=False,
        default=Decimal("0"),
        server_default="0",
    )
    estimated_cost_usd: Mapped[Decimal] = mapped_column(
        Numeric(12, 6),
        nullable=False,
        default=Decimal("0"),
        server_default="0",
    )
    cost_usd: Mapped[Decimal] = mapped_column(
        Numeric(12, 6),
        nullable=False,
        default=Decimal("0"),
        server_default="0",
    )
    input_tokens: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    cached_input_tokens: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default="0",
    )
    output_tokens: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    model_usage_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )

    skill: Mapped[CurriculumSkill] = relationship("CurriculumSkill")
    module: Mapped[CanonicalModule | None] = relationship(
        "CanonicalModule",
        foreign_keys=[module_id],
    )
    module_version: Mapped[CanonicalModuleVersion | None] = relationship(
        "CanonicalModuleVersion",
        foreign_keys=[module_version_id],
    )
    quality_reports: Mapped[list[ModuleQualityReport]] = relationship(
        "ModuleQualityReport",
        back_populates="generation_job",
        lazy="selectin",
        # The append-only trigger only permits the nested FK action emitted by
        # PostgreSQL.  Never have the ORM null this relationship directly,
        # even when the select-in collection is already loaded.
        passive_deletes="all",
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("stage", GenerationStage.TAXONOMY)
        kwargs.setdefault("state", GenerationState.QUEUED)
        kwargs.setdefault("priority", 0)
        kwargs.setdefault("checkpoints_json", {})
        kwargs.setdefault("attempts", 0)
        kwargs.setdefault("max_attempts", 3)
        kwargs.setdefault("repair_attempts", 0)
        kwargs.setdefault("max_repairs", 2)
        kwargs.setdefault("budget_limit_usd", Decimal("0"))
        kwargs.setdefault("estimated_cost_usd", Decimal("0"))
        kwargs.setdefault("cost_usd", Decimal("0"))
        kwargs.setdefault("input_tokens", 0)
        kwargs.setdefault("cached_input_tokens", 0)
        kwargs.setdefault("output_tokens", 0)
        kwargs.setdefault("model_usage_json", {})
        super().__init__(**kwargs)


class ModuleQualityReport(Base, UUIDMixin, TimestampMixin):
    """Independent quality-gate result pinned to an exact content hash."""

    __tablename__ = "module_quality_reports"
    __table_args__ = (
        UniqueConstraint(
            "module_version_id",
            "review_type",
            "attempt",
            name="uq_module_quality_reports_review_attempt",
        ),
        Index(
            "ix_module_quality_reports_version_verdict",
            "module_version_id",
            "verdict",
        ),
        CheckConstraint("attempt > 0", name="ck_module_quality_reports_attempt"),
        CheckConstraint(
            "score IS NULL OR (score >= 0 AND score <= 1)",
            name="ck_module_quality_reports_score",
        ),
        CheckConstraint(
            f"reviewed_content_hash ~ '{SHA256_PATTERN}'",
            name="ck_module_quality_reports_content_hash_sha256",
        ),
    )

    module_version_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("canonical_module_versions.id", ondelete="RESTRICT"),
        nullable=False,
    )
    generation_job_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("curriculum_generation_jobs.id", ondelete="SET NULL"),
        nullable=True,
    )
    review_type: Mapped[QualityReviewType] = mapped_column(
        _db_enum(QualityReviewType, "module_quality_review_type"),
        nullable=False,
    )
    verdict: Mapped[QualityVerdict] = mapped_column(
        _db_enum(QualityVerdict, "module_quality_verdict"),
        nullable=False,
    )
    score: Mapped[float | None] = mapped_column(Float, nullable=True)
    attempt: Mapped[int] = mapped_column(
        Integer, nullable=False, default=1, server_default="1"
    )
    reviewed_content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    issues_json: Mapped[list] = mapped_column(
        JSONB,
        nullable=False,
        default=list,
        server_default=text("'[]'::jsonb"),
    )
    evidence_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )
    deterministic_checks_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )
    repair_instructions_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    reviewer_model: Mapped[str | None] = mapped_column(String(120), nullable=True)
    prompt_version: Mapped[str | None] = mapped_column(String(100), nullable=True)

    module_version: Mapped[CanonicalModuleVersion] = relationship(
        "CanonicalModuleVersion",
        back_populates="quality_reports",
    )
    generation_job: Mapped[CurriculumGenerationJob | None] = relationship(
        "CurriculumGenerationJob",
        back_populates="quality_reports",
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("attempt", 1)
        kwargs.setdefault("issues_json", [])
        kwargs.setdefault("evidence_json", {})
        kwargs.setdefault("deterministic_checks_json", {})
        super().__init__(**kwargs)


class MentorEvidenceClaim(Base, UUIDMixin, TimestampUpdateMixin):
    """One source-backed mentor fact that may be composed into relevant lessons."""

    __tablename__ = "mentor_evidence_claims"
    __table_args__ = (
        UniqueConstraint(
            "idol_id",
            "normalized_hash",
            "source_hash",
            name="uq_mentor_evidence_claims_idol_claim_source",
        ),
        Index(
            "ix_mentor_evidence_claims_idol_status_type",
            "idol_id",
            "verification_status",
            "claim_type",
        ),
        CheckConstraint(
            f"normalized_hash ~ '{SHA256_PATTERN}'",
            name="ck_mentor_evidence_claims_normalized_hash_sha256",
        ),
        CheckConstraint(
            f"source_hash ~ '{SHA256_PATTERN}'",
            name="ck_mentor_evidence_claims_source_hash_sha256",
        ),
        CheckConstraint(
            "confidence >= 0 AND confidence <= 1",
            name="ck_mentor_evidence_claims_confidence",
        ),
        CheckConstraint(
            "source_chunk_id IS NOT NULL OR source_url IS NOT NULL",
            name="ck_mentor_evidence_claims_provenance",
        ),
        CheckConstraint(
            "(verification_status <> 'verified' OR verified_at IS NOT NULL) AND "
            "(verification_status <> 'revoked' OR "
            "(revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))",
            name="ck_mentor_evidence_claims_lifecycle",
        ),
        CheckConstraint(
            f"((verification_status IN ('pending', 'rejected') AND verified_at IS NULL) OR "
            "(verification_status IN ('verified', 'revoked') AND verified_at IS NOT NULL)) AND "
            "((verification_status <> 'revoked' AND revoked_at IS NULL AND "
            "revocation_reason IS NULL) OR "
            "(verification_status = 'revoked' AND revoked_at IS NOT NULL AND "
            "NULLIF(btrim(COALESCE(revocation_reason, ''), "
            f"{PYTHON_STRIP_CHARACTERS_SQL}), '') IS NOT NULL))",
            name="ck_mentor_evidence_claims_audit_shape",
        ),
    )

    idol_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("idols.id", ondelete="CASCADE"),
        nullable=False,
    )
    claim_type: Mapped[MentorClaimType] = mapped_column(
        _db_enum(MentorClaimType, "mentor_claim_type"),
        nullable=False,
    )
    claim_text: Mapped[str] = mapped_column(Text, nullable=False)
    normalized_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    source_chunk_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("source_chunks.id", ondelete="RESTRICT"),
        nullable=True,
    )
    source_title: Mapped[str | None] = mapped_column(String(500), nullable=True)
    source_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    evidence_excerpt: Mapped[str] = mapped_column(Text, nullable=False)
    evidence_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )
    source_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    skill_tags_json: Mapped[list] = mapped_column(
        JSONB,
        nullable=False,
        default=list,
        server_default=text("'[]'::jsonb"),
    )
    confidence: Mapped[float] = mapped_column(Float, nullable=False)
    verification_status: Mapped[EvidenceVerificationStatus] = mapped_column(
        _db_enum(EvidenceVerificationStatus, "evidence_verification_status"),
        nullable=False,
        default=EvidenceVerificationStatus.PENDING,
        server_default=EvidenceVerificationStatus.PENDING.value,
    )
    valid_from: Mapped[date | None] = mapped_column(Date, nullable=True)
    valid_to: Mapped[date | None] = mapped_column(Date, nullable=True)
    verified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    revocation_reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    idol: Mapped[Idol] = relationship("Idol")
    source_chunk: Mapped[SourceChunk | None] = relationship("SourceChunk")
    skills: Mapped[list[CurriculumSkill]] = relationship(
        "CurriculumSkill",
        secondary=mentor_evidence_claim_skills,
        back_populates="mentor_claims",
        lazy="selectin",
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("evidence_json", {})
        kwargs.setdefault("skill_tags_json", [])
        kwargs.setdefault("verification_status", EvidenceVerificationStatus.PENDING)
        super().__init__(**kwargs)


class LearnerSkillState(Base, UUIDMixin, TimestampUpdateMixin):
    """Current demonstrated learner state used to build a pinned lesson brief."""

    __tablename__ = "learner_skill_states"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "skill_id", name="uq_learner_skill_states_user_skill"
        ),
        Index(
            "ix_learner_skill_states_user_mastery",
            "user_id",
            "mastery_status",
        ),
        CheckConstraint("state_version > 0", name="ck_learner_skill_states_version"),
        CheckConstraint(
            "mastery_score IS NULL OR (mastery_score >= 0 AND mastery_score <= 1)",
            name="ck_learner_skill_states_mastery_score",
        ),
        CheckConstraint(
            f"state_hash IS NULL OR state_hash ~ '{SHA256_PATTERN}'",
            name="ck_learner_skill_states_state_hash_sha256",
        ),
    )

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    skill_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
        nullable=False,
    )
    current_level: Mapped[SkillLevel] = mapped_column(
        _db_enum(SkillLevel, "curriculum_skill_level"),
        nullable=False,
        default=SkillLevel.UNKNOWN,
        server_default=SkillLevel.UNKNOWN.value,
    )
    mastery_status: Mapped[LearnerMasteryStatus] = mapped_column(
        _db_enum(LearnerMasteryStatus, "learner_mastery_status"),
        nullable=False,
        default=LearnerMasteryStatus.UNASSESSED,
        server_default=LearnerMasteryStatus.UNASSESSED.value,
    )
    mastery_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    state_version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=1, server_default="1"
    )
    strengths_json: Mapped[list] = mapped_column(
        JSONB,
        nullable=False,
        default=list,
        server_default=text("'[]'::jsonb"),
    )
    gaps_json: Mapped[list] = mapped_column(
        JSONB,
        nullable=False,
        default=list,
        server_default=text("'[]'::jsonb"),
    )
    misconceptions_json: Mapped[list] = mapped_column(
        JSONB,
        nullable=False,
        default=list,
        server_default=text("'[]'::jsonb"),
    )
    evidence_json: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default=text("'{}'::jsonb"),
    )
    state_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    assessed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    user: Mapped[User] = relationship("User")
    skill: Mapped[CurriculumSkill] = relationship("CurriculumSkill")
    personalized_lessons: Mapped[list[PersonalizedLessonVersion]] = relationship(
        "PersonalizedLessonVersion",
        back_populates="learner_state",
        lazy="selectin",
        # PostgreSQL owns learner_state_id ON DELETE SET NULL. In particular,
        # READY snapshots must pass through the narrowly-scoped RI exception in
        # the database guard instead of an ORM-emitted direct UPDATE.
        passive_deletes="all",
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("current_level", SkillLevel.UNKNOWN)
        kwargs.setdefault("mastery_status", LearnerMasteryStatus.UNASSESSED)
        kwargs.setdefault("state_version", 1)
        kwargs.setdefault("strengths_json", [])
        kwargs.setdefault("gaps_json", [])
        kwargs.setdefault("misconceptions_json", [])
        kwargs.setdefault("evidence_json", {})
        super().__init__(**kwargs)


class PersonalizedLessonVersion(Base, UUIDMixin, TimestampMixin):
    """Complete personalized reader artifact pinned to one canonical session."""

    __tablename__ = "personalized_lesson_versions"
    __table_args__ = (
        ForeignKeyConstraint(
            ["module_session_id", "module_version_id"],
            ["module_sessions.id", "module_sessions.module_version_id"],
            name="fk_personalized_lessons_pinned_session",
            ondelete="RESTRICT",
        ),
        UniqueConstraint(
            "id",
            "module_session_id",
            name="uq_personalized_lessons_id_session",
        ),
        UniqueConstraint(
            "user_id",
            "module_session_id",
            "version_number",
            name="uq_personalized_lessons_user_session_version",
        ),
        UniqueConstraint(
            "user_id",
            "input_hash",
            name="uq_personalized_lessons_user_input_hash",
        ),
        Index(
            "ix_personalized_lessons_user_status",
            "user_id",
            "status",
        ),
        Index(
            "ix_personalized_lessons_ready_mentor_evidence",
            "content_json",
            postgresql_using="gin",
            postgresql_ops={"content_json": "jsonb_path_ops"},
            postgresql_where=text("status = 'ready' AND revoked_at IS NULL"),
        ),
        CheckConstraint("version_number > 0", name="ck_personalized_lessons_version"),
        CheckConstraint(
            "estimated_minutes > 0", name="ck_personalized_lessons_minutes"
        ),
        CheckConstraint(
            f"input_hash ~ '{SHA256_PATTERN}'",
            name="ck_personalized_lessons_input_hash_sha256",
        ),
        CheckConstraint(
            f"learner_state_hash ~ '{SHA256_PATTERN}'",
            name="ck_personalized_lessons_state_hash_sha256",
        ),
        CheckConstraint(
            f"mentor_evidence_hash ~ '{SHA256_PATTERN}'",
            name="ck_personalized_lessons_mentor_hash_sha256",
        ),
        CheckConstraint(
            f"content_hash IS NULL OR content_hash ~ '{SHA256_PATTERN}'",
            name="ck_personalized_lessons_content_hash_sha256",
        ),
        CheckConstraint(
            "(status <> 'ready' OR "
            "(content_json IS NOT NULL AND content_hash IS NOT NULL AND ready_at IS NOT NULL)) AND "
            "(status <> 'failed' OR last_error IS NOT NULL) AND "
            "(status <> 'revoked' OR (revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))",
            name="ck_personalized_lessons_lifecycle",
        ),
        CheckConstraint(
            f"((status IN ('queued', 'generating', 'failed') AND ready_at IS NULL) OR "
            "(status IN ('ready', 'revoked') AND ready_at IS NOT NULL)) AND "
            "((status <> 'revoked' AND revoked_at IS NULL AND revocation_reason IS NULL) OR "
            "(status = 'revoked' AND revoked_at IS NOT NULL AND "
            "NULLIF(btrim(COALESCE(revocation_reason, ''), "
            f"{PYTHON_STRIP_CHARACTERS_SQL}), '') IS NOT NULL AND "
            "content_json IS NOT NULL AND content_hash IS NOT NULL))",
            name="ck_personalized_lessons_audit_shape",
        ),
    )

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    module_session_id: Mapped[str] = mapped_column(UUID(as_uuid=False), nullable=False)
    module_version_id: Mapped[str] = mapped_column(UUID(as_uuid=False), nullable=False)
    learner_state_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("learner_skill_states.id", ondelete="SET NULL"),
        nullable=True,
    )
    version_number: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[PersonalizedLessonStatus] = mapped_column(
        _db_enum(PersonalizedLessonStatus, "personalized_lesson_status"),
        nullable=False,
        default=PersonalizedLessonStatus.QUEUED,
        server_default=PersonalizedLessonStatus.QUEUED.value,
    )
    learner_state_snapshot_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    learner_state_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    mentor_evidence_snapshot_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    mentor_evidence_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    personalization_brief_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    input_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    content_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    content_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    estimated_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    prompt_version: Mapped[str] = mapped_column(String(100), nullable=False)
    model_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    ready_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    revocation_reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    user: Mapped[User] = relationship("User")
    module_session: Mapped[ModuleSession] = relationship(
        "ModuleSession",
        back_populates="personalized_versions",
        foreign_keys=[module_session_id, module_version_id],
    )
    learner_state: Mapped[LearnerSkillState | None] = relationship(
        "LearnerSkillState",
        back_populates="personalized_lessons",
    )
    assignments: Mapped[list[PlanLessonAssignment]] = relationship(
        "PlanLessonAssignment",
        back_populates="personalized_lesson_version",
        lazy="selectin",
        viewonly=True,
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("status", PersonalizedLessonStatus.QUEUED)
        super().__init__(**kwargs)


class PlanLessonAssignment(Base, UUIDMixin, TimestampUpdateMixin):
    """A scheduled session pinned to immutable catalog/personalized versions."""

    __tablename__ = "plan_lesson_assignments"
    __table_args__ = (
        ForeignKeyConstraint(
            ["personalized_lesson_version_id", "module_session_id"],
            [
                "personalized_lesson_versions.id",
                "personalized_lesson_versions.module_session_id",
            ],
            name="fk_plan_lesson_assignments_personalized_session",
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "plan_id",
            "week_number",
            "position",
            name="uq_plan_lesson_assignments_week_position",
        ),
        Index(
            "uq_plan_lesson_assignments_plan_session",
            "plan_id",
            "module_session_id",
            unique=True,
            postgresql_where=text("status NOT IN ('skipped', 'replaced')"),
        ),
        Index(
            "ix_plan_lesson_assignments_plan_status",
            "plan_id",
            "status",
        ),
        Index(
            "ix_plan_lesson_assignments_session",
            "module_session_id",
        ),
        # Mirrors ix_plan_lesson_assignments_plan_item in the migration. The runtime
        # readiness check filters on plan_item_id alone, which the plan_id-leading
        # index above cannot serve.
        Index(
            "ix_plan_lesson_assignments_plan_item",
            "plan_item_id",
            postgresql_where=text("plan_item_id IS NOT NULL"),
        ),
        CheckConstraint("week_number > 0", name="ck_plan_lesson_assignments_week"),
        CheckConstraint("position > 0", name="ck_plan_lesson_assignments_position"),
        CheckConstraint(
            "allocated_minutes > 0",
            name="ck_plan_lesson_assignments_allocated_minutes",
        ),
        CheckConstraint(
            "match_score IS NULL OR (match_score >= 0 AND match_score <= 1)",
            name="ck_plan_lesson_assignments_match_score",
        ),
        CheckConstraint(
            "status NOT IN ('available', 'in_progress', 'completed') OR "
            "personalized_lesson_version_id IS NOT NULL",
            name="ck_plan_lesson_assignments_personalized_visibility",
        ),
        CheckConstraint(
            "status <> 'available' OR available_at IS NOT NULL",
            name="ck_plan_lesson_assignments_available_at",
        ),
    )

    plan_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plans.id", ondelete="CASCADE"),
        nullable=False,
    )
    plan_item_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plan_items.id", ondelete="SET NULL"),
        nullable=True,
    )
    module_session_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("module_sessions.id", ondelete="RESTRICT"),
        nullable=False,
    )
    personalized_lesson_version_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        nullable=True,
    )
    week_number: Mapped[int] = mapped_column(Integer, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    allocated_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[AssignmentStatus] = mapped_column(
        _db_enum(AssignmentStatus, "plan_lesson_assignment_status"),
        nullable=False,
        default=AssignmentStatus.SCHEDULED,
        server_default=AssignmentStatus.SCHEDULED.value,
    )
    comparison_gap_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    match_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    match_reason: Mapped[str] = mapped_column(Text, nullable=False)
    available_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    replaced_by_assignment_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("plan_lesson_assignments.id", ondelete="SET NULL"),
        nullable=True,
    )

    plan: Mapped[Plan] = relationship("Plan")
    plan_item: Mapped[PlanItem | None] = relationship("PlanItem")
    module_session: Mapped[ModuleSession] = relationship("ModuleSession")
    personalized_lesson_version: Mapped[PersonalizedLessonVersion | None] = (
        relationship(
            "PersonalizedLessonVersion",
            back_populates="assignments",
            foreign_keys=[personalized_lesson_version_id, module_session_id],
            viewonly=True,
        )
    )
    replaced_by_assignment: Mapped[PlanLessonAssignment | None] = relationship(
        "PlanLessonAssignment",
        remote_side="PlanLessonAssignment.id",
        foreign_keys=[replaced_by_assignment_id],
    )

    def __init__(self, **kwargs) -> None:
        kwargs.setdefault("status", AssignmentStatus.SCHEDULED)
        super().__init__(**kwargs)


@event.listens_for(PlanLessonAssignment, "before_update")
def _protect_terminal_assignment_status(_mapper, _connection, target) -> None:
    """Prevent a skipped/replaced assignment status from being resurrected."""

    status_history = sa_inspect(target).attrs.status.history
    if not status_history.has_changes() or not status_history.deleted:
        return
    previous_status = AssignmentStatus(status_history.deleted[0])
    current_status = AssignmentStatus(target.status)
    if previous_status in {AssignmentStatus.SKIPPED, AssignmentStatus.REPLACED}:
        raise ValueError(
            "Terminal PlanLessonAssignment status is immutable; "
            f"cannot transition {previous_status.value} to {current_status.value}"
        )


def _protect_lifecycle_audit_fields(
    target,
    state,
    *,
    status_field: str,
    final_status: Enum,
    finalized_at_field: str,
    revoked_status: Enum,
    label: str,
) -> None:
    """Allow audit timestamps only on their exact lifecycle transition."""

    status_history = state.attrs[status_field].history
    status_changed = bool(
        status_history.has_changes() and status_history.deleted and status_history.added
    )
    old_status = (
        type(final_status)(status_history.deleted[0])
        if status_history.deleted
        else type(final_status)(getattr(target, status_field))
    )
    new_status = type(final_status)(getattr(target, status_field))

    finalized_history = state.attrs[finalized_at_field].history
    old_finalized_at = (
        finalized_history.deleted[0]
        if finalized_history.deleted
        else (
            None
            if finalized_history.has_changes()
            else getattr(target, finalized_at_field)
        )
    )
    transitions_to_final = (
        status_changed and old_status != final_status and new_status == final_status
    )
    valid_finalization = (
        transitions_to_final
        and finalized_history.has_changes()
        and old_finalized_at is None
        and getattr(target, finalized_at_field) is not None
    )
    if finalized_history.has_changes() and not valid_finalization:
        raise ValueError(f"{label} lifecycle audit fields are immutable")
    if transitions_to_final and not valid_finalization:
        raise ValueError(
            f"{label} must set {finalized_at_field} exactly when it is finalized"
        )

    revoked_at_history = state.attrs.revoked_at.history
    reason_history = state.attrs.revocation_reason.history
    old_revoked_at = (
        revoked_at_history.deleted[0]
        if revoked_at_history.deleted
        else (None if revoked_at_history.has_changes() else target.revoked_at)
    )
    old_reason = (
        reason_history.deleted[0]
        if reason_history.deleted
        else (None if reason_history.has_changes() else target.revocation_reason)
    )
    transitions_to_revoked = (
        status_changed and old_status == final_status and new_status == revoked_status
    )
    valid_revocation = (
        transitions_to_revoked
        and revoked_at_history.has_changes()
        and reason_history.has_changes()
        and old_revoked_at is None
        and old_reason is None
        and target.revoked_at is not None
        and bool(str(target.revocation_reason or "").strip())
    )
    if (
        revoked_at_history.has_changes() or reason_history.has_changes()
    ) and not valid_revocation:
        raise ValueError(f"{label} lifecycle audit fields are immutable")
    if transitions_to_revoked and not valid_revocation:
        raise ValueError(
            f"{label} must set revoked_at and revocation_reason exactly when revoked"
        )


_CANONICAL_VERSION_PROTECTED_FIELDS = frozenset(
    {
        "module_id",
        "version_number",
        "supersedes_version_id",
        "content_json",
        "source_manifest_json",
        "technique_plan_json",
        "content_hash",
        "source_hash",
        "estimated_minutes",
        "quality_score",
        "prompt_version",
        "gate_version",
        "model_name",
        "retrieval_metadata_json",
        "retrieval_metadata_hash",
    }
)


@event.listens_for(CanonicalModuleVersion, "before_update")
def _protect_published_canonical_content(_mapper, _connection, target) -> None:
    """Keep published content append-only while allowing draft assembly."""

    state = sa_inspect(target)
    status_history = state.attrs.status.history
    _protect_lifecycle_audit_fields(
        target,
        state,
        status_field="status",
        final_status=VersionStatus.PUBLISHED,
        finalized_at_field="published_at",
        revoked_status=VersionStatus.REVOKED,
        label="CanonicalModuleVersion",
    )
    previous_status = (
        VersionStatus(status_history.deleted[0])
        if status_history.deleted
        else VersionStatus(target.status)
    )
    changed = {
        field
        for field in _CANONICAL_VERSION_PROTECTED_FIELDS
        if state.attrs[field].history.has_changes()
    }
    if changed and previous_status in {VersionStatus.PUBLISHED, VersionStatus.REVOKED}:
        names = ", ".join(sorted(changed))
        raise ValueError(
            "Published CanonicalModuleVersion content is append-only; "
            f"create a new version to change: {names}"
        )

    if not status_history.has_changes() or not status_history.deleted:
        return
    old_status = VersionStatus(status_history.deleted[0])
    new_status = VersionStatus(status_history.added[0])
    allowed = {
        VersionStatus.DRAFT: {VersionStatus.IN_REVIEW, VersionStatus.PUBLISHED},
        VersionStatus.IN_REVIEW: {VersionStatus.DRAFT, VersionStatus.PUBLISHED},
        VersionStatus.PUBLISHED: {VersionStatus.REVOKED},
        VersionStatus.REVOKED: set(),
    }
    if new_status not in allowed[old_status]:
        raise ValueError(
            f"Invalid canonical version transition: {old_status} -> {new_status}"
        )


@event.listens_for(CanonicalModuleVersion, "before_delete")
def _prevent_canonical_version_delete(_mapper, _connection, _target) -> None:
    raise ValueError(
        "CanonicalModuleVersion rows are append-only and cannot be deleted"
    )


_TECHNIQUE_VERSION_PROTECTED_FIELDS = frozenset(
    {
        "technique_key",
        "version_number",
        "title",
        "summary",
        "evidence_level",
        "appropriate_for_json",
        "conditions_json",
        "implementation_contract_json",
        "limitations_json",
        "source_manifest_json",
        "content_hash",
        "source_hash",
        "reviewed_at",
    }
)


@event.listens_for(LearningTechniqueVersion, "before_update")
def _protect_published_technique_content(_mapper, _connection, target) -> None:
    state = sa_inspect(target)
    status_history = state.attrs.status.history
    _protect_lifecycle_audit_fields(
        target,
        state,
        status_field="status",
        final_status=VersionStatus.PUBLISHED,
        finalized_at_field="published_at",
        revoked_status=VersionStatus.REVOKED,
        label="LearningTechniqueVersion",
    )
    previous_status = (
        VersionStatus(status_history.deleted[0])
        if status_history.deleted
        else VersionStatus(target.status)
    )
    changed = {
        field
        for field in _TECHNIQUE_VERSION_PROTECTED_FIELDS
        if state.attrs[field].history.has_changes()
    }
    if changed and previous_status in {VersionStatus.PUBLISHED, VersionStatus.REVOKED}:
        names = ", ".join(sorted(changed))
        raise ValueError(
            "Published LearningTechniqueVersion content is append-only; "
            f"create a new version to change: {names}"
        )

    if not status_history.has_changes() or not status_history.deleted:
        return
    old_status = VersionStatus(status_history.deleted[0])
    new_status = VersionStatus(status_history.added[0])
    allowed = {
        VersionStatus.DRAFT: {VersionStatus.IN_REVIEW, VersionStatus.PUBLISHED},
        VersionStatus.IN_REVIEW: {VersionStatus.DRAFT, VersionStatus.PUBLISHED},
        VersionStatus.PUBLISHED: {VersionStatus.REVOKED},
        VersionStatus.REVOKED: set(),
    }
    if new_status not in allowed[old_status]:
        raise ValueError(
            f"Invalid technique version transition: {old_status} -> {new_status}"
        )


@event.listens_for(LearningTechniqueVersion, "before_delete")
def _prevent_technique_version_delete(_mapper, _connection, _target) -> None:
    raise ValueError(
        "LearningTechniqueVersion rows are append-only and cannot be deleted"
    )


@event.listens_for(ModuleSession, "before_insert")
@event.listens_for(ModuleSession, "before_update")
def _protect_published_module_session(_mapper, connection, target) -> None:
    parent = target.__dict__.get("module_version")
    if parent is not None:
        parent_status = VersionStatus(parent.status)
    else:
        parent_status = VersionStatus(
            connection.execute(
                select(CanonicalModuleVersion.status).where(
                    CanonicalModuleVersion.id == target.module_version_id
                )
            ).scalar_one()
        )
    if parent_status in {VersionStatus.PUBLISHED, VersionStatus.REVOKED}:
        raise ValueError(
            "Sessions of a published CanonicalModuleVersion are immutable; "
            "create a new module version"
        )


@event.listens_for(ModuleSession, "before_delete")
def _protect_published_module_session_delete(_mapper, connection, target) -> None:
    _protect_published_module_session(_mapper, connection, target)


_PERSONALIZED_LESSON_PROTECTED_FIELDS = frozenset(
    {
        "user_id",
        "module_session_id",
        "module_version_id",
        "learner_state_id",
        "version_number",
        "learner_state_snapshot_json",
        "learner_state_hash",
        "mentor_evidence_snapshot_json",
        "mentor_evidence_hash",
        "personalization_brief_json",
        "input_hash",
        "content_json",
        "content_hash",
        "estimated_minutes",
        "prompt_version",
        "model_name",
    }
)


@event.listens_for(PersonalizedLessonVersion, "before_update")
def _protect_ready_personalized_lesson(_mapper, _connection, target) -> None:
    state = sa_inspect(target)
    status_history = state.attrs.status.history
    _protect_lifecycle_audit_fields(
        target,
        state,
        status_field="status",
        final_status=PersonalizedLessonStatus.READY,
        finalized_at_field="ready_at",
        revoked_status=PersonalizedLessonStatus.REVOKED,
        label="PersonalizedLessonVersion",
    )
    previous_status = (
        PersonalizedLessonStatus(status_history.deleted[0])
        if status_history.deleted
        else PersonalizedLessonStatus(target.status)
    )
    changed = {
        field
        for field in _PERSONALIZED_LESSON_PROTECTED_FIELDS
        if state.attrs[field].history.has_changes()
    }
    if changed and previous_status in {
        PersonalizedLessonStatus.READY,
        PersonalizedLessonStatus.REVOKED,
    }:
        names = ", ".join(sorted(changed))
        raise ValueError(
            "Ready PersonalizedLessonVersion content is immutable; "
            f"create a new version to change: {names}"
        )

    if not status_history.has_changes() or not status_history.deleted:
        return
    old_status = PersonalizedLessonStatus(status_history.deleted[0])
    new_status = PersonalizedLessonStatus(status_history.added[0])
    allowed = {
        PersonalizedLessonStatus.QUEUED: {
            PersonalizedLessonStatus.GENERATING,
            PersonalizedLessonStatus.FAILED,
        },
        PersonalizedLessonStatus.GENERATING: {
            PersonalizedLessonStatus.READY,
            PersonalizedLessonStatus.FAILED,
        },
        PersonalizedLessonStatus.FAILED: {
            PersonalizedLessonStatus.QUEUED,
            PersonalizedLessonStatus.GENERATING,
        },
        PersonalizedLessonStatus.READY: {PersonalizedLessonStatus.REVOKED},
        PersonalizedLessonStatus.REVOKED: set(),
    }
    if new_status not in allowed[old_status]:
        raise ValueError(
            f"Invalid personalized lesson transition: {old_status} -> {new_status}"
        )


@event.listens_for(PersonalizedLessonVersion, "before_delete")
def _protect_ready_personalized_lesson_delete(_mapper, _connection, target) -> None:
    if PersonalizedLessonStatus(target.status) in {
        PersonalizedLessonStatus.READY,
        PersonalizedLessonStatus.REVOKED,
    }:
        raise ValueError(
            "Ready PersonalizedLessonVersion rows are immutable; revoke them instead"
        )


@event.listens_for(ModuleQualityReport, "before_update")
@event.listens_for(ModuleQualityReport, "before_delete")
def _protect_quality_report(_mapper, _connection, _target) -> None:
    raise ValueError("ModuleQualityReport rows are append-only")


_MENTOR_CLAIM_PROTECTED_FIELDS = frozenset(
    {
        "idol_id",
        "claim_type",
        "claim_text",
        "normalized_hash",
        "source_chunk_id",
        "source_title",
        "source_url",
        "evidence_excerpt",
        "evidence_json",
        "source_hash",
        "skill_tags_json",
        "confidence",
        "valid_from",
        "valid_to",
    }
)


@event.listens_for(MentorEvidenceClaim, "before_update")
def _protect_verified_mentor_claim(_mapper, _connection, target) -> None:
    state = sa_inspect(target)
    status_history = state.attrs.verification_status.history
    _protect_lifecycle_audit_fields(
        target,
        state,
        status_field="verification_status",
        final_status=EvidenceVerificationStatus.VERIFIED,
        finalized_at_field="verified_at",
        revoked_status=EvidenceVerificationStatus.REVOKED,
        label="MentorEvidenceClaim",
    )
    previous_status = (
        EvidenceVerificationStatus(status_history.deleted[0])
        if status_history.deleted
        else EvidenceVerificationStatus(target.verification_status)
    )
    changed = {
        field
        for field in _MENTOR_CLAIM_PROTECTED_FIELDS
        if state.attrs[field].history.has_changes()
    }
    if changed and previous_status is not EvidenceVerificationStatus.PENDING:
        names = ", ".join(sorted(changed))
        raise ValueError(
            "Verified MentorEvidenceClaim evidence is immutable; "
            f"create a new claim to change: {names}"
        )

    if not status_history.has_changes() or not status_history.deleted:
        return
    old_status = EvidenceVerificationStatus(status_history.deleted[0])
    new_status = EvidenceVerificationStatus(status_history.added[0])
    allowed = {
        EvidenceVerificationStatus.PENDING: {
            EvidenceVerificationStatus.VERIFIED,
            EvidenceVerificationStatus.REJECTED,
        },
        EvidenceVerificationStatus.VERIFIED: {
            EvidenceVerificationStatus.REVOKED,
        },
        EvidenceVerificationStatus.REJECTED: set(),
        EvidenceVerificationStatus.REVOKED: set(),
    }
    if new_status not in allowed[old_status]:
        raise ValueError(
            f"Invalid mentor evidence transition: {old_status} -> {new_status}"
        )


@event.listens_for(MentorEvidenceClaim, "before_delete")
def _protect_finalized_mentor_claim_delete(_mapper, _connection, target) -> None:
    if (
        EvidenceVerificationStatus(target.verification_status)
        is not EvidenceVerificationStatus.PENDING
    ):
        raise ValueError("Finalized MentorEvidenceClaim rows are append-only")
