"""Timeout diagnostics distinguish waiting from interrupted visible output."""
import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.openlux import OpenLuxLLMClient
from app.services.llm.telemetry import usage_record_from_response


@pytest.mark.asyncio
@pytest.mark.parametrize("progress", ["none", "event", "content", "finished"])
async def test_cancelled_json_retains_progress_but_never_partial_content(progress, monkeypatch):
    monkeypatch.setattr("app.services.llm.tracing.record_attempt", AsyncMock())
    ready = asyncio.Event()

    class StreamClient(OpenLuxLLMClient):
        async def _events(self, *args):
            if progress != "none":
                yield SimpleNamespace(usage=None, choices=[SimpleNamespace(
                    index=0, finish_reason="stop" if progress == "finished" else None,
                    delta=SimpleNamespace(content='{"private":"unfinished' if progress in {"content", "finished"} else None),
                )])
            ready.set()
            await asyncio.Event().wait()

    client = StreamClient(api_key="not-a-real-key", model="test-model")
    task = asyncio.create_task(client.generate_json("System", "User"))
    await asyncio.wait_for(ready.wait(), timeout=1)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    response = client.last_attempt
    assert (response.first_event_ms is not None) == (progress != "none")
    assert (response.first_content_ms is not None) == (progress in {"content", "finished"})
    assert response.response_chars == (22 if progress in {"content", "finished"} else 0)
    assert response.finish_reason == ("stop" if progress == "finished" else None)
    assert response.data == {} and response.raw_response is None
    assert response.total_tokens is None
    usage = usage_record_from_response(operation="lesson_package", response=response)
    assert not usage.success
    assert usage.metadata["response_chars"] == response.response_chars
    assert "private" not in json.dumps(usage.metadata)


@pytest.mark.parametrize("details,expected", [
    (None, None), ({"reasoning_tokens": 7}, 7),
    (SimpleNamespace(reasoning_tokens=0), 0),
    ({"reasoning_tokens": -1}, None), ({"reasoning_tokens": True}, None),
    ({"reasoning_tokens": "7"}, None), ({"reasoning_tokens": 21}, None),
    ({"reasoning_tokens": float("nan")}, None),
])
def test_reasoning_count_is_optional_validated_provider_metadata(details, expected):
    usage = SimpleNamespace(completion_tokens=20, completion_tokens_details=details)
    assert OpenLuxLLMClient._reported_reasoning_tokens(usage) == expected


@pytest.mark.asyncio
@pytest.mark.parametrize("outcome", ["complete", "length", "cancelled"])
async def test_json_attempt_retains_reasoning_count_without_reasoning_text(outcome, monkeypatch):
    monkeypatch.setattr("app.services.llm.tracing.record_attempt", AsyncMock())
    ready = asyncio.Event()
    reported = SimpleNamespace(prompt_tokens=10, completion_tokens=20, total_tokens=30,
        completion_tokens_details=SimpleNamespace(reasoning_tokens=7))

    class StreamClient(OpenLuxLLMClient):
        async def _events(self, *args):
            yield SimpleNamespace(usage=reported, choices=[SimpleNamespace(
                index=0, finish_reason="length" if outcome == "length" else "stop",
                delta=SimpleNamespace(content='{"ok":true}', reasoning_content="PRIVATE REASONING"),
            )])
            ready.set()
            if outcome == "cancelled":
                await asyncio.Event().wait()

    client = StreamClient(api_key="not-a-real-key", model="test-model")
    if outcome == "cancelled":
        task = asyncio.create_task(client.generate_json("System", "User"))
        await asyncio.wait_for(ready.wait(), timeout=1)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        response = client.last_attempt
    else:
        response = await client.generate_json("System", "User")
    assert response.thoughts_tokens == 7
    assert response.completion_tokens == 20 and response.total_tokens == 30
    assert bool(response.error) == (outcome != "complete")
    assert "PRIVATE REASONING" not in str(response)
    record = usage_record_from_response(operation="lesson_package", response=response)
    assert record.metadata["thoughts_tokens"] == 7
    assert record.completion_tokens == 20 and record.total_tokens == 30
