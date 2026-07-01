"""
Daily task completion endpoints for habits and practices.

LLM USAGE: NONE (database operations only)
"""
import logging
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import and_, distinct, select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Annotated

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.daily_task_completion import DailyTaskCompletion
from app.models.plan import Plan, PlanItem, PlanItemType
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter(tags=["daily-tasks"])


# =============================================================================
# Helpers
# =============================================================================

async def _get_item_for_user(
    db: AsyncSession,
    item_id: str,
    user_id: str,
) -> PlanItem:
    """Get a plan item, verifying ownership via the parent plan."""
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


def _validate_habit_or_practice(item: PlanItem) -> None:
    """Ensure the item is a habit or practice type."""
    if item.type not in (PlanItemType.HABIT, PlanItemType.PRACTICE):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Daily tracking is only available for habit and practice items",
        )


async def calculate_streak(db: AsyncSession, user_id: str) -> int:
    """
    Calculate the user's current consecutive-day streak.

    Counts consecutive days ending today (or yesterday if no completions today)
    where the user has at least one DailyTaskCompletion.
    """
    today = date.today()

    # Get all distinct completed dates for the user, ordered descending
    stmt = (
        select(distinct(DailyTaskCompletion.completed_date))
        .where(DailyTaskCompletion.user_id == user_id)
        .order_by(DailyTaskCompletion.completed_date.desc())
    )
    result = await db.execute(stmt)
    dates = [row[0] for row in result.fetchall()]

    if not dates:
        return 0

    # Streak must start from today or yesterday
    if dates[0] != today and dates[0] != today - timedelta(days=1):
        return 0

    streak = 0
    expected = dates[0]
    for d in dates:
        if d == expected:
            streak += 1
            expected -= timedelta(days=1)
        elif d < expected:
            # Gap found — stop counting
            break
        # d > expected shouldn't happen since we ordered desc

    return streak


