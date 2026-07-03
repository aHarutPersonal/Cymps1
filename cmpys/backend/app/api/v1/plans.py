"""
Development plans endpoints.

PROMPT MAPPING:
- POST /plans/generate
  - Service: app.services.planning.generator.generate_plan()
  - Prompts (when LLM mode): planner_system.txt, plan_generate.txt
  - LLM: OPTIONAL (controlled by PLAN_GENERATOR_MODE env var)
  
- All other endpoints: NO LLM (database operations only)
"""
import logging
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import and_, select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.intake import IntakeSession
from app.models.item_detail_job import PlanItemDetailJob
from app.models.idol import Idol
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


def _item_to_response(item: PlanItem) -> PlanItemResponse:
    """Convert plan item model to response."""
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
        status=item.status,
        progressPercent=item.progress_percent,
        notes=item.notes,
        resourceTitle=item.resource_title,
        resourceUrl=item.resource_url,
        createdAt=item.created_at,
        updatedAt=item.updated_at,
    )


def _plan_to_response(plan: Plan, idol_name: str | None = None) -> PlanResponse:
    """Convert plan model to response."""
    items = [_item_to_response(i) for i in plan.items]
    completed = sum(1 for i in plan.items if i.status == PlanItemStatus.COMPLETED)
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
        item for item in plan.items
        if item.week_start == 1
    ]
    
    # If no week 1 items, take the first N items regardless of week
    if not week1_items:
        week1_items = sorted(plan.items, key=lambda x: (x.week_start, x.id))
    
    # Limit to MAX_PREGENERATE_ITEMS
    items_to_generate = week1_items[:MAX_PREGENERATE_ITEMS]
    
    # Enqueue detail generation for each item
    for item in items_to_generate:
        task = regenerate_plan_item_details.delay(item.id, user_id)
        logger.info(
            f"[PLAN_GENERATE] Pre-enqueued details for item '{item.title}' "
            f"(id={item.id}, week={item.week_start}, job_id={task.id})"
        )


