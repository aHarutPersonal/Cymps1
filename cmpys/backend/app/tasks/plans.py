import logging
from typing import Any

from pydantic import ValidationError
from sqlalchemy import and_, select, update
from sqlalchemy.orm import selectinload

from app.core.celery import celery_app
from app.core.async_runtime import run_async
from app.core.db import async_session_maker
from app.models.idol_persona import IdolPersona
from app.models.idol_profile import IdolProfile
from app.models.idol_timeline import IdolTimelineEvent
from app.models.plan import Plan, PlanItem, PlanItemType
from app.models.plan_job import PlanGenerationJob
from app.models.user_achievement import UserAchievement
from app.models.user import User
from app.models.user_profile import UserProfile
from app.services.planning.generator import generate_plan
from app.services.content_quality import (
    MIN_PLAN_DETAIL_LESSON_WORDS,
    MIN_PLAN_DETAIL_MATERIAL_WORDS,
)
from app.services.transcripts import build_chat_history_json
from app.services.llm.schemas import PlanItemDetailsOutput

logger = logging.getLogger(__name__)


def _validate_plan_detail_response(response: Any) -> None:
    """Apply the same basic contract for providers with or without native JSON schema."""
    if getattr(response, "error", None):
        return
    try:
        validated = PlanItemDetailsOutput.model_validate(response.data)
        response.data = validated.model_dump(mode="json")
    except ValidationError as exc:
        response.error = f"Plan detail schema validation failed: {exc}"


def _plan_detail_recovery_prompt(prompt: str, error: str) -> tuple[str, str]:
    """Return a retry prompt and stage matched to the actual failure type."""
    if error.startswith("Plan detail schema validation failed:"):
        return (
            prompt
            + "\n\nQUALITY CONTRACT RETRY: The previous complete draft failed "
            "the deterministic reader-quality contract below:\n"
            + error[:4000]
            + "\nRewrite the complete JSON artifact and correct every reported "
            "issue. Preserve exactly three lessons and three materials. Each "
            "lesson must contain 1,200-1,800 substantive words under every "
            "required heading, with 20-50 word actionable substeps and exact "
            "references to top-level material titles. Include exactly one book, "
            "one video, and one allowed third material. Do not pad or repeat.",
            "quality_recovery",
        )
    return (
        prompt
        + "\n\nJSON RECOVERY: Return ONLY strictly valid JSON. Escape every "
        "quote and newline inside string values. No trailing commas, "
        "commentary, or markdown fences. Preserve every content-depth rule "
        "from the original request.",
        "json_recovery",
    )


def _build_idol_plan_context(
    *,
    idol: Any,
    profile: Any | None,
    persona: Any | None,
    milestones: list[Any],
    gaps: list[str],
) -> dict[str, Any]:
    """Build the evidence-backed idol context passed to the plan prompt."""
    profile_payload = {
        "name": idol.name,
        "domain": idol.domain,
    }
    if profile:
        profile_payload.update(
            {
                "display_name": profile.display_name,
                "short_description": profile.short_description,
                "domains": profile.domains,
                "primary_roles": profile.primary_roles,
                "notable_themes": profile.notable_themes,
            }
        )

    persona_payload = {}
    if persona:
        persona_payload = {
            "voice_style": persona.voice_style,
            "principles": persona.principles,
            "topics_of_strength": persona.topics_of_strength,
            "era_context": persona.era_context or "contemporary",
        }

    milestone_payload = [
        {
            "title": milestone.canonical_title,
            "description": milestone.canonical_description,
            "age": milestone.age_at_event,
            "category": milestone.category,
            "importance": milestone.importance_score,
        }
        for milestone in milestones
        if milestone.age_at_event is not None
    ]
    return {
        "idol_profile": profile_payload,
        "idol_persona": persona_payload,
        "idol_milestones": milestone_payload,
        "gaps": gaps,
        "readiness_by_gap": {gap: "beginner" for gap in gaps},
    }

def build_previous_cycle_block(
    cycle_number: int,
    prior_thesis: str,
    completed_missions: list[str],
    achievements: list[str],
) -> str:
    """Render the previous-cycle directive. Empty for cycle 1 (backward compat)."""
    if cycle_number < 2:
        return ""
    prev = cycle_number - 1
    missions = "\n".join(f"- {m}" for m in completed_missions[:20]) or "- (none)"
    wins = "\n".join(f"- {a}" for a in achievements[:20]) or "- (none)"
    return (
        f"## PREVIOUS CYCLE (cycle {prev}) — THIS IS CYCLE {cycle_number}\n"
        f"Prior thesis: {prior_thesis}\n"
        f"Completed mission tasks:\n{missions}\n"
        f"Logged achievements:\n{wins}\n\n"
        "Directive: assume mastery of cycle "
        f"{prev}'s foundations — do NOT repeat them. Open at the level cycle "
        f"{prev} ended. Escalate difficulty, depth, and idol-proximity. Reference "
        "the user's actual logged achievements so this cycle visibly builds on them.\n"
    )


