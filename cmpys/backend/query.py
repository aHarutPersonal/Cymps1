import asyncio
from app.core.db import async_session_maker
from app.models.suggest_job import IdolSuggestJob
from sqlalchemy import select

async def main():
    async with async_session_maker() as session:
        result = await session.execute(select(IdolSuggestJob).where(IdolSuggestJob.id == '6cc7c102-78c4-42ed-a1d3-6db8ebf3e054'))
        job = result.scalar_one_or_none()
        if job:
            print(f"Status: {job.status}, Interests: {job.interests}, Res: {job.result_json}")

asyncio.run(main())
