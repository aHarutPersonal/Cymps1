"""
Intake questionnaire API endpoints.

PROMPT MAPPING:
- POST /intake/start
  - Prompts: intake_questions_generate.txt
  - LLM: REQUIRED for generating questions

- POST /intake/{session_id}/finish
  - Prompts: intake_answers_normalize.txt
  - LLM: REQUIRED for normalizing answers

- Other endpoints: NO LLM (database operations only)
"""
import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.config import settings
from app.core.db import get_db
from app.models.idol import Idol
from app.models.idol_persona import IdolPersona
from app.models.idol_profile import IdolProfile
from app.models.idol_timeline import IdolTimelineEvent
from app.models.intake import IntakeAnswer, IntakeSession, IntakeSessionStatus as IntakeStatusEnum
from app.models.user import User
from app.models.user_achievement import AchievementCategory as UserAchievementCategory, UserAchievement
from app.models.user_profile import UserProfile
from app.schemas.intake import (
    AnswerDetail,
    IntakeAnswerRequest,
    IntakeAnswerResponse,
    IntakeFinishResponse,
    IntakeNormalizeResponse,
    IntakeSessionResponse,
    IntakeSessionStatus,
    IntakeStartRequest,
    IntakeStartResponse,
    Question,
    QuestionsGenerateResponse,
)
from app.services.llm import get_llm_client
from app.services.llm.prompt_loader import load_prompt, render_prompt
from app.services.planning import generate_plan

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/intake", tags=["intake"])


# =============================================================================
# Helper Functions
# =============================================================================


async def _verify_session_ownership(
    session_id: str,
    user: User,
    db: AsyncSession,
) -> IntakeSession:
    """Verify that the session exists and belongs to the current user."""
    stmt = (
        select(IntakeSession)
        .options(selectinload(IntakeSession.answers))
        .where(IntakeSession.id == session_id)
    )
    result = await db.execute(stmt)
    session = result.scalar_one_or_none()
    
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Intake session not found",
        )
    
    if session.user_id != user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this session",
        )
    
    return session


def _questions_from_json(questions_json: dict | list | None) -> list[Question]:
    """Convert stored questions JSON to Question models."""
    if not questions_json:
        return []
    
    # Handle both list and dict with "questions" key
    if isinstance(questions_json, dict):
        questions_list = questions_json.get("questions", [])
    else:
        questions_list = questions_json
    
    return [Question(**q) for q in questions_list]


async def _generate_questions(
    idol: Idol,
    idol_profile: IdolProfile | None,
    idol_persona: IdolPersona | None,
    milestones: list[IdolTimelineEvent],
    user: User,
    target_age: int,
) -> list[Question]:
    """Generate intake questions using LLM."""
    if not settings.llm_configured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LLM not configured. Cannot generate intake questions.",
        )
    
    client = get_llm_client()
    
    # Prepare inputs as dicts - render_prompt will auto-convert to JSON
    idol_profile_dict = {}
    if idol_profile:
        idol_profile_dict = {
            "display_name": idol_profile.display_name,
            "short_description": idol_profile.short_description,
            "domains": idol_profile.domains,
            "primary_roles": idol_profile.primary_roles,
            "notable_themes": idol_profile.notable_themes,
        }
    
    idol_persona_dict = {}
    if idol_persona:
        idol_persona_dict = {
            "voice_style": idol_persona.voice_style,
            "principles": idol_persona.principles,
            "topics_of_strength": idol_persona.topics_of_strength,
            "era_context": idol_persona.era_context or "contemporary",
            "default_frameworks": idol_persona.default_frameworks or [],
        }
    
    milestones_list = [
        {
            "title": m.canonical_title,
            "age": m.age_at_event,
            "category": m.category,
        }
        for m in milestones[:10]
        if m.age_at_event is not None
    ]
    
    user_profile_dict = {
        "age": target_age,
    }
    if user.profile:
        user_profile_dict["interests"] = user.profile.interests or []
    
    # Load and render prompt with validation
    # render_prompt auto-converts dict/list params to JSON strings
    template = load_prompt("intake_questions_generate")
    prompt = render_prompt(
        template,
        {
            "idol_name": idol.name,
            "idol_persona_json": idol_persona_dict,  # Will be auto-serialized
            "idol_profile_json": idol_profile_dict,  # Will be auto-serialized
            "milestones_json": milestones_list,      # Will be auto-serialized
            "user_profile_json": user_profile_dict,  # Will be auto-serialized
            "target_age": target_age,
            "limit": 10,
        },
        prompt_name="intake_questions_generate.txt",  # Enables validation
        strict=True,
    )
    
    system_prompt = load_prompt("extractor_system")
    
    logger.info(f"[INTAKE] Generating questions for idol={idol.name}, user={user.id}")
    
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=prompt,
        output_model=QuestionsGenerateResponse,
        repair_on_failure=True,
    )
    
    if validated:
        logger.info(f"[INTAKE] Generated {len(validated.questions)} questions")
        return validated.questions
    
    logger.error(f"[INTAKE] Failed to generate questions: {response.error}")
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Failed to generate intake questions",
    )


