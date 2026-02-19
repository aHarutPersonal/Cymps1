from fastapi import APIRouter, status
from sqlalchemy import text

from app.core.db import engine

router = APIRouter(tags=["health"])


@router.get("/health", status_code=status.HTTP_200_OK)
async def health() -> dict:
    """Basic health check - returns OK if the service is running."""
    return {"status": "ok"}


@router.get("/ready", status_code=status.HTTP_200_OK)
async def ready() -> dict:
    """
    Readiness check - verifies the service can handle requests.
    Checks database connectivity.
    """
    checks = {"database": False}

    # Check database connection
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        checks["database"] = True
    except Exception:
        pass

    all_ready = all(checks.values())

    return {
        "status": "ready" if all_ready else "not_ready",
        "checks": checks,
    }
