"""
Plan generation service.

PROMPT MAPPING:
- generate_plan() -> extractor_system.txt + plan_generate.txt (LLM optional)

When PLAN_GENERATOR_MODE=llm and LLM is configured, uses LLM to generate plan items.
Otherwise, generates deterministic template-based items.
"""
import json
import logging
from dataclasses import dataclass

from app.core.config import settings
from app.models.plan import PlanItemType
from app.services.llm import get_llm_client
from app.services.llm.prompt_loader import load_prompt, render_prompt
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


# =============================================================================
# Deterministic Plan Generation (no LLM)
# =============================================================================


# Template items by category
PLAN_TEMPLATES = {
    "career": PlanItemData(
        title="Build Professional Portfolio",
        type=PlanItemType.PROJECT,
        description="Create or update your professional portfolio showcasing key projects and achievements",
        week_start=1,
        week_end=4,
        success_metric="Portfolio live and shared with network",
        estimated_hours=20,
    ),
    "learning": PlanItemData(
        title="Deep Study Session",
        type=PlanItemType.READING,
        description="Dedicate focused time to studying your field's fundamentals and recent developments",
        week_start=1,
        week_end=6,
        success_metric="Complete study notes and key takeaways document",
        estimated_hours=25,
    ),
    "finance": PlanItemData(
        title="Financial Analysis Practice",
        type=PlanItemType.PRACTICE,
        description="Practice analyzing financial statements or investment opportunities",
        week_start=3,
        week_end=8,
        success_metric="Complete 3 detailed analyses with written conclusions",
        estimated_hours=20,
    ),
    "impact": PlanItemData(
        title="Community Contribution",
        type=PlanItemType.PROJECT,
        description="Contribute to your community or professional network in a meaningful way",
        week_start=5,
        week_end=10,
        success_metric="Complete one significant contribution with documented impact",
        estimated_hours=15,
    ),
    "mindset": PlanItemData(
        title="Weekly Reflection Habit",
        type=PlanItemType.HABIT,
        description="Establish a weekly reflection practice to track progress and learnings",
        week_start=1,
        week_end=12,
        success_metric="12 weekly reflection entries completed",
        estimated_hours=6,
    ),
    "other": PlanItemData(
        title="Skill Development",
        type=PlanItemType.COURSE,
        description="Focus on developing a new skill relevant to your goals",
        week_start=2,
        week_end=8,
        success_metric="Demonstrate new skill through a practical project",
        estimated_hours=30,
    ),
}


def _generate_deterministic_items(
    gaps: list[str],
    duration_weeks: int,
    weekly_hours: int,
) -> list[PlanItemData]:
    """
    Generate deterministic plan items based on missing categories.
    
    NO LLM USED - pure template-based generation.
    """
    items = []
    total_hours = duration_weeks * weekly_hours
    
    # Scale hours proportionally
    hours_per_item = total_hours // max(1, len(gaps))
    
    for category in gaps[:6]:  # Max 6 items
        template = PLAN_TEMPLATES.get(category, PLAN_TEMPLATES["other"])
        
        # Adjust weeks to fit duration
        week_start = min(template.week_start, duration_weeks)
        week_end = min(template.week_end, duration_weeks)
        
        items.append(PlanItemData(
            title=template.title,
            type=template.type,
            description=template.description,
            week_start=week_start,
            week_end=week_end,
            success_metric=template.success_metric,
            estimated_hours=min(template.estimated_hours, hours_per_item),
        ))
    
    return items


# =============================================================================
# LLM Plan Generation
# PROMPTS: extractor_system.txt, plan_generate.txt
# =============================================================================


