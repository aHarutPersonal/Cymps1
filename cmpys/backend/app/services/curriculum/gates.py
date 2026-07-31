"""Deterministic and independent-review publication gates."""

from __future__ import annotations

import unicodedata
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any, Iterable

from app.services.curriculum.schemas import (
    CanonicalModuleDraft,
    CurriculumOutline,
    LessonBlockType,
    QualityReview,
    ResearchManifest,
    ReviewBundle,
    ReviewIssue,
    ReviewSeverity,
    TechniqueId,
    TechniquePlan,
)
from app.services.curriculum.sessions import SessionPackingError, pack_session_blocks


QUALITY_GATE_VERSION = "curriculum-gates-v3"
MIN_REVIEW_SCORE = 0.82
MAX_SHINGLE_SIMILARITY = 0.72
MAX_SOURCE_SHINGLE_CONTAINMENT = 0.55
MAX_CANONICAL_SHINGLE_CONTAINMENT = 0.72


@dataclass(frozen=True, slots=True)
class GateResult:
    passed: bool
    score: float
    issues: tuple[ReviewIssue, ...] = field(default_factory=tuple)
    metrics: dict[str, float | int | str] = field(default_factory=dict)


def _issue(
    code: str,
    description: str,
    repair: str,
    *,
    severity: ReviewSeverity = ReviewSeverity.BLOCKING,
    block_id: str | None = None,
    source_ids: list[str] | None = None,
) -> ReviewIssue:
    return ReviewIssue(
        code=code,
        severity=severity,
        block_id=block_id,
        description=description,
        repair_instruction=repair,
        source_ids=source_ids or [],
    )


def validate_source_attribution(
    draft: CanonicalModuleDraft,
    manifest: ResearchManifest,
) -> GateResult:
    allowed = {source.source_id for source in manifest.sources}
    claims = {claim.claim_id: claim for claim in manifest.claims}
    issues: list[ReviewIssue] = []
    referenced: set[str] = set()
    source_required_types = {
        LessonBlockType.EXPLANATION,
        LessonBlockType.VISUAL_EXPLANATION,
        LessonBlockType.WORKED_EXAMPLE,
    }
    for block in draft.blocks:
        missing = sorted(set(block.source_ids) - allowed)
        if missing:
            issues.append(
                _issue(
                    "unknown_source_id",
                    f"Block references unknown source ids: {missing}",
                    "Use only source IDs from the stored research manifest.",
                    block_id=block.block_id,
                )
            )
        if block.block_type in source_required_types and not block.source_ids:
            issues.append(
                _issue(
                    "missing_source_attribution",
                    "Explanatory or worked-example block has no source attribution.",
                    "Bind factual teaching claims to one or more manifest source IDs.",
                    block_id=block.block_id,
                )
            )
        if block.block_type in source_required_types and not block.claim_ids:
            issues.append(
                _issue(
                    "missing_claim_attribution",
                    "Factual teaching block has no verified claim attribution.",
                    "Bind the block to one or more verified manifest claim IDs.",
                    block_id=block.block_id,
                )
            )
        unknown_claims = sorted(set(block.claim_ids) - set(claims))
        if unknown_claims:
            issues.append(
                _issue(
                    "unknown_claim_id",
                    f"Block references unknown claim ids: {unknown_claims}",
                    "Use only verified claim IDs from the stored research manifest.",
                    block_id=block.block_id,
                )
            )
        bound_claims = [
            claims[claim_id] for claim_id in block.claim_ids if claim_id in claims
        ]
        supported_source_ids = {
            source_id for claim in bound_claims for source_id in claim.source_ids
        }
        unsupported_block_sources = (
            sorted(set(block.source_ids) - supported_source_ids) if bound_claims else []
        )
        missing_claim_support = sorted(
            claim.claim_id
            for claim in bound_claims
            if not set(claim.source_ids).intersection(block.source_ids)
        )
        if unsupported_block_sources or missing_claim_support:
            issues.append(
                _issue(
                    "claim_source_mismatch",
                    (
                        "Block source bindings do not match its verified claims: "
                        f"unsupported sources={unsupported_block_sources}, "
                        f"unsupported claims={missing_claim_support}."
                    ),
                    "Use source IDs that support each referenced claim and remove unrelated citations.",
                    block_id=block.block_id,
                    source_ids=unsupported_block_sources,
                )
            )
        referenced.update(block.source_ids)
    coverage = len(referenced) / max(len(allowed), 1)
    score = max(0.0, 1.0 - 0.15 * len(issues))
    return GateResult(
        passed=not issues,
        score=score,
        issues=tuple(issues),
        metrics={"referenced_sources": len(referenced), "source_coverage": coverage},
    )


