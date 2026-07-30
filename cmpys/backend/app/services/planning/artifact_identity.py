"""Exact identity helpers for mutable plan-item lesson artifacts."""

from collections.abc import Mapping, Sequence
from datetime import datetime
from typing import Any, cast as type_cast
from uuid import UUID

from sqlalchemy import (
    String,
    and_,
    cast,
    exists,
    false,
    func,
    not_,
    or_,
    select,
    text,
    true,
)
from sqlalchemy.orm import aliased

from app.models.item_detail_job import PlanItemDetailJob
from app.models.plan import PlanItem, PlanItemCompletion, PlanItemStepCompletion
from app.services.content_quality import MIN_PLAN_DETAIL_LESSON_WORDS


ACTIVE_DETAIL_JOB_STATUSES = frozenset({"pending", "queued", "running"})
PLAN_ITEM_STEP_ID_MAX_LENGTH = 100


def _optional_strings_are_valid(
    payload: Mapping[str, Any],
    field_names: tuple[str, ...],
) -> bool:
    return all(
        payload.get(field_name) is None
        or isinstance(payload.get(field_name), str)
        for field_name in field_names
    )


def _optional_string_lists_are_valid(
    payload: Mapping[str, Any],
    field_names: tuple[str, ...],
) -> bool:
    for field_name in field_names:
        value = payload.get(field_name)
        if value is not None and (
            not isinstance(value, list)
            or not all(isinstance(entry, str) for entry in value)
        ):
            return False
    return True


def _optional_int_is_valid(value: Any) -> bool:
    return value is None or (isinstance(value, int) and not isinstance(value, bool))


def artifact_job_id_from_details(details_json: Any) -> str | None:
    """Return the embedded job marker; ``None`` means the key is truly absent.

    A present-but-null/empty marker is deliberately returned as an invalid
    string. Collapsing it to ``None`` would let malformed modern artifacts
    inherit legacy ``artifact_job_id IS NULL`` completion history.
    """

    if not isinstance(details_json, Mapping):
        return None
    if "_generation" not in details_json:
        return None
    generation = details_json.get("_generation")
    if not isinstance(generation, Mapping):
        return ""
    if "job_id" not in generation:
        return None
    raw_job_id = generation.get("job_id")
    return "" if raw_job_id is None else str(raw_job_id)


def artifact_job_marker_is_invalid(details_json: Any) -> bool:
    """Whether modern metadata contains a non-canonical UUID job reference."""

    if not isinstance(details_json, Mapping):
        return False
    if "_generation" not in details_json:
        return False
    generation = details_json.get("_generation")
    if not isinstance(generation, Mapping):
        return True
    if "job_id" not in generation:
        return False
    raw_job_id = generation.get("job_id")
    if not isinstance(raw_job_id, str) or not raw_job_id:
        return True
    try:
        parsed_job_id = UUID(raw_job_id)
    except (TypeError, ValueError, AttributeError):
        return True
    return str(parsed_job_id) != raw_job_id


def current_artifact_job_id(item: PlanItem) -> str | None:
    return artifact_job_id_from_details(item.details_json)


async def artifact_job_reference_is_valid(
    db: Any,
    details_json: Any,
    *,
    plan_item_id: str,
    user_id: str,
) -> bool:
    """Validate that a modern marker names a job owned by this item/user.

    Legacy artifacts without a ``job_id`` marker remain valid. Modern markers
    fail closed when malformed, missing, or copied from another item/user. The
    UUID column is cast to text so malformed JSON is never cast to UUID by the
    database.
    """

    if artifact_job_marker_is_invalid(details_json):
        return False
    artifact_job_id = artifact_job_id_from_details(details_json)
    if artifact_job_id is None:
        return True
    if not artifact_job_id:
        return False
    matched_job_id = await db.scalar(
        select(cast(PlanItemDetailJob.id, String))
        .where(
            cast(PlanItemDetailJob.id, String) == artifact_job_id,
            PlanItemDetailJob.plan_item_id == plan_item_id,
            PlanItemDetailJob.user_id == user_id,
        )
        .limit(1)
    )
    return matched_job_id is not None


