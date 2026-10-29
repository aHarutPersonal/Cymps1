"""R1-I6: ``POST /idols/import`` never pays to re-ingest a prepared idol.

An existing idol used to get a new paid ingestion job whenever no job was
queued or running, even after one had completed. Now a completed import, or
any import attempted in the last 24 hours, is returned as it stands, and new
paid imports are capped per user per day (429 with a clear detail).
"""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api.v1 import idols
from app.models.idol import CatalogStatus
from app.schemas.idol import IdolImportRequest

NOW = datetime.now(timezone.utc)


def _job(job_id: str, status: str, *, age: timedelta, step: str = "done"):
    stamp = NOW - age
    return SimpleNamespace(
        id=job_id, status=status, step=step, created_at=stamp, updated_at=stamp,
        error_message=None,
    )


def _existing(*jobs, idol_status=CatalogStatus.PENDING):
    idol = SimpleNamespace(
        id="idol-1", name="Warren Buffett", import_jobs=list(jobs), status=idol_status,
    )
    return SimpleNamespace(idol_id="idol-1", idol=idol)


class _Result:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


def _db(existing, *, imports_today: int = 0) -> AsyncMock:
    db = AsyncMock()
    # The database assigns primary keys on flush; give added rows one at once.
    db.add = MagicMock(side_effect=lambda row: setattr(row, "id", f"new-{type(row).__name__}"))
    db.execute.return_value = _Result(existing)
    db.scalar.return_value = imports_today
    return db


def _request(provider="wikidata", **extra) -> IdolImportRequest:
    return IdolImportRequest(provider=provider, externalId="Q47213", **extra)


async def _import(db, request=None):
    with patch("app.tasks.ingestion.run_idol_ingestion") as task:
        response = await idols.import_idol(request or _request(), db, SimpleNamespace(id="user-1"))
    return response, task


@pytest.mark.asyncio
async def test_completed_import_is_returned_instead_of_reingesting() -> None:
    completed = _job("job-done", "completed", age=timedelta(days=40))
    old_failure = _job("job-old", "failed", age=timedelta(days=60))
    db = _db(_existing(old_failure, completed))

    response, task = await _import(db)

    assert (response.idolId, response.jobId, response.status) == ("idol-1", "job-done", "completed")
    db.add.assert_not_called()
    task.delay.assert_not_called()


@pytest.mark.asyncio
async def test_a_recent_failed_import_never_blocks_a_retry() -> None:
    """Follow-up ruling: a FAILED latest import always allows a new job."""
    recent_failure = _job("job-recent", "failed", age=timedelta(hours=3), step="error")
    db = _db(_existing(_job("job-older", "failed", age=timedelta(hours=20), step="error"),
                       recent_failure), imports_today=2)

    response, task = await _import(db)

    assert response.status == "queued" and response.jobId not in {"job-recent", "job-older"}
    (new_job,) = [call.args[0] for call in db.add.call_args_list]
    assert new_job.idol_id == "idol-1" and new_job.user_id == "user-1"
    task.delay.assert_called_once()


@pytest.mark.asyncio
async def test_a_failure_after_an_earlier_completion_retries() -> None:
    """The latest job decides: an earlier completion doesn't block a retry."""
    db = _db(_existing(_job("job-done", "completed", age=timedelta(days=5)),
                       _job("job-failed", "failed", age=timedelta(hours=1), step="error")))

    response, task = await _import(db)

    assert response.status == "queued"
    task.delay.assert_called_once()


@pytest.mark.asyncio
async def test_a_stale_queued_import_is_failed_and_retried() -> None:
    stale = _job("job-stale", "queued", age=timedelta(minutes=30), step="queued")
    db = _db(_existing(stale))

    response, task = await _import(db)

    assert stale.status == "failed"
    assert response.status == "queued" and response.jobId != "job-stale"
    task.delay.assert_called_once()


@pytest.mark.asyncio
@pytest.mark.parametrize("status", ["completed", "published"])
async def test_a_completed_or_published_latest_import_is_returned(status) -> None:
    db = _db(_existing(_job("job-failed", "failed", age=timedelta(days=9), step="error"),
                       _job("job-latest", status, age=timedelta(hours=2))))

    response, task = await _import(db)

    assert (response.jobId, response.status) == ("job-latest", status)
    db.add.assert_not_called()
    task.delay.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("job_status", ["completed", "published"])
