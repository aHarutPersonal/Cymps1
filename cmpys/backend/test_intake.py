import asyncio
from app.core.db import async_session_maker
from app.models.intake import IntakeSession, IntakeAnswer
from sqlalchemy import select
from sqlalchemy.orm import selectinload

async def main():
    async with async_session_maker() as session:
        stmt = select(IntakeSession).order_by(IntakeSession.created_at.desc()).limit(1)
        result = await session.execute(stmt)
        intake_sess = result.scalar_one_or_none()
        
        if intake_sess:
            print(f"Session: {intake_sess.id}, Status: {intake_sess.status}")
            print(f"Answers count: {len(intake_sess.answers)}")
            # show questions
            import json
            questions = intake_sess.questions_json.get("questions", [])
            print(f"Questions count: {len(questions)}")
            
            # test answering the last question
            # test finishing the session
            
asyncio.run(main())
