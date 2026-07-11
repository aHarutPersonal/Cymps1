import asyncio

from app.core.async_runtime import run_async


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
