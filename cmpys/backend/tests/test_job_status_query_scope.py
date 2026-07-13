from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.api.v1.jobs import get_job_status
from app.models.plan_job import PlanGenerationJob


@pytest.mark.asyncio
async def test_known_plan_job_type_uses_one_database_query() -> None:
    job = PlanGenerationJob(
        id="plan-job-1",
        user_id="user-1",
        idol_id=None,
        status="pending",
        step="queued",
        progress_percent=0,
        error_message=None,
        duration_weeks=12,
        weekly_hours=10,
        thinking_text=None,
    )

    class Result:
        def scalar_one_or_none(self):
            return job

    class Database:
        calls = 0
        statement = None

        async def execute(self, statement):
            self.calls += 1
            self.statement = statement
            return Result()

    db = Database()
    response = await get_job_status(
        "plan-job-1",
        db,
        SimpleNamespace(id="user-1"),
        job_type="plan",
    )

    assert response.id == "plan-job-1"
    assert db.calls == 1
    assert "plan_generation_jobs.user_id" in str(db.statement)
    assert "user-1" in db.statement.compile().params.values()


@pytest.mark.parametrize(
    ("job_type", "ownership_column"),
    [
        ("import", "idol_import_jobs.user_id"),
        ("plan", "plan_generation_jobs.user_id"),
        ("plan_detail", "plan_item_detail_jobs.user_id"),
        ("suggest", "idol_suggest_jobs.user_id"),
    ],
)
@pytest.mark.asyncio
async def test_job_status_hides_jobs_owned_by_another_user(
    job_type: str,
    ownership_column: str,
) -> None:
    class Result:
        def scalar_one_or_none(self):
            return None

    class Database:
        statement = None

        async def execute(self, statement):
            self.statement = statement
            return Result()

    db = Database()
    with pytest.raises(HTTPException) as exc_info:
        await get_job_status(
            "plan-job-1",
            db,
            SimpleNamespace(id="other-user"),
            job_type=job_type,
        )

    assert exc_info.value.status_code == 404
    assert ownership_column in str(db.statement)
    assert "other-user" in db.statement.compile().params.values()
