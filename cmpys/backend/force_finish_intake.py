import asyncio
from app.core.db import async_session_maker
from app.models.intake import IntakeSession
from app.models.user import User
from app.api.v1.intake import finish_intake
from sqlalchemy import select
from sqlalchemy.orm import selectinload

async def main():
    async with async_session_maker() as db:
        stmt = (select(IntakeSession)
                .options(selectinload(IntakeSession.answers))
                .order_by(IntakeSession.created_at.desc()).limit(10))
        res = await db.execute(stmt)
        sessions = res.scalars().all()
        
        session = None
        for s in sessions:
            if s.answers and len(s.answers) >= 6:
                session = s
                break
                
        if not session:
            print("No completed session found.")
            return
            
        print(f"Running finish_intake for session {session.id}")
        
        if session.status.value == 'completed':
            session.status = "in_progress"
            await db.commit()
            
        user_stmt = select(User).where(User.id == session.user_id)
        user_res = await db.execute(user_stmt)
        user = user_res.scalar_one_or_none()
        
        try:
            response = await finish_intake(session_id=session.id, db=db, current_user=user)
            print("Successfully finished intake! Plan generated with ID:", response.job_id)
        except Exception as e:
            print("Error while finishing intake:")
            import traceback
            traceback.print_exc()

asyncio.run(main())
