import asyncio
from sqlalchemy import select
from app.core.db import async_session_maker
from app.models.idol import Idol

async def main():
    async with async_session_maker() as db:
        stmt = select(Idol).limit(1)
        res = await db.execute(stmt)
        idol = res.scalar_one_or_none()
        if idol:
            print(f"IDOL_ID={idol.id}")
            print(f"IDOL_NAME={idol.name}")

asyncio.run(main())
