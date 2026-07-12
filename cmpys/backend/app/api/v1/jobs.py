from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload, selectinload

from app.core.db import get_db
from app.models.idol_job import IdolImportJob
from app.models.plan_job import PlanGenerationJob
from app.models.item_detail_job import PlanItemDetailJob
from app.models.suggest_job import IdolSuggestJob
from app.models.idol_profile import IdolProfile
from app.models.idol_timeline import IdolTimelineEvent
from app.models.plan import Plan, PlanItem

router = APIRouter(prefix="/jobs", tags=["jobs"])


# =============================================================================
# AI Thinking Stream - Dynamic typewriter-style text for processing
# =============================================================================

# Thinking narratives - multiple sentences that appear progressively
THINKING_NARRATIVES = {
    "queued": [
        "Let me look into {idol_name} for you...",
        "I'm preparing to research their life and achievements.",
        "This should take about a minute.",
    ],
    "collecting_sources": [
        "Searching for reliable sources about {idol_name}...",
        "Checking source sections for dates, roles, and early domain signals.",
        "Collecting cited milestones that can support age-matched comparison.",
        "Separating concrete events from vague reputation claims.",
        "Saving source-backed details for the comparison and mentor persona.",
    ],
    "extracting_profile": [
        "Now I'm piecing together {idol_name}'s profile...",
        "Let me figure out their birth date and background...",
        "Interesting... I'm seeing their main areas of expertise.",
        "They seem to have focused on {domain_hint}.",
        "Building a picture of who they are...",
        "Got the basics down. Moving on to the good stuff.",
    ],
    "extracting_achievements": [
        "Extracting dated achievements, publications, roles, launches, and awards.",
        "Keeping milestones only when they are concrete enough to compare.",
        "Looking for repeatable methods behind the achievement, not just the headline.",
        "Tagging milestones that can become lessons, habits, or practice tasks.",
    ],
    "normalizing_timeline": [
        "Now let me organize everything chronologically...",
        "Calculating how old they were at each milestone...",
        "This helps us compare your journey to theirs.",
        "Some achievements happened surprisingly early...",
        "Others took years of preparation.",
        "Building a clear timeline of their path.",
    ],
    "generating_persona": [
        "Final step - understanding how {idol_name} thinks...",
        "Analyzing their communication style...",
        "What principles guided their decisions?",
        "I'm preparing so you can have conversations with them.",
        "Learning their perspective on success...",
        "Almost ready for you to meet them.",
    ],
    "storing_data": [
        "Saving everything I learned...",
        "Just a few more seconds...",
        "{idol_name} is almost ready!",
    ],
    "done": [
        "All done! {idol_name} has been fully imported.",
        "You can now explore their timeline and compare achievements.",
        "Ready when you are!",
    ],
    "error": [
        "Hmm, something went wrong...",
        "I couldn't complete the research.",
        "You might want to try again.",
    ],
    # Plan generation narratives
    "analyzing_gaps": [
        "Comparing your current profile with {idol_name}'s age-matched milestones...",
        "Identifying domain gaps that can become specific weekly missions.",
        "Prioritizing the gaps that should drive today, week one, and the 12-week plan.",
    ],
    "structuring_curriculum": [
        "Translating the mentor verdict into a 12-week execution path.",
        "Balancing major missions with daily rhythm tasks you can actually complete.",
        "Selecting resources and practice loops tied to the idol's real domain.",
    ],
    "balancing_workload": [
        "Fitting these goals into your {weekly_hours}h weekly schedule...",
        "Making sure the plan is realistic but challenging...",
        "Prioritizing foundational steps for the early weeks...",
    ],
    "finalizing_plan": [
        "Polishing your personalized {duration_weeks}-week curriculum...",
        "Adding success metrics for each milestone...",
        "Synthesizing {idol_name}'s principles into actionable tasks...",
        "Your path to success is almost ready!",
    ],
    # Idol Suggestion narratives
    "analyzing_interests": [
        "Analyzing your profile & interests...",
        "Looking for common traits among your hobbies...",
        "Mapping your {interests} to potential figures...",
    ],
    "querying_knowledge_base": [
        "Querying my AI knowledge base for matches...",
        "Scanning thousands of notable figures...",
        "Looking for people who shared your passion for {interests}...",
    ],
    "filtering_matches": [
        "Filtering results to find the most inspiring matches...",
        "Verifying their background and achievements...",
        "Selecting the top recommendations for you...",
    ],
    # Plan Item Detail narratives
    "loading_context": [
        "Loading your goals, current week, and plan metadata.",
        "Connecting {task_title} back to {idol_name}'s domain and methods.",
        "Preparing lessons, materials, and completion criteria for this task.",
    ],
    "generating_curriculum": [
        "Writing teach-first steps with examples, practice, and reflection.",
        "Selecting resources that connect directly to this week's mission.",
        "Checking that each step has a concrete definition of done.",
    ],
    "finalizing_steps": [
        "Finalizing your personalized tasks...",
        "Polishing the instructions and success metrics...",
        "Almost ready to show you the details!",
    ],
}