def validate_manifest_verification(manifest: ResearchManifest) -> GateResult:
    issues = [
        _issue(
            "unverified_manifest_claim",
            f"Manifest claim {claim.claim_id} lacks independent verification.",
            "Run independent entailment verification before lesson generation.",
            source_ids=claim.source_ids,
        )
        for claim in manifest.claims
        if claim.verification_score is None
        or claim.verification_score < 0.80
        or not claim.verification_note
    ]
    return GateResult(
        passed=not issues,
        score=max(0.0, 1.0 - 0.2 * len(issues)),
        issues=tuple(issues),
        metrics={"verified_claims": len(manifest.claims) - len(issues)},
    )


TECHNIQUE_BLOCK_REQUIREMENTS: dict[
    TechniqueId, tuple[frozenset[LessonBlockType], ...]
] = {
    TechniqueId.RETRIEVAL_PRACTICE: (frozenset({LessonBlockType.RETRIEVAL}),),
    TechniqueId.SPACED_PRACTICE: (
        frozenset({LessonBlockType.RETRIEVAL, LessonBlockType.TRANSFER}),
    ),
    TechniqueId.WORKED_EXAMPLES: (frozenset({LessonBlockType.WORKED_EXAMPLE}),),
    TechniqueId.GUIDANCE_FADING: (
        frozenset({LessonBlockType.GUIDED_PRACTICE}),
        frozenset({LessonBlockType.INDEPENDENT_PRACTICE}),
    ),
    TechniqueId.SELF_EXPLANATION: (frozenset({LessonBlockType.REFLECTION}),),
    TechniqueId.INTERLEAVING: (
        frozenset({LessonBlockType.INDEPENDENT_PRACTICE, LessonBlockType.TRANSFER}),
    ),
    TechniqueId.ACTIVE_APPLICATION: (
        frozenset({LessonBlockType.INDEPENDENT_PRACTICE, LessonBlockType.TRANSFER}),
    ),
    TechniqueId.FEEDBACK_REVISION: (
        frozenset({LessonBlockType.FEEDBACK}),
        frozenset({LessonBlockType.REVISION}),
    ),
    TechniqueId.MASTERY_CHECKS: (frozenset({LessonBlockType.ASSESSMENT}),),
    TechniqueId.CONCRETE_ABSTRACT_LINKING: (
        frozenset({LessonBlockType.EXPLANATION}),
        frozenset({LessonBlockType.WORKED_EXAMPLE}),
    ),
    TechniqueId.VISUAL_VERBAL: (frozenset({LessonBlockType.VISUAL_EXPLANATION}),),
}


