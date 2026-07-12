"""
Plan generation service.

PROMPT MAPPING:
- generate_plan() -> planner_system.txt + plan_generate.txt (LLM optional)

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
from app.services.llm.telemetry import record_llm_response

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


def validate_plan_contract(
    plan: PlanGenerationResponse,
    *,
    duration_weeks: int,
    hours_per_week: int,
) -> list[str]:
    """Validate the prompt's dynamic execution contract before persistence."""
    issues: list[str] = []
    expected_weeks = set(range(1, duration_weeks + 1))
    ordered_weeks = list(range(1, duration_weeks + 1))
    week_numbers = [week.week_number for week in plan.weeks]
    if (
        len(week_numbers) != duration_weeks
        or set(week_numbers) != expected_weeks
        or week_numbers != ordered_weeks
    ):
        issues.append(
            f"weeks must be exactly {ordered_weeks}; got {week_numbers}"
        )
    if len(week_numbers) != len(set(week_numbers)):
        issues.append("week_number values must be unique")
    if not plan.roadmap_thesis.strip():
        issues.append("roadmap_thesis must be non-empty")
    if not plan.anti_goals:
        issues.append("anti_goals must contain at least one domain-specific item")

    mission_types = {"project", "course", "reading"}
    daily_types = {"habit", "practice"}
    low_capacity = hours_per_week < 6
    for week in plan.weeks:
        missions = [task for task in week.binary_tasks if task.type in mission_types]
        daily = [task for task in week.binary_tasks if task.type in daily_types]
        unknown = [
            task.type
            for task in week.binary_tasks
            if task.type not in mission_types | daily_types
        ]
        expected_missions = "exactly 1" if low_capacity else "2-3"
        expected_daily = "exactly 1" if low_capacity else "1-2"
        if (low_capacity and len(missions) != 1) or (
            not low_capacity and not 2 <= len(missions) <= 3
        ):
            issues.append(
                f"week {week.week_number} must have {expected_missions} mission task(s)"
            )
        if (low_capacity and len(daily) != 1) or (
            not low_capacity and not 1 <= len(daily) <= 2
        ):
            issues.append(
                f"week {week.week_number} must have {expected_daily} daily task(s)"
            )
        if unknown:
            issues.append(
                f"week {week.week_number} has unsupported task types {unknown}"
            )
        if not week.primary_mission.strip():
            issues.append(f"week {week.week_number} primary_mission is empty")

        rounded_total = sum(
            _resolve_estimated_hours(
                task.estimated_hours,
                hours_per_week,
                len(week.binary_tasks),
            )
            for task in week.binary_tasks
        )
        if rounded_total > hours_per_week:
            issues.append(
                f"week {week.week_number} stores {rounded_total} hours, above the "
                f"{hours_per_week}-hour cap"
            )

        for task in week.binary_tasks:
            description_words = len(task.description.split())
            minimum_words = 50 if task.type in mission_types else 30
            if description_words < minimum_words:
                issues.append(
                    f"week {week.week_number} task '{task.title}' description has "
                    f"{description_words} words; minimum is {minimum_words}"
                )
            metric = (task.success_metric or "").strip()
            if not metric or metric.casefold() == "task completed":
                issues.append(
                    f"week {week.week_number} task '{task.title}' needs a binary "
                    "success_metric"
                )
            if task.type in daily_types:
                instruction_words = len((task.daily_instructions or "").split())
                if instruction_words < 40:
                    issues.append(
                        f"week {week.week_number} daily task '{task.title}' has "
                        f"{instruction_words} daily-instruction words; minimum is 40"
                    )
    return issues


# =============================================================================
# Deterministic Plan Generation (no LLM)
# =============================================================================


