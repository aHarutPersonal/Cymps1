"""
Plan generation service.

PROMPT MAPPING:
- generate_plan() -> extractor_system.txt + plan_generate.txt (LLM optional)

When PLAN_GENERATOR_MODE=llm and LLM is configured, uses LLM to generate plan items.
Otherwise, generates deterministic template-based items.
"""
import logging
from dataclasses import dataclass, field

from app.core.config import settings
from app.models.plan import PlanItemType
from app.services.llm import get_llm_client
from app.services.llm.prompt_loader import load_prompt, render_prompt, sanitize_untrusted_input
from app.services.llm.schemas import PlanGenerationResponse

logger = logging.getLogger(__name__)


@dataclass
class PlanItemData:
    """Data for a plan item."""
    title: str
    type: PlanItemType
    description: str
    week_start: int
    week_end: int
    success_metric: str
    estimated_hours: int
    resource_title: str | None = None
    resource_url: str | None = None
    # Metadata for detail generation (stored in meta_json)
    meta_json: dict | None = None


@dataclass
class PlanRoadmap:
    """Top-level roadmap data from the new prompt schema."""
    roadmap_thesis: str = ""
    anti_goals: list[str] = field(default_factory=list)
    items: list[PlanItemData] = field(default_factory=list)


# =============================================================================
# QA Fix Helpers
# =============================================================================