def validate_technique_implementation(
    draft: CanonicalModuleDraft,
    plan: TechniquePlan,
    manifest: ResearchManifest,
    *,
    durable_spacing_scheduler_enabled: bool = False,
) -> GateResult:
    blocks = {block.block_id: block for block in draft.blocks}
    source_ids = {source.source_id for source in manifest.sources}
    source_ids_by_url = {source.url: source.source_id for source in manifest.sources}
    from app.services.curriculum.pilot import TECHNIQUE_REGISTRY

    registry_urls = {
        entry.technique_id: set(entry.source_urls) for entry in TECHNIQUE_REGISTRY
    }
    issues: list[ReviewIssue] = []
    for application in plan.applications:
        if (
            application.technique_id == TechniqueId.SPACED_PRACTICE
            and not durable_spacing_scheduler_enabled
        ):
            issues.append(
                _issue(
                    "spacing_scheduler_unavailable",
                    "Spaced practice was selected without a durable follow-up scheduler.",
                    "Use an immediately executable technique until durable spacing is enabled.",
                )
            )
        unknown_sources = sorted(set(application.evidence_source_ids) - source_ids)
        if unknown_sources:
            issues.append(
                _issue(
                    "technique_evidence_missing",
                    f"Technique cites unknown sources: {unknown_sources}",
                    "Bind the technique rationale to existing manifest sources.",
                    source_ids=unknown_sources,
                )
            )
        approved_evidence_ids = {
            source_ids_by_url[url]
            for url in registry_urls[application.technique_id]
            if url in source_ids_by_url
        }
        if not approved_evidence_ids.intersection(application.evidence_source_ids):
            issues.append(
                _issue(
                    "technique_registry_evidence_missing",
                    (
                        f"{application.technique_id.value} is not bound to its "
                        "versioned registry evidence source."
                    ),
                    "Cite a source ID whose exact URL appears in this technique's registry entry.",
                )
            )
        referenced_blocks = [
            blocks[block_id]
            for block_id in application.implementation_block_ids
            if block_id in blocks
        ]
        missing_blocks = sorted(set(application.implementation_block_ids) - set(blocks))
        if missing_blocks:
            issues.append(
                _issue(
                    "technique_block_missing",
                    f"Technique plan references missing blocks: {missing_blocks}",
                    "Create the planned blocks or update the technique plan.",
                )
            )
        if any(
            application.technique_id not in block.technique_ids
            for block in referenced_blocks
        ):
            issues.append(
                _issue(
                    "technique_binding_missing",
                    f"Blocks do not declare {application.technique_id.value}.",
                    "Add the technique ID to every planned implementation block.",
                )
            )
        block_types = {block.block_type for block in referenced_blocks}
        for allowed_types in TECHNIQUE_BLOCK_REQUIREMENTS[application.technique_id]:
            if block_types.isdisjoint(allowed_types):
                issues.append(
                    _issue(
                        "technique_contract_incomplete",
                        (
                            f"{application.technique_id.value} is named but lacks "
                            f"a required block type: {sorted(t.value for t in allowed_types)}"
                        ),
                        "Implement the required learning activity in a dedicated block.",
                    )
                )
        if application.technique_id == TechniqueId.SPACED_PRACTICE:
            scheduled_days = {
                block.follow_up_day
                for block in referenced_blocks
                if block.follow_up_day is not None
            }
            missing_days = sorted(set(plan.spacing_follow_up_days) - scheduled_days)
            if missing_days:
                issues.append(
                    _issue(
                        "spacing_follow_up_unscheduled",
                        f"Spaced-practice offsets lack executable blocks: {missing_days}",
                        "Add retrieval/transfer blocks with matching follow_up_day metadata.",
                    )
                )
    score = max(0.0, 1.0 - 0.12 * len(issues))
    return GateResult(
        passed=not issues,
        score=score,
        issues=tuple(issues),
        metrics={"planned_techniques": len(plan.applications)},
    )


def _normalized_text(value: object) -> str:
    return " ".join(str(value or "").split())


def _normalized_prerequisites(value: object) -> tuple[str, ...]:
    if not isinstance(value, (list, tuple)):
        return ()
    return tuple(
        sorted(
            {
                _normalized_text(item).casefold()
                for item in value
                if _normalized_text(item)
            }
        )
    )


