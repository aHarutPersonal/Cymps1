import json

import httpx
import pytest
from redis.exceptions import ConnectionError as RedisConnectionError

from app.core.config import Settings, settings
from app.services import google_books as books


class Cache:
    def __init__(self):
        self.values = {}
        self.ttls = {}

    async def get(self, key):
        return self.values.get(key)

    async def set(self, key, value, ex):
        self.values[key] = value
        self.ttls[key] = ex

    async def aclose(self):
        pass


@pytest.fixture
def cache(monkeypatch):
    cache = Cache()
    monkeypatch.setattr(books, "_cache_client", lambda: cache)
    monkeypatch.setattr(settings, "google_books_api_key", "test-private-key")
    return cache


@pytest.mark.asyncio
async def test_key_header_and_cached_results(cache):
    requests = []

    def handle(request):
        requests.append(request)
        assert request.headers["x-goog-api-key"] == "test-private-key"
        assert "test-private-key" not in str(request.url)
        return httpx.Response(200, json={"items": [{"id": "book"}]})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        first = await books.search_volumes({"q": "finance"}, client=client)
        second = await books.search_volumes({"q": "finance"}, client=client)
    assert first == second == {"items": [{"id": "book"}]}
    assert len(requests) == 1
    assert list(cache.ttls.values()) == [86400]
    assert all("test-private-key" not in k for k in cache.values)


@pytest.mark.asyncio
@pytest.mark.parametrize("status,payload,expected", [
    (429, {}, 900),
    (403, {}, 3600),
    (429, {"error": {"details": [{"metadata": {"quota_limit": "defaultPerDayPerProject"}}]}}, 86400),
])
async def test_quota_cooldown_shared_across_different_queries(cache, status, payload, expected):
    calls = []
    def handle(request):
        calls.append(request)
        return httpx.Response(status, json=payload)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        assert await books.search_volumes({"q": "finance"}, client=client) is None
        assert await books.search_volumes({"q": "philosophy"}, client=client) is None
    assert len(calls) == 1
    assert list(cache.ttls.values()) == [expected]


@pytest.mark.asyncio
async def test_retry_after_and_credential_change(cache, monkeypatch):
    calls = []
    def handle(request):
        calls.append(request)
        if len(calls) == 1:
            return httpx.Response(429, json={}, headers={"Retry-After": "7200"})
        return httpx.Response(200, json={"items": []})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        assert await books.search_volumes({"q": "a"}, client=client) is None
        assert 7200 in cache.ttls.values()
        monkeypatch.setattr(settings, "google_books_api_key", "fixed-test-key")
        assert await books.search_volumes({"q": "a"}, client=client) == {"items": []}
    assert len(calls) == 2


@pytest.mark.asyncio
async def test_cached_book_still_available_during_cooldown(cache):
    def handle(request):
        if request.url.params["q"] == "cached":
            return httpx.Response(200, json={"items": [{"id": "a"}]})
        return httpx.Response(429, json={})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        first = await books.search_volumes({"q": "cached"}, client=client)
        await books.search_volumes({"q": "other"}, client=client)
        assert await books.search_volumes({"q": "cached"}, client=client) == first


@pytest.mark.asyncio
async def test_invalid_response_and_secret_safe_logs(cache, caplog):
    def handle(request):
        raise httpx.ConnectError("test-private-key must never be logged", request=request)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        assert await books.search_volumes({"q": "a"}, client=client) is None
    assert "test-private-key" not in caplog.text
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json=[]))) as client:
        assert await books.search_volumes({"q": "a"}, client=client) is None
    assert not cache.values


@pytest.mark.asyncio
async def test_redis_failure_does_not_break_direct_lookup(cache, monkeypatch):
    async def fail(*args, **kwargs):
        raise RedisConnectionError()
    monkeypatch.setattr(cache, "get", fail)
    monkeypatch.setattr(cache, "set", fail)
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"items": []}))) as client:
        assert await books.search_volumes({"q": "a"}, client=client) == {"items": []}


def test_secret_loading_and_no_serialization(monkeypatch):
    from app.core import credentials
    calls = []
    def read(*args):
        calls.append(args)
        return "private-test-value"
    monkeypatch.setattr(credentials, "read_aws_secret", read)
    configured = Settings(_env_file=None, llm_provider="dummy", google_books_secret_id="test-secret")
    assert calls == [("test-secret", "us-east-1", "GOOGLE_BOOKS_API_KEY")]
    assert configured.google_books_api_key == "private-test-value"
    assert "private-test-value" not in repr(configured)
    assert "private-test-value" not in json.dumps(configured.model_dump())
