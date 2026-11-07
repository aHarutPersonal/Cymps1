"""F5: a streamed reply survives one transient connect-phase stall.

Live run G2: the mentor lab's written comparison failed on first try with a
stream APITimeoutError after exactly the 10 s httpx connect timeout; the
endpoint was healthy a moment later. A connect failure sends no request and
costs nothing, so the streaming transport retries it once, before any text. A
read timeout, any other failure, or anything after text arrived is never
retried. Each actual request still records its own usage row.
"""

import anthropic
import httpx
import httpx2
import openai
import pytest

from app.core.config import settings
from app.services.llm.protocol import ProviderStreamError
from tests.direct_wire import PROVIDERS, Reply, client_for, serve


def _failure(provider: str, kind: str) -> Exception:
    """The SDK's connection error raised ``from`` its HTTP library's error."""
    sdk, http = (openai, httpx) if provider == "openai" else (anthropic, httpx2)
    request = http.Request("POST", "https://api.example.invalid/v1/stream")
    cause = {
        "connect_error": http.ConnectError("refused"),
        "connect_timeout": http.ConnectTimeout("connect stalled"),
        "read_timeout": http.ReadTimeout("read stalled"),
        "protocol": http.RemoteProtocolError("server closed the connection"),
    }[kind]
    error = (
        sdk.APITimeoutError(request=request)
        if isinstance(cause, http.TimeoutException)
        else sdk.APIConnectionError(request=request)
    )
    error.__cause__ = cause
    return error


@pytest.fixture
def usage_rows(monkeypatch):
    from app.services.llm import telemetry

    rows = []

    async def record(items, **_):
        rows.extend(items)

    monkeypatch.setattr(telemetry, "record_usage_records", record)
    return rows


@pytest.fixture(params=PROVIDERS)
def client(request, monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    return client_for(request.param)


async def _collect(client):
    return [text async for text in client.stream_text("System", "User", operation="comparison_stream")]


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["connect_error", "connect_timeout"])
async def test_one_connect_phase_failure_is_retried_before_any_text(client, usage_rows, kind):
    wire = serve(client, [
        Reply(usage=None, open_error=_failure(client.provider_name, kind)),
        Reply(pieces=["Your record ", "at 24."], usage=(10, 20)),
    ])

    assert await _collect(client) == ["Your record ", "at 24."]

    assert len(wire.requests) == 2
    # One usage row per actual request: the failed connect and the reply.
    assert [(row.success, row.result_status) for row in usage_rows] == [
        (False, "incomplete"), (True, "streamed"),
    ]
    assert usage_rows[0].total_tokens is None and usage_rows[1].total_tokens == 30
    assert all(row.operation == "comparison_stream" for row in usage_rows)
    assert all(row.provider == client.provider_name for row in usage_rows)


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["read_timeout", "protocol"])
async def test_read_timeouts_and_other_failures_are_never_retried(client, usage_rows, kind):
    wire = serve(client, [Reply(usage=None, open_error=_failure(client.provider_name, kind)),
                          Reply("never", "stop")])

    with pytest.raises(ProviderStreamError):
        await _collect(client)

    assert len(wire.requests) == 1 and len(usage_rows) == 1


@pytest.mark.asyncio
async def test_a_failure_after_text_arrived_is_never_retried(client, usage_rows):
    wire = serve(client, [
        Reply(pieces=["Partial "], usage=None, error=_failure(client.provider_name, "connect_error")),
        Reply("spliced", "stop"),
    ])
    received = []

    with pytest.raises(ProviderStreamError):
        async for text in client.stream_text("System", "User", operation="comparison_stream"):
            received.append(text)

    assert received == ["Partial "]
    assert len(wire.requests) == 1 and len(usage_rows) == 1


@pytest.mark.asyncio
async def test_the_connect_retry_happens_once(client, usage_rows):
    wire = serve(client, [Reply(usage=None, open_error=_failure(client.provider_name, "connect_timeout")),
                          Reply(usage=None, open_error=_failure(client.provider_name, "connect_timeout"))])

    with pytest.raises(ProviderStreamError) as raised:
        await _collect(client)

    assert len(wire.requests) == 2 and len(usage_rows) == 2
    assert raised.value.retryable is True  # callers' own recovery still applies
    assert "stalled" not in str(raised.value)
