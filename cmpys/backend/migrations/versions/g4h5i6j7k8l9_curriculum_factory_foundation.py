"""add evidence-based curriculum factory foundation

Revision ID: g4h5i6j7k8l9
Revises: f3g4h5i6j7k8

The upgrade is additive: it creates new catalog, evidence, generation, learner,
and assignment tables without changing existing lesson or plan data.
"""

from typing import Sequence, Union

from alembic import op
from pgvector.sqlalchemy import Vector
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "g4h5i6j7k8l9"
down_revision: Union[str, None] = "f3g4h5i6j7k8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


CURRICULUM_SKILL_LEVEL = postgresql.ENUM(
    "unknown",
    "beginner",
    "intermediate",
    "advanced",
    name="curriculum_skill_level",
    create_type=False,
)
CURRICULUM_SKILL_STATUS = postgresql.ENUM(
    "draft",
    "active",
    "retired",
    name="curriculum_skill_status",
    create_type=False,
)
LEARNING_EVIDENCE_LEVEL = postgresql.ENUM(
    "strong",
    "moderate",
    "emerging",
    name="learning_evidence_level",
    create_type=False,
)
CURRICULUM_VERSION_STATUS = postgresql.ENUM(
    "draft",
    "in_review",
    "published",
    "revoked",
    name="curriculum_version_status",
    create_type=False,
)
CURRICULUM_GENERATION_STAGE = postgresql.ENUM(
    "taxonomy",
    "source_research",
    "technique_design",
    "outline",
    "writing",
    "factual_review",
    "pedagogy_review",
    "originality_review",
    "publish",
    name="curriculum_generation_stage",
    create_type=False,
)
CURRICULUM_GENERATION_STATE = postgresql.ENUM(
    "queued",
    "running",
    "retry_wait",
    "completed",
    "failed",
    "flagged",
    "cancelled",
    name="curriculum_generation_state",
    create_type=False,
)
MODULE_QUALITY_REVIEW_TYPE = postgresql.ENUM(
    "schema",
    "source_attribution",
    "factual",
    "pedagogy",
    "originality",
    "editorial",
    name="module_quality_review_type",
    create_type=False,
)
MODULE_QUALITY_VERDICT = postgresql.ENUM(
    "passed",
    "needs_repair",
    "rejected",
    name="module_quality_verdict",
    create_type=False,
)
MENTOR_CLAIM_TYPE = postgresql.ENUM(
    "recommended_book",
    "habit",
    "decision_method",
    "principle",
    "failure",
    "learning_method",
    "preference",
    name="mentor_claim_type",
    create_type=False,
)
EVIDENCE_VERIFICATION_STATUS = postgresql.ENUM(
    "pending",
    "verified",
    "rejected",
    "revoked",
    name="evidence_verification_status",
    create_type=False,
)
LEARNER_MASTERY_STATUS = postgresql.ENUM(
    "unassessed",
    "developing",
    "demonstrated",
    "mastered",
    name="learner_mastery_status",
    create_type=False,
)
PERSONALIZED_LESSON_STATUS = postgresql.ENUM(
    "queued",
    "generating",
    "ready",
    "failed",
    "revoked",
    name="personalized_lesson_status",
    create_type=False,
)
PLAN_LESSON_ASSIGNMENT_STATUS = postgresql.ENUM(
    "scheduled",
    "available",
    "in_progress",
    "completed",
    "skipped",
    "replaced",
    name="plan_lesson_assignment_status",
    create_type=False,
)


ENUMS = (
    CURRICULUM_SKILL_LEVEL,
    CURRICULUM_SKILL_STATUS,
    LEARNING_EVIDENCE_LEVEL,
    CURRICULUM_VERSION_STATUS,
    CURRICULUM_GENERATION_STAGE,
    CURRICULUM_GENERATION_STATE,
    MODULE_QUALITY_REVIEW_TYPE,
    MODULE_QUALITY_VERDICT,
    MENTOR_CLAIM_TYPE,
    EVIDENCE_VERIFICATION_STATUS,
    LEARNER_MASTERY_STATUS,
    PERSONALIZED_LESSON_STATUS,
    PLAN_LESSON_ASSIGNMENT_STATUS,
)


def _timestamps() -> tuple[sa.Column, sa.Column]:
    return (
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )


def _created_at() -> sa.Column:
    return sa.Column(
        "created_at",
        sa.DateTime(timezone=True),
        server_default=sa.func.now(),
        nullable=False,
    )


