"""Progress computation helpers for plan items and weeks."""

import logging
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.item_detail_job import PlanItemDetailJob
from app.models.plan import (
    PlanItem,
    PlanItemCompletion,
    PlanItemStepCompletion,
)
from app.services.planning.artifact_identity import (
    artifact_job_reference_is_valid,
    current_artifact_job_id,
    current_item_completion_predicates,
    current_item_completion_query_predicates,
    current_step_completion_predicates,
    current_step_ids,
)

logger = logging.getLogger(__name__)

_ACTIVE_DETAIL_JOB_STATUSES = frozenset({"pending", "queued", "running"})


@dataclass
class ItemProgress:
    """Progress for a single plan item."""

    completed_steps: int
    total_steps: int
    percent: float
    is_completed: bool  # Item-level completion


@dataclass
class WeekProgress:
    """Progress for a week in a plan."""

    completed_items: int
    total_items: int
    percent: float


def _artifact_job_id(item: PlanItem) -> str | None:
    """Compatibility alias retained for callers/tests of the old helper."""

    return current_artifact_job_id(item)


async def compute_item_progress(
    db: AsyncSession,
    user_id: str,
    plan_item_id: str,
) -> ItemProgress:
    """
    Compute progress for a specific plan item.

    Args:
        db: Database session
        user_id: User ID
        plan_item_id: Plan item ID

    Returns:
        ItemProgress with completed_steps, total_steps, percent, and is_completed
    """
    # Hold the artifact owner row through latest-job and completion reads.
    # Otherwise a terminal B publication can land between an unlocked A read
    # and the latest-job query, producing B job state with A completion keys.
    item_stmt = (
        select(PlanItem)
        .where(PlanItem.id == plan_item_id)
        .execution_options(populate_existing=True)
        .with_for_update(of=PlanItem)
    )
    item_result = await db.execute(item_stmt)
    item = item_result.scalar_one_or_none()

    if not item:
        logger.warning(f"[PROGRESS] Plan item {plan_item_id} not found")
        return ItemProgress(
            completed_steps=0,
            total_steps=0,
            percent=0.0,
            is_completed=False,
        )

    if not await artifact_job_reference_is_valid(
        db,
        item.details_json,
        plan_item_id=str(item.id),
        user_id=str(user_id),
    ):
        return ItemProgress(
            completed_steps=0,
            total_steps=0,
            percent=0.0,
            is_completed=False,
        )

    latest_job_result = await db.execute(
        select(PlanItemDetailJob)
        .where(
            PlanItemDetailJob.plan_item_id == plan_item_id,
            PlanItemDetailJob.user_id == user_id,
        )
        .order_by(
            PlanItemDetailJob.artifact_epoch_at.desc(),
            PlanItemDetailJob.id.desc(),
        )
        .limit(1)
    )
    latest_job = latest_job_result.scalar_one_or_none()
    if (
        latest_job is not None
        and latest_job.status in _ACTIVE_DETAIL_JOB_STATUSES
        and str(latest_job.id) != _artifact_job_id(item)
    ):
        return ItemProgress(
            completed_steps=0,
            total_steps=0,
            percent=0.0,
            is_completed=False,
        )

    step_ids = current_step_ids(item)
    total_steps = len(step_ids)

    completed_stmt = (
        select(func.count())
        .select_from(PlanItemStepCompletion)
        .where(
            *current_step_completion_predicates(
                item,
                user_id=user_id,
                step_ids=step_ids,
            )
        )
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

    return ItemProgress(
        completed_steps=completed_steps,
        total_steps=total_steps,
        percent=percent,
        is_completed=is_completed,
    )


async def compute_week_progress(
    db: AsyncSession,
    user_id: str,
    plan_id: str,
    week: int,
) -> WeekProgress:
    """
    Compute progress for a specific week in a plan.

    Args:
        db: Database session
        user_id: User ID
        plan_id: Plan ID
        week: Week number (1-indexed)

    Returns:
        WeekProgress with completed_items, total_items, and percent
    """
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
        return WeekProgress(completed_items=0, total_items=0, percent=0.0)

    # Count completed items for this user
    completed_stmt = (
        select(func.count())
        .select_from(PlanItemCompletion)
        .join(PlanItem, PlanItemCompletion.plan_item_id == PlanItem.id)
        .where(
            *current_item_completion_query_predicates(
                user_id=user_id,
                item_ids=item_ids,
            )
        )
    )
    completed_result = await db.execute(completed_stmt)
    completed_items = completed_result.scalar() or 0

    # Calculate percent
    percent = (
        round((completed_items / total_items) * 100, 1) if total_items > 0 else 0.0
    )

    return WeekProgress(
        completed_items=completed_items,
        total_items=total_items,
        percent=percent,
    )


async def compute_plan_progress(
    db: AsyncSession,
    user_id: str,
    plan_id: str,
) -> WeekProgress:
    """
    Compute overall progress for an entire plan.

    Args:
        db: Database session
        user_id: User ID
        plan_id: Plan ID

    Returns:
        WeekProgress with completed_items, total_items, and percent for the whole plan
    """
    # Get all items for this plan
    items_stmt = (
        select(func.count()).select_from(PlanItem).where(PlanItem.plan_id == plan_id)
    )
    items_result = await db.execute(items_stmt)
    total_items = items_result.scalar() or 0

    if total_items == 0:
        return WeekProgress(completed_items=0, total_items=0, percent=0.0)

    # Count completed items for this user
    completed_stmt = (
        select(func.count())
        .select_from(PlanItemCompletion)
        .join(PlanItem, PlanItemCompletion.plan_item_id == PlanItem.id)
        .where(
            *current_item_completion_query_predicates(user_id=user_id),
            PlanItem.plan_id == plan_id,
        )
    )
    completed_result = await db.execute(completed_stmt)
    completed_items = completed_result.scalar() or 0

    # Calculate percent
    percent = round((completed_items / total_items) * 100, 1)

    return WeekProgress(
        completed_items=completed_items,
        total_items=total_items,
        percent=percent,
    )
