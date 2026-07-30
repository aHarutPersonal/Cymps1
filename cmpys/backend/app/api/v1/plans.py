"""
Development plans endpoints.

PROMPT MAPPING:
- POST /plans/generate
  - Service: app.services.planning.generator.generate_plan()
  - Prompts (when LLM mode): planner_system.txt, plan_backbone_generate.txt,
    plan_week_generate.txt
  - LLM: OPTIONAL (controlled by PLAN_GENERATOR_MODE env var)

- All other endpoints: NO LLM (database operations only)
"""

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import ValidationError
from sqlalchemy import and_, select, func, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.chat import ChatThread, MessageRole
from app.models.daily_task_completion import DailyTaskCompletion
from app.models.item_detail_job import PlanItemDetailJob
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.plan import (
    Plan,
    PlanItem,
    PlanItemStatus,
    PlanItemType,
    PlanItemCompletion,
    PlanItemStepCompletion,
)
from app.models.plan_job import PlanGenerationJob
from app.models.user import User
from app.models.user_achievement import UserAchievement
from app.services.content_quality import (
    BOOK_MODULE_QUALITY_GATE_VERSION,
    MIN_PLAN_DETAIL_LESSON_WORDS,
)
from app.services.content_resources import normalized_material_type
from app.services.interview_inputs import (
    INTERVIEW_ANSWER_KEYS,
    build_interview_plan_inputs,
    extract_legacy_weekly_hours,
)
from app.services.planning.artifact_identity import (
    artifact_job_reference_is_valid,
    artifact_job_marker_is_invalid,
    artifact_identity_predicate,
    current_artifact_job_id,
    current_item_completion_predicates,
    current_item_completion_query_predicates,
    current_step_completion_predicates as _current_step_completion_predicates,
    current_step_ids as _current_step_ids,
    new_plan_item_detail_job as _new_plan_item_detail_job,
    progress_eligible_step_ids as _progress_eligible_step_ids,
    progressive_ready_step_ids as _progressive_ready_step_ids,
    validated_lesson_materials as _validated_lesson_materials,
    validated_lesson_steps as _validated_lesson_steps,
)
from app.services.tavily import is_direct_resource_url
from app.schemas.plan import (
    AchievementSuggestionResponse,
    BookIdeaDetail,
    CycleSummaryResponse,
    DetailsStatus,
    ItemDetails,
    ItemProgress,
    MaterialDetail,
    PlanGenerateRequest,
    PlanItemCreate,
    PlanItemDetailedResponse,
    PlanItemResponse,
    PlanItemUpdate,
    PlanResponse,
    RegenerateDetailsResponse,
    StepDetail,
    ToggleCompleteResponse,
    ToggleStepResponse,
    WeekSummaryResponse,
)
from app.schemas.idol import IdolImportResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/plans", tags=["plans"])

MISSION_TYPES = {PlanItemType.PROJECT, PlanItemType.COURSE, PlanItemType.READING}
DAILY_TYPES = {PlanItemType.HABIT, PlanItemType.PRACTICE}
PLAN_JOB_STALE_AFTER = timedelta(minutes=15)
DETAIL_JOB_QUEUE_STALE_AFTER = timedelta(minutes=2)
DETAIL_JOB_RUNNING_STALE_AFTER = timedelta(minutes=10)
ACTIVE_DETAIL_JOB_STATUSES = frozenset({"pending", "queued", "running"})
CATALOG_ASSIGNMENT_CONFLICT_DETAIL = (
    "This personalized lesson changed. Refresh the lesson and try again."
)
PLAN_COMPLETION_CONFLICT_DETAIL = "This plan changed. Refresh the plan and try again."
STEP_COMPLETION_CONFLICT_DETAIL = (
    "This lesson changed. Refresh the lesson and try again."
)


@dataclass(frozen=True)
class _CatalogAssignmentCompletionScope:
    personalized_lesson_version_ids: frozenset[str]
    rows: tuple[Any, ...]


def _catalog_assignment_completion_ids(item: PlanItem) -> frozenset[str] | None:
    """Return the immutable catalog pins represented by an item's details."""

    details = item.details_json if isinstance(item.details_json, dict) else {}
    generation = details.get("_generation")
    if (
        not isinstance(generation, dict)
        or generation.get("content_origin") != "catalog_personalized"
    ):
        return None

    raw_ids = generation.get("personalized_lesson_version_ids") or [
        generation.get("personalized_lesson_version_id")
    ]
    if isinstance(raw_ids, (str, bytes)) or not isinstance(
        raw_ids,
        (list, tuple, set, frozenset),
    ):
        raw_ids = [raw_ids]
    persisted_ids = frozenset(str(value) for value in raw_ids if value)
    if not persisted_ids:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=CATALOG_ASSIGNMENT_CONFLICT_DETAIL,
        )
    return persisted_ids


def _normalized_utc_datetime(value: Any) -> datetime | None:
    """Parse persisted generation timestamps for safe Python comparisons."""

    parsed: datetime
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _details_generation_job_id(item: PlanItem) -> str | None:
    """Compatibility alias for the shared artifact identity helper."""

    return current_artifact_job_id(item)


def _completion_steps_or_conflict(item: PlanItem) -> tuple[Any, ...] | None:
    """Return mutation-safe lesson steps, failing closed on corrupt JSON.

    Legacy items may legitimately have no details or no ``steps`` key. A
    present artifact, however, must be fully parser-safe before any completion
    row or cached item state can be mutated. This deliberately validates the
    complete rendered payload (including materials and top-level schema), not
    only the selected step: completion state must never be created for an
    artifact that the detailed endpoint cannot render.
    """

    details = item.details_json
    if details is None:
        return None
    if not isinstance(details, dict):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=STEP_COMPLETION_CONFLICT_DETAIL,
        )
    if "steps" not in details:
        return None
    steps = _validated_lesson_steps(details)
    materials = _validated_lesson_materials(details)
    if steps is None or materials is None or _parse_item_details(details) is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=STEP_COMPLETION_CONFLICT_DETAIL,
        )
    return steps


async def _database_completion_time(db: AsyncSession) -> datetime:
    """Use the database clock shared by job and completion timestamps."""

    now = _normalized_utc_datetime(await db.scalar(select(func.clock_timestamp())))
    if now is None:
        logger.error("[PLAN_ITEM] Database did not return a completion timestamp")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Progress could not be saved. Try again.",
        )
    return now


async def _latest_active_detail_job(
    db: AsyncSession,
    *,
    item_id: str,
    user_id: str,
) -> PlanItemDetailJob | None:
    result = await db.execute(
        select(PlanItemDetailJob)
        .where(
            PlanItemDetailJob.plan_item_id == item_id,
            PlanItemDetailJob.user_id == user_id,
        )
        .order_by(
            PlanItemDetailJob.artifact_epoch_at.desc(),
            PlanItemDetailJob.id.desc(),
        )
        .limit(1)
    )
    latest_job = result.scalar_one_or_none()
    if latest_job is None or latest_job.status not in ACTIVE_DETAIL_JOB_STATUSES:
        return None
    return latest_job


def _active_job_replaces_artifact(
    item: PlanItem,
    active_job: PlanItemDetailJob | None,
) -> bool:
    if active_job is None:
        return False
    return str(active_job.id) != _details_generation_job_id(item)


async def _validate_expected_artifact(
    db: AsyncSession,
    item: PlanItem,
    *,
    user_id: str,
    expected_job_id: str | None,
) -> None:
    """Reject mutations from a client that rendered an older modern artifact."""

    if artifact_job_marker_is_invalid(item.details_json):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=STEP_COMPLETION_CONFLICT_DETAIL,
        )
    current_job_id = _details_generation_job_id(item)
    if current_job_id is None:
        if expected_job_id is None:
            return  # Legacy artifacts predate optimistic-concurrency tokens.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=STEP_COMPLETION_CONFLICT_DETAIL,
        )
    if expected_job_id is not None:
        if str(expected_job_id) != current_job_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=STEP_COMPLETION_CONFLICT_DETAIL,
            )

    if not await artifact_job_reference_is_valid(
        db,
        item.details_json,
        plan_item_id=str(item.id),
        user_id=user_id,
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=STEP_COMPLETION_CONFLICT_DETAIL,
        )
    if expected_job_id is not None:
        return

    details = item.details_json if isinstance(item.details_json, dict) else {}
    generation = details.get("_generation")
    if isinstance(generation, dict) and generation.get("supersedes_artifact"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=STEP_COMPLETION_CONFLICT_DETAIL,
        )

    # Tokenless compatibility follows the durable publication marker, not raw
    # job history. Failed/never-published attempts do not create an ambiguous
    # artifact; a genuine replacement always persists supersedes_artifact.


async def _lock_catalog_assignment_completion_scope(
    db: AsyncSession,
    *,
    item: PlanItem,
    user_id: str,
) -> _CatalogAssignmentCompletionScope | None:
    """Lock and validate the exact assignment set represented by an item."""

    persisted_ids = _catalog_assignment_completion_ids(item)
    if persisted_ids is None:
        return None

    from app.models.curriculum import AssignmentStatus
    from app.services.planning.catalog_lessons import (
        PersonalizationQualityError,
        lock_catalog_assignments_for_mutation,
    )

    try:
        rows = await lock_catalog_assignments_for_mutation(
            db,
            plan_id=str(item.plan_id),
            plan_item_id=str(item.id),
            personalized_lesson_version_ids=sorted(persisted_ids),
            require_ready_personalized_version_ids=sorted(persisted_ids),
            expected_user_id=str(user_id),
        )
    except PersonalizationQualityError as exc:
        logger.info(
            "Catalog completion scope changed item_id=%s user_id=%s: %s",
            item.id,
            user_id,
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=CATALOG_ASSIGNMENT_CONFLICT_DETAIL,
        ) from exc

    locked_ids = [
        str(row.personalized_lesson_version_id)
        for row in rows
        if row.personalized_lesson_version_id is not None
    ]
    if len(rows) != len(persisted_ids) or set(locked_ids) != set(persisted_ids):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=CATALOG_ASSIGNMENT_CONFLICT_DETAIL,
        )
    if any(
        row.status in {AssignmentStatus.SKIPPED, AssignmentStatus.REPLACED}
        for row in rows
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=CATALOG_ASSIGNMENT_CONFLICT_DETAIL,
        )
    return _CatalogAssignmentCompletionScope(persisted_ids, tuple(rows))


