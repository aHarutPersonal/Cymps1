"""Autonomous, source-backed curriculum generation pipeline.

Beat only leases and dispatches bounded work. Each worker invocation performs
one durable stage, commits its checkpoint, and wakes the control queue. Heavy
provider calls never hold a database transaction open.
"""

from __future__ import annotations

import logging
import os
import socket
from hashlib import sha256
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError

from app.core.async_runtime import run_async
from app.core.celery import celery_app
from app.core.config import settings
from app.core.db import async_session_maker
from app.models.curriculum import (
    AssignmentStatus,
    CanonicalModule,
    CanonicalModuleVersion,
    CurriculumGenerationJob,
    CurriculumSkill,
    CurriculumSkillStatus,
    EvidenceLevel,
    EvidenceVerificationStatus,
    GenerationStage,
    GenerationState,
    LearningTechniqueVersion,
    MentorClaimType,
    MentorEvidenceClaim,
    ModuleQualityReport,
    ModuleSession,
    PersonalizedLessonStatus,
    PersonalizedLessonVersion,
    PlanLessonAssignment,
    QualityReviewType,
    QualityVerdict,
    SkillLevel,
    VersionStatus,
)
from app.models.idol import CatalogStatus, Idol
from app.models.idol_source import IdolSource
from app.models.plan import Plan, PlanItem
from app.models.source_chunk import SourceChunk
from app.services.curriculum.budget import (
    apply_curriculum_job_usage,
    curriculum_budget_allows_stage,
    curriculum_job_budget_allows_stage,
    curriculum_stage_reserve_usd,
    get_curriculum_budget_status,
    get_curriculum_job_usage,
)
from app.services.curriculum.gates import (
    MIN_REVIEW_SCORE,
    QUALITY_GATE_VERSION,
    draft_text,
    publication_gate,
    validate_manifest_verification,
)
from app.services.curriculum.generation import (
    GeneratedArtifact,
    configured_tier,
    deterministic_draft_gate,
    generate_module_draft,
    generate_outline,
    generate_technique_plan,
    merge_structure_review,
    repair_module_draft,
    review_module,
)
from app.services.curriculum.hashing import sha256_json, stage_input_hash
from app.services.curriculum.pilot import (
    PILOT_SKILLS,
    PILOT_TAXONOMY_VERSION,
    TECHNIQUE_REGISTRY,
    TECHNIQUE_REGISTRY_VERSION,
)
from app.services.curriculum.research import build_research_manifest
from app.services.curriculum.schemas import (
    CanonicalModuleDraft,
    CurriculumOutline,
    MentorClaimCuration,
    MentorClaimCandidate,
    MentorClaimVerificationBundle,
    QualityReview,
    ResearchManifest,
    ReviewBundle,
    TechniquePlan,
)
from app.services.curriculum.security import sanitize_external_text
from app.services.curriculum.sessions import pack_session_blocks
from app.services.curriculum.transitions import (
    PIPELINE_VERSION,
    PROMPT_VERSION,
    PipelineStage,
    transition_after_gate_failure,
    transition_after_success,
    retry_delay_seconds,
)
from app.services.llm import get_llm_client
from app.services.llm.prompt_loader import load_and_render, load_prompt
from app.services.llm.telemetry import record_llm_response
from app.services.tavily import is_direct_resource_url

logger = logging.getLogger(__name__)

MENTOR_CONFIDENCE_FLOOR = 0.84
MENTOR_LEXICAL_OVERLAP_FLOOR = 0.35
MENTOR_RECIPE_VERSION = "mentor-evidence-recipe-v2"
MENTOR_CHUNK_LIMIT = 30
MAX_LLM_COMPARISON_MODULES = 20
MAX_ORIGINALITY_CORPUS_MODULES = 100
MAX_ORIGINALITY_TEXT_CHARS = 40_000
ORIGINALITY_PUBLICATION_LOCK_KEY = 0x435552524943554C
MENTOR_JOB_KIND = "mentor_evidence_curation"
ACTIVE_COST_RESERVATION_KEY = "_active_cost_reservation"
CURRICULUM_PROMPT_FILES = (
    "curriculum_research_system",
    "curriculum_writer_system",
    "curriculum_research_discovery",
    "curriculum_research_curate",
    "curriculum_research_verify",
    "curriculum_technique_plan",
    "curriculum_outline",
    "curriculum_module_write",
    "curriculum_module_repair",
    "curriculum_review_structure",
    "curriculum_review_factual",
    "curriculum_review_pedagogy",
    "curriculum_review_originality",
)
MENTOR_PROMPT_FILES = (
    "curriculum_writer_system",
    "curriculum_mentor_claims",
    "curriculum_mentor_claim_verify",
)


@dataclass(frozen=True, slots=True)
class StageResult:
    updates: dict[str, Any]
    model_usage: dict[str, Any]
    passed: bool = True
    issues: tuple[dict[str, Any], ...] = ()
    quality_score: float | None = None


def _worker_owner() -> str:
    return f"{socket.gethostname()}:{os.getpid()}:{uuid4()}"


def _provider_model_for_tier(provider: str, tier: str) -> str | None:
    fields = {
        "openai": {
            "fast": settings.openai_fast_model,
            "balanced": settings.openai_model,
            "quality": settings.openai_quality_model,
        },
        "gemini": {
            "fast": settings.gemini_fast_model,
            "balanced": settings.gemini_model,
            "quality": settings.gemini_quality_model,
        },
        "yunwu": {
            "fast": settings.yunwu_fast_model,
            "balanced": settings.yunwu_model,
            "quality": settings.yunwu_quality_model,
        },
    }
    return fields.get(provider, {}).get(tier)


def _resolved_llm_route(tier: str) -> dict[str, Any]:
    """Describe the exact side-effect-free route used by ``get_llm_client``."""

    provider = settings.llm_provider
    route: dict[str, Any] = {
        "configured_provider": provider,
        "tier": tier,
        "primary": {"provider": "dummy", "model": "deterministic-fixtures"},
        "fallback": None,
        "resolution": "dummy_or_unknown_provider",
    }
    if provider == "openai":
        if settings.openai_api_key:
            route["primary"] = {
                "provider": "openai",
                "model": _provider_model_for_tier("openai", tier),
            }
            route["resolution"] = "configured_primary"
        else:
            route["resolution"] = "configured_primary_unavailable"
        return route
    if provider == "gemini":
        if settings.gemini_api_key:
            route["primary"] = {
                "provider": "gemini",
                "model": _provider_model_for_tier("gemini", tier),
            }
            route["resolution"] = "configured_primary"
        else:
            route["resolution"] = "configured_primary_unavailable"
        return route
    if provider != "yunwu":
        return route

    fallback = None
    if settings.yunwu_fallback_enabled and settings.gemini_api_key:
        fallback = {
            "provider": "gemini",
            "model": _provider_model_for_tier("gemini", tier),
        }
    if settings.yunwu_api_key:
        route["primary"] = {
            "provider": "yunwu",
            "model": _provider_model_for_tier("yunwu", tier),
            # Detect a gateway route change without persisting a potentially
            # private endpoint in curriculum provenance.
            "endpoint_fingerprint": sha256_json(
                {"base_url": settings.yunwu_base_url.rstrip("/")}
            ),
        }
        route["fallback"] = fallback
        route["resolution"] = (
            "configured_primary_with_fallback"
            if fallback is not None
            else "configured_primary"
        )
    elif fallback is not None:
        route["primary"] = fallback
        route["resolution"] = "configured_primary_unavailable_using_fallback"
    else:
        route["resolution"] = "configured_primary_unavailable"
    return route


def _grounded_search_route(tier: str) -> dict[str, Any]:
    """Native Gemini route used only for Google Search-grounded discovery."""

    return {
        "mode": "native_google_search_grounding",
        "tier": tier,
        "primary": {
            "provider": "gemini",
            "model": _provider_model_for_tier("gemini", tier),
        },
        "fallback": None,
        "credential_available": bool(settings.gemini_api_key),
    }


def _curriculum_stage_model_routes() -> dict[str, Any]:
    research_tier = configured_tier(
        settings.curriculum_research_model_tier, default="fast"
    )
    writing_tier = configured_tier(
        settings.curriculum_writing_model_tier, default="balanced"
    )
    review_tier = configured_tier(
        settings.curriculum_review_model_tier, default="quality"
    )
    return {
        "source_research_grounded_discovery": _grounded_search_route(research_tier),
        "source_research_curation": _resolved_llm_route(research_tier),
        "source_research_claim_verification": _resolved_llm_route(review_tier),
        "technique_design": _resolved_llm_route(research_tier),
        "outline": _resolved_llm_route(writing_tier),
        "writing": _resolved_llm_route(writing_tier),
        "repair": _resolved_llm_route(writing_tier),
        "structure_review": _resolved_llm_route(review_tier),
        "factual_review": _resolved_llm_route(review_tier),
        "pedagogy_review": _resolved_llm_route(review_tier),
        "originality_review": _resolved_llm_route(review_tier),
    }


def _prompt_content_hashes(prompt_files: tuple[str, ...]) -> dict[str, str]:
    # The provider calls use this same cached loader. Clearing once here makes
    # the recipe evaluation atomically repopulate the exact strings later used
    # by the paid call, while still detecting a changed immutable deployment.
    load_prompt.cache_clear()
    return {
        prompt_name: sha256(load_prompt(prompt_name).encode("utf-8")).hexdigest()
        for prompt_name in prompt_files
    }


def _technique_registry_content_hash() -> str:
    return sha256_json([entry.model_dump(mode="json") for entry in TECHNIQUE_REGISTRY])


def _curriculum_recipe_provenance() -> dict[str, Any]:
    return {
        "pipeline_version": PIPELINE_VERSION,
        "prompt_version": PROMPT_VERSION,
        "quality_gate_version": QUALITY_GATE_VERSION,
        "technique_registry_version": TECHNIQUE_REGISTRY_VERSION,
        "technique_registry_content_hash": _technique_registry_content_hash(),
        "prompt_content_hashes": _prompt_content_hashes(CURRICULUM_PROMPT_FILES),
        "durable_spacing_scheduler_enabled": (
            settings.curriculum_durable_spacing_scheduler_enabled
        ),
        "model_tier_policy": {
            "research": settings.curriculum_research_model_tier,
            "writing": settings.curriculum_writing_model_tier,
            "review": settings.curriculum_review_model_tier,
        },
        "stage_model_routes": _curriculum_stage_model_routes(),
    }


def _pilot_job_hash(
    identity_hash: str,
    *,
    definition_hash: str,
    technique_manifest_hash: str,
    recipe: dict[str, Any] | None = None,
) -> str:
    return sha256_json(
        {
            "identity_hash": identity_hash,
            "definition_hash": definition_hash,
            "technique_manifest_hash": technique_manifest_hash,
            "recipe": recipe or _curriculum_recipe_provenance(),
        }
    )


def _mentor_recipe_provenance() -> dict[str, Any]:
    review_tier = configured_tier(
        settings.curriculum_review_model_tier, default="quality"
    )
    return {
        "verifier_policy_version": MENTOR_RECIPE_VERSION,
        "pipeline_version": PIPELINE_VERSION,
        "prompt_version": PROMPT_VERSION,
        "prompt_content_hashes": _prompt_content_hashes(MENTOR_PROMPT_FILES),
        "confidence_floor": MENTOR_CONFIDENCE_FLOOR,
        "lexical_overlap_floor": MENTOR_LEXICAL_OVERLAP_FLOOR,
        "model_tier_policy": settings.curriculum_review_model_tier,
        "stage_model_routes": {
            "mentor_claim_curation": _resolved_llm_route(review_tier),
            "mentor_claim_verification": _resolved_llm_route(review_tier),
        },
    }


def _recipe_is_current(
    persisted_recipe: Any,
    current_recipe: dict[str, Any],
) -> bool:
    return isinstance(persisted_recipe, dict) and sha256_json(
        persisted_recipe
    ) == sha256_json(current_recipe)


def _pilot_definition_is_current(job_input: dict[str, Any]) -> bool:
    definition_snapshot = job_input.get("pilot_definition")
    definition_hash = job_input.get("pilot_definition_hash")
    if (
        not isinstance(definition_snapshot, dict)
        or not isinstance(definition_hash, str)
        or sha256_json(definition_snapshot) != definition_hash
    ):
        return False
    skill_key = str(definition_snapshot.get("skill_key") or "")
    current_definition = next(
        (
            definition
            for definition in PILOT_SKILLS
            if definition.skill_key == skill_key
        ),
        None,
    )
    return (
        current_definition is not None
        and sha256_json(current_definition.model_dump(mode="json")) == definition_hash
    )


async def _technique_manifest_is_current(
    db,
    job_input: dict[str, Any],
    *,
    lock: bool = True,
) -> bool:
    """Validate every pinned technique version before paid work or publish."""

    manifest = job_input.get("technique_version_manifest")
    manifest_hash = job_input.get("technique_version_manifest_hash")
    expected_keys = {entry.technique_id.value for entry in TECHNIQUE_REGISTRY}
    if (
        not isinstance(manifest, list)
        or not isinstance(manifest_hash, str)
        or sha256_json(manifest) != manifest_hash
        or len(manifest) != len(expected_keys)
    ):
        return False

    records_by_key: dict[str, dict[str, Any]] = {}
    version_ids: list[UUID] = []
    seen_version_ids: set[str] = set()
    for record in manifest:
        if not isinstance(record, dict):
            return False
        technique_key = record.get("technique_key")
        version_id = record.get("version_id")
        if (
            not isinstance(technique_key, str)
            or technique_key in records_by_key
            or not isinstance(version_id, str)
            or version_id in seen_version_ids
            or not isinstance(record.get("version_number"), int)
            or not isinstance(record.get("content_hash"), str)
            or not isinstance(record.get("source_hash"), str)
        ):
            return False
        try:
            parsed_version_id = UUID(version_id)
        except (TypeError, ValueError):
            return False
        records_by_key[technique_key] = record
        seen_version_ids.add(version_id)
        version_ids.append(parsed_version_id)
    if set(records_by_key) != expected_keys:
        return False

    query = (
        select(LearningTechniqueVersion)
        .where(LearningTechniqueVersion.id.in_(version_ids))
        .order_by(LearningTechniqueVersion.id.asc())
    )
    if lock:
        query = query.with_for_update(of=LearningTechniqueVersion)
    rows = list((await db.execute(query)).scalars().all())
    if len(rows) != len(version_ids):
        return False
    rows_by_id = {str(row.id): row for row in rows}

    registry_by_key = {entry.technique_id.value: entry for entry in TECHNIQUE_REGISTRY}
    for technique_key, record in records_by_key.items():
        row = rows_by_id.get(str(record["version_id"]))
        entry = registry_by_key[technique_key]
        source_manifest = {
            "registry_version": TECHNIQUE_REGISTRY_VERSION,
            "source_urls": list(entry.source_urls),
            "rights_status": "citation_only",
        }
        if (
            row is None
            or row.technique_key != technique_key
            or row.version_number != record["version_number"]
            or row.content_hash != record["content_hash"]
            or row.source_hash != record["source_hash"]
            or row.content_hash != sha256_json(entry.model_dump(mode="json"))
            or row.source_hash != sha256_json(source_manifest)
            or getattr(row.status, "value", row.status) != VersionStatus.PUBLISHED.value
            or row.revoked_at is not None
        ):
            return False
    return True


