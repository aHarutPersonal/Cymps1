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
            res = await _normalize_answers(
                idol=idol,
                idol_profile=idol_prof,
                idol_persona=idol_pers,
                milestones=milestones,
                user=user,
                questions=questions,
                answers=list(intake_sess.answers)
            )
            print("Normalization output:", res)
        except Exception as e:
            print("Error in _normalize_answers:", e)
            import traceback
            traceback.print_exc()

asyncio.run(main())