def artifact_job_reference_predicate(
    details_json: Any,
    *,
    plan_item_id: str,
    user_id: str,
) -> Any:
    """SQL equivalent of :func:`artifact_job_reference_is_valid`."""

    if artifact_job_marker_is_invalid(details_json):
        return false()
    artifact_job_id = artifact_job_id_from_details(details_json)
    if artifact_job_id is None:
        return true()
    if not artifact_job_id:
        return false()
    return exists(
        select(1).where(
            cast(PlanItemDetailJob.id, String) == artifact_job_id,
            PlanItemDetailJob.plan_item_id == plan_item_id,
            PlanItemDetailJob.user_id == user_id,
        )
    )


def item_completion_artifact_is_eligible(details_json: Any) -> bool:
    """Whether item-level completion may represent the current artifact."""

    if artifact_job_marker_is_invalid(details_json):
        return False
    artifact_job_id = artifact_job_id_from_details(details_json)
    if artifact_job_id is None:
        return True
    generation = (
        details_json.get("_generation")
        if isinstance(details_json, Mapping)
        else None
    )
    return isinstance(generation, Mapping) and generation.get("status") in {
        "ready",
        "revoked",
    }


def validated_lesson_steps(
    details_json: Any,
) -> tuple[Mapping[str, Any], ...] | None:
    """Return a present lesson step array only when every ID is unambiguous.

    ``None`` covers both an absent array (legacy/no lesson) and a present but
    malformed array. Callers that mutate state can distinguish those cases by
    checking whether the ``steps`` key is present and return a stable conflict.
    """

    if not isinstance(details_json, Mapping) or "steps" not in details_json:
        return None
    raw_steps = details_json.get("steps")
    if not isinstance(raw_steps, list):
        return None

    seen_ids: set[str] = set()
    validated: list[Mapping[str, Any]] = []
    for step in raw_steps:
        if not isinstance(step, Mapping):
            return None
        raw_step_id = step.get("id")
        if not isinstance(raw_step_id, str):
            return None
        step_id = raw_step_id.strip()
        if (
            not step_id
            or step_id != raw_step_id
            or len(step_id) > PLAN_ITEM_STEP_ID_MAX_LENGTH
            or step_id in seen_ids
        ):
            return None
        if "title" in step and not isinstance(step.get("title"), str):
            return None
        if not _optional_strings_are_valid(
            step,
            ("description", "expected_output", "lesson_content"),
        ) or not _optional_string_lists_are_valid(
            step,
            ("resources", "substeps"),
        ):
            return None
        if not _optional_int_is_valid(step.get("order")):
            return None
        for snake_name, camel_name in (
            ("estimate_minutes", "estimateMinutes"),
            ("reading_minutes", "readingMinutes"),
            ("practice_minutes", "practiceMinutes"),
        ):
            for field_name in (snake_name, camel_name):
                if field_name in step and not _optional_int_is_valid(
                    step.get(field_name)
                ):
                    return None
        seen_ids.add(step_id)
        validated.append(step)
    return tuple(validated)


def validated_lesson_materials(
    details_json: Any,
) -> tuple[Mapping[str, Any], ...] | None:
    """Return parser-safe optional materials; ``None`` means malformed."""

    if not isinstance(details_json, Mapping):
        return None
    raw_materials = details_json.get("materials")
    if raw_materials is None:
        return ()
    if not isinstance(raw_materials, list):
        return None

    validated: list[Mapping[str, Any]] = []
    for material in raw_materials:
        if not isinstance(material, Mapping):
            return None
        if "title" in material and not isinstance(material.get("title"), str):
            return None
        if not _optional_strings_are_valid(
            material,
            (
                "url",
                "type",
                "content_resource_id",
                "contentResourceId",
                "canonical_key",
                "canonicalKey",
                "author_or_creator",
                "authorOrCreator",
                "thumbnail_url",
                "thumbnailUrl",
                "license_status",
                "licenseStatus",
                "search_query",
                "searchQuery",
                "url_resolution_status",
                "urlResolutionStatus",
                "url_provider",
                "urlProvider",
                "content_markdown",
                "reason",
            ),
        ) or not _optional_int_is_valid(material.get("duration_minutes")):
            return None
        ideas = material.get("ideas")
        if ideas is not None and (
            not isinstance(ideas, list)
            or not all(isinstance(idea, Mapping) for idea in ideas)
        ):
            return None
        if ideas is not None and any(
            ("title" in idea and not isinstance(idea.get("title"), str))
            or ("content" in idea and not isinstance(idea.get("content"), str))
            or ("category" in idea and not isinstance(idea.get("category"), str))
            for idea in ideas
        ):
            return None
        validated.append(material)
    return tuple(validated)


