from contextlib import asynccontextmanager
from datetime import datetime, timezone
from types import SimpleNamespace

import httpx
import pytest

from app.core.config import settings
from app.models.idol import CatalogStatus
from app.models.ingest_job import IngestKind, IngestState
from app.services.catalog_discovery import (
    BookDiscoveryCandidate,
    discovery_kind_for_bucket,
    discover_google_books_candidates,
    discover_wikidata_candidates,
    utc_time_bucket,
)
from app.tasks import catalog


class _Response:
    def __init__(self, payload):
        self.payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self.payload


class _Client:
    def __init__(self, payload):
        self.payload = payload
        self.calls = []

    async def get(self, url, *, params):
        self.calls.append((url, params))
        return _Response(self.payload)


class _FailingClient:
    async def get(self, url, *, params):
        request = httpx.Request("GET", url, params=params)
        raise httpx.ConnectError("temporary provider failure", request=request)


def _google_book(book_id: str, title: str, author: str) -> dict:
    return {
        "id": book_id,
        "volumeInfo": {
            "title": title,
            "authors": [author],
            "description": "A grounded publisher catalog description. " * 8,
            "language": "en",
            "pageCount": 240,
            "canonicalVolumeLink": f"https://books.google.com/books?id={book_id}",
            "imageLinks": {"thumbnail": f"https://books.google.com/{book_id}.jpg"},
        },
    }


def test_discovery_kind_strictly_alternates_and_bucket_is_stable():
    now = datetime(2026, 7, 14, 12, 34, tzinfo=timezone.utc)
    bucket = utc_time_bucket(now, interval_seconds=900)

    assert utc_time_bucket(now, interval_seconds=900) == bucket
    assert discovery_kind_for_bucket(bucket) != discovery_kind_for_bucket(bucket + 1)
    assert {discovery_kind_for_bucket(bucket), discovery_kind_for_bucket(bucket + 1)} == {
        IngestKind.BOOK,
        IngestKind.IDOL,
    }


@pytest.mark.asyncio
async def test_google_books_random_choice_is_bounded_and_reproducible():
    payload = {
        "items": [
            _google_book("book-a", "The Useful Book", "A. Author"),
            _google_book("book-b", "Another Useful Book", "B. Author"),
            _google_book("guide", "Study Guide for a Famous Book", "C. Author"),
            {
                **_google_book("thin", "Thin", "D. Author"),
                "volumeInfo": {
                    **_google_book("thin", "Thin", "D. Author")["volumeInfo"],
                    "pageCount": 20,
                },
            },
        ]
    }
    first_client = _Client(payload)
    second_client = _Client(payload)

    first = await discover_google_books_candidates(
        bucket=1234,
        client=first_client,
    )
    second = await discover_google_books_candidates(
        bucket=1234,
        client=second_client,
    )

    assert [candidate.google_books_id for candidate in first] == [
        candidate.google_books_id for candidate in second
    ]
    assert {candidate.google_books_id for candidate in first} == {"book-a", "book-b"}
    assert first_client.calls == second_client.calls
    params = first_client.calls[0][1]
    assert params["maxResults"] == 40
    assert params["startIndex"] in {0, 40, 80, 120}
    assert params["q"].startswith("subject:")


@pytest.mark.asyncio
async def test_google_books_failure_uses_deterministic_curated_fallback():
    first = await discover_google_books_candidates(
        bucket=8675309,
        limit=4,
        client=_FailingClient(),
    )
    second = await discover_google_books_candidates(
        bucket=8675309,
        limit=4,
        client=_FailingClient(),
    )

    assert len(first) == 4
    assert [(item.title, item.author) for item in first] == [
        (item.title, item.author) for item in second
    ]
    assert all(item.provider == "curated_fallback" for item in first)
    assert all(item.google_books_id.startswith("curated:") for item in first)


