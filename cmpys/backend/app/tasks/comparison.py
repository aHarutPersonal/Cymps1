import json
import logging

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.celery import celery_app
from app.core.async_runtime import run_async
from app.core.db import async_session_maker

logger = logging.getLogger(__name__)


@celery_app.task(bind=True)
def backfill_comparison_scores(self, session_id: str) -> dict:
    """
    Generate structured comparison scores for a session that has a comparison
    verdict but no comparison_scores_json (the scorer failed during the
    results stream, or the session predates the feature).

    Enqueued when such a session is fetched, so old sessions self-heal and
    the client stops falling back to seed numbers. Idempotent: no-ops when
    scores already exist.
    """
    logger.info(f"[CMP_SCORES] Starting backfill for session={session_id}")
    try:
        result = run_async(_backfill_comparison_scores_async(session_id))
        logger.info(f"[CMP_SCORES] Backfill for session={session_id}: {result}")
        return result
    except Exception as e:
        logger.exception(f"[CMP_SCORES] Backfill error for session={session_id}: {e}")
        raise


async def _backfill_comparison_scores_async(session_id: str) -> dict:
    from app.models.chat import ChatThread
    from app.models.intake import IntakeSession
    from app.services.comparison.scoring import generate_comparison_scores
    from app.services.llm.client import get_llm_client
    from app.services.transcripts import build_chat_history_json

    async with async_session_maker() as db:
        result = await db.execute(
            select(IntakeSession)
            .options(selectinload(IntakeSession.idol))
            .where(IntakeSession.id == session_id)
        )
        session = result.scalar_one_or_none()
        if not session:
            return {"status": "skipped", "reason": "session_not_found"}
        if session.comparison_scores_json:
            return {"status": "skipped", "reason": "scores_already_present"}
        if not session.comparison_output:
            return {"status": "skipped", "reason": "no_comparison_output"}

        # Same context the streaming scorer uses: transcript reconstructed
        # from the interview thread with user turns wrapped as untrusted DATA.
        interview_transcript = ""
        if session.interview_thread_id:
            thread_result = await db.execute(
                select(ChatThread)
                .options(selectinload(ChatThread.messages))
                .where(ChatThread.id == session.interview_thread_id)
            )
            thread = thread_result.scalar_one_or_none()
            if thread and thread.messages:
                interview_transcript = build_chat_history_json(
                    thread.messages, sanitize_user=True
                )

        user_profile = {
            "age": session.user_age,
            "financial_status": session.user_financial_status,
            "interests": session.user_interests,
        }

        scores = await generate_comparison_scores(
            get_llm_client(),
            idol_name=session.idol.name if session.idol else "Unknown",
            user_age=session.user_age,
            user_profile_json=json.dumps(user_profile),
            interview_transcript_json=interview_transcript,
            idol_facts_json=json.dumps(session.idol_facts_json or {}),
            comparison_summary=session.comparison_output or "",
        )
        if not scores:
            return {"status": "failed", "reason": "scorer_returned_none"}

        session.comparison_scores_json = scores
        await db.commit()
        return {"status": "completed", "session_id": str(session_id)}
