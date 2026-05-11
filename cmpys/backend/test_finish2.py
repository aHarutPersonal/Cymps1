import asyncio
from app.core.db import async_session_maker
from app.models.intake import IntakeSession
from app.models.user import User
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from app.api.v1.intake import _normalize_answers
from app.models.idol import Idol
from app.models.idol_profile import IdolProfile
from app.models.idol_persona import IdolPersona
from app.models.idol_timeline import IdolTimelineEvent
import json

async def main():
    async with async_session_maker() as session:
        stmt = (select(IntakeSession)
                .options(selectinload(IntakeSession.answers))
                .order_by(IntakeSession.created_at.desc())
                .limit(1))
        
        result = await session.execute(stmt)
        intake_sess = result.scalar_one_or_none()
        
        if not intake_sess:
            print("No intake session found")
            return
            
        print(f"Testing session: {intake_sess.id}")
        
        # Load user
        stmt_user = select(User).where(User.id == intake_sess.user_id).options(selectinload(User.profile))
        res_user = await session.execute(stmt_user)
        user = res_user.scalar_one_or_none()
        
        # Load idol
        stmt_idol = select(Idol).where(Idol.id == intake_sess.idol_id)
        res_idol = await session.execute(stmt_idol)
        idol = res_idol.scalar_one_or_none()
        
        stmt_prof = select(IdolProfile).where(IdolProfile.idol_id == intake_sess.idol_id)
        res_prof = await session.execute(stmt_prof)
        idol_prof = res_prof.scalar_one_or_none()
        
        stmt_pers = select(IdolPersona).where(IdolPersona.idol_id == intake_sess.idol_id)
        res_pers = await session.execute(stmt_pers)
        idol_pers = res_pers.scalar_one_or_none()
        
        stmt_mile = select(IdolTimelineEvent).where(IdolTimelineEvent.idol_id == intake_sess.idol_id)
        res_mile = await session.execute(stmt_mile)
        milestones = list(res_mile.scalars().all())
        
        # Get questions
        import app.schemas.intake as schemas
        from pydantic import TypeAdapter
        questions = TypeAdapter(list[schemas.Question]).validate_python(intake_sess.questions_json.get("questions", []))
        
        try:
            normalized = await _normalize_answers(
                idol=idol,
                idol_profile=idol_prof,
                idol_persona=idol_pers,
                milestones=milestones,
                user=user,
                questions=questions,
                answers=list(intake_sess.answers)
            )
            print("Normalization output successful")
            
            readiness_dict = normalized.readiness_by_gap.model_dump()
            gaps = [cat for cat, level in readiness_dict.items() if level in ("beginner", "intermediate")]
            if not gaps:
                gaps = ["learning", "career", "mindset"]
                
            user_profile_for_plan = {
                "weekly_hours": normalized.user_profile_patch.weekly_hours or 6,
                "goals": normalized.user_profile_patch.goals,
                "interests": normalized.user_profile_patch.interests,
                "constraints": normalized.user_profile_patch.constraints,
                "skills": [s.model_dump() for s in normalized.user_profile_patch.skills],
                "readiness_by_gap": readiness_dict,
            }
            
            idol_profile_for_plan = {
                "name": idol.name,
                "domain": idol.domain,
            }
            if idol_prof:
                idol_profile_for_plan.update({
                    "display_name": idol_prof.display_name,
                    "domains": idol_prof.domains,
                    "notable_themes": idol_prof.notable_themes,
                })
            
            idol_persona_for_plan = {}
            if idol_pers:
                idol_persona_for_plan = {
                    "voice_style": idol_pers.voice_style,
                    "principles": idol_pers.principles,
                    "era_context": idol_pers.era_context or "contemporary",
                    "default_frameworks": idol_pers.default_frameworks or [],
                }
            
            milestones_for_plan = [
                {"title": m.canonical_title, "age": m.age_at_event, "category": m.category}
                for m in milestones[:15]
                if m.age_at_event is not None
            ]
            
            target_age = 25
            if user.profile and user.profile.birth_date:
                from datetime import date
                today = date.today()
                target_age = today.year - user.profile.birth_date.year
                
            from app.services.planning.generator import generate_plan
            print(f"Generating plan with target_age={target_age}, gaps={gaps}")
            
            plan_items = await generate_plan(
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
                allowed_resources=[],
            )
            
            print(f"Generated {len(plan_items)} plan items successfully")
            
        except Exception as e:
            print("Error in finish pipeline:", e)
            import traceback
            traceback.print_exc()

asyncio.run(main())