def _blueprint_phase_for_week(week: int | None) -> str:
    """Map a plan week number to its blueprint phase label.

    The 12-week blueprint is split into four three-week phases. Used to thread
    the right phase context into per-item detail generation. Defaults to the
    Foundation phase when the week is unknown.
    """
    if week is None or week <= 3:
        return "Weeks 1-3: Foundation"
    if week <= 6:
        return "Weeks 4-6: Core Skills"
    if week <= 9:
        return "Weeks 7-9: Applied Practice"
    return "Weeks 10-12: Integration"


def normalize_lesson_durations(details: dict[str, Any]) -> dict[str, Any]:
    """Make every lesson's time claim auditable from reading + practice.

    The LLM supplies the practice design, while the backend derives reading
    time from the actual lesson length and constrains total lesson time to the
    product's 40-60 minute contract.
    """
    for step in details.get("steps", []):
        lesson = str(step.get("lesson_content") or "")
        word_count = len(lesson.split())
        reading_minutes = max(1, round(word_count / 200))

        requested_total = int(
            step.get("estimate_minutes") or step.get("estimateMinutes") or 45
        )
        requested_total = max(40, min(60, requested_total))
        requested_practice = int(
            step.get("practice_minutes") or requested_total - reading_minutes
        )
        practice_minutes = max(30, requested_practice)
        total_minutes = reading_minutes + practice_minutes
        if total_minutes < 40:
            practice_minutes += 40 - total_minutes
        elif total_minutes > 60:
            practice_minutes = max(20, 60 - reading_minutes)

        step["reading_minutes"] = reading_minutes
        step["practice_minutes"] = practice_minutes
        step["estimate_minutes"] = reading_minutes + practice_minutes
    return details


async def _resolve_plan_detail_materials(
    db,
    *,
    plan_item_id: str,
    materials: list[dict[str, Any]],
    user_goal: str,
) -> list[dict[str, Any]]:
    """Resolve lightweight material metadata without blocking on book writing.

    Full 3,200+ word book guides are shared catalog artifacts. Cache misses are
    queued by ``attach_content_resources_to_materials`` while the plan lesson
    can finish immediately; already-published books still attach synchronously.
    """
    if not materials:
        return []

    from app.services.content_resources import (
        attach_content_resources_to_materials,
        sync_plan_item_content_resource_links,
    )
    from app.services.tavily import resolve_material_urls

    resolved = await resolve_material_urls(materials)
    attached = await attach_content_resources_to_materials(
        db,
        resolved,
        user_goal=user_goal,
        defer_book_generation=True,
    )
    await sync_plan_item_content_resource_links(
        db,
        plan_item_id=plan_item_id,
        materials=attached,
    )
    return attached


async def _load_session_context(
    db,
    user_id: str | None = None,
    idol_id: str | None = None,
    session_id: str | None = None,
) -> dict:
    """Load agentic-session context (interview transcript, comparison verdict,
    blueprint) so plan generation can build on what the user already revealed.

    Resolution order:
      1. ``session_id`` — the exact session the plan was generated from (set on
         the job when the agentic flow triggers /plans/generate).
      2. Fallback: the user's most recent ``IntakeSession`` for this idol, the
         same way ``GET /plans/current`` resolves the active idol.

    Returns an empty dict for legacy ``/plans`` jobs (no session resolvable), so
    the plan path degrades gracefully to profile+gap analysis alone.

    Keys returned (all optional) match the plan_generate.txt placeholders:
    ``interview_transcript_json``, ``comparison_summary``, ``blueprint_markdown``.
    """
    if db is None:
        return {}

    from app.models.intake import IntakeSession
    from app.models.chat import ChatThread

    if session_id:
        result = await db.execute(
            select(IntakeSession).where(IntakeSession.id == session_id)
        )
    elif user_id and idol_id:
        result = await db.execute(
            select(IntakeSession)
            .where(
                IntakeSession.user_id == user_id,
                IntakeSession.idol_id == idol_id,
            )
            .order_by(IntakeSession.created_at.desc())
            .limit(1)
        )
    else:
        return {}

    session = result.scalar_one_or_none()
    if session is None:
        return {}

    ctx: dict = {}

    # Interview transcript is not a column — it lives as ChatMessage rows on the
    # session's interview thread. Reconstruct it with the same helper the live
    # SSE endpoints use, so user turns get the same untrusted-input wrapping.
    if session.interview_thread_id:
        thread_result = await db.execute(
            select(ChatThread)
            .options(selectinload(ChatThread.messages))
            .where(ChatThread.id == session.interview_thread_id)
        )
        thread = thread_result.scalar_one_or_none()
        if thread and thread.messages:
            # Shared serializer; sanitize_user wraps user turns as untrusted DATA.
            ctx["interview_transcript_json"] = build_chat_history_json(
                thread.messages, sanitize_user=True
            )

    if session.comparison_output:
        ctx["comparison_summary"] = session.comparison_output
    if session.blueprint_output:
        ctx["blueprint_markdown"] = session.blueprint_output

    return ctx

