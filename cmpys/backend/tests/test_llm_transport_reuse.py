"""Provider connection reuse must not share mutable per-request timeouts.

``app/services/llm/transport.py`` keeps one pooled SDK client per provider
credential and event loop; each direct client applies its own timeout through
``with_options``. No request here leaves the process.
"""
import asyncio
import json

import anthropic
import httpx
import httpx2
import openai
import pytest

from app.services.llm import transport
from app.services.llm.anthropic_direct import AnthropicDirectLLMClient
from app.services.llm.openai_direct import OpenAIDirectLLMClient

CLIENTS = {"openai": OpenAIDirectLLMClient, "anthropic": AnthropicDirectLLMClient}


@pytest.fixture(autouse=True)
def isolated_pool():
    transport.reset_pools_for_tests()
    yield
    transport.reset_pools_for_tests()


def sdk(provider, timeout=45, key="synthetic-key"):
    """The pooled SDK view one direct client would send its request through."""
    return CLIENTS[provider](api_key=key, timeout=timeout)._sdk()


def pool_size():
    return sum(len(clients) for clients in transport._pools.values())


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", CLIENTS)
async def test_different_timeouts_reuse_one_transport_with_independent_options(provider):
    first, second, third = sdk(provider, 45), sdk(provider, 120), sdk(provider, 60)
    try:
        assert first._client is second._client is third._client
        assert pool_size() == 1
        assert (first.timeout, second.timeout, third.timeout) == (45, 120, 60)
        # The SDK's own retries would multiply a user-facing wait; callers own retries.
        assert first.max_retries == second.max_retries == third.max_retries == 0
    finally:
        await first.close()


def _mock_sdk(monkeypatch, provider, respond):
    """Route the pooled SDK client through an in-process transport."""
    if provider == "openai":
        http = httpx.AsyncClient(transport=httpx.MockTransport(respond))
        sdk_class = openai.AsyncOpenAI
        monkeypatch.setattr(openai, "AsyncOpenAI", lambda **kw: sdk_class(http_client=http, **kw))
    else:
        http = httpx2.AsyncClient(transport=httpx2.MockTransport(respond))
        sdk_class = anthropic.AsyncAnthropic
        monkeypatch.setattr(anthropic, "AsyncAnthropic", lambda **kw: sdk_class(http_client=http, **kw))


async def _request(provider, client, model):
    if provider == "openai":
        return await client.chat.completions.create(model=model, messages=[])
    return await client.messages.create(model=model, max_tokens=1, messages=[])


def _response(provider, model):
    if provider == "openai":
        return httpx.Response(200, json={"id": "offline", "object": "chat.completion", "created": 0,
                                         "model": model, "choices": []})
    return httpx2.Response(200, json={"id": "offline", "type": "message", "role": "assistant", "model": model,
                                      "content": [], "stop_reason": "end_turn", "stop_sequence": None,
                                      "usage": {"input_tokens": 0, "output_tokens": 0}})


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", CLIENTS)
async def test_concurrent_requests_keep_their_own_timeout_extensions(monkeypatch, provider):
    seen = {}
    entered = asyncio.Event()

    async def respond(request):
        model = json.loads(request.content)["model"]
        seen[model] = dict(request.extensions["timeout"])
        if len(seen) == 2:
            entered.set()
        await asyncio.wait_for(entered.wait(), 2)
        return _response(provider, model)

    _mock_sdk(monkeypatch, provider, respond)
    first, second = sdk(provider, 45), sdk(provider, 120)
    timeout = httpx.Timeout if provider == "openai" else httpx2.Timeout
    try:
        assert first._client is second._client
        await asyncio.gather(_request(provider, first, "short"), _request(provider, second, "long"))
        assert seen == {"short": timeout(45).as_dict(), "long": timeout(120).as_dict()}
        assert (first.timeout, second.timeout) == (45, 120)
    finally:
        await first.close()


@pytest.mark.asyncio
@pytest.mark.parametrize("boundary", ["credential", "provider"])
async def test_security_boundaries_get_distinct_transports(boundary):
    first = sdk("openai")
    second = sdk("anthropic") if boundary == "provider" else sdk("openai", key="other-synthetic-key")
    try:
        assert first._client is not second._client
        assert pool_size() == 2
        assert first.max_retries == second.max_retries == 0
    finally:
        await asyncio.gather(first.close(), second.close())


@pytest.mark.parametrize("provider", CLIENTS)
def test_event_loops_get_distinct_transports(provider):
    first_loop, second_loop = asyncio.new_event_loop(), asyncio.new_event_loop()

    async def client():
        return sdk(provider)

    first = second = None
    try:
        first = first_loop.run_until_complete(client())
        second = second_loop.run_until_complete(client())
        assert first._client is not second._client
        assert pool_size() == 2
    finally:
        if first is not None:
            first_loop.run_until_complete(first.close())
        if second is not None:
            second_loop.run_until_complete(second.close())
        first_loop.close()
        second_loop.close()


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", CLIENTS)
async def test_closed_shared_transport_is_replaced(provider):
    first = sdk(provider, 45)
    second = sdk(provider, 90)
    await second.close()
    assert first.is_closed()

    replacement = sdk(provider, 120)
    try:
        assert not replacement.is_closed()
        assert replacement._client is not first._client
        assert replacement.timeout == 120
        assert pool_size() == 1
    finally:
        await replacement.close()


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", CLIENTS)
async def test_a_missing_credential_never_opens_a_transport(provider, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, f"{provider}_api_key", None)
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    response = await CLIENTS[provider]().generate_json("System", "User")
    assert response.error == f"{provider} request failed (MissingCredential; client)"
    assert response.error_code == "generation_unavailable" and pool_size() == 0
