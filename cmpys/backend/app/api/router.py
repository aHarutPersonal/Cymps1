from fastapi import APIRouter

from app.api.v1 import (
    achievements,
    auth,
    chat,
    comparison,
    content_resources,
    debug,
    feed,
    idea_cards,
    idols,
    intake,
    jobs,
    me,
    notes,
    plans,
    sessions,
    tools,
    daily_tasks,
)

router = APIRouter(prefix="/api/v1")

# Include v1 routers
router.include_router(auth.router)
router.include_router(me.router)
router.include_router(idols.router)
router.include_router(jobs.router)
router.include_router(achievements.router)
router.include_router(comparison.router)
router.include_router(content_resources.router)
router.include_router(plans.router)
router.include_router(plans.items_router)  # /plan-items
router.include_router(notes.router)
router.include_router(feed.router)
router.include_router(idea_cards.router)
router.include_router(chat.router)
router.include_router(intake.router)
router.include_router(sessions.router)
router.include_router(debug.router)
router.include_router(tools.router, prefix="/tools", tags=["tools"])
router.include_router(daily_tasks.router)


@router.get("/")
async def root() -> dict:
    """API v1 root endpoint."""
    return {"message": "Welcome to cmpys API v1"}