# =============================================================================
# API Endpoints
# =============================================================================


@router.post("/start", response_model=IntakeStartResponse, status_code=status.HTTP_201_CREATED)
async def start_intake(
    data: IntakeStartRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IntakeStartResponse:
    """
    Start a new intake session for an idol.
    
    PROMPT FILES USED:
    - intake_questions_generate.txt
    
    LLM USAGE: REQUIRED
    - Generates personalized questions based on idol and user context
    """
    # Load idol
    idol_stmt = select(Idol).where(Idol.id == data.idol_id)
    idol_result = await db.execute(idol_stmt)
    idol = idol_result.scalar_one_or_none()
    
    if not idol:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )
    
    # Load idol profile and persona
    profile_stmt = select(IdolProfile).where(IdolProfile.idol_id == data.idol_id)
    profile_result = await db.execute(profile_stmt)
    idol_profile = profile_result.scalar_one_or_none()
    
    persona_stmt = select(IdolPersona).where(IdolPersona.idol_id == data.idol_id)
    persona_result = await db.execute(persona_stmt)
    idol_persona = persona_result.scalar_one_or_none()
    
    # Load milestones
    target_age = data.target_age or 30
    milestone_stmt = select(IdolTimelineEvent).where(
        IdolTimelineEvent.idol_id == data.idol_id,
        IdolTimelineEvent.age_at_event <= target_age,
    )
    milestone_result = await db.execute(milestone_stmt)
    milestones = list(milestone_result.scalars().all())
    
    # Generate questions
    questions = await _generate_questions(
        idol=idol,
        idol_profile=idol_profile,
        idol_persona=idol_persona,
        milestones=milestones,
        user=current_user,
        target_age=target_age,
    )
    
    # Create session
    session = IntakeSession(
        user_id=current_user.id,
        idol_id=data.idol_id,
        status=IntakeStatusEnum.IN_PROGRESS,
        questions_json={"questions": [q.model_dump() for q in questions]},
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    
    logger.info(f"[INTAKE] Created session {session.id} for user {current_user.id}, idol {idol.name}")
    
    return IntakeStartResponse(
        session_id=session.id,
        questions=questions,
    )


@router.post("/{session_id}/answer", response_model=IntakeAnswerResponse)
async def submit_answer(
    session_id: str,
    data: IntakeAnswerRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IntakeAnswerResponse:
    """
    Submit an answer to a question in the intake session.
    
    LLM USAGE: NONE (database operation only)
    """
    session = await _verify_session_ownership(session_id, current_user, db)
    
    if session.status == IntakeStatusEnum.COMPLETED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This intake session has already been completed",
        )
    
    # Check question exists
    questions = _questions_from_json(session.questions_json)
    question_ids = {q.id for q in questions}
    
    if data.question_id not in question_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Question '{data.question_id}' not found in this session",
        )
    
    # Check if answer already exists (update or create)
    existing_answer = None
    for ans in session.answers:
        if ans.question_id == data.question_id:
            existing_answer = ans
            break
    
    if existing_answer:
        existing_answer.answer_json = {"value": data.answer}
    else:
        answer = IntakeAnswer(
            session_id=session.id,
            question_id=data.question_id,
            answer_json={"value": data.answer},
        )
        db.add(answer)
    
    await db.commit()
    
    logger.debug(f"[INTAKE] Saved answer for question {data.question_id} in session {session_id}")
    
    return IntakeAnswerResponse(ok=True)


