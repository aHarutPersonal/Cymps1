from contextlib import asynccontextmanager
from types import SimpleNamespace

import pytest

from app.core.celery import celery_app
from app.models.idol import CatalogStatus
from app.tasks import catalog
from app.tasks.catalog import catalog_retry_delay_seconds, retry_delay_seconds
from app.tasks.ingestion import _idol_catalog_quality
from app.models.ingest_job import IngestKind, IngestState


def test_catalog_retry_backoff_is_bounded():
    assert retry_delay_seconds(1) == 300
    assert retry_delay_seconds(2) == 600
    assert retry_delay_seconds(3) == 1200
    assert retry_delay_seconds(99) == 21600


def test_user_requested_book_retries_quickly_and_bypasses_background_budget():
    user_book = SimpleNamespace(
        kind=IngestKind.BOOK,
        priority=catalog.USER_DEMANDED_BOOK_PRIORITY,
        attempts=1,
        payload_json={"origin": "plan_material"},
    )
    autonomous_book = SimpleNamespace(
        kind=IngestKind.BOOK,
        priority=10,
        attempts=1,
        payload_json={"origin": catalog.IDLE_DISCOVERY_ORIGIN},
    )

    assert catalog_retry_delay_seconds(user_book) == 15
    assert catalog.bypasses_background_budget(user_book) is True
    assert catalog_retry_delay_seconds(autonomous_book) == 300
    assert catalog.bypasses_background_budget(autonomous_book) is False


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
    discovery_schedule = celery_app.conf.beat_schedule["idle-catalog-discovery"]

    assert schedule["task"] == "app.tasks.catalog.catalog_tick"
    assert schedule["options"]["queue"] == "catalog_control"
    assert (
        celery_app.conf.task_routes["app.tasks.catalog.process_catalog_job"]["queue"]
        == "catalog"
    )
    assert discovery_schedule["task"] == "app.tasks.catalog.catalog_discovery_tick"
    assert discovery_schedule["options"]["queue"] == "catalog_control"
    assert discovery_schedule["schedule"] >= 60
    assert (
        celery_app.conf.task_routes["app.tasks.catalog.catalog_discovery_tick"]["queue"]
        == "catalog_control"
    )
    assert catalog.process_catalog_job.acks_late is True
    assert catalog.process_catalog_job.reject_on_worker_lost is True


def test_catalog_task_entrypoints_reuse_the_worker_event_loop(monkeypatch):
    coroutine_names = []

    def fake_run_async(coroutine):
        coroutine_names.append(coroutine.cr_code.co_name)
        coroutine.close()
        return {"runner": "persistent"}

    monkeypatch.setattr(catalog, "run_async", fake_run_async)
    monkeypatch.setattr(catalog.settings, "catalog_scheduler_enabled", True)
    monkeypatch.setattr(catalog.settings, "catalog_idle_discovery_enabled", True)

    assert catalog.enqueue_catalog_book.run("A Book", None) == {"runner": "persistent"}
    assert catalog.catalog_tick.run() == {"runner": "persistent"}
    assert catalog.catalog_discovery_tick.run() == {"runner": "persistent"}
    assert catalog.process_catalog_job.run("job-1") == {"runner": "persistent"}
    assert coroutine_names == [
        "_enqueue_catalog_book_async",
        "_catalog_tick_async",
        "_catalog_discovery_tick_async",
        "_process_catalog_job_async",
    ]


@pytest.mark.asyncio
async def test_repeated_worker_redelivery_returns_to_durable_retry(monkeypatch):
    job = SimpleNamespace(
        state=IngestState.RUNNING,
        kind=IngestKind.BOOK,
        payload_json={catalog.WORKER_REDELIVERY_COUNT_KEY: 1},
    )

    class Database:
        async def get(self, _model, _job_id):
            return job

    @asynccontextmanager
    async def session_maker():
        yield Database()

    recorded = {}

    async def record_failure(job_id, error):
        recorded.update(job_id=job_id, error=error)
        return {"status": "queued", "job_id": job_id}

    monkeypatch.setattr(catalog, "async_session_maker", session_maker)
    monkeypatch.setattr(catalog, "_record_failure", record_failure)

    result = await catalog._process_catalog_job_async(
        "job-1",
        redelivered=True,
    )

    assert result == {"status": "queued", "job_id": "job-1"}
    assert recorded["job_id"] == "job-1"
    assert "lost twice" in recorded["error"]


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


@pytest.mark.asyncio
async def test_failed_book_quality_is_requeued_before_becoming_terminal(monkeypatch):
    from app.services import content_resources

    job = SimpleNamespace(
        attempts=1,
        kind=IngestKind.BOOK,
        priority=catalog.USER_DEMANDED_BOOK_PRIORITY,
        state=IngestState.RUNNING,
        last_error=None,
        locked_at=object(),
        next_attempt_at=None,
        completed_at=None,
    )
    resource = SimpleNamespace(
        id="resource-1",
        canonical_key="book:author:title",
        status=CatalogStatus.FLAGGED,
        metadata_json={"quality_report": {"score": 0.52, "issues": ["too short"]}},
    )

    class Database:
        async def get(self, _model, _job_id):
            return job

        async def commit(self):
            return None

    @asynccontextmanager
    async def session_maker():
        yield Database()

    async def generate_resource(*_args, **_kwargs):
        return resource

    scheduled = {}
    monkeypatch.setattr(catalog, "async_session_maker", session_maker)
    monkeypatch.setattr(
        content_resources,
        "get_or_create_book_module_resource",
        generate_resource,
    )
    monkeypatch.setattr(
        catalog.catalog_tick,
        "apply_async",
        lambda **kwargs: scheduled.update(kwargs),
    )
    monkeypatch.setattr(catalog.settings, "catalog_max_attempts", 3)

    result = await catalog._process_book_job(
        "job-1", {"title": "Title", "author": "Author"}
    )

    assert result["status"] == "queued"
    assert job.state == IngestState.QUEUED
    assert job.completed_at is None
    assert job.next_attempt_at is not None
    assert "quality_gate_failed" in job.last_error
    assert scheduled == {"queue": "catalog_control", "countdown": 15}