def _apply_catalog_assignment_completion(
    scope: _CatalogAssignmentCompletionScope | None,
    *,
    completed: bool,
    now: datetime,
    personalized_lesson_version_id: str | None = None,
) -> None:
    if scope is None:
        return

    from app.models.curriculum import AssignmentStatus

    target_ids = scope.personalized_lesson_version_ids
    if personalized_lesson_version_id is not None:
        selected_id = str(personalized_lesson_version_id)
        if selected_id not in target_ids:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=CATALOG_ASSIGNMENT_CONFLICT_DETAIL,
            )
        target_ids = frozenset({selected_id})

    for row in scope.rows:
        if str(row.personalized_lesson_version_id) not in target_ids:
            continue
        row.status = (
            AssignmentStatus.COMPLETED if completed else AssignmentStatus.IN_PROGRESS
        )
        if completed:
            row.completed_at = row.completed_at or now
        else:
            row.completed_at = None
            row.started_at = row.started_at or now


async def _sync_catalog_assignment_completion(
    db: AsyncSession,
    *,
    item: PlanItem,
    user_id: str,
    completed: bool,
    now: datetime,
    personalized_lesson_version_id: str | None = None,
) -> None:
    """Keep catalog scheduling state aligned with an explicit item toggle."""

    scope = await _lock_catalog_assignment_completion_scope(
        db,
        item=item,
        user_id=user_id,
    )
    _apply_catalog_assignment_completion(
        scope,
        completed=completed,
        now=now,
        personalized_lesson_version_id=personalized_lesson_version_id,
    )


def _plan_job_is_stale(
    job: PlanGenerationJob,
    *,
    now: datetime | None = None,
) -> bool:
    """Return whether a pending/running job has stopped making progress.

    Celery's hard time limit is ten minutes. A fifteen-minute window avoids
    duplicating healthy work while allowing recovery after a broker failure,
    worker restart, or an onboarding request that persisted the job but lost
    the task message.
    """
    last_update = getattr(job, "updated_at", None) or job.created_at
    if last_update is None:
        return True
    if last_update.tzinfo is None:
        last_update = last_update.replace(tzinfo=timezone.utc)
    return (now or datetime.now(timezone.utc)) - last_update >= PLAN_JOB_STALE_AFTER


def _detail_job_is_stale(
    job: PlanItemDetailJob,
    *,
    now: datetime | None = None,
) -> bool:
    last_update = getattr(job, "updated_at", None) or job.created_at
    if last_update is None:
        return True
    if last_update.tzinfo is None:
        last_update = last_update.replace(tzinfo=timezone.utc)
    stale_after = (
        DETAIL_JOB_RUNNING_STALE_AFTER
        if getattr(job, "status", None) == "running"
        else DETAIL_JOB_QUEUE_STALE_AFTER
    )
    return (now or datetime.now(timezone.utc)) - last_update >= stale_after


async def _promote_prefetched_detail_job(
    db: AsyncSession,
    job: PlanItemDetailJob,
) -> str | None:
    """Republish an unopened prefetch on the user-facing priority queue.

    The worker atomically claims queued/pending rows, so the original
    low-priority message and this promoted message cannot both generate the
    lesson. Returns ``promoted``, ``failed``, or ``None`` when no promotion was
    needed (or another worker already claimed it).
    """
    prefetch_steps = {"prefetch_queued", "background_queued"}
    if job.status not in {"pending", "queued"} or job.step not in prefetch_steps:
        return None

    original_status = job.status
    promoted = await db.execute(
        update(PlanItemDetailJob)
        .where(
            PlanItemDetailJob.id == job.id,
            PlanItemDetailJob.status == original_status,
            PlanItemDetailJob.step.in_(prefetch_steps),
        )
        .values(
            status="queued",
            step="user_priority",
            error_message=None,
        )
    )
    await db.commit()
    if promoted.rowcount != 1:
        await db.refresh(job)
        return None

    job.status = "queued"
    job.step = "user_priority"
    try:
        from app.tasks.plans import regenerate_plan_item_details

        regenerate_plan_item_details.apply_async(args=[job.id], queue="high_priority")
        logger.info(
            "[PLAN_ITEM] Promoted prefetched detail job item_id=%s job_id=%s",
            job.plan_item_id,
            job.id,
        )
        return "promoted"
    except Exception as exc:
        logger.exception(
            "[PLAN_ITEM] Could not publish promoted job item_id=%s job_id=%s",
            job.plan_item_id,
            job.id,
        )
        await db.execute(
            update(PlanItemDetailJob)
            .where(
                PlanItemDetailJob.id == job.id,
                PlanItemDetailJob.status == "queued",
            )
            .values(
                status="failed",
                step="error",
                error_message=f"Could not start lesson generation: {exc}"[:4000],
            )
        )
        await db.commit()
        job.status = "failed"
        job.step = "error"
        job.error_message = "Could not start lesson generation"
        return "failed"


def _count_remaining_missions(items, completed_item_ids: set[str]) -> int:
    """Number of mission tasks (project/course/reading) not yet completed.

    Daily rhythm items (habit/practice) never gate plan completion.
    """
    return sum(
        1
        for it in items
        if it.type in MISSION_TYPES and str(it.id) not in completed_item_ids
    )


def _should_clear_completed_at(completed_at_set: bool, next_cycle_exists: bool) -> bool:
    """Un-check recovery: clear a plan's completion stamp only when it was set
    AND no next cycle has been generated from it. Once a next cycle exists the
    stamp is sticky (a cycle-2+ plan is still eligible to clear before its own
    successor exists)."""
    return completed_at_set and not next_cycle_exists


def _item_to_response(
    item: PlanItem,
    *,
    completed_item_ids: set[str] | None = None,
    authoritative_progress: ItemProgress | None = None,
) -> PlanItemResponse:
    """Convert plan item model to response."""
    completed_from_record = (
        item.type not in DAILY_TYPES
        and completed_item_ids is not None
        and str(item.id) in completed_item_ids
    )
    is_daily = item.type in DAILY_TYPES
    authoritative_incomplete = (
        item.type not in DAILY_TYPES
        and completed_item_ids is not None
        and not completed_from_record
    )
    stored_status = item.status
    stored_progress = item.progress_percent
    if authoritative_incomplete and authoritative_progress is not None:
        stored_status = (
            PlanItemStatus.IN_PROGRESS
            if authoritative_progress.completed_steps > 0
            else PlanItemStatus.NOT_STARTED
        )
        stored_progress = min(99, int(round(authoritative_progress.percent)))
    elif authoritative_incomplete:
        # Completion records are authoritative. A replacement artifact can be
        # published while the denormalized PlanItem still says COMPLETED/100.
        if stored_status == PlanItemStatus.COMPLETED:
            stored_status = PlanItemStatus.NOT_STARTED
            stored_progress = 0
        else:
            stored_progress = min(stored_progress, 99)
    return PlanItemResponse(
        id=item.id,
        planId=item.plan_id,
        title=item.title,
        type=item.type,
        description=item.description,
        weekStart=item.week_start,
        weekEnd=item.week_end,
        successMetric=item.success_metric,
        estimatedHours=item.estimated_hours,
        status=(
            PlanItemStatus.NOT_STARTED
            if is_daily
            else PlanItemStatus.COMPLETED
            if completed_from_record
            else stored_status
        ),
        progressPercent=(
            0 if is_daily else 100 if completed_from_record else stored_progress
        ),
        notes=item.notes,
        resourceTitle=item.resource_title,
        resourceUrl=item.resource_url,
        createdAt=item.created_at,
        updatedAt=item.updated_at,
    )


def _detailed_item_response(item: PlanItem, *, completed: bool) -> PlanItemResponse:
    """Render a mission from its current artifact's authoritative completion."""

    completed_ids = {str(item.id)} if completed else set()
    return _item_to_response(item, completed_item_ids=completed_ids)


def _plan_to_response(
    plan: Plan,
    idol_name: str | None = None,
    *,
    completed_item_ids: set[str] | None = None,
) -> PlanResponse:
    """Convert plan model to response."""
    items = [
        _item_to_response(i, completed_item_ids=completed_item_ids) for i in plan.items
    ]
    completed = sum(1 for item in items if item.status == PlanItemStatus.COMPLETED)
    total = len(plan.items)

    # Extract roadmap data from JSONB
    roadmap = plan.roadmap_json or {}

    return PlanResponse(
        id=plan.id,
        userId=plan.user_id,
        idolId=plan.idol_id,
        idolName=idol_name,
        targetAge=plan.target_age,
        durationWeeks=plan.duration_weeks,
        weeklyHours=plan.weekly_hours,
        cycleNumber=plan.cycle_number,
        items=items,
        createdAt=plan.created_at,
        roadmapThesis=roadmap.get("roadmap_thesis"),
        antiGoals=roadmap.get("anti_goals", []),
        totalItems=total,
        completedItems=completed,
        overallProgress=(completed / total * 100) if total > 0 else 0,
    )


# Maximum number of items to pre-generate details for
MAX_PREGENERATE_ITEMS = 5


async def _enqueue_week1_details_generation(plan: Plan, user_id: str) -> None:
    """
    Pre-generate details for Week 1 items (or first N items) so they're
    instantly available when the user opens them.

    Enqueues Celery tasks asynchronously - doesn't block the response.
    """
    from app.tasks.ingestion import regenerate_plan_item_details

    # Get Week 1 items, sorted by week_start then by creation order
    week1_items = [
        item
        for item in plan.items
        if item.week_start == 1 and item.type in MISSION_TYPES
    ]

    # If no week 1 items, take the first N items regardless of week
    if not week1_items:
        week1_items = sorted(
            (item for item in plan.items if item.type in MISSION_TYPES),
            key=lambda x: (x.week_start, x.id),
        )

    # Limit to MAX_PREGENERATE_ITEMS
    items_to_generate = week1_items[:MAX_PREGENERATE_ITEMS]

    # Enqueue detail generation for each item
    for item in items_to_generate:
        task = regenerate_plan_item_details.delay(item.id, user_id)
        logger.info(
            f"[PLAN_GENERATE] Pre-enqueued details for item '{item.title}' "
            f"(id={item.id}, week={item.week_start}, job_id={task.id})"
        )