async def test_a_reused_job_of_a_published_idol_reports_published(job_status) -> None:
    """The app's ``isPublished`` branch keys on the response status."""
    db = _db(_existing(_job("job-latest", job_status, age=timedelta(hours=2)),
                       idol_status=CatalogStatus.PUBLISHED))

    response, task = await _import(db)

    assert (response.idolId, response.jobId, response.status) == (
        "idol-1", "job-latest", "published",
    )
    db.add.assert_not_called()
    task.delay.assert_not_called()


@pytest.mark.asyncio
async def test_a_published_idol_with_a_selection_record_only_reports_published() -> None:
    db = _db(_existing(_job("job-select", "done", age=timedelta(hours=1), step="selected"),
                       idol_status=CatalogStatus.PUBLISHED))

    response, _ = await _import(db)

    assert (response.jobId, response.status) == ("job-select", "published")


@pytest.mark.asyncio
async def test_a_fresh_active_job_of_a_published_idol_keeps_its_status() -> None:
    db = _db(_existing(_job("job-running", "running", age=timedelta(minutes=1)),
                       idol_status=CatalogStatus.PUBLISHED))

    response, _ = await _import(db)

    assert (response.jobId, response.status) == ("job-running", "running")


@pytest.mark.asyncio
async def test_a_selection_record_never_hides_a_failed_import() -> None:
    """/idols/{id}/select writes a status "done" bookkeeping row; it is not an import."""
    db = _db(_existing(_job("job-failed", "failed", age=timedelta(hours=2), step="error"),
                       _job("job-select", "done", age=timedelta(hours=1), step="selected")))

    response, task = await _import(db)

    assert response.status == "queued"
    task.delay.assert_called_once()


@pytest.mark.asyncio
async def test_the_cap_still_applies_when_retrying_a_failed_import() -> None:
    db = _db(_existing(_job("job-failed", "failed", age=timedelta(hours=2), step="error")),
             imports_today=idols.IMPORT_DAILY_LIMIT_PER_USER)

    with pytest.raises(HTTPException) as raised:
        await _import(db)

    assert raised.value.status_code == 429
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_a_fresh_active_import_is_still_returned() -> None:
    running = _job("job-running", "running", age=timedelta(minutes=1))
    db = _db(_existing(running))

    response, task = await _import(db)

    assert (response.jobId, response.status) == ("job-running", "running")
    db.add.assert_not_called()
    task.delay.assert_not_called()


@pytest.mark.asyncio
async def test_old_failure_only_starts_a_new_import_within_the_daily_cap() -> None:
    db = _db(_existing(_job("job-old", "failed", age=timedelta(days=3))), imports_today=4)

    response, task = await _import(db)

    assert response.status == "queued"
    (new_job,) = [call.args[0] for call in db.add.call_args_list]
    assert new_job.idol_id == "idol-1" and new_job.user_id == "user-1"
    task.delay.assert_called_once()


@pytest.mark.asyncio
async def test_existing_idol_reimport_over_the_daily_cap_is_429() -> None:
    db = _db(_existing(_job("job-old", "failed", age=timedelta(days=3))),
             imports_today=idols.IMPORT_DAILY_LIMIT_PER_USER)

    with pytest.raises(HTTPException) as raised:
        await _import(db)

    assert raised.value.status_code == 429
    assert "5" in raised.value.detail and "24 hours" in raised.value.detail
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_new_idol_over_the_daily_cap_is_429_before_any_lookup_or_write() -> None:
    db = _db(None, imports_today=idols.IMPORT_DAILY_LIMIT_PER_USER)

    with patch.object(idols, "fetch_entity_by_id", AsyncMock()) as fetch:
        with pytest.raises(HTTPException) as raised:
            await _import(db)

    assert raised.value.status_code == 429
    fetch.assert_not_awaited()
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_new_idol_under_the_cap_is_imported() -> None:
    db = _db(None, imports_today=0)

    response, task = await _import(db, _request("llm", name="Ada Lovelace"))

    assert response.status == "queued"
    assert len(db.add.call_args_list) == 3  # idol, external id, job
    task.delay.assert_called_once()


def test_the_daily_cap_counts_only_imports_this_user_actually_started() -> None:
    statement = idols._imports_in_last_day_statement("user-1", NOW)
    sql = str(statement.compile(compile_kwargs={"literal_binds": True}))
    assert "idol_import_jobs.user_id =" in sql and "idol_import_jobs.created_at >=" in sql
    # Selection bookkeeping rows are not imports.
    assert "'selected'" in sql
    # A job that failed while still queued never reached a worker: no cost.
    assert "'failed'" in sql and "'queued'" in sql
