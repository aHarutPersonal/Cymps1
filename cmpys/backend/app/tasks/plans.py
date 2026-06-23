import asyncio
import logging

from sqlalchemy import and_, select
from sqlalchemy.orm import selectinload

from app.core.celery import celery_app
from app.core.db import async_session_maker
from app.models.idol_persona import IdolPersona
from app.models.idol_profile import IdolProfile
from app.models.idol_timeline import IdolTimelineEvent
from app.models.plan import Plan, PlanItem
from app.models.plan_job import PlanGenerationJob
from app.models.user_achievement import UserAchievement
from app.models.user import User
from app.models.user_profile import UserProfile
from app.services.planning.generator import generate_plan

logger = logging.getLogger(__name__)

MIN_PLAN_DETAIL_LESSON_WORDS = 500
MIN_PLAN_DETAIL_MATERIAL_WORDS = 600


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


async def _load_session_context(db, session_id: str | None) -> dict:
    """Load agentic-session context (interview transcript, comparison summary,
    blueprint) for threading into plan generation.

    Returns an empty dict for legacy ``/plans`` jobs that carry no session_id,
    so the database is never touched in that path.
    """
    if not session_id or db is None:
        return {}

    from app.models.intake import IntakeSession

    result = await db.execute(
        select(IntakeSession).where(IntakeSession.id == session_id)
    )
    session = result.scalar_one_or_none()
    if session is None:
        return {}

    ctx: dict = {}
    transcript = (
        getattr(session, "interview_transcript", None)
        or getattr(session, "transcript", None)
    )
    if transcript:
        ctx["interview_transcript_json"] = transcript
    comparison = (
        getattr(session, "comparison_output", None)
        or getattr(session, "comparison_summary", None)
    )
    if comparison:
        ctx["comparison_summary"] = comparison
    blueprint = (
        getattr(session, "blueprint_output", None)
        or getattr(session, "blueprint_markdown", None)
    )
    if blueprint:
        ctx["blueprint_markdown"] = blueprint
    return ctx