def validate_module_target(
    artifact: CurriculumOutline | CanonicalModuleDraft,
    module_target: dict[str, object],
) -> GateResult:
    """Keep server-owned curriculum identity immutable across model stages."""
    issues: list[ReviewIssue] = []
    exact_fields = ("skill_key", "domain", "level", "locale", "artifact_type")
    for field_name in exact_fields:
        actual = _normalized_text(getattr(artifact, field_name, ""))
        expected = _normalized_text(module_target.get(field_name))
        if actual != expected:
            issues.append(
                _issue(
                    f"target_{field_name}_changed",
                    f"Generated {field_name} does not match the server-owned module target.",
                    f"Restore the exact server-owned {field_name} value.",
                )
            )
    if _normalized_text(artifact.learning_outcome) != _normalized_text(
        module_target.get("learning_outcome")
    ):
        issues.append(
            _issue(
                "target_learning_outcome_changed",
                "Generated learning outcome does not match the server-owned target.",
                "Restore the exact target learning outcome.",
            )
        )
    if _normalized_prerequisites(artifact.prerequisites) != _normalized_prerequisites(
        module_target.get("prerequisites")
    ):
        issues.append(
            _issue(
                "target_prerequisites_changed",
                "Generated prerequisites differ from the server-owned target.",
                "Restore exactly the normalized target prerequisite set.",
            )
        )
    target_minutes = int(module_target.get("estimated_minutes") or 0)
    tolerance = max(10, round(target_minutes * 0.10))
    if (
        target_minutes <= 0
        or abs(artifact.estimated_minutes - target_minutes) > tolerance
    ):
        issues.append(
            _issue(
                "target_minutes_changed",
                "Generated duration is outside the server-owned target tolerance.",
                f"Keep total duration within {tolerance} minutes of {target_minutes}.",
            )
        )
    return GateResult(
        passed=not issues,
        score=max(0.0, 1.0 - 0.15 * len(issues)),
        issues=tuple(issues),
        metrics={"target_minutes": target_minutes, "minutes_tolerance": tolerance},
    )


def validate_structure(draft: CanonicalModuleDraft) -> GateResult:
    issues: list[ReviewIssue] = []
    types = {block.block_type for block in draft.blocks}
    required = {
        LessonBlockType.EXPLANATION,
        LessonBlockType.WORKED_EXAMPLE,
        LessonBlockType.INDEPENDENT_PRACTICE,
        LessonBlockType.ASSESSMENT,
    }
    missing = sorted(block_type.value for block_type in required - types)
    if missing:
        issues.append(
            _issue(
                "required_blocks_missing",
                f"Module lacks required block types: {missing}",
                "Add complete explanation, worked example, practice, and assessment blocks.",
            )
        )
    if sum(block.minutes for block in draft.blocks) < 40:
        issues.append(
            _issue(
                "module_too_short",
                "Module does not support an honest 40-minute learning session.",
                "Add substantive guided or independent practice, not filler prose.",
            )
        )
    assessment_blocks = [
        block
        for block in draft.blocks
        if block.block_type == LessonBlockType.ASSESSMENT
    ]
    if any(not block.success_criteria for block in assessment_blocks):
        issues.append(
            _issue(
                "assessment_without_success_criteria",
                "An assessment block lacks observable success criteria.",
                "Add criteria that directly test the stated learning outcome.",
            )
        )
    try:
        sessions = pack_session_blocks(draft)
    except SessionPackingError as exc:
        sessions = ()
        issues.append(
            _issue(
                "session_time_contract_unmet",
                str(exc),
                "Adjust whole-block minutes/order so each contiguous session totals 40–60 minutes.",
            )
        )
    score = max(0.0, 1.0 - 0.2 * len(issues))
    return GateResult(
        passed=not issues,
        score=score,
        issues=tuple(issues),
        metrics={
            "blocks": len(draft.blocks),
            "minutes": sum(block.minutes for block in draft.blocks),
            "rubric_criteria": len(draft.rubric),
            "session_count": len(sessions),
        },
    )


_CHARACTER_TOKEN_RANGES = (
    (0x0E00, 0x0FFF),  # Thai and Lao
    (0x1000, 0x109F),  # Myanmar
    (0x1780, 0x17FF),  # Khmer
    (0x2E80, 0x2FFF),  # CJK radicals
    (0x3040, 0x30FF),  # Hiragana and Katakana
    (0x3400, 0x4DBF),  # CJK extension A
    (0x4E00, 0x9FFF),  # CJK unified ideographs
    (0xAC00, 0xD7AF),  # Hangul syllables
    (0xF900, 0xFAFF),  # CJK compatibility ideographs
    (0x20000, 0x323AF),  # CJK extensions B through H
)