def _generate_deterministic_items(
    weekly_hours: int,
    duration_weeks: int = 12,
    *,
    idol_name: str = "the selected mentor",
    user_goal: str = "personal and professional growth",
) -> PlanRoadmap:
    """
    Generate deterministic plan items as fallback.

    NO LLM USED - pure template-based generation.
    """
    items: list[PlanItemData] = []
    weekly_hours = max(2, weekly_hours)

    for week in range(1, duration_weeks + 1):
        if week <= 3:
            phase = "Foundation"
        elif week <= 6:
            phase = "Core Skills"
        elif week <= 9:
            phase = "Applied Practice"
        else:
            phase = "Integration"
        daily_hours = 1
        mission_budget = weekly_hours - daily_hours
        mission_count = 1 if weekly_hours < 6 else 2
        first_hours = mission_budget if mission_count == 1 else max(2, mission_budget // 2)
        second_hours = max(2, mission_budget - first_hours) if mission_count == 2 else 0
        if mission_count == 2 and first_hours + second_hours + daily_hours > weekly_hours:
            first_hours = max(2, weekly_hours - daily_hours - second_hours)

        mission_specs: list[tuple[str, PlanItemType, int]] = [
            (
                f"Week {week}: Build the {phase.lower()} proof",
                PlanItemType.PROJECT,
                first_hours,
            ),
        ]
        if mission_count == 2:
            mission_specs.append(
                (
                    f"Week {week}: Test the {phase.lower()} method",
                    PlanItemType.READING,
                    second_hours,
                )
            )

        for title, item_type, estimated in mission_specs:
            items.append(PlanItemData(
                title=title,
                type=item_type,
                description=(
                    f"Use {idol_name}'s documented domain as a reference point while "
                    f"advancing the {phase.lower()} stage of {user_goal}. Select one "
                    "specific technique from the available evidence, study how it works, "
                    "apply it to a real artifact from your own context, record the choices "
                    "you made, and revise the artifact once against an explicit quality "
                    "check. Keep the scope narrow enough to finish this week."
                ),
                week_start=week,
                week_end=week,
                success_metric=(
                    "One finished artifact, one written rationale, and one documented "
                    "revision pass are saved for review."
                ),
                estimated_hours=estimated,
                meta_json={
                    "primary_mission": f"Produce a verifiable {phase.lower()} outcome",
                    "predicted_friction": "The first useful version may feel incomplete",
                    "friction_solution": "Time-box the draft, then improve it against one rubric",
                },
            ))

        items.append(PlanItemData(
            title=f"Week {week}: Daily {phase.lower()} drill",
            type=PlanItemType.PRACTICE,
            description=(
                f"Practice one domain-specific component of {user_goal} for ten to "
                "twenty focused minutes on four days this week. Log the input, the "
                "observable result, and one adjustment after every repetition so the "
                "routine compounds instead of becoming passive repetition."
            ),
            week_start=week,
            week_end=week,
            success_metric="Four dated practice logs with an output and adjustment are complete.",
            estimated_hours=daily_hours,
            meta_json={
                "primary_mission": f"Produce a verifiable {phase.lower()} outcome",
                "predicted_friction": "Skipping a day after an imperfect session",
                "friction_solution": "Use the minimum ten-minute version and record the result",
                "daily_instructions": (
                    "Set a ten-to-twenty-minute timer and choose one small component of "
                    "this week's mission. Produce a visible attempt without switching "
                    "tools. Compare it with yesterday's attempt or the stated rubric, "
                    "write one sentence about the difference, and log the next adjustment. "
                    "You are done when the attempt and adjustment are both saved."
                ),
            },
        ))

    return PlanRoadmap(
        roadmap_thesis=(
            f"Turn {idol_name}'s documented methods into weekly evidence that advances "
            f"{user_goal}, while keeping every commitment inside the available capacity."
        ),
        anti_goals=[
            "Do not collect advice without producing a domain-specific artifact and revision."
        ],
        items=items,
    )


# =============================================================================
# LLM Plan Generation
# PROMPTS: planner_system.txt, plan_generate.txt
# =============================================================================


async def _generate_llm_items(
    idol_name: str,
    user_goal: str,
    hours_per_week: int,
    duration_weeks: int = 12,
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
    - System: planner_system.txt
    - User: plan_generate.txt

    Falls back to deterministic if LLM fails.
    """
    # Plans are a core user-visible artifact. Use the balanced model; the fast
    # tier is reserved for extraction/classification where source constraints
    # make the smaller model reliable.
    client = get_llm_client(tier="balanced", thinking_budget=1024)

    try:
        # Load prompt templates. planner_system.txt (not extractor_system.txt):
        # plan generation needs world knowledge of real books/courses, which the
        # extraction system prompt explicitly forbids.
        system_prompt = load_prompt("planner_system")
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
            "user_goal": sanitize_untrusted_input(user_goal),
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
            "comparison_summary": sanitize_untrusted_input(comparison_summary)
            if comparison_summary else "",
            "blueprint_markdown": sanitize_untrusted_input(blueprint_markdown)
            if blueprint_markdown else "",
            "previous_cycle_block": sanitize_untrusted_input(previous_cycle_block)
            if previous_cycle_block else "",
        }, prompt_name="plan_generate.txt", strict=True)

        validated, response = await client.generate_and_validate(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            output_model=PlanGenerationResponse,
            repair_on_failure=True,
        )

        contract_issues = (
            validate_plan_contract(
                validated,
                duration_weeks=duration_weeks,
                hours_per_week=hours_per_week,
            )
            if validated is not None
            else []
        )
        if validated is not None and contract_issues:
            await record_llm_response(
                operation="plan_generation",
                response=response,
                model=getattr(client, "model", None),
                result_status="contract_failed",
                quality_score=0.0,
                metadata={"contract_issues": contract_issues[:20]},
            )
            retry_prompt = user_prompt + (
                "\n\nPLAN CONTRACT RETRY: The previous plan failed deterministic "
                "validation. Rewrite the complete plan and fix every issue below:\n- "
                + "\n- ".join(contract_issues[:30])
                + "\nReturn the full JSON plan, not a patch. Preserve domain specificity "
                "and do not weaken description or daily-instruction depth."
            )
            retry_validated, retry_response = await client.generate_and_validate(
                system_prompt=system_prompt,
                user_prompt=retry_prompt,
                output_model=PlanGenerationResponse,
                repair_on_failure=False,
            )
            setattr(retry_response, "retried", True)
            validated, response = retry_validated, retry_response
            contract_issues = (
                validate_plan_contract(
                    validated,
                    duration_weeks=duration_weeks,
                    hours_per_week=hours_per_week,
                )
                if validated is not None
                else []
            )
            if contract_issues:
                logger.error(
                    "LLM plan still violates contract after retry: %s",
                    contract_issues,
                )
                validated = None

        week_count = len(validated.weeks) if validated else 0
        nonempty_weeks = (
            sum(1 for week in validated.weeks if week.binary_tasks) if validated else 0
        )
        structure_score = min(1.0, week_count / max(duration_weeks, 1)) * (
            nonempty_weeks / max(week_count, 1)
        )
        await record_llm_response(
            operation="plan_generation",
            response=response,
            model=getattr(client, "model", None),
            result_status="schema_valid" if validated and validated.weeks else "fallback",
            quality_score=structure_score,
            metadata={
                "week_count": week_count,
                "nonempty_week_count": nonempty_weeks,
                "retried": response.retried,
                "contract_issue_count": len(contract_issues),
            },
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
    return _generate_deterministic_items(
        hours_per_week,
        duration_weeks,
        idol_name=idol_name,
        user_goal=user_goal,
    )


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
    - System: planner_system.txt
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
            duration_weeks=duration_weeks,
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
        return _generate_deterministic_items(
            weekly_hours,
            duration_weeks,
            idol_name=idol_name,
            user_goal=user_goal,
        )