async def _generate_llm_items(
    gaps: list[str],
    duration_weeks: int,
    weekly_hours: int,
    target_age: int = 25,
    user_profile: dict | None = None,
    idol_profile: dict | None = None,
    idol_name: str = "the idol",
    idol_milestones: list[dict] | None = None,
    idol_persona: dict | None = None,
    readiness_by_gap: dict | None = None,
    allowed_resources: list[dict] | None = None,
) -> list[PlanItemData]:
    """
    Generate plan items using LLM.
    
    PROMPTS USED:
    - System: extractor_system.txt
    - User: plan_generate.txt
    
    Falls back to deterministic if LLM fails.
    """
    client = get_llm_client()
    
    try:
        # Load prompt templates
        system_prompt = load_prompt("extractor_system")
        user_template = load_prompt("plan_generate")
        
        # Prepare variables (render_prompt handles json.dumps for dict/list)
        user_profile_data = user_profile or {"weekly_hours": weekly_hours}
        
        # Render user prompt with strict validation
        user_prompt = render_prompt(user_template, {
            "idol_name": idol_name,
            "user_profile_json": user_profile_data,
            "idol_profile_json": idol_profile or {},
            "idol_persona_json": idol_persona or {},
            "idol_milestones_json": idol_milestones or [],
            "target_age": str(target_age),
            "gaps_json": gaps,
            "readiness_by_gap_json": readiness_by_gap or {},
            "allowed_resources_json": allowed_resources or [],
        }, prompt_name="plan_generate.txt", strict=True)
        
        validated, response = await client.generate_and_validate(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            output_model=PlanGenerationResponse,
            repair_on_failure=True,
        )
        
        if validated and validated.plan.items:
            result_items = []
            for item in validated.plan.items:
                # Build meta_json from extra LLM fields (for detail generation)
                meta = {}
                if item.detail_tags:
                    meta["detail_tags"] = item.detail_tags
                if item.primary_gap:
                    meta["primary_gap"] = item.primary_gap
                if item.suggested_queries:
                    meta["suggested_queries"] = item.suggested_queries
                if item.idol_parallel:
                    meta["idol_parallel"] = item.idol_parallel
                if item.difficulty:
                    meta["difficulty"] = item.difficulty.value
                if item.confidence:
                    meta["confidence"] = item.confidence
                
                result_items.append(PlanItemData(
                    title=item.title,
                    type=PlanItemType(item.type.value),
                    description=item.description,
                    week_start=item.week_start,
                    week_end=item.week_end,
                    success_metric=item.success_metric,
                    estimated_hours=item.estimated_hours,
                    resource_title=item.resource.title if item.resource.kind.value != "none" else None,
                    resource_url=item.resource.url if item.resource.kind.value != "none" else None,
                    meta_json=meta if meta else None,
                ))
            return result_items
            
    except Exception as e:
        logger.exception(f"LLM plan generation failed: {e}, falling back to deterministic")
    
    # Fall back to deterministic
    return _generate_deterministic_items(gaps, duration_weeks, weekly_hours)


# =============================================================================
# Main Entry Point
# =============================================================================


async def generate_plan(
    gaps: list[str],
    duration_weeks: int = 12,
    weekly_hours: int = 10,
    target_age: int = 25,
    user_profile: dict | None = None,
    idol_profile: dict | None = None,
    idol_name: str = "the idol",
    idol_milestones: list[dict] | None = None,
    idol_persona: dict | None = None,
    readiness_by_gap: dict | None = None,
    allowed_resources: list[dict] | None = None,
    force_llm: bool = False,
) -> list[PlanItemData]:
    """
    Generate plan items to close gaps vs idol.
    
    PROMPTS USED (when LLM mode):
    - System: extractor_system.txt
    - User: plan_generate.txt
    
    LLM is used if:
    - PLAN_GENERATOR_MODE=llm AND LLM_PROVIDER=openai AND API key is set
    - OR force_llm=True
    
    Otherwise generates deterministic template-based items.
    
    Args:
        gaps: List of category gaps (e.g., ["career", "finance"])
        duration_weeks: Plan duration in weeks
        weekly_hours: Weekly time commitment in hours
        target_age: User's target age for plan
        user_profile: User profile data for LLM context (enriched after intake)
        idol_profile: Idol profile data for LLM context
        idol_name: Name of the idol for personalized plans
        idol_milestones: List of idol's milestones for context
        idol_persona: Idol persona for era/worldview context
        readiness_by_gap: User readiness levels per category (from intake normalization)
        allowed_resources: List of allowed resources for plan items
        force_llm: Force LLM usage (raises error if not configured)
        
    Returns:
        List of PlanItemData objects
    """
    use_llm = (
        settings.plan_generator_mode == "llm" and 
        settings.llm_provider == "openai" and 
        settings.llm_configured
    ) or force_llm
    
    if use_llm:
        if force_llm and not settings.llm_configured:
            raise ValueError("LLM not configured but force_llm=True")
        
        logger.info(f"Generating plan using LLM for {idol_name}")
        return await _generate_llm_items(
            gaps=gaps,
            duration_weeks=duration_weeks,
            weekly_hours=weekly_hours,
            target_age=target_age,
            user_profile=user_profile,
            idol_profile=idol_profile,
            idol_name=idol_name,
            idol_milestones=idol_milestones,
            idol_persona=idol_persona,
            readiness_by_gap=readiness_by_gap,
            allowed_resources=allowed_resources,
        )
    else:
        logger.info("Generating plan using deterministic templates")
        return _generate_deterministic_items(gaps, duration_weeks, weekly_hours)
