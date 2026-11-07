"""Independent optional work cannot delay primary sources or leak running tasks."""
import asyncio
from unittest.mock import AsyncMock

import pytest

from app.services import content_resources as resources
from app.services import learning_support as support


FULL_TEXT = {"source_context": "Verified original source words. " * 100, "source_url": "https://example.test/book"}


def source_mocks(monkeypatch, *, public=None, official=None, reference=None):
    calls = {}
    for name, result in (("lookup_public_domain_book", public),
                         ("lookup_gutenberg_book", official),
                         ("lookup_book_reference_context", reference)):
        calls[name] = AsyncMock(return_value=result)
        monkeypatch.setattr(resources, name, calls[name])
    return calls


@pytest.mark.asyncio
async def test_sufficient_full_text_does_not_wait_for_metadata_and_drains_it(monkeypatch):
    calls = source_mocks(monkeypatch, public=FULL_TEXT)
    started, cancelled = asyncio.Event(), asyncio.Event()
    async def reference(**kwargs):
        started.set()
        try:
            await asyncio.Event().wait()
        finally:
            cancelled.set()
    monkeypatch.setattr(resources, "lookup_book_reference_context", reference)
    async with asyncio.timeout(1):
        assert await resources.lookup_book_source(title="Book", author="Author") == FULL_TEXT
    assert started.is_set() and cancelled.is_set()
    calls["lookup_gutenberg_book"].assert_not_awaited()


@pytest.mark.asyncio
async def test_official_fallback_starts_without_waiting_for_metadata(monkeypatch):
    source_mocks(monkeypatch)
    reference_started, reference_cancelled = asyncio.Event(), asyncio.Event()
    async def reference(**kwargs):
        reference_started.set()
        try:
            await asyncio.Event().wait()
        finally:
            reference_cancelled.set()
    async def official(**kwargs):
        await reference_started.wait()
        return FULL_TEXT
    monkeypatch.setattr(resources, "lookup_book_reference_context", reference)
    monkeypatch.setattr(resources, "lookup_gutenberg_book", official)
    async with asyncio.timeout(1):
        assert await resources.lookup_book_source(title="Book", author="Author") == FULL_TEXT
    assert reference_cancelled.is_set()


@pytest.mark.asyncio
@pytest.mark.parametrize("public,official,reference,expected", [
    (FULL_TEXT, None, {"catalog": True}, FULL_TEXT),
    ({"source_context": "short"}, FULL_TEXT, {"catalog": True}, FULL_TEXT),
    ({"source_context": "short"}, None, {"catalog": True}, {"source_context": "short"}),
    (None, None, {"catalog": True}, {"catalog": True}),
    (None, None, None, None),
])
async def test_source_priority_is_unchanged(monkeypatch, public, official, reference, expected):
    calls = source_mocks(monkeypatch, public=public, official=official, reference=reference)
    assert await resources.lookup_book_source(title="Book", author=None) == expected
    calls["lookup_public_domain_book"].assert_awaited_once()
    calls["lookup_book_reference_context"].assert_awaited_once()
    assert calls["lookup_gutenberg_book"].await_count == (0 if public is FULL_TEXT else 1)


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["public", "official", "reference"])
async def test_required_source_failure_is_propagated_and_siblings_drained(monkeypatch, failure):
    calls = source_mocks(monkeypatch)
    reference_cancelled = asyncio.Event()
    async def pending_reference(**kwargs):
        try:
            await asyncio.Event().wait()
        finally:
            reference_cancelled.set()
    if failure != "reference":
        monkeypatch.setattr(resources, "lookup_book_reference_context", pending_reference)
    calls[{"public": "lookup_public_domain_book", "official": "lookup_gutenberg_book",
           "reference": "lookup_book_reference_context"}[failure]].side_effect = RuntimeError("lookup failed")
    async with asyncio.timeout(1):
        with pytest.raises(RuntimeError, match="lookup failed"):
            await resources.lookup_book_source(title="Book", author=None)
    if failure != "reference":
        assert reference_cancelled.is_set()


@pytest.mark.asyncio
async def test_cancelled_lookup_drains_both_started_sources(monkeypatch):
    started, cancelled = set(), set()
    both = asyncio.Event()
    async def pending(name):
        started.add(name)
        if len(started) == 2:
            both.set()
        try:
            await asyncio.Event().wait()
        finally:
            cancelled.add(name)
    monkeypatch.setattr(resources, "lookup_public_domain_book", lambda **kw: pending("public"))
    monkeypatch.setattr(resources, "lookup_book_reference_context", lambda **kw: pending("reference"))
    task = asyncio.create_task(resources.lookup_book_source(title="Book", author=None))
    async with asyncio.timeout(1):
        await both.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    assert cancelled == started == {"public", "reference"}