def _mark_job_recipe_changed(
    job: CurriculumGenerationJob,
    *,
    persisted_recipe: Any,
    current_recipe: dict[str, Any],
    now: datetime,
    identity_change: dict[str, Any] | None = None,
) -> None:
    job.state = GenerationState.FLAGGED
    job.completed_at = now
    job.lease_owner = None
    job.lease_expires_at = None
    job.heartbeat_at = None
    job.next_attempt_at = None
    job.last_error_code = "recipe_changed"
    job.last_error = (
        "Generation recipe or pilot definition changed before the next provider call"
    )
    job.checkpoints_json = {
        **dict(job.checkpoints_json or {}),
        "recipe_changed": {
            "persisted_recipe_hash": (
                sha256_json(persisted_recipe)
                if isinstance(persisted_recipe, dict)
                else None
            ),
            "current_recipe_hash": sha256_json(current_recipe),
            "detected_at": now.isoformat(),
            **(identity_change or {}),
        },
    }


def _stage(value: GenerationStage | str) -> PipelineStage:
    return PipelineStage(value.value if hasattr(value, "value") else str(value))


def _stage_enum(value: PipelineStage) -> GenerationStage:
    return GenerationStage(value.value)


def _state_value(value: GenerationState | str) -> str:
    return value.value if hasattr(value, "value") else str(value)


def _model_usage(generated: GeneratedArtifact) -> dict[str, Any]:
    return {
        "model": generated.model_name,
        "provider": generated.provider,
        "input_tokens": generated.input_tokens,
        "output_tokens": generated.output_tokens,
        "total_tokens": generated.total_tokens,
    }


def _running_job_reserve(
    stage: GenerationStage | str,
    input_json: dict[str, Any] | None,
) -> float:
    if (input_json or {}).get("job_kind") == MENTOR_JOB_KIND:
        return curriculum_stage_reserve_usd("mentor_evidence")
    stage_value = stage.value if hasattr(stage, "value") else str(stage)
    return curriculum_stage_reserve_usd(stage_value)


def _module_target(job_input: dict[str, Any]) -> dict[str, Any]:
    target = job_input.get("module_target")
    if not isinstance(target, dict):
        raise ValueError("curriculum job is missing module_target")
    return target


def _checkpoint_model(checkpoints: dict[str, Any], key: str, model):
    value = checkpoints.get(key)
    if not isinstance(value, dict):
        raise ValueError(f"missing {key} checkpoint")
    return model.model_validate(value)


def _stage_dependencies(
    *,
    stage: PipelineStage,
    job_input: dict[str, Any],
    checkpoints: dict[str, Any],
    repair_attempts: int,
) -> dict[str, Any]:
    dependencies: dict[str, Any] = {"module_target": _module_target(job_input)}
    if stage not in {PipelineStage.TAXONOMY, PipelineStage.SOURCE_RESEARCH}:
        dependencies["source_manifest"] = checkpoints.get("source_manifest")
    if stage not in {
        PipelineStage.TAXONOMY,
        PipelineStage.SOURCE_RESEARCH,
        PipelineStage.TECHNIQUE_DESIGN,
    }:
        dependencies["technique_plan"] = checkpoints.get("technique_plan")
    if stage in {
        PipelineStage.WRITING,
        PipelineStage.FACTUAL_REVIEW,
        PipelineStage.PEDAGOGY_REVIEW,
        PipelineStage.ORIGINALITY_REVIEW,
        PipelineStage.PUBLISH,
    }:
        dependencies["outline"] = checkpoints.get("outline")
    if stage in {
        PipelineStage.FACTUAL_REVIEW,
        PipelineStage.PEDAGOGY_REVIEW,
        PipelineStage.ORIGINALITY_REVIEW,
        PipelineStage.PUBLISH,
    } or (stage == PipelineStage.WRITING and repair_attempts > 0):
        dependencies["draft"] = checkpoints.get("draft")
    if stage == PipelineStage.WRITING and repair_attempts > 0:
        dependencies["repair_issues"] = checkpoints.get("repair_issues")
        dependencies["repair_attempts"] = repair_attempts
    if stage == PipelineStage.PUBLISH:
        dependencies["reviews"] = checkpoints.get("reviews")
    if stage == PipelineStage.ORIGINALITY_REVIEW:
        dependencies["originality_corpus_manifest"] = checkpoints.get(
            "originality_corpus_manifest"
        )
        dependencies["originality_corpus_hash"] = checkpoints.get(
            "originality_corpus_hash"
        )
    return dependencies


def _checkpoint_stage(
    checkpoints: dict[str, Any],
    *,
    stage: PipelineStage,
    input_hash: str,
    updates: dict[str, Any],
    model_usage: dict[str, Any],
    completed_at: datetime,
) -> dict[str, Any]:
    result = dict(checkpoints)
    result.update(updates)
    stage_records = dict(result.get("stages") or {})
    stage_records[stage.value] = {
        "input_hash": input_hash,
        "completed_at": completed_at.isoformat(),
        "output_hash": sha256_json(updates),
    }
    result["stages"] = stage_records
    usage = dict(result.get("model_usage") or {})
    usage[stage.value] = model_usage
    result["model_usage"] = usage
    return result