async def _normalize_answers(
    idol: Idol,
    idol_profile: IdolProfile | None,
    idol_persona: IdolPersona | None,
    milestones: list[IdolTimelineEvent],
    user: User,
    questions: list[Question],
    answers: list[IntakeAnswer],
) -> IntakeNormalizeResponse:
    """Normalize intake answers using LLM."""
    if not settings.llm_configured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LLM not configured. Cannot normalize intake answers.",
        )
    
    client = get_llm_client()
    
    # Prepare idol data
    idol_profile_dict = {}
    if idol_profile:
        idol_profile_dict = {
            "display_name": idol_profile.display_name,
            "short_description": idol_profile.short_description,
            "domains": idol_profile.domains,
            "primary_roles": idol_profile.primary_roles,
            "notable_themes": idol_profile.notable_themes,
        }
    
    idol_persona_dict = {}
    if idol_persona:
        idol_persona_dict = {
            "voice_style": idol_persona.voice_style,
            "principles": idol_persona.principles,
            "topics_of_strength": idol_persona.topics_of_strength,
            "era_context": idol_persona.era_context or "contemporary",
            "default_frameworks": idol_persona.default_frameworks or [],
        }
    
    milestones_list = [
        {"title": m.canonical_title, "age": m.age_at_event, "category": m.category}
        for m in milestones[:10]
        if m.age_at_event is not None
    ]
    
    # Current user profile
    user_profile_dict = {}
    if user.profile:
        user_profile_dict = {
            "full_name": user.profile.full_name,
            "birth_date": user.profile.birth_date.isoformat() if user.profile.birth_date else None,
            "weekly_hours": user.profile.weekly_hours,
            "goals": user.profile.goals or [],
            "interests": user.profile.interests or [],
        }
    
    # Questions and answers
    questions_list = [q.model_dump() for q in questions]
    answers_dict = {
        ans.question_id: ans.answer_json.get("value") if isinstance(ans.answer_json, dict) else ans.answer_json
        for ans in answers
    }
    
    # Load and render prompt
    template = load_prompt("intake_answers_normalize")
    prompt = render_prompt(
        template,
        {
            "idol_name": idol.name,
            "idol_persona_json": idol_persona_dict,
            "idol_profile_json": idol_profile_dict,
            "milestones_json": milestones_list,
            "user_profile_json": user_profile_dict,
            "questions_json": questions_list,
            "answers_json": answers_dict,
        },
        prompt_name="intake_answers_normalize.txt",
        strict=True,
    )
    
    system_prompt = load_prompt("extractor_system")
    
    logger.info(f"[INTAKE] Normalizing answers for idol={idol.name}, user={user.id}")
    
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=prompt,
        output_model=IntakeNormalizeResponse,
        repair_on_failure=True,
    )
    
    if validated:
        logger.info(f"[INTAKE] Normalized {len(validated.structured_achievements)} achievements")
        return validated
    
    logger.error(f"[INTAKE] Failed to normalize answers: {response.error}")
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Failed to normalize intake answers",
    )


async def _apply_profile_patch(
    db: AsyncSession,
    user: User,
    patch: "UserProfilePatch",
    readiness: "ReadinessByGap",
) -> UserProfile:
    """Apply the profile patch to the user's profile."""
    from app.schemas.intake import UserProfilePatch, ReadinessByGap
    
    # Get or create user profile
    if not user.profile:
        profile = UserProfile(user_id=user.id)
        db.add(profile)
        await db.flush()
    else:
        profile = user.profile
    
    # Apply patch fields (only update if value is not None/empty)
    if patch.weekly_hours is not None:
        profile.weekly_hours = patch.weekly_hours
    if patch.goals:
        profile.goals = patch.goals
    if patch.interests:
        profile.interests = patch.interests
    if patch.domains:
        profile.domains = patch.domains
    if patch.constraints:
        profile.constraints = patch.constraints
    if patch.learning_preferences:
        profile.learning_preferences = patch.learning_preferences
    if patch.skills:
        profile.skills = [s.model_dump() for s in patch.skills]
    if patch.achievements_raw:
        profile.achievements_raw = patch.achievements_raw
    
    # Store readiness by gap
    profile.readiness_by_gap = readiness.model_dump()
    
    await db.commit()
    await db.refresh(profile)
    
    return profile


async def _store_structured_achievements(
    db: AsyncSession,
    user: User,
    achievements: list["StructuredAchievement"],
) -> list[UserAchievement]:
    """Store structured achievements as UserAchievement records."""
    from datetime import datetime
    from app.schemas.intake import StructuredAchievement
    
    stored = []
    for ach in achievements:
        # Parse date if provided
        ach_date = None
        if ach.date:
            try:
                ach_date = datetime.strptime(ach.date, "%Y-%m-%d").date()
            except ValueError:
                pass
        
        # Map category
        try:
            category = UserAchievementCategory(ach.category.value)
        except ValueError:
            category = UserAchievementCategory.OTHER
        
        user_ach = UserAchievement(
            user_id=user.id,
            title=ach.title,
            category=category,
            achievement_date=ach_date,
            notes=ach.description,
        )
        db.add(user_ach)
        stored.append(user_ach)
    
    await db.commit()
    return stored


