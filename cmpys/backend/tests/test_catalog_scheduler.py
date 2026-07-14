from contextlib import asynccontextmanager
from types import SimpleNamespace

import pytest

from app.core.celery import celery_app
from app.tasks import catalog
from app.tasks.catalog import retry_delay_seconds
from app.tasks.ingestion import _idol_catalog_quality
from app.models.ingest_job import IngestKind, IngestState


def test_catalog_retry_backoff_is_bounded():
    assert retry_delay_seconds(1) == 300
    assert retry_delay_seconds(2) == 600
    assert retry_delay_seconds(3) == 1200
    assert retry_delay_seconds(99) == 21600


def test_catalog_supports_quote_ingestion_jobs():
    assert IngestKind.QUOTE.value == "quote"


def test_idol_catalog_quality_requires_confident_timeline_evidence():
    class Event:
        def __init__(self, confidence, evidence=True):
            self.confidence = confidence
            self.evidence = [{"source": "test"}] if evidence else []

    good_score, good_publishable = _idol_catalog_quality(
        profile_confidence=0.9,
        profile_evidence_count=2,
        timeline_events=[Event(0.9), Event(0.8), Event(0.7)],
        persona_generated=True,
        persona_evidence_count=2,
    )
    weak_score, weak_publishable = _idol_catalog_quality(
        profile_confidence=0.9,
        profile_evidence_count=1,
        timeline_events=[Event(0.2)],
        persona_generated=True,
        persona_evidence_count=1,
    )

    assert good_score >= 0.65
    assert good_publishable is True
    assert weak_score < good_score
    assert weak_publishable is False


def test_idol_catalog_rejects_confident_but_evidence_free_claims():
    class Event:
        confidence = 0.99
        evidence = []

    score, publishable = _idol_catalog_quality(
        profile_confidence=0.99,
        profile_evidence_count=0,
        timeline_events=[Event(), Event(), Event()],
        persona_generated=True,
        persona_evidence_count=0,
    )

    assert score < 0.7
    assert publishable is False


def test_celery_beat_and_routes_include_catalog_workers():
    schedule = celery_app.conf.beat_schedule["catalog-tick"]

    assert schedule["task"] == "app.tasks.catalog.catalog_tick"
    assert schedule["options"]["queue"] == "catalog_control"
    assert (
        celery_app.conf.task_routes["app.tasks.catalog.process_catalog_job"]["queue"]
        == "catalog"
    )


def test_catalog_task_entrypoints_reuse_the_worker_event_loop(monkeypatch):
    coroutine_names = []

    def fake_run_async(coroutine):
        coroutine_names.append(coroutine.cr_code.co_name)
        coroutine.close()
        return {"runner": "persistent"}

    monkeypatch.setattr(catalog, "run_async", fake_run_async)
    monkeypatch.setattr(catalog.settings, "catalog_scheduler_enabled", True)

    assert catalog.enqueue_catalog_book.run("A Book", None) == {
        "runner": "persistent"
    }
    assert catalog.catalog_tick.run() == {"runner": "persistent"}
    assert catalog.process_catalog_job.run("job-1") == {"runner": "persistent"}
    assert coroutine_names == [
        "_enqueue_catalog_book_async",
        "_catalog_tick_async",
        "_process_catalog_job_async",
    ]


@pytest.mark.asyncio
async def test_catalog_failure_schedules_its_due_retry(monkeypatch):
    job = SimpleNamespace(
        attempts=1,
        state=IngestState.RUNNING,
        last_error=None,
        locked_at=object(),
        next_attempt_at=None,
    )

    class Database:
        async def get(self, _model, _job_id):
            return job

        async def commit(self):
            return None

    @asynccontextmanager
    async def session_maker():
        yield Database()

    scheduled = {}

    def schedule_retry(**kwargs):
        scheduled.update(kwargs)

    monkeypatch.setattr(catalog, "async_session_maker", session_maker)
    monkeypatch.setattr(catalog.catalog_tick, "apply_async", schedule_retry)
    monkeypatch.setattr(catalog.settings, "catalog_max_attempts", 3)

    result = await catalog._record_failure("job-1", "temporary provider error")

    assert result["status"] == "queued"
    assert job.state == IngestState.QUEUED
    assert job.locked_at is None
    assert job.next_attempt_at is not None
    assert scheduled == {"queue": "catalog_control", "countdown": 300}