# Contextual insights based on what we're discovering
DISCOVERY_INSIGHTS = {
    "collecting_sources": [
        "Did you know most Wikipedia articles have 50+ citations?",
        "I cross-reference multiple sections for accuracy.",
        "The 'Early life' section often has the best insights.",
    ],
    "extracting_profile": [
        "Birth dates help me calculate achievement ages precisely.",
        "Understanding their domain helps filter relevant milestones.",
        "Background context makes achievements more meaningful.",
    ],
    "extracting_achievements": [
        "I look for actions, not just descriptions.",
        "Dates are crucial - they show the timeline of growth.",
        "Some achievements lead to others - I track these patterns.",
        "Real milestones are things you could replicate.",
    ],
    "normalizing_timeline": [
        "Age at achievement tells you what's realistic.",
        "Early wins often enabled later successes.",
        "Gaps in timelines can be as informative as peaks.",
    ],
    "generating_persona": [
        "Their words reveal their thinking patterns.",
        "Principles are more valuable than specific advice.",
        "I try to capture what made them unique.",
    ],
    "analyzing_gaps": [
        "Most successful people follow similar growth trajectories.",
        "Focusing on gaps helps us prioritize what matters most.",
    ],
    "structuring_curriculum": [
        "Consistent habits often outperform one-off projects.",
        "We prioritize skills that {idol_name} leveraged most.",
    ],
}


