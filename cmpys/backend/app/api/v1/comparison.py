"""Comparison endpoint for user vs idol achievements."""
import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.idol import Idol
from app.models.idol_timeline import IdolTimelineEvent
from app.models.user import User
from app.models.user_achievement import UserAchievement
from app.schemas.comparison import (
    CategoryBreakdown,
    ComparisonMode,
    ComparisonResponse,
    MilestoneItem,
    UserAchievementItem,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/comparison", tags=["comparison"])


# Category weights for scoring
CATEGORY_WEIGHTS = {
    "career": 0.25,
    "learning": 0.20,
    "finance": 0.20,
    "impact": 0.20,
    "mindset": 0.10,
    "other": 0.05,
}


def _calculate_category_score(
    user_achievements: list[UserAchievement],
    idol_milestones: list[IdolTimelineEvent],
    category: str,
) -> tuple[float, int, int]:
    """
    Calculate score for a category.
    
    Returns: (percent, user_count, idol_count)
    """
    user_in_cat = [a for a in user_achievements if a.category.value == category]
    idol_in_cat = [m for m in idol_milestones if m.category == category]
    
    user_count = len(user_in_cat)
    idol_count = len(idol_in_cat)
    
    if idol_count == 0:
        # No idol milestones in this category - full credit if user has any
        return (100.0 if user_count > 0 else 0.0, user_count, idol_count)
    
    # Simple ratio: user achievements / idol milestones, capped at 100%
    percent = min(100.0, (user_count / idol_count) * 100)
    return (percent, user_count, idol_count)


def _match_achievements_to_milestones(
    user_achievements: list[UserAchievement],
    idol_milestones: list[IdolTimelineEvent],
) -> dict[str, list[str]]:
    """
    Simple matching: achievements match milestones in the same category.
    
    Returns: {achievement_id: [milestone_ids]}
    """
    matches: dict[str, list[str]] = {}
    
    # Group milestones by category
    milestones_by_cat: dict[str, list[IdolTimelineEvent]] = {}
    for m in idol_milestones:
        if m.category not in milestones_by_cat:
            milestones_by_cat[m.category] = []
        milestones_by_cat[m.category].append(m)
    
    for ach in user_achievements:
        cat = ach.category.value
        if cat in milestones_by_cat:
            # Match to all milestones in the same category (simple approach)
            matches[ach.id] = [m.id for m in milestones_by_cat[cat]]
        else:
            matches[ach.id] = []
    
    return matches


@router.get("", response_model=ComparisonResponse)
async def compare_to_idol(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    idolId: str = Query(..., description="Idol ID to compare against"),
    age: int = Query(..., ge=1, le=150, description="Target age for comparison"),
    mode: ComparisonMode = Query(ComparisonMode.UP_TO, description="Comparison mode"),
) -> ComparisonResponse:
    """
    Compare user achievements to idol milestones.
    
    This is a deterministic comparison (no LLM).
    
    - mode=exact: Only milestones at exactly the target age
    - mode=up_to: All milestones up to and including the target age
    """
    logger.info(f"[COMPARISON] Request: idolId={idolId}, age={age}, mode={mode.value}")
    
    # Load idol
    idol_stmt = select(Idol).where(Idol.id == idolId)
    idol_result = await db.execute(idol_stmt)
    idol = idol_result.scalar_one_or_none()
    
    if not idol:
        logger.warning(f"[COMPARISON] Idol not found: {idolId}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )
    
    logger.info(f"[COMPARISON] Idol found: {idol.name}, birth_date={idol.birth_date}")
    
    # First, check total milestones for this idol (for debugging)
    total_stmt = select(IdolTimelineEvent).where(IdolTimelineEvent.idol_id == idolId)
    total_result = await db.execute(total_stmt)
    all_milestones = list(total_result.scalars().all())
    logger.info(f"[COMPARISON] Total milestones for idol: {len(all_milestones)}")
    
    # Log age distribution
    age_dist = {}
    for m in all_milestones:
        age_key = m.age_at_event if m.age_at_event is not None else "NULL"
        age_dist[age_key] = age_dist.get(age_key, 0) + 1
    logger.debug(f"[COMPARISON] Age distribution: {age_dist}")
    
    # Load idol milestones at target age
    # Strategy: First try to get milestones with known ages, then consider NULL ages
    from sqlalchemy import or_
    from app.models.idol_achievement import IdolAchievement
    
    milestone_stmt = select(IdolTimelineEvent).where(
        IdolTimelineEvent.idol_id == idolId
    )
    
    if mode == ComparisonMode.EXACT:
        milestone_stmt = milestone_stmt.where(IdolTimelineEvent.age_at_event == age)
    else:  # UP_TO
        milestone_stmt = milestone_stmt.where(IdolTimelineEvent.age_at_event <= age)
    
    milestone_stmt = milestone_stmt.order_by(
        IdolTimelineEvent.age_at_event.nulls_last(),
        IdolTimelineEvent.importance_score.desc(),
    )
    
    milestone_result = await db.execute(milestone_stmt)
    idol_milestones = list(milestone_result.scalars().all())
    logger.info(f"[COMPARISON] Timeline events with age <= {age}: {len(idol_milestones)}")
    
    # If no milestones with known ages, try IdolAchievement table
    if not idol_milestones:
        logger.info(f"[COMPARISON] No timeline events with age, trying IdolAchievement table")
        
        ach_stmt = select(IdolAchievement).where(
            IdolAchievement.idol_id == idolId
        )
        if mode == ComparisonMode.EXACT:
            ach_stmt = ach_stmt.where(IdolAchievement.age_at_achievement == age)
        else:
            ach_stmt = ach_stmt.where(IdolAchievement.age_at_achievement <= age)
        
        ach_result = await db.execute(ach_stmt)
        achievements_with_age = list(ach_result.scalars().all())
        logger.info(f"[COMPARISON] Achievements with age <= {age}: {len(achievements_with_age)}")
        
        # Filter out birth events - they're not real achievements
        achievements_with_age = [
            a for a in achievements_with_age 
            if a.age_at_achievement != 0 and "birth" not in a.title.lower()
        ]
        logger.info(f"[COMPARISON] After filtering birth events: {len(achievements_with_age)}")
        
        if achievements_with_age:
            # Convert IdolAchievement to pseudo-timeline events
            class PseudoMilestone:
                def __init__(self, ach):
                    self.id = str(ach.id)
                    self.canonical_title = ach.title
                    self.canonical_description = ach.description
                    self.category = ach.category
                    self.age_at_event = ach.age_at_achievement
                    self.event_date = ach.achievement_date
                    self.importance_score = ach.importance_score or 0.5
            
            idol_milestones = [PseudoMilestone(a) for a in achievements_with_age]
        else:
            # Last resort: include early-career categories with NULL ages
            # Filter to categories likely to be early-career: learning, career starts
            logger.info(f"[COMPARISON] No age-based data, using early-career heuristic")
            
            early_career_categories = ["learning", "career", "finance"]
            
            ach_null_stmt = select(IdolAchievement).where(
                IdolAchievement.idol_id == idolId,
                IdolAchievement.age_at_achievement.is_(None),
                IdolAchievement.category.in_(early_career_categories)
            ).limit(10)  # Limit to prevent noise
            
            ach_null_result = await db.execute(ach_null_stmt)
            null_achievements = list(ach_null_result.scalars().all())
            
            # Filter out obvious later-life events by keywords
            def is_likely_early_career(title: str, desc: str) -> bool:
                later_keywords = ["pledged", "give away", "philanthrop", "succession", "retire", 
                                  "chairman", "ceo", "billion", "richest"]
                combined = (title + " " + (desc or "")).lower()
                return not any(kw in combined for kw in later_keywords)
            
            filtered = [a for a in null_achievements 
                       if is_likely_early_career(a.title, a.description)]
            
            logger.info(f"[COMPARISON] Filtered early-career achievements: {len(filtered)}")
            
            class PseudoMilestone:
                def __init__(self, ach):
                    self.id = str(ach.id)
                    self.canonical_title = ach.title
                    self.canonical_description = ach.description
                    self.category = ach.category
                    self.age_at_event = ach.age_at_achievement
                    self.event_date = ach.achievement_date
                    self.importance_score = ach.importance_score or 0.5
            
            idol_milestones = [PseudoMilestone(a) for a in filtered]
    
    logger.info(f"[COMPARISON] Final milestone count: {len(idol_milestones)}")
    
    # Load user achievements
    ach_stmt = select(UserAchievement).where(
        UserAchievement.user_id == current_user.id
    )
    ach_result = await db.execute(ach_stmt)
    user_achievements = list(ach_result.scalars().all())
    
    # Calculate category breakdowns
    category_breakdowns = []
    weighted_score = 0.0
    total_weight = 0.0
    
    for category, weight in CATEGORY_WEIGHTS.items():
        percent, user_count, idol_count = _calculate_category_score(
            user_achievements, idol_milestones, category
        )
        category_breakdowns.append(CategoryBreakdown(
            category=category,
            percent=percent,
            userCount=user_count,
            idolCount=idol_count,
        ))
        
        # Only count categories where idol has milestones
        if idol_count > 0:
            weighted_score += percent * weight
            total_weight += weight
    
    # Calculate overall score
    if total_weight > 0:
        overall_score = weighted_score / total_weight
    else:
        overall_score = 100.0 if user_achievements else 0.0
    
    # Match achievements to milestones
    matches = _match_achievements_to_milestones(user_achievements, idol_milestones)
    
    # Find missing milestones (ones not matched by any achievement)
    matched_milestone_ids = set()
    for ach_id, milestone_ids in matches.items():
        if milestone_ids:  # Only count if there were matches
            matched_milestone_ids.update(milestone_ids)
    
    missing_milestones = [m for m in idol_milestones if m.id not in matched_milestone_ids]
    
    # Build response items
    idol_milestone_items = [
        MilestoneItem(
            id=m.id,
            title=m.canonical_title,
            description=m.canonical_description,
            category=m.category,
            ageAtEvent=m.age_at_event,
            eventDate=m.event_date,
            importanceScore=m.importance_score,
        )
        for m in idol_milestones
    ]
    
    missing_items = [
        MilestoneItem(
            id=m.id,
            title=m.canonical_title,
            description=m.canonical_description,
            category=m.category,
            ageAtEvent=m.age_at_event,
            eventDate=m.event_date,
            importanceScore=m.importance_score,
        )
        for m in missing_milestones
    ]
    
    counted_achievements = [
        UserAchievementItem(
            id=a.id,
            title=a.title,
            category=a.category.value,
            achievementDate=a.achievement_date,
            matchedMilestones=matches.get(a.id, []),
        )
        for a in user_achievements
        if matches.get(a.id)  # Only include if matched something
    ]
    
    # Calculate completeness (based on idol data availability)
    completeness = 1.0 if idol_milestones else 0.0
    if idol_milestones:
        # Reduce completeness if many milestones lack age data
        milestones_with_age = sum(1 for m in idol_milestones if m.age_at_event is not None)
        completeness = milestones_with_age / len(idol_milestones)
    
    return ComparisonResponse(
        idolId=idol.id,
        idolName=idol.name,
        targetAge=age,
        mode=mode,
        overallScore=round(overall_score, 1),
        categoryBreakdown=category_breakdowns,
        missingVsIdol=missing_items,
        countedUserAchievements=counted_achievements,
        idolMilestonesAtAge=idol_milestone_items,
        completeness=round(completeness, 2),
        totalIdolMilestones=len(idol_milestones),
        totalUserAchievements=len(user_achievements),
        matchedCount=len(counted_achievements),
    )


# ============================================================================
# AI-ENHANCED COMPARISON
# ============================================================================

from app.core.config import settings
from app.schemas.comparison import ComparisonStrength, ComparisonGap, NextMilestone
import json
import openai
import os


async def _run_ai_comparison(
    idol_name: str,
    idol_field: str,
    idol_bio: str,
    idol_milestones_text: str,
    user_age: int,
    user_background: str,
    user_achievements_text: str,
    target_age: int,
) -> dict:
    """
    Run AI comparison using OpenAI.
    
    Returns parsed JSON response from the LLM.
    """
    # Read prompt template
    prompt_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))),
        "..", "prompts", "comparison_analyze.txt"
    )
    prompt_path = os.path.abspath(prompt_path)
    
    with open(prompt_path, "r") as f:
        prompt_template = f.read()
    
    # Fill in the template
    prompt = prompt_template.replace("{{idol_name}}", idol_name)
    prompt = prompt.replace("{{idol_field}}", idol_field or "Various")
    prompt = prompt.replace("{{idol_bio}}", idol_bio or "No biography available")
    prompt = prompt.replace("{{target_age}}", str(target_age))
    prompt = prompt.replace("{{idol_milestones}}", idol_milestones_text)
    prompt = prompt.replace("{{user_age}}", str(user_age))
    prompt = prompt.replace("{{user_background}}", user_background or "Not specified")
    prompt = prompt.replace("{{user_achievements}}", user_achievements_text)
    
    # Call OpenAI
    client = openai.AsyncOpenAI(api_key=settings.openai_api_key)
    
    response = await client.chat.completions.create(
        model=settings.openai_model,
        messages=[
            {
                "role": "system",
                "content": "You are an expert life coach. Return only valid JSON, no markdown code blocks."
            },
            {"role": "user", "content": prompt}
        ],
        temperature=0.7,
        max_tokens=4000,
    )
    
    content = response.choices[0].message.content.strip()
    
    # Clean up response - remove markdown code blocks if present
    if content.startswith("```"):
        lines = content.split("\n")
        content = "\n".join(lines[1:-1])
    
    return json.loads(content)


