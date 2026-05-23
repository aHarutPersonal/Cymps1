import asyncio
from app.core.db import async_session_maker
from app.models.intake import IntakeSession

async def main():
    async with async_session_maker() as db_session:
        from sqlalchemy import select
        # Find the latest session
        stmt = select(IntakeSession).order_by(IntakeSession.created_at.desc()).limit(1)
        res = await db_session.execute(stmt)
        session = res.scalar_one_or_none()
        
        if not session:
            print("No session found")
            return
            
        print(f"Testing the API locally for session: {session.id}")
        
    # We use httpx to hit the endpoints, skipping authentication if we can't easily fake it or we can just run the test_finish2 but imported
    # Actually, test_finish2.py showed it worked except for the DB commit. 
    # Let me just run test_finish2.py but point it to the DB session handling exactly like the API.

asyncio.run(main())