def _uses_character_tokens(character: str) -> bool:
    codepoint = ord(character)
    return any(start <= codepoint <= end for start, end in _CHARACTER_TOKEN_RANGES)


def _tokens(text: str) -> list[str]:
    """Tokenize spaced scripts by word and unspaced scripts by character."""

    tokens: list[str] = []
    word: list[str] = []

    def flush_word() -> None:
        if word:
            tokens.append("".join(word))
            word.clear()

    for character in unicodedata.normalize("NFKC", text.casefold()):
        category = unicodedata.category(character)
        if _uses_character_tokens(character):
            flush_word()
            if category[0] in {"L", "M", "N"}:
                tokens.append(character)
        elif character.isalnum() or (category.startswith("M") and word):
            word.append(character)
        else:
            flush_word()
    flush_word()
    return tokens


def _token_shingles(
    tokens: list[str],
    size: int,
) -> set[tuple[str, ...]]:
    if not tokens or size <= 0 or len(tokens) < size:
        return set()
    return {
        tuple(tokens[index : index + size]) for index in range(len(tokens) - size + 1)
    }


def _shingles(text: str, size: int = 7) -> set[tuple[str, ...]]:
    """Return adaptive shingles without treating non-Latin prose as empty."""

    tokens = _tokens(text)
    return _token_shingles(tokens, min(size, len(tokens)))


def shingle_similarity(left: str, right: str) -> float:
    left_tokens = _tokens(left)
    right_tokens = _tokens(right)
    size = min(7, len(left_tokens), len(right_tokens))
    a = _token_shingles(left_tokens, size)
    b = _token_shingles(right_tokens, size)
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def _ordered_token_containment(
    source_tokens: list[str],
    candidate_tokens: list[str],
) -> float:
    """Return exact LCS source coverage with a bit-parallel O(mn/word) update."""

    if not source_tokens or not candidate_tokens:
        return 0.0
    source_masks: dict[str, int] = {}
    for position, token in enumerate(source_tokens):
        source_masks[token] = source_masks.get(token, 0) | (1 << position)

    state = 0
    for token in candidate_tokens:
        matches = source_masks.get(token, 0)
        combined = state | matches
        shifted = (state << 1) | 1
        state = combined & ~(combined - shifted)
    return state.bit_count() / len(source_tokens)


def _directional_containment(
    source_tokens: list[str],
    candidate_tokens: list[str],
) -> float:
    if not source_tokens or not candidate_tokens:
        return 0.0
    size = min(7, len(source_tokens))
    source_shingles = _token_shingles(source_tokens, size)
    candidate_shingles = _token_shingles(candidate_tokens, size)
    phrase_containment = (
        len(source_shingles & candidate_shingles) / len(source_shingles)
        if source_shingles
        else 0.0
    )
    return max(
        phrase_containment,
        _ordered_token_containment(source_tokens, candidate_tokens),
    )


def shingle_containment(source: str, candidate: str) -> float:
    """Measure ordered phrase coverage in both copy directions.

    Taking both directions catches a padded full copy as well as a shorter candidate
    copied from one subsection of a larger reference. Exact bit-parallel LCS coverage
    tolerates inserted tokens without reducing the check to a bag-of-words metric.
    """

    source_tokens = _tokens(source)
    candidate_tokens = _tokens(candidate)
    if not source_tokens or not candidate_tokens:
        return 0.0
    return max(
        _directional_containment(source_tokens, candidate_tokens),
        _directional_containment(candidate_tokens, source_tokens),
    )