def validated_ready_step_ids(generation: Any) -> frozenset[str] | None:
    """Return unambiguous progressive-checkpoint IDs or fail closed."""

    if not isinstance(generation, Mapping):
        return None
    raw_ids = generation.get("ready_step_ids")
    if not isinstance(raw_ids, list):
        return None
    ready_ids: set[str] = set()
    for raw_id in raw_ids:
        if not isinstance(raw_id, str):
            return None
        step_id = raw_id.strip()
        if (
            not step_id
            or step_id != raw_id
            or len(step_id) > PLAN_ITEM_STEP_ID_MAX_LENGTH
            or step_id in ready_ids
        ):
            return None
        ready_ids.add(step_id)
    return frozenset(ready_ids)


def artifact_identity_predicate(column: Any, artifact_job_id: str | None) -> Any:
    """Match one exact artifact, including ``NULL`` for pre-job legacy lessons."""

    if artifact_job_id is None:
        return column.is_(None)
    try:
        parsed_job_id = UUID(str(artifact_job_id))
    except (TypeError, ValueError, AttributeError):
        return false()
    if str(parsed_job_id) != str(artifact_job_id):
        return false()
    return column == artifact_job_id


async def allocate_detail_artifact_epoch(
    db: Any,
    *,
    plan_item_id: str,
    user_id: str,
) -> datetime:
    """Allocate a DB-clock epoch strictly after every prior item/user job.

    Callers serialize an existing PlanItem before allocation. A newly inserted
    PlanItem is intrinsically first-writer-only inside its creating transaction.
    """

    next_prior_epoch = (
        select(
            func.max(PlanItemDetailJob.artifact_epoch_at)
            + text("INTERVAL '1 microsecond'")
        )
        .where(
            PlanItemDetailJob.plan_item_id == plan_item_id,
            PlanItemDetailJob.user_id == user_id,
        )
        .scalar_subquery()
    )
    allocated = await db.scalar(
        select(
            func.greatest(
                func.clock_timestamp(),
                func.coalesce(next_prior_epoch, func.clock_timestamp()),
            )
        )
    )
    return type_cast(datetime, allocated)


async def new_plan_item_detail_job(
    db: Any,
    *,
    plan_item_id: str,
    user_id: str,
    **values: Any,
) -> PlanItemDetailJob:
    """Construct a runtime job with monotonic database artifact chronology."""

    return PlanItemDetailJob(
        plan_item_id=plan_item_id,
        user_id=user_id,
        artifact_epoch_at=await allocate_detail_artifact_epoch(
            db,
            plan_item_id=plan_item_id,
            user_id=user_id,
        ),
        **values,
    )


def current_item_completion_predicates(
    item: PlanItem,
    *,
    user_id: str,
) -> tuple[Any, ...]:
    return (
        PlanItemCompletion.user_id == user_id,
        PlanItemCompletion.plan_item_id == item.id,
        artifact_identity_predicate(
            PlanItemCompletion.artifact_job_id,
            current_artifact_job_id(item),
        ),
        artifact_job_reference_predicate(
            item.details_json,
            plan_item_id=str(item.id),
            user_id=user_id,
        ),
        true() if item_completion_artifact_is_eligible(item.details_json) else false(),
        PlanItemCompletion.completed_at.isnot(None),
    )