@pytest.mark.asyncio
async def test_video_starts_during_book_preparation_but_idea_waits(monkeypatch):
    video_started = asyncio.Event()
    finished = []
    ready = {"status": "ready", "title": "Book"}
    async def companion(book):
        await video_started.wait()
        finished.append("book")
        return ready
    async def video(value):
        video_started.set()
        return [{"id": "verified-video"}]
    async def idea(value, books):
        assert finished == ["book"] and books == [ready]
        return {"id": "verified-idea"}
    monkeypatch.setattr(support, "resolved_companion", companion)
    monkeypatch.setattr(support, "find_support_video", video)
    monkeypatch.setattr(support, "match_book_idea", idea)
    value = {"lesson": "Tutorial", "books": [{"title": "Book"}]}
    async with asyncio.timeout(1):
        result = await support.build_support(value)
    assert result == {"books": value["books"], "idea": {"id": "verified-idea"},
                      "videos": [{"id": "verified-video"}]}


@pytest.mark.asyncio
@pytest.mark.parametrize("failed", ["idea", "video"])
async def test_optional_support_failure_keeps_other_component(monkeypatch, failed):
    monkeypatch.setattr(support, "resolved_companion", AsyncMock(return_value={"status": "checking"}))
    idea = AsyncMock(return_value={"id": "idea"})
    video = AsyncMock(return_value=[{"id": "video"}])
    (idea if failed == "idea" else video).side_effect = RuntimeError("component unavailable")
    monkeypatch.setattr(support, "match_book_idea", idea)
    monkeypatch.setattr(support, "find_support_video", video)
    value = {"lesson": "Tutorial", "books": [{"title": "Book"}]}
    result = await support.build_support(value)
    assert result == {"books": value["books"], "books_pending": True,
                      "idea": None if failed == "idea" else {"id": "idea"},
                      "videos": [] if failed == "video" else [{"id": "video"}]}


@pytest.mark.asyncio
async def test_empty_lesson_starts_no_optional_ai_calls(monkeypatch):
    monkeypatch.setattr(support, "resolved_companion", AsyncMock(return_value={"status": "ready"}))
    idea, video = AsyncMock(), AsyncMock()
    monkeypatch.setattr(support, "match_book_idea", idea)
    monkeypatch.setattr(support, "find_support_video", video)
    assert await support.build_support({"lesson": "", "books": []}) == {"books": [], "idea": None, "videos": []}
    idea.assert_not_awaited(); video.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("cancel", [False, True])
async def test_book_failure_or_caller_cancellation_drains_video_and_companions(monkeypatch, cancel):
    started, drained = set(), set()
    all_started = asyncio.Event()
    async def component(name):
        started.add(name)
        if len(started) == 3:
            all_started.set()
        try:
            await all_started.wait()
            if name == "first" and not cancel:
                raise RuntimeError("book unavailable")
            await asyncio.Event().wait()
        finally:
            drained.add(name)
    monkeypatch.setattr(support, "resolved_companion", lambda book: component(book["title"]))
    monkeypatch.setattr(support, "find_support_video", lambda value: component("video"))
    value = {"lesson": "Tutorial", "books": [{"title": "first"}, {"title": "second"}]}
    task = asyncio.create_task(support.build_support(value))
    async with asyncio.timeout(1):
        await all_started.wait()
        if cancel:
            task.cancel()
        with pytest.raises(asyncio.CancelledError if cancel else RuntimeError):
            await task
    assert drained == started == {"first", "second", "video"}


@pytest.mark.asyncio
async def test_unused_metadata_error_cannot_hide_sufficient_full_text(monkeypatch):
    calls = source_mocks(monkeypatch, public=FULL_TEXT)
    calls["lookup_book_reference_context"].side_effect = RuntimeError("catalog unavailable")
    assert await resources.lookup_book_source(title="Book", author=None) == FULL_TEXT
    calls["lookup_gutenberg_book"].assert_not_awaited()


@pytest.mark.asyncio
async def test_cancellation_during_official_fallback_drains_all_sources(monkeypatch):
    source_mocks(monkeypatch)
    started, drained = set(), set()
    ready = asyncio.Event()
    async def pending(name):
        started.add(name)
        if len(started) == 2:
            ready.set()
        try:
            await asyncio.Event().wait()
        finally:
            drained.add(name)
    monkeypatch.setattr(resources, "lookup_gutenberg_book", lambda **kw: pending("official"))
    monkeypatch.setattr(resources, "lookup_book_reference_context", lambda **kw: pending("reference"))
    task = asyncio.create_task(resources.lookup_book_source(title="Book", author=None))
    async with asyncio.timeout(1):
        await ready.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    assert drained == started == {"official", "reference"}


@pytest.mark.asyncio
async def test_cancellation_after_books_ready_drains_both_support_calls(monkeypatch):
    monkeypatch.setattr(support, "resolved_companion", AsyncMock(return_value={"status": "ready"}))
    started, drained = set(), set()
    ready = asyncio.Event()
    async def pending(name):
        started.add(name)
        if len(started) == 2:
            ready.set()
        try:
            await asyncio.Event().wait()
        finally:
            drained.add(name)
    monkeypatch.setattr(support, "match_book_idea", lambda *args: pending("idea"))
    monkeypatch.setattr(support, "find_support_video", lambda *args: pending("video"))
    task = asyncio.create_task(support.build_support({"lesson": "Tutorial", "books": [{"title": "Book"}]}))
    async with asyncio.timeout(1):
        await ready.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    assert drained == started == {"idea", "video"}
