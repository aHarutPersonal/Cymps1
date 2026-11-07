"""Offline integration checks for cancelled shared leases and provider attempts."""
import asyncio
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from sqlalchemy.dialects import postgresql

from app.models.idol import CatalogStatus
from app.services import book_companions as books
from app.services import learning_support as support
from app.services.llm.client import BaseLLMClient, LLMResponse
from app.services.llm.tracing import trace_context


class LeaseDatabase:
    """An isolated row double that applies the actual SQL update's owner predicate."""
    def __init__(self):
        self.row = SimpleNamespace(
            status=CatalogStatus.PENDING, metadata_json={}, summary_json=None,
            title="Healthy", author_or_creator=None,
        )
        self.sessions = 0
        self.commits = 0
        self.updates = []
        self.release_started = asyncio.Event()
        self.release_allowed = None
        self.release_drained = asyncio.Event()

    def session(self):
        owner = self
        class Session:
            async def __aenter__(self):
                owner.sessions += 1
                return self

            async def __aexit__(self, *_):
                return False

            async def execute(self, statement):
                if statement.is_update:
                    compiled = statement.compile(dialect=postgresql.dialect())
                    sql, params = str(compiled), compiled.params
                    assert "canonical_key =" in sql and "metadata_json ->>" in sql
                    assert "status =" in sql
                    owner.updates.append(params)
                    owner.release_started.set()
                    try:
                        if owner.release_allowed is not None:
                            await owner.release_allowed.wait()
                        if (owner.row.status == params["status_1"]
                                and owner.row.metadata_json.get("token") == params["param_1"]):
                            owner.row.status = params["status"]
                            owner.row.metadata_json = params["metadata_json"]
                    finally:
                        owner.release_drained.set()
                return SimpleNamespace(scalar_one=lambda: owner.row)

            async def commit(self):
                owner.commits += 1
        return Session()


@pytest.mark.asyncio
@pytest.mark.parametrize("replaced", [False, True])
async def test_book_failure_releases_only_owned_committed_sibling_lease(monkeypatch, replaced):
    database = LeaseDatabase()
    started = asyncio.Event()
    original_token = None

    async def building(*args):
        nonlocal original_token
        original_token = database.row.metadata_json["token"]
        assert database.commits == 1
        started.set()
        await asyncio.Event().wait()

    async def companion(title, author):
        if title == "Failing":
            await started.wait()
            if replaced:
                database.row.metadata_json = {"token": "another-worker", "retry_after":
                    (datetime.now(timezone.utc) + timedelta(minutes=12)).isoformat()}
            raise RuntimeError("book unavailable")
        return await books.get_companion(title, author)

    monkeypatch.setattr(books, "async_session_maker", database.session)
    monkeypatch.setattr(books, "build_companion", building)
    monkeypatch.setattr(support, "get_companion", companion)
    async with asyncio.timeout(1):
        with pytest.raises(RuntimeError, match="book unavailable"):
            await support.build_support({"lesson": "", "books": [
                {"title": "Healthy"}, {"title": "Failing"}]})
    assert database.sessions == 2
    assert database.updates[0]["param_1"] == original_token
    assert database.updates[0]["canonical_key_1"] == books.companion_key("Healthy", None)
    if replaced:
        assert database.row.status == CatalogStatus.PENDING
        assert database.row.metadata_json["token"] == "another-worker"
    else:
        assert database.row.status == CatalogStatus.FLAGGED
        assert database.row.metadata_json == {}


@pytest.mark.asyncio
async def test_repeated_cancellation_drains_owned_lease_cleanup(monkeypatch):
    database = LeaseDatabase()
    database.release_allowed = asyncio.Event()
    started = asyncio.Event()

    async def building(*args):
        started.set()
        await asyncio.Event().wait()

    monkeypatch.setattr(books, "async_session_maker", database.session)
    monkeypatch.setattr(books, "build_companion", building)
    task = asyncio.create_task(books.get_companion("Healthy", None))
    async with asyncio.timeout(1):
        await started.wait()
        task.cancel()
        await database.release_started.wait()
        task.cancel()
        database.release_allowed.set()
        with pytest.raises(asyncio.CancelledError):
            await task
    assert database.row.metadata_json == {}
    assert database.release_drained.is_set()