@celery_app.task(bind=True)
def run_plan_generation(self, job_id: str) -> dict:
    """
    Run the plan generation pipeline as a background task.
    """
    logger.info(f"[PLANNING] Starting plan generation for job_id={job_id}")
    try:
        result = run_async(_run_plan_generation_async(job_id))
        logger.info(f"[PLANNING] Completed job_id={job_id}, result={result}")
        return result
    except Exception as e:
        logger.exception(f"[PLANNING] Fatal error in job_id={job_id}: {e}")
        raise

async def _run_plan_generation_async(job_id: str) -> dict:
    """Async implementation of the plan generation pipeline."""
    async with async_session_maker() as db:
        # Fetch job with idol
        stmt = (
            select(PlanGenerationJob)
            .options(selectinload(PlanGenerationJob.idol))
            .where(PlanGenerationJob.id == job_id)
        )
        result = await db.execute(stmt)
        job = result.scalar_one_or_none()

        if not job:
            return {"error": "Job not found"}

        idol = job.idol
        if not idol:
            await _update_job(db, job, status="failed", step="error", error_message="Idol not found")
            return {"error": "Idol not found"}

        try:
            # Step 1: Analyzing gaps (0-30%)
            await _update_job(db, job, status="running", step="analyzing_gaps", progress=10)
            
            # Load idol profile
            profile_stmt = select(IdolProfile).where(IdolProfile.idol_id == job.idol_id)
            profile_result = await db.execute(profile_stmt)
            idol_profile = profile_result.scalar_one_or_none()
            
            # Load idol persona
            persona_stmt = select(IdolPersona).where(IdolPersona.idol_id == job.idol_id)
            persona_result = await db.execute(persona_stmt)
            idol_persona = persona_result.scalar_one_or_none()
            
            # Load idol milestones up to target age
            milestone_stmt = select(IdolTimelineEvent).where(
                and_(
                    IdolTimelineEvent.idol_id == job.idol_id,
                    IdolTimelineEvent.age_at_event <= job.target_age,
                )
            ).order_by(
                IdolTimelineEvent.age_at_event.asc(),
                IdolTimelineEvent.importance_score.desc(),
            )
            milestone_result = await db.execute(milestone_stmt)
            idol_milestones = list(milestone_result.scalars().all())
            
            # Load user achievements
            ach_stmt = select(UserAchievement).where(
                UserAchievement.user_id == job.user_id
            )
            ach_result = await db.execute(ach_stmt)
            user_achievements = list(ach_result.scalars().all())
            
            # Gap analysis
            user_cats = {a.category.value for a in user_achievements}
            idol_cats = {m.category for m in idol_milestones}
            gaps = sorted(idol_cats - user_cats)
            if not gaps:
                gaps = ["learning", "career", "mindset"]
            
            await _update_job(db, job, progress=30)

            # Step 2: Structuring curriculum (30-60%)
            await _update_job(db, job, step="structuring_curriculum", progress=40)
            
            idol_plan_context = _build_idol_plan_context(
                idol=idol,
                profile=idol_profile,
                persona=idol_persona,
                milestones=idol_milestones,
                gaps=gaps,
            )
            
            await _update_job(db, job, progress=50)

            # Step 3: Balancing workload (60-85%)
            await _update_job(db, job, step="balancing_workload", progress=65)
            
            # Keep progress copy deterministic. The previous implementation
            # launched an untracked OpenAI stream even when Gemini was the
            # configured provider; it was not metered and could be destroyed
            # when the Celery event loop closed.
            gap_summary = ", ".join(gaps[:3])
            job.thinking_text = (
                f"Analyzing {idol.name}'s journey and building a plan around "
                f"your highest-priority gaps: {gap_summary}."
            )
            await db.commit()
            
            await _update_job(db, job, progress=70)
            
            # Load user data for context
            user_stmt = select(User).where(User.id == job.user_id)
            user_res = await db.execute(user_stmt)
            user = user_res.scalar_one_or_none()
            
            u_prof_stmt = select(UserProfile).where(UserProfile.user_id == job.user_id)
            u_prof_res = await db.execute(u_prof_stmt)
            user_profile = u_prof_res.scalar_one_or_none()
            
            u_ach_stmt = select(UserAchievement).where(UserAchievement.user_id == job.user_id).limit(5)
            u_ach_res = await db.execute(u_ach_stmt)
            recent_achieves = list(u_ach_res.scalars().all())
            
            # Build Context String
            context_parts = []
            if user:
                context_parts.append(f"User Age: {job.target_age if job.target_age else 'Unknown'}")
            
            if user_profile:
                if user_profile.goals:
                    context_parts.append(f"Stated Goals: {', '.join(user_profile.goals)}")
                if user_profile.interests:
                    context_parts.append(f"Interests: {', '.join(user_profile.interests)}")
                if user_profile.learning_preferences:
                     context_parts.append(f"Learning Preferences: {', '.join(user_profile.learning_preferences)}")
            
            if recent_achieves:
                ach_txt = ", ".join([a.title for a in recent_achieves])
                context_parts.append(f"Recent Wins: {ach_txt}")
                
            user_context_str = "\n".join(context_parts)

            # Derive user goal from profile or default
            user_goal = "personal and professional growth"
            if user_profile and user_profile.goals:
                 user_goal = user_profile.goals[0]
            elif idol_profile and idol_profile.notable_themes:
                user_goal = ", ".join(idol_profile.notable_themes[:3])
            elif idol.domain and idol.domain != "general":
                user_goal = f"excellence in {idol.domain}"

            # Thread the agentic-session context (interview transcript, comparison
            # verdict, blueprint) into the plan so it builds on what the user
            # revealed instead of profile+gaps alone. Resolved via user+idol since
            # the job carries no session_id. Best-effort: a failure here must not
            # fail plan generation, which still works from the profile.
            session_ctx: dict = {}
            try:
                session_ctx = await _load_session_context(
                    db,
                    user_id=job.user_id,
                    idol_id=job.idol_id,
                    session_id=job.session_id,
                )
                if session_ctx:
                    logger.info(
                        f"[PLANNING] Threaded session context into plan for job={job.id}: "
                        f"{sorted(session_ctx.keys())}"
                    )
            except Exception as e:
                logger.warning(f"[PLANNING] Could not load session context for job={job.id}: {e}")

            previous_cycle_block = ""
            if job.cycle_number and job.cycle_number >= 2 and job.previous_plan_id:
                prior = await db.get(Plan, job.previous_plan_id)
                prior_items = (await db.execute(
                    select(PlanItem).where(PlanItem.plan_id == job.previous_plan_id)
                )).scalars().all() if prior else []
                completed_missions = [
                    i.title for i in prior_items if i.type in {
                        PlanItemType.PROJECT, PlanItemType.COURSE, PlanItemType.READING}
                ]
                ach_titles = (await db.execute(
                    select(UserAchievement.title).where(
                        UserAchievement.plan_id == job.previous_plan_id)
                )).scalars().all()
                prior_thesis = (prior.roadmap_json or {}).get("roadmap_thesis", "") if prior else ""
                previous_cycle_block = build_previous_cycle_block(
                    job.cycle_number,
                    prior_thesis,
                    completed_missions,
                    list(ach_titles),
                )

            roadmap = await generate_plan(
                idol_name=idol.name,
                user_goal=user_goal,
                weekly_hours=job.weekly_hours,
                duration_weeks=job.duration_weeks,
                target_age=job.target_age,
                user_context=user_context_str,
                **idol_plan_context,
                interview_transcript_json=session_ctx.get("interview_transcript_json", ""),
                comparison_summary=session_ctx.get("comparison_summary", ""),
                blueprint_markdown=session_ctx.get("blueprint_markdown", ""),
                previous_cycle_block=previous_cycle_block,
            )
            
            plan_items_data = roadmap.items
            
            await _update_job(db, job, progress=85)

            # Step 4: Finalizing plan (85-100%)
            # Clear thinking text so frontend switches to simulated narratives or static text
            job.thinking_text = None
            await _update_job(db, job, step="finalizing_plan", progress=90)
            
            # Create plan with roadmap metadata
            plan = Plan(
                user_id=job.user_id,
                idol_id=job.idol_id,
                target_age=job.target_age,
                duration_weeks=job.duration_weeks,
                weekly_hours=job.weekly_hours,
                roadmap_json={
                    "roadmap_thesis": roadmap.roadmap_thesis,
                    "anti_goals": roadmap.anti_goals,
                },
                cycle_number=job.cycle_number or 1,
                previous_plan_id=job.previous_plan_id,
            )
            db.add(plan)
            await db.flush()
            
            # Create plan items
            for item_data in plan_items_data:
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
                    meta_json=item_data.meta_json,
                )
                db.add(item)
            
            await db.flush()
            
            # Update job with results
            job.plan_id = plan.id
            await _update_job(db, job, status="completed", step="done", progress=100)
            
            # Pre-generate details for all items, starting with Week 1
            await _enqueue_all_details_generation_async(db, plan, job.user_id)
            
            return {"status": "completed", "plan_id": str(plan.id)}

        except Exception as e:
            logger.exception(f"Plan generation failed for job {job_id}")
            await _update_job(
                db, job,
                status="failed",
                step="error",
                error_message=str(e)
            )
            return {"error": str(e)}

    await db.commit()