def _get_current_plan_week(plan_created_at: datetime) -> int:
    """Determine which week (1-based) the user is currently in for a plan."""
    now = datetime.now(timezone.utc)
    days_diff = (now - plan_created_at).days
    return max(1, (days_diff // 7) + 1)


def _get_week_start_end(ref_date: date) -> tuple[date, date]:
    """Get Monday-Sunday for the week containing ref_date."""
    # Monday = 0, Sunday = 6
    weekday = ref_date.weekday()
    monday = ref_date - timedelta(days=weekday)
    sunday = monday + timedelta(days=6)
    return monday, sunday


# =============================================================================
# Schemas
# =============================================================================

class DailyToggleResponse(BaseModel):
    completed: bool
    date: str
    streak: int


class TodayItemResponse(BaseModel):
    id: str
    title: str
    type: str
    estimated_hours: int
    completed_today: bool
    daily_instructions: str | None = None


class TodayViewResponse(BaseModel):
    date: str
    items: list[TodayItemResponse]
    streak: int
    total_today: int
    completed_today: int


class DayDotResponse(BaseModel):
    date: str
    day_name: str
    completed: bool


class DailyStatusResponse(BaseModel):
    item_id: str
    week_start: str
    week_end: str
    days: list[DayDotResponse]
    completed_count: int
    total_days: int


class StreakResponse(BaseModel):
    current_streak: int
    longest_streak: int
    last_active_date: str | None = None


class DailyFocusItemResponse(BaseModel):
    id: str
    title: str
    type: str
    estimated_hours: int
    daily_instructions: str | None = None


class DailyFocusResponse(BaseModel):
    focus_item: DailyFocusItemResponse | None = None
    reflection_prompt: str | None = None
    streak: int


def _daily_instructions_for_item(item: PlanItem) -> str | None:
    """Return the daily script from plan metadata, falling back to detail metadata."""
    if item.meta_json and isinstance(item.meta_json, dict):
        value = item.meta_json.get("daily_instructions")
        if value:
            return str(value)

    if item.details_json and isinstance(item.details_json, dict):
        value = item.details_json.get("daily_instructions")
        if value:
            return str(value)

    return None


# =============================================================================
# Endpoints
# =============================================================================

@router.post(
    "/plan-items/{item_id}/daily-toggle",
    response_model=DailyToggleResponse,
)
async def toggle_daily_completion(
    item_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> DailyToggleResponse:
    """
    Toggle today's completion for a habit/practice plan item.

    If already completed today → removes the completion (uncheck).
    If not completed today → creates a completion (check).
    """
    item = await _get_item_for_user(db, item_id, current_user.id)
    _validate_habit_or_practice(item)

    today = date.today()

    # Check if already completed today
    stmt = (
        select(DailyTaskCompletion)
        .where(
            and_(
                DailyTaskCompletion.user_id == current_user.id,
                DailyTaskCompletion.plan_item_id == item_id,
                DailyTaskCompletion.completed_date == today,
            )
        )
    )
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()

    if existing:
        # Uncheck — delete the record
        await db.delete(existing)
        await db.commit()
        completed = False
    else:
        # Check — create a new record
        completion = DailyTaskCompletion(
            user_id=current_user.id,
            plan_item_id=item_id,
            completed_date=today,
        )
        db.add(completion)
        await db.commit()
        completed = True

    streak = await calculate_streak(db, current_user.id)

    return DailyToggleResponse(
        completed=completed,
        date=today.isoformat(),
        streak=streak,
    )


@router.get(
    "/plans/{plan_id}/today",
    response_model=TodayViewResponse,
)
async def get_today_view(
    plan_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> TodayViewResponse:
    """
    Get today's view of all habit/practice items for the current plan week.

    Returns each item with its completion status for today, plus overall
    streak and completion counts.
    """
    # Verify plan ownership and get the plan
    plan_stmt = (
        select(Plan)
        .where(
            and_(
                Plan.id == plan_id,
                Plan.user_id == current_user.id,
            )
        )
    )
    plan_result = await db.execute(plan_stmt)
    plan = plan_result.scalar_one_or_none()

    if not plan:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Plan not found",
        )

    # Determine current week
    current_week = _get_current_plan_week(plan.created_at)
    today = date.today()

    # Get all habit/practice items for the current week
    items_stmt = (
        select(PlanItem)
        .where(
            and_(
                PlanItem.plan_id == plan_id,
                PlanItem.type.in_([PlanItemType.HABIT, PlanItemType.PRACTICE]),
                PlanItem.week_start <= current_week,
                PlanItem.week_end >= current_week,
            )
        )
    )
    items_result = await db.execute(items_stmt)
    items = list(items_result.scalars().all())

    # Get all completions for today for these items
    item_ids = [item.id for item in items]
    completed_today_set: set[str] = set()

    if item_ids:
        completions_stmt = (
            select(DailyTaskCompletion.plan_item_id)
            .where(
                and_(
                    DailyTaskCompletion.user_id == current_user.id,
                    DailyTaskCompletion.plan_item_id.in_(item_ids),
                    DailyTaskCompletion.completed_date == today,
                )
            )
        )
        completions_result = await db.execute(completions_stmt)
        completed_today_set = {row[0] for row in completions_result.fetchall()}

    # Build response items
    response_items = []
    for item in items:
        daily_instructions = _daily_instructions_for_item(item)

        response_items.append(
            TodayItemResponse(
                id=item.id,
                title=item.title,
                type=item.type.value,
                estimated_hours=item.estimated_hours,
                completed_today=item.id in completed_today_set,
                daily_instructions=daily_instructions,
            )
        )

    total_today = len(response_items)
    completed_count = sum(1 for i in response_items if i.completed_today)
    streak = await calculate_streak(db, current_user.id)

    return TodayViewResponse(
        date=today.isoformat(),
        items=response_items,
        streak=streak,
        total_today=total_today,
        completed_today=completed_count,
    )


@router.get(
    "/plan-items/{item_id}/daily-status",
    response_model=DailyStatusResponse,
)
async def get_daily_status(
    item_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> DailyStatusResponse:
    """
    Get the 7-day dot grid (Mon-Sun) for a habit/practice item.

    Returns completion status for each day of the current week.
    """
    item = await _get_item_for_user(db, item_id, current_user.id)
    _validate_habit_or_practice(item)

    today = date.today()
    week_start, week_end = _get_week_start_end(today)

    # Get completions for this item within the current week
    stmt = (
        select(DailyTaskCompletion.completed_date)
        .where(
            and_(
                DailyTaskCompletion.user_id == current_user.id,
                DailyTaskCompletion.plan_item_id == item_id,
                DailyTaskCompletion.completed_date >= week_start,
                DailyTaskCompletion.completed_date <= week_end,
            )
        )
    )
    result = await db.execute(stmt)
    completed_dates = {row[0] for row in result.fetchall()}

    # Build the 7-day grid
    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    days = []
    completed_count = 0

    for i in range(7):
        day = week_start + timedelta(days=i)
        is_completed = day in completed_dates
        if is_completed:
            completed_count += 1
        days.append(
            DayDotResponse(
                date=day.isoformat(),
                day_name=day_names[i],
                completed=is_completed,
            )
        )

    return DailyStatusResponse(
        item_id=item_id,
        week_start=week_start.isoformat(),
        week_end=week_end.isoformat(),
        days=days,
        completed_count=completed_count,
        total_days=7,
    )


@router.get("/streak", response_model=StreakResponse)
async def get_streak(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> StreakResponse:
    """Get the user's current and longest daily streak."""
    # ⚡ Bolt Optimization: Fetch distinct dates once to calculate all streak stats
    # in memory, saving 2 database queries
    dates_stmt = (
        select(distinct(DailyTaskCompletion.completed_date))
        .where(DailyTaskCompletion.user_id == current_user.id)
        .order_by(DailyTaskCompletion.completed_date.desc())
    )
    dates_result = await db.execute(dates_stmt)
    all_dates = [row[0] for row in dates_result.fetchall()]

    if not all_dates:
        return StreakResponse(
            current_streak=0,
            longest_streak=0,
            last_active_date=None,
        )

    # Calculate current streak
    today = date.today()
    current = 0
    if all_dates[0] == today or all_dates[0] == today - timedelta(days=1):
        expected = all_dates[0]
        for d in all_dates:
            if d == expected:
                current += 1
                expected -= timedelta(days=1)
            elif d < expected:
                break

    # Calculate longest streak
    longest = 1
    current_run = 1
    for i in range(1, len(all_dates)):
        # all_dates is ordered descending, so the previous day is all_dates[i - 1] - 1 day
        if all_dates[i] == all_dates[i - 1] - timedelta(days=1):
            current_run += 1
            longest = max(longest, current_run)
        else:
            current_run = 1

    return StreakResponse(
        current_streak=current,
        longest_streak=longest,
        last_active_date=all_dates[0].isoformat(),
    )


@router.get("/daily-focus", response_model=DailyFocusResponse)
async def get_daily_focus(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> DailyFocusResponse:
    """Get today's primary focus item, a reflection prompt, and current streak."""
    streak = await calculate_streak(db, current_user.id)

    # Find the user's most recent plan
    plan_stmt = (
        select(Plan)
        .where(Plan.user_id == current_user.id)
        .order_by(Plan.created_at.desc())
        .limit(1)
    )
    plan_result = await db.execute(plan_stmt)
    plan = plan_result.scalar_one_or_none()

    focus_item = None
    if plan:
        current_week = _get_current_plan_week(plan.created_at)
        today = date.today()

        # Get habit/practice items for the current week that aren't completed today
        items_stmt = (
            select(PlanItem)
            .where(
                and_(
                    PlanItem.plan_id == plan.id,
                    PlanItem.type.in_([PlanItemType.HABIT, PlanItemType.PRACTICE]),
                    PlanItem.week_start <= current_week,
                    PlanItem.week_end >= current_week,
                )
            )
            .order_by(PlanItem.week_start.asc())
        )
        items_result = await db.execute(items_stmt)
        items = list(items_result.scalars().all())

        # Find the first item not completed today
        completed_ids: set[str] = set()
        item_ids = [item.id for item in items]
        if item_ids:
            comp_stmt = (
                select(DailyTaskCompletion.plan_item_id)
                .where(
                    and_(
                        DailyTaskCompletion.user_id == current_user.id,
                        DailyTaskCompletion.plan_item_id.in_(item_ids),
                        DailyTaskCompletion.completed_date == today,
                    )
                )
            )
            comp_result = await db.execute(comp_stmt)
            completed_ids = {row[0] for row in comp_result.fetchall()}

        for item in items:
            if item.id not in completed_ids:
                daily_instructions = _daily_instructions_for_item(item)
                focus_item = DailyFocusItemResponse(
                    id=item.id,
                    title=item.title,
                    type=item.type.value,
                    estimated_hours=item.estimated_hours,
                    daily_instructions=daily_instructions,
                )
                break

    # Generate a reflection prompt based on streak
    reflection_prompts = [
        "What would your idol refuse to optimize today?",
        "What's one thing you can do in 15 minutes that moves you closer to your goal?",
        "Which of your habits is hardest to maintain, and why?",
        "What did you learn this week that surprised you?",
        "If your idol were reviewing your progress, what would they focus on?",
        "What's the smallest action you can take today to build momentum?",
        "What assumption are you making that your idol would question?",
    ]
    prompt_index = date.today().timetuple().tm_yday % len(reflection_prompts)
    reflection_prompt = reflection_prompts[prompt_index]

    return DailyFocusResponse(
        focus_item=focus_item,
        reflection_prompt=reflection_prompt,
        streak=streak,
    )