def _resolve_estimated_hours(task_hours, hours_per_week, num_tasks) -> int:
    """Never truncate a real task to 0h. Round sub-hour tasks up to 1;
    derive a positive share when the model gave 0/None."""
    if task_hours and task_hours > 0:
        return max(1, round(task_hours))
    return max(1, hours_per_week // max(1, num_tasks))


def _resolve_success_metric(task) -> str:
    """Use the model's success_metric; fall back to something derived from the
    description — never the useless 'Task completed: <title>' placeholder."""
    metric = (getattr(task, "success_metric", None) or "").strip()
    if metric:
        return metric
    description = (getattr(task, "description", "") or "").strip()
    if description:
        return f"Delivered: {description.split('. ')[0].rstrip('.')}"
    return f"Delivered the outcome of: {task.title}"


def validate_roadmap_structure(roadmap, duration_weeks) -> list[str]:
    """Return human-readable warnings if the roadmap misses weeks or has empty
    weeks in the requested 1..duration_weeks range."""
    warnings: list[str] = []
    tasks_per_week: dict[int, int] = {}
    for item in roadmap.items:
        for week in range(item.week_start, item.week_end + 1):
            tasks_per_week[week] = tasks_per_week.get(week, 0) + 1
    missing = sorted(set(range(1, duration_weeks + 1)) - set(tasks_per_week))
    if missing:
        warnings.append(f"Plan is missing week(s) {missing} of {duration_weeks} requested.")
    for week in range(1, duration_weeks + 1):
        if tasks_per_week.get(week, 0) == 0 and week not in missing:
            warnings.append(f"Week {week} has no tasks.")
    return warnings


# =============================================================================
# Deterministic Plan Generation (no LLM)
# =============================================================================


def _generate_deterministic_items(
    weekly_hours: int,
    duration_weeks: int = 12,
) -> PlanRoadmap:
    """
    Generate deterministic plan items as fallback.

    NO LLM USED - pure template-based generation.
    """
    items = []

    # Week-based deterministic plan (3-phase approach)
    phases = [
        # Phase 1: Foundation (Weeks 1-4)
        {"weeks": range(1, 5), "theme": "Foundation & Research"},
        # Phase 2: Build (Weeks 5-8)
        {"weeks": range(5, 9), "theme": "Execution & Building"},
        # Phase 3: Scale (Weeks 9-12)
        {"weeks": range(9, 13), "theme": "Refinement & Consolidation"},
    ]

    for phase in phases:
        for w in phase["weeks"]:
            if w > duration_weeks:
                break
            items.append(PlanItemData(
                title=f"Week {w}: {phase['theme']}",
                type=PlanItemType.PROJECT,
                description=f"Execute the highest-leverage task for {phase['theme'].lower()} this week.",
                week_start=w,
                week_end=w,
                success_metric="All binary tasks completed for this week",
                estimated_hours=weekly_hours,
                meta_json={
                    "predicted_friction": "Procrastination or overthinking",
                    "friction_solution": "Start with the smallest possible action",
                },
            ))

    return PlanRoadmap(
        roadmap_thesis="Focus on the critical 20% of actions that drive 80% of results.",
        anti_goals=["Avoid busywork disguised as productivity"],
        items=items,
    )


# =============================================================================
# LLM Plan Generation
# PROMPTS: extractor_system.txt, plan_generate.txt
# =============================================================================


async def _generate_llm_items(
    idol_name: str,
    user_goal: str,
    hours_per_week: int,
    target_age: int | None = None,
    user_context: str = "",
    idol_profile: dict | list | str | None = None,
    idol_persona: dict | list | str | None = None,
    idol_milestones: dict | list | str | None = None,
    gaps: dict | list | str | None = None,
    readiness_by_gap: dict | list | str | None = None,
    interview_transcript_json: str = "",
    comparison_summary: str = "",
    blueprint_markdown: str = "",
    previous_cycle_block: str = "",
) -> PlanRoadmap:
    """
    Generate plan items using LLM.

    PROMPTS USED:
    - System: extractor_system.txt
    - User: plan_generate.txt

    Falls back to deterministic if LLM fails.
    """
    client = get_llm_client(fast=True)

    try:
        # Load prompt templates
        system_prompt = load_prompt("extractor_system")
        user_template = load_prompt("plan_generate")

        # Render user prompt with the full plan contract.
        #
        # The three session-context placeholders (interview_transcript_json,
        # comparison_summary, blueprint_markdown) are REQUIRED by plan_generate.txt.
        # When this path runs without an agentic session they must still be
        # provided (empty) or strict rendering raises PromptRenderError. The
        # prompt is written to build from profile + gaps alone when they are empty.
        # user_context is free user-authored text, so wrap it as untrusted data.
        user_prompt = render_prompt(user_template, {
            "user_goal": user_goal,
            "idol_name": idol_name,
            "hours_per_week": str(hours_per_week),
            "target_age": str(target_age or "null"),
            "user_context": sanitize_untrusted_input(user_context) if user_context else "",
            "idol_profile_json": idol_profile or {},
            "idol_persona_json": idol_persona or {},
            "idol_milestones_json": idol_milestones or [],
            "gaps_json": gaps or [],
            "readiness_by_gap_json": readiness_by_gap or {},
            "interview_transcript_json": interview_transcript_json or "",
            "comparison_summary": comparison_summary or "",
            "blueprint_markdown": blueprint_markdown or "",
            "previous_cycle_block": previous_cycle_block or "",
        }, prompt_name="plan_generate.txt", strict=True)

        validated, response = await client.generate_and_validate(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            output_model=PlanGenerationResponse,
            repair_on_failure=True,
        )

        if validated and validated.weeks:
            result_items = []
            type_map = {
                "project": PlanItemType.PROJECT,
                "course": PlanItemType.COURSE,
                "habit": PlanItemType.HABIT,
                "practice": PlanItemType.PRACTICE,
                "reading": PlanItemType.READING,
                "reflection": PlanItemType.REFLECTION,
            }
            for week in validated.weeks:
                for task in week.binary_tasks:
                    item_type = type_map.get(task.type.lower(), PlanItemType.PROJECT)
                    estimated_hours = _resolve_estimated_hours(
                        task.estimated_hours, hours_per_week, len(week.binary_tasks)
                    )
                    result_items.append(PlanItemData(
                        title=task.title,
                        type=item_type,
                        description=task.description,
                        week_start=week.week_number,
                        week_end=week.week_number,
                        success_metric=_resolve_success_metric(task),
                        estimated_hours=estimated_hours,
                        meta_json={
                            "primary_mission": week.primary_mission,
                            "predicted_friction": week.predicted_friction,
                            "friction_solution": week.friction_solution,
                            "daily_instructions": task.daily_instructions,
                        },
                    ))

            return PlanRoadmap(
                roadmap_thesis=validated.roadmap_thesis,
                anti_goals=validated.anti_goals,
                items=result_items,
            )

    except Exception as e:
        logger.exception(f"LLM plan generation failed: {e}, falling back to deterministic")

    # Fall back to deterministic
    return _generate_deterministic_items(hours_per_week)


# =============================================================================
# Main Entry Point
# =============================================================================


async def generate_plan(
    idol_name: str = "the idol",
    user_goal: str = "personal and professional growth",
    weekly_hours: int = 10,
    duration_weeks: int = 12,
    force_llm: bool = False,
    user_context: str = "",
    previous_cycle_block: str = "",
    # Legacy params kept for backward compat (ignored by new prompt)
    **kwargs,
) -> PlanRoadmap:
    """
    Generate a strategic 12-week plan.

    PROMPTS USED (when LLM mode):
    - System: extractor_system.txt
    - User: plan_generate.txt

    LLM is used if:
    - PLAN_GENERATOR_MODE=llm AND LLM_PROVIDER=openai AND API key is set
    - OR force_llm=True

    Otherwise generates deterministic template-based items.

    Returns:
        PlanRoadmap with roadmap_thesis, anti_goals, and items
    """
    use_llm = (
        settings.plan_generator_mode == "llm" and
        settings.llm_configured
    ) or force_llm

    if use_llm:
        if force_llm and not settings.llm_configured:
            raise ValueError("LLM not configured but force_llm=True")

        logger.info(f"Generating plan using LLM for {idol_name}")
        return await _generate_llm_items(
            idol_name=idol_name,
            user_goal=user_goal,
            hours_per_week=weekly_hours,
            target_age=kwargs.get("target_age"),
            user_context=user_context,
            idol_profile=kwargs.get("idol_profile"),
            idol_persona=kwargs.get("idol_persona"),
            idol_milestones=kwargs.get("idol_milestones"),
            gaps=kwargs.get("gaps"),
            readiness_by_gap=kwargs.get("readiness_by_gap"),
            interview_transcript_json=kwargs.get("interview_transcript_json", ""),
            comparison_summary=kwargs.get("comparison_summary", ""),
            blueprint_markdown=kwargs.get("blueprint_markdown", ""),
            previous_cycle_block=previous_cycle_block,
        )
    else:
        logger.info("Generating plan using deterministic templates")
        return _generate_deterministic_items(weekly_hours, duration_weeks)