@celery_app.task(bind=True, soft_time_limit=540, time_limit=600)
def regenerate_plan_item_details(self, job_id: str) -> dict:
    """
    Regenerate details (steps + materials) for a plan item using LLM.
    """
    logger.info(f"[PLAN_DETAILS] Starting regeneration for job_id={job_id}")
    try:
        result = run_async(_regenerate_plan_item_details_async(job_id))
        logger.info(f"[PLAN_DETAILS] Completed job_id={job_id}")
        return result
    except Exception as e:
        logger.exception(f"[PLAN_DETAILS] Error regenerating job_id={job_id}: {e}")
        # Context loading and strict prompt rendering happen before the inner
        # provider try/except. Persist those failures (and the 9-minute soft
        # timeout) so the client receives a terminal retry state instead of a
        # job that says "running" forever.
        try:
            run_async(_mark_plan_detail_job_failed(job_id, str(e)))
        except Exception:
            logger.exception(
                "[PLAN_DETAILS] Could not persist failure job_id=%s", job_id
            )
        raise


async def _mark_plan_detail_job_failed(job_id: str, error: str) -> None:
    from app.models.item_detail_job import PlanItemDetailJob

    async with async_session_maker() as db:
        await db.execute(
            update(PlanItemDetailJob)
            .where(
                PlanItemDetailJob.id == job_id,
                PlanItemDetailJob.status != "completed",
            )
            .values(
                status="failed",
                step="error",
                error_message=error[:4000],
            )
        )
        await db.commit()


