"""Progress computation helpers for plan items and weeks."""
import logging
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.plan import (
    PlanItem,
    PlanItemCompletion,
    PlanItemStepCompletion,
)

logger = logging.getLogger(__name__)


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
    # Get the plan item with details
    item_stmt = select(PlanItem).where(PlanItem.id == plan_item_id)
    item_result = await db.execute(item_stmt)
    item = item_result.scalar_one_or_none()
    
    if not item:
        logger.warning(f"[PROGRESS] Plan item {plan_item_id} not found")
        return ItemProgress(completed_steps=0, total_steps=0, percent=0.0, is_completed=False)
    
    # Get total steps from details_json
    total_steps = 0
    if item.details_json and "steps" in item.details_json:
        total_steps = len(item.details_json["steps"])
    
    # Count completed steps for this user
    completed_stmt = (
        select(func.count())
        .select_from(PlanItemStepCompletion)
        .where(
            PlanItemStepCompletion.user_id == user_id,
            PlanItemStepCompletion.plan_item_id == plan_item_id,
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
            PlanItemCompletion.plan_item_id == plan_item_id,
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
        return WeekProgress(completed_items=0, total_items=0, percent=0.0)
    
    # Count completed items for this user
    completed_stmt = (
        select(func.count())
        .select_from(PlanItemCompletion)
        .where(
            PlanItemCompletion.user_id == user_id,
            PlanItemCompletion.plan_item_id.in_(item_ids),
            PlanItemCompletion.completed_at.isnot(None),
        )
    )
    completed_result = await db.execute(completed_stmt)
    completed_items = completed_result.scalar() or 0
    
    # Calculate percent
    percent = round((completed_items / total_items) * 100, 1) if total_items > 0 else 0.0
    
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
        select(func.count())
        .select_from(PlanItem)
        .where(PlanItem.plan_id == plan_id)
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
            PlanItemCompletion.user_id == user_id,
            PlanItem.plan_id == plan_id,
            PlanItemCompletion.completed_at.isnot(None),
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