@pytest.mark.asyncio
async def test_wikidata_discovery_requires_wikipedia_and_commons_image():
    candidates = [
        SimpleNamespace(externalId="Q1"),
        SimpleNamespace(externalId="Q2"),
        SimpleNamespace(externalId="Q3"),
    ]

    async def search(occupation_qids, *, limit):
        assert len(occupation_qids) == 1
        assert limit == 20
        return candidates

    async def fetch(qid):
        if qid == "Q1":
            return {
                "name": "No Photo",
                "wikipedia_url": "https://en.wikipedia.org/wiki/No_Photo",
                "image_url": None,
            }
        if qid == "Q2":
            return {
                "name": "Wrong Image Host",
                "wikipedia_url": "https://en.wikipedia.org/wiki/Wrong_Image_Host",
                "image_url": "https://example.com/photo.jpg",
            }
        return {
            "name": "Ada Example",
            "birth_date": None,
            "wikipedia_url": "https://en.wikipedia.org/wiki/Ada_Example",
            "image_url": "https://commons.wikimedia.org/wiki/Special:FilePath/Ada.jpg",
        }

    result = await discover_wikidata_candidates(
        bucket=4321,
        occupation_search=search,
        entity_fetch=fetch,
    )

    assert len(result) == 1
    assert result[0].wikidata_qid == "Q3"
    assert result[0].image_source_url.endswith("File:Ada.jpg")
    assert result[0].image_license == "wikimedia_pending_verification"


@pytest.mark.asyncio
async def test_wikidata_search_failure_uses_verified_curated_qids():
    fetched = []

    async def search(_occupation_qids, *, limit):
        assert limit == 20
        return []

    async def fetch(qid):
        fetched.append(qid)
        return {
            "name": f"Verified Person {qid}",
            "birth_date": None,
            "wikipedia_url": f"https://en.wikipedia.org/wiki/{qid}",
            "image_url": f"https://commons.wikimedia.org/wiki/Special:FilePath/{qid}.jpg",
        }

    result = await discover_wikidata_candidates(
        bucket=20260715,
        limit=2,
        occupation_search=search,
        entity_fetch=fetch,
    )

    assert len(result) == 2
    assert [item.wikidata_qid for item in result] == fetched[:2]
    assert all(item.image_license == "wikimedia_pending_verification" for item in result)


@pytest.mark.asyncio
async def test_idle_tick_seeds_exactly_one_book_after_double_admission_check(
    monkeypatch,
):
    now = datetime.fromtimestamp(2 * 900, tz=timezone.utc)  # even bucket => book
    sessions = []

    class Database:
        async def commit(self):
            return None

    @asynccontextmanager
    async def session_maker():
        db = Database()
        sessions.append(db)
        yield db

    queue_checks = 0

    async def queue_depths():
        nonlocal queue_checks
        queue_checks += 1
        return {"high_priority": 0, "default": 0, "low_priority": 0}

    async def no_blocker(*_args, **_kwargs):
        return None

    budget = SimpleNamespace(state="normal", spent_usd=0.01, committed_usd=0.01)

    async def budget_allowed(*_args, **_kwargs):
        return None, budget

    candidate = BookDiscoveryCandidate(
        google_books_id="book-1",
        title="Useful Book",
        author="A. Author",
        source_url="https://books.google.com/book-1",
        thumbnail_url=None,
        description="description",
        topic="business",
    )

    async def discover(*, bucket):
        assert bucket == 2
        return [candidate, candidate]

    seed_calls = 0

    async def seed(_db, *, candidates, bucket):
        nonlocal seed_calls
        seed_calls += 1
        assert len(candidates) == 2
        assert bucket == 2
        return {"status": "seeded", "kind": "book", "job_id": "job-1"}

    from app.services import catalog_discovery as discovery

    monkeypatch.setattr(catalog, "async_session_maker", session_maker)
    monkeypatch.setattr(catalog, "_interactive_queue_depths", queue_depths)
    monkeypatch.setattr(catalog, "_idle_discovery_db_blocker", no_blocker)
    monkeypatch.setattr(catalog, "_idle_discovery_budget_blocker", budget_allowed)
    monkeypatch.setattr(catalog, "_seed_discovered_book", seed)
    monkeypatch.setattr(discovery, "discover_google_books_candidates", discover)
    monkeypatch.setattr(settings, "catalog_idle_discovery_interval_seconds", 900)

    result = await catalog._catalog_discovery_tick_async(now=now)

    assert result["status"] == "seeded"
    assert result["job_id"] == "job-1"
    assert seed_calls == 1
    assert queue_checks == 2
    assert len(sessions) == 2


@pytest.mark.asyncio
async def test_idle_tick_stops_before_db_or_provider_when_queue_is_busy(monkeypatch):
    async def queue_depths():
        return {"high_priority": 1, "default": 0, "low_priority": 0}

    monkeypatch.setattr(catalog, "_interactive_queue_depths", queue_depths)

    result = await catalog._catalog_discovery_tick_async(
        now=datetime(2026, 7, 14, tzinfo=timezone.utc)
    )

    assert result == {
        "status": "skipped",
        "reason": "interactive_queue_busy",
        "queue_depths": {"high_priority": 1, "default": 0, "low_priority": 0},
    }


