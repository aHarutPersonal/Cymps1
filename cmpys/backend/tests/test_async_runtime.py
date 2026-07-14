import asyncio

from app.core.async_runtime import run_async
from app.services import gemini


async def _value():
    return "ok"


def test_run_async_creates_loop_when_worker_has_none():
    asyncio.set_event_loop(None)
    try:
        assert run_async(_value()) == "ok"
        loop = asyncio.get_event_loop()
        assert loop.is_closed() is False
    finally:
        loop = asyncio.get_event_loop()
        loop.close()
        asyncio.set_event_loop(None)


def test_gemini_client_is_reused_only_on_its_own_event_loop(monkeypatch):
    created = []

    class FakeClient:
        def __init__(self, *, api_key):
            self.api_key = api_key
            created.append(self)

    monkeypatch.setattr(gemini.genai, "Client", FakeClient)
    monkeypatch.setattr(gemini, "_client_singleton", None)
    monkeypatch.setattr(gemini, "_client_api_key", None)
    monkeypatch.setattr(gemini, "_client_event_loop", None)

    async def get_clients():
        return gemini._gemini_client(), gemini._gemini_client()

    first_loop = asyncio.new_event_loop()
    second_loop = asyncio.new_event_loop()
    try:
        first, first_again = first_loop.run_until_complete(get_clients())
        second, second_again = second_loop.run_until_complete(get_clients())
    finally:
        first_loop.close()
        second_loop.close()

    assert first is first_again
    assert second is second_again
    assert first is not second
    assert created == [first, second]