async def _regenerate_plan_item_details_async(job_id: str) -> dict:
    """Async implementation of plan item details regeneration."""
    from datetime import datetime, timezone
    from app.models.item_detail_job import PlanItemDetailJob
    from app.models.plan import Plan, PlanItem
    from app.models.idol_persona import IdolPersona
    from app.models.user_profile import UserProfile
    from app.services.llm.client import get_llm_client
    from app.services.llm.prompt_loader import load_and_render
    from app.services.llm.routing import choose_llm_tier
    from app.services.llm.telemetry import (
        record_usage_records,
        usage_record_from_response,
    )
    
    async with async_session_maker() as db:
        # Atomically claim the row. A prefetched low-priority message may be
        # republished to high priority when its screen is opened; only one
        # worker may perform the expensive generation.
        claim_result = await db.execute(
            update(PlanItemDetailJob)
            .where(
                PlanItemDetailJob.id == job_id,
                PlanItemDetailJob.status.in_(["queued", "pending"]),
            )
            .values(
                status="running",
                step="loading_context",
                progress_percent=10,
                error_message=None,
            )
        )
        await db.commit()
        if claim_result.rowcount != 1:
            status_result = await db.execute(
                select(PlanItemDetailJob.status).where(
                    PlanItemDetailJob.id == job_id
                )
            )
            existing_status = status_result.scalar_one_or_none()
            if existing_status is None:
                return {"status": "failed", "error": "Job not found"}
            return {
                "status": "skipped",
                "reason": f"job_already_{existing_status}",
            }

        # Load the claimed job and its complete generation context.
        stmt = (
            select(PlanItemDetailJob)
            .options(
                selectinload(PlanItemDetailJob.plan_item).selectinload(PlanItem.plan).selectinload(Plan.idol),
            )
            .where(PlanItemDetailJob.id == job_id)
        )
        result = await db.execute(stmt)
        job = result.scalar_one_or_none()
        
        if not job:
            return {"status": "failed", "error": "Job not found"}
        
        item = job.plan_item
        user_id = job.user_id
        
        # Step 1: Loading context (the atomic claim above persisted 10%).
        plan = item.plan
        idol = plan.idol if plan else None
        idol_name = idol.name if idol else "this person"
        idol_domain = idol.domain if idol and idol.domain else "general excellence"
        
        # Load idol persona for context
        idol_persona_dict = {}
        if idol:
            persona_stmt = select(IdolPersona).where(IdolPersona.idol_id == idol.id)
            persona_result = await db.execute(persona_stmt)
            persona = persona_result.scalar_one_or_none()
            if persona:
                idol_persona_dict = {
                    "voice_style": persona.voice_style,
                    "principles": persona.principles,
                    "era_context": persona.era_context,
                    "topics_of_strength": persona.topics_of_strength,
                    "lexicon_allow": persona.lexicon_allow or [],
                    "lexicon_ban": persona.lexicon_ban or [],
                }

        # Give the lesson writer actual evidence instead of asking it to recall
        # biographical examples from the idol's name alone.
        idol_evidence: dict = {"persona": idol_persona_dict}
        if idol:
            profile_result = await db.execute(
                select(IdolProfile).where(IdolProfile.idol_id == idol.id)
            )
            profile = profile_result.scalar_one_or_none()
            if profile:
                idol_evidence["profile"] = {
                    "display_name": profile.display_name,
                    "short_description": profile.short_description,
                    "domains": profile.domains or [],
                    "primary_roles": profile.primary_roles or [],
                    "notable_themes": profile.notable_themes or [],
                }
            timeline_result = await db.execute(
                select(IdolTimelineEvent)
                .where(
                    IdolTimelineEvent.idol_id == idol.id,
                    IdolTimelineEvent.confidence >= 0.55,
                )
                .order_by(IdolTimelineEvent.importance_score.desc())
                .limit(8)
            )
            idol_evidence["timeline"] = [
                {
                    "title": event.canonical_title,
                    "description": event.canonical_description,
                    "age_at_event": event.age_at_event,
                    "confidence": event.confidence,
                }
                for event in timeline_result.scalars().all()
            ]
        
        await _update_job(db, job, progress=25)

        # Load user profile for goal context + learning preferences
        user_goal = "personal and professional growth"
        user_learning_pref = "mixed"
        user_profile_stmt = select(UserProfile).where(UserProfile.user_id == user_id)
        user_profile_result = await db.execute(user_profile_stmt)
        user_profile = user_profile_result.scalar_one_or_none()
        if user_profile and user_profile.goals:
            user_goal = ", ".join(user_profile.goals[:3])
        if user_profile and user_profile.learning_preferences:
            user_learning_pref = ", ".join(user_profile.learning_preferences[:3])
        
        # Step 2: Generating curriculum
        await _update_job(db, job, step="generating_curriculum", progress=40)
        
        # Job polling already renders deterministic, step-aware narratives.
        # Keep artifact generation focused on the user-visible lesson instead
        # of launching an untracked second-provider "thinking" request.
        job.thinking_text = None
        await _update_job(db, job, progress=50)
        
        # session_context grounds the lesson in the user's agentic session
        # (blueprint + comparison). Best-effort: an empty string still renders a
        # valid lesson, but the prompt REQUIRES the key, so it must always be
        # supplied (its omission failed every lesson with PROMPT_PARAMS_MISSING).
        session_context = ""
        try:
            sctx = await _load_session_context(
                db,
                user_id=user_id,
                idol_id=idol.id if idol else None,
                session_id=None,
            )
            session_context = "\n\n".join(
                p
                for p in [
                    sctx.get("blueprint_markdown") or "",
                    sctx.get("comparison_summary") or "",
                ]
                if p
            ).strip()[:4000]
        except Exception as e:
            logger.warning(f"[PLAN_DETAILS] session_context load failed: {e}")

        # Render prompt (task, goal, learning pref, idol, session context).
        prompt = load_and_render(
            "plan_item_details.txt",
            {
                "task_title": item.title,
                "user_goal": user_goal,
                "learning_preferences": user_learning_pref,
                "idol_name": idol_name,
                "idol_domain": idol_domain,
                "idol_evidence_json": idol_evidence,
                "session_context": session_context,
            },
            strict=True,
        )

        await _update_job(db, job, progress=60)
        
        try:
            # planner_system.txt, not extractor_system.txt: lesson/material
            # generation needs world knowledge of real resources, which the
            # extraction prompt forbids.
            system_prompt = load_and_render("planner_system.txt", {}, strict=False)
            routing_decision = await choose_llm_tier(
                operation="plan_item_detail_generation",
                routing_key=str(item.id),
                default_tier="balanced",
                db=db,
            )
            active_tier = routing_decision.tier
            client = get_llm_client(
                max_tokens=16000,
                tier=active_tier,
                thinking_budget=0,
            )
            detail_llm_calls = []
            call_quality: dict[int, float] = {}

            def _score_detail_payload(payload: dict) -> float:
                components: list[float] = []
                for payload_step in payload.get("steps", []):
                    lesson = payload_step.get("lesson_content", "")
                    if lesson:
                        components.append(
                            min(
                                1.0,
                                len(lesson.split()) / MIN_PLAN_DETAIL_LESSON_WORDS,
                            )
                        )
                for payload_material in payload.get("materials", []):
                    content = payload_material.get("content_markdown", "")
                    if content:
                        components.append(
                            min(
                                1.0,
                                len(content.split()) / MIN_PLAN_DETAIL_MATERIAL_WORDS,
                            )
                        )
                return sum(components) / len(components) if components else 0.0

            async def _persist_detail_usage(
                result_status: str,
                quality_score: float,
            ) -> None:
                await record_usage_records(
                    [
                        usage_record_from_response(
                            operation="plan_item_detail_generation",
                            response=call_response,
                            model=call_model,
                            result_status=(
                                (
                                    "quality_passed"
                                    if call_quality[id(call_response)] >= 1.0
                                    else "quality_failed"
                                )
                                if id(call_response) in call_quality
                                else result_status
                            ),
                            quality_score=call_quality.get(
                                id(call_response), quality_score
                            ),
                            metadata={
                                "stage": stage,
                                "selected_tier": selected_tier,
                                "routing_reason": route_reason,
                                "plan_item_id": str(item.id),
                                "item_type": getattr(item.type, "value", str(item.type)),
                            },
                        )
                        for stage, call_response, selected_tier, route_reason, call_model in detail_llm_calls
                    ],
                    db=db,
                )

            llm_response = await client.generate_json(
                system_prompt=system_prompt,
                user_prompt=prompt,
                output_model=PlanItemDetailsOutput,
            )
            _validate_plan_detail_response(llm_response)
            detail_llm_calls.append(
                (
                    "draft",
                    llm_response,
                    active_tier,
                    routing_decision.reason,
                    getattr(client, "model", None),
                )
            )

            # Gemini occasionally emits JSON that survives neither the parser nor
            # _repair_json (e.g. a dropped delimiter inside long lesson markdown).
            # A single fresh sampling almost always returns valid JSON, so retry
            # once with an explicit strict-JSON reminder before giving up.
            if llm_response.error:
                retry_prompt, recovery_stage = _plan_detail_recovery_prompt(
                    prompt,
                    llm_response.error,
                )
                logger.warning(
                    f"[PLAN_DETAILS] LLM contract error for '{item.title}': "
                    f"{llm_response.error}. Retrying once."
                )
                if active_tier == "fast":
                    active_tier = "balanced"
                    client = get_llm_client(
                        max_tokens=16000,
                        tier="balanced",
                        thinking_budget=0,
                    )
                    recovery_reason = "fast_schema_fallback"
                else:
                    recovery_reason = "balanced_schema_retry"
                json_retry_response = await client.generate_json(
                    system_prompt=system_prompt,
                    user_prompt=retry_prompt,
                    output_model=PlanItemDetailsOutput,
                )
                _validate_plan_detail_response(json_retry_response)
                detail_llm_calls.append(
                    (
                        recovery_stage,
                        json_retry_response,
                        active_tier,
                        recovery_reason,
                        getattr(client, "model", None),
                    )
                )
                llm_response = json_retry_response

            if llm_response.error:
                await _persist_detail_usage("generation_failed", 0.0)
                await _update_job(db, job, status="failed", step="error", error_message=llm_response.error)
                return {"status": "failed", "error": llm_response.error}
            
            details = llm_response.data

            # Normalize before URL/resource resolution so `kind` aliases become `type`
            # and book/video resources can be deduplicated reliably.
            from app.tasks.ingestion import _normalize_plan_item_details
            details = _normalize_plan_item_details(details)
            details = normalize_lesson_durations(details)
            call_quality[id(llm_response)] = _score_detail_payload(details)

            # Validate content depth — retry once if lesson_content is too thin
            min_lesson_words = MIN_PLAN_DETAIL_LESSON_WORDS
            min_material_words = MIN_PLAN_DETAIL_MATERIAL_WORDS
            needs_retry = False
            for step in details.get("steps", []):
                lesson = step.get("lesson_content", "")
                if lesson and len(lesson.split()) < min_lesson_words:
                    needs_retry = True
                    break
            if not needs_retry:
                for mat in details.get("materials", []):
                    md = mat.get("content_markdown", "")
                    if md and len(md.split()) < min_material_words:
                        needs_retry = True
                        break

            if needs_retry:
                logger.warning(
                    f"[PLAN_DETAILS] Content too thin for item '{item.title}'. "
                    f"Retrying with stronger prompt."
                )
                retry_prompt = prompt + (
                    "\n\nIMPORTANT: Your previous attempt produced content that was too thin. "
                    "Each step's lesson_content MUST be 1,200-1,800 words, and each "
                    "book/in_app_lesson material's content_markdown roughly 400-600 words. "
                    "Strengthen thin lessons with mechanisms, a worked example, failure modes, "
                    "a 30-45 minute guided practice, a knowledge check, and exact material "
                    "references — stay within those ranges and do NOT pad or repeat."
                )
                if active_tier == "fast":
                    active_tier = "balanced"
                    client = get_llm_client(
                        max_tokens=16000,
                        tier="balanced",
                        thinking_budget=0,
                    )
                    quality_retry_reason = "fast_quality_fallback"
                else:
                    quality_retry_reason = "balanced_quality_retry"
                retry_response = await client.generate_json(
                    system_prompt=system_prompt,
                    user_prompt=retry_prompt,
                    output_model=PlanItemDetailsOutput,
                )
                _validate_plan_detail_response(retry_response)
                detail_llm_calls.append(
                    (
                        "quality_retry",
                        retry_response,
                        active_tier,
                        quality_retry_reason,
                        getattr(client, "model", None),
                    )
                )
                if not retry_response.error:
                    retry_details = _normalize_plan_item_details(retry_response.data)
                    retry_details = normalize_lesson_durations(retry_details)
                    call_quality[id(retry_response)] = _score_detail_payload(
                        retry_details
                    )
                    # Check if retry produced deeper content
                    retry_ok = True
                    for step in retry_details.get("steps", []):
                        lesson = step.get("lesson_content", "")
                        if lesson and len(lesson.split()) < min_lesson_words:
                            retry_ok = False
                            break
                    if retry_ok:
                        for mat in retry_details.get("materials", []):
                            md = mat.get("content_markdown", "")
                            if md and len(md.split()) < min_material_words:
                                retry_ok = False
                                break
                    if retry_ok:
                        details = retry_details

            detail_quality_score = _score_detail_payload(details)
            
            # Step 3: Resolve material URLs via Tavily (real web search)
            await _update_job(db, job, step="resolving_materials", progress=75)
            try:
                raw_materials = details.get("materials", [])
                if raw_materials:
                    details["materials"] = await _resolve_plan_detail_materials(
                        db,
                        plan_item_id=item.id,
                        materials=raw_materials,
                        user_goal=user_goal,
                    )
                    logger.info(
                        "[PLAN_DETAILS] Resolved %s material references",
                        len(details["materials"]),
                    )
            except Exception as resolve_err:
                logger.warning(f"[PLAN_DETAILS] URL resolution failed, using fallbacks: {resolve_err}")
            
            # Step 4: Finalizing steps
            await _update_job(db, job, step="finalizing_steps", progress=85)

            details["generated_at"] = datetime.now(timezone.utc).isoformat()
            
            from app.tasks.ingestion import sanitize_for_postgres
            item.details_json = sanitize_for_postgres(details)

            await _persist_detail_usage(
                "quality_passed" if detail_quality_score >= 1.0 else "quality_partial",
                detail_quality_score,
            )
            
            # Finalize
            await _update_job(db, job, status="completed", step="done", progress=100)
            
            return {
                "status": "completed",
                "steps_count": len(details.get("steps", [])),
                "materials_count": len(details.get("materials", [])),
            }
            
        except Exception as e:
            logger.error(f"[PLAN_DETAILS] LLM error for job {job_id}: {e}")
            await _update_job(db, job, status="failed", step="error", error_message=str(e))
            return {"status": "failed", "error": str(e)}