def _reconcile_job_usage_snapshot(
    job: CurriculumGenerationJob,
    *,
    usage,
    checkpoints: dict[str, Any] | None = None,
) -> dict[str, Any]:
    updated = dict(
        checkpoints if checkpoints is not None else job.checkpoints_json or {}
    )
    active = updated.pop(ACTIVE_COST_RESERVATION_KEY, None)
    estimated = float(job.estimated_cost_usd or 0)
    if isinstance(active, dict):
        reserve = max(float(active.get("reserve_usd") or 0), 0.0)
        cost_before = max(float(active.get("actual_cost_before_usd") or 0), 0.0)
        attempt_actual = max(usage.estimated_cost_usd - cost_before, 0.0)
        estimated += max(attempt_actual - reserve, 0.0)
        history = list(updated.get("cost_attempts") or [])[-49:]
        history.append(
            {
                **active,
                "actual_cost_usd": round(attempt_actual, 8),
                "reconciled_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        updated["cost_attempts"] = history
    estimated = max(estimated, usage.estimated_cost_usd)
    job.estimated_cost_usd = Decimal(str(round(estimated, 8)))
    apply_curriculum_job_usage(
        job,
        usage,
        stage_usage=dict(updated.get("model_usage") or {}),
    )
    job.checkpoints_json = updated
    return updated


async def _reconcile_job_usage(
    db,
    job: CurriculumGenerationJob,
    *,
    checkpoints: dict[str, Any] | None = None,
) -> tuple[dict[str, Any], Any]:
    """Reconcile the durable reserve ledger with all job-tagged usage events."""

    usage = await get_curriculum_job_usage(db, job_id=str(job.id))
    updated = _reconcile_job_usage_snapshot(
        job,
        usage=usage,
        checkpoints=checkpoints,
    )
    return updated, usage


def _reserve_job_attempt(
    job: CurriculumGenerationJob,
    *,
    checkpoints: dict[str, Any],
    stage: str,
    reserve_usd: float,
    actual_cost_before_usd: float,
) -> dict[str, Any]:
    """Charge a conservative attempt reserve before any provider call."""

    updated = dict(checkpoints)
    job.estimated_cost_usd = Decimal(
        str(round(float(job.estimated_cost_usd or 0) + reserve_usd, 8))
    )
    updated[ACTIVE_COST_RESERVATION_KEY] = {
        "stage": stage,
        "reserve_usd": round(reserve_usd, 8),
        "actual_cost_before_usd": round(actual_cost_before_usd, 8),
        "reserved_at": datetime.now(timezone.utc).isoformat(),
    }
    job.checkpoints_json = updated
    return updated


async def _seed_pilot(db, *, now: datetime) -> dict[str, int]:
    existing_skills = {
        skill.key: skill
        for skill in (
            await db.execute(
                select(CurriculumSkill)
                .where(
                    CurriculumSkill.key.in_([item.skill_key for item in PILOT_SKILLS])
                )
                .order_by(CurriculumSkill.id.asc())
                .with_for_update(of=CurriculumSkill)
            )
        ).scalars()
    }
    seeded_skills = 0
    new_skill_keys: set[str] = set()
    for definition in PILOT_SKILLS:
        skill = existing_skills.get(definition.skill_key)
        if skill is not None:
            continue
        skill = CurriculumSkill(
            key=definition.skill_key,
            domain=definition.domain,
            name=definition.title,
            description=definition.learning_outcome,
            skill_type="applied",
            taxonomy_version=1,
            tags_json=[definition.level, definition.locale, PILOT_TAXONOMY_VERSION],
            status=CurriculumSkillStatus.ACTIVE,
            # Async SQLAlchemy cannot lazy-load an uninitialized relationship
            # collection after the flush below.  Mark it loaded while the row
            # is still pending; prerequisite links are assigned in the second
            # pass once every pilot skill exists.
            prerequisites=[],
        )
        db.add(skill)
        existing_skills[definition.skill_key] = skill
        new_skill_keys.add(definition.skill_key)
        seeded_skills += 1
    await db.flush()

    for definition in PILOT_SKILLS:
        if definition.skill_key not in new_skill_keys:
            continue
        skill = existing_skills[definition.skill_key]
        required = [
            existing_skills[key]
            for key in definition.prerequisites
            if key in existing_skills
        ]
        if {item.key for item in skill.prerequisites} != {
            item.key for item in required
        }:
            skill.prerequisites = required

    technique_rows = list(
        (
            await db.execute(
                select(LearningTechniqueVersion)
                .where(
                    LearningTechniqueVersion.technique_key.in_(
                        [entry.technique_id.value for entry in TECHNIQUE_REGISTRY]
                    )
                )
                .order_by(LearningTechniqueVersion.id.asc())
                .with_for_update(of=LearningTechniqueVersion)
            )
        ).scalars()
    )
    versions_by_technique: dict[str, list[LearningTechniqueVersion]] = {}
    for row in technique_rows:
        versions_by_technique.setdefault(row.technique_key, []).append(row)
    seeded_techniques = 0
    active_technique_versions: dict[str, LearningTechniqueVersion] = {}
    blocked_techniques: set[str] = set()
    for entry in TECHNIQUE_REGISTRY:
        key = entry.technique_id.value
        content = entry.model_dump(mode="json")
        source_manifest = {
            "registry_version": TECHNIQUE_REGISTRY_VERSION,
            "source_urls": list(entry.source_urls),
            "rights_status": "citation_only",
        }
        content_hash = sha256_json(content)
        source_hash = sha256_json(source_manifest)
        existing_versions = versions_by_technique.get(key, [])
        matching_versions = [
            row
            for row in existing_versions
            if row.content_hash == content_hash and row.source_hash == source_hash
        ]
        active_match = next(
            (
                row
                for row in matching_versions
                if row.status == VersionStatus.PUBLISHED and row.revoked_at is None
            ),
            None,
        )
        if active_match is not None:
            active_technique_versions[key] = active_match
            continue
        if matching_versions:
            # Content-address uniqueness intentionally prevents silently
            # republishing evidence that an operator explicitly revoked.
            blocked_techniques.add(key)
            continue
        next_version = (
            max(
                (row.version_number for row in existing_versions),
                default=0,
            )
            + 1
        )
        new_version = LearningTechniqueVersion(
            technique_key=key,
            version_number=next_version,
            title=key.replace("_", " ").title(),
            summary=(
                f"Evidence-rated implementation contract for {key.replace('_', ' ')}."
            ),
            evidence_level=EvidenceLevel(entry.evidence_tier.value),
            appropriate_for_json={"contexts": list(entry.applicable_to)},
            conditions_json={"registry_version": entry.version},
            implementation_contract_json={"steps": list(entry.implementation_contract)},
            limitations_json={"items": list(entry.limitations)},
            source_manifest_json=source_manifest,
            content_hash=content_hash,
            source_hash=source_hash,
            status=VersionStatus.PUBLISHED,
            reviewed_at=now,
            published_at=now,
        )
        db.add(new_version)
        active_technique_versions[key] = new_version
        seeded_techniques += 1
    await db.flush()
    technique_manifest = [
        {
            "technique_key": entry.technique_id.value,
            "version_id": str(active_technique_versions[entry.technique_id.value].id),
            "version_number": active_technique_versions[
                entry.technique_id.value
            ].version_number,
            "content_hash": active_technique_versions[
                entry.technique_id.value
            ].content_hash,
            "source_hash": active_technique_versions[
                entry.technique_id.value
            ].source_hash,
        }
        for entry in TECHNIQUE_REGISTRY
        if entry.technique_id.value in active_technique_versions
    ]
    technique_manifest_hash = sha256_json(technique_manifest)

    existing_modules = {
        module.key: module
        for module in (
            await db.execute(
                select(CanonicalModule)
                .where(
                    CanonicalModule.key.in_(
                        [
                            f"{item.skill_key}:{item.level}:{item.locale}"
                            for item in PILOT_SKILLS
                        ]
                    )
                )
                .order_by(CanonicalModule.id.asc())
                .with_for_update(of=CanonicalModule)
            )
        ).scalars()
    }
    seeded_modules = 0
    seeded_jobs = 0
    recipe = _curriculum_recipe_provenance()
    for definition in PILOT_SKILLS:
        module_key = f"{definition.skill_key}:{definition.level}:{definition.locale}"
        module = existing_modules.get(module_key)
        if module is None:
            module = CanonicalModule(
                skill_id=existing_skills[definition.skill_key].id,
                key=module_key,
                level=SkillLevel(definition.level),
                language=definition.locale,
                title=definition.title,
                learning_outcome=definition.learning_outcome,
                artifact_type="applied_project",
                estimated_total_minutes=definition.estimated_minutes,
                status=CurriculumSkillStatus.DRAFT,
            )
            db.add(module)
            await db.flush()
            existing_modules[module_key] = module
            seeded_modules += 1
        elif (
            module.current_published_version_id is None
            and module.status == CurriculumSkillStatus.DRAFT
        ):
            # The stable module row is mutable catalog metadata; immutable
            # published metadata changes only with the pointer swap at publish.
            module.skill_id = existing_skills[definition.skill_key].id
            module.level = SkillLevel(definition.level)
            module.language = definition.locale
            module.title = definition.title
            module.learning_outcome = definition.learning_outcome
            module.artifact_type = "applied_project"
            module.estimated_total_minutes = definition.estimated_minutes
        definition_snapshot = definition.model_dump(mode="json")
        definition_hash = sha256_json(definition_snapshot)
        if blocked_techniques or len(technique_manifest) != len(TECHNIQUE_REGISTRY):
            continue
        job_hash = _pilot_job_hash(
            definition.identity_hash,
            definition_hash=definition_hash,
            technique_manifest_hash=technique_manifest_hash,
            recipe=recipe,
        )
        existing_job = await db.scalar(
            select(CurriculumGenerationJob.id).where(
                CurriculumGenerationJob.input_hash == job_hash
            )
        )
        if existing_job is not None:
            continue
        db.add(
            CurriculumGenerationJob(
                skill_id=existing_skills[definition.skill_key].id,
                module_id=module.id,
                stage=GenerationStage.SOURCE_RESEARCH,
                state=GenerationState.QUEUED,
                priority=definition.priority,
                input_hash=job_hash,
                input_json={
                    "identity_hash": definition.identity_hash,
                    "pilot_definition_hash": definition_hash,
                    "pilot_definition": definition_snapshot,
                    "technique_version_manifest": technique_manifest,
                    "technique_version_manifest_hash": technique_manifest_hash,
                    "recipe_provenance": recipe,
                    "module_target": {
                        "skill_key": definition.skill_key,
                        "domain": definition.domain,
                        "level": definition.level,
                        "locale": definition.locale,
                        "title": definition.title,
                        "learning_outcome": definition.learning_outcome,
                        "prerequisites": list(definition.prerequisites),
                        "estimated_minutes": definition.estimated_minutes,
                        "artifact_type": "applied_project",
                        "taxonomy_version": PILOT_TAXONOMY_VERSION,
                    },
                },
                pipeline_version=PIPELINE_VERSION,
                max_repairs=max(settings.curriculum_max_repairs, 0),
                budget_limit_usd=Decimal(
                    str(max(settings.curriculum_job_budget_usd, 0))
                ),
            )
        )
        seeded_jobs += 1
    return {
        "skills": seeded_skills,
        "techniques": seeded_techniques,
        "modules": seeded_modules,
        "jobs": seeded_jobs,
    }


async def _mentor_corpus(
    db,
    idol_id: str,
    *,
    lock: bool = False,
) -> tuple[list[dict[str, Any]], str]:
    """Build the deterministic mentor corpus, optionally pinning every input row."""

    if lock:
        idol_query = select(Idol.id).where(Idol.id == idol_id).with_for_update(of=Idol)
        if await db.scalar(idol_query) is None:
            return [], sha256_json([])
    source_query = (
        select(IdolSource)
        .where(IdolSource.idol_id == idol_id)
        .order_by(IdolSource.id.asc())
    )
    if lock:
        source_query = source_query.with_for_update(of=IdolSource)
    sources = list((await db.execute(source_query)).scalars().all())
    source_by_id = {str(source.id): source for source in sources}
    if not sources:
        return [], sha256_json([])

    chunk_query = (
        select(SourceChunk)
        .where(SourceChunk.source_id.in_([source.id for source in sources]))
        .order_by(
            SourceChunk.source_id.asc(),
            SourceChunk.chunk_index.asc(),
            SourceChunk.id.asc(),
        )
    )
    if lock:
        # Lock the whole candidate set, not only the first N rows. Otherwise an
        # unlocked later chunk could change its ordering and enter the bounded
        # corpus after the snapshot was verified.
        chunk_query = chunk_query.with_for_update(of=SourceChunk)
    else:
        chunk_query = chunk_query.limit(MENTOR_CHUNK_LIMIT)
    chunks = list((await db.execute(chunk_query)).scalars().all())
    pack = []
    for chunk in chunks[:MENTOR_CHUNK_LIMIT]:
        source = source_by_id.get(str(chunk.source_id))
        if source is None:
            raise ValueError("mentor corpus source ownership changed while reading")
        if not is_direct_resource_url(source.url):
            continue
        text = sanitize_external_text(chunk.text, max_chars=2500)
        if len(text) < 20:
            continue
        pack.append(
            {
                "source_chunk_id": str(chunk.id),
                "source_id": str(source.id),
                "source_title": source.title,
                "source_url": source.url,
                "text": text,
            }
        )
    return pack, sha256_json(pack)


async def _load_mentor_corpus(
    idol_id: str,
) -> tuple[list[dict[str, Any]], str]:
    async with async_session_maker() as db:
        return await _mentor_corpus(db, idol_id, lock=True)


def _mentor_provider_source_pack(
    pack: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    """Replace persistent database IDs with request-scoped provider aliases."""

    source_aliases: dict[str, str] = {}
    provider_pack: list[dict[str, Any]] = []
    chunks_by_alias: dict[str, dict[str, Any]] = {}
    for position, item in enumerate(pack, start=1):
        raw_source_id = str(item["source_id"])
        source_alias = source_aliases.setdefault(
            raw_source_id,
            f"source_{len(source_aliases) + 1}",
        )
        chunk_alias = f"chunk_{position}"
        chunks_by_alias[chunk_alias] = item
        provider_pack.append(
            {
                "source_chunk_id": chunk_alias,
                "source_id": source_alias,
                "source_title": item["source_title"],
                "source_url": item["source_url"],
                "text": item["text"],
            }
        )
    return provider_pack, chunks_by_alias


def _mentor_prompt_context(idol: Idol, skill_keys: list[str]) -> dict[str, Any]:
    return {
        "name": sanitize_external_text(idol.name, max_chars=300),
        "domain": sanitize_external_text(idol.domain, max_chars=200),
        "allowed_skill_keys": sorted({str(key) for key in skill_keys}),
    }


async def _mentor_context_from_db(
    db,
    idol_id: str,
    *,
    lock: bool = False,
) -> dict[str, Any] | None:
    idol_query = select(Idol).where(Idol.id == idol_id)
    skill_query = (
        select(CurriculumSkill.id, CurriculumSkill.key)
        .where(CurriculumSkill.status == CurriculumSkillStatus.ACTIVE)
        .order_by(CurriculumSkill.id.asc())
    )
    if lock:
        idol_query = idol_query.with_for_update()
        skill_query = skill_query.with_for_update()
    idol = (await db.execute(idol_query)).scalar_one_or_none()
    if idol is None:
        return None
    skill_keys = sorted(str(key) for _, key in (await db.execute(skill_query)).all())
    if not skill_keys:
        return None
    return _mentor_prompt_context(idol, skill_keys)


async def _load_mentor_context(idol_id: str) -> dict[str, Any] | None:
    async with async_session_maker() as db:
        return await _mentor_context_from_db(db, idol_id)


def _mentor_job_hash(
    idol_id: str,
    corpus_hash: str,
    *,
    mentor_context_hash: str,
    recipe: dict[str, Any] | None = None,
) -> str:
    return sha256_json(
        {
            "job_kind": MENTOR_JOB_KIND,
            "idol_id": idol_id,
            "corpus_hash": corpus_hash,
            "mentor_context_hash": mentor_context_hash,
            "recipe": recipe or _mentor_recipe_provenance(),
        }
    )


async def _reserve_mentor_candidate(
    db,
    *,
    owner: str,
    now: datetime,
    allow_new: bool,
) -> tuple[str, str, str, str] | None:
    """Atomically persist the lease before a paid mentor task is published."""
    idols = (
        await db.execute(
            select(Idol)
            .join(IdolSource, IdolSource.idol_id == Idol.id)
            .join(SourceChunk, SourceChunk.source_id == IdolSource.id)
            .where(Idol.status == CatalogStatus.PUBLISHED)
            .distinct()
            .order_by(Idol.created_at.asc())
        )
    ).scalars()
    skill_rows = list(
        (
            await db.execute(
                select(CurriculumSkill.id, CurriculumSkill.key)
                .where(CurriculumSkill.status == CurriculumSkillStatus.ACTIVE)
                .order_by(CurriculumSkill.key.asc())
            )
        ).all()
    )
    if not skill_rows:
        return None
    skill_id = skill_rows[0][0]
    skill_keys = [str(key) for _, key in skill_rows]
    recipe = _mentor_recipe_provenance()
    recipe_hash = sha256_json(recipe)
    for idol in idols:
        pack, corpus_hash = await _mentor_corpus(db, str(idol.id))
        if not pack:
            continue
        mentor_context = _mentor_prompt_context(idol, skill_keys)
        mentor_context_hash = sha256_json(mentor_context)
        existing = await db.scalar(
            select(MentorEvidenceClaim.id)
            .where(
                MentorEvidenceClaim.idol_id == idol.id,
                MentorEvidenceClaim.evidence_json["corpus_hash"].astext == corpus_hash,
                MentorEvidenceClaim.evidence_json["recipe_hash"].astext == recipe_hash,
                MentorEvidenceClaim.evidence_json["mentor_context_hash"].astext
                == mentor_context_hash,
            )
            .limit(1)
        )
        if existing is not None:
            continue
        input_hash = _mentor_job_hash(
            str(idol.id),
            corpus_hash,
            mentor_context_hash=mentor_context_hash,
            recipe=recipe,
        )
        marker = await db.scalar(
            select(CurriculumGenerationJob)
            .where(CurriculumGenerationJob.input_hash == input_hash)
            .with_for_update(skip_locked=True)
        )
        lease_owner = f"{owner}:mentor:{idol.id}:{corpus_hash[:12]}"
        if marker is not None:
            if marker.state in {
                GenerationState.COMPLETED,
                GenerationState.FLAGGED,
            }:
                continue
            if (
                marker.state == GenerationState.RETRY_WAIT
                and marker.next_attempt_at is not None
                and marker.next_attempt_at > now
            ):
                continue
            if (
                marker.state == GenerationState.RUNNING
                and marker.lease_expires_at is not None
                and marker.lease_expires_at >= now
            ):
                continue
            if marker.attempts >= marker.max_attempts:
                marker.state = GenerationState.FLAGGED
                marker.completed_at = now
                continue
            marker.state = GenerationState.RUNNING
            marker.lease_owner = lease_owner
            marker.lease_expires_at = now + timedelta(
                seconds=max(settings.curriculum_lease_seconds, 60)
            )
            marker.heartbeat_at = now
            marker.next_attempt_at = None
            marker.started_at = marker.started_at or now
            return str(idol.id), corpus_hash, str(marker.id), lease_owner
        if not allow_new:
            continue
        marker = CurriculumGenerationJob(
            skill_id=skill_id,
            module_id=None,
            stage=GenerationStage.SOURCE_RESEARCH,
            state=GenerationState.RUNNING,
            priority=-10,
            input_hash=input_hash,
            input_json={
                "job_kind": MENTOR_JOB_KIND,
                "idol_id": str(idol.id),
                "corpus_hash": corpus_hash,
                "mentor_context_hash": mentor_context_hash,
                "mentor_context_snapshot": mentor_context,
                "recipe_hash": recipe_hash,
                "recipe_provenance": recipe,
            },
            pipeline_version=PIPELINE_VERSION,
            lease_owner=lease_owner,
            lease_expires_at=now
            + timedelta(seconds=max(settings.curriculum_lease_seconds, 60)),
            heartbeat_at=now,
            started_at=now,
            max_attempts=3,
            max_repairs=0,
            budget_limit_usd=Decimal(str(max(settings.curriculum_job_budget_usd, 0))),
        )
        try:
            async with db.begin_nested():
                db.add(marker)
                await db.flush()
        except IntegrityError:
            # A concurrent control tick won the unique input-hash reservation.
            continue
        return str(idol.id), corpus_hash, str(marker.id), lease_owner
    return None


@celery_app.task(name="app.tasks.curriculum.curriculum_control_tick")
def curriculum_control_tick() -> dict[str, Any]:
    if not settings.curriculum_enabled:
        return {"status": "disabled"}
    return run_async(_curriculum_control_tick_async())


def _recover_expired_job(job: CurriculumGenerationJob, *, now: datetime) -> bool:
    """Consume one attempt for a lost lease and return whether retries are spent."""

    max_attempts = max(int(job.max_attempts or 0), 1)
    job.attempts = min(int(job.attempts or 0) + 1, max_attempts)
    exhausted = job.attempts >= max_attempts
    job.state = GenerationState.FAILED if exhausted else GenerationState.QUEUED
    job.lease_owner = None
    job.lease_expires_at = None
    job.heartbeat_at = None
    job.next_attempt_at = None if exhausted else now
    job.last_error_code = "lease_expired"
    job.last_error = "Recovered an expired curriculum worker lease"
    job.completed_at = now if exhausted else None
    return exhausted


async def _curriculum_control_tick_async(
    *,
    now: datetime | None = None,
) -> dict[str, Any]:
    current = now or datetime.now(timezone.utc)
    day_start = current.replace(hour=0, minute=0, second=0, microsecond=0)
    owner = _worker_owner()
    dispatched: list[tuple[str, str]] = []
    recovered = 0
    mentor_candidate: tuple[str, str, str, str] | None = None
    async with async_session_maker() as db:
        seeded = await _seed_pilot(db, now=current)
        expired = (
            await db.execute(
                select(CurriculumGenerationJob)
                .where(
                    CurriculumGenerationJob.state == GenerationState.RUNNING,
                    CurriculumGenerationJob.lease_expires_at.is_not(None),
                    CurriculumGenerationJob.lease_expires_at < current,
                )
                .with_for_update(skip_locked=True)
            )
        ).scalars()
        for job in expired:
            _recover_expired_job(job, now=current)
            recovered += 1

        started_today = int(
            (
                await db.execute(
                    select(func.count(CurriculumGenerationJob.id)).where(
                        CurriculumGenerationJob.started_at.is_not(None),
                        CurriculumGenerationJob.started_at >= day_start,
                    )
                )
            ).scalar_one()
            or 0
        )
        running_rows = list(
            (
                await db.execute(
                    select(
                        CurriculumGenerationJob.stage,
                        CurriculumGenerationJob.input_json,
                    ).where(CurriculumGenerationJob.state == GenerationState.RUNNING)
                )
            ).all()
        )
        running_jobs = len(running_rows)
        running_reserved_usd = sum(
            _running_job_reserve(stage, input_json)
            for stage, input_json in running_rows
        )
        budget = await get_curriculum_budget_status(
            db,
            now=current,
            running_jobs=running_jobs,
            reserved_usd=running_reserved_usd,
        )
        due = (
            await db.execute(
                select(CurriculumGenerationJob)
                .where(
                    CurriculumGenerationJob.state.in_(
                        [GenerationState.QUEUED, GenerationState.RETRY_WAIT]
                    ),
                    or_(
                        CurriculumGenerationJob.input_json["job_kind"].astext.is_(None),
                        CurriculumGenerationJob.input_json["job_kind"].astext
                        != MENTOR_JOB_KIND,
                    ),
                    CurriculumGenerationJob.attempts
                    < CurriculumGenerationJob.max_attempts,
                    or_(
                        CurriculumGenerationJob.next_attempt_at.is_(None),
                        CurriculumGenerationJob.next_attempt_at <= current,
                    ),
                )
                .order_by(
                    CurriculumGenerationJob.priority.desc(),
                    CurriculumGenerationJob.created_at.asc(),
                )
                .limit(max(settings.curriculum_max_dispatch_per_tick * 10, 20))
                .with_for_update(skip_locked=True)
            )
        ).scalars()
        new_capacity = max(settings.curriculum_daily_job_limit - started_today, 0)
        running_capacity = max(
            settings.curriculum_max_running_jobs - running_jobs,
            0,
        )
        admitted_reserve_usd = 0.0
        for job in due:
            if len(dispatched) >= max(settings.curriculum_max_dispatch_per_tick, 0):
                break
            if len(dispatched) >= running_capacity:
                break
            if job.started_at is None and new_capacity <= 0:
                continue
            job_reserve = _running_job_reserve(job.stage, job.input_json)
            if job_reserve > 0 and not curriculum_budget_allows_stage(
                budget,
                additional_reserve_usd=admitted_reserve_usd + job_reserve,
            ):
                continue
            lease_owner = f"{owner}:{job.id}"
            job.state = GenerationState.RUNNING
            job.lease_owner = lease_owner
            job.lease_expires_at = current + timedelta(
                seconds=max(settings.curriculum_lease_seconds, 60)
            )
            job.heartbeat_at = current
            job.next_attempt_at = None
            job.started_at = job.started_at or current
            if job.started_at == current:
                new_capacity -= 1
            admitted_reserve_usd += job_reserve
            dispatched.append((str(job.id), lease_owner))
        if (
            not dispatched
            and running_capacity > 0
            and curriculum_budget_allows_stage(
                budget,
                additional_reserve_usd=curriculum_stage_reserve_usd("mentor_evidence"),
            )
        ):
            mentor_candidate = await _reserve_mentor_candidate(
                db,
                owner=owner,
                now=current,
                allow_new=new_capacity > 0,
            )
        await db.commit()

    for job_id, lease_owner in dispatched:
        process_curriculum_job.apply_async(
            args=[job_id, lease_owner],
            queue="curriculum",
        )
    if mentor_candidate is not None:
        curate_mentor_evidence.apply_async(
            args=list(mentor_candidate),
            queue="curriculum",
        )
    return {
        "status": "ok",
        "seeded": seeded,
        "recovered": recovered,
        "dispatched": len(dispatched),
        "mentor_dispatched": mentor_candidate is not None,
        "daily_started": started_today,
        "daily_limit": settings.curriculum_daily_job_limit,
        "budget_state": budget.state,
        "budget_spent_usd": budget.spent_usd,
        "budget_reserved_usd": budget.reserved_usd,
        "budget_limit_usd": budget.limit_usd,
    }


def _comparison_version_text(content: Any) -> str:
    return draft_text(content)[:MAX_ORIGINALITY_TEXT_CHARS]


async def _comparison_corpus(db, module_id: str | None) -> dict[str, Any]:
    query = (
        select(
            CanonicalModuleVersion.id,
            CanonicalModuleVersion.module_id,
            CanonicalModuleVersion.content_hash,
            CanonicalModuleVersion.content_json,
        )
        .join(
            CanonicalModule,
            CanonicalModule.current_published_version_id == CanonicalModuleVersion.id,
        )
        .where(
            CanonicalModuleVersion.status == VersionStatus.PUBLISHED,
            CanonicalModuleVersion.revoked_at.is_(None),
            CanonicalModule.status == CurriculumSkillStatus.ACTIVE,
        )
    )
    if module_id:
        query = query.where(CanonicalModuleVersion.module_id != module_id)
    query = query.order_by(CanonicalModuleVersion.id.asc()).limit(
        MAX_ORIGINALITY_CORPUS_MODULES + 1
    )
    rows = list((await db.execute(query)).all())
    if len(rows) > MAX_ORIGINALITY_CORPUS_MODULES:
        raise ValueError("originality corpus exceeds the safe complete-corpus bound")
    versions: list[dict[str, Any]] = []
    for version_id, version_module_id, content_hash, content in rows:
        if not isinstance(content, dict) or sha256_json(content) != content_hash:
            raise ValueError("published originality corpus contains a corrupt version")
        bounded_text = _comparison_version_text(content)
        versions.append(
            {
                "version_id": str(version_id),
                "module_id": str(version_module_id),
                "content_hash": str(content_hash),
                "bounded_text": bounded_text,
                "bounded_text_hash": sha256(bounded_text.encode("utf-8")).hexdigest(),
            }
        )
    return {"versions": versions, "corpus_hash": sha256_json(versions)}


async def _load_comparison_corpus(module_id: str | None) -> dict[str, Any]:
    async with async_session_maker() as db:
        return await _comparison_corpus(db, module_id)


def _comparison_corpus_texts(
    corpus: dict[str, Any],
    *,
    limit: int | None = None,
) -> list[str]:
    versions = corpus.get("versions")
    if not isinstance(versions, list) or corpus.get("corpus_hash") != sha256_json(
        versions
    ):
        raise ValueError("originality corpus manifest hash mismatch")
    selected = versions if limit is None else versions[:limit]
    return [
        str(record.get("bounded_text") or "")
        for record in selected
        if isinstance(record, dict)
    ]


async def _run_stage(
    *,
    stage: PipelineStage,
    job_input: dict[str, Any],
    checkpoints: dict[str, Any],
    repair_attempts: int,
    module_id: str | None,
    job_id: str,
) -> StageResult:
    target = _module_target(job_input)
    research_tier = configured_tier(
        settings.curriculum_research_model_tier, default="fast"
    )
    writing_tier = configured_tier(
        settings.curriculum_writing_model_tier, default="balanced"
    )
    review_tier = configured_tier(
        settings.curriculum_review_model_tier, default="quality"
    )
    telemetry_metadata = {"curriculum_job_id": job_id}
    if stage == PipelineStage.SOURCE_RESEARCH:
        approved_seed = job_input.get("approved_source_manifest")
        if approved_seed is not None:
            if job_input.get(
                "approved_source_manifest_provenance"
            ) != "deterministic_seed" or job_input.get(
                "approved_source_manifest_hash"
            ) != sha256_json(approved_seed):
                raise ValueError(
                    "approved source seed is missing deterministic provenance"
                )
            manifest = ResearchManifest.model_validate(approved_seed)
            if not validate_manifest_verification(manifest).passed:
                raise ValueError(
                    "approved source seed contains claims without independent verification"
                )
            usage = {"model": "deterministic_approved_seed", "total_tokens": 0}
        else:
            research_usage: list[dict[str, Any]] = []
            manifest = await build_research_manifest(
                module_target=target,
                research_tier=research_tier,
                curation_tier=research_tier,
                verification_tier=review_tier,
                telemetry_metadata=telemetry_metadata,
                usage_sink=research_usage,
            )
            usage = {
                f"call_{index}": item
                for index, item in enumerate(research_usage, start=1)
            }
        return StageResult(
            updates={"source_manifest": manifest.model_dump(mode="json")},
            model_usage=usage,
        )

    if stage == PipelineStage.TAXONOMY:
        return StageResult(
            updates={"taxonomy_target": target},
            model_usage={"model": "deterministic", "total_tokens": 0},
        )

    manifest = _checkpoint_model(checkpoints, "source_manifest", ResearchManifest)
    if stage == PipelineStage.TECHNIQUE_DESIGN:
        generated = await generate_technique_plan(
            module_target=target,
            manifest=manifest,
            tier=research_tier,
            durable_spacing_scheduler_enabled=(
                settings.curriculum_durable_spacing_scheduler_enabled
            ),
            telemetry_metadata=telemetry_metadata,
        )
        plan = TechniquePlan.model_validate(generated.value)
        return StageResult(
            updates={"technique_plan": plan.model_dump(mode="json")},
            model_usage=_model_usage(generated),
        )

    plan = _checkpoint_model(checkpoints, "technique_plan", TechniquePlan)
    if stage == PipelineStage.OUTLINE:
        generated = await generate_outline(
            module_target=target,
            manifest=manifest,
            technique_plan=plan,
            tier=writing_tier,
            telemetry_metadata=telemetry_metadata,
        )
        outline = CurriculumOutline.model_validate(generated.value)
        return StageResult(
            updates={"outline": outline.model_dump(mode="json")},
            model_usage=_model_usage(generated),
        )

    outline = _checkpoint_model(checkpoints, "outline", CurriculumOutline)
    if stage == PipelineStage.WRITING:
        if repair_attempts > 0:
            draft = _checkpoint_model(checkpoints, "draft", CanonicalModuleDraft)
            issues = checkpoints.get("repair_issues")
            if not isinstance(issues, list) or not issues:
                raise ValueError("repair stage has no targeted issues")
            generated = await repair_module_draft(
                module_target=target,
                manifest=manifest,
                technique_plan=plan,
                outline=outline,
                draft=draft,
                issues=issues,
                tier=writing_tier,
                repair_attempt=repair_attempts,
                telemetry_metadata=telemetry_metadata,
            )
        else:
            generated = await generate_module_draft(
                module_target=target,
                manifest=manifest,
                technique_plan=plan,
                outline=outline,
                tier=writing_tier,
                telemetry_metadata=telemetry_metadata,
            )
        draft = CanonicalModuleDraft.model_validate(generated.value)
        deterministic = deterministic_draft_gate(
            draft=draft,
            manifest=manifest,
            technique_plan=plan,
            module_target=target,
            durable_spacing_scheduler_enabled=(
                settings.curriculum_durable_spacing_scheduler_enabled
            ),
        )
        if not deterministic.passed:
            return StageResult(
                updates={
                    "draft": draft.model_dump(mode="json"),
                    "reviews": {},
                },
                model_usage=_model_usage(generated),
                passed=False,
                issues=tuple(
                    issue.model_dump(mode="json") for issue in deterministic.issues
                ),
                quality_score=deterministic.score,
            )
        reviewed = await review_module(
            reviewer="structure",
            module_target=target,
            manifest=manifest,
            technique_plan=plan,
            draft=draft,
            comparison_texts=[],
            tier=review_tier,
            repair_attempt=repair_attempts,
            telemetry_metadata=telemetry_metadata,
        )
        structure = merge_structure_review(
            QualityReview.model_validate(reviewed.value), deterministic
        )
        return StageResult(
            updates={
                "draft": draft.model_dump(mode="json"),
                "reviews": {"structure": structure.model_dump(mode="json")},
            },
            model_usage={
                "writer": _model_usage(generated),
                "structure_reviewer": _model_usage(reviewed),
            },
            passed=structure.passed,
            issues=tuple(issue.model_dump(mode="json") for issue in structure.issues),
            quality_score=structure.score,
        )

    draft = _checkpoint_model(checkpoints, "draft", CanonicalModuleDraft)
    reviewer_by_stage = {
        PipelineStage.FACTUAL_REVIEW: "factual",
        PipelineStage.PEDAGOGY_REVIEW: "pedagogy",
        PipelineStage.ORIGINALITY_REVIEW: "originality",
    }
    reviewer = reviewer_by_stage[stage]
    originality_corpus = None
    comparisons: list[str] = []
    if reviewer == "originality":
        originality_corpus = {
            "versions": checkpoints.get("originality_corpus_manifest"),
            "corpus_hash": checkpoints.get("originality_corpus_hash"),
        }
        comparisons = _comparison_corpus_texts(
            originality_corpus,
            limit=MAX_LLM_COMPARISON_MODULES,
        )
    generated = await review_module(
        reviewer=reviewer,
        module_target=target,
        manifest=manifest,
        technique_plan=plan,
        draft=draft,
        comparison_texts=comparisons,
        tier=review_tier,
        repair_attempt=repair_attempts,
        telemetry_metadata=telemetry_metadata,
    )
    review = QualityReview.model_validate(generated.value)
    reviews = dict(checkpoints.get("reviews") or {})
    reviews[reviewer] = review.model_dump(mode="json")
    passed = review.passed and review.score >= MIN_REVIEW_SCORE
    issues = tuple(issue.model_dump(mode="json") for issue in review.issues)
    quality_score = review.score
    updates: dict[str, Any] = {"reviews": reviews}
    if originality_corpus is not None:
        updates["originality_corpus_manifest"] = originality_corpus["versions"]
        updates["originality_corpus_hash"] = originality_corpus["corpus_hash"]
    if reviewer == "originality" and passed:
        bundle = ReviewBundle.model_validate({"reviews": list(reviews.values())})
        gate = publication_gate(
            draft=draft,
            manifest=manifest,
            technique_plan=plan,
            reviews=bundle,
            comparison_texts=comparisons,
            module_target=target,
            durable_spacing_scheduler_enabled=(
                settings.curriculum_durable_spacing_scheduler_enabled
            ),
        )
        passed = gate.passed
        issues = tuple(issue.model_dump(mode="json") for issue in gate.issues)
        quality_score = gate.score
        updates["publication_gate"] = {
            "passed": gate.passed,
            "score": gate.score,
            "issues": list(issues),
            "metrics": gate.metrics,
        }
    return StageResult(
        updates=updates,
        model_usage=_model_usage(generated),
        passed=passed,
        issues=issues,
        quality_score=quality_score,
    )


def _tomorrow_after_midnight(now: datetime) -> datetime:
    return (now + timedelta(days=1)).replace(hour=0, minute=1, second=0, microsecond=0)


def _retryable_error(exc: Exception, stage: PipelineStage) -> bool:
    text = str(exc).casefold()
    transient_markers = (
        "timeout",
        "timed out",
        "connection",
        "network",
        "rate limit",
        "429",
        "overloaded",
        "unavailable",
        "502",
        "503",
        "504",
    )
    if any(marker in text for marker in transient_markers):
        return True
    if stage == PipelineStage.SOURCE_RESEARCH and (
        "fewer than two" in text
        or "failed independent source verification" in text
        or "qualified live source" in text
    ):
        return True
    return False


async def _record_stage_failure(
    *,
    job_id: str,
    lease_owner: str,
    stage: PipelineStage,
    error: Exception,
) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    async with async_session_maker() as db:
        job = await db.get(CurriculumGenerationJob, job_id, with_for_update=True)
        if job is None:
            return {"status": "missing", "job_id": job_id}
        if job.lease_owner != lease_owner or job.state != GenerationState.RUNNING:
            return {"status": "ignored", "job_id": job_id}
        await _reconcile_job_usage(db, job)
        job.attempts = min(job.attempts + 1, job.max_attempts)
        retryable = _retryable_error(error, stage) and job.attempts < job.max_attempts
        job.state = GenerationState.RETRY_WAIT if retryable else GenerationState.FAILED
        job.next_attempt_at = (
            now + timedelta(seconds=retry_delay_seconds(job.attempts))
            if retryable
            else None
        )
        job.completed_at = None if retryable else now
        job.lease_owner = None
        job.lease_expires_at = None
        job.heartbeat_at = None
        job.last_error_code = (
            "transient_stage_failure" if retryable else "stage_failure"
        )
        job.last_error = str(error)[:4000]
        await db.commit()
        return {
            "status": "retry_wait" if retryable else "failed",
            "job_id": job_id,
            "stage": stage.value,
            "attempts": job.attempts,
            "next_attempt_at": (
                job.next_attempt_at.isoformat() if job.next_attempt_at else None
            ),
        }


@celery_app.task(
    bind=True,
    name="app.tasks.curriculum.process_curriculum_job",
    acks_late=True,
    reject_on_worker_lost=True,
)
def process_curriculum_job(
    self,
    job_id: str,
    lease_owner: str | None = None,
) -> dict[str, Any]:
    del self
    return run_async(_process_curriculum_job_async(job_id, lease_owner=lease_owner))


async def _process_curriculum_job_async(
    job_id: str,
    *,
    lease_owner: str | None,
) -> dict[str, Any]:
    async with async_session_maker() as db:
        job = await db.get(CurriculumGenerationJob, job_id)
        if job is None:
            return {"status": "missing", "job_id": job_id}
        if job.state != GenerationState.RUNNING:
            return {"status": "ignored", "state": _state_value(job.state)}
        owner = lease_owner or job.lease_owner
        if owner is None or job.lease_owner != owner:
            return {"status": "ignored", "reason": "stale_lease"}
        if not settings.curriculum_enabled:
            job.state = GenerationState.QUEUED
            job.lease_owner = None
            job.lease_expires_at = None
            job.heartbeat_at = None
            job.next_attempt_at = None
            job.last_error_code = "curriculum_disabled"
            job.last_error = "Generation paused by CURRICULUM_ENABLED kill switch"
            await db.commit()
            return {"status": "disabled", "job_id": job_id}
        stage = _stage(job.stage)
        input_json = dict(job.input_json or {})
        # Match seeding and publication lock order: skill -> technique ->
        # module. Holding the skill lock through publication also prevents the
        # final metadata update from inverting against a concurrent seed tick.
        target_snapshot = input_json.get("module_target")
        prerequisite_keys = sorted(
            {
                str(key)
                for key in (
                    target_snapshot.get("prerequisites", [])
                    if isinstance(target_snapshot, dict)
                    else []
                )
                if key
            }
        )
        skill_predicate = CurriculumSkill.id == job.skill_id
        if prerequisite_keys:
            skill_predicate = or_(
                skill_predicate,
                CurriculumSkill.key.in_(prerequisite_keys),
            )
        locked_skills = list(
            (
                await db.execute(
                    select(CurriculumSkill)
                    .where(skill_predicate)
                    .order_by(CurriculumSkill.id.asc())
                    .with_for_update(of=CurriculumSkill)
                )
            )
            .scalars()
            .all()
        )
        locked_skill = next(
            (skill for skill in locked_skills if skill.id == job.skill_id),
            None,
        )
        locked_prerequisites = {
            skill.key: skill
            for skill in locked_skills
            if skill.key in prerequisite_keys
            and skill.status == CurriculumSkillStatus.ACTIVE
        }
        if locked_skill is None or set(locked_prerequisites) != set(prerequisite_keys):
            missing_reason = (
                "Pinned curriculum skill no longer exists"
                if locked_skill is None
                else "A pinned prerequisite skill is missing or inactive"
            )
            missing_code = (
                "curriculum_skill_missing"
                if locked_skill is None
                else "curriculum_prerequisite_missing"
            )
            job.state = GenerationState.FLAGGED
            job.completed_at = datetime.now(timezone.utc)
            job.lease_owner = None
            job.lease_expires_at = None
            job.heartbeat_at = None
            job.last_error_code = missing_code
            job.last_error = missing_reason
            await db.commit()
            return {
                "status": "skill_missing",
                "job_id": job_id,
                "error_code": missing_code,
            }
        persisted_recipe = input_json.get("recipe_provenance")
        current_recipe = _curriculum_recipe_provenance()
        recipe_current = _recipe_is_current(persisted_recipe, current_recipe)
        definition_current = _pilot_definition_is_current(input_json)
        technique_manifest_current = await _technique_manifest_is_current(
            db,
            input_json,
            lock=True,
        )
        if (
            not recipe_current
            or not definition_current
            or not technique_manifest_current
        ):
            await _reconcile_job_usage(db, job)
            definition_snapshot = input_json.get("pilot_definition")
            definition_skill_key = (
                str(definition_snapshot.get("skill_key") or "")
                if isinstance(definition_snapshot, dict)
                else ""
            )
            current_definition = next(
                (
                    definition
                    for definition in PILOT_SKILLS
                    if definition.skill_key == definition_skill_key
                ),
                None,
            )
            _mark_job_recipe_changed(
                job,
                persisted_recipe=persisted_recipe,
                current_recipe=current_recipe,
                now=datetime.now(timezone.utc),
                identity_change={
                    "persisted_definition_hash": input_json.get(
                        "pilot_definition_hash"
                    ),
                    "current_definition_hash": (
                        sha256_json(current_definition.model_dump(mode="json"))
                        if current_definition is not None
                        else None
                    ),
                    "persisted_technique_manifest_hash": input_json.get(
                        "technique_version_manifest_hash"
                    ),
                    "technique_manifest_current": technique_manifest_current,
                },
            )
            result_status = "recipe_changed"
            if not technique_manifest_current:
                job.last_error_code = "technique_version_revoked"
                job.last_error = (
                    "A pinned learning-technique version was revoked, changed, or "
                    "is no longer published"
                )
                result_status = "technique_version_revoked"
            await db.commit()
            curriculum_control_tick.apply_async(queue="curriculum_control")
            return {"status": result_status, "job_id": job_id}
        if stage == PipelineStage.PUBLISH:
            try:
                return await _publish_curriculum_job(db, job, lease_owner=owner)
            except Exception as exc:
                await db.rollback()
                logger.exception("[CURRICULUM] Job %s publish failed", job_id)
                return await _record_stage_failure(
                    job_id=job_id,
                    lease_owner=owner,
                    stage=stage,
                    error=exc,
                )
        checkpoints = dict(job.checkpoints_json or {})
        repair_attempts = int(job.repair_attempts or 0)
        module_id = str(job.module_id) if job.module_id else None
        running_other_rows = list(
            (
                await db.execute(
                    select(
                        CurriculumGenerationJob.stage,
                        CurriculumGenerationJob.input_json,
                    ).where(
                        CurriculumGenerationJob.state == GenerationState.RUNNING,
                        CurriculumGenerationJob.id != job.id,
                    )
                )
            ).all()
        )
        budget = await get_curriculum_budget_status(
            db,
            running_jobs=len(running_other_rows),
            reserved_usd=sum(
                _running_job_reserve(other_stage, other_input)
                for other_stage, other_input in running_other_rows
            ),
        )
        checkpoints, authoritative_usage = await _reconcile_job_usage(
            db,
            job,
            checkpoints=checkpoints,
        )
        stage_reserve = (
            0.0
            if stage == PipelineStage.SOURCE_RESEARCH
            and input_json.get("approved_source_manifest") is not None
            else curriculum_stage_reserve_usd(stage.value)
        )
        job_limit = (
            float(job.budget_limit_usd) if job.budget_limit_usd is not None else None
        )
        if not curriculum_job_budget_allows_stage(
            spent_usd=max(
                float(job.cost_usd or 0),
                float(job.estimated_cost_usd or 0),
            ),
            budget_limit_usd=job_limit,
            reserve_usd=stage_reserve,
        ):
            job.state = GenerationState.FLAGGED
            job.completed_at = datetime.now(timezone.utc)
            job.lease_owner = None
            job.lease_expires_at = None
            job.heartbeat_at = None
            job.next_attempt_at = None
            job.last_error_code = "curriculum_job_budget_exhausted"
            job.last_error = "Per-job curriculum budget cannot admit the next stage"
            await db.commit()
            return {"status": "job_budget_exhausted", "job_id": job_id}
        if not curriculum_budget_allows_stage(
            budget,
            additional_reserve_usd=stage_reserve,
        ):
            job.state = GenerationState.RETRY_WAIT
            job.lease_owner = None
            job.lease_expires_at = None
            job.heartbeat_at = None
            job.next_attempt_at = _tomorrow_after_midnight(datetime.now(timezone.utc))
            job.last_error_code = "curriculum_budget_deferred"
            job.last_error = "Deferred before provider call by curriculum daily budget"
            await db.commit()
            return {
                "status": "deferred_budget",
                "job_id": job_id,
                "next_attempt_at": job.next_attempt_at.isoformat(),
            }
        checkpoints = _reserve_job_attempt(
            job,
            checkpoints=checkpoints,
            stage=stage.value,
            reserve_usd=stage_reserve,
            actual_cost_before_usd=authoritative_usage.estimated_cost_usd,
        )
        job.heartbeat_at = datetime.now(timezone.utc)
        job.lease_expires_at = datetime.now(timezone.utc) + timedelta(
            seconds=max(settings.curriculum_lease_seconds, 60)
        )
        await db.commit()

    try:
        stage_checkpoints = checkpoints
        if stage == PipelineStage.ORIGINALITY_REVIEW:
            originality_corpus = await _load_comparison_corpus(module_id)
            stage_checkpoints = {
                **checkpoints,
                "originality_corpus_manifest": originality_corpus["versions"],
                "originality_corpus_hash": originality_corpus["corpus_hash"],
            }
        dependencies = _stage_dependencies(
            stage=stage,
            job_input=input_json,
            checkpoints=stage_checkpoints,
            repair_attempts=repair_attempts,
        )
        stage_hash = stage_input_hash(
            identity_hash=str(input_json.get("identity_hash") or job_id),
            stage=stage.value,
            pipeline_version=PIPELINE_VERSION,
            prompt_version=PROMPT_VERSION,
            inputs=dependencies,
        )
        result = await _run_stage(
            stage=stage,
            job_input=input_json,
            checkpoints=stage_checkpoints,
            repair_attempts=repair_attempts,
            module_id=module_id,
            job_id=job_id,
        )
    except Exception as exc:
        logger.exception("[CURRICULUM] Job %s stage %s failed", job_id, stage.value)
        return await _record_stage_failure(
            job_id=job_id,
            lease_owner=owner,
            stage=stage,
            error=exc,
        )

    now = datetime.now(timezone.utc)
    async with async_session_maker() as db:
        job = await db.get(CurriculumGenerationJob, job_id, with_for_update=True)
        if job is None:
            return {"status": "missing", "job_id": job_id}
        if job.state != GenerationState.RUNNING or job.lease_owner != owner:
            return {"status": "ignored", "reason": "lease_changed_after_stage"}
        updated = _checkpoint_stage(
            dict(job.checkpoints_json or {}),
            stage=stage,
            input_hash=stage_hash,
            updates=result.updates,
            model_usage=result.model_usage,
            completed_at=now,
        )
        if not result.passed:
            updated["repair_issues"] = list(result.issues)
            transition = transition_after_gate_failure(
                stage,
                repair_attempts=int(job.repair_attempts or 0),
                max_repairs=int(job.max_repairs or 0),
            )
            job.repair_attempts = transition.repair_attempts
            if transition.terminal:
                job.state = GenerationState.FLAGGED
                job.completed_at = now
                job.next_attempt_at = None
                status = "flagged"
            else:
                job.stage = _stage_enum(transition.stage)
                job.state = GenerationState.QUEUED
                job.next_attempt_at = now
                status = "repair_queued"
            job.last_error_code = "quality_gate_failed"
            job.last_error = "; ".join(
                str(issue.get("description") or issue.get("code") or "quality issue")
                for issue in result.issues[:12]
            )[:4000]
        else:
            transition = transition_after_success(
                stage,
                repair_attempts=int(job.repair_attempts or 0),
            )
            job.stage = _stage_enum(transition.stage)
            job.state = GenerationState.QUEUED
            job.next_attempt_at = now
            job.attempts = 0
            job.last_error_code = None
            job.last_error = None
            status = "stage_completed"
        updated, _ = await _reconcile_job_usage(
            db,
            job,
            checkpoints=updated,
        )
        job.lease_owner = None
        job.lease_expires_at = None
        job.heartbeat_at = None
        await db.commit()

    if status != "flagged":
        curriculum_control_tick.apply_async(queue="curriculum_control")
    return {
        "status": status,
        "job_id": job_id,
        "completed_stage": stage.value,
        "next_stage": transition.stage.value,
        "repair_attempts": transition.repair_attempts,
        "quality_score": result.quality_score,
    }


def _review_type(name: str) -> QualityReviewType:
    return {
        "structure": QualityReviewType.SCHEMA,
        "factual": QualityReviewType.FACTUAL,
        "pedagogy": QualityReviewType.PEDAGOGY,
        "originality": QualityReviewType.ORIGINALITY,
    }[name]


def _validated_revocation_reason(reason: str) -> str:
    normalized = " ".join(str(reason or "").split())
    if not normalized:
        raise ValueError("canonical revocation requires a non-empty reason")
    return normalized[:2000]


async def _call_canonical_revoke_helper(
    db,
    *,
    module_version_id: str,
    reason: str,
) -> dict[str, int]:
    from app.services.planning.catalog_lessons import (
        revoke_canonical_module_version_and_invalidate,
    )

    return await revoke_canonical_module_version_and_invalidate(
        db,
        module_version_id=module_version_id,
        reason=reason,
    )


@celery_app.task(
    name="app.tasks.curriculum.revoke_canonical_module_version",
    acks_late=True,
    reject_on_worker_lost=True,
)
def revoke_canonical_module_version(
    module_version_id: str,
    reason: str,
) -> dict[str, Any]:
    return run_async(
        _revoke_canonical_module_version_async(
            module_version_id=module_version_id,
            reason=reason,
        )
    )


async def _revoke_canonical_module_version_async(
    *,
    module_version_id: str,
    reason: str,
    db_factory=None,
) -> dict[str, Any]:
    module_version_id = str(module_version_id or "").strip()
    if not module_version_id:
        raise ValueError("canonical revocation requires module_version_id")
    normalized_reason = _validated_revocation_reason(reason)
    factory = db_factory or async_session_maker
    async with factory() as db:
        current_status = await db.scalar(
            select(CanonicalModuleVersion.status).where(
                CanonicalModuleVersion.id == module_version_id
            )
        )
        if current_status is None:
            return {"status": "missing", "module_version_id": module_version_id}
        already_revoked = current_status == VersionStatus.REVOKED
        if already_revoked:
            await db.commit()
            return {
                "status": "already_revoked",
                "module_version_id": module_version_id,
                "reason": normalized_reason,
                "invalidated": {
                    "personalized_versions": 0,
                    "assignments": 0,
                    "plan_items": 0,
                },
            }
        invalidated = await _call_canonical_revoke_helper(
            db,
            module_version_id=module_version_id,
            reason=normalized_reason,
        )
        await db.commit()
    return {
        "status": "revoked",
        "module_version_id": module_version_id,
        "reason": normalized_reason,
        "invalidated": invalidated,
    }


async def _publish_curriculum_job(
    db,
    job: CurriculumGenerationJob,
    *,
    lease_owner: str,
) -> dict[str, Any]:
    if job.lease_owner != lease_owner:
        return {"status": "ignored", "reason": "stale_publish_lease"}
    if job.module_version_id:
        existing = await db.get(CanonicalModuleVersion, job.module_version_id)
        if existing is not None and existing.status == VersionStatus.PUBLISHED:
            job.state = GenerationState.COMPLETED
            job.completed_at = job.completed_at or datetime.now(timezone.utc)
            job.lease_owner = None
            job.lease_expires_at = None
            await db.commit()
            return {"status": "already_published", "version_id": str(existing.id)}

    checkpoints = dict(job.checkpoints_json or {})
    draft = _checkpoint_model(checkpoints, "draft", CanonicalModuleDraft)
    manifest = _checkpoint_model(checkpoints, "source_manifest", ResearchManifest)
    plan = _checkpoint_model(checkpoints, "technique_plan", TechniquePlan)
    reviews_map = checkpoints.get("reviews")
    if not isinstance(reviews_map, dict):
        raise ValueError("publish stage is missing independent reviews")
    bundle = ReviewBundle.model_validate({"reviews": list(reviews_map.values())})
    # Serialize the live-corpus recheck with every other publisher. PostgreSQL
    # releases this transaction-level advisory lock automatically at commit.
    await db.execute(
        select(func.pg_advisory_xact_lock(ORIGINALITY_PUBLICATION_LOCK_KEY))
    )
    publication_corpus = await _comparison_corpus(
        db,
        str(job.module_id) if job.module_id else None,
    )
    if checkpoints.get("originality_corpus_hash") != publication_corpus["corpus_hash"]:
        # The independent originality verdict is bound to its exact corpus.
        # A deterministic live gate cannot make a stale semantic review current,
        # so return to that review stage instead of publishing across the drift.
        reviews = dict(checkpoints.get("reviews") or {})
        reviews.pop("originality", None)
        checkpoints["reviews"] = reviews
        checkpoints.pop("originality_corpus_manifest", None)
        checkpoints.pop("originality_corpus_hash", None)
        job.checkpoints_json = checkpoints
        job.stage = GenerationStage.ORIGINALITY_REVIEW
        job.state = GenerationState.QUEUED
        job.next_attempt_at = datetime.now(timezone.utc)
        job.completed_at = None
        job.lease_owner = None
        job.lease_expires_at = None
        job.heartbeat_at = None
        job.attempts = 0
        job.last_error_code = "originality_corpus_changed"
        job.last_error = "Published comparison corpus changed after originality review"
        await db.commit()
        curriculum_control_tick.apply_async(queue="curriculum_control")
        return {"status": "originality_review_queued", "job_id": str(job.id)}
    comparisons = _comparison_corpus_texts(publication_corpus)
    module_target = _module_target(dict(job.input_json or {}))
    gate = publication_gate(
        draft=draft,
        manifest=manifest,
        technique_plan=plan,
        reviews=bundle,
        comparison_texts=comparisons,
        module_target=module_target,
        durable_spacing_scheduler_enabled=(
            settings.curriculum_durable_spacing_scheduler_enabled
        ),
    )
    if not gate.passed:
        checkpoints["repair_issues"] = [
            issue.model_dump(mode="json") for issue in gate.issues
        ]
        transition = transition_after_gate_failure(
            PipelineStage.PUBLISH,
            repair_attempts=int(job.repair_attempts or 0),
            max_repairs=int(job.max_repairs or 0),
        )
        job.repair_attempts = transition.repair_attempts
        job.checkpoints_json = checkpoints
        job.lease_owner = None
        job.lease_expires_at = None
        job.heartbeat_at = None
        job.last_error_code = "publication_gate_changed"
        job.last_error = "; ".join(issue.description for issue in gate.issues)[:4000]
        if transition.terminal:
            job.state = GenerationState.FLAGGED
            job.completed_at = datetime.now(timezone.utc)
            status = "flagged"
        else:
            job.stage = GenerationStage.WRITING
            job.state = GenerationState.QUEUED
            job.next_attempt_at = datetime.now(timezone.utc)
            status = "repair_queued"
        await db.commit()
        if status == "repair_queued":
            curriculum_control_tick.apply_async(queue="curriculum_control")
        return {
            "status": status,
            "job_id": str(job.id),
            "repair_attempts": transition.repair_attempts,
        }
    sessions = pack_session_blocks(draft)
    module = await db.get(CanonicalModule, job.module_id, with_for_update=True)
    if module is None:
        raise ValueError("publish stage has no canonical module")
    latest_number = int(
        (
            await db.execute(
                select(
                    func.coalesce(func.max(CanonicalModuleVersion.version_number), 0)
                ).where(CanonicalModuleVersion.module_id == module.id)
            )
        ).scalar_one()
        or 0
    )
    now = datetime.now(timezone.utc)
    content_json = draft.model_dump(mode="json")
    source_json = manifest.model_dump(mode="json")
    plan_json = plan.model_dump(mode="json")
    writing_usage = (checkpoints.get("model_usage") or {}).get("writing") or {}
    writer_model = str(
        (
            writing_usage.get("writer", {}).get("model")
            if isinstance(writing_usage.get("writer"), dict)
            else writing_usage.get("model")
        )
        or "unknown"
    )
    if writer_model == "unknown":
        raise ValueError("publish stage lacks pinned writer model provenance")
    all_usage = checkpoints.get("model_usage") or {}
    reviewer_models = {
        "structure": (
            ((all_usage.get("writing") or {}).get("structure_reviewer") or {}).get(
                "model"
            )
        ),
        "factual": (all_usage.get("factual_review") or {}).get("model"),
        "pedagogy": (all_usage.get("pedagogy_review") or {}).get("model"),
        "originality": (all_usage.get("originality_review") or {}).get("model"),
    }
    if any(not model or model == "unknown" for model in reviewer_models.values()):
        raise ValueError(
            "publish stage lacks exact independent reviewer model provenance"
        )
    retrieval_metadata = {
        "title": draft.title,
        "skill_key": draft.skill_key,
        "domain": module_target["domain"],
        "level": draft.level,
        "locale": draft.locale,
        "learning_outcome": draft.learning_outcome,
        "artifact_type": module_target["artifact_type"],
        "prerequisites": list(module_target.get("prerequisites") or []),
        "pilot_definition_hash": (job.input_json or {}).get("pilot_definition_hash"),
        "recipe_hash": sha256_json(
            (job.input_json or {}).get("recipe_provenance") or {}
        ),
        "technique_version_manifest": (job.input_json or {}).get(
            "technique_version_manifest"
        ),
        "technique_version_manifest_hash": (job.input_json or {}).get(
            "technique_version_manifest_hash"
        ),
        "originality_stage_corpus_manifest": checkpoints.get(
            "originality_corpus_manifest"
        ),
        "originality_stage_corpus_hash": checkpoints.get("originality_corpus_hash"),
        "publication_corpus_manifest": publication_corpus["versions"],
        "publication_corpus_hash": publication_corpus["corpus_hash"],
        "spacing_follow_up_days": plan.spacing_follow_up_days,
    }
    version = CanonicalModuleVersion(
        module_id=module.id,
        version_number=latest_number + 1,
        supersedes_version_id=module.current_published_version_id,
        status=VersionStatus.DRAFT,
        content_json=content_json,
        source_manifest_json=source_json,
        technique_plan_json=plan_json,
        content_hash=sha256_json(content_json),
        source_hash=sha256_json(source_json),
        estimated_minutes=draft.estimated_minutes,
        quality_score=gate.score,
        prompt_version=PROMPT_VERSION,
        gate_version=QUALITY_GATE_VERSION,
        model_name=writer_model,
        published_at=None,
        retrieval_metadata_json=retrieval_metadata,
        retrieval_metadata_hash=sha256_json(retrieval_metadata),
    )
    db.add(version)
    await db.flush()
    for position, session_blocks in enumerate(sessions, start=1):
        block_json = [block.model_dump(mode="json") for block in session_blocks]
        session_content = {
            "blocks": block_json,
            "follow_up_days": sorted(
                {
                    block.follow_up_day
                    for block in session_blocks
                    if block.follow_up_day is not None
                }
            ),
        }
        assessment_blocks = [
            block.model_dump(mode="json")
            for block in session_blocks
            if block.block_type.value == "assessment"
        ]
        db.add(
            ModuleSession(
                module_version_id=version.id,
                position=position,
                title=(
                    session_blocks[0].title
                    if len(session_blocks) == 1
                    else f"Session {position}: {session_blocks[0].title}"
                ),
                learning_objective=draft.learning_outcome,
                estimated_minutes=sum(block.minutes for block in session_blocks),
                content_json=session_content,
                assessment_json={"blocks": assessment_blocks},
                artifact_spec_json={
                    "description": draft.artifact_description,
                    "rubric": [item.model_dump(mode="json") for item in draft.rubric],
                },
                technique_plan_json={
                    **plan_json,
                    "session_technique_ids": sorted(
                        {
                            technique.value
                            for block in session_blocks
                            for technique in block.technique_ids
                        }
                    ),
                },
                content_hash=sha256_json(session_content),
            )
        )
    attempt = int(job.repair_attempts or 0) + 1
    for review in bundle.reviews:
        verdict = (
            QualityVerdict.PASSED
            if review.passed and review.score >= MIN_REVIEW_SCORE
            else QualityVerdict.NEEDS_REPAIR
        )
        db.add(
            ModuleQualityReport(
                module_version_id=version.id,
                generation_job_id=job.id,
                review_type=_review_type(review.reviewer),
                verdict=verdict,
                score=review.score,
                attempt=attempt,
                reviewed_content_hash=version.content_hash,
                issues_json=[issue.model_dump(mode="json") for issue in review.issues],
                evidence_json={"items": review.evidence},
                deterministic_checks_json=gate.metrics,
                repair_instructions_json={
                    "items": [issue.repair_instruction for issue in review.issues]
                },
                reviewer_model=str(reviewer_models[review.reviewer]),
                prompt_version=PROMPT_VERSION,
            )
        )
    # Children must exist before the immutable publication guard activates.
    await db.flush()
    version.status = VersionStatus.PUBLISHED
    version.published_at = now
    # The module pointer guard observes database state, so persist the parent
    # lifecycle transition before pointing the module at this version.
    await db.flush()
    module.title = draft.title
    module.learning_outcome = draft.learning_outcome
    module.level = SkillLevel(module_target["level"])
    module.language = str(module_target["locale"])
    module.artifact_type = str(module_target["artifact_type"])
    module.current_published_version_id = version.id
    module.status = CurriculumSkillStatus.ACTIVE
    module.estimated_total_minutes = draft.estimated_minutes
    skill = await db.get(CurriculumSkill, job.skill_id)
    if skill is not None:
        skill.domain = str(module_target["domain"])
        skill.name = str(module_target["title"])
        skill.description = str(module_target["learning_outcome"])
        skill.skill_type = "applied"
        skill.tags_json = [
            str(module_target["level"]),
            str(module_target["locale"]),
            str(module_target["taxonomy_version"]),
        ]
        prerequisite_keys = list(module_target.get("prerequisites") or [])
        prerequisites = list(
            (
                await db.execute(
                    select(CurriculumSkill).where(
                        CurriculumSkill.key.in_(prerequisite_keys)
                    )
                )
            ).scalars()
        )
        if {item.key for item in prerequisites} != set(prerequisite_keys):
            raise ValueError("publish target references an unknown prerequisite skill")
        skill.prerequisites = prerequisites
        skill.status = CurriculumSkillStatus.ACTIVE
    job.module_version_id = version.id
    job.target_version_number = version.version_number
    job.state = GenerationState.COMPLETED
    job.completed_at = now
    job.lease_owner = None
    job.lease_expires_at = None
    job.heartbeat_at = None
    job.next_attempt_at = None
    job.last_error_code = None
    job.last_error = None
    checkpoints["published_version"] = {
        "version_id": str(version.id),
        "version_number": version.version_number,
        "content_hash": version.content_hash,
        "source_hash": version.source_hash,
        "published_at": now.isoformat(),
    }
    checkpoints["publication_originality_corpus"] = publication_corpus
    job.checkpoints_json = checkpoints
    await db.commit()
    return {
        "status": "published",
        "job_id": str(job.id),
        "module_id": str(module.id),
        "version_id": str(version.id),
        "version_number": version.version_number,
        "sessions": len(sessions),
        "quality_score": gate.score,
    }


@celery_app.task(
    bind=True,
    name="app.tasks.curriculum.curate_mentor_evidence",
    acks_late=True,
    reject_on_worker_lost=True,
)
def curate_mentor_evidence(
    self,
    idol_id: str,
    expected_source_hash: str,
    reservation_job_id: str,
    lease_owner: str,
) -> dict[str, Any]:
    del self
    try:
        return run_async(
            _curate_mentor_evidence_async(
                idol_id=idol_id,
                expected_source_hash=expected_source_hash,
                reservation_job_id=reservation_job_id,
                lease_owner=lease_owner,
            )
        )
    except Exception as exc:
        run_async(
            _record_mentor_failure(
                reservation_job_id=reservation_job_id,
                lease_owner=lease_owner,
                error=exc,
            )
        )
        raise


async def _record_mentor_failure(
    *,
    reservation_job_id: str,
    lease_owner: str,
    error: Exception,
) -> None:
    now = datetime.now(timezone.utc)
    async with async_session_maker() as db:
        marker = await db.get(
            CurriculumGenerationJob,
            reservation_job_id,
            with_for_update=True,
        )
        if (
            marker is None
            or marker.state != GenerationState.RUNNING
            or marker.lease_owner != lease_owner
        ):
            return
        await _reconcile_job_usage(db, marker)
        marker.attempts = min(int(marker.attempts or 0) + 1, marker.max_attempts)
        retryable = marker.attempts < marker.max_attempts
        marker.state = (
            GenerationState.RETRY_WAIT if retryable else GenerationState.FAILED
        )
        marker.next_attempt_at = (
            now + timedelta(seconds=retry_delay_seconds(marker.attempts))
            if retryable
            else None
        )
        marker.completed_at = None if retryable else now
        marker.lease_owner = None
        marker.lease_expires_at = None
        marker.heartbeat_at = None
        marker.last_error_code = "mentor_curation_failure"
        marker.last_error = str(error)[:4000]
        await db.commit()


async def _flag_active_job_recipe_changed(
    *,
    job_id: str,
    lease_owner: str,
    current_recipe: dict[str, Any],
    error_code: str = "recipe_changed",
    identity_change: dict[str, Any] | None = None,
) -> dict[str, Any]:
    async with async_session_maker() as db:
        marker = await db.get(
            CurriculumGenerationJob,
            job_id,
            with_for_update=True,
        )
        if (
            marker is None
            or marker.state != GenerationState.RUNNING
            or marker.lease_owner != lease_owner
        ):
            return {"status": "ignored", "reason": "lease_changed"}
        await _reconcile_job_usage(db, marker)
        persisted_recipe = (marker.input_json or {}).get("recipe_provenance")
        _mark_job_recipe_changed(
            marker,
            persisted_recipe=persisted_recipe,
            current_recipe=current_recipe,
            now=datetime.now(timezone.utc),
            identity_change=identity_change,
        )
        marker.last_error_code = error_code
        await db.commit()
    curriculum_control_tick.apply_async(queue="curriculum_control")
    return {"status": error_code, "job_id": job_id}


def _mentor_candidate_id(candidate: MentorClaimCandidate) -> str:
    return f"mentor_{sha256_json(candidate.model_dump(mode='json'))[:24]}"


def _mentor_claim_normalized_hash(
    *,
    idol_id: str,
    candidate: MentorClaimCandidate,
    source_hash: str,
    corpus_hash: str,
    recipe_hash: str,
    mentor_context_hash: str,
) -> str:
    return sha256_json(
        {
            "idol_id": idol_id,
            "claim_type": candidate.claim_type,
            "claim": " ".join(candidate.normalized_claim.casefold().split()),
            "evidence_version": source_hash,
            "corpus_hash": corpus_hash,
            "recipe_hash": recipe_hash,
            "mentor_context_hash": mentor_context_hash,
        }
    )


def _mentor_claim_is_current(
    claim: Any,
    *,
    source_hash: str,
    corpus_hash: str,
    recipe_hash: str,
    mentor_context_hash: str,
) -> bool:
    evidence = claim.evidence_json if isinstance(claim.evidence_json, dict) else {}
    return (
        claim.verification_status == EvidenceVerificationStatus.VERIFIED
        and claim.revoked_at is None
        and claim.source_hash == source_hash
        and evidence.get("corpus_hash") == corpus_hash
        and evidence.get("recipe_hash") == recipe_hash
        and evidence.get("mentor_context_hash") == mentor_context_hash
    )


def _supersede_outdated_mentor_claims(
    claims: list[Any],
    *,
    source_hash: str,
    corpus_hash: str,
    recipe_hash: str,
    mentor_context_hash: str,
    reason: str,
    now: datetime,
) -> tuple[bool, set[str]]:
    if any(
        _mentor_claim_is_current(
            claim,
            source_hash=source_hash,
            corpus_hash=corpus_hash,
            recipe_hash=recipe_hash,
            mentor_context_hash=mentor_context_hash,
        )
        for claim in claims
    ):
        return True, set()
    revoked_ids: set[str] = set()
    for claim in claims:
        if claim.verification_status == EvidenceVerificationStatus.VERIFIED:
            claim.verification_status = EvidenceVerificationStatus.REVOKED
            claim.revoked_at = now
            claim.revocation_reason = reason
            revoked_ids.add(str(claim.id))
    return False, revoked_ids


def _revoke_unrepresented_mentor_claims(
    claims: list[Any],
    *,
    authoritative_claim_ids: set[str],
    reason: str,
    now: datetime,
) -> set[str]:
    revoked_ids: set[str] = set()
    for claim in claims:
        if (
            claim.verification_status == EvidenceVerificationStatus.VERIFIED
            and str(claim.id) not in authoritative_claim_ids
        ):
            claim.verification_status = EvidenceVerificationStatus.REVOKED
            claim.revoked_at = now
            claim.revocation_reason = reason
            revoked_ids.add(str(claim.id))
    return revoked_ids


def _mentor_claim_overlap(claim: str, support: str) -> float:
    import re

    stopwords = {
        "about",
        "after",
        "also",
        "and",
        "are",
        "for",
        "from",
        "has",
        "have",
        "that",
        "the",
        "their",
        "this",
        "was",
        "were",
        "with",
    }
    claim_tokens = {
        token
        for token in re.findall(r"[^\W_]+", claim.casefold(), flags=re.UNICODE)
        if len(token) >= 3 and token not in stopwords
    }
    support_tokens = {
        token
        for token in re.findall(r"[^\W_]+", support.casefold(), flags=re.UNICODE)
        if len(token) >= 3 and token not in stopwords
    }
    if not claim_tokens:
        return 0.0
    return len(claim_tokens & support_tokens) / len(claim_tokens)


def _mentor_verification_pack(
    curation: MentorClaimCuration,
    chunks: dict[str, dict[str, Any]],
) -> tuple[dict[str, MentorClaimCandidate], list[dict[str, Any]]]:
    candidates: dict[str, MentorClaimCandidate] = {}
    pack: list[dict[str, Any]] = []
    for candidate in curation.claims:
        if not candidate.source_chunk_ids or any(
            chunk_id not in chunks for chunk_id in candidate.source_chunk_ids
        ):
            continue
        candidate_id = _mentor_candidate_id(candidate)
        if candidate_id in candidates:
            continue
        candidates[candidate_id] = candidate
        pack.append(
            {
                "candidate_id": candidate_id,
                "claim_type": candidate.claim_type,
                "normalized_claim": candidate.normalized_claim,
                "bound_chunks": [
                    {
                        "source_chunk_id": chunk_id,
                        "source_title": chunks[chunk_id]["source_title"],
                        "source_url": chunks[chunk_id]["source_url"],
                        "text": chunks[chunk_id]["text"],
                    }
                    for chunk_id in candidate.source_chunk_ids
                ],
            }
        )
    return candidates, pack


def _accepted_mentor_candidates(
    *,
    candidates: dict[str, MentorClaimCandidate],
    bundle: MentorClaimVerificationBundle,
    chunks: dict[str, dict[str, Any]],
) -> list[tuple[MentorClaimCandidate, Any, float]]:
    verifications = {item.candidate_id: item for item in bundle.verifications}
    if set(verifications) != set(candidates):
        raise ValueError("mentor verifier must return every and only candidate ID")
    accepted = []
    for candidate_id, candidate in candidates.items():
        verification = verifications[candidate_id]
        supported_ids = set(verification.supported_source_chunk_ids)
        if not supported_ids.issubset(candidate.source_chunk_ids):
            raise ValueError("mentor verifier invented or rebound a source chunk ID")
        support = " ".join(chunks[chunk_id]["text"] for chunk_id in supported_ids)
        overlap = _mentor_claim_overlap(candidate.normalized_claim, support)
        if (
            candidate.confidence >= MENTOR_CONFIDENCE_FLOOR
            and verification.passed
            and verification.confidence >= MENTOR_CONFIDENCE_FLOOR
            and supported_ids
            and overlap >= MENTOR_LEXICAL_OVERLAP_FLOOR
        ):
            accepted.append((candidate, verification, overlap))
    return accepted


async def _invalidate_mentor_evidence_dependents(
    db,
    *,
    mentor_evidence_ids: set[str],
    reason: str,
) -> dict[str, int]:
    """Revoke READY artifacts that rendered any newly revoked mentor claim."""

    claim_ids = {str(value) for value in mentor_evidence_ids if value}
    if not claim_ids:
        return {"personalized_versions": 0, "assignments": 0, "plan_items": 0}
    predicates = [
        PersonalizedLessonVersion.content_json.contains(
            {"personalization": {"mentor_evidence_ids": [claim_id]}}
        )
        for claim_id in sorted(claim_ids)
    ]
    lesson_result = await db.execute(
        select(PersonalizedLessonVersion)
        .where(
            PersonalizedLessonVersion.status == PersonalizedLessonStatus.READY,
            PersonalizedLessonVersion.revoked_at.is_(None),
            or_(*predicates),
        )
        .order_by(PersonalizedLessonVersion.id.asc())
        .with_for_update(of=PersonalizedLessonVersion)
    )
    lessons = list(lesson_result.scalars().all())
    now = datetime.now(timezone.utc)
    lesson_ids = {str(lesson.id) for lesson in lessons}
    assignments: list[Any] = []
    if lesson_ids:
        # Assignment writes invoke a database guard that takes a shared lock on
        # the owning Plan. Probe the stable parent IDs first, then take the same
        # Plan -> assignment lock order as catalog composition. A concurrent
        # insert/update must also pass through that guard and therefore cannot
        # slip past the parent locks before the authoritative assignment query.
        assignment_owners = list(
            (
                await db.execute(
                    select(PlanLessonAssignment.plan_id)
                    .where(
                        PlanLessonAssignment.personalized_lesson_version_id.in_(
                            lesson_ids
                        )
                    )
                    .distinct()
                    .order_by(PlanLessonAssignment.plan_id.asc())
                )
            )
            .scalars()
            .all()
        )
        if assignment_owners:
            await db.execute(
                select(Plan)
                .where(Plan.id.in_(assignment_owners))
                .order_by(Plan.id.asc())
                .with_for_update(of=Plan)
            )
        assignment_result = await db.execute(
            select(PlanLessonAssignment)
            .where(PlanLessonAssignment.personalized_lesson_version_id.in_(lesson_ids))
            .order_by(PlanLessonAssignment.id.asc())
            .with_for_update(of=PlanLessonAssignment)
        )
        assignments = list(assignment_result.scalars().all())
    plan_item_ids: set[str] = set()
    for assignment in assignments:
        if assignment.plan_item_id:
            plan_item_ids.add(str(assignment.plan_item_id))

    plan_items: list[PlanItem] = []
    if plan_item_ids:
        item_result = await db.execute(
            select(PlanItem)
            .where(PlanItem.id.in_(plan_item_ids))
            .order_by(PlanItem.id.asc())
            .with_for_update(of=PlanItem)
        )
        plan_items = list(item_result.scalars().all())

    # Take the complete cross-table lock set before dirtying ORM rows. Otherwise
    # a later SELECT can autoflush an assignment status update whose database
    # guard recursively locks Plan and personalized rows ahead of PlanItem.
    for lesson in lessons:
        lesson.status = PersonalizedLessonStatus.REVOKED
        lesson.revoked_at = now
        lesson.revocation_reason = reason
    for assignment in assignments:
        if assignment.status in {
            AssignmentStatus.SCHEDULED,
            AssignmentStatus.AVAILABLE,
            AssignmentStatus.IN_PROGRESS,
        }:
            assignment.status = AssignmentStatus.SKIPPED
    invalidated_items = 0
    for plan_item in plan_items:
        details = plan_item.details_json
        if not isinstance(details, dict):
            continue
        generation = details.get("_generation")
        if not isinstance(generation, dict):
            continue
        plan_item.details_json = {
            **details,
            "_generation": {
                **generation,
                "status": "revoked",
                "personalization_status": "revoked",
                "revoked_at": now.isoformat(),
                "revocation_reason": reason,
                "revoked_mentor_evidence_ids": sorted(claim_ids),
            },
        }
        invalidated_items += 1
    await db.flush()
    return {
        "personalized_versions": len(lessons),
        "assignments": len(assignments),
        "plan_items": invalidated_items,
    }


async def _curate_mentor_evidence_async(
    *,
    idol_id: str,
    expected_source_hash: str,
    reservation_job_id: str,
    lease_owner: str,
) -> dict[str, Any]:
    async with async_session_maker() as db:
        marker = await db.get(
            CurriculumGenerationJob,
            reservation_job_id,
            with_for_update=True,
        )
        marker_input = dict(marker.input_json or {}) if marker is not None else {}
        recipe_provenance = marker_input.get("recipe_provenance")
        recipe_hash = marker_input.get("recipe_hash")
        mentor_context = marker_input.get("mentor_context_snapshot")
        mentor_context_hash = marker_input.get("mentor_context_hash")
        if (
            marker is None
            or marker.state != GenerationState.RUNNING
            or marker.lease_owner != lease_owner
            or marker_input.get("job_kind") != MENTOR_JOB_KIND
            or marker_input.get("idol_id") != idol_id
            or marker_input.get("corpus_hash") != expected_source_hash
            or not isinstance(recipe_provenance, dict)
            or not isinstance(recipe_hash, str)
            or sha256_json(recipe_provenance) != recipe_hash
            or not isinstance(mentor_context, dict)
            or not isinstance(mentor_context_hash, str)
            or sha256_json(mentor_context) != mentor_context_hash
        ):
            return {"status": "ignored", "reason": "stale_mentor_reservation"}
        if not settings.curriculum_enabled:
            marker.state = GenerationState.QUEUED
            marker.lease_owner = None
            marker.lease_expires_at = None
            marker.heartbeat_at = None
            marker.next_attempt_at = None
            marker.last_error_code = "curriculum_disabled"
            marker.last_error = "Generation paused by CURRICULUM_ENABLED kill switch"
            await db.commit()
            return {"status": "disabled", "job_id": reservation_job_id}
        current_recipe = _mentor_recipe_provenance()
        if not _recipe_is_current(recipe_provenance, current_recipe):
            _mark_job_recipe_changed(
                marker,
                persisted_recipe=recipe_provenance,
                current_recipe=current_recipe,
                now=datetime.now(timezone.utc),
            )
            await db.commit()
            curriculum_control_tick.apply_async(queue="curriculum_control")
            return {"status": "recipe_changed", "job_id": reservation_job_id}
        marker_checkpoints, authoritative_usage = await _reconcile_job_usage(
            db,
            marker,
        )
        idol = await db.get(Idol, idol_id)
        if idol is None:
            marker.state = GenerationState.FAILED
            marker.completed_at = datetime.now(timezone.utc)
            marker.lease_owner = None
            marker.lease_expires_at = None
            marker.last_error_code = "mentor_missing"
            await db.commit()
            return {"status": "missing", "idol_id": idol_id}
        live_mentor_context = await _mentor_context_from_db(db, idol_id)
        if live_mentor_context != mentor_context:
            _mark_job_recipe_changed(
                marker,
                persisted_recipe=recipe_provenance,
                current_recipe=current_recipe,
                now=datetime.now(timezone.utc),
                identity_change={
                    "persisted_mentor_context_hash": mentor_context_hash,
                    "current_mentor_context_hash": (
                        sha256_json(live_mentor_context)
                        if live_mentor_context is not None
                        else None
                    ),
                },
            )
            marker.last_error_code = "mentor_context_changed"
            await db.commit()
            curriculum_control_tick.apply_async(queue="curriculum_control")
            return {"status": "mentor_context_changed", "job_id": reservation_job_id}
        pack, corpus_hash = await _mentor_corpus(db, idol_id)
        if not pack or corpus_hash != expected_source_hash:
            _mark_job_recipe_changed(
                marker,
                persisted_recipe=recipe_provenance,
                current_recipe=current_recipe,
                now=datetime.now(timezone.utc),
                identity_change={
                    "persisted_corpus_hash": expected_source_hash,
                    "current_corpus_hash": corpus_hash,
                },
            )
            marker.last_error_code = "mentor_corpus_changed"
            marker.last_error = "Mentor source corpus changed before curation"
            await db.commit()
            curriculum_control_tick.apply_async(queue="curriculum_control")
            return {"status": "mentor_corpus_changed", "idol_id": idol_id}
        existing_corpus = await db.scalar(
            select(MentorEvidenceClaim.id)
            .where(
                MentorEvidenceClaim.idol_id == idol_id,
                MentorEvidenceClaim.evidence_json["corpus_hash"].astext == corpus_hash,
                MentorEvidenceClaim.evidence_json["recipe_hash"].astext == recipe_hash,
                MentorEvidenceClaim.evidence_json["mentor_context_hash"].astext
                == mentor_context_hash,
                MentorEvidenceClaim.verification_status
                == EvidenceVerificationStatus.VERIFIED,
                MentorEvidenceClaim.revoked_at.is_(None),
            )
            .limit(1)
        )
        if existing_corpus is not None:
            marker.state = GenerationState.COMPLETED
            marker.completed_at = datetime.now(timezone.utc)
            marker.lease_owner = None
            marker.lease_expires_at = None
            marker.checkpoints_json = {
                **marker_checkpoints,
                "result": "already_curated",
            }
            await db.commit()
            return {"status": "already_curated", "idol_id": idol_id}
        running_other_rows = list(
            (
                await db.execute(
                    select(
                        CurriculumGenerationJob.stage,
                        CurriculumGenerationJob.input_json,
                    ).where(
                        CurriculumGenerationJob.state == GenerationState.RUNNING,
                        CurriculumGenerationJob.id != marker.id,
                    )
                )
            ).all()
        )
        budget = await get_curriculum_budget_status(
            db,
            running_jobs=len(running_other_rows),
            reserved_usd=sum(
                _running_job_reserve(other_stage, other_input)
                for other_stage, other_input in running_other_rows
            ),
        )
        reserve = curriculum_stage_reserve_usd("mentor_evidence")
        if not curriculum_job_budget_allows_stage(
            spent_usd=max(
                float(marker.cost_usd or 0),
                float(marker.estimated_cost_usd or 0),
            ),
            budget_limit_usd=(
                float(marker.budget_limit_usd)
                if marker.budget_limit_usd is not None
                else None
            ),
            reserve_usd=reserve,
        ):
            marker.state = GenerationState.FLAGGED
            marker.completed_at = datetime.now(timezone.utc)
            marker.lease_owner = None
            marker.lease_expires_at = None
            marker.last_error_code = "curriculum_job_budget_exhausted"
            await db.commit()
            return {"status": "job_budget_exhausted", "idol_id": idol_id}
        if not curriculum_budget_allows_stage(
            budget,
            additional_reserve_usd=reserve,
        ):
            marker.state = GenerationState.RETRY_WAIT
            marker.next_attempt_at = _tomorrow_after_midnight(
                datetime.now(timezone.utc)
            )
            marker.lease_owner = None
            marker.lease_expires_at = None
            marker.heartbeat_at = None
            await db.commit()
            return {"status": "deferred_budget", "idol_id": idol_id}
        skill_keys = list(mentor_context["allowed_skill_keys"])
        mentor_json = dict(mentor_context)
        provider_pack, chunks = _mentor_provider_source_pack(pack)
        marker_checkpoints = _reserve_job_attempt(
            marker,
            checkpoints=marker_checkpoints,
            stage="mentor_evidence",
            reserve_usd=reserve,
            actual_cost_before_usd=authoritative_usage.estimated_cost_usd,
        )
        marker.heartbeat_at = datetime.now(timezone.utc)
        marker.lease_expires_at = datetime.now(timezone.utc) + timedelta(
            seconds=max(settings.curriculum_lease_seconds, 60)
        )
        await db.commit()

    current_recipe = _mentor_recipe_provenance()
    if not _recipe_is_current(recipe_provenance, current_recipe):
        return await _flag_active_job_recipe_changed(
            job_id=reservation_job_id,
            lease_owner=lease_owner,
            current_recipe=current_recipe,
        )
    live_mentor_context = await _load_mentor_context(idol_id)
    if live_mentor_context != mentor_context:
        return await _flag_active_job_recipe_changed(
            job_id=reservation_job_id,
            lease_owner=lease_owner,
            current_recipe=current_recipe,
            error_code="mentor_context_changed",
            identity_change={
                "persisted_mentor_context_hash": mentor_context_hash,
                "current_mentor_context_hash": (
                    sha256_json(live_mentor_context)
                    if live_mentor_context is not None
                    else None
                ),
            },
        )
    live_pack, live_corpus_hash = await _load_mentor_corpus(idol_id)
    if live_corpus_hash != corpus_hash or live_pack != pack:
        return await _flag_active_job_recipe_changed(
            job_id=reservation_job_id,
            lease_owner=lease_owner,
            current_recipe=current_recipe,
            error_code="mentor_corpus_changed",
            identity_change={
                "persisted_corpus_hash": corpus_hash,
                "current_corpus_hash": live_corpus_hash,
            },
        )
    tier = configured_tier(settings.curriculum_review_model_tier, default="quality")
    client = get_llm_client(tier=tier, timeout=90, max_tokens=8000, temperature=0.0)
    validated, response = await client.generate_and_validate(
        system_prompt=load_prompt("curriculum_writer_system"),
        user_prompt=load_and_render(
            "curriculum_mentor_claims",
            {"mentor_json": mentor_json, "source_chunks_json": provider_pack},
        ),
        output_model=MentorClaimCuration,
        repair_on_failure=True,
    )
    await record_llm_response(
        operation="curriculum_mentor_claim_curation",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated else "failed",
        metadata={
            "idol_id": idol_id,
            "corpus_hash": corpus_hash,
            "curriculum_job_id": reservation_job_id,
            "stage": "mentor_curation",
        },
    )
    if validated is None or response.error:
        raise RuntimeError(response.error or "mentor evidence curation failed")
    curation = MentorClaimCuration.model_validate(validated)
    candidates, verification_pack = _mentor_verification_pack(curation, chunks)
    current_recipe = _mentor_recipe_provenance()
    if not _recipe_is_current(recipe_provenance, current_recipe):
        return await _flag_active_job_recipe_changed(
            job_id=reservation_job_id,
            lease_owner=lease_owner,
            current_recipe=current_recipe,
        )
    live_mentor_context = await _load_mentor_context(idol_id)
    if live_mentor_context != mentor_context:
        return await _flag_active_job_recipe_changed(
            job_id=reservation_job_id,
            lease_owner=lease_owner,
            current_recipe=current_recipe,
            error_code="mentor_context_changed",
            identity_change={
                "persisted_mentor_context_hash": mentor_context_hash,
                "current_mentor_context_hash": (
                    sha256_json(live_mentor_context)
                    if live_mentor_context is not None
                    else None
                ),
            },
        )
    live_pack, live_corpus_hash = await _load_mentor_corpus(idol_id)
    if live_corpus_hash != corpus_hash or live_pack != pack:
        return await _flag_active_job_recipe_changed(
            job_id=reservation_job_id,
            lease_owner=lease_owner,
            current_recipe=current_recipe,
            error_code="mentor_corpus_changed",
            identity_change={
                "persisted_corpus_hash": corpus_hash,
                "current_corpus_hash": live_corpus_hash,
            },
        )
    verifier = get_llm_client(tier=tier, timeout=90, max_tokens=8000, temperature=0.0)
    verified_payload, verification_response = await verifier.generate_and_validate(
        system_prompt=load_prompt("curriculum_writer_system"),
        user_prompt=load_and_render(
            "curriculum_mentor_claim_verify",
            {
                "mentor_json": mentor_json,
                "claim_support_pack_json": verification_pack,
            },
        ),
        output_model=MentorClaimVerificationBundle,
        repair_on_failure=True,
    )
    await record_llm_response(
        operation="curriculum_mentor_claim_verification",
        response=verification_response,
        model=getattr(verifier, "model", None),
        result_status="schema_valid" if verified_payload else "failed",
        metadata={
            "idol_id": idol_id,
            "corpus_hash": corpus_hash,
            "curriculum_job_id": reservation_job_id,
            "stage": "mentor_verification",
        },
    )
    if verified_payload is None or verification_response.error:
        raise RuntimeError(
            verification_response.error or "mentor claim verification failed"
        )
    verification_bundle = MentorClaimVerificationBundle.model_validate(verified_payload)
    accepted = _accepted_mentor_candidates(
        candidates=candidates,
        bundle=verification_bundle,
        chunks=chunks,
    )
    now = datetime.now(timezone.utc)
    inserted = 0
    async with async_session_maker() as db:
        marker = await db.get(
            CurriculumGenerationJob,
            reservation_job_id,
            with_for_update=True,
        )
        if (
            marker is None
            or marker.state != GenerationState.RUNNING
            or marker.lease_owner != lease_owner
        ):
            return {"status": "ignored", "reason": "mentor_lease_changed"}
        final_recipe = _mentor_recipe_provenance()
        if not _recipe_is_current(recipe_provenance, final_recipe):
            await _reconcile_job_usage(db, marker)
            _mark_job_recipe_changed(
                marker,
                persisted_recipe=recipe_provenance,
                current_recipe=final_recipe,
                now=datetime.now(timezone.utc),
            )
            await db.commit()
            curriculum_control_tick.apply_async(queue="curriculum_control")
            return {"status": "recipe_changed", "job_id": reservation_job_id}
        live_mentor_context = await _mentor_context_from_db(db, idol_id, lock=True)
        if live_mentor_context != mentor_context:
            await _reconcile_job_usage(db, marker)
            _mark_job_recipe_changed(
                marker,
                persisted_recipe=recipe_provenance,
                current_recipe=_mentor_recipe_provenance(),
                now=datetime.now(timezone.utc),
                identity_change={
                    "persisted_mentor_context_hash": mentor_context_hash,
                    "current_mentor_context_hash": (
                        sha256_json(live_mentor_context)
                        if live_mentor_context is not None
                        else None
                    ),
                },
            )
            marker.last_error_code = "mentor_context_changed"
            await db.commit()
            curriculum_control_tick.apply_async(queue="curriculum_control")
            return {"status": "mentor_context_changed", "job_id": reservation_job_id}
        final_pack, final_corpus_hash = await _mentor_corpus(
            db,
            idol_id,
            lock=True,
        )
        if final_corpus_hash != corpus_hash or final_pack != pack:
            await _reconcile_job_usage(db, marker)
            _mark_job_recipe_changed(
                marker,
                persisted_recipe=recipe_provenance,
                current_recipe=final_recipe,
                now=datetime.now(timezone.utc),
                identity_change={
                    "persisted_corpus_hash": corpus_hash,
                    "current_corpus_hash": final_corpus_hash,
                },
            )
            marker.last_error_code = "mentor_corpus_changed"
            marker.last_error = "Mentor source corpus changed before evidence publish"
            await db.commit()
            curriculum_control_tick.apply_async(queue="curriculum_control")
            return {"status": "mentor_corpus_changed", "job_id": reservation_job_id}
        skills = {
            skill.key: skill
            for skill in (
                await db.execute(
                    select(CurriculumSkill).where(CurriculumSkill.key.in_(skill_keys))
                )
            ).scalars()
        }
        # Match the catalog compose lock order: mentor claims (stable ID order)
        # precede personalized versions, assignments, and plan items.
        prior_claims = list(
            (
                await db.execute(
                    select(MentorEvidenceClaim)
                    .where(MentorEvidenceClaim.idol_id == idol_id)
                    .order_by(MentorEvidenceClaim.id)
                    .with_for_update()
                )
            ).scalars()
        )
        revoked_claim_ids: set[str] = set()
        authoritative_claim_ids: set[str] = set()
        supersession_reason = "Superseded by authoritative mentor evidence snapshot"
        for candidate, verification, lexical_overlap in accepted:
            supported_ids = verification.supported_source_chunk_ids
            source = chunks[supported_ids[0]]
            source_hash = sha256_json([chunks[chunk_id] for chunk_id in supported_ids])
            normalized_hash = _mentor_claim_normalized_hash(
                idol_id=idol_id,
                candidate=candidate,
                source_hash=source_hash,
                corpus_hash=corpus_hash,
                recipe_hash=recipe_hash,
                mentor_context_hash=mentor_context_hash,
            )
            normalized_claim_text = " ".join(
                candidate.normalized_claim.casefold().split()
            )
            existing_rows = [
                claim
                for claim in prior_claims
                if claim.claim_type == MentorClaimType(candidate.claim_type)
                and " ".join(claim.claim_text.casefold().split())
                == normalized_claim_text
            ]
            is_current, superseded_ids = _supersede_outdated_mentor_claims(
                existing_rows,
                source_hash=source_hash,
                corpus_hash=corpus_hash,
                recipe_hash=recipe_hash,
                mentor_context_hash=mentor_context_hash,
                reason=supersession_reason,
                now=now,
            )
            if is_current:
                authoritative_claim_ids.update(
                    str(claim.id)
                    for claim in existing_rows
                    if _mentor_claim_is_current(
                        claim,
                        source_hash=source_hash,
                        corpus_hash=corpus_hash,
                        recipe_hash=recipe_hash,
                        mentor_context_hash=mentor_context_hash,
                    )
                )
                continue
            revoked_claim_ids.update(superseded_ids)
            duplicate = await db.scalar(
                select(MentorEvidenceClaim).where(
                    MentorEvidenceClaim.idol_id == idol_id,
                    MentorEvidenceClaim.normalized_hash == normalized_hash,
                )
            )
            if duplicate is not None:
                continue
            evidence = {
                "corpus_hash": corpus_hash,
                "recipe_hash": recipe_hash,
                "recipe_provenance": recipe_provenance,
                "mentor_context_hash": mentor_context_hash,
                "mentor_context_snapshot": mentor_context,
                "source_chunk_ids": [
                    chunks[chunk_id]["source_chunk_id"] for chunk_id in supported_ids
                ],
                "pedagogical_use": candidate.pedagogical_use,
                "curation_model": str(response.model or getattr(client, "model", None)),
                "verification_model": str(
                    verification_response.model or getattr(verifier, "model", None)
                ),
                "verification": verification.model_dump(mode="json"),
                "lexical_overlap": lexical_overlap,
            }
            bound_skills = [
                skills[key] for key in candidate.related_skill_keys if key in skills
            ]
            claim = MentorEvidenceClaim(
                idol_id=idol_id,
                claim_type=MentorClaimType(candidate.claim_type),
                claim_text=candidate.normalized_claim,
                normalized_hash=normalized_hash,
                source_chunk_id=source["source_chunk_id"],
                source_title=source["source_title"],
                source_url=source["source_url"],
                evidence_excerpt=source["text"][:1200],
                evidence_json=evidence,
                source_hash=source_hash,
                skill_tags_json=[skill.key for skill in bound_skills],
                confidence=min(candidate.confidence, verification.confidence),
                verification_status=EvidenceVerificationStatus.PENDING,
            )
            claim.skills = bound_skills
            db.add(claim)
            # The DB permits skill binding only while the claim is pending.
            await db.flush()
            claim.verification_status = EvidenceVerificationStatus.VERIFIED
            claim.verified_at = now
            authoritative_claim_ids.add(str(claim.id))
            inserted += 1
        revoked_claim_ids.update(
            _revoke_unrepresented_mentor_claims(
                prior_claims,
                authoritative_claim_ids=authoritative_claim_ids,
                reason=supersession_reason,
                now=now,
            )
        )
        if revoked_claim_ids:
            # Persist claim state first while keeping the same transaction;
            # no dependent can remain READY after the commit below.
            await db.flush()
        invalidated = await _invalidate_mentor_evidence_dependents(
            db,
            mentor_evidence_ids=revoked_claim_ids,
            reason=supersession_reason,
        )
        final_checkpoints = {
            **dict(marker.checkpoints_json or {}),
            "result": "curated",
            "corpus_hash": corpus_hash,
            "recipe_hash": recipe_hash,
            "candidates": len(curation.claims),
            "verified": len(accepted),
            "inserted": inserted,
            "revoked_claims": len(revoked_claim_ids),
            "invalidated_dependents": invalidated,
        }
        await _reconcile_job_usage(
            db,
            marker,
            checkpoints=final_checkpoints,
        )
        marker.state = GenerationState.COMPLETED
        marker.completed_at = now
        marker.lease_owner = None
        marker.lease_expires_at = None
        marker.heartbeat_at = None
        marker.last_error_code = None
        marker.last_error = None
        await db.commit()
    return {
        "status": "curated",
        "idol_id": idol_id,
        "corpus_hash": corpus_hash,
        "inserted": inserted,
        "revoked_claims": len(revoked_claim_ids),
        "invalidated_dependents": invalidated,
        "candidates": len(curation.claims),
        "verified": len(accepted),
    }