def get_thinking_stream(
    step: str | None, 
    idol_name: str, 
    progress: int,
    domains: list[str] | None = None,
    weekly_hours: float | None = None,
    duration_weeks: int | None = None,
    interests: str | None = None,
    task_title: str | None = None,
) -> dict:
    """
    Generate a stream of thinking text for typewriter effect.
    
    Returns multiple text segments that frontend can animate progressively.
    """
    step = step or "queued"
    narratives = THINKING_NARRATIVES.get(step, THINKING_NARRATIVES["queued"])
    insights = DISCOVERY_INSIGHTS.get(step, [])
    
    # Domain hint for profile extraction
    domain_hint = domains[0] if domains else "their field"
    
    # Calculate which narrative lines to show based on progress within step
    # Each step spans roughly 15-20% progress, so we show more lines as progress increases
    step_progress_map = {
        # Import steps
        "queued": (0, 5),
        "collecting_sources": (5, 20),
        "extracting_profile": (20, 35),
        "extracting_achievements": (35, 55),
        "normalizing_timeline": (55, 70),
        "generating_persona": (70, 85),
        "storing_data": (85, 95),
        "done": (95, 100),
        # Plan steps
        "finalizing_plan": (85, 100),
        # Idol Suggestion steps
        "analyzing_interests": (0, 30),
        "querying_knowledge_base": (30, 70),
        "filtering_matches": (70, 100),
        # Plan Item Detail steps
        "loading_context": (0, 30),
        "generating_curriculum": (30, 70),
        "finalizing_steps": (70, 100),
    }
    
    start, end = step_progress_map.get(step, (0, 100))
    step_duration = end - start
    progress_in_step = max(0, min(progress - start, step_duration))
    
    # Calculate how many narrative lines to show (progressively reveal more)
    if step_duration > 0:
        ratio = progress_in_step / step_duration
    else:
        ratio = 1.0
    
    num_lines = max(1, int(len(narratives) * ratio) + 1)
    num_lines = min(num_lines, len(narratives))
    
    # Get the lines to display
    lines_to_show = narratives[:num_lines]
    
    # Format with idol name, domain, etc.
    formatted_lines = [
        line.format(
            idol_name=idol_name, 
            domain_hint=domain_hint,
            weekly_hours=weekly_hours or 10,
            duration_weeks=duration_weeks or 12,
            interests=interests or "your interests",
            task_title=task_title or "this task",
        )
        for line in lines_to_show
    ]
    
    # Pick an insight if we have any
    current_insight = None
    if insights and progress > start + 5:
        insight_idx = (progress // 7) % len(insights)
        current_insight = insights[insight_idx]
    
    # Current line (the latest one being "typed")
    current_line = formatted_lines[-1] if formatted_lines else ""
    
    # Completed lines (already shown)
    completed_lines = formatted_lines[:-1] if len(formatted_lines) > 1 else []
    
    return {
        "currentLine": current_line,
        "completedLines": completed_lines,
        "insight": current_insight,
        "step": step,
        "stepProgress": int(ratio * 100),
    }


class ThinkingStream(BaseModel):
    """
    AI thinking stream for typewriter effect.
    
    Frontend should:
    1. Display completedLines immediately
    2. Animate currentLine with typewriter effect
    3. Show insight as a subtle aside
    """
    currentLine: str
    completedLines: list[str] = []
    insight: str | None = None
    step: str
    stepProgress: int  # 0-100 within current step


class ThinkingText(BaseModel):
    """AI thinking text shown during processing (legacy format)."""
    message: str
    funFact: str | None = None
    step: str


class JobStatusResponse(BaseModel):
    id: str
    idolId: str | None
    idolName: str | None = None
    status: str
    step: str | None
    progressPercent: int
    errorMessage: str | None = None
    # New streaming thinking text (for typewriter effect)
    thinkingStream: ThinkingStream | None = None
    # Legacy format (kept for backward compatibility)
    thinkingText: ThinkingText | None = None
    # Preview data (populated as we extract)
    previewAchievements: list[str] | None = None
    previewDomains: list[str] | None = None
    # Final results (e.g., idol suggestions)
    results: dict | None = None

    model_config = {"from_attributes": True}


@router.get("/{job_id}", response_model=JobStatusResponse)
async def get_job_status(
    job_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    job_type: Annotated[
        Literal["import", "plan", "plan_detail", "suggest"] | None,
        Query(alias="type"),
    ] = None,
) -> JobStatusResponse:
    """
    Get the current status of an import job.
    
    Returns dynamic "AI thinking" text that changes based on the current step
    and progress, providing an engaging experience while waiting.
    """
    # Existing clients can omit ``type`` and retain the legacy probing order.
    # Callers that know the job kind avoid up to three guaranteed-miss queries
    # on every polling tick.
    job = None
    if job_type in (None, "import"):
        stmt = (
            select(IdolImportJob)
            .options(joinedload(IdolImportJob.idol))
            .where(IdolImportJob.id == job_id)
        )
        result = await db.execute(stmt)
        job = result.scalar_one_or_none()

    if not job and job_type in (None, "plan"):
        # Try Plan Generation Job
        stmt = (
            select(PlanGenerationJob)
            .options(joinedload(PlanGenerationJob.idol))
            .where(PlanGenerationJob.id == job_id)
        )
        result = await db.execute(stmt)
        job = result.scalar_one_or_none()

    if not job and job_type in (None, "plan_detail"):
        # Try Plan Item Detail Job
        stmt = (
            select(PlanItemDetailJob)
            .options(
                joinedload(PlanItemDetailJob.plan_item)
                .joinedload(PlanItem.plan)
                .joinedload(Plan.idol)
            )
            .where(PlanItemDetailJob.id == job_id)
        )
        result = await db.execute(stmt)
        job = result.scalar_one_or_none()

    if not job and job_type in (None, "suggest"):
        # Try Idol Suggest Job
        stmt = (
            select(IdolSuggestJob)
            .where(IdolSuggestJob.id == job_id)
        )
        result = await db.execute(stmt)
        job = result.scalar_one_or_none()

    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found",
        )
    
    # Generic job handling
    idol_name = "this person"
    if hasattr(job, "idol") and job.idol:
        idol_name = job.idol.name
    elif hasattr(job, "plan_item") and job.plan_item and job.plan_item.plan and job.plan_item.plan.idol:
        idol_name = job.plan_item.plan.idol.name
    
    # Contextual parameters
    weekly_hours = getattr(job, "weekly_hours", None)
    duration_weeks = getattr(job, "duration_weeks", None)
    interests = getattr(job, "interests", None)
    task_title = None
    if isinstance(job, PlanItemDetailJob) and job.plan_item:
        task_title = job.plan_item.title
    
    # Try to get preview data if available (profile/achievements already extracted)
    preview_achievements = None
    preview_domains = None
    domains_list = None
    
    idol_id = getattr(job, "idol_id", None)
    
    if idol_id and job.progress_percent >= 25 and isinstance(job, IdolImportJob):
        # Profile might be extracted, try to get domains
        profile_stmt = select(IdolProfile).where(IdolProfile.idol_id == idol_id)
        profile_result = await db.execute(profile_stmt)
        profile = profile_result.scalar_one_or_none()
        if profile:
            domains_list = profile.domains[:5] if profile.domains else None
            preview_domains = domains_list
    
    if idol_id and job.progress_percent >= 60 and isinstance(job, IdolImportJob):
        # Achievements might be extracted, get a preview
        timeline_stmt = (
            select(IdolTimelineEvent)
            .where(IdolTimelineEvent.idol_id == idol_id)
            .order_by(IdolTimelineEvent.importance_score.desc())
            .limit(3)
        )
        timeline_result = await db.execute(timeline_stmt)
        events = timeline_result.scalars().all()
        if events:
            preview_achievements = [e.canonical_title for e in events]
    
    # Check if job has real streamed thinking text AND we are in a step that uses it
    real_thinking = getattr(job, "thinking_text", None)
    use_real_thinking = False
    
    if real_thinking:
        if isinstance(job, PlanGenerationJob):
            # Only show LLM thinking during the balancing phase
            if job.step == "balancing_workload":
                use_real_thinking = True
        elif isinstance(job, IdolImportJob):
            # Only show LLM thinking during profile extraction and collection
            if job.step in ["extracting_profile", "collecting_sources"]:
                use_real_thinking = True
        elif isinstance(job, IdolSuggestJob):
             use_real_thinking = True
        elif isinstance(job, PlanItemDetailJob):
             use_real_thinking = True

    if use_real_thinking:
        # Use real LLM output - split into lines for display
        lines = real_thinking.strip().split('\n')
        # Show last few lines as current, rest as completed
        if lines:
            completed_lines = lines[:-1]
            current_line = lines[-1]
        else:
            completed_lines = []
            current_line = ""
        
        thinking_stream = ThinkingStream(
            currentLine=current_line[:500],  # Limit length for UI
            completedLines=completed_lines[-10:],  # Keep last 10 lines
            insight=None,
            step=job.step,
            stepProgress=job.progress_percent,
        )
        thinking_text = ThinkingText(
            message=current_line[:500],
            funFact=None,
            step=job.step,
        )
    else:
        # Fallback to simulated thinking
        stream = get_thinking_stream(
            job.step, 
            idol_name, 
            job.progress_percent, 
            domains_list,
            weekly_hours=weekly_hours,
            duration_weeks=duration_weeks,
            interests=interests,
            task_title=task_title,
        )
        thinking_stream = ThinkingStream(
            currentLine=stream["currentLine"],
            completedLines=stream["completedLines"],
            insight=stream["insight"],
            step=stream["step"],
            stepProgress=stream["stepProgress"],
        )
        thinking_text = ThinkingText(
            message=stream["currentLine"],
            funFact=stream["insight"],
            step=stream["step"],
        )

    return JobStatusResponse(
        id=str(job.id),
        idolId=str(idol_id) if idol_id else None,
        idolName=idol_name,
        status=job.status,
        step=job.step,
        progressPercent=job.progress_percent,
        errorMessage=job.error_message,
        thinkingStream=thinking_stream,
        thinkingText=thinking_text,
        previewAchievements=preview_achievements,
        previewDomains=preview_domains,
        results=getattr(job, "result_json", None),
    )