@pytest.mark.asyncio
async def test_unavailable_lease_cleanup_is_bounded_and_cancellation_propagates(monkeypatch):
    database = LeaseDatabase()
    database.release_allowed = asyncio.Event()
    started = asyncio.Event()

    async def building(*args):
        started.set()
        await asyncio.Event().wait()

    monkeypatch.setattr(books, "_FINALIZATION_SECONDS", 0.01)
    monkeypatch.setattr(books, "async_session_maker", database.session)
    monkeypatch.setattr(books, "build_companion", building)
    task = asyncio.create_task(books.get_companion("Healthy", None))
    async with asyncio.timeout(1):
        await started.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    assert database.release_drained.is_set()
    assert database.row.metadata_json.get("token")  # Existing TTL remains the crash fallback.


class AttemptClient(BaseLLMClient):
    model = "test-model"
    provider_name = "test-provider"

    def __init__(self, *, partial=False, repair=False, same_id=False, queued=False, expected_trace=None):
        self.partial, self.repair, self.same_id, self.queued = partial, repair, same_id, queued
        self.expected_trace = expected_trace
        self.calls = 0
        self.last_attempt = None
        self.started = asyncio.Event()

    async def generate_json(self, **kwargs):
        self.calls += 1
        assert trace_context.get() is self.expected_trace
        if self.repair and self.calls == 1:
            self.last_attempt = LLMResponse(data={}, model=self.model, prompt_tokens=11,
                                           completion_tokens=7, attempt_id="first-attempt")
            return self.last_attempt
        self.started.set()
        self.request_started = not self.queued
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            if self.partial or self.same_id:
                self.last_attempt = LLMResponse(
                    data={}, model=self.model, prompt_tokens=37,
                    attempt_id="first-attempt" if self.same_id else "cancelled-attempt")
            raise


@pytest.mark.asyncio
@pytest.mark.parametrize("partial,repair,same_id,queued", [
    (True, False, False, False), (False, False, False, False),
    (True, True, False, False), (False, True, False, False),
    (False, True, True, False), (False, False, False, True),
])
async def test_speculative_video_cancellation_records_fresh_usage_only(
    monkeypatch, partial, repair, same_id, queued,
):
    client = AttemptClient(partial=partial, repair=repair, same_id=same_id, queued=queued)
    record = AsyncMock(return_value=True)
    monkeypatch.setattr(books, "get_llm_client", lambda **kw: client)
    monkeypatch.setattr(books, "record_llm_response", record)
    monkeypatch.setattr(support.settings, "tavily_api_key", "offline-enabled")

    async def failing_book(book):
        await client.started.wait()
        raise RuntimeError("book unavailable")

    monkeypatch.setattr(support, "resolved_companion", failing_book)
    value = {"lesson": "Tutorial", "lesson_title": "Title", "books": [{"title": "Failing"}]}
    async with asyncio.timeout(1):
        with pytest.raises(RuntimeError, match="book unavailable"):
            await support.build_support(value)
    assert client.calls == 1 + repair
    assert record.await_count == int(repair) + (not queued)
    recorded = [call.kwargs["response"] for call in record.await_args_list]
    if repair:
        assert recorded[0].prompt_tokens == 11
        assert recorded[0].completion_tokens == 7
        assert recorded[0].attempt_id == "first-attempt"
    if not queued:
        assert recorded[-1].prompt_tokens == (37 if partial else None)
        assert record.await_args.kwargs["result_status"] == "cancelled"
        assert recorded[-1].attempt_id != "first-attempt"
        assert recorded[-1].error
    assert trace_context.get() is None