@router.post("/{session_id}/finish", response_model=IntakeFinishResponse)
async def finish_intake(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IntakeFinishResponse:
    """
    Finish the intake session and trigger answer normalization + plan generation.
    
    Pipeline:
    1. Load session questions + answers
    2. Call LLM with intake_answers_normalize.txt
    3. Parse: user_profile_patch, structured_achievements, readiness_by_gap
    4. Persist patch into user profile + store achievements
    5. Trigger plan generation and return job_id
    
    PROMPT FILES USED:
    - intake_answers_normalize.txt
    - plan_generate.txt (via generate_plan)
    
    LLM USAGE: REQUIRED
    """
    session = await _verify_session_ownership(session_id, current_user, db)
    
    if session.status == IntakeStatusEnum.COMPLETED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This intake session has already been completed",
        )
    
    # Check required questions are answered
    questions = _questions_from_json(session.questions_json)
    required_ids = {q.id for q in questions if q.required}
    answered_ids = {ans.question_id for ans in session.answers}
    
    missing = required_ids - answered_ids
    if missing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Required questions not answered: {', '.join(missing)}",
        )
    
    # Load idol data
    idol_stmt = select(Idol).where(Idol.id == session.idol_id)
    idol_result = await db.execute(idol_stmt)
    idol = idol_result.scalar_one_or_none()
    
    if not idol:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )
    
    # Load idol profile and persona
    profile_stmt = select(IdolProfile).where(IdolProfile.idol_id == session.idol_id)
    profile_result = await db.execute(profile_stmt)
    idol_profile = profile_result.scalar_one_or_none()
    
    persona_stmt = select(IdolPersona).where(IdolPersona.idol_id == session.idol_id)
    persona_result = await db.execute(persona_stmt)
    idol_persona = persona_result.scalar_one_or_none()
    
    # Load milestones
    milestone_stmt = select(IdolTimelineEvent).where(
        IdolTimelineEvent.idol_id == session.idol_id
    )
    milestone_result = await db.execute(milestone_stmt)
    milestones = list(milestone_result.scalars().all())
    
    # Step 2: Normalize answers with LLM
    logger.info(f"[INTAKE] Step 2: Normalizing answers for session {session_id}")
    normalized = await _normalize_answers(
        idol=idol,
        idol_profile=idol_profile,
        idol_persona=idol_persona,
        milestones=milestones,
        user=current_user,
        questions=questions,
        answers=list(session.answers),
    )
    
    # Step 3 & 4: Persist profile patch and achievements
    logger.info(f"[INTAKE] Step 3-4: Persisting profile patch and achievements")
    await _apply_profile_patch(
        db=db,
        user=current_user,
        patch=normalized.user_profile_patch,
        readiness=normalized.readiness_by_gap,
    )
    
    if normalized.structured_achievements:
        await _store_structured_achievements(
            db=db,
            user=current_user,
            achievements=normalized.structured_achievements,
        )
    
    # Mark session as completed
    session.status = IntakeStatusEnum.COMPLETED
    await db.commit()
    
    # Step 5: Trigger plan generation
    # Determine gaps from readiness
    readiness_dict = normalized.readiness_by_gap.model_dump()
    gaps = [cat for cat, level in readiness_dict.items() if level in ("beginner", "intermediate")]
    if not gaps:
        gaps = ["learning", "career", "mindset"]  # Default gaps
    
    # Prepare user profile for plan generation
    user_profile_for_plan = {
        "weekly_hours": normalized.user_profile_patch.weekly_hours or 6,
        "goals": normalized.user_profile_patch.goals,
        "interests": normalized.user_profile_patch.interests,
        "constraints": normalized.user_profile_patch.constraints,
        "skills": [s.model_dump() for s in normalized.user_profile_patch.skills],
        "readiness_by_gap": readiness_dict,
    }
    
    # Prepare idol data for plan generation
    idol_profile_for_plan = {
        "name": idol.name,
        "domain": idol.domain,
    }
    if idol_profile:
        idol_profile_for_plan.update({
            "display_name": idol_profile.display_name,
            "domains": idol_profile.domains,
            "notable_themes": idol_profile.notable_themes,
        })
    
    idol_persona_for_plan = {}
    if idol_persona:
        idol_persona_for_plan = {
            "voice_style": idol_persona.voice_style,
            "principles": idol_persona.principles,
            "era_context": idol_persona.era_context or "contemporary",
            "default_frameworks": idol_persona.default_frameworks or [],
        }
    
    milestones_for_plan = [
        {"title": m.canonical_title, "age": m.age_at_event, "category": m.category}
        for m in milestones[:15]
        if m.age_at_event is not None
    ]
    
    # Calculate target age from user birth date or default to 25
    target_age = 25
    if current_user.profile and current_user.profile.birth_date:
        from datetime import date
        today = date.today()
        target_age = today.year - current_user.profile.birth_date.year
    
    logger.info(f"[INTAKE] Step 5: Generating plan with gaps={gaps}, target_age={target_age}")
    
    # Generate plan (this uses LLM internally)
    from app.models.plan import Plan, PlanItem, PlanItemType
    
    roadmap = await generate_plan(
        gaps=gaps,
        duration_weeks=12,
        weekly_hours=normalized.user_profile_patch.weekly_hours or 6,
        target_age=target_age,
        user_profile=user_profile_for_plan,
        idol_profile=idol_profile_for_plan,
        idol_name=idol.name,
        idol_milestones=milestones_for_plan,
        idol_persona=idol_persona_for_plan,
        readiness_by_gap=readiness_dict,
        allowed_resources=[],  # No resources by default; can be extended later
    )
    
    # Create plan in database
    plan = Plan(
        user_id=current_user.id,
        idol_id=session.idol_id,
        target_age=target_age,
        duration_weeks=12,
        weekly_hours=normalized.user_profile_patch.weekly_hours or 6,
        roadmap_json={
            "roadmap_thesis": roadmap.roadmap_thesis,
            "anti_goals": roadmap.anti_goals,
        }
    )
    db.add(plan)
    await db.flush()
    
    for item_data in roadmap.items:
        item = PlanItem(
            plan_id=plan.id,
            title=item_data.title,
            type=item_data.type,
            description=item_data.description,
            week_start=item_data.week_start,
            week_end=item_data.week_end,
            success_metric=item_data.success_metric,
            estimated_hours=item_data.estimated_hours,
            resource_title=item_data.resource_title,
            resource_url=item_data.resource_url,
            meta_json=item_data.meta_json,  # Store extra LLM fields for detail generation
        )
        db.add(item)
    
    await db.commit()
    
    logger.info(f"[INTAKE] Finished session {session_id}, created plan {plan.id}")
    
    return IntakeFinishResponse(job_id=plan.id)


