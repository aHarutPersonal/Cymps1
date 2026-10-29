"""Opt-in PostgreSQL regression for opening a mission whose prefetch is queued.

The ORM bulk update that promotes the job expires its SQL-computed
``updated_at``; the detail endpoint then reads it synchronously. All rows are
rolled back after verification.
"""
import asyncio
import os
from unittest.mock import patch
from uuid import uuid4

from sqlalchemy import inspect
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from app.api.v1.plans import _detail_job_is_stale, _promote_prefetched_detail_job
from app.core.config import settings
from app.models.item_detail_job import PlanItemDetailJob
from app.models.plan import Plan, PlanItem
from app.models.user import User


async def verify_promoted_job_timestamp_is_loaded():
    engine = create_async_engine(settings.database_url)
    try:
        async with engine.connect() as connection:
            outer = await connection.begin()
            try:
                async with AsyncSession(
                    connection, expire_on_commit=False,
                    join_transaction_mode="create_savepoint",
                ) as db:
                    user = User(email=f"probe-{uuid4().hex}@example.com", password_hash="x")
                    db.add(user)
                    await db.flush()
                    plan = Plan(user_id=user.id, target_age=30)
                    db.add(plan)
                    await db.flush()
                    item = PlanItem(
                        plan_id=plan.id, title="Probe mission",
                        description="Probe", success_metric="Probe",
                    )
                    db.add(item)
                    await db.flush()
                    job = PlanItemDetailJob(
                        plan_item_id=item.id, user_id=user.id,
                        status="pending", step="prefetch_queued",
                    )
                    db.add(job)
                    await db.commit()

                    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async"):
                        assert await _promote_prefetched_detail_job(db, job) == "promoted"

                    # The detail endpoint calls this synchronously next.
                    assert "updated_at" not in inspect(job).expired_attributes
                    assert _detail_job_is_stale(job) is False
                    assert (job.status, job.step) == ("queued", "user_priority")
            finally:
                await outer.rollback()
    finally:
        await engine.dispose()


def test_promoted_prefetch_job_timestamp_against_postgres():
    if os.environ.get("RUN_POSTGRES_INTEGRATION") != "1":
        import pytest
        pytest.skip("Set RUN_POSTGRES_INTEGRATION=1 for the PostgreSQL regression")
    asyncio.run(verify_promoted_job_timestamp_is_loaded())


if __name__ == "__main__":
    asyncio.run(verify_promoted_job_timestamp_is_loaded())
    print("PASS: promoted prefetch job keeps a loaded timestamp; rows rolled back")