def _draft_prose_segments_with_locations(
    draft: CanonicalModuleDraft | Mapping[str, Any],
) -> tuple[tuple[str | None, str, str], ...]:
    content: Mapping[str, Any]
    if isinstance(draft, CanonicalModuleDraft):
        content = draft.model_dump(mode="python")
    elif isinstance(draft, Mapping):
        content = draft
    else:
        return ()

    prose: list[tuple[str | None, str, str]] = []

    def append_text(
        value: Any,
        *,
        field_name: str,
        block_id: str | None = None,
    ) -> None:
        if isinstance(value, str) and value.strip():
            prose.append((block_id, field_name, value.strip()))

    for field_name in (
        "title",
        "summary",
        "learning_outcome",
        "artifact_type",
        "artifact_description",
    ):
        append_text(content.get(field_name), field_name=field_name)
    prerequisites = content.get("prerequisites")
    if isinstance(prerequisites, list):
        for index, prerequisite in enumerate(prerequisites):
            append_text(
                prerequisite,
                field_name=f"prerequisites[{index}]",
            )

    blocks = content.get("blocks")
    if isinstance(blocks, list):
        for block in blocks:
            if not isinstance(block, Mapping):
                continue
            raw_block_id = block.get("block_id")
            block_id = str(raw_block_id) if raw_block_id else None
            append_text(
                block.get("title"),
                field_name="title",
                block_id=block_id,
            )
            append_text(
                block.get("content_markdown"),
                field_name="content_markdown",
                block_id=block_id,
            )
            for field_name in ("learner_instructions", "success_criteria"):
                values = block.get(field_name)
                if isinstance(values, list):
                    for index, value in enumerate(values):
                        append_text(
                            value,
                            field_name=f"{field_name}[{index}]",
                            block_id=block_id,
                        )

    rubric = content.get("rubric")
    if isinstance(rubric, list):
        for index, criterion in enumerate(rubric):
            if not isinstance(criterion, Mapping):
                continue
            for field_name in (
                "criterion",
                "evidence_required",
                "passing_standard",
            ):
                append_text(
                    criterion.get(field_name),
                    field_name=f"rubric[{index}].{field_name}",
                )

    return tuple(prose)


def _draft_prose_segments(
    draft: CanonicalModuleDraft | Mapping[str, Any],
) -> tuple[str, ...]:
    return tuple(
        text for _, _, text in _draft_prose_segments_with_locations(draft)
    )


def draft_text(draft: CanonicalModuleDraft | Mapping[str, Any]) -> str:
    """Return all learner-visible canonical prose in a stable field order.

    Publication compares persisted JSON as well as in-memory drafts. Keeping one
    extractor for both prevents titles, instructions, artifact specifications, or
    rubric prose from becoming an originality blind spot.
    """

    return "\n".join(_draft_prose_segments(draft))


def _originality_candidate_segments(
    draft: CanonicalModuleDraft,
) -> tuple[tuple[str | None, str, str], ...]:
    segments = _draft_prose_segments_with_locations(draft)
    complete_text = "\n".join(text for _, _, text in segments)
    # Whole-field comparisons catch a copied subsection even when the complete
    # module contains enough unrelated prose to dilute its aggregate overlap.
    substantive_segments = tuple(
        segment for segment in segments if len(_tokens(segment[2])) >= 12
    )
    return ((None, "complete_draft", complete_text), *substantive_segments)


def _originality_candidate_texts(draft: CanonicalModuleDraft) -> tuple[str, ...]:
    return tuple(text for _, _, text in _originality_candidate_segments(draft))


def validate_originality(
    draft: CanonicalModuleDraft,
    comparison_texts: Iterable[str],
) -> GateResult:
    candidate_texts = _originality_candidate_texts(draft)
    similarities = [
        max(
            shingle_containment(str(text), candidate_text)
            for candidate_text in candidate_texts
        )
        for text in comparison_texts
        if str(text).strip()
    ]
    maximum = max(similarities, default=0.0)
    issues: list[ReviewIssue] = []
    if maximum > MAX_SHINGLE_SIMILARITY:
        issues.append(
            _issue(
                "excessive_catalog_overlap",
                f"Module has {maximum:.1%} phrase overlap with an existing module.",
                "Rewrite the overlapping passages and preserve only necessary terminology.",
                severity=ReviewSeverity.CRITICAL,
            )
        )
    return GateResult(
        passed=not issues,
        score=max(0.0, 1.0 - maximum),
        issues=tuple(issues),
        metrics={"maximum_shingle_similarity": maximum},
    )