@router.get("/{session_id}", response_model=IntakeSessionResponse)
async def get_session(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IntakeSessionResponse:
    """
    Get the current state of an intake session.
    
    LLM USAGE: NONE (database query only)
    """
    session = await _verify_session_ownership(session_id, current_user, db)
    
    questions = _questions_from_json(session.questions_json)
    
    answers = [
        AnswerDetail(
            question_id=ans.question_id,
            answer=ans.answer_json.get("value") if isinstance(ans.answer_json, dict) else ans.answer_json,
            created_at=ans.created_at,
        )
        for ans in session.answers
    ]
    
    return IntakeSessionResponse(
        session_id=session.id,
        idol_id=session.idol_id,
        status=IntakeSessionStatus(session.status.value),
        questions=questions,
        answers=answers,
        created_at=session.created_at,
        updated_at=session.updated_at,
    )


# =============================================================================
# Achievement Intake Endpoints
# =============================================================================


async def _generate_achievement_questions(
    idol: Idol,
    idol_profile: IdolProfile | None,
    milestones: list[IdolTimelineEvent],
    user_age: int,
) -> list[Question]:
    """Generate achievement-specific questions using LLM."""
    if not settings.llm_configured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LLM not configured. Cannot generate achievement questions.",
        )
    
    client = get_llm_client()
    
    idol_profile_dict = {}
    if idol_profile:
        idol_profile_dict = {
            "display_name": idol_profile.display_name,
            "short_description": idol_profile.short_description,
            "domains": idol_profile.domains,
            "primary_roles": idol_profile.primary_roles,
            "notable_themes": idol_profile.notable_themes,
        }
    
    milestones_list = [
        {
            "title": m.canonical_title,
            "age": m.age_at_event,
            "category": m.category,
        }
        for m in milestones[:15]
        if m.age_at_event is not None
    ]
    
    template = load_prompt("achievement_intake_generate")
    prompt = render_prompt(
        template,
        {
            "idol_name": idol.name,
            "idol_profile_json": idol_profile_dict,
            "milestones_json": milestones_list,
            "user_age": user_age,
            "limit": 6,
        },
        prompt_name="achievement_intake_generate.txt",
        strict=True,
    )
    
    system_prompt = load_prompt("extractor_system")
    
    logger.info(f"[ACH_INTAKE] Generating achievement questions for idol={idol.name}")
    
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=prompt,
        output_model=QuestionsGenerateResponse,
        repair_on_failure=True,
    )
    
    if validated:
        logger.info(f"[ACH_INTAKE] Generated {len(validated.questions)} achievement questions")
        return validated.questions
    
    logger.error(f"[ACH_INTAKE] Failed to generate questions: {response.error}")
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Failed to generate achievement questions",
    )