async def _update_job(db, job, progress=None, status=None, step=None, error_message=None):
    """Helper to update job status in DB."""
    if progress is not None:
        job.progress_percent = progress
    if status is not None:
        job.status = status
    if step is not None:
        job.step = step
    if error_message is not None:
        job.error_message = error_message
    
    db.add(job)
    await db.commit()

async def _enqueue_all_details_generation_async(db, plan, user_id):
    """Enqueue detail generation for all plan items."""
    from app.models.item_detail_job import PlanItemDetailJob
    
    # Explicitly load items to avoid lazy loading (greenlet_spawn error)
    items_stmt = (
        select(PlanItem)
        .where(PlanItem.plan_id == plan.id)
        .order_by(PlanItem.week_start.asc(), PlanItem.id.asc())
    )
    items_result = await db.execute(items_stmt)
    all_items = [
        item
        for item in items_result.scalars().all()
        if item.type in {
            PlanItemType.PROJECT,
            PlanItemType.COURSE,
            PlanItemType.READING,
        }
    ]
    week_one = [item for item in all_items if item.week_start == 1]
    # Prime only the immediately useful work. Generating every week at once
    # occupies every worker for minutes, delays comparison/recovery jobs, and
    # spends tokens on content the user may not open for months. Remaining
    # items still generate on demand through the high-priority detail endpoint.
    items = (week_one or all_items)[:5]
    
    jobs = []
    for item in items:
        job = PlanItemDetailJob(
            user_id=user_id,
            plan_item_id=item.id,
            status="pending",
            step="prefetch_queued",
            progress_percent=0,
        )
        db.add(job)
        jobs.append(job)

    # The worker can pick up low-priority tasks immediately. Persist every job
    # before publishing any Celery message, otherwise workers race the open
    # transaction, report "Job not found", and the context manager rolls the
    # uncommitted job rows back on return.
    await db.flush()
    await db.commit()

    publish_failures = 0
    for job in jobs:
        try:
            regenerate_plan_item_details.apply_async(
                args=[str(job.id)], queue="low_priority"
            )
        except Exception as exc:
            publish_failures += 1
            logger.exception(
                "[PLANNING] Could not publish detail prefetch job_id=%s",
                job.id,
            )
            await db.execute(
                update(PlanItemDetailJob)
                .where(PlanItemDetailJob.id == job.id)
                .values(
                    status="failed",
                    step="error",
                    error_message=f"Could not start lesson generation: {exc}"[:4000],
                )
            )

    if publish_failures:
        await db.commit()

    logger.info(
        "[PLANNING] Enqueued %s week-one detail jobs (%s publish failures)",
        len(jobs),
        publish_failures,
    )
