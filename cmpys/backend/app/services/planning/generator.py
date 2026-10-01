"""
Plan generation service.

PROMPT MAPPING:
- generate_plan() -> planner_system.txt + plan_backbone_generate.txt
- generate_plan_week_from_backbone() -> planner_system.txt + plan_week_generate.txt

When PLAN_GENERATOR_MODE=llm and LLM is configured, uses LLM to generate plan items
and reports provider failure honestly. Deterministic templates are used only
when deterministic mode is explicitly configured.
"""

import logging
import json
import re
from contextvars import ContextVar
from pydantic import BaseModel, Field
from dataclasses import dataclass, field

from app.core.config import settings
from app.models.plan import PlanItemType
from app.services.llm import get_llm_client
from app.services.llm.recovery import operational_recovery_client, CompleteRecoveryClient
from app.services.curriculum.hashing import sha256_json
from app.services.planning.checkpoints import PlanCheckpointStore
from app.services.llm.prompt_loader import (
    load_prompt,
    render_prompt,
    sanitize_untrusted_input,
)
from app.services.llm.schemas import (
    BinaryTask,
    PlanBackboneResponse,
    PlanBackboneWeek,
    PlanGenerationResponse,
    ExecutionPlanResponse,
    PlanWeek,
)
from app.services.llm.telemetry import record_llm_response

logger = logging.getLogger(__name__)

_plan_recovery_response = ContextVar("plan_recovery_response", default=None)
_plan_run_active = ContextVar("plan_run_active", default=False)


def _recover_plan_outage(response, **kwargs):
    client = operational_recovery_client(response, **kwargs)
    if client is not None and _plan_run_active.get():
        # Carry an observed outage through this run only. Subsequent stages
        # must not pay for another call to the same unavailable gateway.
        _plan_recovery_response.set(response)
    return client



def _plan_client(**kwargs):
    recovery = operational_recovery_client(
        _plan_recovery_response.get(), timeout=max(90, kwargs["timeout"]), max_tokens=kwargs["max_tokens"]
    )
    return recovery or get_llm_client(**kwargs)


class BackboneWeekRepair(BaseModel):
    weeks: list[PlanBackboneWeek] = Field(min_length=1, max_length=12)


PLAN_BACKBONE_TIMEOUT_SECONDS = 45.0
PLAN_BACKBONE_MAX_TOKENS = 9000
PLAN_BACKBONE_RECOVERY_TIMEOUT_SECONDS = 90.0
PLAN_BACKBONE_RECOVERY_MAX_TOKENS = 16000
PLAN_WEEK_TIMEOUT_SECONDS = 45.0
PLAN_WEEK_MAX_TOKENS = 8000
PLAN_WEEK_RECOVERY_TIMEOUT_SECONDS = 90.0
PLAN_WEEK_RECOVERY_MAX_TOKENS = 16000


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
    generation_source: str = "deterministic"


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
        warnings.append(
            f"Plan is missing week(s) {missing} of {duration_weeks} requested."
        )
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
        issues.append(f"weeks must be exactly {ordered_weeks}; got {week_numbers}")
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
        issues.append(
            f"backbone weeks must be exactly {expected_weeks}; got {actual_weeks}"
        )

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