@router.post("/achievement-intake", response_model=IntakeStartResponse, status_code=status.HTTP_201_CREATED)
async def start_achievement_intake(
    data: IntakeStartRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> IntakeStartResponse:
    """
    Start an achievement-specific intake session for an idol.
    
    Generates questions focused on the user's existing achievements,
    mapped to the idol's milestone categories for later comparison.
    
    PROMPT FILES USED:
    - achievement_intake_generate.txt
    
    LLM USAGE: REQUIRED
    """
    # Load idol
    idol_stmt = select(Idol).where(Idol.id == data.idol_id)
    idol_result = await db.execute(idol_stmt)
    idol = idol_result.scalar_one_or_none()
    
    if not idol:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )
    
    # Load idol profile
    profile_stmt = select(IdolProfile).where(IdolProfile.idol_id == data.idol_id)
    profile_result = await db.execute(profile_stmt)
    idol_profile = profile_result.scalar_one_or_none()
    
    # Load milestones up to user age
    target_age = data.target_age or 30
    milestone_stmt = select(IdolTimelineEvent).where(
        IdolTimelineEvent.idol_id == data.idol_id,
        IdolTimelineEvent.age_at_event <= target_age,
    )
    milestone_result = await db.execute(milestone_stmt)
    milestones = list(milestone_result.scalars().all())
    
    # Generate achievement questions
    questions = await _generate_achievement_questions(
        idol=idol,
        idol_profile=idol_profile,
        milestones=milestones,
        user_age=target_age,
    )
    
    # Create session (reuse IntakeSession model with a marker)
    session = IntakeSession(
        user_id=current_user.id,
        idol_id=data.idol_id,
        status=IntakeStatusEnum.IN_PROGRESS,
        questions_json={"questions": [q.model_dump() for q in questions]},
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    
    logger.info(f"[ACH_INTAKE] Created session {session.id} for user {current_user.id}, idol {idol.name}")
    
    return IntakeStartResponse(
        session_id=session.id,
        questions=questions,
    )


@router.post("/achievement-intake/{session_id}/finish")
async def finish_achievement_intake(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> dict:
    """
    Finish the achievement intake: extract achievements from answers
    and store them as UserAchievement records.
    
    LLM USAGE: NONE (simple extraction from structured answers)
    """
    session = await _verify_session_ownership(session_id, current_user, db)
    
    if session.status == IntakeStatusEnum.COMPLETED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This session has already been completed",
        )
    
    # Extract achievements from answers
    questions = _questions_from_json(session.questions_json)
    answers_by_qid = {
        ans.question_id: (
            ans.answer_json.get("value") if isinstance(ans.answer_json, dict) else ans.answer_json
        )
        for ans in session.answers
    }
    
    from datetime import datetime
    
    stored_count = 0
    for q in questions:
        answer_text = answers_by_qid.get(q.id)
        if not answer_text or (isinstance(answer_text, str) and not answer_text.strip()):
            continue
        
        # Determine category from mapping_hint
        mapping = q.mapping_hint or ""
        category_str = mapping.split(".")[-1] if "." in mapping else "other"
        
        try:
            category = UserAchievementCategory(category_str)
        except ValueError:
            category = UserAchievementCategory.OTHER
        
        user_ach = UserAchievement(
            user_id=current_user.id,
            title=q.title,
            category=category,
            notes=str(answer_text) if answer_text else None,
        )
        db.add(user_ach)
        stored_count += 1
    
    # Mark session as completed
    session.status = IntakeStatusEnum.COMPLETED
    await db.commit()
    
    logger.info(f"[ACH_INTAKE] Stored {stored_count} achievements for user {current_user.id}")
    
    return {"ok": True, "achievements_count": stored_count}
