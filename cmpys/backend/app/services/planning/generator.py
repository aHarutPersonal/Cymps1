"""
Plan generation service.

PROMPT MAPPING:
- generate_plan() -> planner_system.txt + plan_backbone_generate.txt
- generate_plan_week_from_backbone() -> planner_system.txt + plan_week_generate.txt

When PLAN_GENERATOR_MODE=llm and LLM is configured, uses LLM to generate plan items.
Otherwise, generates deterministic template-based items.
"""
import logging
from dataclasses import dataclass, field

from app.core.config import settings
from app.models.plan import PlanItemType
from app.services.llm import get_llm_client
from app.services.llm.prompt_loader import load_prompt, render_prompt, sanitize_untrusted_input
from app.services.llm.schemas import (
    PlanBackboneResponse,
    PlanBackboneWeek,
    PlanGenerationResponse,
    PlanWeek,
)
from app.services.llm.telemetry import record_llm_response

logger = logging.getLogger(__name__)

PLAN_BACKBONE_TIMEOUT_SECONDS = 45.0
PLAN_BACKBONE_MAX_TOKENS = 6500
PLAN_WEEK_TIMEOUT_SECONDS = 45.0
PLAN_WEEK_MAX_TOKENS = 5000


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
    backbone_weeks: list[dict] = field(default_factory=list)


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
    start_week: int = 1,
) -> list[str]:
    """Validate the prompt's dynamic execution contract before persistence."""
    issues: list[str] = []
    ordered_weeks = list(range(start_week, start_week + duration_weeks))
    expected_weeks = set(ordered_weeks)
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
        if rounded_total != hours_per_week:
            issues.append(
                f"week {week.week_number} stores {rounded_total} hours; it must "
                f"fill the {hours_per_week}-hour weekly capacity"
            )

        for task in week.binary_tasks:
            resolved_hours = _resolve_estimated_hours(
                task.estimated_hours,
                hours_per_week,
                len(week.binary_tasks),
            )
            if task.type in mission_types and not 2 <= resolved_hours <= 8:
                issues.append(
                    f"week {week.week_number} mission '{task.title}' stores "
                    f"{resolved_hours} hours; mission range is 2-8"
                )
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


def validate_plan_backbone(
    backbone: PlanBackboneResponse,
    *,
    duration_weeks: int,
    hours_per_week: int,
) -> list[str]:
    """Validate the compact cycle before any week is expanded."""
    issues: list[str] = []
    expected_weeks = list(range(1, duration_weeks + 1))
    actual_weeks = [week.week_number for week in backbone.weeks]
    if actual_weeks != expected_weeks:
        issues.append(f"backbone weeks must be exactly {expected_weeks}; got {actual_weeks}")

    mission_types = {"project", "course", "reading"}
    daily_types = {"habit", "practice"}
    low_capacity = hours_per_week < 6
    expected_phases = {
        **{week: "foundation" for week in range(1, 4)},
        **{week: "core_skills" for week in range(4, 7)},
        **{week: "applied_practice" for week in range(7, 10)},
        **{week: "integration" for week in range(10, 13)},
    }
    seen_titles: set[str] = set()
    for week in backbone.weeks:
        expected_phase = expected_phases.get(week.week_number)
        if expected_phase and week.phase != expected_phase:
            issues.append(
                f"week {week.week_number} phase must be {expected_phase}; got {week.phase}"
            )
        missions = [task for task in week.tasks if task.type in mission_types]
        daily = [task for task in week.tasks if task.type in daily_types]
        if (low_capacity and len(missions) != 1) or (
            not low_capacity and not 2 <= len(missions) <= 3
        ):
            issues.append(f"week {week.week_number} has invalid mission task count")
        if (low_capacity and len(daily) != 1) or (
            not low_capacity and not 1 <= len(daily) <= 2
        ):
            issues.append(f"week {week.week_number} has invalid daily task count")
        stored_hours = sum(
            _resolve_estimated_hours(
                task.estimated_hours,
                hours_per_week,
                len(week.tasks),
            )
            for task in week.tasks
        )
        if stored_hours != hours_per_week:
            issues.append(
                f"week {week.week_number} stores {stored_hours} hours; it must "
                f"fill the {hours_per_week}-hour weekly capacity"
            )
        for task in week.tasks:
            resolved_hours = _resolve_estimated_hours(
                task.estimated_hours,
                hours_per_week,
                len(week.tasks),
            )
            if task.type in mission_types and not 2 <= resolved_hours <= 8:
                issues.append(
                    f"week {week.week_number} mission '{task.title}' stores "
                    f"{resolved_hours} hours; mission range is 2-8"
                )
            normalized_title = task.title.strip().casefold()
            if normalized_title in seen_titles:
                issues.append(f"duplicate backbone task title: {task.title}")
            seen_titles.add(normalized_title)
            if not task.success_metric.strip():
                issues.append(
                    f"week {week.week_number} task '{task.title}' needs a success metric"
                )
    return issues


