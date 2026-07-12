import logging

from app.core.celery import celery_app
from app.core.async_runtime import run_async
from app.core.db import async_session_maker

logger = logging.getLogger(__name__)


@celery_app.task(bind=True)
def generate_book_module_resource(
    self,
    title: str,
    author: str | None,
    user_goal: str,
    source_context: str | None = None,
) -> dict:
    """
    Generate and cache one shared book-module resource in the background.

    Enqueued by the interactive learning-materials path so the Gutendex lookup
    and the long book-module LLM call never block a request. Idempotent: if the
    canonical key is already cached, the existing resource is reused.
    """
    logger.info(f"[BOOK_MODULE] Starting background generation for '{title}'")
    try:
        result = run_async(
            _generate_book_module_resource_async(title, author, user_goal, source_context)
        )
        logger.info(f"[BOOK_MODULE] Completed '{title}': {result}")
        return result
    except Exception as e:
        logger.exception(f"[BOOK_MODULE] Error generating '{title}': {e}")
        raise


async def _generate_book_module_resource_async(
    title: str,
    author: str | None,
    user_goal: str,
    source_context: str | None,
) -> dict:
    from app.services.content_resources import get_or_create_book_module_resource

    async with async_session_maker() as db:
        resource = await get_or_create_book_module_resource(
            db,
            title=title,
            author=author,
            user_goal=user_goal,
            source_context=source_context,
        )
        await db.commit()
        return {
            "status": "completed",
            "content_resource_id": str(resource.id),
            "canonical_key": resource.canonical_key,
        }