@celery_app.task(bind=True)
def run_plan_generation(self, job_id: str) -> dict:
    """
    Run the plan generation pipeline as a background task.
    """
    logger.info(f"[PLANNING] Starting plan generation for job_id={job_id}")
    try:
        result = asyncio.get_event_loop().run_until_complete(_run_plan_generation_async(job_id))
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
            gaps = list(idol_cats - user_cats)
            if not gaps:
                gaps = ["learning", "career", "mindset"]
            
            await _update_job(db, job, progress=30)

            # Step 2: Structuring curriculum (30-60%)
            await _update_job(db, job, step="structuring_curriculum", progress=40)
            
            # Prepare data for LLM
            milestones_for_llm = [
                {
                    "title": m.canonical_title,
                    "description": m.canonical_description,
                    "age": m.age_at_event,
                    "category": m.category,
                    "importance": m.importance_score,
                }
                for m in idol_milestones
                if m.age_at_event is not None
            ]
            
            profile_for_llm = {
                "name": idol.name,
                "domain": idol.domain,
            }
            if idol_profile:
                profile_for_llm.update({
                    "display_name": idol_profile.display_name,
                    "short_description": idol_profile.short_description,
                    "domains": idol_profile.domains,
                    "primary_roles": idol_profile.primary_roles,
                    "notable_themes": idol_profile.notable_themes,
                })
            
            persona_for_llm = {}
            if idol_persona:
                persona_for_llm = {
                    "voice_style": idol_persona.voice_style,
                    "principles": idol_persona.principles,
                    "topics_of_strength": idol_persona.topics_of_strength,
                    "era_context": idol_persona.era_context or "contemporary",
                }
            
            await _update_job(db, job, progress=50)

            # Step 3: Balancing workload (60-85%)
            await _update_job(db, job, step="balancing_workload", progress=65)
            
            # Generate human-readable thinking concurrently
            try:
                import openai
                from app.core.config import settings as app_settings
                from app.services.llm.prompt_loader import load_prompt, render_prompt
                
                thinking_template = load_prompt("thinking_plan")
                thinking_prompt = render_prompt(thinking_template, {
                    "idol_name": idol.name,
                }, prompt_name="thinking_plan.txt")
                
                thinking_system = "You are an inspiring AI coach who thinks out loud while crafting personalized development plans. Be warm and insightful."
                
                async def _generate_thinking_stream_concurrently():
                    try:
                        async with async_session_maker() as stream_db:
                            stream_stmt = select(PlanGenerationJob).where(PlanGenerationJob.id == job_id)
                            stream_res = await stream_db.execute(stream_stmt)
                            stream_job = stream_res.scalar_one_or_none()
                            
                            if not stream_job:
                                return
                                
                            openai_client = openai.AsyncOpenAI(api_key=app_settings.openai_api_key)
                            thinking_text = ""
                            buffer = ""
                            last_update_time = asyncio.get_event_loop().time()
                            
                            stream = await openai_client.chat.completions.create(
                                model="gpt-4o-mini",
                                messages=[
                                    {"role": "system", "content": thinking_system},
                                    {"role": "user", "content": thinking_prompt},
                                ],
                                stream=True,
                                max_tokens=80,
                                temperature=0.7,
                            )
                            
                            async for chunk in stream:
                                delta = chunk.choices[0].delta
                                if delta.content:
                                    content_piece = delta.content
                                    thinking_text += content_piece
                                    buffer += content_piece
                                    
                                    current_time = asyncio.get_event_loop().time()
                                    
                                    # Buffer updates to avoid slamming the DB (every 20 chars or 200ms)
                                    if len(buffer) >= 20 or (current_time - last_update_time) > 0.2:
                                        stream_job.thinking_text = thinking_text
                                        await stream_db.commit()
                                        buffer = ""
                                        last_update_time = current_time
                                        
                            # Final flush
                            if buffer:
                                stream_job.thinking_text = thinking_text
                                await stream_db.commit()
                            
                            logger.info(f"[PLANNING] Thinking generated: {len(thinking_text)} chars")
                    except Exception as e:
                        logger.warning(f"[PLANNING] Concurrent thinking stream failed: {e}")
                
                logger.info("[PLANNING] Starting concurrent thinking stream...")
                asyncio.create_task(_generate_thinking_stream_concurrently())
            except Exception as e:
                logger.warning(f"[PLANNING] Failed to start thinking stream: {e}")
                job.thinking_text = f"Let me analyze {idol.name}'s journey and craft a personalized plan for you..."
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
            
            roadmap = await generate_plan(
                idol_name=idol.name,
                user_goal=user_goal,
                weekly_hours=job.weekly_hours,
                duration_weeks=job.duration_weeks,
                target_age=job.target_age,
                user_context=user_context_str,
                idol_profile={
                    "display_name": idol_profile.display_name,
                    "domains": idol_profile.domains,
                    "notable_themes": idol_profile.notable_themes,
                    "primary_roles": idol_profile.primary_roles,
                } if idol_profile else {},
                idol_persona={},
                idol_milestones=[],
                gaps=[],
                readiness_by_gap={},
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


@celery_app.task(bind=True)
def regenerate_plan_item_details(self, job_id: str) -> dict:
    """
    Regenerate details (steps + materials) for a plan item using LLM.
    """
    logger.info(f"[PLAN_DETAILS] Starting regeneration for job_id={job_id}")
    try:
        result = asyncio.get_event_loop().run_until_complete(
            _regenerate_plan_item_details_async(job_id)
        )
        logger.info(f"[PLAN_DETAILS] Completed job_id={job_id}")
        return result
    except Exception as e:
        logger.exception(f"[PLAN_DETAILS] Error regenerating job_id={job_id}: {e}")
        raise


async def _regenerate_plan_item_details_async(job_id: str) -> dict:
    """Async implementation of plan item details regeneration."""
    from datetime import datetime, timezone
    from app.models.item_detail_job import PlanItemDetailJob
    from app.models.plan import Plan, PlanItem
    from app.models.idol_persona import IdolPersona
    from app.models.user_profile import UserProfile
    from app.services.llm.client import get_llm_client
    from app.services.llm.prompt_loader import load_and_render
    
    async with async_session_maker() as db:
        # Load job
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
        
        # Step 1: Loading context
        await _update_job(db, job, status="running", step="loading_context", progress=10)
        
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
        
        # Generate human-readable thinking concurrently
        try:
            import openai
            from app.core.config import settings as app_settings
            from app.services.llm.prompt_loader import load_prompt, render_prompt
            
            thinking_template = load_prompt("thinking_task")
            thinking_prompt = render_prompt(thinking_template, {
                "task_title": item.title,
                "idol_name": idol_name,
            }, prompt_name="thinking_task.txt")
            
            thinking_system = "You are a helpful AI coach who thinks out loud while creating detailed learning steps. Be practical and encouraging."
            
            async def _generate_thinking_stream_concurrently():
                try:
                    async with async_session_maker() as stream_db:
                        stream_stmt = select(PlanItemDetailJob).where(PlanItemDetailJob.id == job_id)
                        stream_res = await stream_db.execute(stream_stmt)
                        stream_job = stream_res.scalar_one_or_none()
                        
                        if not stream_job:
                            return
                            
                        openai_client = openai.AsyncOpenAI(api_key=app_settings.openai_api_key)
                        thinking_text = ""
                        buffer = ""
                        last_update_time = asyncio.get_event_loop().time()
                        
                        stream = await openai_client.chat.completions.create(
                            model="gpt-4o-mini",
                            messages=[
                                {"role": "system", "content": thinking_system},
                                {"role": "user", "content": thinking_prompt},
                            ],
                            stream=True,
                            max_tokens=80,
                            temperature=0.7,
                        )
                        
                        async for chunk in stream:
                            delta = chunk.choices[0].delta
                            if delta.content:
                                content_piece = delta.content
                                thinking_text += content_piece
                                buffer += content_piece
                                
                                current_time = asyncio.get_event_loop().time()
                                
                                # Buffer updates
                                if len(buffer) >= 20 or (current_time - last_update_time) > 0.2:
                                    stream_job.thinking_text = thinking_text
                                    await stream_db.commit()
                                    buffer = ""
                                    last_update_time = current_time
                        
                        # Final flush
                        if buffer:
                            stream_job.thinking_text = thinking_text
                            await stream_db.commit()
                        
                        logger.info(f"[PLAN_DETAILS] Thinking generated: {len(thinking_text)} chars")
                except Exception as e:
                    logger.warning(f"[PLAN_DETAILS] Concurrent thinking generation failed: {e}")
            
            logger.info("[PLAN_DETAILS] Starting concurrent thinking stream...")
            asyncio.create_task(_generate_thinking_stream_concurrently())
        except Exception as e:
            logger.warning(f"[PLAN_DETAILS] Failed to start thinking stream: {e}")
            job.thinking_text = f"Let me break down '{item.title}' into actionable steps..."
            await db.commit()
        
        await _update_job(db, job, progress=50)
        
        # Render prompt with 3-var schema (task, goal, learning preference)
        prompt = load_and_render(
            "plan_item_details.txt",
            {
                "task_title": item.title,
                "user_goal": user_goal,
                "learning_preferences": user_learning_pref,
                "idol_name": idol_name,
                "idol_domain": idol_domain,
            },
            strict=True,
        )

        await _update_job(db, job, progress=60)
        
        try:
            system_prompt = load_and_render("extractor_system.txt", {}, strict=False)
            client = get_llm_client(max_tokens=16000)
            llm_response = await client.generate_json(
                system_prompt=system_prompt,
                user_prompt=prompt,
            )
            
            if llm_response.error:
                await _update_job(db, job, status="failed", step="error", error_message=llm_response.error)
                return {"status": "failed", "error": llm_response.error}
            
            details = llm_response.data

            # Normalize before URL/resource resolution so `kind` aliases become `type`
            # and book/video resources can be deduplicated reliably.
            from app.tasks.ingestion import _normalize_plan_item_details
            details = _normalize_plan_item_details(details)

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
                    "\n\nIMPORTANT: Your previous attempt produced content that was too brief. "
                    "You MUST write at least 500 words for each step's lesson_content (800+ if the "
                    "step claims 60+ minutes), and 600-1,000 words for each book/in_app_lesson "
                    "material's content_markdown. Expand every section with real examples from "
                    "the idol's life, detailed practice exercises, and concrete case studies."
                )
                retry_response = await client.generate_json(
                    system_prompt=system_prompt,
                    user_prompt=retry_prompt,
                )
                if not retry_response.error:
                    retry_details = _normalize_plan_item_details(retry_response.data)
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
            
            # Step 3: Resolve material URLs via Tavily (real web search)
            await _update_job(db, job, step="resolving_materials", progress=75)
            try:
                from app.services.tavily import resolve_material_urls
                from app.services.content_resources import (
                    attach_content_resources_to_materials,
                    sync_plan_item_content_resource_links,
                )
                raw_materials = details.get("materials", [])
                if raw_materials:
                    details["materials"] = await resolve_material_urls(raw_materials)
                    details["materials"] = await attach_content_resources_to_materials(
                        db,
                        details["materials"],
                        user_goal=user_goal,
                    )
                    await sync_plan_item_content_resource_links(
                        db,
                        plan_item_id=item.id,
                        materials=details["materials"],
                    )
                    logger.info(f"[PLAN_DETAILS] Resolved {len(details['materials'])} material URLs via Google Search")
            except Exception as resolve_err:
                logger.warning(f"[PLAN_DETAILS] URL resolution failed, using fallbacks: {resolve_err}")
            
            # Step 4: Finalizing steps
            await _update_job(db, job, step="finalizing_steps", progress=85)

            details["generated_at"] = datetime.now(timezone.utc).isoformat()
            
            from app.tasks.ingestion import sanitize_for_postgres
            item.details_json = sanitize_for_postgres(details)
            
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
    items = list(items_result.scalars().all())
    
    for item in items:
        # Create job
        job = PlanItemDetailJob(
            user_id=user_id,
            plan_item_id=item.id,
            status="pending"
        )
        db.add(job)
        await db.flush()
        
        # Enqueue task to low priority so interactive features aren't blocked
        regenerate_plan_item_details.apply_async(args=[job.id], queue="low_priority")
    
    logger.info(f"[PLANNING] Enqueued {len(items)} items for detail generation (All Weeks)")
