"""Bounded LLM stages after grounded source discovery."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Literal, TypeVar

from pydantic import BaseModel

from app.services.curriculum.gates import (
    MIN_REVIEW_SCORE,
    TECHNIQUE_BLOCK_REQUIREMENTS,
    GateResult,
    validate_source_attribution,
    validate_manifest_verification,
    validate_source_originality,
    validate_structure,
    validate_technique_implementation,
    validate_module_target,
)
from app.services.curriculum.pilot import TECHNIQUE_REGISTRY
from app.services.curriculum.schemas import (
    CanonicalModuleDraft,
    CurriculumOutline,
    QualityReview,
    RepairResult,
    ResearchManifest,
    ReviewIssue,
    ReviewSeverity,
    TechniquePlan,
    TechniqueId,
)
from app.services.curriculum.security import writer_source_pack
from app.services.llm import get_llm_client
from app.services.llm.prompt_loader import load_and_render, load_prompt
from app.services.llm.telemetry import record_llm_response


T = TypeVar("T", bound=BaseModel)
ReviewerName = Literal["structure", "factual", "pedagogy", "originality"]
_BLOCK_ID_PATTERN = re.compile(r"^block_[a-z0-9][a-z0-9_-]{2,63}$")


@dataclass(frozen=True, slots=True)
class GeneratedArtifact:
    value: BaseModel
    model_name: str
    provider: str | None
    input_tokens: int
    output_tokens: int
    total_tokens: int


def configured_tier(value: str, *, default: str) -> str:
    return value if value in {"fast", "balanced", "quality"} else default


async def _generate(
    *,
    operation: str,
    prompt_name: str,
    prompt_variables: dict[str, Any],
    output_model: type[T],
    tier: str,
    max_tokens: int,
    metadata: dict[str, Any],
) -> GeneratedArtifact:
    client = get_llm_client(
        tier=tier,
        timeout=120,
        max_tokens=max_tokens,
        temperature=0.1,
    )
    validated, response = await client.generate_and_validate(
        system_prompt=load_prompt("curriculum_writer_system"),
        user_prompt=load_and_render(prompt_name, prompt_variables),
        output_model=output_model,
        repair_on_failure=True,
    )
    await record_llm_response(
        operation=operation,
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated else "failed",
        metadata=metadata,
    )
    if validated is None or response.error:
        raise RuntimeError(response.error or f"{operation} returned no artifact")
    value = output_model.model_validate(validated)
    return GeneratedArtifact(
        value=value,
        model_name=str(response.model or getattr(client, "model", None) or "unknown"),
        provider=response.provider,
        input_tokens=int(response.prompt_tokens or 0),
        output_tokens=int(response.completion_tokens or 0),
        total_tokens=int(response.total_tokens or 0),
    )


def _assert_plan_sources(plan: TechniquePlan, manifest: ResearchManifest) -> None:
    source_ids = {source.source_id for source in manifest.sources}
    unknown = sorted(
        {
            source_id
            for application in plan.applications
            for source_id in application.evidence_source_ids
            if source_id not in source_ids
        }
    )
    if unknown:
        raise ValueError(f"technique plan invented source ids: {unknown}")
    source_url_by_id = {source.source_id: source.url for source in manifest.sources}
    registry_urls = {
        item.technique_id: set(item.source_urls) for item in TECHNIQUE_REGISTRY
    }
    missing_registry_evidence = [
        application.technique_id.value
        for application in plan.applications
        if not any(
            source_url_by_id.get(source_id)
            in registry_urls[application.technique_id]
            for source_id in application.evidence_source_ids
        )
    ]
    if missing_registry_evidence:
        raise ValueError(
            "technique plan lacks exact registry evidence for: "
            f"{sorted(missing_registry_evidence)}"
        )


def _registry_evidence_bindings(
    manifest: ResearchManifest,
    *,
    technique_ids: set[TechniqueId],
) -> tuple[dict[TechniqueId, str], set[str]]:
    source_id_by_url = {source.url: source.source_id for source in manifest.sources}
    registry_urls = {
        url for entry in TECHNIQUE_REGISTRY for url in entry.source_urls
    }
    registry_source_ids = {
        source_id
        for url, source_id in source_id_by_url.items()
        if url in registry_urls
    }
    bindings: dict[TechniqueId, str] = {}
    for entry in TECHNIQUE_REGISTRY:
        if entry.technique_id not in technique_ids:
            continue
        source_id = source_id_by_url.get(entry.source_urls[0])
        if source_id is None:
            raise ValueError(
                "research manifest lacks required registry source for: "
                f"{entry.technique_id.value}"
            )
        bindings[entry.technique_id] = source_id
    return bindings, registry_source_ids


def _bind_exact_registry_evidence(
    plan: TechniquePlan,
    manifest: ResearchManifest,
) -> TechniquePlan:
    """Replace ambiguous registry citations with the server-pinned source ID."""

    bindings, registry_source_ids = _registry_evidence_bindings(
        manifest,
        technique_ids={application.technique_id for application in plan.applications},
    )
    applications = []
    for application in plan.applications:
        live_source_ids = [
            source_id
            for source_id in application.evidence_source_ids
            if source_id not in registry_source_ids
        ][:7]
        evidence_source_ids = list(
            dict.fromkeys(
                [*live_source_ids, bindings[application.technique_id]]
            )
        )
        applications.append(
            application.model_copy(
                update={"evidence_source_ids": evidence_source_ids}
            )
        )
    return plan.model_copy(update={"applications": applications})


def _bind_technique_block_contracts(plan: TechniquePlan) -> TechniquePlan:
    """Give every selected technique enough valid, stable implementation IDs."""

    used_ids = {
        block_id
        for application in plan.applications
        for block_id in application.implementation_block_ids
        if _BLOCK_ID_PATTERN.fullmatch(block_id)
    }
    applications = []
    for application in plan.applications:
        block_ids = list(
            dict.fromkeys(
                block_id
                for block_id in application.implementation_block_ids
                if _BLOCK_ID_PATTERN.fullmatch(block_id)
            )
        )
        required_count = len(
            TECHNIQUE_BLOCK_REQUIREMENTS[application.technique_id]
        )
        suffix = 1
        while len(block_ids) < required_count:
            candidate = f"block_{application.technique_id.value}_{suffix}"
            suffix += 1
            if candidate in used_ids:
                continue
            block_ids.append(candidate)
            used_ids.add(candidate)
        applications.append(
            application.model_copy(
                update={"implementation_block_ids": block_ids}
            )
        )
    return plan.model_copy(update={"applications": applications})


def _assert_plan_target(plan: TechniquePlan, module_target: dict[str, Any]) -> None:
    if " ".join(plan.learning_outcome.split()) != " ".join(
        str(module_target.get("learning_outcome") or "").split()
    ):
        raise ValueError("technique plan changed the server-owned learning outcome")
    if plan.learner_level != module_target.get("level"):
        raise ValueError("technique plan changed the server-owned learner level")


async def generate_technique_plan(
    *,
    module_target: dict[str, Any],
    manifest: ResearchManifest,
    tier: str,
    durable_spacing_scheduler_enabled: bool = False,
    telemetry_metadata: dict[str, Any] | None = None,
) -> GeneratedArtifact:
    registry = [
        item
        for item in TECHNIQUE_REGISTRY
        if durable_spacing_scheduler_enabled
        or item.technique_id != TechniqueId.SPACED_PRACTICE
    ]
    registry_bindings, _ = _registry_evidence_bindings(
        manifest,
        technique_ids={item.technique_id for item in registry},
    )
    generated = await _generate(
        operation="curriculum_technique_plan",
        prompt_name="curriculum_technique_plan",
        prompt_variables={
            "module_target_json": module_target,
            "source_pack_json": writer_source_pack(manifest),
            "technique_registry_json": [
                {
                    **item.model_dump(mode="json"),
                    "required_evidence_source_ids": [
                        registry_bindings[item.technique_id]
                    ],
                }
                for item in registry
            ],
            "runtime_capabilities_json": {
                "durable_spacing_scheduler": durable_spacing_scheduler_enabled,
            },
        },
        output_model=TechniquePlan,
        tier=tier,
        max_tokens=6000,
        metadata={"stage": "technique_design", **(telemetry_metadata or {})},
    )
    plan = TechniquePlan.model_validate(generated.value)
    plan = _bind_exact_registry_evidence(plan, manifest)
    plan = _bind_technique_block_contracts(plan)
    _assert_plan_sources(plan, manifest)
    _assert_plan_target(plan, module_target)
    if (
        not durable_spacing_scheduler_enabled
        and any(
            item.technique_id == TechniqueId.SPACED_PRACTICE
            for item in plan.applications
        )
    ):
        raise ValueError("technique plan selected unavailable spaced practice")
    return GeneratedArtifact(
        value=plan,
        model_name=generated.model_name,
        provider=generated.provider,
        input_tokens=generated.input_tokens,
        output_tokens=generated.output_tokens,
        total_tokens=generated.total_tokens,
    )


def _assert_outline_contract(
    outline: CurriculumOutline,
    plan: TechniquePlan,
    manifest: ResearchManifest,
    module_target: dict[str, Any],
) -> None:
    target_gate = validate_module_target(outline, module_target)
    if not target_gate.passed:
        raise ValueError(
            "outline changed server-owned module target: "
            + ", ".join(issue.code for issue in target_gate.issues)
        )
    blocks = {block.block_id: block for block in outline.blocks}
    allowed_sources = {source.source_id for source in manifest.sources}
    claims = {claim.claim_id: claim for claim in manifest.claims}
    unknown_sources = sorted(
        {
            source_id
            for block in outline.blocks
            for source_id in block.source_ids
            if source_id not in allowed_sources
        }
    )
    if unknown_sources:
        raise ValueError(f"outline invented source ids: {unknown_sources}")
    factual_types = {
        "explanation",
        "visual_explanation",
        "worked_example",
    }
    for block in outline.blocks:
        if block.block_type.value in factual_types and not block.claim_ids:
            raise ValueError(f"outline block {block.block_id} lacks verified claim IDs")
        unknown_claims = set(block.claim_ids) - set(claims)
        if unknown_claims:
            raise ValueError(
                f"outline invented claim ids: {sorted(unknown_claims)}"
            )
        bound_claims = [claims[claim_id] for claim_id in block.claim_ids]
        supported_sources = {
            source_id for claim in bound_claims for source_id in claim.source_ids
        }
        if bound_claims and set(block.source_ids) - supported_sources:
            raise ValueError(
                f"outline block {block.block_id} binds unrelated source IDs"
            )
        if any(
            not set(claim.source_ids).intersection(block.source_ids)
            for claim in bound_claims
        ):
            raise ValueError(
                f"outline block {block.block_id} has unsupported claim bindings"
            )
    for application in plan.applications:
        for block_id in application.implementation_block_ids:
            block = blocks.get(block_id)
            if block is None:
                raise ValueError(f"outline omitted technique block: {block_id}")
            if application.technique_id not in block.technique_ids:
                raise ValueError(
                    f"outline block {block_id} omitted {application.technique_id.value}"
                )
        referenced_types = {
            blocks[block_id].block_type
            for block_id in application.implementation_block_ids
            if block_id in blocks
        }
        for allowed_types in TECHNIQUE_BLOCK_REQUIREMENTS[
            application.technique_id
        ]:
            if referenced_types.isdisjoint(allowed_types):
                raise ValueError(
                    "outline technique contract incomplete: "
                    f"{application.technique_id.value} requires one of "
                    f"{sorted(item.value for item in allowed_types)}"
                )


def _bind_outline_claim_sources(
    outline: CurriculumOutline,
    manifest: ResearchManifest,
) -> CurriculumOutline:
    """Make block citations the exact union of their verified claim sources."""

    claims = {claim.claim_id: claim for claim in manifest.claims}
    blocks = []
    for block in outline.blocks:
        if block.claim_ids and all(claim_id in claims for claim_id in block.claim_ids):
            source_ids = list(
                dict.fromkeys(
                    source_id
                    for claim_id in block.claim_ids
                    for source_id in claims[claim_id].source_ids
                )
            )
            block = block.model_copy(update={"source_ids": source_ids})
        blocks.append(block)
    return outline.model_copy(update={"blocks": blocks})


def _bind_outline_technique_blocks(
    outline: CurriculumOutline,
    plan: TechniquePlan,
) -> CurriculumOutline:
    """Align model-chosen block IDs with the server-pinned technique blueprint."""

    blocks = list(outline.blocks)
    reserved_ids = {
        block_id
        for application in plan.applications
        for block_id in application.implementation_block_ids
    }
    for application in plan.applications:
        expected_ids = list(application.implementation_block_ids)
        referenced_indexes: set[int] = set()

        for expected_id in expected_ids:
            index = next(
                (
                    candidate_index
                    for candidate_index, block in enumerate(blocks)
                    if block.block_id == expected_id
                ),
                None,
            )
            if index is None:
                continue
            referenced_indexes.add(index)
            block = blocks[index]
            if application.technique_id not in block.technique_ids:
                blocks[index] = block.model_copy(
                    update={
                        "technique_ids": [
                            *block.technique_ids,
                            application.technique_id,
                        ]
                    }
                )

        missing_ids = [
            expected_id
            for expected_id in expected_ids
            if all(block.block_id != expected_id for block in blocks)
        ]
        for expected_id in missing_ids:
            unsatisfied_groups = [
                allowed_types
                for allowed_types in TECHNIQUE_BLOCK_REQUIREMENTS[
                    application.technique_id
                ]
                if all(
                    blocks[index].block_type not in allowed_types
                    for index in referenced_indexes
                )
            ]
            candidates = [
                (index, block)
                for index, block in enumerate(blocks)
                if index not in referenced_indexes
                and block.block_id not in reserved_ids
                and application.technique_id in block.technique_ids
            ]
            if unsatisfied_groups:
                preferred = [
                    candidate
                    for candidate in candidates
                    if candidate[1].block_type in unsatisfied_groups[0]
                ]
                candidates = preferred or candidates
            if not candidates:
                continue
            index, block = candidates[0]
            blocks[index] = block.model_copy(update={"block_id": expected_id})
            referenced_indexes.add(index)

    return outline.model_copy(update={"blocks": blocks})


async def generate_outline(
    *,
    module_target: dict[str, Any],
    manifest: ResearchManifest,
    technique_plan: TechniquePlan,
    tier: str,
    telemetry_metadata: dict[str, Any] | None = None,
) -> GeneratedArtifact:
    generated = await _generate(
        operation="curriculum_module_outline",
        prompt_name="curriculum_outline",
        prompt_variables={
            "module_target_json": module_target,
            "source_pack_json": writer_source_pack(manifest),
            "technique_plan_json": technique_plan.model_dump(mode="json"),
        },
        output_model=CurriculumOutline,
        tier=tier,
        max_tokens=6000,
        metadata={"stage": "outline", **(telemetry_metadata or {})},
    )
    outline = _bind_outline_technique_blocks(
        _bind_outline_claim_sources(
            CurriculumOutline.model_validate(generated.value),
            manifest,
        ),
        technique_plan,
    )
    _assert_outline_contract(
        outline,
        technique_plan,
        manifest,
        module_target,
    )
    return GeneratedArtifact(
        value=outline,
        model_name=generated.model_name,
        provider=generated.provider,
        input_tokens=generated.input_tokens,
        output_tokens=generated.output_tokens,
        total_tokens=generated.total_tokens,
    )


async def generate_module_draft(
    *,
    module_target: dict[str, Any],
    manifest: ResearchManifest,
    technique_plan: TechniquePlan,
    outline: CurriculumOutline,
    tier: str,
    telemetry_metadata: dict[str, Any] | None = None,
) -> GeneratedArtifact:
    return await _generate(
        operation="curriculum_module_draft",
        prompt_name="curriculum_module_write",
        prompt_variables={
            "module_target_json": module_target,
            "source_pack_json": writer_source_pack(manifest),
            "technique_plan_json": technique_plan.model_dump(mode="json"),
            "outline_json": outline.model_dump(mode="json"),
        },
        output_model=CanonicalModuleDraft,
        tier=tier,
        max_tokens=24000,
        metadata={
            "stage": "writing",
            "repair": False,
            **(telemetry_metadata or {}),
        },
    )


async def repair_module_draft(
    *,
    module_target: dict[str, Any],
    manifest: ResearchManifest,
    technique_plan: TechniquePlan,
    outline: CurriculumOutline,
    draft: CanonicalModuleDraft,
    issues: list[dict[str, Any]],
    tier: str,
    repair_attempt: int,
    telemetry_metadata: dict[str, Any] | None = None,
) -> GeneratedArtifact:
    generated = await _generate(
        operation="curriculum_module_repair",
        prompt_name="curriculum_module_repair",
        prompt_variables={
            "module_target_json": module_target,
            "source_pack_json": writer_source_pack(manifest),
            "technique_plan_json": technique_plan.model_dump(mode="json"),
            "outline_json": outline.model_dump(mode="json"),
            "draft_json": draft.model_dump(mode="json"),
            "repair_issues_json": issues,
        },
        output_model=RepairResult,
        tier=tier,
        max_tokens=26000,
        metadata={
            "stage": "writing",
            "repair": True,
            "attempt": repair_attempt,
            **(telemetry_metadata or {}),
        },
    )
    repaired = RepairResult.model_validate(generated.value)
    requested_codes = {str(issue.get("code") or "") for issue in issues}
    if not requested_codes.issubset(set(repaired.addressed_issue_codes)):
        raise ValueError("repair did not acknowledge every targeted issue code")
    return GeneratedArtifact(
        value=repaired.repaired_draft,
        model_name=generated.model_name,
        provider=generated.provider,
        input_tokens=generated.input_tokens,
        output_tokens=generated.output_tokens,
        total_tokens=generated.total_tokens,
    )


def deterministic_draft_gate(
    *,
    draft: CanonicalModuleDraft,
    manifest: ResearchManifest,
    technique_plan: TechniquePlan,
    module_target: dict[str, Any] | None = None,
    durable_spacing_scheduler_enabled: bool = False,
) -> GateResult:
    results = (
        *(
            (validate_module_target(draft, module_target),)
            if module_target is not None
            else ()
        ),
        validate_structure(draft),
        validate_manifest_verification(manifest),
        validate_source_attribution(draft, manifest),
        validate_technique_implementation(
            draft,
            technique_plan,
            manifest,
            durable_spacing_scheduler_enabled=durable_spacing_scheduler_enabled,
        ),
        validate_source_originality(draft, manifest),
    )
    issues = tuple(issue for result in results for issue in result.issues)
    return GateResult(
        passed=all(result.passed for result in results),
        score=min(result.score for result in results),
        issues=issues,
        metrics={
            "deterministic_gate_count": len(results),
            "deterministic_issue_count": len(issues),
        },
    )


def merge_structure_review(
    review: QualityReview,
    deterministic: GateResult,
) -> QualityReview:
    issues = [*review.issues, *deterministic.issues]
    unique: dict[tuple[str, str | None], ReviewIssue] = {
        (issue.code, issue.block_id): issue for issue in issues
    }
    passed = review.passed and deterministic.passed and review.score >= MIN_REVIEW_SCORE
    return QualityReview(
        reviewer="structure",
        passed=passed,
        score=min(review.score, deterministic.score),
        issues=list(unique.values()),
        evidence=[
            *review.evidence,
            *[f"{key}={value}" for key, value in deterministic.metrics.items()],
        ],
    )


async def review_module(
    *,
    reviewer: ReviewerName,
    module_target: dict[str, Any],
    manifest: ResearchManifest,
    technique_plan: TechniquePlan,
    draft: CanonicalModuleDraft,
    comparison_texts: list[str],
    tier: str,
    repair_attempt: int,
    telemetry_metadata: dict[str, Any] | None = None,
) -> GeneratedArtifact:
    variables: dict[str, Any]
    if reviewer == "structure":
        variables = {
            "module_target_json": module_target,
            "technique_plan_json": technique_plan.model_dump(mode="json"),
            "draft_json": draft.model_dump(mode="json"),
        }
    elif reviewer == "factual":
        variables = {
            "source_pack_json": writer_source_pack(manifest),
            "draft_json": draft.model_dump(mode="json"),
        }
    elif reviewer == "pedagogy":
        variables = {
            "module_target_json": module_target,
            "technique_plan_json": technique_plan.model_dump(mode="json"),
            "draft_json": draft.model_dump(mode="json"),
        }
    else:
        variables = {
            "source_pack_json": writer_source_pack(manifest),
            "comparison_texts_json": [text[:12000] for text in comparison_texts[:20]],
            "draft_json": draft.model_dump(mode="json"),
        }
    generated = await _generate(
        operation=f"curriculum_review_{reviewer}",
        prompt_name=f"curriculum_review_{reviewer}",
        prompt_variables=variables,
        output_model=QualityReview,
        tier=tier,
        max_tokens=6000,
        metadata={
            "stage": f"{reviewer}_review",
            "repair_attempt": repair_attempt,
            **(telemetry_metadata or {}),
        },
    )
    review = QualityReview.model_validate(generated.value)
    if review.reviewer != reviewer:
        raise ValueError(
            f"reviewer contract mismatch: expected {reviewer}, got {review.reviewer}"
        )
    if review.score < MIN_REVIEW_SCORE and review.passed:
        review = review.model_copy(
            update={
                "passed": False,
                "issues": [
                    *review.issues,
                    ReviewIssue(
                        code=f"{reviewer}_score_below_threshold",
                        severity=ReviewSeverity.BLOCKING,
                        description=(
                            f"Review score {review.score:.2f} is below the publication floor."
                        ),
                        repair_instruction="Repair the identified weaknesses and rerun this independent review.",
                    ),
                ],
            }
        )
    return GeneratedArtifact(
        value=review,
        model_name=generated.model_name,
        provider=generated.provider,
        input_tokens=generated.input_tokens,
        output_tokens=generated.output_tokens,
        total_tokens=generated.total_tokens,
    )