@router.post("/generate", response_model=IdolImportResponse, status_code=status.HTTP_201_CREATED)
async def generate_plan_endpoint(
    data: PlanGenerateRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IdolImportResponse:
    """
    Trigger asynchronous plan generation.
    Returns jobId to poll for status.
    """
    # Create the job record
    job = PlanGenerationJob(
        user_id=current_user.id,
        idol_id=data.idolId,
        session_id=data.sessionId,
        target_age=data.targetAge,
        duration_weeks=data.durationWeeks,
        weekly_hours=data.weeklyHours,
        focus=data.focus,
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
        idolId=data.idolId,
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
    
    idol_name = plan.idol.name if plan.idol else None
    return _plan_to_response(plan, idol_name)

@router.post("/{plan_id}/items", response_model=PlanItemResponse, status_code=status.HTTP_201_CREATED)
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
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    
    # Trigger detail generation immediately for usability
    from app.tasks.plans import regenerate_plan_item_details
    from app.models.item_detail_job import PlanItemDetailJob
    
    job = PlanItemDetailJob(
        plan_item_id=item.id,
        user_id=current_user.id,
        status="queued"
    )
    db.add(job)
    await db.commit()
    
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
    stmt = (
        select(PlanItem)
        .join(Plan)
        .where(
            and_(
                PlanItem.id == plan_item_id,
                Plan.user_id == current_user.id,
            )
        )
    )
    result = await db.execute(stmt)
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Plan item not found",
        )
    
    return _item_to_response(item)


@items_router.patch("/{plan_item_id}", response_model=PlanItemResponse)
async def update_plan_item(
    plan_item_id: str,
    data: PlanItemUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> PlanItemResponse:
    """
    Update a plan item's status, progress, or notes.
    
    LLM USAGE: NONE (database update only)
    """
    stmt = (
        select(PlanItem)
        .join(Plan)
        .where(
            and_(
                PlanItem.id == plan_item_id,
                Plan.user_id == current_user.id,
            )
        )
    )
    result = await db.execute(stmt)
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Plan item not found",
        )
    
    if data.status is not None:
        item.status = PlanItemStatus(data.status.value)
    if data.progressPercent is not None:
        item.progress_percent = data.progressPercent
    if data.notes is not None:
        item.notes = data.notes
    
    await db.commit()
    await db.refresh(item)
    
    return _item_to_response(item)


# =============================================================================
# Plan Item Details & Completion Endpoints
# =============================================================================

async def _get_item_for_user(
    db: AsyncSession, 
    item_id: str, 
    user_id: str
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
    result = await db.execute(stmt)
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Plan item not found",
        )
    return item


async def _compute_item_progress(
    db: AsyncSession,
    user_id: str,
    item: PlanItem,
) -> tuple[ItemProgress, bool]:
    """Compute progress and completion status for an item."""
    # Get total steps from details_json
    total_steps = 0
    if item.details_json and "steps" in item.details_json:
        total_steps = len(item.details_json["steps"])
    
    # Count completed steps
    completed_stmt = (
        select(func.count())
        .select_from(PlanItemStepCompletion)
        .where(
            PlanItemStepCompletion.user_id == user_id,
            PlanItemStepCompletion.plan_item_id == item.id,
            PlanItemStepCompletion.completed_at.isnot(None),
        )
    )
    completed_result = await db.execute(completed_stmt)
    completed_steps = completed_result.scalar() or 0
    
    # Check item-level completion
    item_completion_stmt = (
        select(PlanItemCompletion)
        .where(
            PlanItemCompletion.user_id == user_id,
            PlanItemCompletion.plan_item_id == item.id,
            PlanItemCompletion.completed_at.isnot(None),
        )
    )
    item_completion_result = await db.execute(item_completion_stmt)
    is_completed = item_completion_result.scalar_one_or_none() is not None
    
    # Calculate percent
    if total_steps > 0:
        percent = round((completed_steps / total_steps) * 100, 1)
    elif is_completed:
        percent = 100.0
    else:
        percent = 0.0
    
    progress = ItemProgress(
        completed_steps=completed_steps,
        total_steps=total_steps,
        percent=percent,
    )
    return progress, is_completed


def _parse_item_details(details_json: dict | None) -> ItemDetails | None:
    """Parse details_json into ItemDetails schema."""
    if not details_json:
        return None
    
    steps = [
        StepDetail(
            id=s.get("id", str(i)),
            title=s.get("title", ""),
            description=s.get("description"),
            expected_output=s.get("expected_output"),
            estimate_minutes=s.get("estimate_minutes") or s.get("estimateMinutes"),
            order=s.get("order"),
            resources=s.get("resources"),
            substeps=s.get("substeps"),
            lesson_content=s.get("lesson_content"),
        )
        for i, s in enumerate(details_json.get("steps", []))
    ]
    
    materials = [
        MaterialDetail(
            title=m.get("title", ""),
            url=m.get("url"),
            type=m.get("type"),
            content_resource_id=m.get("content_resource_id") or m.get("contentResourceId"),
            canonical_key=m.get("canonical_key") or m.get("canonicalKey"),
            author_or_creator=m.get("author_or_creator") or m.get("authorOrCreator"),
            thumbnail_url=m.get("thumbnail_url") or m.get("thumbnailUrl"),
            license_status=m.get("license_status") or m.get("licenseStatus"),
            search_query=m.get("search_query") or m.get("searchQuery"),
            content_markdown=m.get("content_markdown"),
            duration_minutes=m.get("duration_minutes"),
            reason=m.get("reason"),
            ideas=[
                BookIdeaDetail(
                    title=idea.get("title", ""),
                    content=idea.get("content", ""),
                    category=idea.get("category", "Mindset"),
                )
                for idea in m.get("ideas", [])
            ] if m.get("ideas") else None,
        )
        for m in details_json.get("materials", [])
    ]
    
    return ItemDetails(
        steps=steps,
        materials=materials,
        generated_from_prompt_version=details_json.get("generated_from_prompt_version"),
        generated_at=details_json.get("generated_at"),
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
    progress, is_completed = await _compute_item_progress(db, current_user.id, item)
    
    # Check if details exist
    if item.details_json:
        details = _parse_item_details(item.details_json)
        return PlanItemDetailedResponse(
            item=_item_to_response(item),
            details=details,
            progress=progress,
            completed=is_completed,
            details_status=DetailsStatus.AVAILABLE,
            job_id=None,
        )
    
    # No details - check if a job is ALREADY in progress
    active_job_stmt = (
        select(PlanItemDetailJob)
        .where(
            and_(
                PlanItemDetailJob.plan_item_id == item_id,
                PlanItemDetailJob.user_id == current_user.id,
                PlanItemDetailJob.status.in_(["queued", "running", "pending"]),
            )
        )
        .order_by(PlanItemDetailJob.created_at.desc())
        .limit(1)
    )
    result = await db.execute(active_job_stmt)
    existing_job = result.scalar_one_or_none()
    
    if existing_job:
        logger.info(f"[PLAN_ITEM] Active job already exists for item_id={item_id}, job_id={existing_job.id}")
        return PlanItemDetailedResponse(
            item=_item_to_response(item),
            details=None,
            progress=existing_job.progress_percent,
            completed=is_completed,
            details_status=DetailsStatus.PENDING,
            job_id=existing_job.id,
        )

    # No details and no active job - enqueue generation job
    from app.tasks.plans import regenerate_plan_item_details
    
    # Create job
    job = PlanItemDetailJob(
        plan_item_id=item_id,
        user_id=current_user.id,
        status="queued",
        step="loading_context",
        progress_percent=0,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    # Queue the regeneration task on high priority since user is waiting
    regenerate_plan_item_details.apply_async(args=[job.id], queue="high_priority")
    logger.info(f"[PLAN_ITEM] Enqueued high_priority details generation for item_id={item_id}, job_id={job.id}")
    
    return PlanItemDetailedResponse(
        item=_item_to_response(item),
        details=None,
        progress=progress,
        completed=is_completed,
        details_status=DetailsStatus.PENDING,
        job_id=job.id,
    )


@items_router.post("/{item_id}/toggle-complete", response_model=ToggleCompleteResponse)
async def toggle_item_complete(
    item_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ToggleCompleteResponse:
    """
    Toggle completion status for a plan item.
    
    If marking complete, also marks all steps as complete.
    If uncompleting, does NOT automatically uncheck steps.
    
    LLM USAGE: NONE (database update only)
    """
    item = await _get_item_for_user(db, item_id, current_user.id)
    
    # Check current completion status
    completion_stmt = (
        select(PlanItemCompletion)
        .where(
            PlanItemCompletion.user_id == current_user.id,
            PlanItemCompletion.plan_item_id == item_id,
        )
    )
    result = await db.execute(completion_stmt)
    completion = result.scalar_one_or_none()
    
    now = datetime.now(timezone.utc)
    
    if completion and completion.completed_at:
        # Currently complete -> uncomplete
        completion.completed_at = None
        new_completed = False
    else:
        if completion:
            # Exists but not completed -> mark complete
            completion.completed_at = now
        else:
            # Create new completion record
            completion = PlanItemCompletion(
                user_id=current_user.id,
                plan_item_id=item_id,
                completed_at=now,
            )
            db.add(completion)
        
        new_completed = True
        
        # If marking complete AND details exist, also mark all steps complete
        if item.details_json and "steps" in item.details_json:
            step_ids = [
                s.get("id") for s in item.details_json["steps"] if s.get("id")
            ]
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
                    )
                )
                existing_result = await db.execute(existing_stmt)
                existing_steps = {
                    sc.step_id: sc for sc in existing_result.scalars().all()
                }

            for step in item.details_json["steps"]:
                step_id = step.get("id")
                if not step_id:
                    continue

                step_completion = existing_steps.get(step_id)
                if step_completion:
                    if not step_completion.completed_at:
                        step_completion.completed_at = now
                else:
                    step_completion = PlanItemStepCompletion(
                        user_id=current_user.id,
                        plan_item_id=item_id,
                        step_id=step_id,
                        completed_at=now,
                    )
                    db.add(step_completion)
    
    await db.commit()

    # Recompute progress
    progress, _ = await _compute_item_progress(db, current_user.id, item)

    # Completion detection: count remaining mission tasks across the plan.
    items_stmt = select(PlanItem).where(PlanItem.plan_id == item.plan_id)
    items = (await db.execute(items_stmt)).scalars().all()
    comp_stmt = select(PlanItemCompletion.plan_item_id).where(
        PlanItemCompletion.user_id == current_user.id,
        PlanItemCompletion.completed_at.isnot(None),
        PlanItemCompletion.plan_item_id.in_([str(i.id) for i in items]),
    )
    completed_ids = {str(r) for r in (await db.execute(comp_stmt)).scalars().all()}
    has_missions = any(i.type in MISSION_TYPES for i in items)
    remaining = _count_remaining_missions(items, completed_ids)

    plan = await db.get(Plan, item.plan_id)
    plan_complete = False
    if has_missions and remaining == 0:
        if plan and plan.completed_at is None:
            plan.completed_at = datetime.now(timezone.utc)
            await db.commit()
        plan_complete = True
    elif plan and plan.completed_at is not None:
        # Re-opened before any next cycle exists: clear only when no successor
        # cycle has been generated yet (sticky once a next cycle exists).
        next_exists = await db.scalar(
            select(func.count())
            .select_from(Plan)
            .where(Plan.previous_plan_id == plan.id)
        )
        if _should_clear_completed_at(plan.completed_at is not None, bool(next_exists)):
            plan.completed_at = None
            await db.commit()

    return ToggleCompleteResponse(
        completed=new_completed,
        progress=progress,
        planComplete=plan_complete,
        missionTasksRemaining=remaining if has_missions else None,
    )


@items_router.post("/{item_id}/steps/{step_id}/toggle", response_model=ToggleStepResponse)
async def toggle_step_complete(
    item_id: str,
    step_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ToggleStepResponse:
    """
    Toggle completion status for a specific step.
    
    - Auto-marks item complete if ALL steps are now complete.
    - Auto-uncompletes item if step is being unchecked.
    
    LLM USAGE: NONE (database update only)
    """
    item = await _get_item_for_user(db, item_id, current_user.id)
    
    # Verify step exists in details
    if not item.details_json or "steps" not in item.details_json:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Item has no steps defined",
        )
    
    step_ids = [s.get("id") for s in item.details_json["steps"]]
    if step_id not in step_ids:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Step {step_id} not found in item",
        )
    
    # Check current step completion status
    step_stmt = (
        select(PlanItemStepCompletion)
        .where(
            PlanItemStepCompletion.user_id == current_user.id,
            PlanItemStepCompletion.plan_item_id == item_id,
            PlanItemStepCompletion.step_id == step_id,
        )
    )
    result = await db.execute(step_stmt)
    step_completion = result.scalar_one_or_none()
    
    now = datetime.now(timezone.utc)
    
    if step_completion and step_completion.completed_at:
        # Currently complete -> uncomplete
        step_completion.completed_at = None
        new_step_completed = False
        
        # Auto-uncomplete the item
        item_completion_stmt = (
            select(PlanItemCompletion)
            .where(
                PlanItemCompletion.user_id == current_user.id,
                PlanItemCompletion.plan_item_id == item_id,
            )
        )
        item_result = await db.execute(item_completion_stmt)
        item_completion = item_result.scalar_one_or_none()
        if item_completion and item_completion.completed_at:
            item_completion.completed_at = None
    else:
        if step_completion:
            step_completion.completed_at = now
        else:
            step_completion = PlanItemStepCompletion(
                user_id=current_user.id,
                plan_item_id=item_id,
                step_id=step_id,
                completed_at=now,
            )
            db.add(step_completion)
        
        new_step_completed = True
    
    await db.commit()
    
    # Recompute progress and check if all steps are now complete
    progress, is_item_completed = await _compute_item_progress(db, current_user.id, item)
    
    # Auto-mark item complete if all steps done
    total_steps = len(item.details_json["steps"])
    if new_step_completed and progress.completed_steps == total_steps and not is_item_completed:
        item_completion_stmt = (
            select(PlanItemCompletion)
            .where(
                PlanItemCompletion.user_id == current_user.id,
                PlanItemCompletion.plan_item_id == item_id,
            )
        )
        item_result = await db.execute(item_completion_stmt)
        item_completion = item_result.scalar_one_or_none()
        
        if item_completion:
            item_completion.completed_at = now
        else:
            item_completion = PlanItemCompletion(
                user_id=current_user.id,
                plan_item_id=item_id,
                completed_at=now,
            )
            db.add(item_completion)
        
        await db.commit()
        is_item_completed = True
    
    return ToggleStepResponse(
        step_id=step_id,
        completed=new_step_completed,
        progress=progress,
        item_completed=is_item_completed,
    )


@items_router.post("/{item_id}/regenerate-details", response_model=RegenerateDetailsResponse)
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
    item = await _get_item_for_user(db, item_id, current_user.id)
    
    # Create job
    job = PlanItemDetailJob(
        plan_item_id=item_id,
        user_id=current_user.id,
        status="queued",
        step="loading_context",
        progress_percent=0,
    )
    db.add(job)
    await db.commit()
    
    # Import here to avoid circular imports
    from app.tasks.plans import regenerate_plan_item_details
    
    # Queue the regeneration task on high priority
    regenerate_plan_item_details.apply_async(args=[job.id], queue="high_priority")
    
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
    items_stmt = (
        select(PlanItem.id)
        .where(
            PlanItem.plan_id == plan_id,
            PlanItem.week_start <= week,
            PlanItem.week_end >= week,
        )
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
        .where(
            PlanItemCompletion.user_id == current_user.id,
            PlanItemCompletion.plan_item_id.in_(item_ids),
            PlanItemCompletion.completed_at.isnot(None),
        )
    )
    completed_result = await db.execute(completed_stmt)
    completed_items = completed_result.scalar() or 0
    
    percent = round((completed_items / total_items) * 100, 1) if total_items > 0 else 0.0
    
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


@router.post("/{plan_id}/generate-next", response_model=IdolImportResponse,
             status_code=status.HTTP_201_CREATED)
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
        await db.execute(
            select(UserAchievement.title).where(
                UserAchievement.user_id == current_user.id,
                UserAchievement.plan_id == plan_id,
            )
        )
    ).scalars().all()
    out = await cycle_summary(idol.name if idol else "your mentor", list(titles))
    return CycleSummaryResponse(**out)