def _normalize_backbone_workload(
    backbone: PlanBackboneResponse,
    *,
    hours_per_week: int,
) -> tuple[PlanBackboneResponse, list[dict]]:
    """Correct a one-hour scheduling slip before lesson content is written.

    Models select the learning work; integer workload accounting is server
    arithmetic. Keep all identities and pedagogical text, reject infeasible
    task counts, and leave larger discrepancies for a quality review.
    """
    candidate = backbone.model_copy(deep=True)
    adjustments: list[dict] = []
    for week in candidate.weeks:
        missions = [i for i, task in enumerate(week.tasks) if task.type in {"project", "course", "reading"}]
        daily = [i for i, task in enumerate(week.tasks) if task.type in {"habit", "practice"}]
        low_capacity = hours_per_week < 6
        if (
            (low_capacity and (len(missions), len(daily)) != (1, 1))
            or (not low_capacity and not (2 <= len(missions) <= 3 and 1 <= len(daily) <= 2))
            or len(missions) + len(daily) != len(week.tasks)
        ):
            continue
        hours = [_resolve_estimated_hours(task.estimated_hours, hours_per_week, len(week.tasks)) for task in week.tasks]
        if any(not 2 <= hours[index] <= 8 for index in missions):
            continue
        difference = hours_per_week - sum(hours)
        if abs(difference) != 1:
            continue
        if difference > 0:
            eligible = sorted((index for index in missions if hours[index] < 8), key=lambda index: hours[index])
            eligible += sorted(daily, key=lambda index: hours[index])
        else:
            eligible = sorted((index for index in daily if hours[index] > 1), key=lambda index: -hours[index])
            eligible += sorted((index for index in missions if hours[index] > 2), key=lambda index: -hours[index])
        if not eligible:
            continue
        index = eligible[0]
        previous = hours[index]
        week.tasks[index].estimated_hours = previous + difference
        adjustments.append({"week": week.week_number, "task_index": index, "from_hours": previous, "to_hours": previous + difference})
    return candidate, adjustments