def validate_source_originality(
    draft: CanonicalModuleDraft,
    manifest: ResearchManifest,
) -> GateResult:
    candidates = _originality_candidate_segments(draft)
    maximum = 0.0
    source_id = ""
    closest_block_id: str | None = None
    closest_field = "complete_draft"
    for source in manifest.sources:
        source_tokens = _tokens(source.sanitized_support_text)
        size = min(7, len(source_tokens))
        # Very short quotations are legitimate attribution, not evidence that
        # a lesson replaced the source. Count positional windows rather than the
        # distinct shingle set so repetitive long sources cannot appear "short".
        positional_shingle_count = len(source_tokens) - size + 1 if size > 0 else 0
        if positional_shingle_count < 4:
            continue
        containment, block_id, field_name = max(
            (
                (
                    shingle_containment(
                        source.sanitized_support_text,
                        candidate_text,
                    ),
                    candidate_block_id,
                    candidate_field,
                )
                for candidate_block_id, candidate_field, candidate_text in candidates
            ),
            key=lambda item: (item[0], item[2] != "complete_draft"),
        )
        if containment > maximum:
            maximum = containment
            source_id = source.source_id
            closest_block_id = block_id
            closest_field = field_name
    issues: list[ReviewIssue] = []
    if maximum > MAX_SOURCE_SHINGLE_CONTAINMENT:
        location = (
            f"{closest_field} in block {closest_block_id}"
            if closest_block_id
            else closest_field
        )
        issues.append(
            _issue(
                "source_copying_detected",
                (
                    f"Draft segment {location} contains {maximum:.1%} of a "
                    "source excerpt's phrase shingles."
                ),
                (
                    f"Rewrite {location} as an original synthesis and keep only "
                    "short attributed quotations."
                ),
                severity=ReviewSeverity.CRITICAL,
                block_id=closest_block_id,
                source_ids=[source_id] if source_id else [],
            )
        )
    return GateResult(
        passed=not issues,
        score=max(0.0, 1.0 - maximum),
        issues=tuple(issues),
        metrics={
            "maximum_source_shingle_containment": maximum,
            "closest_source_id": source_id,
        },
    )


def validate_independent_reviews(bundle: ReviewBundle) -> GateResult:
    issues: list[ReviewIssue] = []
    for review in bundle.reviews:
        if not review.passed or review.score < MIN_REVIEW_SCORE:
            issues.extend(review.issues)
            if not review.issues:
                issues.append(
                    _issue(
                        f"{review.reviewer}_review_below_threshold",
                        f"{review.reviewer} review scored {review.score:.2f}.",
                        "Repair the module against this review and run all reviews again.",
                    )
                )
    minimum = min(review.score for review in bundle.reviews)
    return GateResult(
        passed=not issues,
        score=minimum,
        issues=tuple(issues),
        metrics={f"{review.reviewer}_score": review.score for review in bundle.reviews},
    )


def publication_gate(
    *,
    draft: CanonicalModuleDraft,
    manifest: ResearchManifest,
    technique_plan: TechniquePlan,
    reviews: ReviewBundle,
    comparison_texts: Iterable[str] = (),
    module_target: dict[str, object] | None = None,
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
        validate_originality(draft, comparison_texts),
        validate_source_originality(draft, manifest),
        validate_independent_reviews(reviews),
    )
    issues = tuple(issue for result in results for issue in result.issues)
    return GateResult(
        passed=all(result.passed for result in results),
        score=min(result.score for result in results),
        issues=issues,
        metrics={
            "gate_version": QUALITY_GATE_VERSION,
            "gate_count": len(results),
            "issue_count": len(issues),
        },
    )


def review_from_gate(reviewer: str, result: GateResult) -> QualityReview:
    return QualityReview(
        reviewer=reviewer,
        passed=result.passed,
        score=result.score,
        issues=list(result.issues),
        evidence=[f"{key}={value}" for key, value in result.metrics.items()],
    )