@pytest.mark.asyncio
async def test_schema_repair_usage_records_each_attempt_without_aggregation(monkeypatch):
    class Client(BaseLLMClient):
        calls = 0
        async def generate_json(self, **kwargs):
            self.calls += 1
            return LLMResponse(data={} if self.calls == 1 else {"query": "specific teaching query"},
                               model="test-model", prompt_tokens=11 if self.calls == 1 else 13,
                               completion_tokens=7 if self.calls == 1 else 9,
                               attempt_id=str(self.calls))
    client = Client()
    record = AsyncMock(return_value=True)
    monkeypatch.setattr(books, "get_llm_client", lambda **kw: client)
    monkeypatch.setattr(books, "record_llm_response", record)
    result = await books.structured_call("lesson_video_search_intent", support.VideoSearchIntent, "Teach", {})
    assert result.query == "specific teaching query"
    responses = [call.kwargs["response"] for call in record.await_args_list]
    assert [response.prompt_tokens for response in responses] == [11, 13]
    assert [response.completion_tokens for response in responses] == [7, 9]
    assert [response.attempt_id for response in responses] == ["1", "2"]
    assert trace_context.get() is None


@pytest.mark.asyncio
async def test_repeated_cancellation_waits_for_bounded_usage_finalization(monkeypatch):
    client = AttemptClient(partial=True)
    record_started, record_allowed, record_drained = asyncio.Event(), asyncio.Event(), asyncio.Event()

    async def record(**kwargs):
        assert kwargs["response"].prompt_tokens == 37
        record_started.set()
        try:
            await record_allowed.wait()
        finally:
            record_drained.set()

    monkeypatch.setattr(books, "get_llm_client", lambda **kw: client)
    monkeypatch.setattr(books, "record_llm_response", record)
    task = asyncio.create_task(books.structured_call("lesson_video_search_intent", support.VideoSearchIntent, "Teach", {}))
    async with asyncio.timeout(1):
        await client.started.wait()
        task.cancel()
        await record_started.wait()
        task.cancel()
        record_allowed.set()
        with pytest.raises(asyncio.CancelledError):
            await task
    assert record_drained.is_set()


@pytest.mark.asyncio
async def test_unavailable_usage_finalization_is_bounded(monkeypatch):
    client = AttemptClient(partial=True)
    record_drained = asyncio.Event()

    async def record(**kwargs):
        try:
            await asyncio.Event().wait()
        finally:
            record_drained.set()

    monkeypatch.setattr(books, "_FINALIZATION_SECONDS", 0.01)
    monkeypatch.setattr(books, "get_llm_client", lambda **kw: client)
    monkeypatch.setattr(books, "record_llm_response", record)
    task = asyncio.create_task(books.structured_call("lesson_video_search_intent", support.VideoSearchIntent, "Teach", {}))
    async with asyncio.timeout(1):
        await client.started.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    assert record_drained.is_set()


@pytest.mark.asyncio
async def test_inherited_provider_trace_is_preserved_without_new_trace_writes(monkeypatch):
    inherited = {"trace_id": "parent-trace", "operation": "parent-operation"}
    client = AttemptClient(partial=True, expected_trace=inherited)
    record = AsyncMock(return_value=True)
    monkeypatch.setattr(books, "get_llm_client", lambda **kw: client)
    monkeypatch.setattr(books, "record_llm_response", record)
    token = trace_context.set(inherited)
    try:
        task = asyncio.create_task(books.structured_call(
            "lesson_video_search_intent", support.VideoSearchIntent, "Teach", {}))
        async with asyncio.timeout(1):
            await client.started.wait()
            task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task
        assert trace_context.get() is inherited
        assert record.await_args.kwargs["response"].trace_id == "parent-trace"
        assert record.await_count == 1
    finally:
        trace_context.reset(token)


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [TimeoutError, RuntimeError])
async def test_cancellation_wins_when_cleanup_failure_finishes_at_same_time(monkeypatch, failure):
    async def failed_cleanup():
        raise failure("cleanup unavailable")

    async def cancel_as_cleanup_finishes(task):
        await asyncio.wait({task})
        raise asyncio.CancelledError

    monkeypatch.setattr(books.asyncio, "shield", cancel_as_cleanup_finishes)
    with pytest.raises(asyncio.CancelledError):
        await books._finish_support(failed_cleanup)