@router.get("/ai", response_model=ComparisonResponse)
async def compare_to_idol_ai(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    idolId: str = Query(..., description="Idol ID to compare against"),
    age: int = Query(..., ge=1, le=150, description="Target age for comparison"),
    mode: ComparisonMode = Query(ComparisonMode.UP_TO, description="Comparison mode"),
) -> ComparisonResponse:
    """
    AI-enhanced comparison between user achievements and idol milestones.
    
    This uses an LLM to provide realistic, qualitative analysis rather than
    simple count-based comparison.
    """
    logger.info(f"[AI_COMPARISON] Request: idolId={idolId}, age={age}, mode={mode.value}")
    
    # Check if LLM is configured
    if not settings.llm_configured or settings.llm_provider != "openai":
        logger.warning("[AI_COMPARISON] LLM not configured, falling back to basic comparison")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI comparison not available - LLM not configured",
        )
    
    # Load idol with full details
    idol_stmt = select(Idol).where(Idol.id == idolId)
    idol_result = await db.execute(idol_stmt)
    idol = idol_result.scalar_one_or_none()
    
    if not idol:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Idol not found")
    
    # Load idol milestones
    milestone_stmt = select(IdolTimelineEvent).where(
        IdolTimelineEvent.idol_id == idolId
    )
    if mode == ComparisonMode.UP_TO:
        milestone_stmt = milestone_stmt.where(IdolTimelineEvent.age_at_event <= age)
    else:
        milestone_stmt = milestone_stmt.where(IdolTimelineEvent.age_at_event == age)
    
    milestone_result = await db.execute(milestone_stmt)
    idol_milestones = list(milestone_result.scalars().all())
    
    # Format milestones for prompt
    milestones_text = ""
    for m in idol_milestones:
        age_str = f"Age {m.age_at_event}" if m.age_at_event else "Unknown age"
        milestones_text += f"- [{m.category.upper()}] {age_str}: {m.canonical_title}\n"
        if m.canonical_description:
            milestones_text += f"  {m.canonical_description[:200]}...\n"
    
    if not milestones_text:
        milestones_text = "No specific milestones recorded for this age range."
    
    # Load user achievements
    ach_stmt = select(UserAchievement).where(UserAchievement.user_id == current_user.id)
    ach_result = await db.execute(ach_stmt)
    user_achievements = list(ach_result.scalars().all())
    
    # Format user achievements for prompt
    achievements_text = ""
    for a in user_achievements:
        date_str = a.achievement_date.strftime("%Y") if a.achievement_date else "Unknown date"
        achievements_text += f"- [{a.category.value.upper()}] {date_str}: {a.title}\n"
        if a.notes:
            achievements_text += f"  Notes: {a.notes[:100]}...\n"
    
    if not achievements_text:
        achievements_text = "No achievements recorded yet."
    
    # Get user background
    user_background = ""
    if current_user.interests:
        user_background = f"Interests: {', '.join(current_user.interests)}"
    
    # Calculate user age
    user_age = age  # Use the target age for comparison
    if current_user.birth_date:
        from datetime import date
        today = date.today()
        user_age = today.year - current_user.birth_date.year
    
    try:
        # Run AI comparison
        ai_result = await _run_ai_comparison(
            idol_name=idol.name,
            idol_field=idol.primary_field or "",
            idol_bio=idol.ai_summary or idol.core_identity or "",
            idol_milestones_text=milestones_text,
            user_age=user_age,
            user_background=user_background,
            user_achievements_text=achievements_text,
            target_age=age,
        )
        
        logger.info(f"[AI_COMPARISON] AI returned overallScore: {ai_result.get('overallScore')}")
        
        # Parse AI response into schema objects
        category_breakdowns = []
        for cat_data in ai_result.get("categoryBreakdown", []):
            category_breakdowns.append(CategoryBreakdown(
                category=cat_data.get("category", "other"),
                percent=min(100, max(0, cat_data.get("score", 0))),
                userCount=0,  # AI doesn't count these
                idolCount=0,
                analysis=cat_data.get("analysis"),
                userStrengths=cat_data.get("userStrengths", []),
                gaps=cat_data.get("gaps", []),
                keyIdolMilestone=cat_data.get("keyIdolMilestone"),
                userBestMatch=cat_data.get("userBestMatch"),
            ))
        
        strengths = [
            ComparisonStrength(
                category=s.get("category", "other"),
                description=s.get("description", ""),
                achievementTitle=s.get("achievementTitle"),
            )
            for s in ai_result.get("strengths", [])
        ]
        
        gaps = [
            ComparisonGap(
                category=g.get("category", "other"),
                description=g.get("description", ""),
                idolMilestone=g.get("idolMilestone"),
                ageAtMilestone=g.get("ageAtMilestone"),
                suggestion=g.get("suggestion"),
            )
            for g in ai_result.get("gaps", [])
        ]
        
        next_milestone = None
        if ai_result.get("nextMilestone"):
            nm = ai_result["nextMilestone"]
            next_milestone = NextMilestone(
                title=nm.get("title", ""),
                description=nm.get("description", ""),
                estimatedTimeframe=nm.get("estimatedTimeframe"),
            )
        
        # Build idol milestone items
        idol_milestone_items = [
            MilestoneItem(
                id=m.id,
                title=m.canonical_title,
                description=m.canonical_description or "",
                category=m.category or "other",
                ageAtEvent=m.age_at_event,
                eventDate=m.event_date,
                importanceScore=m.importance_score or 0.5,
            )
            for m in idol_milestones
        ]
        
        # Build user achievement items
        user_achievement_items = [
            UserAchievementItem(
                id=a.id,
                title=a.title,
                category=a.category.value,
                achievementDate=a.achievement_date,
                matchedMilestones=[],
            )
            for a in user_achievements
        ]
        
        return ComparisonResponse(
            idolId=idol.id,
            idolName=idol.name,
            targetAge=age,
            mode=mode,
            overallScore=min(100, max(0, ai_result.get("overallScore", 0))),
            overallAnalysis=ai_result.get("overallAnalysis"),
            realisticPerspective=ai_result.get("realisticPerspective"),
            encouragement=ai_result.get("encouragement"),
            categoryBreakdown=category_breakdowns,
            strengths=strengths,
            gaps=gaps,
            missingVsIdol=[],  # AI provides qualitative gaps instead
            countedUserAchievements=user_achievement_items,
            idolMilestonesAtAge=idol_milestone_items,
            completeness=1.0 if idol_milestones else 0.0,
            totalIdolMilestones=len(idol_milestones),
            totalUserAchievements=len(user_achievements),
            matchedCount=len(user_achievements),
            nextMilestone=next_milestone,
            aiEnhanced=True,
        )
        
    except json.JSONDecodeError as e:
        logger.error(f"[AI_COMPARISON] Failed to parse AI response: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to parse AI comparison response",
        )
    except Exception as e:
        logger.exception(f"[AI_COMPARISON] Error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"AI comparison failed: {str(e)}",
        )
