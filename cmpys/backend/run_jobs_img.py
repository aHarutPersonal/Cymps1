import asyncio
from app.core.db import async_session_maker
from app.api.v1.idols import generate_idol_image

async def fake_user():
    return type('User', (), {'id': '1'})()

async def main():
    async with async_session_maker() as db:
        res = await generate_idol_image(
            idol_id='da5159d6-6def-4d65-90e6-e1ab1645e809',
            age=28,
            db=db,
            current_user=await fake_user()
        )
        print("Result:", res)

asyncio.run(main())
