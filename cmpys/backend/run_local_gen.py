import asyncio
from sqlalchemy import select
from app.core.db import async_session_maker
from app.models.idol import Idol
from app.api.v1.idols import generate_idol_image

async def fake_user():
    return type('User', (), {'id': '1'})()

async def main():
    async with async_session_maker() as db:
        stmt = select(Idol).limit(1)
        res = await db.execute(stmt)
        idol = res.scalar_one_or_none()
        if not idol:
            print("No idol")
            return
            
        print(f"Generating image for {idol.name}")
        res = await generate_idol_image(
            idol_id=idol.id,
            age=30,
            db=db,
            current_user=await fake_user()
        )
        print("Result:", res)

asyncio.run(main())
