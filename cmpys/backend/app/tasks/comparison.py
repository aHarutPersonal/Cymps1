import json
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.celery import celery_app
from app.core.async_runtime import run_async
from app.core.db import async_session_maker

logger = logging.getLogger(__name__)


class ComparisonScoresUnavailableError(RuntimeError):
    """Raised so Celery records exhausted score generation as a real failure."""


@celery_app.task(bind=True, max_retries=3, soft_time_limit=65, time_limit=75)
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
    except Exception as e:
        logger.exception(f"[CMP_SCORES] Backfill error for session={session_id}: {e}")
        raise
    logger.info(f"[CMP_SCORES] Backfill for session={session_id}: {result}")
    if result.get("status") == "retry_wait":
        delay = int(result.get("retry_in_seconds") or 15)
        raise self.retry(
            exc=ComparisonScoresUnavailableError(
                str(result.get("reason") or "scorer_returned_none")
            ),
            countdown=delay,
        )
    if result.get("status") == "failed":
        # Do not return a failure-shaped success.  Monitoring must see the
        # terminal failure while the persisted session state tells the client
        # that an explicit retry is available.
        raise ComparisonScoresUnavailableError(
            str(result.get("reason") or "comparison_scores_failed")
        )
    return result


async def _backfill_comparison_scores_async(session_id: str) -> dict:
    from app.models.chat import ChatThread
    from app.models.intake import IntakeSession
    from app.services.comparison.scoring import (
        COMPARISON_SCORE_MAX_ATTEMPTS,
        COMPARISON_SCORE_PROVIDER_TIMEOUT_SECONDS,
        COMPARISON_SCORE_TOTAL_TIMEOUT_SECONDS,
        comparison_scores_are_current,
        comparison_score_retry_delay,
        generate_comparison_scores,
    )
    from app.services.interview_inputs import (
        build_interview_plan_inputs,
        provider_interview_plan_inputs,
    )
    from app.services.llm.client import get_llm_client
    from app.services.transcripts import build_chat_history_json

    async with async_session_maker() as db:
        result = await db.execute(
            select(IntakeSession)
            .options(selectinload(IntakeSession.idol))
            .where(IntakeSession.id == session_id)
            .with_for_update()
        )
        session = result.scalar_one_or_none()
        if not session:
            return {"status": "skipped", "reason": "session_not_found"}
        if comparison_scores_are_current(session.comparison_scores_json):
            return {"status": "skipped", "reason": "scores_already_present"}
        if not session.comparison_output:
            return {"status": "skipped", "reason": "no_comparison_output"}

        now = datetime.now(timezone.utc)
        current_status = str(
            getattr(session, "comparison_scores_status", None) or "queued"
        )
        last_attempt = getattr(session, "comparison_scores_last_attempt_at", None)
        if last_attempt is not None and last_attempt.tzinfo is None:
            last_attempt = last_attempt.replace(tzinfo=timezone.utc)
        if (
            current_status == "running"
            and last_attempt is not None
            and now - last_attempt < timedelta(minutes=2)
        ):
            return {"status": "skipped", "reason": "scores_already_running"}

        attempts = int(getattr(session, "comparison_scores_attempts", 0) or 0)
        if current_status == "failed" and attempts >= COMPARISON_SCORE_MAX_ATTEMPTS:
            return {"status": "failed", "reason": "attempts_exhausted"}

        session.comparison_scores_status = "running"
        session.comparison_scores_attempts = attempts + 1
        session.comparison_scores_error = None
        session.comparison_scores_last_attempt_at = now
        session.comparison_scores_next_retry_at = None
        # Release the row lock and DB connection before waiting on providers.
        await db.commit()

        # Same context the streaming scorer uses: transcript reconstructed
        # from the interview thread with user turns wrapped as untrusted DATA.
        interview_transcript = ""
        interview_messages = []
        if session.interview_thread_id:
            thread_result = await db.execute(
                select(ChatThread)
                .options(selectinload(ChatThread.messages))
                .where(ChatThread.id == session.interview_thread_id)
            )
            thread = thread_result.scalar_one_or_none()
            if thread and thread.messages:
                interview_messages = list(thread.messages)
                interview_transcript = build_chat_history_json(
                    thread.messages, sanitize_user=True
                )

        session_goal = getattr(session, "user_goal", None)
        if not isinstance(session_goal, str):
            session_goal = None
        plan_inputs = build_interview_plan_inputs(
            interview_messages,
            session_goal=session_goal,
        )
        learner_baseline = (
            provider_interview_plan_inputs(plan_inputs)
            if plan_inputs["answered_keys"]
            else None
        )

        user_profile = {
            "age": session.user_age,
            "financial_status": session.user_financial_status,
            "interests": session.user_interests,
            "goal": session_goal,
            "learner_baseline": learner_baseline,
        }

        scores = await generate_comparison_scores(
            get_llm_client(
                timeout=COMPARISON_SCORE_PROVIDER_TIMEOUT_SECONDS,
                max_tokens=3500,
                tier="fast",
                thinking_level="minimal",
            ),
            idol_name=session.idol.name if session.idol else "Unknown",
            user_age=session.user_age,
            user_profile_json=json.dumps(user_profile),
            interview_transcript_json=interview_transcript,
            idol_facts_json=json.dumps(session.idol_facts_json or {}),
            comparison_summary=session.comparison_output or "",
            achievement_baseline_status=plan_inputs["achievement_baseline_status"],
            timeout_s=COMPARISON_SCORE_TOTAL_TIMEOUT_SECONDS,
        )
        if not scores:
            attempts = int(session.comparison_scores_attempts or 1)
            retryable = attempts < COMPARISON_SCORE_MAX_ATTEMPTS
            delay = comparison_score_retry_delay(attempts)
            session.comparison_scores_status = "retry_wait" if retryable else "failed"
            session.comparison_scores_error = (
                "The comparison service did not return valid evidence classifications."
            )
            session.comparison_scores_next_retry_at = (
                datetime.now(timezone.utc) + timedelta(seconds=delay)
                if retryable
                else None
            )
            await db.commit()
            return {
                "status": "retry_wait" if retryable else "failed",
                "reason": "scorer_returned_none",
                "attempts": attempts,
                "retry_in_seconds": delay if retryable else None,
            }

        session.comparison_scores_json = scores
        session.comparison_scores_status = "ready"
        session.comparison_scores_error = None
        session.comparison_scores_next_retry_at = None
        await db.commit()
        return {"status": "completed", "session_id": str(session_id)}
