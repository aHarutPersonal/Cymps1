from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from app.api.dependencies import get_current_user
from app.api.v1 import jobs
from app.tasks import ingestion


def _job():
    return SimpleNamespace(
        id="job-1", user_id="owner", idol_id="idol-1", idol=SimpleNamespace(name="Ada"),
        status="queued", step="queued", progress_percent=0, error_message=None,
        updated_at=datetime.now(timezone.utc), created_at=datetime.now(timezone.utc),
    )


def test_job_start_requires_authentication_dependency():
    route = next(route for route in jobs.router.routes if route.path.endswith("/start"))
    assert get_current_user in [dependency.call for dependency in route.dependant.dependencies]


@pytest.mark.asyncio
async def test_job_start_is_scoped_to_owner_and_locked(monkeypatch):
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: None)
    delay = MagicMock()
    monkeypatch.setattr(ingestion.run_idol_ingestion, "delay", delay)
    with pytest.raises(HTTPException) as error:
        await jobs.start_job("someone-elses-job", db, SimpleNamespace(id="owner"))
    assert error.value.status_code == 404
    statement = db.execute.await_args.args[0]
    assert "idol_import_jobs.user_id =" in str(statement)
    assert "owner" in statement.compile().params.values()
    assert "FOR UPDATE" in str(statement)
    delay.assert_not_called()


@pytest.mark.asyncio
async def test_repeated_start_only_dispatches_once(monkeypatch):
    job = _job()
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: job)
    delay = MagicMock()
    monkeypatch.setattr(ingestion.run_idol_ingestion, "delay", delay)
    first = await jobs.start_job("job-1", db, SimpleNamespace(id="owner"))
    second = await jobs.start_job("job-1", db, SimpleNamespace(id="owner"))
    assert first.id == second.id == "job-1"
    delay.assert_called_once_with("job-1")


@pytest.mark.asyncio
@pytest.mark.parametrize("state", ["running", "completed"])
async def test_running_and_completed_import_jobs_are_not_restarted(monkeypatch, state):
    job = _job()
    job.status = state
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: job)
    delay = MagicMock()
    monkeypatch.setattr(ingestion.run_idol_ingestion, "delay", delay)
    response = await jobs.start_job("job-1", db, SimpleNamespace(id="owner"))
    assert response.status == state
    delay.assert_not_called()


@pytest.mark.asyncio
async def test_duplicate_import_delivery_skips_all_paid_work(monkeypatch):
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(rowcount=0)
    db.get.return_value = SimpleNamespace(status="running")
    class Context:
        async def __aenter__(self):
            return db
        async def __aexit__(self, *_args):
            return None
    monkeypatch.setattr(ingestion, "async_session_maker", Context)
    source = AsyncMock()
    monkeypatch.setattr(ingestion, "_collect_wikipedia_source", source)
    result = await ingestion._run_ingestion_async("job-1")
    assert result == {"status": "skipped", "job_status": "running"}
    source.assert_not_awaited()
    db.execute.assert_awaited_once()
