"""F5: a streamed reply survives one transient connect-phase stall.

Live run G2: the mentor lab's written comparison failed on first try with
"zai stream failed (APITimeoutError)" after exactly the 10 s httpx connect
timeout; the endpoint was healthy a moment later. A connect failure sends no
request and costs nothing, so the streaming transport retries it once, before
any text. A read timeout, any other failure, or anything after text arrived is
never retried. Each actual request still records its own usage row.
"""

from types import SimpleNamespace as NS

import httpx
import openai
import pytest

from app.core.config import settings
from app.services.llm.client import get_llm_client
from app.services.llm.openlux import OpenLuxStreamError
from app.services.llm.zai import ZaiLLMClient
from tests.test_openlux import Stream, chunk

URL = "https://api.example.invalid/v1/chat/completions"


def _failure(kind: str) -> Exception:
    request = httpx.Request("POST", URL)
    cause = {
        "connect_error": httpx.ConnectError("refused"),
        "connect_timeout": httpx.ConnectTimeout("connect stalled"),
        "read_timeout": httpx.ReadTimeout("read stalled"),
        "protocol": httpx.RemoteProtocolError("server closed the connection"),
    }[kind]
    error = (
        openai.APITimeoutError(request=request)
        if isinstance(cause, httpx.TimeoutException)
        else openai.APIConnectionError(request=request)
    )
    error.__cause__ = cause
    return error


def _transport(monkeypatch, client, outcomes):
    """Each create() call takes the next outcome: an exception or a chunk list."""
    calls = []

    async def create(**kwargs):
        calls.append(kwargs)
        outcome = outcomes[len(calls) - 1]
        if isinstance(outcome, Exception):
            raise outcome
        return Stream(outcome)

    monkeypatch.setattr(
        client, "_get_client", lambda key: NS(chat=NS(completions=NS(create=create)))
    )
    return calls


@pytest.fixture
def usage_rows(monkeypatch):
    from app.services.llm import telemetry

    rows = []

    async def record(items):
        rows.extend(items)

    monkeypatch.setattr(telemetry, "record_usage_records", record)
    return rows


@pytest.fixture(params=["openlux", "zai"])
def client(request, monkeypatch):
    if request.param == "openlux":
        monkeypatch.setattr(settings, "llm_provider", "openlux")
        monkeypatch.setattr(settings, "openlux_api_key", "fake-openlux-secret")
        monkeypatch.setattr(settings, "openlux_base_url", "https://api.openlux.ai/v1")
        monkeypatch.setattr(settings, "openlux_fast_model", "gpt-5.6-terra")
        monkeypatch.setattr(settings, "openlux_model", "gpt-5.6-terra")
        monkeypatch.setattr(settings, "openlux_quality_model", "gpt-5.6-sol")
    else:
        monkeypatch.setattr(settings, "llm_provider", "zai")
        monkeypatch.setattr(settings, "zai_api_key", "fake-test-key")
    built = get_llm_client()
    assert isinstance(built, ZaiLLMClient) is (request.param == "zai")
    return built


async def _collect(client):
    return [text async for text in client.stream_text("System", "User", operation="comparison_stream")]


USAGE = NS(prompt_tokens=10, completion_tokens=20, total_tokens=30)


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["connect_error", "connect_timeout"])
async def test_one_connect_phase_failure_is_retried_before_any_text(monkeypatch, client, usage_rows, kind):
    calls = _transport(monkeypatch, client, [
        _failure(kind),
        [chunk("Your record "), chunk("at 24.", "stop"), NS(choices=[], usage=USAGE)],
    ])

    assert await _collect(client) == ["Your record ", "at 24."]

    assert len(calls) == 2
    # One usage row per actual request: the failed connect and the reply.
    assert [(row.success, row.result_status) for row in usage_rows] == [
        (False, "incomplete"), (True, "streamed"),
    ]
    assert usage_rows[0].total_tokens is None and usage_rows[1].total_tokens == 30
    assert all(row.operation == "comparison_stream" for row in usage_rows)


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["read_timeout", "protocol"])
async def test_read_timeouts_and_other_failures_are_never_retried(monkeypatch, client, usage_rows, kind):
    calls = _transport(monkeypatch, client, [_failure(kind), [chunk("never", "stop")]])

    with pytest.raises(OpenLuxStreamError):
        await _collect(client)

    assert len(calls) == 1 and len(usage_rows) == 1


@pytest.mark.asyncio
async def test_a_failure_after_text_arrived_is_never_retried(monkeypatch, client, usage_rows):
    calls = _transport(monkeypatch, client, [
        [chunk("Partial "), _failure("connect_error")],
        [chunk("spliced", "stop")],
    ])
    received = []

    with pytest.raises(OpenLuxStreamError):
        async for text in client.stream_text("System", "User", operation="comparison_stream"):
            received.append(text)

    assert received == ["Partial "]
    assert len(calls) == 1 and len(usage_rows) == 1


@pytest.mark.asyncio
async def test_the_connect_retry_happens_once(monkeypatch, client, usage_rows):
    calls = _transport(monkeypatch, client, [_failure("connect_timeout"), _failure("connect_timeout")])

    with pytest.raises(OpenLuxStreamError) as raised:
        await _collect(client)

    assert len(calls) == 2 and len(usage_rows) == 2
    assert raised.value.retryable is True  # callers' own recovery still applies