def validate_week_against_backbone(
    week: PlanWeek,
    backbone_week: PlanBackboneWeek,
) -> list[str]:
    """Ensure enrichment cannot silently change the approved cycle shape."""
    issues: list[str] = []
    if len(week.primary_mission.split()) < 35:
        issues.append(
            f"week {week.week_number} primary_mission must contain at least 35 words"
        )
    if week.week_number != backbone_week.week_number:
        issues.append(
            f"week_number must remain {backbone_week.week_number}; got {week.week_number}"
        )
    if len(week.binary_tasks) != len(backbone_week.tasks):
        issues.append(
            f"week {week.week_number} must preserve {len(backbone_week.tasks)} tasks; "
            f"got {len(week.binary_tasks)}"
        )
        return issues
    for index, (task, backbone_task) in enumerate(
        zip(week.binary_tasks, backbone_week.tasks, strict=True)
    ):
        if task.type != backbone_task.type:
            issues.append(
                f"task {index + 1} type must remain {backbone_task.type}; got {task.type}"
            )
        if _resolve_estimated_hours(task.estimated_hours, 168, 1) != _resolve_estimated_hours(
            backbone_task.estimated_hours, 168, 1
        ):
            issues.append(
                f"task {index + 1} estimated_hours must remain "
                f"{backbone_task.estimated_hours}; got {task.estimated_hours}"
            )
        description_words = len(task.description.split())
        minimum_description_words = (
            80 if task.type in {"project", "course", "reading"} else 45
        )
        if description_words < minimum_description_words:
            issues.append(
                f"task {index + 1} description has {description_words} words; "
                f"minimum is {minimum_description_words}"
            )
        if task.type in {"habit", "practice"}:
            instruction_words = len((task.daily_instructions or "").split())
            if instruction_words < 70:
                issues.append(
                    f"task {index + 1} daily_instructions has {instruction_words} "
                    "words; minimum is 70"
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
    weekly_hours = max(3, weekly_hours)

    for week in range(1, duration_weeks + 1):
        if week <= 3:
            phase = "Foundation"
        elif week <= 6:
            phase = "Core Skills"
        elif week <= 9:
            phase = "Applied Practice"
        else:
            phase = "Integration"
        available_for_missions = weekly_hours - 1
        mission_count = (
            1
            if weekly_hours < 6
            else min(3, max(2, (available_for_missions + 7) // 8))
        )
        mission_budget = min(available_for_missions, mission_count * 8)
        daily_hours = weekly_hours - mission_budget
        base_hours, remainder = divmod(mission_budget, mission_count)
        allocated_hours = [
            base_hours + (1 if index < remainder else 0)
            for index in range(mission_count)
        ]
        mission_templates = [
            ("Build", "proof", PlanItemType.PROJECT),
            ("Test", "method", PlanItemType.READING),
            ("Apply", "method", PlanItemType.COURSE),
        ]
        mission_specs = [
            (
                f"Week {week}: {verb} the {phase.lower()} {noun}",
                item_type,
                allocated_hours[index],
            )
            for index, (verb, noun, item_type) in enumerate(
                mission_templates[:mission_count]
            )
        ]

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
# PROMPTS: planner_system.txt, plan_backbone_generate.txt, plan_week_generate.txt
# =============================================================================


async def _generate_plan_backbone(
    *,
    system_prompt: str,
    user_prompt: str,
    duration_weeks: int,
    hours_per_week: int,
) -> PlanBackboneResponse:
    client = get_llm_client(
        timeout=PLAN_BACKBONE_TIMEOUT_SECONDS,
        max_tokens=PLAN_BACKBONE_MAX_TOKENS,
        tier="balanced",
        thinking_budget=0,
    )
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=PlanBackboneResponse,
        repair_on_failure=True,
    )
    issues = (
        validate_plan_backbone(
            validated,
            duration_weeks=duration_weeks,
            hours_per_week=hours_per_week,
        )
        if validated is not None
        else [str(response.error or "backbone schema validation failed")]
    )
    if validated is not None and issues:
        await record_llm_response(
            operation="plan_backbone_generation",
            response=response,
            model=getattr(client, "model", None),
            result_status="contract_failed",
            quality_score=0.0,
            metadata={"stage": "draft", "contract_issues": issues[:30]},
        )
        retry_prompt = user_prompt + (
            "\n\nBACKBONE CONTRACT RETRY: Rewrite the complete compact backbone and "
            "correct every issue below:\n- "
            + "\n- ".join(issues[:30])
        )
        validated, response = await client.generate_and_validate(
            system_prompt=system_prompt,
            user_prompt=retry_prompt,
            output_model=PlanBackboneResponse,
            repair_on_failure=False,
        )
        response.retried = True
        issues = (
            validate_plan_backbone(
                validated,
                duration_weeks=duration_weeks,
                hours_per_week=hours_per_week,
            )
            if validated is not None
            else [str(response.error or "backbone schema validation failed")]
        )

    await record_llm_response(
        operation="plan_backbone_generation",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated is not None and not issues else "failed",
        quality_score=1.0 if validated is not None and not issues else 0.0,
        metadata={
            "stage": "final",
            "week_count": len(validated.weeks) if validated else 0,
            "contract_issues": issues[:30],
        },
    )
    if validated is None or issues:
        raise ValueError("Invalid plan backbone: " + "; ".join(issues))
    return validated


async def generate_plan_week_from_backbone(
    *,
    backbone_week: PlanBackboneWeek | dict,
    roadmap_thesis: str,
    idol_name: str,
    idol_domain: str,
    user_goal: str,
    hours_per_week: int,
    user_context: str = "",
    session_context: str = "",
) -> PlanWeek:
    """Expand one stable backbone week into execution-ready task copy."""
    backbone_week = PlanBackboneWeek.model_validate(backbone_week)
    system_prompt = load_prompt("planner_system")
    user_prompt = render_prompt(
        load_prompt("plan_week_generate"),
        {
            "user_goal": sanitize_untrusted_input(user_goal),
            "hours_per_week": str(hours_per_week),
            "user_context": sanitize_untrusted_input(user_context)
            if user_context
            else "",
            "idol_name": idol_name,
            "idol_domain": idol_domain,
            "roadmap_thesis": roadmap_thesis,
            "backbone_week_json": backbone_week.model_dump(mode="json"),
            "session_context": sanitize_untrusted_input(session_context)
            if session_context
            else "",
        },
        prompt_name="plan_week_generate.txt",
        strict=True,
    )
    client = get_llm_client(
        timeout=PLAN_WEEK_TIMEOUT_SECONDS,
        max_tokens=PLAN_WEEK_MAX_TOKENS,
        tier="balanced",
        thinking_budget=0,
    )
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=PlanGenerationResponse,
        repair_on_failure=True,
    )

    def _issues(result: PlanGenerationResponse | None) -> list[str]:
        if result is None:
            return [str(response.error or "week schema validation failed")]
        contract_issues = validate_plan_contract(
            result,
            duration_weeks=1,
            hours_per_week=hours_per_week,
            start_week=backbone_week.week_number,
        )
        if len(result.weeks) == 1:
            contract_issues.extend(
                validate_week_against_backbone(result.weeks[0], backbone_week)
            )
        return contract_issues

    issues = _issues(validated)
    if validated is not None and issues:
        await record_llm_response(
            operation="plan_week_generation",
            response=response,
            model=getattr(client, "model", None),
            result_status="contract_failed",
            quality_score=0.0,
            metadata={
                "stage": "draft",
                "week": backbone_week.week_number,
                "contract_issues": issues[:30],
            },
        )
        retry_prompt = user_prompt + (
            "\n\nWEEK CONTRACT RETRY: Rewrite only this week and correct every "
            "issue below while preserving the approved task order:\n- "
            + "\n- ".join(issues[:30])
        )
        validated, response = await client.generate_and_validate(
            system_prompt=system_prompt,
            user_prompt=retry_prompt,
            output_model=PlanGenerationResponse,
            repair_on_failure=False,
        )
        response.retried = True
        issues = _issues(validated)

    await record_llm_response(
        operation="plan_week_generation",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated is not None and not issues else "failed",
        quality_score=1.0 if validated is not None and not issues else 0.0,
        metadata={
            "stage": "final",
            "week": backbone_week.week_number,
            "contract_issues": issues[:30],
        },
    )
    if validated is None or issues:
        raise ValueError(
            f"Invalid expanded week {backbone_week.week_number}: " + "; ".join(issues)
        )
    return validated.weeks[0]


def _roadmap_from_backbone(
    backbone: PlanBackboneResponse,
    *,
    expanded_week: PlanWeek,
    hours_per_week: int,
) -> PlanRoadmap:
    type_map = {
        "project": PlanItemType.PROJECT,
        "course": PlanItemType.COURSE,
        "habit": PlanItemType.HABIT,
        "practice": PlanItemType.PRACTICE,
        "reading": PlanItemType.READING,
    }
    result_items: list[PlanItemData] = []
    expanded_by_index = {
        index: task for index, task in enumerate(expanded_week.binary_tasks)
    }
    for week in backbone.weeks:
        for index, backbone_task in enumerate(week.tasks):
            task = (
                expanded_by_index[index]
                if week.week_number == expanded_week.week_number
                else None
            )
            title = task.title if task else backbone_task.title
            description = (
                task.description
                if task
                else (
                    f"{week.primary_mission} This task advances the approved outcome: "
                    f"{week.outcome}"
                )
            )
            result_items.append(
                PlanItemData(
                    title=title[:200],
                    type=type_map[backbone_task.type],
                    description=description,
                    week_start=week.week_number,
                    week_end=week.week_number,
                    success_metric=(
                        _resolve_success_metric(task)
                        if task
                        else backbone_task.success_metric
                    ),
                    estimated_hours=_resolve_estimated_hours(
                        backbone_task.estimated_hours,
                        hours_per_week,
                        len(week.tasks),
                    ),
                    meta_json={
                        "primary_mission": (
                            expanded_week.primary_mission
                            if task
                            else week.primary_mission
                        ),
                        "predicted_friction": (
                            expanded_week.predicted_friction
                            if task
                            else week.predicted_friction
                        ),
                        "friction_solution": (
                            expanded_week.friction_solution
                            if task
                            else week.friction_solution
                        ),
                        "daily_instructions": task.daily_instructions if task else None,
                        "backbone_task_index": index,
                        "week_content_status": "ready" if task else "backbone",
                    },
                )
            )
    return PlanRoadmap(
        roadmap_thesis=backbone.roadmap_thesis,
        anti_goals=backbone.anti_goals,
        items=result_items,
        backbone_weeks=[week.model_dump(mode="json") for week in backbone.weeks],
    )


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

    Generates one compact cycle backbone, then expands Week 1 only. Future
    weeks are enriched by the one-week-ahead worker before they unlock.

    Falls back to deterministic if LLM fails.
    """
    try:
        system_prompt = load_prompt("planner_system")
        user_prompt = render_prompt(load_prompt("plan_backbone_generate"), {
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
        }, prompt_name="plan_backbone_generate.txt", strict=True)
        backbone = await _generate_plan_backbone(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            duration_weeks=duration_weeks,
            hours_per_week=hours_per_week,
        )
        first_week = await generate_plan_week_from_backbone(
            backbone_week=backbone.weeks[0],
            roadmap_thesis=backbone.roadmap_thesis,
            idol_name=idol_name,
            idol_domain=(
                str(idol_profile.get("domains", [""])[0])
                if isinstance(idol_profile, dict) and idol_profile.get("domains")
                else "general"
            ),
            user_goal=user_goal,
            hours_per_week=hours_per_week,
            user_context=user_context,
            session_context="\n\n".join(
                value
                for value in (
                    interview_transcript_json,
                    comparison_summary,
                    blueprint_markdown,
                )
                if value
            ),
        )
        return _roadmap_from_backbone(
            backbone,
            expanded_week=first_week,
            hours_per_week=hours_per_week,
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
    - User: plan_backbone_generate.txt, then plan_week_generate.txt for Week 1

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