def current_step_completion_predicates(
    item: PlanItem,
    *,
    user_id: str,
    step_ids: Sequence[str] | None = None,
) -> tuple[Any, ...]:
    eligible_ids = progress_eligible_step_ids(item.details_json)
    if step_ids is None:
        current_ids = eligible_ids
    else:
        eligible_set = frozenset(eligible_ids)
        current_ids = tuple(step_id for step_id in step_ids if step_id in eligible_set)
    return (
        PlanItemStepCompletion.user_id == user_id,
        PlanItemStepCompletion.plan_item_id == item.id,
        PlanItemStepCompletion.step_id.in_(current_ids),
        artifact_identity_predicate(
            PlanItemStepCompletion.artifact_job_id,
            current_artifact_job_id(item),
        ),
        artifact_job_reference_predicate(
            item.details_json,
            plan_item_id=str(item.id),
            user_id=user_id,
        ),
        PlanItemStepCompletion.completed_at.isnot(None),
    )


def current_step_ids(item: PlanItem) -> tuple[str, ...]:
    steps = validated_lesson_steps(item.details_json)
    if steps is None:
        return ()
    return tuple(str(step["id"]) for step in steps)


def progressive_ready_step_ids(details_json: Any) -> tuple[str, ...]:
    """Return strict, current, substantive ready IDs for a progressive artifact."""

    steps = validated_lesson_steps(details_json)
    if steps is None:
        return ()
    all_ids = tuple(str(step["id"]) for step in steps)
    generation = (
        details_json.get("_generation")
        if isinstance(details_json, Mapping)
        else None
    )
    generation_status = (
        generation.get("status") if isinstance(generation, Mapping) else None
    )
    if generation_status not in {"partial", "generating"}:
        return ()
    ready_ids = validated_ready_step_ids(generation)
    if not ready_ids or not ready_ids.issubset(frozenset(all_ids)):
        return ()
    return tuple(
        str(step["id"])
        for step in steps
        if str(step["id"]) in ready_ids
        and len(str(step.get("lesson_content") or "").split())
        >= MIN_PLAN_DETAIL_LESSON_WORDS
    )


def progress_eligible_step_ids(details_json: Any) -> tuple[str, ...]:
    """Return step IDs whose completion may contribute to visible progress.

    Ready, revoked, and true legacy artifacts retain their full strict step
    set. During modern progressive generation, only current, substantive,
    explicitly ready checkpoints are eligible. A malformed/non-current ready
    list or any unsupported modern status fails closed.
    """

    steps = validated_lesson_steps(details_json)
    if steps is None:
        return ()
    all_ids = tuple(str(step["id"]) for step in steps)
    generation = (
        details_json.get("_generation")
        if isinstance(details_json, Mapping)
        else None
    )
    generation_status = (
        generation.get("status") if isinstance(generation, Mapping) else None
    )
    if artifact_job_marker_is_invalid(details_json):
        return ()
    if generation_status in {"partial", "generating"}:
        return progressive_ready_step_ids(details_json)
    if generation_status in {"ready", "revoked"}:
        return all_ids
    if generation_status is not None:
        return ()
    if isinstance(generation, Mapping) and "status" in generation:
        return ()
    artifact_job_id = artifact_job_id_from_details(details_json)
    if artifact_job_id is None:
        return all_ids
    return ()


def current_item_completion_join_predicate() -> Any:
    """Match completion rows to the artifact currently embedded in PlanItem.

    Casting UUID to text avoids ever binding/casting an invalid JSON marker.
    A NULL completion is legacy only when the ``job_id`` key is truly absent;
    present null/empty/malformed modern markers fail closed.
    """

    generation_key_present = func.coalesce(
        PlanItem.details_json.op("?")("_generation"),
        false(),
    )
    generation = func.jsonb_extract_path(PlanItem.details_json, "_generation")
    generation_is_object = func.jsonb_typeof(generation) == "object"
    job_key_present = func.coalesce(
        generation.op("?")("job_id"),
        false(),
    )
    embedded_job_id = func.jsonb_extract_path_text(
        PlanItem.details_json,
        "_generation",
        "job_id",
    )
    return or_(
        and_(
            or_(
                not_(generation_key_present),
                and_(generation_is_object, not_(job_key_present)),
            ),
            PlanItemCompletion.artifact_job_id.is_(None),
        ),
        and_(
            job_key_present,
            PlanItemCompletion.artifact_job_id.isnot(None),
            cast(PlanItemCompletion.artifact_job_id, String) == embedded_job_id,
        ),
    )