@router.post("/{job_id}/start", response_model=JobStatusResponse)
async def start_job(
    job_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> JobStatusResponse:
    """Manually trigger a queued job to start."""
    stmt = (
        select(IdolImportJob)
        .options(selectinload(IdolImportJob.idol))
        .where(IdolImportJob.id == job_id)
    )
    result = await db.execute(stmt)
    job = result.scalar_one_or_none()

    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found",
        )

    if job.status not in ["queued", "pending"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Job cannot be started, current status: {job.status}",
        )

    # Import here to avoid circular imports
    from app.tasks.ingestion import run_idol_ingestion

    # Trigger the Celery task
    run_idol_ingestion.delay(job_id)
    
    # Get idol name for personalized messages
    idol_name = job.idol.name if job.idol else "this person"
    
    # Generate thinking stream
    stream = get_thinking_stream(job.step, idol_name, job.progress_percent, None)
    thinking_stream = ThinkingStream(
        currentLine=stream["currentLine"],
        completedLines=stream["completedLines"],
        insight=stream["insight"],
        step=stream["step"],
        stepProgress=stream["stepProgress"],
    )
    
    thinking_text = ThinkingText(
        message=stream["currentLine"],
        funFact=stream["insight"],
        step=stream["step"],
    )

    return JobStatusResponse(
        id=str(job.id),
        idolId=str(job.idol_id) if job.idol_id else None,
        idolName=idol_name,
        status=job.status,
        step=job.step,
        progressPercent=job.progress_percent,
        errorMessage=job.error_message,
        thinkingStream=thinking_stream,
        thinkingText=thinking_text,
    )
