import asyncio

from fastapi import APIRouter, Response, status
from redis.asyncio import Redis
from sqlalchemy import text

from app.core.config import settings
from app.core.db import engine

router = APIRouter(tags=["health"])


@router.get("/health", status_code=status.HTTP_200_OK)
async def health() -> dict:
    """Basic health check - returns OK if the service is running."""
    return {"status": "ok"}


@router.get("/ready", status_code=status.HTTP_200_OK)
async def ready(response: Response) -> dict:
    """
    Readiness check - verifies the service can handle requests.
    Checks database connectivity.
    """
    database_ready, redis_ready = await asyncio.gather(
        _database_ready(),
        _redis_ready(),
    )
    checks = {
        "database": database_ready,
        "redis": redis_ready,
    }

    all_ready = all(checks.values())
    if not all_ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    return {
        "status": "ready" if all_ready else "not_ready",
        "checks": checks,
    }


async def _database_ready() -> bool:
    try:
        async with asyncio.timeout(3):
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


async def _redis_ready() -> bool:
    client = Redis.from_url(
        settings.redis_url,
        socket_connect_timeout=3,
        socket_timeout=3,
    )
    try:
        async with asyncio.timeout(3):
            return bool(await client.ping())
    except Exception:
        return False
    finally:
        await client.aclose()