def upgrade() -> None:
    bind = op.get_bind()
    for enum in ENUMS:
        enum.create(bind, checkfirst=True)

    op.create_table(
        "curriculum_skills",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column("key", sa.String(length=160), nullable=False),
        sa.Column("domain", sa.String(length=100), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("skill_type", sa.String(length=50), nullable=False),
        sa.Column("taxonomy_version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column(
            "tags_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "status",
            CURRICULUM_SKILL_STATUS,
            nullable=False,
            server_default="draft",
        ),
        *_timestamps(),
        sa.CheckConstraint(
            "taxonomy_version > 0",
            name="ck_curriculum_skills_taxonomy_version",
        ),
        sa.UniqueConstraint("key", name="uq_curriculum_skills_key"),
    )
    op.create_index(
        "ix_curriculum_skills_domain_status",
        "curriculum_skills",
        ["domain", "status"],
    )

    op.create_table(
        "curriculum_skill_prerequisites",
        sa.Column(
            "skill_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("curriculum_skills.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "prerequisite_skill_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
            primary_key=True,
        ),
        sa.CheckConstraint(
            "skill_id <> prerequisite_skill_id",
            name="ck_curriculum_skill_prerequisite_not_self",
        ),
    )

    op.create_table(
        "learning_technique_versions",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column("technique_key", sa.String(length=120), nullable=False),
        sa.Column("version_number", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("evidence_level", LEARNING_EVIDENCE_LEVEL, nullable=False),
        sa.Column(
            "appropriate_for_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "conditions_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "implementation_contract_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column(
            "limitations_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "source_manifest_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("source_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "status",
            CURRICULUM_VERSION_STATUS,
            nullable=False,
            server_default="draft",
        ),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revocation_reason", sa.Text(), nullable=True),
        _created_at(),
        sa.CheckConstraint(
            "version_number > 0",
            name="ck_learning_technique_version_number",
        ),
        sa.CheckConstraint(
            "content_hash ~ '^[0-9a-f]{64}$'",
            name="ck_learning_technique_content_hash_sha256",
        ),
        sa.CheckConstraint(
            "source_hash ~ '^[0-9a-f]{64}$'",
            name="ck_learning_technique_source_hash_sha256",
        ),
        sa.CheckConstraint(
            "(status <> 'published' OR published_at IS NOT NULL) AND "
            "(status <> 'revoked' OR "
            "(revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))",
            name="ck_learning_technique_version_lifecycle",
        ),
        sa.UniqueConstraint(
            "technique_key",
            "version_number",
            name="uq_learning_technique_versions_key_version",
        ),
        sa.UniqueConstraint(
            "technique_key",
            "content_hash",
            name="uq_learning_technique_versions_key_content_hash",
        ),
    )
    op.create_index(
        "ix_learning_technique_versions_key_status",
        "learning_technique_versions",
        ["technique_key", "status"],
    )

    # The current-version foreign key is added after versions exist, because it
    # is intentionally circular and includes module_id to prevent cross-module
    # pointers.
    op.create_table(
        "canonical_modules",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "skill_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("key", sa.String(length=200), nullable=False),
        sa.Column("level", CURRICULUM_SKILL_LEVEL, nullable=False),
        sa.Column("language", sa.String(length=12), nullable=False, server_default="en"),
        sa.Column("title", sa.String(length=240), nullable=False),
        sa.Column("learning_outcome", sa.Text(), nullable=False),
        sa.Column("artifact_type", sa.String(length=100), nullable=False),
        sa.Column("estimated_total_minutes", sa.Integer(), nullable=False),
        sa.Column(
            "status",
            CURRICULUM_SKILL_STATUS,
            nullable=False,
            server_default="draft",
        ),
        sa.Column(
            "current_published_version_id",
            postgresql.UUID(as_uuid=False),
            nullable=True,
        ),
        *_timestamps(),
        sa.CheckConstraint(
            "level <> 'unknown'",
            name="ck_canonical_modules_known_level",
        ),
        sa.CheckConstraint(
            "estimated_total_minutes > 0",
            name="ck_canonical_modules_estimated_minutes",
        ),
        sa.CheckConstraint(
            "status <> 'active' OR current_published_version_id IS NOT NULL",
            name="ck_canonical_modules_active_version",
        ),
        sa.UniqueConstraint("key", name="uq_canonical_modules_key"),
    )
    op.create_index(
        "ix_canonical_modules_match",
        "canonical_modules",
        ["skill_id", "level", "language", "status"],
    )

    op.create_table(
        "canonical_module_versions",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "module_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("canonical_modules.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("version_number", sa.Integer(), nullable=False),
        sa.Column(
            "supersedes_version_id",
            postgresql.UUID(as_uuid=False),
            nullable=True,
        ),
        sa.Column(
            "status",
            CURRICULUM_VERSION_STATUS,
            nullable=False,
            server_default="draft",
        ),
        sa.Column(
            "content_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column(
            "source_manifest_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column(
            "technique_plan_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("source_hash", sa.String(length=64), nullable=False),
        sa.Column("embedding", Vector(1024), nullable=True),
        sa.Column(
            "retrieval_metadata_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("retrieval_metadata_hash", sa.String(length=64), nullable=False),
        sa.Column("estimated_minutes", sa.Integer(), nullable=False),
        sa.Column("quality_score", sa.Float(), nullable=True),
        sa.Column("prompt_version", sa.String(length=100), nullable=False),
        sa.Column("gate_version", sa.String(length=100), nullable=True),
        sa.Column("model_name", sa.String(length=120), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revocation_reason", sa.Text(), nullable=True),
        _created_at(),
        sa.ForeignKeyConstraint(
            ["supersedes_version_id", "module_id"],
            ["canonical_module_versions.id", "canonical_module_versions.module_id"],
            name="fk_canonical_module_versions_supersedes_same_module",
            ondelete="RESTRICT",
        ),
        sa.CheckConstraint(
            "version_number > 0",
            name="ck_canonical_module_version_number",
        ),
        sa.CheckConstraint(
            "estimated_minutes > 0",
            name="ck_canonical_module_version_minutes",
        ),
        sa.CheckConstraint(
            "quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)",
            name="ck_canonical_module_version_quality_score",
        ),
        sa.CheckConstraint(
            "content_hash ~ '^[0-9a-f]{64}$'",
            name="ck_canonical_module_version_content_hash_sha256",
        ),
        sa.CheckConstraint(
            "source_hash ~ '^[0-9a-f]{64}$'",
            name="ck_canonical_module_version_source_hash_sha256",
        ),
        sa.CheckConstraint(
            "retrieval_metadata_hash ~ '^[0-9a-f]{64}$'",
            name="ck_canonical_module_version_retrieval_hash_sha256",
        ),
        sa.CheckConstraint(
            "(status <> 'published' OR published_at IS NOT NULL) AND "
            "(status <> 'revoked' OR "
            "(revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))",
            name="ck_canonical_module_version_lifecycle",
        ),
        sa.UniqueConstraint(
            "id",
            "module_id",
            name="uq_canonical_module_versions_id_module",
        ),
        sa.UniqueConstraint(
            "module_id",
            "version_number",
            name="uq_canonical_module_versions_module_version",
        ),
        sa.UniqueConstraint(
            "module_id",
            "content_hash",
            name="uq_canonical_module_versions_module_content_hash",
        ),
    )
    op.create_index(
        "ix_canonical_module_versions_module_status",
        "canonical_module_versions",
        ["module_id", "status"],
    )
    op.execute(
        "CREATE INDEX ix_canonical_module_versions_embedding_hnsw "
        "ON canonical_module_versions USING hnsw "
        "(embedding vector_cosine_ops) WHERE embedding IS NOT NULL"
    )
    op.create_foreign_key(
        "fk_canonical_modules_current_published_version",
        "canonical_modules",
        "canonical_module_versions",
        ["current_published_version_id", "id"],
        ["id", "module_id"],
        ondelete="RESTRICT",
    )

    op.create_table(
        "module_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "module_version_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("canonical_module_versions.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(length=240), nullable=False),
        sa.Column("learning_objective", sa.Text(), nullable=False),
        sa.Column("estimated_minutes", sa.Integer(), nullable=False),
        sa.Column(
            "content_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column(
            "assessment_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column(
            "artifact_spec_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column(
            "technique_plan_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        _created_at(),
        sa.CheckConstraint("position > 0", name="ck_module_sessions_position"),
        sa.CheckConstraint(
            "estimated_minutes > 0",
            name="ck_module_sessions_minutes",
        ),
        sa.CheckConstraint(
            "content_hash ~ '^[0-9a-f]{64}$'",
            name="ck_module_sessions_content_hash_sha256",
        ),
        sa.UniqueConstraint(
            "module_version_id",
            "position",
            name="uq_module_sessions_version_position",
        ),
        sa.UniqueConstraint(
            "id",
            "module_version_id",
            name="uq_module_sessions_id_version",
        ),
    )

    op.create_table(
        "curriculum_generation_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "skill_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "module_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("canonical_modules.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column(
            "module_version_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("canonical_module_versions.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column("target_version_number", sa.Integer(), nullable=True),
        sa.Column(
            "stage",
            CURRICULUM_GENERATION_STAGE,
            nullable=False,
            server_default="taxonomy",
        ),
        sa.Column(
            "state",
            CURRICULUM_GENERATION_STATE,
            nullable=False,
            server_default="queued",
        ),
        sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("input_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "input_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column(
            "checkpoints_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("pipeline_version", sa.String(length=100), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("max_attempts", sa.Integer(), nullable=False, server_default="3"),
        sa.Column("repair_attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("max_repairs", sa.Integer(), nullable=False, server_default="2"),
        sa.Column("lease_owner", sa.String(length=160), nullable=True),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("heartbeat_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_error_code", sa.String(length=100), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("budget_limit_usd", sa.Numeric(12, 6), nullable=True),
        sa.Column(
            "estimated_cost_usd",
            sa.Numeric(12, 6),
            nullable=False,
            server_default="0",
        ),
        sa.Column("cost_usd", sa.Numeric(12, 6), nullable=False, server_default="0"),
        sa.Column("input_tokens", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "cached_input_tokens",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column("output_tokens", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "model_usage_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        *_timestamps(),
        sa.CheckConstraint(
            "input_hash ~ '^[0-9a-f]{64}$'",
            name="ck_curriculum_generation_jobs_input_hash_sha256",
        ),
        sa.CheckConstraint(
            "attempts >= 0 AND max_attempts > 0 AND attempts <= max_attempts",
            name="ck_curriculum_generation_jobs_attempts",
        ),
        sa.CheckConstraint(
            "repair_attempts >= 0 AND max_repairs >= 0 AND repair_attempts <= max_repairs",
            name="ck_curriculum_generation_jobs_repairs",
        ),
        sa.CheckConstraint(
            "budget_limit_usd IS NULL OR budget_limit_usd >= 0",
            name="ck_curriculum_generation_jobs_budget",
        ),
        sa.CheckConstraint(
            "estimated_cost_usd >= 0 AND cost_usd >= 0",
            name="ck_curriculum_generation_jobs_cost",
        ),
        sa.CheckConstraint(
            "input_tokens >= 0 AND cached_input_tokens >= 0 AND output_tokens >= 0",
            name="ck_curriculum_generation_jobs_tokens",
        ),
        sa.CheckConstraint(
            "state <> 'running' OR "
            "(lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL)",
            name="ck_curriculum_generation_jobs_running_lease",
        ),
        sa.UniqueConstraint(
            "input_hash",
            name="uq_curriculum_generation_jobs_input_hash",
        ),
    )
    op.create_index(
        "ix_curriculum_generation_jobs_eligible",
        "curriculum_generation_jobs",
        ["state", "next_attempt_at", "priority"],
    )
    op.create_index(
        "ix_curriculum_generation_jobs_lease",
        "curriculum_generation_jobs",
        ["state", "lease_expires_at"],
    )

    op.create_table(
        "module_quality_reports",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "module_version_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("canonical_module_versions.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "generation_job_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("curriculum_generation_jobs.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("review_type", MODULE_QUALITY_REVIEW_TYPE, nullable=False),
        sa.Column("verdict", MODULE_QUALITY_VERDICT, nullable=False),
        sa.Column("score", sa.Float(), nullable=True),
        sa.Column("attempt", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("reviewed_content_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "issues_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "evidence_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "deterministic_checks_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "repair_instructions_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
        sa.Column("reviewer_model", sa.String(length=120), nullable=True),
        sa.Column("prompt_version", sa.String(length=100), nullable=True),
        _created_at(),
        sa.CheckConstraint("attempt > 0", name="ck_module_quality_reports_attempt"),
        sa.CheckConstraint(
            "score IS NULL OR (score >= 0 AND score <= 1)",
            name="ck_module_quality_reports_score",
        ),
        sa.CheckConstraint(
            "reviewed_content_hash ~ '^[0-9a-f]{64}$'",
            name="ck_module_quality_reports_content_hash_sha256",
        ),
        sa.UniqueConstraint(
            "module_version_id",
            "review_type",
            "attempt",
            name="uq_module_quality_reports_review_attempt",
        ),
    )
    op.create_index(
        "ix_module_quality_reports_version_verdict",
        "module_quality_reports",
        ["module_version_id", "verdict"],
    )

    op.create_table(
        "mentor_evidence_claims",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "idol_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("idols.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("claim_type", MENTOR_CLAIM_TYPE, nullable=False),
        sa.Column("claim_text", sa.Text(), nullable=False),
        sa.Column("normalized_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "source_chunk_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("source_chunks.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column("source_title", sa.String(length=500), nullable=True),
        sa.Column("source_url", sa.String(length=2048), nullable=True),
        sa.Column("evidence_excerpt", sa.Text(), nullable=False),
        sa.Column(
            "evidence_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("source_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "skill_tags_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column(
            "verification_status",
            EVIDENCE_VERIFICATION_STATUS,
            nullable=False,
            server_default="pending",
        ),
        sa.Column("valid_from", sa.Date(), nullable=True),
        sa.Column("valid_to", sa.Date(), nullable=True),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revocation_reason", sa.Text(), nullable=True),
        *_timestamps(),
        sa.CheckConstraint(
            "normalized_hash ~ '^[0-9a-f]{64}$'",
            name="ck_mentor_evidence_claims_normalized_hash_sha256",
        ),
        sa.CheckConstraint(
            "source_hash ~ '^[0-9a-f]{64}$'",
            name="ck_mentor_evidence_claims_source_hash_sha256",
        ),
        sa.CheckConstraint(
            "confidence >= 0 AND confidence <= 1",
            name="ck_mentor_evidence_claims_confidence",
        ),
        sa.CheckConstraint(
            "source_chunk_id IS NOT NULL OR source_url IS NOT NULL",
            name="ck_mentor_evidence_claims_provenance",
        ),
        sa.CheckConstraint(
            "(verification_status <> 'verified' OR verified_at IS NOT NULL) AND "
            "(verification_status <> 'revoked' OR "
            "(revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))",
            name="ck_mentor_evidence_claims_lifecycle",
        ),
        sa.UniqueConstraint(
            "idol_id",
            "normalized_hash",
            "source_hash",
            name="uq_mentor_evidence_claims_idol_claim_source",
        ),
    )
    op.create_index(
        "ix_mentor_evidence_claims_idol_status_type",
        "mentor_evidence_claims",
        ["idol_id", "verification_status", "claim_type"],
    )

    op.create_table(
        "mentor_evidence_claim_skills",
        sa.Column(
            "claim_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("mentor_evidence_claims.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "skill_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
            primary_key=True,
        ),
    )

    op.create_table(
        "learner_skill_states",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "skill_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("curriculum_skills.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "current_level",
            CURRICULUM_SKILL_LEVEL,
            nullable=False,
            server_default="unknown",
        ),
        sa.Column(
            "mastery_status",
            LEARNER_MASTERY_STATUS,
            nullable=False,
            server_default="unassessed",
        ),
        sa.Column("mastery_score", sa.Float(), nullable=True),
        sa.Column("state_version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column(
            "strengths_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "gaps_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "misconceptions_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "evidence_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("state_hash", sa.String(length=64), nullable=True),
        sa.Column("assessed_at", sa.DateTime(timezone=True), nullable=True),
        *_timestamps(),
        sa.CheckConstraint(
            "state_version > 0",
            name="ck_learner_skill_states_version",
        ),
        sa.CheckConstraint(
            "mastery_score IS NULL OR (mastery_score >= 0 AND mastery_score <= 1)",
            name="ck_learner_skill_states_mastery_score",
        ),
        sa.CheckConstraint(
            "state_hash IS NULL OR state_hash ~ '^[0-9a-f]{64}$'",
            name="ck_learner_skill_states_state_hash_sha256",
        ),
        sa.UniqueConstraint(
            "user_id",
            "skill_id",
            name="uq_learner_skill_states_user_skill",
        ),
    )
    op.create_index(
        "ix_learner_skill_states_user_mastery",
        "learner_skill_states",
        ["user_id", "mastery_status"],
    )

    op.create_table(
        "personalized_lesson_versions",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("module_session_id", postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column("module_version_id", postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column(
            "learner_state_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("learner_skill_states.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("version_number", sa.Integer(), nullable=False),
        sa.Column(
            "status",
            PERSONALIZED_LESSON_STATUS,
            nullable=False,
            server_default="queued",
        ),
        sa.Column(
            "learner_state_snapshot_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column("learner_state_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "mentor_evidence_snapshot_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column("mentor_evidence_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "personalization_brief_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column("input_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "content_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
        sa.Column("content_hash", sa.String(length=64), nullable=True),
        sa.Column("estimated_minutes", sa.Integer(), nullable=False),
        sa.Column("prompt_version", sa.String(length=100), nullable=False),
        sa.Column("model_name", sa.String(length=120), nullable=True),
        sa.Column("ready_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revocation_reason", sa.Text(), nullable=True),
        _created_at(),
        sa.ForeignKeyConstraint(
            ["module_session_id", "module_version_id"],
            ["module_sessions.id", "module_sessions.module_version_id"],
            name="fk_personalized_lessons_pinned_session",
            ondelete="RESTRICT",
        ),
        sa.UniqueConstraint(
            "id",
            "module_session_id",
            name="uq_personalized_lessons_id_session",
        ),
        sa.CheckConstraint(
            "version_number > 0",
            name="ck_personalized_lessons_version",
        ),
        sa.CheckConstraint(
            "estimated_minutes > 0",
            name="ck_personalized_lessons_minutes",
        ),
        sa.CheckConstraint(
            "input_hash ~ '^[0-9a-f]{64}$'",
            name="ck_personalized_lessons_input_hash_sha256",
        ),
        sa.CheckConstraint(
            "learner_state_hash ~ '^[0-9a-f]{64}$'",
            name="ck_personalized_lessons_state_hash_sha256",
        ),
        sa.CheckConstraint(
            "mentor_evidence_hash ~ '^[0-9a-f]{64}$'",
            name="ck_personalized_lessons_mentor_hash_sha256",
        ),
        sa.CheckConstraint(
            "content_hash IS NULL OR content_hash ~ '^[0-9a-f]{64}$'",
            name="ck_personalized_lessons_content_hash_sha256",
        ),
        sa.CheckConstraint(
            "(status <> 'ready' OR "
            "(content_json IS NOT NULL AND content_hash IS NOT NULL "
            "AND ready_at IS NOT NULL)) AND "
            "(status <> 'failed' OR last_error IS NOT NULL) AND "
            "(status <> 'revoked' OR "
            "(revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))",
            name="ck_personalized_lessons_lifecycle",
        ),
        sa.UniqueConstraint(
            "user_id",
            "module_session_id",
            "version_number",
            name="uq_personalized_lessons_user_session_version",
        ),
        sa.UniqueConstraint(
            "user_id",
            "input_hash",
            name="uq_personalized_lessons_user_input_hash",
        ),
    )
    op.create_index(
        "ix_personalized_lessons_user_status",
        "personalized_lesson_versions",
        ["user_id", "status"],
    )

    op.create_table(
        "plan_lesson_assignments",
        sa.Column("id", postgresql.UUID(as_uuid=False), primary_key=True),
        sa.Column(
            "plan_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("plans.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "plan_item_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("plan_items.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "module_session_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("module_sessions.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "personalized_lesson_version_id",
            postgresql.UUID(as_uuid=False),
            nullable=True,
        ),
        sa.Column("week_number", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("allocated_minutes", sa.Integer(), nullable=False),
        sa.Column(
            "status",
            PLAN_LESSON_ASSIGNMENT_STATUS,
            nullable=False,
            server_default="scheduled",
        ),
        sa.Column(
            "comparison_gap_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column("match_score", sa.Float(), nullable=True),
        sa.Column("match_reason", sa.Text(), nullable=False),
        sa.Column("available_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "replaced_by_assignment_id",
            postgresql.UUID(as_uuid=False),
            sa.ForeignKey("plan_lesson_assignments.id", ondelete="SET NULL"),
            nullable=True,
        ),
        *_timestamps(),
        sa.ForeignKeyConstraint(
            ["personalized_lesson_version_id", "module_session_id"],
            ["personalized_lesson_versions.id", "personalized_lesson_versions.module_session_id"],
            name="fk_plan_lesson_assignments_personalized_session",
            ondelete="CASCADE",
        ),
        sa.CheckConstraint(
            "week_number > 0",
            name="ck_plan_lesson_assignments_week",
        ),
        sa.CheckConstraint(
            "position > 0",
            name="ck_plan_lesson_assignments_position",
        ),
        sa.CheckConstraint(
            "allocated_minutes > 0",
            name="ck_plan_lesson_assignments_allocated_minutes",
        ),
        sa.CheckConstraint(
            "match_score IS NULL OR (match_score >= 0 AND match_score <= 1)",
            name="ck_plan_lesson_assignments_match_score",
        ),
        sa.CheckConstraint(
            "status NOT IN ('available', 'in_progress', 'completed') OR "
            "personalized_lesson_version_id IS NOT NULL",
            name="ck_plan_lesson_assignments_personalized_visibility",
        ),
        sa.CheckConstraint(
            "status <> 'available' OR available_at IS NOT NULL",
            name="ck_plan_lesson_assignments_available_at",
        ),
        sa.UniqueConstraint(
            "plan_id",
            "week_number",
            "position",
            name="uq_plan_lesson_assignments_week_position",
        ),
        sa.UniqueConstraint(
            "plan_id",
            "module_session_id",
            name="uq_plan_lesson_assignments_plan_session",
        ),
    )
    op.create_index(
        "ix_plan_lesson_assignments_plan_status",
        "plan_lesson_assignments",
        ["plan_id", "status"],
    )
    op.create_index(
        "ix_plan_lesson_assignments_session",
        "plan_lesson_assignments",
        ["module_session_id"],
    )
    # catalog_details_are_ready_in_database filters on plan_item_id ALONE, so the
    # plan_id-leading index above cannot serve it. Four request handlers call it on
    # every plan-item open, and the plan_item_id SET NULL action rescans this table
    # for each deleted plan_items row.
    op.create_index(
        "ix_plan_lesson_assignments_plan_item",
        "plan_lesson_assignments",
        ["plan_item_id"],
        postgresql_where=sa.text("plan_item_id IS NOT NULL"),
    )
    op.create_index(
        "ix_llm_usage_events_curriculum_job",
        "llm_usage_events",
        [sa.text("(metadata_json ->> 'curriculum_job_id')")],
        postgresql_where=sa.text("metadata_json ? 'curriculum_job_id'"),
    )

    _create_immutability_guards()


def _create_immutability_guards() -> None:
    op.execute(
        """
        CREATE FUNCTION guard_canonical_module_version() RETURNS trigger AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                RAISE EXCEPTION 'canonical module versions are append-only';
            END IF;

            IF OLD.status::text IN ('published', 'revoked') AND (
                OLD.module_id IS DISTINCT FROM NEW.module_id OR
                OLD.version_number IS DISTINCT FROM NEW.version_number OR
                OLD.supersedes_version_id IS DISTINCT FROM NEW.supersedes_version_id OR
                OLD.content_json IS DISTINCT FROM NEW.content_json OR
                OLD.source_manifest_json IS DISTINCT FROM NEW.source_manifest_json OR
                OLD.technique_plan_json IS DISTINCT FROM NEW.technique_plan_json OR
                OLD.content_hash IS DISTINCT FROM NEW.content_hash OR
                OLD.source_hash IS DISTINCT FROM NEW.source_hash OR
                OLD.estimated_minutes IS DISTINCT FROM NEW.estimated_minutes OR
                OLD.quality_score IS DISTINCT FROM NEW.quality_score OR
                OLD.prompt_version IS DISTINCT FROM NEW.prompt_version OR
                OLD.gate_version IS DISTINCT FROM NEW.gate_version OR
                OLD.model_name IS DISTINCT FROM NEW.model_name OR
                OLD.retrieval_metadata_json IS DISTINCT FROM NEW.retrieval_metadata_json OR
                OLD.retrieval_metadata_hash IS DISTINCT FROM NEW.retrieval_metadata_hash
            ) THEN
                RAISE EXCEPTION 'published canonical module content is immutable';
            END IF;

            IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
                (OLD.status::text = 'draft' AND NEW.status::text IN ('in_review', 'published')) OR
                (OLD.status::text = 'in_review' AND NEW.status::text IN ('draft', 'published')) OR
                (OLD.status::text = 'published' AND NEW.status::text = 'revoked')
            ) THEN
                RAISE EXCEPTION 'invalid canonical module version transition';
            END IF;
            IF NEW.status::text = 'revoked' AND EXISTS (
                SELECT 1 FROM canonical_modules
                WHERE current_published_version_id = NEW.id
            ) THEN
                RAISE EXCEPTION 'detach a current module version before revoking it';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_canonical_module_version
        BEFORE UPDATE OR DELETE ON canonical_module_versions
        FOR EACH ROW EXECUTE FUNCTION guard_canonical_module_version();
        """
    )
    op.execute(
        """
        CREATE FUNCTION guard_canonical_module_current_version() RETURNS trigger AS $$
        DECLARE
            version_status text;
        BEGIN
            IF NEW.current_published_version_id IS NOT NULL THEN
                SELECT status::text INTO version_status
                FROM canonical_module_versions
                WHERE id = NEW.current_published_version_id
                  AND module_id = NEW.id
                FOR SHARE;
                IF version_status IS DISTINCT FROM 'published' THEN
                    RAISE EXCEPTION 'current module version must be published and owned by the module';
                END IF;
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_canonical_module_current_version
        BEFORE INSERT OR UPDATE OF current_published_version_id, status
        ON canonical_modules
        FOR EACH ROW EXECUTE FUNCTION guard_canonical_module_current_version();
        """
    )
    op.execute(
        """
        CREATE FUNCTION guard_learning_technique_version() RETURNS trigger AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                RAISE EXCEPTION 'learning technique versions are append-only';
            END IF;

            IF OLD.status::text IN ('published', 'revoked') AND (
                OLD.technique_key IS DISTINCT FROM NEW.technique_key OR
                OLD.version_number IS DISTINCT FROM NEW.version_number OR
                OLD.title IS DISTINCT FROM NEW.title OR
                OLD.summary IS DISTINCT FROM NEW.summary OR
                OLD.evidence_level IS DISTINCT FROM NEW.evidence_level OR
                OLD.appropriate_for_json IS DISTINCT FROM NEW.appropriate_for_json OR
                OLD.conditions_json IS DISTINCT FROM NEW.conditions_json OR
                OLD.implementation_contract_json IS DISTINCT FROM NEW.implementation_contract_json OR
                OLD.limitations_json IS DISTINCT FROM NEW.limitations_json OR
                OLD.source_manifest_json IS DISTINCT FROM NEW.source_manifest_json OR
                OLD.content_hash IS DISTINCT FROM NEW.content_hash OR
                OLD.source_hash IS DISTINCT FROM NEW.source_hash
            ) THEN
                RAISE EXCEPTION 'published learning technique content is immutable';
            END IF;

            IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
                (OLD.status::text = 'draft' AND NEW.status::text IN ('in_review', 'published')) OR
                (OLD.status::text = 'in_review' AND NEW.status::text IN ('draft', 'published')) OR
                (OLD.status::text = 'published' AND NEW.status::text = 'revoked')
            ) THEN
                RAISE EXCEPTION 'invalid learning technique version transition';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_learning_technique_version
        BEFORE UPDATE OR DELETE ON learning_technique_versions
        FOR EACH ROW EXECUTE FUNCTION guard_learning_technique_version();
        """
    )
    op.execute(
        """
        CREATE FUNCTION guard_published_module_session() RETURNS trigger AS $$
        DECLARE
            old_parent_status text;
            new_parent_status text;
        BEGIN
            IF TG_OP IN ('UPDATE', 'DELETE') THEN
                SELECT status::text INTO old_parent_status
                FROM canonical_module_versions
                WHERE id = OLD.module_version_id
                FOR SHARE;
            END IF;

            IF TG_OP IN ('INSERT', 'UPDATE') THEN
                SELECT status::text INTO new_parent_status
                FROM canonical_module_versions
                WHERE id = NEW.module_version_id
                FOR SHARE;
            END IF;

            IF old_parent_status IN ('published', 'revoked') OR
               new_parent_status IN ('published', 'revoked') THEN
                RAISE EXCEPTION 'sessions of published module versions are immutable';
            END IF;
            IF TG_OP = 'DELETE' THEN
                RETURN OLD;
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_published_module_session
        BEFORE INSERT OR UPDATE OR DELETE ON module_sessions
        FOR EACH ROW EXECUTE FUNCTION guard_published_module_session();
        """
    )
    op.execute(
        """
        CREATE FUNCTION guard_ready_personalized_lesson() RETURNS trigger AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                -- Direct deletion is forbidden. A deeper RI-trigger call is
                -- the users.id privacy cascade and must remain possible.
                IF OLD.status::text IN ('ready', 'revoked')
                   AND pg_trigger_depth() <= 1 THEN
                    RAISE EXCEPTION 'ready personalized lesson versions are immutable';
                END IF;
                RETURN OLD;
            END IF;

            -- Deleting a user first cascades through learner_skill_states.
            -- Its FK action must clear the live pointer before the separate
            -- users -> personalized lessons cascade deletes this immutable
            -- snapshot. Permit only that nested RI-trigger update; a direct
            -- application UPDATE still runs at depth 1 and remains forbidden.
            IF OLD.status::text IN ('ready', 'revoked')
               AND pg_trigger_depth() > 1
               AND OLD.learner_state_id IS NOT NULL
               AND NEW.learner_state_id IS NULL
               AND OLD.status IS NOT DISTINCT FROM NEW.status
               AND OLD.user_id IS NOT DISTINCT FROM NEW.user_id
               AND OLD.module_session_id IS NOT DISTINCT FROM NEW.module_session_id
               AND OLD.module_version_id IS NOT DISTINCT FROM NEW.module_version_id
               AND OLD.version_number IS NOT DISTINCT FROM NEW.version_number
               AND OLD.learner_state_snapshot_json IS NOT DISTINCT FROM NEW.learner_state_snapshot_json
               AND OLD.learner_state_hash IS NOT DISTINCT FROM NEW.learner_state_hash
               AND OLD.mentor_evidence_snapshot_json IS NOT DISTINCT FROM NEW.mentor_evidence_snapshot_json
               AND OLD.mentor_evidence_hash IS NOT DISTINCT FROM NEW.mentor_evidence_hash
               AND OLD.personalization_brief_json IS NOT DISTINCT FROM NEW.personalization_brief_json
               AND OLD.input_hash IS NOT DISTINCT FROM NEW.input_hash
               AND OLD.content_json IS NOT DISTINCT FROM NEW.content_json
               AND OLD.content_hash IS NOT DISTINCT FROM NEW.content_hash
               AND OLD.estimated_minutes IS NOT DISTINCT FROM NEW.estimated_minutes
               AND OLD.prompt_version IS NOT DISTINCT FROM NEW.prompt_version
               AND OLD.model_name IS NOT DISTINCT FROM NEW.model_name THEN
                RETURN NEW;
            END IF;

            IF OLD.status::text IN ('ready', 'revoked') AND (
                OLD.user_id IS DISTINCT FROM NEW.user_id OR
                OLD.module_session_id IS DISTINCT FROM NEW.module_session_id OR
                OLD.module_version_id IS DISTINCT FROM NEW.module_version_id OR
                OLD.learner_state_id IS DISTINCT FROM NEW.learner_state_id OR
                OLD.version_number IS DISTINCT FROM NEW.version_number OR
                OLD.learner_state_snapshot_json IS DISTINCT FROM NEW.learner_state_snapshot_json OR
                OLD.learner_state_hash IS DISTINCT FROM NEW.learner_state_hash OR
                OLD.mentor_evidence_snapshot_json IS DISTINCT FROM NEW.mentor_evidence_snapshot_json OR
                OLD.mentor_evidence_hash IS DISTINCT FROM NEW.mentor_evidence_hash OR
                OLD.personalization_brief_json IS DISTINCT FROM NEW.personalization_brief_json OR
                OLD.input_hash IS DISTINCT FROM NEW.input_hash OR
                OLD.content_json IS DISTINCT FROM NEW.content_json OR
                OLD.content_hash IS DISTINCT FROM NEW.content_hash OR
                OLD.estimated_minutes IS DISTINCT FROM NEW.estimated_minutes OR
                OLD.prompt_version IS DISTINCT FROM NEW.prompt_version OR
                OLD.model_name IS DISTINCT FROM NEW.model_name
            ) THEN
                RAISE EXCEPTION 'ready personalized lesson content is immutable';
            END IF;

            IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
                (OLD.status::text = 'queued' AND NEW.status::text IN ('generating', 'failed')) OR
                (OLD.status::text = 'generating' AND NEW.status::text IN ('ready', 'failed')) OR
                (OLD.status::text = 'failed' AND NEW.status::text IN ('queued', 'generating')) OR
                (OLD.status::text = 'ready' AND NEW.status::text = 'revoked')
            ) THEN
                RAISE EXCEPTION 'invalid personalized lesson transition';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_ready_personalized_lesson
        BEFORE UPDATE OR DELETE ON personalized_lesson_versions
        FOR EACH ROW EXECUTE FUNCTION guard_ready_personalized_lesson();
        """
    )
    op.execute(
        """
        CREATE FUNCTION guard_module_quality_report() RETURNS trigger AS $$
        BEGIN
            RAISE EXCEPTION 'module quality reports are append-only';
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_module_quality_report
        BEFORE UPDATE OR DELETE ON module_quality_reports
        FOR EACH ROW EXECUTE FUNCTION guard_module_quality_report();
        """
    )
    op.execute(
        """
        CREATE FUNCTION guard_mentor_evidence_claim() RETURNS trigger AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                IF OLD.verification_status::text <> 'pending' THEN
                    RAISE EXCEPTION 'finalized mentor evidence claims are append-only';
                END IF;
                RETURN OLD;
            END IF;

            IF OLD.verification_status::text <> 'pending' AND (
                OLD.idol_id IS DISTINCT FROM NEW.idol_id OR
                OLD.claim_type IS DISTINCT FROM NEW.claim_type OR
                OLD.claim_text IS DISTINCT FROM NEW.claim_text OR
                OLD.normalized_hash IS DISTINCT FROM NEW.normalized_hash OR
                OLD.source_chunk_id IS DISTINCT FROM NEW.source_chunk_id OR
                OLD.source_title IS DISTINCT FROM NEW.source_title OR
                OLD.source_url IS DISTINCT FROM NEW.source_url OR
                OLD.evidence_excerpt IS DISTINCT FROM NEW.evidence_excerpt OR
                OLD.evidence_json IS DISTINCT FROM NEW.evidence_json OR
                OLD.source_hash IS DISTINCT FROM NEW.source_hash OR
                OLD.skill_tags_json IS DISTINCT FROM NEW.skill_tags_json OR
                OLD.confidence IS DISTINCT FROM NEW.confidence OR
                OLD.valid_from IS DISTINCT FROM NEW.valid_from OR
                OLD.valid_to IS DISTINCT FROM NEW.valid_to
            ) THEN
                RAISE EXCEPTION 'finalized mentor evidence is immutable';
            END IF;

            IF OLD.verification_status IS DISTINCT FROM NEW.verification_status AND NOT (
                (OLD.verification_status::text = 'pending' AND
                 NEW.verification_status::text IN ('verified', 'rejected')) OR
                (OLD.verification_status::text = 'verified' AND
                 NEW.verification_status::text = 'revoked')
            ) THEN
                RAISE EXCEPTION 'invalid mentor evidence transition';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_mentor_evidence_claim
        BEFORE UPDATE OR DELETE ON mentor_evidence_claims
        FOR EACH ROW EXECUTE FUNCTION guard_mentor_evidence_claim();
        """
    )
    op.execute(
        """
        CREATE FUNCTION guard_mentor_claim_skill_binding() RETURNS trigger AS $$
        DECLARE
            target_claim_id uuid;
            claim_status text;
        BEGIN
            IF TG_OP = 'DELETE' THEN
                target_claim_id := OLD.claim_id;
            ELSE
                target_claim_id := NEW.claim_id;
            END IF;
            SELECT verification_status::text INTO claim_status
            FROM mentor_evidence_claims
            WHERE id = target_claim_id
            FOR SHARE;
            IF claim_status IS DISTINCT FROM 'pending' THEN
                RAISE EXCEPTION 'skill bindings of finalized mentor evidence are immutable';
            END IF;
            IF TG_OP = 'DELETE' THEN
                RETURN OLD;
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_mentor_claim_skill_binding
        BEFORE INSERT OR UPDATE OR DELETE ON mentor_evidence_claim_skills
        FOR EACH ROW EXECUTE FUNCTION guard_mentor_claim_skill_binding();
        """
    )
    op.execute(
        """
        CREATE FUNCTION guard_mentor_claim_source_owner() RETURNS trigger AS $$
        BEGIN
            IF NEW.source_chunk_id IS NOT NULL AND NOT EXISTS (
                SELECT 1
                FROM source_chunks chunk
                JOIN idol_sources source ON source.id = chunk.source_id
                WHERE chunk.id = NEW.source_chunk_id
                  AND source.idol_id = NEW.idol_id
            ) THEN
                RAISE EXCEPTION 'mentor evidence source chunk belongs to another idol';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_mentor_claim_source_owner
        BEFORE INSERT OR UPDATE OF idol_id, source_chunk_id
        ON mentor_evidence_claims
        FOR EACH ROW EXECUTE FUNCTION guard_mentor_claim_source_owner();
        """
    )
    op.execute(
        """
        CREATE FUNCTION guard_plan_lesson_assignment_owner() RETURNS trigger AS $$
        DECLARE
            plan_user_id uuid;
            item_plan_id uuid;
            lesson_user_id uuid;
            lesson_status text;
            lesson_revoked_at timestamptz;
        BEGIN
            SELECT user_id INTO plan_user_id
            FROM plans WHERE id = NEW.plan_id
            FOR SHARE;

            -- plan_id is NOT NULL and carries an FK to plans, so NOT FOUND can only
            -- mean the parent plan is being deleted in this same transaction -- the
            -- users privacy cascade reaches plan_items (and its plan_item_id SET NULL
            -- action on this table) while the plans row is already gone. Without this
            -- early return plan_user_id stays NULL and every comparison below misfires,
            -- because NULL IS DISTINCT FROM <uuid> is TRUE: an ordinary cascade would
            -- abort with 'personalized lesson belongs to another plan user' and
            -- DELETE FROM users would fail outright. A row on its way out cannot
            -- violate ownership. Returning here also stops the ready-lesson check
            -- below from rejecting a completed assignment whose personalized version
            -- was revoked earlier.
            IF NOT FOUND THEN
                RETURN NEW;
            END IF;

            IF NEW.personalized_lesson_version_id IS NOT NULL THEN
                SELECT user_id, status::text, revoked_at
                INTO lesson_user_id, lesson_status, lesson_revoked_at
                FROM personalized_lesson_versions
                WHERE id = NEW.personalized_lesson_version_id
                  AND module_session_id = NEW.module_session_id
                FOR SHARE;
                IF plan_user_id IS DISTINCT FROM lesson_user_id THEN
                    RAISE EXCEPTION 'personalized lesson belongs to another plan user';
                END IF;
            END IF;

            IF NEW.plan_item_id IS NOT NULL THEN
                SELECT plan_id INTO item_plan_id
                FROM plan_items
                WHERE id = NEW.plan_item_id
                FOR SHARE;
                IF item_plan_id IS DISTINCT FROM NEW.plan_id THEN
                    RAISE EXCEPTION 'plan lesson assignment item belongs to another plan';
                END IF;
            END IF;

            IF NEW.status::text IN ('available', 'in_progress', 'completed') AND (
                NEW.personalized_lesson_version_id IS NULL OR
                lesson_status IS DISTINCT FROM 'ready' OR
                lesson_revoked_at IS NOT NULL
            ) THEN
                RAISE EXCEPTION 'visible assignment requires a ready personalized lesson';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER trg_guard_plan_lesson_assignment_owner
        BEFORE INSERT OR UPDATE OF plan_id, plan_item_id, module_session_id,
            personalized_lesson_version_id, status
        ON plan_lesson_assignments
        FOR EACH ROW EXECUTE FUNCTION guard_plan_lesson_assignment_owner();
        """
    )


def downgrade() -> None:
    op.drop_index(
        "ix_llm_usage_events_curriculum_job",
        table_name="llm_usage_events",
    )
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_plan_lesson_assignment_owner "
        "ON plan_lesson_assignments"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_plan_lesson_assignment_owner()")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_mentor_claim_source_owner "
        "ON mentor_evidence_claims"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_mentor_claim_source_owner()")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_mentor_claim_skill_binding "
        "ON mentor_evidence_claim_skills"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_mentor_claim_skill_binding()")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_mentor_evidence_claim "
        "ON mentor_evidence_claims"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_mentor_evidence_claim()")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_module_quality_report "
        "ON module_quality_reports"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_module_quality_report()")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_ready_personalized_lesson "
        "ON personalized_lesson_versions"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_ready_personalized_lesson()")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_published_module_session ON module_sessions"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_published_module_session()")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_learning_technique_version "
        "ON learning_technique_versions"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_learning_technique_version()")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_canonical_module_version "
        "ON canonical_module_versions"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_canonical_module_version()")
    op.execute(
        "DROP TRIGGER IF EXISTS trg_guard_canonical_module_current_version "
        "ON canonical_modules"
    )
    op.execute("DROP FUNCTION IF EXISTS guard_canonical_module_current_version()")

    op.drop_index("ix_plan_lesson_assignments_plan_item", table_name="plan_lesson_assignments")
    op.drop_index("ix_plan_lesson_assignments_session", table_name="plan_lesson_assignments")
    op.drop_index("ix_plan_lesson_assignments_plan_status", table_name="plan_lesson_assignments")
    op.drop_table("plan_lesson_assignments")
    op.drop_index("ix_personalized_lessons_user_status", table_name="personalized_lesson_versions")
    op.drop_table("personalized_lesson_versions")
    op.drop_index("ix_learner_skill_states_user_mastery", table_name="learner_skill_states")
    op.drop_table("learner_skill_states")
    op.drop_table("mentor_evidence_claim_skills")
    op.drop_index("ix_mentor_evidence_claims_idol_status_type", table_name="mentor_evidence_claims")
    op.drop_table("mentor_evidence_claims")
    op.drop_index("ix_module_quality_reports_version_verdict", table_name="module_quality_reports")
    op.drop_table("module_quality_reports")
    op.drop_index("ix_curriculum_generation_jobs_lease", table_name="curriculum_generation_jobs")
    op.drop_index("ix_curriculum_generation_jobs_eligible", table_name="curriculum_generation_jobs")
    op.drop_table("curriculum_generation_jobs")
    op.drop_table("module_sessions")
    op.drop_constraint(
        "fk_canonical_modules_current_published_version",
        "canonical_modules",
        type_="foreignkey",
    )
    op.execute("DROP INDEX IF EXISTS ix_canonical_module_versions_embedding_hnsw")
    op.drop_index(
        "ix_canonical_module_versions_module_status",
        table_name="canonical_module_versions",
    )
    op.drop_table("canonical_module_versions")
    op.drop_index("ix_canonical_modules_match", table_name="canonical_modules")
    op.drop_table("canonical_modules")
    op.drop_index(
        "ix_learning_technique_versions_key_status",
        table_name="learning_technique_versions",
    )
    op.drop_table("learning_technique_versions")
    op.drop_table("curriculum_skill_prerequisites")
    op.drop_index("ix_curriculum_skills_domain_status", table_name="curriculum_skills")
    op.drop_table("curriculum_skills")

    bind = op.get_bind()
    for enum in reversed(ENUMS):
        enum.drop(bind, checkfirst=True)