def daily_workload_issues(task: BinaryTask) -> list[str]:
    if task.type not in {"habit", "practice"}:
        return []
    text = " ".join((task.description, task.daily_instructions or ""))
    # Verify explicit weekly totals; do not interpret a single session as a week.
    totals = re.findall(r"\b(\d+(?:\.\d+)?)\s*minutes?\s+(?:per|a|each)\s+week\b", text, re.IGNORECASE)
    expected = float(task.estimated_hours) * 60
    return [f"Daily task '{task.title}' claims {v} minutes per week but stores {expected:g}; make the cadence and workload agree."
            for v in totals if abs(float(v) - expected) > 0.01]


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
        if _resolve_estimated_hours(
            task.estimated_hours, 168, 1
        ) != _resolve_estimated_hours(backbone_task.estimated_hours, 168, 1):
            issues.append(
                f"task {index + 1} estimated_hours must remain "
                f"{backbone_task.estimated_hours}; got {task.estimated_hours}"
            )
        description_words = len(task.description.split())
        # A daily card is a summary; execution depth is checked separately in
        # its >=70-word instructions. Use the existing plan-contract floor for
        # the summary instead of rejecting a complete plan at 44 vs 45 words.
        minimum_description_words = (
            80 if task.type in {"project", "course", "reading"} else 30
        )
        if description_words < minimum_description_words:
            issues.append(
                f"task {index + 1} description has {description_words} words; "
                f"minimum is {minimum_description_words}"
            )
        if task.type in {"habit", "practice"}:
            issues.extend(daily_workload_issues(task))
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
            1 if weekly_hours < 6 else min(3, max(2, (available_for_missions + 7) // 8))
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
            items.append(
                PlanItemData(
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
                )
            )

        items.append(
            PlanItemData(
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
            )
        )

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
    telemetry_context: dict | None = None,
    candidate_callback=None,
) -> PlanBackboneResponse:
    telemetry_context = telemetry_context or {}
    active_client = _plan_client(
        timeout=90 if settings.llm_provider == "zai" else PLAN_BACKBONE_TIMEOUT_SECONDS,
        max_tokens=PLAN_BACKBONE_MAX_TOKENS,
        tier="balanced",
        thinking_level="medium",
    )
    validated, response = await active_client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=PlanBackboneResponse,
        # A malformed full-cycle response should be regenerated by the quality
        # model, not expanded into a second large same-tier repair prompt.
        repair_on_failure=False,
    )
    workload_adjustments = []
    if validated is not None:
        validated, workload_adjustments = _normalize_backbone_workload(
            validated, hours_per_week=hours_per_week
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
    localized_failure = (
        candidate_callback is not None
        and validated is not None
        and bool(issues)
        and all(re.match(r"week \d+\b", issue) for issue in issues)
    )
    if issues and not localized_failure and not (isinstance(active_client, CompleteRecoveryClient) and _plan_recovery_response.get() is not None):
        finish_reason = str(getattr(response, "finish_reason", "") or "")
        was_truncated = "MAX_TOKENS" in finish_reason.upper()
        recovery_reason = (
            "truncated"
            if was_truncated
            else "contract_invalid"
            if validated is not None
            else "schema_invalid"
        )
        logger.warning(
            "Plan backbone %s; regenerating once with the quality tier",
            recovery_reason,
        )
        await record_llm_response(
            operation="plan_backbone_generation",
            response=response,
            model=getattr(active_client, "model", None),
            result_status=(
                "contract_failed" if validated is not None else "schema_failed"
            ),
            quality_score=0.0,
            metadata={
                **telemetry_context,
                "stage": "draft",
                "contract_issues": issues[:30],
                "recovery_reason": recovery_reason,
                "recovery_tier": "quality",
            },
        )

        # Gemini counts hidden reasoning inside max_output_tokens. A balanced
        # fallback can therefore stop at MAX_TOKENS despite emitting only a
        # few thousand visible tokens. Escalate exactly once to the quality
        # model with enough total headroom and low reasoning so the complete
        # JSON artifact, rather than hidden thoughts, receives the budget.
        active_client = _recover_plan_outage(
            response,
            timeout=PLAN_BACKBONE_RECOVERY_TIMEOUT_SECONDS,
            max_tokens=PLAN_BACKBONE_RECOVERY_MAX_TOKENS,
        ) or _plan_client(
            timeout=PLAN_BACKBONE_RECOVERY_TIMEOUT_SECONDS,
            max_tokens=PLAN_BACKBONE_RECOVERY_MAX_TOKENS,
            tier="quality",
            thinking_level="low",
        )
        failure_summary = " | ".join(
            issue.replace("\n", " ")[:180] for issue in issues[:8]
        )
        retry_prompt = user_prompt + (
            "\n\nBACKBONE QUALITY RECOVERY:\n"
            "The prior draft was cut off or invalid. Regenerate the complete "
            "backbone from scratch. Return JSON only; include every week from 1 "
            f"through {duration_weeks}; keep each text field to one concise "
            "sentence; preserve the exact weekly capacity; and do not include "
            "commentary."
            + (f"\nChecks to correct: {failure_summary}" if failure_summary else "")
        )
        validated, response = await active_client.generate_and_validate(
            system_prompt=system_prompt,
            user_prompt=retry_prompt,
            output_model=PlanBackboneResponse,
            repair_on_failure=False,
        )
        response.retried = True
        if validated is not None:
            validated, workload_adjustments = _normalize_backbone_workload(
                validated, hours_per_week=hours_per_week
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

    await record_llm_response(
        operation="plan_backbone_generation",
        response=response,
        model=getattr(active_client, "model", None),
        result_status="schema_valid"
        if validated is not None and not issues
        else "failed",
        quality_score=1.0 if validated is not None and not issues else 0.0,
        metadata={
            **telemetry_context,
            "stage": "final",
            "week_count": len(validated.weeks) if validated else 0,
            "contract_issues": issues[:30],
            "workload_adjustments": workload_adjustments,
            "targeted_repair": localized_failure,
        },
    )
    if candidate_callback is not None and validated is not None:
        await candidate_callback(validated, response, issues)
    if validated is None or issues:
        raise ValueError("Invalid plan backbone: " + "; ".join(issues))
    return validated


async def _checkpointed_backbone(*, store, system_prompt, user_prompt,
                                 duration_weeks, hours_per_week, telemetry_context):
    async def remember(candidate, response, issues):
        await store.put("backbone", candidate.model_dump(mode="json"),
                        provider=getattr(response, "provider", None),
                        model=getattr(response, "model", None), issues=issues, repair_attempts=0)
    saved = store.load("backbone")
    if saved is None:
        try:
            return await _generate_plan_backbone(
                system_prompt=system_prompt, user_prompt=user_prompt,
                duration_weeks=duration_weeks, hours_per_week=hours_per_week,
                telemetry_context=telemetry_context, candidate_callback=remember)
        except ValueError:
            saved = store.load("backbone")
            if saved is None:
                raise
    candidate = PlanBackboneResponse.model_validate(saved["payload"])
    candidate, workload_adjustments = _normalize_backbone_workload(
        candidate, hours_per_week=hours_per_week
    )
    issues = validate_plan_backbone(candidate, duration_weeks=duration_weeks,
                                    hours_per_week=hours_per_week)
    if not issues:
        if workload_adjustments:
            await store.put("backbone", candidate.model_dump(mode="json"),
                            **{key: value for key, value in saved.items() if key not in {"payload", "issues", "workload_adjustments"}},
                            issues=[], workload_adjustments=workload_adjustments)
        return candidate
    if saved.get("repair_attempts", 0) >= 1:
        raise ValueError("Saved backbone exhausted its targeted repair: " + "; ".join(issues))
    # Only localized semantic failures can be repaired by replacing weeks.
    # Global topology/title failures need a changed full-cycle request.
    numbers = set()
    for issue in issues:
        match = re.match(r"week (\d+)\b", issue)
        if not match:
            raise ValueError("Backbone requires full-cycle revision: " + issue)
        numbers.add(int(match.group(1)))
    if not numbers.issubset({w.week_number for w in candidate.weeks}):
        raise ValueError("Backbone repair references an unknown week")
    await store.put("backbone", candidate.model_dump(mode="json"),
                    provider=saved.get("provider"), model=saved.get("model"),
                    issues=issues, repair_attempts=1)
    client = (
        CompleteRecoveryClient(model=settings.gemini_quality_model, timeout=90,
                               max_tokens=6000, thinking_level="low")
        if saved.get("provider") == "gemini" and settings.gemini_api_key
        else _plan_client(timeout=90, max_tokens=6000, tier="quality", thinking_level="low")
    )
    prompt = user_prompt + "\n\nTARGETED BACKBONE CORRECTION:\n" + json.dumps({
        "replace_only_week_numbers": sorted(numbers), "errors": issues,
        "current_backbone": candidate.model_dump(mode="json"),
        "instruction": "Return only the requested replacement weeks. Copy each requested week's primary_mission, outcome and phase verbatim; preserve its place in the progression. Correct task count and capacity; every task must serve the user's goal. Do not include other weeks, thesis or anti-goals."
    }, ensure_ascii=False)
    result, response = await client.generate_and_validate(
        system_prompt=system_prompt, user_prompt=prompt,
        output_model=BackboneWeekRepair, repair_on_failure=False)
    repair_issues = []
    merged = None
    if result is None:
        repair_issues = [str(response.error or "invalid repair schema")]
    elif len(result.weeks) != len(numbers) or {w.week_number for w in result.weeks} != numbers:
        repair_issues = ["Repair must replace exactly the requested weeks"]
    elif any(
        (w.primary_mission, w.outcome, w.phase) !=
        next((old.primary_mission, old.outcome, old.phase) for old in candidate.weeks if old.week_number == w.week_number)
        for w in result.weeks
    ):
        repair_issues = ["Repair changed the approved weekly outcome or phase"]
    else:
        replacements = {w.week_number: w for w in result.weeks}
        merged = candidate.model_copy(update={"weeks": [replacements.get(w.week_number, w) for w in candidate.weeks]})
        merged, _ = _normalize_backbone_workload(merged, hours_per_week=hours_per_week)
        repair_issues = validate_plan_backbone(merged, duration_weeks=duration_weeks,
                                              hours_per_week=hours_per_week)
    await record_llm_response(operation="plan_backbone_targeted_repair", response=response,
        model=getattr(client, "model", None), result_status="failed" if repair_issues else "schema_valid",
        metadata={**(telemetry_context or {}), "repaired_weeks": sorted(numbers), "contract_issues": repair_issues})
    if merged is not None:
        await store.put("backbone", merged.model_dump(mode="json"),
                        provider=getattr(response, "provider", None), model=getattr(client, "model", None),
                        issues=repair_issues, repair_attempts=1,
                        previous_payload=candidate.model_dump(mode="json"))
    if repair_issues or merged is None:
        raise ValueError("Invalid targeted backbone repair: " + "; ".join(repair_issues))
    return merged


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
    telemetry_context: dict | None = None,
) -> PlanWeek:
    """Expand one stable backbone week into execution-ready task copy."""
    telemetry_context = telemetry_context or {}
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
    active_client = _plan_client(
        timeout=90 if settings.llm_provider == "zai" else PLAN_WEEK_TIMEOUT_SECONDS,
        max_tokens=PLAN_WEEK_MAX_TOKENS,
        tier="balanced",
        thinking_level="medium",
    )
    validated, response = await active_client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=ExecutionPlanResponse,
        # A malformed week should be regenerated by the quality model, not
        # expanded into a second large same-tier schema repair prompt.
        repair_on_failure=False,
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
    if issues and not (isinstance(active_client, CompleteRecoveryClient) and _plan_recovery_response.get() is not None):
        finish_reason = str(getattr(response, "finish_reason", "") or "")
        was_truncated = "MAX_TOKENS" in finish_reason.upper()
        recovery_reason = (
            "truncated"
            if was_truncated
            else "contract_invalid"
            if validated is not None
            else "schema_invalid"
        )
        logger.warning(
            "Plan week %s %s; regenerating once with the quality tier",
            backbone_week.week_number,
            recovery_reason,
        )
        await record_llm_response(
            operation="plan_week_generation",
            response=response,
            model=getattr(active_client, "model", None),
            result_status=(
                "contract_failed" if validated is not None else "schema_failed"
            ),
            quality_score=0.0,
            metadata={
                **telemetry_context,
                "stage": "draft",
                "week": backbone_week.week_number,
                "contract_issues": issues[:30],
                "recovery_reason": recovery_reason,
                "recovery_tier": "quality",
            },
        )

        # Hidden Gemini reasoning consumes max_output_tokens even when little
        # visible JSON is returned. Give the one bounded quality rewrite enough
        # total headroom and low reasoning so it can finish the approved week.
        active_client = _recover_plan_outage(
            response,
            timeout=PLAN_WEEK_RECOVERY_TIMEOUT_SECONDS,
            max_tokens=PLAN_WEEK_RECOVERY_MAX_TOKENS,
        ) or _plan_client(
            timeout=PLAN_WEEK_RECOVERY_TIMEOUT_SECONDS,
            max_tokens=PLAN_WEEK_RECOVERY_MAX_TOKENS,
            tier="quality",
            thinking_level="low",
        )
        failure_summary = " | ".join(
            issue.replace("\n", " ")[:180] for issue in issues[:8]
        )
        retry_prompt = user_prompt + (
            f"\n\nWEEK {backbone_week.week_number} QUALITY RECOVERY:\n"
            "The prior draft was cut off or invalid. Regenerate this week from "
            "scratch. Return JSON only with exactly one week; preserve the "
            "approved task order, types, task intent, and estimated hours; titles "
            "may only be clarified; keep prose concise while meeting the existing "
            "minimum detail; and do not include commentary."
            + (f"\nChecks to correct: {failure_summary}" if failure_summary else "")
        )
        validated, response = await active_client.generate_and_validate(
            system_prompt=system_prompt,
            user_prompt=retry_prompt,
            output_model=ExecutionPlanResponse,
            repair_on_failure=False,
        )
        response.retried = True
        issues = _issues(validated)

    await record_llm_response(
        operation="plan_week_generation",
        response=response,
        model=getattr(active_client, "model", None),
        result_status="schema_valid"
        if validated is not None and not issues
        else "failed",
        quality_score=1.0 if validated is not None and not issues else 0.0,
        metadata={
            **telemetry_context,
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
        generation_source="llm",
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
    learner_baseline_json: str = "",
    interview_transcript_json: str = "",
    comparison_summary: str = "",
    blueprint_markdown: str = "",
    previous_cycle_block: str = "",
    telemetry_context: dict | None = None,
    generation_checkpoint: dict | None = None,
    save_generation_checkpoint=None,
    on_generation_stage=None,
    recovery_response=None,
) -> PlanRoadmap:
    """
    Generate plan items using LLM.

    Generates one compact cycle backbone, then expands Week 1 only. Future
    weeks are enriched by the one-week-ahead worker before they unlock.

    Raises if both configured provider routes fail. Deterministic templates are
    reserved for explicit deterministic mode; silently publishing one from an
    LLM-mode outage would mislabel a degraded artifact as a personalized plan.
    """
    recovery_token = _plan_recovery_response.set(recovery_response)
    active_token = _plan_run_active.set(True)
    try:
        system_prompt = load_prompt("planner_system")
        user_prompt = render_prompt(
            load_prompt("plan_backbone_generate"),
            {
                "duration_weeks": str(duration_weeks),
                "user_goal": sanitize_untrusted_input(user_goal),
                "idol_name": idol_name,
                "hours_per_week": str(hours_per_week),
                "target_age": str(target_age or "null"),
                "user_context": sanitize_untrusted_input(user_context)
                if user_context
                else "",
                "idol_profile_json": idol_profile or {},
                "idol_persona_json": idol_persona or {},
                "idol_milestones_json": idol_milestones or [],
                "gaps_json": gaps or [],
                "readiness_by_gap_json": readiness_by_gap or {},
                "learner_baseline_json": sanitize_untrusted_input(learner_baseline_json)
                if learner_baseline_json
                else "",
                "interview_transcript_json": interview_transcript_json or "",
                "comparison_summary": sanitize_untrusted_input(comparison_summary)
                if comparison_summary
                else "",
                "blueprint_markdown": sanitize_untrusted_input(blueprint_markdown)
                if blueprint_markdown
                else "",
                "previous_cycle_block": sanitize_untrusted_input(previous_cycle_block)
                if previous_cycle_block
                else "",
            },
            prompt_name="plan_backbone_generate.txt",
            strict=True,
        )
        store = PlanCheckpointStore(generation_checkpoint, sha256_json({
            "version": "planning-checkpoints-v1", "system": system_prompt, "user": user_prompt,
            "provider": settings.llm_provider, "openlux_model": settings.openlux_model,
            "zai_model": settings.zai_model, "zai_quality_model": settings.zai_quality_model,
            "zai_fast_model": settings.zai_fast_model,
            "openlux_quality_model": settings.openlux_quality_model,
            "gemini_model": settings.gemini_model, "gemini_quality_model": settings.gemini_quality_model,
            "week_prompt": load_prompt("plan_week_generate"),
            "duration_weeks": duration_weeks, "hours_per_week": hours_per_week,
        }), save_generation_checkpoint)
        previous_backbone = store.load("backbone")
        if previous_backbone is not None:
            candidate = PlanBackboneResponse.model_validate(previous_backbone["payload"])
            candidate, _ = _normalize_backbone_workload(candidate, hours_per_week=hours_per_week)
            previous_issues = validate_plan_backbone(
                candidate, duration_weeks=duration_weeks, hours_per_week=hours_per_week
            )
            if previous_issues and (
                previous_backbone.get("repair_attempts", 0) >= 1
                or any(not re.match(r"week \d+\b", issue) for issue in previous_issues)
            ):
                # An explicit retry must be able to make progress after a
                # failed repair. Keeping an exhausted invalid stage made every
                # later attempt fail immediately without a provider call.
                logger.warning("Replacing an invalid exhausted backbone checkpoint")
                await store.discard("backbone", "week_one")
        backbone = await _checkpointed_backbone(
            store=store,
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            duration_weeks=duration_weeks,
            hours_per_week=hours_per_week,
            telemetry_context=telemetry_context,
        )
        # A stored draft can still require repair. Publish this milestone only
        # after the complete backbone validates, including checkpoint resumes.
        if on_generation_stage:
            await on_generation_stage("backbone_ready")
        saved_week = store.load("week_one")
        backbone_hash = sha256_json(backbone.model_dump(mode="json"))
        if saved_week is not None and saved_week.get("backbone_hash") == backbone_hash:
            first_week = PlanWeek.model_validate(saved_week["payload"])
            week_issues = validate_week_against_backbone(first_week, backbone.weeks[0])
            week_issues += validate_plan_contract(PlanGenerationResponse(weeks=[first_week],
                roadmap_thesis=backbone.roadmap_thesis, anti_goals=backbone.anti_goals),
                duration_weeks=1, hours_per_week=hours_per_week, start_week=1)
            if week_issues:
                raise ValueError("Saved first week violates its contract: " + "; ".join(week_issues))
        else:
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
                # The transcript already shaped the backbone. Repeating it in the
                # Week 1 expansion adds prompt latency without new information;
                # keep only the distilled decision artifacts.
                session_context="\n\n".join(
                    value
                    for value in (
                        ("Current learner placement: " + learner_baseline_json)
                        if learner_baseline_json else "",
                        comparison_summary,
                        blueprint_markdown,
                    )
                    if value
                ),
                telemetry_context=telemetry_context,
            )
            await store.put("week_one", first_week.model_dump(mode="json"), backbone_hash=backbone_hash)
        if on_generation_stage:
            await on_generation_stage("week_one_ready")
        return _roadmap_from_backbone(
            backbone,
            expanded_week=first_week,
            hours_per_week=hours_per_week,
        )

    except Exception as exc:
        logger.exception("LLM plan generation failed; refusing silent downgrade")
        raise RuntimeError(
            "Personalized plan generation failed across configured providers"
        ) from exc
    finally:
        _plan_recovery_response.reset(recovery_token)
        _plan_run_active.reset(active_token)


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
    - PLAN_GENERATOR_MODE=llm AND an LLM provider/key is configured
    - OR force_llm=True

    Otherwise generates deterministic template-based items.

    Returns:
        PlanRoadmap with roadmap_thesis, anti_goals, and items
    """
    use_llm = (
        settings.plan_generator_mode == "llm" and settings.llm_configured
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
            learner_baseline_json=kwargs.get("learner_baseline_json", ""),
            interview_transcript_json=kwargs.get("interview_transcript_json", ""),
            comparison_summary=kwargs.get("comparison_summary", ""),
            blueprint_markdown=kwargs.get("blueprint_markdown", ""),
            previous_cycle_block=previous_cycle_block,
            telemetry_context=kwargs.get("telemetry_context"),
            generation_checkpoint=kwargs.get("generation_checkpoint"),
            save_generation_checkpoint=kwargs.get("save_generation_checkpoint"),
            on_generation_stage=kwargs.get("on_generation_stage"),
            recovery_response=kwargs.get("recovery_response"),
        )
    else:
        logger.info("Generating plan using deterministic templates")
        return _generate_deterministic_items(
            weekly_hours,
            duration_weeks,
            idol_name=idol_name,
            user_goal=user_goal,
        )