@router.post(
    "/generate", response_model=IdolImportResponse, status_code=status.HTTP_201_CREATED
)
async def generate_plan_endpoint(
    data: PlanGenerateRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IdolImportResponse:
    """
    Trigger asynchronous plan generation.
    Returns jobId to poll for status.
    """
    canonical_idol_id = data.idolId
    canonical_target_age = data.targetAge
    canonical_weekly_hours = data.weeklyHours
    canonical_focus = data.focus

    # A linked session is authoritative planning context, not a caller-supplied
    # lookup hint. Resolve it within the authenticated user's scope before
    # reading or reusing any job, then derive the plan inputs from that session.
    if data.sessionId:
        session = (
            await db.execute(
                select(IntakeSession)
                .options(
                    selectinload(IntakeSession.interview_thread).selectinload(
                        ChatThread.messages
                    )
                )
                .where(
                    IntakeSession.id == data.sessionId,
                    IntakeSession.user_id == current_user.id,
                )
                .with_for_update(of=IntakeSession)
            )
        ).scalar_one_or_none()
        if session is None:
            raise HTTPException(status_code=404, detail="Session not found")
        if not session.idol_id or str(session.idol_id) != str(data.idolId):
            raise HTTPException(
                status_code=409,
                detail="The selected mentor does not match this intake session.",
            )
        if session.phase not in {
            SessionPhase.COMPARISON,
            SessionPhase.BLUEPRINT,
            SessionPhase.COMPLETED,
        }:
            raise HTTPException(
                status_code=409,
                detail="The intake session is not ready for plan generation.",
            )

        messages = (
            list(session.interview_thread.messages)
            if session.interview_thread is not None
            else []
        )
        baseline = build_interview_plan_inputs(
            messages,
            session_goal=session.user_goal,
        )
        uses_semantic_intake = any(
            message.role == MessageRole.ASSISTANT
            and isinstance(message.response_ui_json, dict)
            and message.response_ui_json.get("answer_key") in INTERVIEW_ANSWER_KEYS
            for message in messages
        )
        if uses_semantic_intake:
            if baseline["missing_keys"]:
                raise HTTPException(
                    status_code=409,
                    detail={
                        "code": "interview_profile_incomplete",
                        "message": "The intake is missing required planning answers.",
                    },
                )
            confirmed_hours = baseline.get("weekly_capacity_hours")
        else:
            # Legacy clients did not persist semantic answer keys. Keep their
            # recovery path, but trust only the owned server transcript rather
            # than the request's caller-controlled weeklyHours fallback.
            confirmed_hours = extract_legacy_weekly_hours(messages)
        if not isinstance(confirmed_hours, int):
            raise HTTPException(
                status_code=409,
                detail={
                    "code": "interview_profile_incomplete",
                    "message": (
                        "The intake has no server-recorded weekly capacity. "
                        "Resume the intake before recovering plan generation."
                    ),
                },
            )
        if not isinstance(session.user_age, int) or session.user_age < 1:
            raise HTTPException(
                status_code=409,
                detail="The intake session has no valid learner age.",
            )

        canonical_idol_id = str(session.idol_id)
        canonical_target_age = session.user_age
        canonical_weekly_hours = confirmed_hours
        target_outcome = baseline.get("target_outcome")
        canonical_focus = (
            str(target_outcome.get("answer") or "").strip()
            if isinstance(target_outcome, dict)
            else None
        ) or session.user_goal

        if not (
            str(session.comparison_output or "").strip()
            and str(session.blueprint_output or "").strip()
        ):
            raise HTTPException(
                status_code=409,
                detail={
                    "code": "session_results_incomplete",
                    "message": (
                        "Comparison and blueprint are required before plan "
                        "generation. Resume this session's generate-results flow."
                    ),
                },
            )

    # Recovery calls can arrive after the onboarding SSE already enqueued the
    # job but before the client persisted its id. Reuse that session-linked
    # job instead of charging for and racing a duplicate plan generation.
    if data.sessionId:
        existing = (
            await db.execute(
                select(PlanGenerationJob)
                .where(
                    PlanGenerationJob.user_id == current_user.id,
                    PlanGenerationJob.idol_id == canonical_idol_id,
                    PlanGenerationJob.session_id == data.sessionId,
                    PlanGenerationJob.status.in_(["pending", "running", "completed"]),
                )
                .order_by(PlanGenerationJob.created_at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        if existing and existing.status == "completed" and existing.plan_id:
            return IdolImportResponse(
                idolId=canonical_idol_id,
                jobId=str(existing.id),
                status=existing.status,
            )
        if existing and existing.status in {"pending", "running"}:
            if existing.status == "pending" and existing.step == "waiting_for_strategy":
                # generate-results stages this row before writing strategy. If
                # its terminal dispatch was lost, publish the same durable job
                # now that both required artifacts are confirmed above.
                existing.target_age = canonical_target_age
                existing.duration_weeks = data.durationWeeks
                existing.weekly_hours = canonical_weekly_hours
                existing.focus = canonical_focus
                existing.progress_percent = 0
                existing.step = "analyzing_gaps"
                existing.error_message = None
                await db.commit()

                from app.tasks.plans import run_plan_generation

                run_plan_generation.delay(str(existing.id))
                return IdolImportResponse(
                    idolId=canonical_idol_id,
                    jobId=str(existing.id),
                    status="pending",
                )

            if not _plan_job_is_stale(existing):
                return IdolImportResponse(
                    idolId=canonical_idol_id,
                    jobId=str(existing.id),
                    status=existing.status,
                )

            # The database row outlived its Celery delivery/worker. Requeue the
            # same idempotent job so clients already polling this id recover as
            # well; creating another row would strand those clients forever.
            existing.status = "pending"
            existing.progress_percent = 0
            existing.step = "analyzing_gaps"
            existing.error_message = None
            await db.commit()

            from app.tasks.plans import run_plan_generation

            run_plan_generation.delay(str(existing.id))
            logger.warning(
                "[PLAN_GENERATE] Requeued stale job id=%s session_id=%s",
                existing.id,
                data.sessionId,
            )
            return IdolImportResponse(
                idolId=canonical_idol_id,
                jobId=str(existing.id),
                status="pending",
            )

    # Create the job record
    job = PlanGenerationJob(
        user_id=current_user.id,
        idol_id=canonical_idol_id,
        session_id=data.sessionId,
        target_age=canonical_target_age,
        duration_weeks=data.durationWeeks,
        weekly_hours=canonical_weekly_hours,
        focus=canonical_focus,
        status="pending",
        progress_percent=0,
        step="analyzing_gaps",
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    # Import and trigger the task
    from app.tasks.plans import run_plan_generation

    run_plan_generation.delay(str(job.id))

    return IdolImportResponse(
        idolId=canonical_idol_id,
        jobId=str(job.id),
        status="pending",
    )


@router.get("/current", response_model=PlanResponse | None)
async def get_current_plan(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> PlanResponse | None:
    """
    Get the user's current plan — the plan for the idol they most recently
    chose, NOT merely the globally-newest plan row.

    Without scoping to the active idol, a user who onboarded with idol A
    (producing plan A) and then switched to idol B would keep seeing plan A
    until B's plan finishes generating — and worse, would keep seeing A even
    though B is now their mentor. We resolve the current idol from the user's
    most recent session and prefer that idol's newest plan. If that idol has no
    plan yet, return None so the client shows "generating" / starts generation
    rather than presenting a stale other-idol plan as current.

    LLM USAGE: NONE (database query only)
    """
    # Resolve the user's current idol from their most recent session that has
    # one selected (the agentic flow selects the idol mid-session).
    latest_session_idol = (
        await db.execute(
            select(IntakeSession.idol_id)
            .where(
                IntakeSession.user_id == current_user.id,
                IntakeSession.idol_id.isnot(None),
            )
            .order_by(IntakeSession.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()

    # This endpoint is polled by the Plan/Today screens and its response never
    # includes item details — defer the multi-KB-per-item JSONB columns so a
    # 30-item plan doesn't drag hundreds of KB out of the DB per poll.
    from sqlalchemy.orm import defer

    stmt = (
        select(Plan)
        .options(
            selectinload(Plan.items).options(
                defer(PlanItem.details_json),
                defer(PlanItem.meta_json),
            ),
            selectinload(Plan.idol),
        )
        .where(Plan.user_id == current_user.id)
    )
    if latest_session_idol is not None:
        stmt = stmt.where(Plan.idol_id == latest_session_idol)
    stmt = stmt.order_by(Plan.created_at.desc()).limit(1)

    result = await db.execute(stmt)
    plan = result.scalar_one_or_none()

    if not plan:
        return None

    item_ids = [str(item.id) for item in plan.items]
    completed_item_ids: set[str] = set()
    if item_ids:
        completion_result = await db.execute(
            select(PlanItemCompletion.plan_item_id)
            .join(PlanItem, PlanItemCompletion.plan_item_id == PlanItem.id)
            .where(
                *current_item_completion_query_predicates(
                    user_id=str(current_user.id),
                    item_ids=item_ids,
                )
            )
        )
        completed_item_ids = {
            str(item_id) for item_id in completion_result.scalars().all()
        }

    idol_name = plan.idol.name if plan.idol else None
    return _plan_to_response(
        plan,
        idol_name,
        completed_item_ids=completed_item_ids,
    )


@router.post(
    "/{plan_id}/items",
    response_model=PlanItemResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_plan_item(
    plan_id: str,
    data: PlanItemCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> PlanItemResponse:
    """
    Manually add an item to a plan.
    """
    # Verify plan ownership
    plan_stmt = select(Plan).where(
        and_(
            Plan.id == plan_id,
            Plan.user_id == current_user.id,
        )
    )
    result = await db.execute(plan_stmt)
    plan = result.scalar_one_or_none()

    if not plan:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Plan not found",
        )

    # If weekStart not provided, default to current plan week
    week_start = data.weekStart
    if week_start is None:
        if plan.start_date:
            days_diff = (datetime.now(timezone.utc) - plan.start_date).days
            week_start = max(1, (days_diff // 7) + 1)
        else:
            week_start = 1

    week_end = data.weekEnd or week_start

    daily_instructions = (
        str(data.dailyInstructions).strip()
        if data.type in DAILY_TYPES and data.dailyInstructions is not None
        else ""
    )
    item = PlanItem(
        plan_id=plan_id,
        title=data.title,
        description=data.description,
        type=data.type,
        week_start=week_start,
        week_end=week_end,
        estimated_hours=data.estimatedHours,
        success_metric=data.successMetric,
        status=PlanItemStatus.NOT_STARTED,
        progress_percent=0,
        meta_json=(
            {"daily_instructions": daily_instructions}
            if daily_instructions
            else None
        ),
    )
    db.add(item)
    await db.flush()

    # Daily rhythms are immediately usable and completed per calendar day.
    # Persist their script on the item itself; no paid long-form lesson job is
    # created or published for HABIT/PRACTICE.
    if item.type in DAILY_TYPES:
        await db.commit()
        await db.refresh(item)
        return _item_to_response(item)

    # Trigger detail generation immediately for usability
    from app.tasks.plans import regenerate_plan_item_details

    job = await _new_plan_item_detail_job(
        db,
        plan_item_id=str(item.id),
        user_id=str(current_user.id),
        status="queued",
    )
    db.add(job)
    await db.commit()
    await db.refresh(item)

    regenerate_plan_item_details.delay(job.id)

    return _item_to_response(item)


# Plan Items router (under /plan-items)
items_router = APIRouter(prefix="/plan-items", tags=["plans"])


@items_router.get("/{plan_item_id}", response_model=PlanItemResponse)
async def get_plan_item(
    plan_item_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> PlanItemResponse:
    """
    Get a specific plan item.

    LLM USAGE: NONE (database query only)
    """
    # Hold the item lock through job selection and progress reads. Otherwise B
    # can publish after an unlocked A read, leaving this response with B's job
    # state but A's completion identity (or vice versa).
    item = await _get_item_for_user(
        db,
        plan_item_id,
        current_user.id,
        for_update=True,
    )

    if item.type in DAILY_TYPES:
        return _item_to_response(item)

    active_job = await _latest_active_detail_job(
        db,
        item_id=str(item.id),
        user_id=str(current_user.id),
    )
    if _active_job_replaces_artifact(item, active_job):
        progress, is_completed = ItemProgress(), False
    else:
        progress, is_completed = await _compute_item_progress(
            db,
            str(current_user.id),
            item,
        )
    completed_ids = {str(item.id)} if is_completed else set()
    return _item_to_response(
        item,
        completed_item_ids=completed_ids,
        authoritative_progress=progress,
    )


@items_router.patch("/{plan_item_id}", response_model=PlanItemResponse)
async def update_plan_item(
    plan_item_id: str,
    data: PlanItemUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> PlanItemResponse:
    """
    Update a plan item's notes.

    Status and progress are derived from artifact-scoped completion records and
    must be changed through the item/step completion endpoints.

    LLM USAGE: NONE (database update only)
    """
    # Notes and the response snapshot share one item lock/transaction, so a
    # terminal B publication cannot race an A progress calculation.
    item = await _get_item_for_user(
        db,
        plan_item_id,
        current_user.id,
        for_update=True,
    )

    if data.notes is not None:
        item.notes = data.notes

    await db.flush()
    await db.refresh(item)

    if item.type in DAILY_TYPES:
        return _item_to_response(item)

    active_job = await _latest_active_detail_job(
        db,
        item_id=str(item.id),
        user_id=str(current_user.id),
    )
    if _active_job_replaces_artifact(item, active_job):
        progress, is_completed = ItemProgress(), False
    else:
        progress, is_completed = await _compute_item_progress(
            db,
            str(current_user.id),
            item,
        )
    completed_ids = {str(item.id)} if is_completed else set()
    return _item_to_response(
        item,
        completed_item_ids=completed_ids,
        authoritative_progress=progress,
    )


# =============================================================================
# Plan Item Details & Completion Endpoints
# =============================================================================


async def _get_item_for_user(
    db: AsyncSession,
    item_id: str,
    user_id: str,
    *,
    for_update: bool = False,
) -> PlanItem:
    """Get a plan item, verifying ownership."""
    stmt = (
        select(PlanItem)
        .join(Plan)
        .where(
            and_(
                PlanItem.id == item_id,
                Plan.user_id == user_id,
            )
        )
    )
    if for_update:
        # Detail generation is a paid, side-effecting operation. Lock the
        # owned item row while deciding whether an active job can be reused or
        # a new one must be created, so concurrent opens/retries serialize
        # without requiring a schema migration.
        stmt = stmt.with_for_update(of=PlanItem).execution_options(
            populate_existing=True
        )
    result = await db.execute(stmt)
    item = result.scalar_one_or_none()

    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Plan item not found",
        )
    return item


async def _lock_plan_item_toggle_state(
    db: AsyncSession,
    *,
    item_id: str,
    user_id: str,
    expected_artifact_job_id: str | None = None,
) -> tuple[Plan, PlanItem, _CatalogAssignmentCompletionScope | None]:
    """Serialize every item/step toggle before reading completion snapshots."""

    item = await _get_item_for_user(db, item_id, user_id)
    initial_plan_id = str(item.plan_id)
    catalog_scope = await _lock_catalog_assignment_completion_scope(
        db,
        item=item,
        user_id=str(user_id),
    )
    # The catalog helper already owns this Plan lock before its assignment and
    # PlanItem locks. Legacy/bespoke toggles take their first row lock here, so
    # every plan-wide completion writer follows Plan -> PlanItem.
    plan_result = await db.execute(
        select(Plan)
        .where(
            Plan.id == initial_plan_id,
            Plan.user_id == user_id,
        )
        .execution_options(populate_existing=True)
        .with_for_update(of=Plan)
    )
    locked_plan = plan_result.scalar_one_or_none()
    if locked_plan is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=PLAN_COMPLETION_CONFLICT_DETAIL,
        )

    # Catalog scope acquisition also already locked this item after the Plan;
    # the reread refreshes ORM state. Non-catalog toggles acquire it here.
    locked_item = await _get_item_for_user(
        db,
        item_id,
        user_id,
        for_update=True,
    )
    if str(locked_item.plan_id) != initial_plan_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=PLAN_COMPLETION_CONFLICT_DETAIL,
        )
    active_job = await _latest_active_detail_job(
        db,
        item_id=str(locked_item.id),
        user_id=str(user_id),
    )
    if _active_job_replaces_artifact(locked_item, active_job):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=STEP_COMPLETION_CONFLICT_DETAIL,
        )
    await _validate_expected_artifact(
        db,
        locked_item,
        user_id=str(user_id),
        expected_job_id=expected_artifact_job_id,
    )
    locked_ids = _catalog_assignment_completion_ids(locked_item)
    if catalog_scope is None:
        scope_changed = locked_ids is not None
    else:
        scope_changed = locked_ids != catalog_scope.personalized_lesson_version_ids
    if scope_changed:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=CATALOG_ASSIGNMENT_CONFLICT_DETAIL,
        )
    return locked_plan, locked_item, catalog_scope


async def _compute_item_progress(
    db: AsyncSession,
    user_id: str,
    item: PlanItem,
    *,
    artifact_reference_validated: bool = False,
) -> tuple[ItemProgress, bool]:
    """Compute progress and completion status for an item."""
    if not artifact_reference_validated and not await artifact_job_reference_is_valid(
        db,
        item.details_json,
        plan_item_id=str(item.id),
        user_id=str(user_id),
    ):
        return ItemProgress(), False

    current_step_ids = _current_step_ids(item)
    total_steps = len(current_step_ids)

    # Historical rows from a replaced artifact must not inflate progress or
    # pre-complete a new lesson that happens to reuse a generic ID like step_1.
    completed_stmt = (
        select(func.count())
        .select_from(PlanItemStepCompletion)
        .where(*_current_step_completion_predicates(item, user_id=user_id))
    )
    completed_result = await db.execute(completed_stmt)
    completed_steps = min(int(completed_result.scalar() or 0), total_steps)

    # Check item-level completion
    item_completion_stmt = select(PlanItemCompletion).where(
        *current_item_completion_predicates(item, user_id=user_id)
    )
    item_completion_result = await db.execute(item_completion_stmt)
    is_completed = item_completion_result.scalar_one_or_none() is not None

    # Calculate percent
    if is_completed:
        completed_steps = total_steps
        percent = 100.0
    elif total_steps > 0:
        percent = round((completed_steps / total_steps) * 100, 1)
    else:
        percent = 0.0

    progress = ItemProgress(
        completed_steps=completed_steps,
        total_steps=total_steps,
        percent=percent,
    )
    return progress, is_completed


async def _reconcile_plan_completion(
    db: AsyncSession,
    *,
    plan: Plan,
    user_id: str,
) -> tuple[bool, int | None]:
    """Reconcile the authoritative plan stamp while its Plan row is locked."""

    items_stmt = select(PlanItem).where(PlanItem.plan_id == plan.id)
    items = (await db.execute(items_stmt)).scalars().all()
    comp_stmt = (
        select(PlanItemCompletion.plan_item_id)
        .join(PlanItem, PlanItemCompletion.plan_item_id == PlanItem.id)
        .where(
            *current_item_completion_query_predicates(
                user_id=user_id,
                item_ids=[str(item.id) for item in items],
            )
        )
    )
    completed_ids = {
        str(plan_item_id)
        for plan_item_id in (await db.execute(comp_stmt)).scalars().all()
    }
    has_missions = any(item.type in MISSION_TYPES for item in items)
    remaining = _count_remaining_missions(items, completed_ids)

    plan_complete = has_missions and remaining == 0
    if plan_complete:
        if plan.completed_at is None:
            plan.completed_at = datetime.now(timezone.utc)
    elif plan.completed_at is not None:
        # Re-opened before any next cycle exists: clear only when no successor
        # cycle has been generated yet (sticky once a next cycle exists).
        next_exists = await db.scalar(
            select(func.count())
            .select_from(Plan)
            .where(Plan.previous_plan_id == plan.id)
        )
        if _should_clear_completed_at(True, bool(next_exists)):
            plan.completed_at = None

    return plan_complete, remaining if has_missions else None


def _parse_material_detail(material: dict) -> MaterialDetail:
    raw_type = normalized_material_type(material)
    content_resource_id = material.get("content_resource_id") or material.get(
        "contentResourceId"
    )
    gate_version = material.get("book_quality_gate_version") or material.get(
        "bookQualityGateVersion"
    )
    validated_book_body = bool(
        raw_type == "book"
        and content_resource_id
        and gate_version == BOOK_MODULE_QUALITY_GATE_VERSION
    )
    body_is_safe = raw_type != "book" or validated_book_body
    ideas = material.get("ideas") if body_is_safe else None
    return MaterialDetail(
        title=material.get("title", ""),
        url=(
            material.get("url") if is_direct_resource_url(material.get("url")) else None
        ),
        type=raw_type or None,
        content_resource_id=content_resource_id,
        canonical_key=material.get("canonical_key") or material.get("canonicalKey"),
        author_or_creator=material.get("author_or_creator")
        or material.get("authorOrCreator"),
        thumbnail_url=material.get("thumbnail_url") or material.get("thumbnailUrl"),
        license_status=material.get("license_status") or material.get("licenseStatus"),
        search_query=material.get("search_query") or material.get("searchQuery"),
        url_resolution_status=(
            material.get("url_resolution_status")
            or material.get("urlResolutionStatus")
            or (
                "resolved"
                if is_direct_resource_url(material.get("url"))
                else "unresolved"
                if material.get("url")
                else None
            )
        ),
        url_provider=material.get("url_provider") or material.get("urlProvider"),
        content_markdown=(material.get("content_markdown") if body_is_safe else None),
        duration_minutes=(material.get("duration_minutes") if body_is_safe else None),
        reason=material.get("reason"),
        ideas=(
            [
                BookIdeaDetail(
                    title=idea.get("title", ""),
                    content=idea.get("content", ""),
                    category=idea.get("category", "Mindset"),
                )
                for idea in ideas
            ]
            if ideas
            else None
        ),
    )


def _parse_item_details(details_json: dict | None) -> ItemDetails | None:
    """Parse details_json into ItemDetails schema."""
    if not isinstance(details_json, dict) or not details_json:
        return None

    try:
        validated_steps = _validated_lesson_steps(details_json)
        if "steps" in details_json and validated_steps is None:
            return None
        validated_materials = _validated_lesson_materials(details_json)
        if validated_materials is None:
            return None
        steps_payload = validated_steps or ()

        steps = [
            StepDetail(
                id=str(s["id"]),
                title=s.get("title", ""),
                description=s.get("description"),
                expected_output=s.get("expected_output"),
                estimate_minutes=s.get("estimate_minutes")
                or s.get("estimateMinutes"),
                reading_minutes=s.get("reading_minutes") or s.get("readingMinutes"),
                practice_minutes=s.get("practice_minutes")
                or s.get("practiceMinutes"),
                order=s.get("order"),
                resources=s.get("resources"),
                substeps=s.get("substeps"),
                lesson_content=s.get("lesson_content"),
            )
            for s in steps_payload
        ]

        materials = [
            _parse_material_detail(material)
            for material in validated_materials
        ]

        return ItemDetails(
            steps=steps,
            materials=materials,
            generated_from_prompt_version=details_json.get(
                "generated_from_prompt_version"
            ),
            generated_at=details_json.get("generated_at"),
        )
    except (AttributeError, TypeError, ValidationError):
        return None


def _lesson_details_meet_quality(details_json: dict | None) -> bool:
    """Treat legacy short lessons as missing so they are upgraded on open."""
    if not details_json:
        return False
    from app.services.planning.catalog_lessons import (
        catalog_details_are_personalized_and_ready,
    )

    if not catalog_details_are_personalized_and_ready(details_json):
        return False
    generation = details_json.get("_generation")
    if (
        isinstance(generation, dict)
        and "job_id" in generation
        and generation.get("status") != "ready"
    ):
        return False
    if _validated_lesson_materials(details_json) is None:
        return False
    steps = _validated_lesson_steps(details_json)
    if not steps:
        return False
    lessons = [str(step.get("lesson_content") or "") for step in steps]
    return _parse_item_details(details_json) is not None and all(
        lesson.strip() and len(lesson.split()) >= MIN_PLAN_DETAIL_LESSON_WORDS
        for lesson in lessons
    )


def _partial_lesson_details_available(details_json: dict | None) -> bool:
    """Expose only explicit checkpoints containing a validated long lesson."""
    if not isinstance(details_json, dict):
        return False
    from app.services.planning.catalog_lessons import (
        catalog_details_are_personalized_and_ready,
    )

    if not catalog_details_are_personalized_and_ready(details_json):
        return False
    generation = details_json.get("_generation")
    if not isinstance(generation, dict) or generation.get("status") not in {
        "partial",
        "generating",
    }:
        return False
    eligible_step_ids = _progressive_ready_step_ids(details_json)
    if not eligible_step_ids:
        return False
    return _parse_item_details(details_json) is not None


async def _artifact_job_reference_is_broken(
    db: AsyncSession,
    details_json: dict | None,
    *,
    user_id: str,
    plan_item_id: str,
) -> bool:
    """Validate modern artifact ownership without treating malformed data as legacy."""

    return not await artifact_job_reference_is_valid(
        db,
        details_json,
        plan_item_id=plan_item_id,
        user_id=user_id,
    )


async def _lesson_details_meet_runtime_quality(
    db: AsyncSession,
    details_json: dict | None,
    *,
    user_id: str,
    plan_item_id: str,
) -> bool:
    if not _lesson_details_meet_quality(details_json):
        return False
    if await _artifact_job_reference_is_broken(
        db,
        details_json,
        user_id=user_id,
        plan_item_id=plan_item_id,
    ):
        return False
    generation = (
        details_json.get("_generation") if isinstance(details_json, dict) else None
    )
    artifact_job_id = (
        str(generation.get("job_id"))
        if isinstance(generation, dict) and generation.get("job_id")
        else None
    )
    active_job = await _latest_active_detail_job(
        db,
        item_id=plan_item_id,
        user_id=user_id,
    )
    if active_job is not None and str(active_job.id) != artifact_job_id:
        return False
    from app.services.planning.catalog_lessons import (
        catalog_details_are_ready_in_database,
    )

    return await catalog_details_are_ready_in_database(
        db,
        details_json,
        user_id=user_id,
        plan_item_id=plan_item_id,
    )


async def _require_completion_artifact_ready(
    db: AsyncSession,
    *,
    item: PlanItem,
    user_id: str,
    catalog_scope: _CatalogAssignmentCompletionScope | None,
    selected_step: Any | None = None,
) -> None:
    """Validate full-item or progressive-step completion readiness."""

    ready = False
    if selected_step is None:
        ready = await _lesson_details_meet_runtime_quality(
            db,
            item.details_json,
            user_id=user_id,
            plan_item_id=str(item.id),
        )
    elif (
        isinstance(selected_step, dict)
        and len(str(selected_step.get("lesson_content") or "").split())
        >= MIN_PLAN_DETAIL_LESSON_WORDS
    ):
        details = item.details_json if isinstance(item.details_json, dict) else {}
        generation = details.get("_generation")
        generation_ready = True
        if isinstance(generation, dict) and "job_id" in generation:
            generation_status = generation.get("status")
            if generation_status in {"partial", "generating"}:
                generation_ready = str(selected_step.get("id")) in frozenset(
                    _progress_eligible_step_ids(details)
                )
            else:
                generation_ready = generation_status == "ready"
        if generation_ready:
            from app.services.planning.catalog_lessons import (
                catalog_details_are_ready_in_database,
                catalog_details_are_personalized_and_ready,
            )

            ready = catalog_details_are_personalized_and_ready(
                details
            ) and await catalog_details_are_ready_in_database(
                db,
                details,
                user_id=user_id,
                plan_item_id=str(item.id),
            )
    if ready:
        return
    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail=(
            CATALOG_ASSIGNMENT_CONFLICT_DETAIL
            if catalog_scope is not None
            else "This personalized lesson is still being prepared"
        ),
    )


def _daily_instructions_for_plan_item(item: PlanItem) -> str | None:
    """Read the generated daily script without requiring lesson generation."""
    for payload in (item.meta_json, item.details_json):
        if isinstance(payload, dict):
            value = payload.get("daily_instructions")
            if value and str(value).strip():
                return str(value).strip()
    return None


async def _item_progress_snapshot(
    db: AsyncSession,
    *,
    item: PlanItem,
    user_id: str,
) -> tuple[ItemProgress, bool, list[str]]:
    """Read progress whose artifact identity matches the supplied item."""

    reference_is_valid = await artifact_job_reference_is_valid(
        db,
        item.details_json,
        plan_item_id=str(item.id),
        user_id=str(user_id),
    )
    if not reference_is_valid:
        return ItemProgress(), False, []
    progress, is_completed = await _compute_item_progress(
        db,
        user_id,
        item,
        artifact_reference_validated=True,
    )
    completed_steps_result = await db.execute(
        select(PlanItemStepCompletion.step_id).where(
            *_current_step_completion_predicates(item, user_id=user_id)
        )
    )
    return (
        progress,
        is_completed,
        [str(step_id) for step_id in completed_steps_result.scalars().all()],
    )


@items_router.get("/{item_id}/detailed", response_model=PlanItemDetailedResponse)
async def get_plan_item_detailed(
    item_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> PlanItemDetailedResponse:
    """
    Get a plan item with details, steps, materials, and progress.

    If details don't exist yet, automatically enqueues a generation job.

    LLM USAGE: INDIRECT (may enqueue Celery task if details missing)
    """
    item = await _get_item_for_user(db, item_id, current_user.id)

    # Habits and practices are lightweight daily rhythms. They reset every
    # day and must never wait for (or pay for) a three-lesson mission module.
    if item.type in DAILY_TYPES:
        completed_today = await db.scalar(
            select(func.count())
            .select_from(DailyTaskCompletion)
            .where(
                DailyTaskCompletion.user_id == current_user.id,
                DailyTaskCompletion.plan_item_id == item.id,
                DailyTaskCompletion.completed_date == datetime.now(timezone.utc).date(),
            )
        )
        return PlanItemDetailedResponse(
            item=_item_to_response(item),
            details=None,
            progress=ItemProgress(),
            completed=False,
            completed_step_ids=[],
            details_status=DetailsStatus.AVAILABLE,
            job_id=None,
            daily_instructions=_daily_instructions_for_plan_item(item),
            completed_today=bool(completed_today),
        )

    # Only the immutable item type is consumed from the initial unlocked read.
    # Refresh and lock every mission before its first progress/job/details
    # snapshot so a terminal artifact B publication cannot be paired with
    # completion state computed from artifact A.
    item = await _get_item_for_user(
        db,
        item_id,
        current_user.id,
        for_update=True,
    )
    progress, is_completed, completed_step_ids = await _item_progress_snapshot(
        db,
        item=item,
        user_id=str(current_user.id),
    )

    # Existing legacy lessons are automatically regenerated once they are
    # opened, so old 2-minute content cannot keep presenting a 40-minute label.
    if await _lesson_details_meet_runtime_quality(
        db,
        item.details_json,
        user_id=str(current_user.id),
        plan_item_id=str(item.id),
    ):
        details = _parse_item_details(item.details_json)
        return PlanItemDetailedResponse(
            item=_detailed_item_response(item, completed=is_completed),
            details=details,
            progress=progress,
            completed=is_completed,
            completed_step_ids=completed_step_ids,
            details_status=DetailsStatus.AVAILABLE,
            job_id=None,
            artifact_job_id=_details_generation_job_id(item),
        )

    # Legacy clients allowed a mission to be marked complete before teach-first
    # lessons existed. Completed work is already terminal: do not spend tokens
    # generating a curriculum the user no longer needs, and never show the
    # contradictory "Done" + "Writing your lesson" state.
    if is_completed and _details_generation_job_id(item) is None:
        active_job = await _latest_active_detail_job(
            db,
            item_id=str(item.id),
            user_id=str(current_user.id),
        )
        if not _active_job_replaces_artifact(item, active_job):
            return PlanItemDetailedResponse(
                item=_detailed_item_response(item, completed=True),
                details=None,
                progress=progress,
                completed=True,
                completed_step_ids=completed_step_ids,
                details_status=DetailsStatus.AVAILABLE,
                job_id=None,
            )

    # No details (or legacy thin details) - inspect the latest generation job.
    # The item lock remains held through this side-effecting lookup/create
    # section, as well as both early terminal return paths above.
    # Failed/invalid jobs are surfaced to the client so it can offer one
    # explicit retry; silently creating a new job on every poll caused an
    # unbounded loading loop when generation repeatedly failed.
    latest_job_stmt = (
        select(PlanItemDetailJob)
        .where(
            and_(
                PlanItemDetailJob.plan_item_id == item_id,
                PlanItemDetailJob.user_id == current_user.id,
            )
        )
        .order_by(
            PlanItemDetailJob.artifact_epoch_at.desc(),
            PlanItemDetailJob.id.desc(),
        )
        .limit(1)
    )
    result = await db.execute(latest_job_stmt)
    existing_job = result.scalar_one_or_none()
    generation = (
        item.details_json.get("_generation")
        if isinstance(item.details_json, dict)
        else None
    )
    catalog_was_revoked = (
        isinstance(generation, dict)
        and generation.get("content_origin") == "catalog_personalized"
        and generation.get("status") == "revoked"
    )
    if (
        catalog_was_revoked
        and existing_job is not None
        and existing_job.status in {"completed", "failed"}
    ):
        # A canonical revocation is an explicit invalidation, not an ordinary
        # generation failure. Queue an append-only replacement automatically.
        existing_job = None
    from app.services.planning.catalog_lessons import (
        catalog_details_are_ready_in_database,
    )

    partial_runtime_safe = await catalog_details_are_ready_in_database(
        db,
        item.details_json,
        user_id=str(current_user.id),
        plan_item_id=str(item.id),
    )
    active_replacement = _active_job_replaces_artifact(
        item,
        (
            existing_job
            if existing_job is not None
            and existing_job.status in ACTIVE_DETAIL_JOB_STATUSES
            else None
        ),
    )
    if active_replacement:
        # Job B owns the next artifact. Never expose Job A's steps or progress
        # while B is able to publish a replacement with reused step IDs.
        progress = ItemProgress()
        is_completed = False
        completed_step_ids = []
    embedded_job_id = _details_generation_job_id(item)
    partial_artifact_owned = bool(
        not artifact_job_marker_is_invalid(item.details_json)
        and embedded_job_id is not None
        and existing_job is not None
        and str(existing_job.id) == embedded_job_id
    )
    partial_details = (
        _parse_item_details(item.details_json)
        if not active_replacement
        and partial_artifact_owned
        and _partial_lesson_details_available(item.details_json)
        and partial_runtime_safe
        else None
    )
    partial_artifact_job_id = (
        embedded_job_id if partial_details is not None else None
    )

    if existing_job and existing_job.status in {"pending", "queued"}:
        await _promote_prefetched_detail_job(db, existing_job)

    if existing_job and existing_job.status in {"queued", "running", "pending"}:
        if _detail_job_is_stale(existing_job):
            existing_job.status = "failed"
            existing_job.step = "error"
            existing_job.error_message = "Generation worker stopped before completion"
            await db.commit()
            logger.warning(
                "[PLAN_ITEM] Stopped stale detail job item_id=%s job_id=%s",
                item_id,
                existing_job.id,
            )
            return PlanItemDetailedResponse(
                item=_detailed_item_response(item, completed=is_completed),
                details=partial_details,
                progress=progress,
                completed=is_completed,
                completed_step_ids=completed_step_ids,
                details_status=(
                    DetailsStatus.PARTIAL
                    if partial_details is not None
                    else DetailsStatus.FAILED
                ),
                job_id=existing_job.id,
                artifact_job_id=partial_artifact_job_id,
                details_progress=existing_job.progress_percent,
                details_step=existing_job.step,
                details_error=(
                    "Lesson preparation stopped before it finished. Generate it again to retry."
                ),
            )
        logger.info(
            f"[PLAN_ITEM] Active job already exists for item_id={item_id}, job_id={existing_job.id}"
        )
        return PlanItemDetailedResponse(
            item=_detailed_item_response(item, completed=is_completed),
            details=partial_details,
            progress=progress,
            completed=is_completed,
            completed_step_ids=completed_step_ids,
            details_status=(
                DetailsStatus.PARTIAL
                if partial_details is not None
                else DetailsStatus.GENERATING
                if existing_job.status == "running"
                else DetailsStatus.PENDING
            ),
            job_id=existing_job.id,
            artifact_job_id=partial_artifact_job_id,
            details_progress=existing_job.progress_percent,
            details_step=existing_job.step,
        )

    if existing_job and existing_job.status in {"failed", "completed"}:
        logger.warning(
            "[PLAN_ITEM] Latest detail job has no usable lesson item_id=%s job_id=%s status=%s",
            item_id,
            existing_job.id,
            existing_job.status,
        )
        return PlanItemDetailedResponse(
            item=_detailed_item_response(item, completed=is_completed),
            details=partial_details,
            progress=progress,
            completed=is_completed,
            completed_step_ids=completed_step_ids,
            details_status=(
                DetailsStatus.PARTIAL
                if partial_details is not None
                else DetailsStatus.FAILED
            ),
            job_id=existing_job.id,
            artifact_job_id=partial_artifact_job_id,
            details_progress=existing_job.progress_percent,
            details_step=existing_job.step,
            details_error=(
                "This lesson could not be prepared. Generate it again to retry."
            ),
        )

    # No details and no active job - enqueue generation job
    from app.tasks.plans import regenerate_plan_item_details

    # Create job
    job = await _new_plan_item_detail_job(
        db,
        plan_item_id=item_id,
        user_id=str(current_user.id),
        status="queued",
        step="loading_context",
        progress_percent=0,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    # Queue the regeneration task on high priority since user is waiting
    try:
        regenerate_plan_item_details.apply_async(args=[job.id], queue="high_priority")
    except Exception as exc:
        logger.exception(
            "[PLAN_ITEM] Could not publish details job item_id=%s job_id=%s",
            item_id,
            job.id,
        )
        job.status = "failed"
        job.step = "error"
        job.error_message = f"Could not start lesson generation: {exc}"[:4000]
        await db.commit()
        return PlanItemDetailedResponse(
            item=_detailed_item_response(item, completed=is_completed),
            details=partial_details,
            progress=progress,
            completed=is_completed,
            completed_step_ids=completed_step_ids,
            details_status=(
                DetailsStatus.PARTIAL
                if partial_details is not None
                else DetailsStatus.FAILED
            ),
            job_id=job.id,
            artifact_job_id=partial_artifact_job_id,
            details_progress=0,
            details_step="error",
            details_error=(
                "Lesson preparation could not start. Generate it again to retry."
            ),
        )
    logger.info(
        f"[PLAN_ITEM] Enqueued high_priority details generation for item_id={item_id}, job_id={job.id}"
    )

    return PlanItemDetailedResponse(
        item=_detailed_item_response(item, completed=False),
        details=None,
        progress=ItemProgress(),
        completed=False,
        completed_step_ids=[],
        details_status=DetailsStatus.PENDING,
        job_id=job.id,
        artifact_job_id=None,
        details_progress=0,
        details_step=job.step,
    )


@items_router.post("/{item_id}/toggle-complete", response_model=ToggleCompleteResponse)
async def toggle_item_complete(
    item_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    artifact_job_id: Annotated[
        str | None,
        Query(alias="artifactJobId"),
    ] = None,
) -> ToggleCompleteResponse:
    """
    Toggle completion status for a plan item.

    If marking complete, also marks all steps as complete.
    If uncompleting, does NOT automatically uncheck steps.

    LLM USAGE: NONE (database update only)
    """
    plan, item, catalog_scope = await _lock_plan_item_toggle_state(
        db,
        item_id=item_id,
        user_id=str(current_user.id),
        expected_artifact_job_id=artifact_job_id,
    )
    lesson_steps = _completion_steps_or_conflict(item)
    current_job_id = _details_generation_job_id(item)

    # The PlanItem lock serializes both the missing-row insert case and updates
    # to existing completion rows. Re-read only after that serialization point.
    completion_stmt = (
        select(PlanItemCompletion)
        .where(
            PlanItemCompletion.user_id == current_user.id,
            PlanItemCompletion.plan_item_id == item_id,
            artifact_identity_predicate(
                PlanItemCompletion.artifact_job_id,
                current_job_id,
            ),
        )
        .execution_options(populate_existing=True)
        .with_for_update(of=PlanItemCompletion)
    )
    result = await db.execute(completion_stmt)
    completion = result.scalar_one_or_none()

    currently_completed = bool(completion and completion.completed_at)

    # Never create completion state from an outline/partial artifact. Existing
    # completion can still be removed without requiring the lesson to remain
    # substantive; catalog revocation keeps its stricter immutable-pin rule.
    if not currently_completed:
        await _require_completion_artifact_ready(
            db,
            item=item,
            user_id=str(current_user.id),
            catalog_scope=catalog_scope,
        )
    elif catalog_scope is not None:
        from app.services.planning.catalog_lessons import (
            catalog_details_are_ready_in_database,
            catalog_details_are_personalized_and_ready,
        )

        if not catalog_details_are_personalized_and_ready(
            item.details_json
        ) or not await catalog_details_are_ready_in_database(
            db,
            item.details_json,
            user_id=str(current_user.id),
            plan_item_id=str(item.id),
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=CATALOG_ASSIGNMENT_CONFLICT_DETAIL,
            )

    now = await _database_completion_time(db)

    if currently_completed:
        # Currently complete -> uncomplete
        # Item-level uncompletion intentionally leaves every step checked. The
        # catalog assignments represent those step/session completions, so they
        # remain COMPLETED as well; only a step toggle demotes its assignment.
        completion.completed_at = None
        new_completed = False
        item.status = (
            PlanItemStatus.IN_PROGRESS
            if lesson_steps
            else PlanItemStatus.NOT_STARTED
        )
    else:
        _apply_catalog_assignment_completion(
            catalog_scope,
            completed=True,
            now=now,
        )

        if completion:
            # Exists but not completed -> mark complete
            completion.completed_at = now
        else:
            # Create new completion record
            completion = PlanItemCompletion(
                user_id=current_user.id,
                plan_item_id=item_id,
                artifact_job_id=current_job_id,
                completed_at=now,
            )
            db.add(completion)

        new_completed = True
        item.status = PlanItemStatus.COMPLETED
        item.progress_percent = 100

        # If marking complete AND details exist, also mark all steps complete
        if lesson_steps is not None:
            step_ids = list(_current_step_ids(item))
            # Batch-fetch existing step completions in a single query instead of
            # one query per step (avoids an N+1 over the item's steps).
            existing_steps: dict[str, PlanItemStepCompletion] = {}
            if step_ids:
                existing_stmt = (
                    select(PlanItemStepCompletion)
                    .where(
                        PlanItemStepCompletion.user_id == current_user.id,
                        PlanItemStepCompletion.plan_item_id == item_id,
                        PlanItemStepCompletion.step_id.in_(step_ids),
                        artifact_identity_predicate(
                            PlanItemStepCompletion.artifact_job_id,
                            current_job_id,
                        ),
                    )
                    .execution_options(populate_existing=True)
                    .with_for_update(of=PlanItemStepCompletion)
                )
                existing_result = await db.execute(existing_stmt)
                existing_steps = {
                    sc.step_id: sc for sc in existing_result.scalars().all()
                }

            for step in lesson_steps:
                step_id = step.get("id")
                if not step_id:
                    continue

                step_completion = existing_steps.get(step_id)
                if step_completion:
                    if step_completion.completed_at is None:
                        step_completion.completed_at = now
                else:
                    step_completion = PlanItemStepCompletion(
                        user_id=current_user.id,
                        plan_item_id=item_id,
                        step_id=step_id,
                        artifact_job_id=current_job_id,
                        completed_at=now,
                    )
                    db.add(step_completion)

    # Reconcile progress and plan completion before releasing the PlanItem lock;
    # otherwise a concurrent step toggle can cross this transaction boundary.
    await db.flush()
    progress, _ = await _compute_item_progress(
        db,
        current_user.id,
        item,
        artifact_reference_validated=True,
    )
    if not new_completed:
        item.progress_percent = int(round(progress.percent))
    await db.flush()

    plan_complete, remaining = await _reconcile_plan_completion(
        db,
        plan=plan,
        user_id=str(current_user.id),
    )
    await db.commit()

    return ToggleCompleteResponse(
        completed=new_completed,
        progress=progress,
        planComplete=plan_complete,
        missionTasksRemaining=remaining,
    )


@items_router.post(
    "/{item_id}/steps/{step_id}/toggle", response_model=ToggleStepResponse
)
async def toggle_step_complete(
    item_id: str,
    step_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    artifact_job_id: Annotated[
        str | None,
        Query(alias="artifactJobId"),
    ] = None,
) -> ToggleStepResponse:
    """
    Toggle completion status for a specific step.

    - Auto-marks item complete if ALL steps are now complete.
    - Auto-uncompletes item if step is being unchecked.

    LLM USAGE: NONE (database update only)
    """
    plan, item, catalog_scope = await _lock_plan_item_toggle_state(
        db,
        item_id=item_id,
        user_id=str(current_user.id),
        expected_artifact_job_id=artifact_job_id,
    )
    lesson_steps = _completion_steps_or_conflict(item)
    current_job_id = _details_generation_job_id(item)

    # Verify step exists in details
    if lesson_steps is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Item has no steps defined",
        )
    step_ids = [step.get("id") for step in lesson_steps]
    if step_id not in step_ids:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Step {step_id} not found in item",
        )
    step_index = step_ids.index(step_id)
    selected_step = lesson_steps[step_index]
    selected_version_id = (
        str(selected_step.get("personalized_lesson_version_id"))
        if selected_step.get("personalized_lesson_version_id")
        else None
    )
    if catalog_scope is not None and (
        selected_version_id is None
        or selected_version_id not in catalog_scope.personalized_lesson_version_ids
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=CATALOG_ASSIGNMENT_CONFLICT_DETAIL,
        )

    # PlanItem serialization protects the missing-row case; lock and refresh an
    # existing row so every toggle observes the latest committed state.
    step_stmt = (
        select(PlanItemStepCompletion)
        .where(
            PlanItemStepCompletion.user_id == current_user.id,
            PlanItemStepCompletion.plan_item_id == item_id,
            PlanItemStepCompletion.step_id == step_id,
            artifact_identity_predicate(
                PlanItemStepCompletion.artifact_job_id,
                current_job_id,
            ),
        )
        .execution_options(populate_existing=True)
        .with_for_update(of=PlanItemStepCompletion)
    )
    result = await db.execute(step_stmt)
    step_completion = result.scalar_one_or_none()
    currently_step_completed = bool(
        step_completion and step_completion.completed_at is not None
    )

    if not currently_step_completed:
        await _require_completion_artifact_ready(
            db,
            item=item,
            user_id=str(current_user.id),
            catalog_scope=catalog_scope,
            selected_step=selected_step,
        )
    elif catalog_scope is not None:
        # Preserve the existing rule that a revoked immutable catalog pin
        # cannot be locally uncompleted into contradictory assignment state.
        from app.services.planning.catalog_lessons import (
            catalog_details_are_ready_in_database,
            catalog_details_are_personalized_and_ready,
        )

        if not catalog_details_are_personalized_and_ready(
            item.details_json
        ) or not await catalog_details_are_ready_in_database(
            db,
            item.details_json,
            user_id=str(current_user.id),
            plan_item_id=str(item.id),
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=CATALOG_ASSIGNMENT_CONFLICT_DETAIL,
            )

    full_artifact_ready_for_completion: bool | None = None
    if currently_step_completed:
        now = await _database_completion_time(db)
        # Currently complete -> uncomplete
        # Auto-uncomplete the item
        item_completion_stmt = (
            select(PlanItemCompletion)
            .where(
                PlanItemCompletion.user_id == current_user.id,
                PlanItemCompletion.plan_item_id == item_id,
                artifact_identity_predicate(
                    PlanItemCompletion.artifact_job_id,
                    current_job_id,
                ),
            )
            .execution_options(populate_existing=True)
            .with_for_update(of=PlanItemCompletion)
        )
        item_result = await db.execute(item_completion_stmt)
        item_completion = item_result.scalar_one_or_none()
        _apply_catalog_assignment_completion(
            catalog_scope,
            completed=False,
            now=now,
            personalized_lesson_version_id=selected_version_id,
        )
        step_completion.completed_at = None
        if item_completion and item_completion.completed_at:
            item_completion.completed_at = None
        new_step_completed = False
    else:
        # Lessons are intentionally sequential. The API enforces the same gate
        # as the UI so a future lesson cannot be completed through a stale or
        # handcrafted client request.
        prior_step_ids = [sid for sid in step_ids[:step_index] if sid]
        other_step_ids = [sid for sid in step_ids if sid and sid != step_id]
        completed_other_ids: set[str] = set()
        if other_step_ids:
            other_result = await db.execute(
                select(PlanItemStepCompletion.step_id).where(
                    *_current_step_completion_predicates(
                        item,
                        user_id=str(current_user.id),
                        step_ids=other_step_ids,
                    )
                )
            )
            completed_other_ids = {
                str(completed_step_id)
                for completed_step_id in other_result.scalars().all()
            }
            missing_prior = [
                sid for sid in prior_step_ids if sid not in completed_other_ids
            ]
            if missing_prior:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Complete the earlier lessons before advancing",
                )
        now = await _database_completion_time(db)
        if len(completed_other_ids) + 1 == len(step_ids):
            full_artifact_ready_for_completion = (
                await _lesson_details_meet_runtime_quality(
                    db,
                    item.details_json,
                    user_id=str(current_user.id),
                    plan_item_id=str(item.id),
                )
            )
            if not full_artifact_ready_for_completion:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="This personalized lesson is still being prepared",
                )
        _apply_catalog_assignment_completion(
            catalog_scope,
            completed=True,
            now=now,
            personalized_lesson_version_id=selected_version_id,
        )
        if step_completion:
            step_completion.completed_at = now
        else:
            step_completion = PlanItemStepCompletion(
                user_id=current_user.id,
                plan_item_id=item_id,
                step_id=step_id,
                artifact_job_id=current_job_id,
                completed_at=now,
            )
            db.add(step_completion)

        new_step_completed = True

    # Keep the PlanItem lock through progress reconciliation so item and step
    # completion cannot cross in separate transactions.
    await db.flush()
    progress, is_item_completed = await _compute_item_progress(
        db,
        current_user.id,
        item,
        artifact_reference_validated=True,
    )

    # Auto-mark item complete if all steps done
    total_steps = len(_current_step_ids(item))
    all_steps_completed = (
        new_step_completed
        and progress.completed_steps == total_steps
        and not is_item_completed
    )
    artifact_fully_ready = False
    if all_steps_completed:
        artifact_fully_ready = (
            full_artifact_ready_for_completion
            if full_artifact_ready_for_completion is not None
            else await _lesson_details_meet_runtime_quality(
                db,
                item.details_json,
                user_id=str(current_user.id),
                plan_item_id=str(item.id),
            )
        )
    if artifact_fully_ready:
        item_completion_stmt = (
            select(PlanItemCompletion)
            .where(
                PlanItemCompletion.user_id == current_user.id,
                PlanItemCompletion.plan_item_id == item_id,
                artifact_identity_predicate(
                    PlanItemCompletion.artifact_job_id,
                    current_job_id,
                ),
            )
            .execution_options(populate_existing=True)
            .with_for_update(of=PlanItemCompletion)
        )
        item_result = await db.execute(item_completion_stmt)
        item_completion = item_result.scalar_one_or_none()

        if item_completion:
            item_completion.completed_at = now
        else:
            item_completion = PlanItemCompletion(
                user_id=current_user.id,
                plan_item_id=item_id,
                artifact_job_id=current_job_id,
                completed_at=now,
            )
            db.add(item_completion)

        item.status = PlanItemStatus.COMPLETED
        item.progress_percent = 100
        is_item_completed = True
    else:
        item.status = (
            PlanItemStatus.COMPLETED
            if is_item_completed
            else PlanItemStatus.IN_PROGRESS
            if progress.completed_steps > 0
            else PlanItemStatus.NOT_STARTED
        )
        item.progress_percent = (
            100
            if is_item_completed
            else min(99, int(round(progress.percent)))
        )
    await db.flush()
    await _reconcile_plan_completion(
        db,
        plan=plan,
        user_id=str(current_user.id),
    )
    await db.commit()

    # As soon as the user completes the first lesson of this week, prepare the
    # next week's missions at low priority. This gives the background workers
    # the rest of the current week to finish, while current user-facing work
    # always retains queue priority. The organizer is idempotent.
    if new_step_completed and step_index == 0:
        duration_weeks = await db.scalar(
            select(Plan.duration_weeks).where(Plan.id == item.plan_id)
        )
        next_week = item.week_end + 1
        if duration_weeks is not None and next_week <= duration_weeks:
            try:
                from app.tasks.plans import prefetch_plan_week_details

                prefetch_plan_week_details.apply_async(
                    args=[str(item.plan_id), str(current_user.id), next_week],
                    kwargs={"priority": "low"},
                    queue="low_priority",
                )
            except Exception:
                # Lesson completion is authoritative and must never fail merely
                # because speculative look-ahead publishing is unavailable.
                logger.exception(
                    "[PLAN_ITEM] Could not schedule week look-ahead plan_id=%s week=%s",
                    item.plan_id,
                    next_week,
                )

    return ToggleStepResponse(
        step_id=step_id,
        completed=new_step_completed,
        progress=progress,
        item_completed=is_item_completed,
    )


@items_router.post(
    "/{item_id}/regenerate-details", response_model=RegenerateDetailsResponse
)
async def regenerate_item_details(
    item_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> RegenerateDetailsResponse:
    """
    Trigger async regeneration of item details (steps + materials) via LLM.

    LLM USAGE: INDIRECT (queued via Celery task)

    Returns job_id to poll for completion.
    """
    # The row lock makes the active-job check plus insert atomic with respect
    # to every other detail open/retry for this item. The lock is released by
    # the commit that persists a new job (or when this request transaction
    # closes on a no-op/reuse response).
    item = await _get_item_for_user(
        db,
        item_id,
        current_user.id,
        for_update=True,
    )
    if item.type in DAILY_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Daily rhythms do not require lesson generation",
        )

    # A stale client may retry after another worker already finished. Do not
    # create a second paid generation in that race; Flutter refreshes the
    # detailed endpoint immediately and does not require a non-empty job id.
    if await _lesson_details_meet_runtime_quality(
        db,
        item.details_json,
        user_id=str(current_user.id),
        plan_item_id=str(item.id),
    ):
        return RegenerateDetailsResponse(job_id="")

    # Make retries idempotent. A double tap or transport retry should observe
    # the same active job instead of charging for two long-form generations.
    active_job = await _latest_active_detail_job(
        db,
        item_id=item_id,
        user_id=str(current_user.id),
    )
    if active_job and active_job.status in {"pending", "queued"}:
        promotion = await _promote_prefetched_detail_job(db, active_job)
        if promotion == "promoted":
            return RegenerateDetailsResponse(job_id=active_job.id)
        if promotion == "failed":
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Lesson generation is temporarily unavailable",
            )
    if active_job and not _detail_job_is_stale(active_job):
        return RegenerateDetailsResponse(job_id=active_job.id)

    broken_artifact_reference = await _artifact_job_reference_is_broken(
        db,
        item.details_json,
        user_id=str(current_user.id),
        plan_item_id=str(item.id),
    )

    # Completion records are the authoritative state (item.status can be stale
    # on legacy rows). Recheck immediately before enqueueing a replacement.
    completion_result = await db.execute(
        select(PlanItemCompletion.id)
        .where(*current_item_completion_predicates(item, user_id=str(current_user.id)))
        .limit(1)
    )
    completed = completion_result.scalar_one_or_none() is not None
    if completed and not broken_artifact_reference:
        if active_job:
            active_job.status = "failed"
            active_job.step = "error"
            active_job.error_message = "Mission completed before lesson retry"
            await db.commit()
        return RegenerateDetailsResponse(job_id="")

    if active_job:
        active_job.status = "failed"
        active_job.step = "error"
        active_job.error_message = "Generation worker stopped before completion"

    # Create job
    job = await _new_plan_item_detail_job(
        db,
        plan_item_id=item_id,
        user_id=str(current_user.id),
        status="queued",
        step="loading_context",
        progress_percent=0,
    )
    db.add(job)
    await db.commit()

    # Import here to avoid circular imports
    from app.tasks.plans import regenerate_plan_item_details

    # Queue the regeneration task on high priority
    try:
        regenerate_plan_item_details.apply_async(args=[job.id], queue="high_priority")
    except Exception as exc:
        logger.exception(
            "[PLAN_ITEM] Could not publish retry item_id=%s job_id=%s",
            item_id,
            job.id,
        )
        job.status = "failed"
        job.step = "error"
        job.error_message = f"Could not start lesson generation: {exc}"[:4000]
        await db.commit()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Lesson generation is temporarily unavailable",
        ) from exc

    return RegenerateDetailsResponse(job_id=job.id)


@items_router.post(
    "/{item_id}/achievement-suggestion",
    response_model=AchievementSuggestionResponse,
)
async def achievement_suggestion(
    item_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> AchievementSuggestionResponse:
    from app.services.achievements.suggestion import ai_suggestion

    item = await _get_item_for_user(db, item_id, current_user.id)
    plan = await db.get(Plan, item.plan_id)
    idol = await db.get(Idol, plan.idol_id) if plan else None
    out = await ai_suggestion(item, idol.name if idol else "your mentor")
    return AchievementSuggestionResponse(**out)


# =============================================================================
# Plan Week Summary
# =============================================================================


@router.get("/{plan_id}/weeks/{week}/summary", response_model=WeekSummaryResponse)
async def get_week_summary(
    plan_id: str,
    week: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> WeekSummaryResponse:
    """
    Get summary of progress for a specific week.

    LLM USAGE: NONE (database query only)
    """
    # Verify plan ownership
    plan_stmt = select(Plan).where(
        and_(
            Plan.id == plan_id,
            Plan.user_id == current_user.id,
        )
    )
    plan_result = await db.execute(plan_stmt)
    plan = plan_result.scalar_one_or_none()

    if not plan:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Plan not found",
        )

    # Get all items for this week
    items_stmt = select(PlanItem.id).where(
        PlanItem.plan_id == plan_id,
        PlanItem.week_start <= week,
        PlanItem.week_end >= week,
    )
    items_result = await db.execute(items_stmt)
    item_ids = [row[0] for row in items_result.fetchall()]

    total_items = len(item_ids)

    if total_items == 0:
        return WeekSummaryResponse(
            week=week,
            completed_items=0,
            total_items=0,
            percent=0.0,
        )

    # Count completed items
    completed_stmt = (
        select(func.count())
        .select_from(PlanItemCompletion)
        .join(PlanItem, PlanItemCompletion.plan_item_id == PlanItem.id)
        .where(
            *current_item_completion_query_predicates(
                user_id=str(current_user.id),
                item_ids=item_ids,
            )
        )
    )
    completed_result = await db.execute(completed_stmt)
    completed_items = completed_result.scalar() or 0

    percent = (
        round((completed_items / total_items) * 100, 1) if total_items > 0 else 0.0
    )

    return WeekSummaryResponse(
        week=week,
        completed_items=completed_items,
        total_items=total_items,
        percent=percent,
    )


def _next_cycle_fields(prev_plan) -> dict:
    """Fields for the next cycle's PlanGenerationJob, derived from the parent."""
    return {
        "cycle_number": (prev_plan.cycle_number or 1) + 1,
        "previous_plan_id": str(prev_plan.id),
        "idol_id": prev_plan.idol_id,
        "weekly_hours": prev_plan.weekly_hours,
        "duration_weeks": prev_plan.duration_weeks,
        "target_age": prev_plan.target_age,
    }


@router.post(
    "/{plan_id}/generate-next",
    response_model=IdolImportResponse,
    status_code=status.HTTP_201_CREATED,
)
async def generate_next_plan(
    plan_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IdolImportResponse:
    prev = await db.get(Plan, plan_id)
    if not prev or prev.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Plan not found")

    # Idempotent: reuse an existing job for this parent.
    existing = (
        await db.execute(
            select(PlanGenerationJob)
            .where(PlanGenerationJob.previous_plan_id == str(prev.id))
            .order_by(PlanGenerationJob.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if existing:
        return IdolImportResponse(
            idolId=existing.idol_id, jobId=str(existing.id), status=existing.status
        )

    fields = _next_cycle_fields(prev)
    job = PlanGenerationJob(
        user_id=current_user.id,
        session_id=None,
        focus=None,
        status="pending",
        progress_percent=0,
        step="analyzing_gaps",
        **fields,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    from app.tasks.plans import run_plan_generation

    run_plan_generation.delay(str(job.id))
    return IdolImportResponse(idolId=job.idol_id, jobId=str(job.id), status="pending")


@router.post("/{plan_id}/cycle-summary", response_model=CycleSummaryResponse)
async def plan_cycle_summary(
    plan_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> CycleSummaryResponse:
    from app.services.achievements.suggestion import cycle_summary

    plan = await db.get(Plan, plan_id)
    if not plan or plan.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Plan not found")
    idol = await db.get(Idol, plan.idol_id)
    titles = (
        (
            await db.execute(
                select(UserAchievement.title).where(
                    UserAchievement.user_id == current_user.id,
                    UserAchievement.plan_id == plan_id,
                )
            )
        )
        .scalars()
        .all()
    )
    out = await cycle_summary(idol.name if idol else "your mentor", list(titles))
    return CycleSummaryResponse(**out)
