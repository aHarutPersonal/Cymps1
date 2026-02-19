import asyncio
from sqlalchemy import text
from app.core.db import async_session_maker

async def cleanup_zombies():
    async with async_session_maker() as db:
        tables = ["idol_import_jobs", "idol_suggest_jobs", "plan_generation_jobs", "plan_item_detail_jobs"]
        for t in tables:
            print(f"Cleaning {t}...")
            await db.execute(text(f"UPDATE {t} SET status='failed', error_message='System restart' WHERE status='running'"))
        await db.commit()
    print("Cleanup complete.")

if __name__ == "__main__":
    asyncio.run(cleanup_zombies())