def current_artifact_job_reference_join_predicate(*, user_id: str) -> Any:
    """Require an owned detail job for a modern embedded artifact marker."""

    generation_key_present = func.coalesce(
        PlanItem.details_json.op("?")("_generation"),
        false(),
    )
    generation = func.jsonb_extract_path(PlanItem.details_json, "_generation")
    generation_is_object = func.jsonb_typeof(generation) == "object"
    job_key_present = func.coalesce(generation.op("?")("job_id"), false())
    embedded_job_id = func.jsonb_extract_path_text(
        PlanItem.details_json,
        "_generation",
        "job_id",
    )
    legacy_marker_absent = or_(
        not_(generation_key_present),
        and_(generation_is_object, not_(job_key_present)),
    )
    owned_job = aliased(PlanItemDetailJob)
    owned_job_exists = exists(
        select(1).where(
            owned_job.plan_item_id == PlanItem.id,
            owned_job.user_id == user_id,
            cast(owned_job.id, String) == embedded_job_id,
        )
    )
    return or_(
        legacy_marker_absent,
        and_(generation_is_object, job_key_present, owned_job_exists),
    )


def current_item_completion_artifact_status_join_predicate() -> Any:
    """Admit legacy, ready, and revoked artifacts to item-level progress."""

    generation_key_present = func.coalesce(
        PlanItem.details_json.op("?")("_generation"),
        false(),
    )
    generation = func.jsonb_extract_path(PlanItem.details_json, "_generation")
    generation_is_object = func.jsonb_typeof(generation) == "object"
    job_key_present = func.coalesce(generation.op("?")("job_id"), false())
    generation_status = func.jsonb_extract_path_text(
        PlanItem.details_json,
        "_generation",
        "status",
    )
    legacy_marker_absent = or_(
        not_(generation_key_present),
        and_(generation_is_object, not_(job_key_present)),
    )
    return or_(
        legacy_marker_absent,
        and_(
            generation_is_object,
            job_key_present,
            generation_status.in_(("ready", "revoked")),
        ),
    )


def no_active_artifact_replacement_predicate(*, user_id: str) -> Any:
    """Exclude completion while the authoritative latest job is replacing it.

    A merely stuck *older* active row must not hide a newer completed artifact,
    so the active candidate must also be the latest job across every status by
    the same wall-clock epoch/id ordering used by workers and API polling.
    """

    active_job = aliased(PlanItemDetailJob)
    newer_job = aliased(PlanItemDetailJob)
    embedded_job_id = func.jsonb_extract_path_text(
        PlanItem.details_json,
        "_generation",
        "job_id",
    )
    newer_job_exists = exists(
        select(1).where(
            newer_job.plan_item_id == active_job.plan_item_id,
            newer_job.user_id == active_job.user_id,
            or_(
                newer_job.artifact_epoch_at > active_job.artifact_epoch_at,
                and_(
                    newer_job.artifact_epoch_at == active_job.artifact_epoch_at,
                    newer_job.id > active_job.id,
                ),
            ),
        )
    )
    active_replacement_exists = exists(
        select(1).where(
            active_job.plan_item_id == PlanItem.id,
            active_job.user_id == user_id,
            active_job.status.in_(ACTIVE_DETAIL_JOB_STATUSES),
            cast(active_job.id, String).is_distinct_from(embedded_job_id),
            not_(newer_job_exists),
        )
    )
    return not_(active_replacement_exists)


def current_item_completion_query_predicates(
    *,
    user_id: str,
    item_ids: Sequence[str] | None = None,
) -> tuple[Any, ...]:
    """Predicates for a query joined from PlanItemCompletion to PlanItem."""

    predicates: list[Any] = [
        PlanItemCompletion.user_id == user_id,
        PlanItemCompletion.completed_at.isnot(None),
        current_item_completion_join_predicate(),
        current_artifact_job_reference_join_predicate(user_id=user_id),
        current_item_completion_artifact_status_join_predicate(),
        no_active_artifact_replacement_predicate(user_id=user_id),
    ]
    if item_ids is not None:
        predicates.append(PlanItemCompletion.plan_item_id.in_(tuple(item_ids)))
    return tuple(predicates)
