"""
Daily task completion endpoints for habits and practices.

LLM USAGE: NONE (database operations only)
"""

import logging
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import and_, distinct, select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Annotated

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.daily_task_completion import DailyTaskCompletion
from app.models.plan import Plan, PlanItem, PlanItemCompletion, PlanItemType
from app.services.planning.capacity import plan_item_minutes
from app.services.planning.habit_schedule import (
    DEFAULT_DAYS,
    learning_today,
    practice_instructions,
    schedule_for,
    scheduled_streak,
    uses_checked_review,
)
from app.services.planning.artifact_identity import (
    current_item_completion_query_predicates,
)
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter(tags=["daily-tasks"])

MISSION_TYPES = {PlanItemType.PROJECT, PlanItemType.COURSE, PlanItemType.READING}
DAILY_TYPES = {PlanItemType.HABIT, PlanItemType.PRACTICE}


# =============================================================================
# Helpers
# =============================================================================


async def _get_item_for_user(
    db: AsyncSession,
    item_id: str,
    user_id: str,
    *,
    lock: bool = False,
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
    if lock:
        stmt = stmt.with_for_update(of=PlanItem)
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


async def _streak_snapshot(db: AsyncSession, user_id: str) -> dict:
    plan = (
        await db.execute(
            select(Plan)
            .where(Plan.user_id == user_id)
            .order_by(Plan.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if plan is None:
        return {
            "current_streak": 0,
            "longest_streak": 0,
            "last_active_date": None,
            "days": [],
            "total_practice_days": 0,
        }
    rows = await db.execute(
        select(distinct(DailyTaskCompletion.completed_date))
        .join(PlanItem, PlanItem.id == DailyTaskCompletion.plan_item_id)
        .where(DailyTaskCompletion.user_id == user_id, PlanItem.plan_id == plan.id)
    )
    dates = {row[0] for row in rows.fetchall()}
    today = learning_today()
    history = (plan.roadmap_json or {}).get("habit_schedule_history") or []
    current, longest = scheduled_streak(dates, set(DEFAULT_DAYS), today, history)
    monday, _ = _get_week_start_end(today)
    days = []
    for i in range(7):
        day = monday + timedelta(days=i)
        weekdays = next(
            (h["weekdays"] for h in reversed(history) if h["from"] <= day.isoformat()),
            DEFAULT_DAYS,
        )
        days.append(
            {
                "date": day.isoformat(),
                "completed": day in dates,
                "scheduled": day.weekday() in weekdays,
            }
        )
    return {
        "current_streak": current,
        "longest_streak": longest,
        "last_active_date": max(dates).isoformat() if dates else None,
        "days": days,
        "total_practice_days": len(dates),
    }


async def calculate_streak(db: AsyncSession, user_id: str) -> int:
    return (await _streak_snapshot(db, user_id))["current_streak"]


def _get_current_plan_week(plan_created_at: datetime) -> int:
    """Determine which week (1-based) the user is currently in for a plan."""
    now = datetime.now(timezone.utc)
    days_diff = (now - plan_created_at).days
    return max(1, (days_diff // 7) + 1)


def _execution_focus_week(
    items: list[PlanItem],
    completed_item_ids: set[str],
    duration_weeks: int,
) -> int:
    """Return the first week with unfinished mission work.

    CMPYS advances by execution, not by time elapsed since plan creation.
    Daily rhythms never gate progression. Once every mission is complete, the
    final week remains the active daily-rhythm context for the cycle recap.
    """
    incomplete_weeks = [
        item.week_start
        for item in items
        if item.type in MISSION_TYPES and str(item.id) not in completed_item_ids
    ]
    if incomplete_weeks:
        return min(max(1, min(incomplete_weeks)), max(1, duration_weeks))

    has_missions = any(item.type in MISSION_TYPES for item in items)
    return max(1, duration_weeks) if has_missions else 1


async def _items_and_execution_week(
    db: AsyncSession,
    *,
    plan: Plan,
    user_id: str,
) -> tuple[list[PlanItem], int]:
    items_result = await db.execute(select(PlanItem).where(PlanItem.plan_id == plan.id))
    items = list(items_result.scalars().all())
    mission_ids = [str(item.id) for item in items if item.type in MISSION_TYPES]
    completed_item_ids: set[str] = set()
    if mission_ids:
        completion_result = await db.execute(
            select(PlanItemCompletion.plan_item_id)
            .join(PlanItem, PlanItemCompletion.plan_item_id == PlanItem.id)
            .where(
                *current_item_completion_query_predicates(
                    user_id=user_id,
                    item_ids=mission_ids,
                )
            )
        )
        completed_item_ids = {
            str(item_id) for item_id in completion_result.scalars().all()
        }
    return items, _execution_focus_week(
        items,
        completed_item_ids,
        plan.duration_weeks,
    )


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
    requires_review: bool = True
    review_available: bool = False
    review_message: str | None = None
    id: str
    title: str
    type: str
    estimated_hours: int
    # Exact weekly minutes (a 15-minute short-week rhythm); hours round up.
    estimated_minutes: int | None = None
    # Minutes of one practice session: the weekly minutes over the rhythm's
    # sessions per week (rhythm_cadence). Optional for older readers.
    session_minutes: int | None = None
    completed_today: bool
    daily_instructions: str | None = None
    schedule: dict | None = None
    scheduled_today: bool = True


class TodayViewResponse(BaseModel):
    date: str
    items: list[TodayItemResponse]
    streak: int
    total_today: int
    completed_today: int


class DayDotResponse(BaseModel):
    scheduled: bool = True
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
    total_practice_days: int = 0
    days: list[dict] = Field(default_factory=list)
    current_streak: int
    longest_streak: int
    last_active_date: str | None = None


class DailyFocusItemResponse(BaseModel):
    id: str
    title: str
    type: str
    estimated_hours: int
    estimated_minutes: int | None = None
    session_minutes: int | None = None
    daily_instructions: str | None = None


class DailyFocusResponse(BaseModel):
    focus_item: DailyFocusItemResponse | None = None
    reflection_prompt: str | None = None
    streak: int


class PracticeScheduleRequest(BaseModel):
    weekdays: list[int] = Field(min_length=1, max_length=7)
    cue: str = Field(default="", max_length=200)

    @field_validator("weekdays")
    @classmethod
    def valid_days(cls, days):
        if len(set(days)) != len(days) or any(d not in range(7) for d in days):
            raise ValueError("Choose distinct weekdays from Monday (0) to Sunday (6)")
        return sorted(days)


@router.put("/plan-items/{item_id}/practice-schedule")
async def update_practice_schedule(
    item_id: str,
    data: PracticeScheduleRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    # Lock the parent first for all schedule edits, then its habits in ID order.
    plan = (
        await db.execute(
            select(Plan)
            .join(PlanItem, PlanItem.plan_id == Plan.id)
            .where(PlanItem.id == item_id, Plan.user_id == current_user.id)
            .with_for_update(of=Plan)
        )
    ).scalar_one_or_none()
    if plan is None:
        raise HTTPException(404, "Plan item not found")
    items = list(
        (
            await db.execute(
                select(PlanItem)
                .where(PlanItem.plan_id == plan.id, PlanItem.type.in_(DAILY_TYPES))
                .order_by(PlanItem.id)
                .with_for_update()
            )
        )
        .scalars()
        .all()
    )
    if not any(str(item.id) == item_id for item in items):
        raise HTTPException(422, "Schedules belong to practice routines")
    if any(plan_item_minutes(item) < len(data.weekdays) for item in items):
        raise HTTPException(
            422, "Choose fewer days so each session has at least one minute"
        )
    today = learning_today()
    # Keep the current week's allocation intact. Changing a 3×20 schedule
    # to 2×30 midweek could otherwise add 30 minutes after 20 were spent.
    effective = (today + timedelta(days=7 - today.weekday())).isoformat()
    change = {"from": effective, "weekdays": data.weekdays, "cue": data.cue.strip()}
    history = [
        h
        for h in (plan.roadmap_json or {}).get("habit_schedule_history", [])
        if h["from"] < effective
    ]
    history.append(change)
    plan.roadmap_json = {**(plan.roadmap_json or {}), "habit_schedule_history": history}
    for item in items:
        item.meta_json = {**(item.meta_json or {}), "habit_schedule_history": history}
    await db.commit()
    return {
        "effective_from": effective,
        "weekdays": data.weekdays,
        "cue": data.cue.strip(),
    }


def _session_minutes(item: PlanItem) -> int:
    return schedule_for(item)["session_minutes"]


def _daily_instructions_for_item(item: PlanItem) -> str | None:
    """Old saved prose cannot promise missing datasets or a conflicting timer."""
    if not uses_checked_review(item):
        return (item.meta_json or {}).get("daily_instructions") or (
            item.details_json or {}
        ).get("daily_instructions")
    return practice_instructions(item)


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
    item = await _get_item_for_user(db, item_id, current_user.id, lock=True)
    _validate_habit_or_practice(item)

    today = learning_today()

    # Check if already completed today
    stmt = select(DailyTaskCompletion).where(
        and_(
            DailyTaskCompletion.user_id == current_user.id,
            DailyTaskCompletion.plan_item_id == item_id,
            DailyTaskCompletion.completed_date == today,
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
        if uses_checked_review(item):
            # Participation requires a real attempt, not a timer or a checkbox.
            from app.services.practice.habit_review import load_review, session_key

            _, _, review, _ = await load_review(
                db, item, str(current_user.id), session_key(today)
            )
            if review is None or not review.attempts_json:
                raise HTTPException(
                    409, "Try and check a review exercise before logging this session."
                )
            last = review.attempts_json[-1]
            reflection = ((item.meta_json or {}).get("daily_reflections") or {}).get(
                today.isoformat(), ""
            )
            if not last.get("passed") and len(reflection.strip()) < 10:
                raise HTTPException(
                    409,
                    "Correct your answer or save a note explaining the correction before logging this session.",
                )
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

    # Determine the active execution week from completed missions. Calendar
    # age is deliberately irrelevant: Week 2 unlocks immediately after Week 1
    # is finished, and an older plan does not lose its current daily rhythm.
    plan_items, current_week = await _items_and_execution_week(
        db,
        plan=plan,
        user_id=current_user.id,
    )
    today = learning_today()

    items = [
        item
        for item in plan_items
        if item.type in DAILY_TYPES and item.week_start <= current_week <= item.week_end
    ]

    # Get all completions for today for these items
    item_ids = [item.id for item in items]
    completed_today_set: set[str] = set()

    if item_ids:
        completions_stmt = select(DailyTaskCompletion.plan_item_id).where(
            and_(
                DailyTaskCompletion.user_id == current_user.id,
                DailyTaskCompletion.plan_item_id.in_(item_ids),
                DailyTaskCompletion.completed_date == today,
            )
        )
        completions_result = await db.execute(completions_stmt)
        completed_today_set = {row[0] for row in completions_result.fetchall()}

    # Build response items
    response_items = []
    for item in items:
        daily_instructions = _daily_instructions_for_item(item)
        from app.services.practice.habit_review import review_status

        checked = uses_checked_review(item)
        review = (
            await review_status(db, item, str(current_user.id), on=today)
            if checked
            else {"available": True}
        )

        response_items.append(
            TodayItemResponse(
                id=item.id,
                title=item.title,
                type=item.type.value,
                estimated_hours=item.estimated_hours,
                estimated_minutes=plan_item_minutes(item),
                session_minutes=_session_minutes(item),
                completed_today=item.id in completed_today_set,
                daily_instructions=daily_instructions,
                schedule=schedule_for(item, today),
                scheduled_today=schedule_for(item, today)["scheduled_today"],
                requires_review=checked,
                review_available=bool(
                    review["available"] or item.id in completed_today_set
                ),
                review_message=review.get("message"),
            )
        )

    total_today = sum(i.scheduled_today and i.review_available for i in response_items)
    completed_count = sum(
        1
        for i in response_items
        if i.completed_today and i.scheduled_today and i.review_available
    )
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

    today = learning_today()
    week_start, week_end = _get_week_start_end(today)

    # Get completions for this item within the current week
    stmt = select(DailyTaskCompletion.completed_date).where(
        and_(
            DailyTaskCompletion.user_id == current_user.id,
            DailyTaskCompletion.plan_item_id == item_id,
            DailyTaskCompletion.completed_date >= week_start,
            DailyTaskCompletion.completed_date <= week_end,
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
        if is_completed and day.weekday() in schedule_for(item, day)["weekdays"]:
            completed_count += 1
        days.append(
            DayDotResponse(
                date=day.isoformat(),
                day_name=day_names[i],
                completed=is_completed,
                scheduled=day.weekday() in schedule_for(item, day)["weekdays"],
            )
        )

    return DailyStatusResponse(
        item_id=item_id,
        week_start=week_start.isoformat(),
        week_end=week_end.isoformat(),
        days=days,
        completed_count=completed_count,
        total_days=len(schedule_for(item, today)["weekdays"]),
    )


@router.get("/streak", response_model=StreakResponse)
async def get_streak(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> StreakResponse:
    """Practice-day streak; scheduled rest days never reset it."""
    return StreakResponse(**await _streak_snapshot(db, str(current_user.id)))


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
        plan_items, current_week = await _items_and_execution_week(
            db,
            plan=plan,
            user_id=current_user.id,
        )
        today = learning_today()

        # Get habit/practice items for the current week that aren't completed today
        items = sorted(
            (
                item
                for item in plan_items
                if item.type in DAILY_TYPES
                and item.week_start <= current_week <= item.week_end
            ),
            key=lambda item: item.week_start,
        )

        # Find the first item not completed today
        completed_ids: set[str] = set()
        item_ids = [item.id for item in items]
        if item_ids:
            comp_stmt = select(DailyTaskCompletion.plan_item_id).where(
                and_(
                    DailyTaskCompletion.user_id == current_user.id,
                    DailyTaskCompletion.plan_item_id.in_(item_ids),
                    DailyTaskCompletion.completed_date == today,
                )
            )
            comp_result = await db.execute(comp_stmt)
            completed_ids = {row[0] for row in comp_result.fetchall()}

        for item in items:
            if (
                item.id not in completed_ids
                and schedule_for(item, today)["scheduled_today"]
            ):
                if uses_checked_review(item):
                    from app.services.practice.habit_review import review_status

                    review = await review_status(
                        db, item, str(current_user.id), on=today
                    )
                    if not review["available"]:
                        continue
                daily_instructions = _daily_instructions_for_item(item)
                focus_item = DailyFocusItemResponse(
                    id=item.id,
                    title=item.title,
                    type=item.type.value,
                    estimated_hours=item.estimated_hours,
                    estimated_minutes=plan_item_minutes(item),
                    session_minutes=_session_minutes(item),
                    daily_instructions=daily_instructions,
                )
                break

    # Generate a reflection prompt based on streak
    reflection_prompts = [
        "Which rule did you recall before checking the lesson?",
        "What did you get wrong, and what is the corrected rule?",
        "What clue will help you choose the right method next time?",
    ]
    prompt_index = learning_today().timetuple().tm_yday % len(reflection_prompts)
    reflection_prompt = reflection_prompts[prompt_index]

    return DailyFocusResponse(
        focus_item=focus_item,
        reflection_prompt=reflection_prompt,
        streak=streak,
    )
