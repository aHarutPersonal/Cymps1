from __future__ import annotations

import pytest

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

        async def execute(self, _statement):
            self.calls += 1
            return Result()

    db = Database()
    response = await get_job_status("plan-job-1", db, job_type="plan")

    assert response.id == "plan-job-1"
    assert db.calls == 1
