"""Timeout diagnostics distinguish waiting from interrupted visible output."""
import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.core.config import settings
from app.services.llm.openai_direct import reported_reasoning_tokens
from app.services.llm.telemetry import usage_record_from_response
from tests.direct_wire import PROVIDERS, Reply, client_for, serve

UNFINISHED = '{"private":"unfinished'


@pytest.fixture(autouse=True)
def offline(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    monkeypatch.setattr("app.services.llm.tracing.record_attempt", AsyncMock())


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("progress", ["none", "event", "content", "finished"])
async def test_cancelled_json_retains_progress_but_never_partial_content(provider, progress):
    if provider == "anthropic" and progress == "finished":
        pytest.skip("Anthropic reports its stop reason only with the final message")
    ready = asyncio.Event()
    pieces = {"none": [], "event": [None], "content": [UNFINISHED], "finished": [UNFINISHED]}[progress]
    client = client_for(provider)
    serve(client, Reply(pieces=pieces, finish="stop" if progress == "finished" else None, usage=None,
                        ready=ready))
    task = asyncio.create_task(client.generate_json("System", "User"))
    await asyncio.wait_for(ready.wait(), timeout=1)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    response = client.last_attempt
    assert response.error == "cancelled"
    assert (response.first_event_ms is not None) == (progress != "none")
    assert (response.first_content_ms is not None) == (progress in {"content", "finished"})
    assert response.data == {} and response.raw_response is None
    assert response.total_tokens is None
    usage = usage_record_from_response(operation="lesson_package", response=response)
    assert not usage.success
    assert "private" not in json.dumps(usage.metadata)
    assert response.finish_reason == ("stop" if progress == "finished" else None)
    assert response.response_chars == (22 if progress in {"content", "finished"} else 0)
    assert usage.metadata["response_chars"] == response.response_chars


@pytest.mark.parametrize("details,expected", [
    (None, None), ({"reasoning_tokens": 7}, 7),
    (SimpleNamespace(reasoning_tokens=0), 0),
    ({"reasoning_tokens": -1}, None), ({"reasoning_tokens": True}, None),
    ({"reasoning_tokens": "7"}, None), ({"reasoning_tokens": 21}, None),
    ({"reasoning_tokens": float("nan")}, None),
])
def test_reasoning_count_is_optional_validated_provider_metadata(details, expected):
    usage = SimpleNamespace(completion_tokens=20, completion_tokens_details=details)
    assert reported_reasoning_tokens(usage) == expected


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("outcome", ["complete", "length", "cancelled"])
async def test_json_attempt_retains_reasoning_count_without_reasoning_text(provider, outcome):
    ready = asyncio.Event()
    client = client_for(provider)
    serve(client, Reply('{"ok":true}', "length" if outcome == "length" else "stop", usage=(10, 20),
                        reasoning_tokens=7, reasoning_text="PRIVATE REASONING",
                        ready=ready if outcome == "cancelled" else None))
    if outcome == "cancelled":
        task = asyncio.create_task(client.generate_json("System", "User"))
        await asyncio.wait_for(ready.wait(), timeout=1)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        response = client.last_attempt
    else:
        response = await client.generate_json("System", "User")
    assert response.completion_tokens == 20 and response.total_tokens == 30
    assert bool(response.error) == (outcome != "complete")
    assert "PRIVATE REASONING" not in str(response)
    record = usage_record_from_response(operation="lesson_package", response=response)
    assert record.completion_tokens == 20 and record.total_tokens == 30
    assert response.thoughts_tokens == 7
    assert record.metadata["thoughts_tokens"] == 7
