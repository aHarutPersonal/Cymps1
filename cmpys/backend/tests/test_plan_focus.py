import uuid

import pytest
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.sessions import _get_or_create_session_plan_job
from app.core.db import engine
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.plan_job import PlanGenerationJob
from app.models.user import User
from app.schemas.plan import PlanGenerateRequest


def test_plan_request_accepts_complete_intake_outcome():
    focus = "A detailed learning outcome with observable evidence. " * 60
    request = PlanGenerateRequest(idolId="mentor", targetAge=28, focus=focus)
    assert request.focus == focus
    with pytest.raises(ValidationError):
        PlanGenerateRequest(idolId="mentor", targetAge=28, focus="x" * 10001)


@pytest.mark.asyncio
async def test_staged_plan_preserves_long_goal_in_database():
    # Exercise the production staging helper against migrated PostgreSQL, with
    # its commits isolated inside savepoints and the outer transaction rolled back.
    async with engine.connect() as connection:
        transaction = await connection.begin()
        try:
            async with AsyncSession(
                bind=connection,
                expire_on_commit=False,
                join_transaction_mode="create_savepoint",
            ) as db:
                user = User(
                    email=f"focus-{uuid.uuid4()}@example.invalid",
                    password_hash="test-not-a-login",
                )
                idol = Idol(name="Fictional mentor", domain="business")
                db.add_all([user, idol])
                await db.flush()
                session = IntakeSession(
                    user_id=user.id,
                    idol_id=idol.id,
                    user_age=28,
                    phase=SessionPhase.COMPARISON,
                )
                db.add(session)
                await db.flush()
                focus = (
                    "Analyze a fictional business and explain profit versus cash. "
                    * 100
                )
                job = await _get_or_create_session_plan_job(
                    db, session=session, user_id=user.id, weekly_hours=8, focus=focus
                )
                job_id = job.id
                db.expunge(job)
                stored = await db.get(PlanGenerationJob, job_id)
                assert stored.focus == focus
                assert stored.weekly_hours == 8
                assert stored.session_id == session.id
                repeated = await _get_or_create_session_plan_job(
                    db, session=session, user_id=user.id, weekly_hours=8, focus=focus
                )
                assert repeated.id == job_id
        finally:
            await transaction.rollback()