@pytest.mark.asyncio
async def test_book_seeding_skips_existing_key_and_inserts_only_one(monkeypatch):
    first = BookDiscoveryCandidate(
        google_books_id="existing",
        title="Existing Book",
        author="A. Author",
        source_url="https://books.google.com/existing",
        thumbnail_url=None,
        description="description",
        topic="business",
    )
    second = BookDiscoveryCandidate(
        google_books_id="new",
        title="New Book",
        author="B. Author",
        source_url="https://books.google.com/new",
        thumbnail_url=None,
        description="description",
        topic="business",
    )

    class Database:
        scalar_calls = 0
        commits = 0

        async def scalar(self, _stmt):
            self.scalar_calls += 1
            return "resource-1" if self.scalar_calls == 1 else None

        async def commit(self):
            self.commits += 1

        async def rollback(self):
            return None

    inserts = []

    async def insert(_db, **kwargs):
        inserts.append(kwargs)
        return "job-1"

    monkeypatch.setattr(catalog, "_insert_job", insert)
    db = Database()

    result = await catalog._seed_discovered_book(
        db,
        candidates=[first, second, second],
        bucket=7,
    )

    assert result["status"] == "seeded"
    assert len(inserts) == 1
    assert inserts[0]["external_id"] == "book:b_author:new_book"
    assert inserts[0]["payload"]["origin"] == catalog.IDLE_DISCOVERY_ORIGIN
    assert inserts[0]["payload"]["discovery_provider"] == "google_books"
    assert "GOOGLE BOOKS CATALOG DESCRIPTION" in inserts[0]["payload"]["source_context"]
    assert inserts[0]["priority"] == settings.catalog_idle_discovery_priority
    assert db.commits == 1


@pytest.mark.asyncio
async def test_idle_discovered_idol_is_flagged_without_verified_photo(monkeypatch):
    idol = SimpleNamespace(
        id="idol-1",
        status=CatalogStatus.PUBLISHED,
        published_at=object(),
    )
    job = SimpleNamespace(
        state=IngestState.RUNNING,
        last_error=None,
        completed_at=None,
        locked_at=object(),
    )

    async def no_photo(_db, _idol):
        return False

    monkeypatch.setattr(catalog, "_resolve_catalog_idol_photo", no_photo)

    verified = await catalog._finalize_idol_catalog_job(
        object(),
        idol=idol,
        job=job,
        payload={"origin": catalog.IDLE_DISCOVERY_ORIGIN},
    )

    assert verified is False
    assert idol.status == CatalogStatus.FLAGGED
    assert idol.published_at is None
    assert job.state == IngestState.FLAGGED
    assert "verified Commons photo" in job.last_error


def test_discovery_entrypoint_requires_both_scheduler_flags(monkeypatch):
    monkeypatch.setattr(settings, "catalog_scheduler_enabled", False)
    monkeypatch.setattr(settings, "catalog_idle_discovery_enabled", True)
    assert catalog.catalog_discovery_tick.run() == {"status": "disabled"}


@pytest.mark.asyncio
async def test_db_admission_stops_when_any_catalog_job_is_active():
    class Database:
        calls = 0

        async def scalar(self, _stmt):
            self.calls += 1
            return "active-job"

    db = Database()
    blocker = await catalog._idle_discovery_db_blocker(
        db,
        now=datetime(2026, 7, 14, tzinfo=timezone.utc),
        bucket=10,
    )

    assert blocker == "catalog_busy"
    assert db.calls == 1


@pytest.mark.asyncio
async def test_db_admission_stops_for_recent_user_generation():
    class Database:
        scalar_values = iter([None, "plan-job"])

        async def scalar(self, _stmt):
            return next(self.scalar_values)

    blocker = await catalog._idle_discovery_db_blocker(
        Database(),
        now=datetime(2026, 7, 14, tzinfo=timezone.utc),
        bucket=10,
    )

    assert blocker == "recent_user_generation"


def test_default_idle_queue_gate_covers_all_user_worker_queues(monkeypatch):
    monkeypatch.setattr(
        settings,
        "catalog_idle_discovery_interactive_queues",
        "high_priority,default,low_priority",
    )
    assert catalog._interactive_queue_names() == (
        "high_priority",
        "default",
        "low_priority",
    )
