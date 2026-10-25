"""Package stage time excludes only the wrapper's unstarted local queue."""
import asyncio

import pytest

from app.core.config import settings
from app.services.llm.client import LLMResponse
from app.tasks.plans import PlanDetailDeadlineExceeded, _deadline_client_factory


@pytest.fixture(autouse=True)
def one_local_slot(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "dummy")
    monkeypatch.setattr(settings, "llm_admission_limits", {"dummy:offline": 1})
    monkeypatch.setattr(settings, "llm_admission_foreground_reserve", 0)
    monkeypatch.setattr(settings, "llm_admission_per_user", 1)


class WaitingClient:
    model = "offline"

    def __init__(self):
        self.started = asyncio.Event()
        self.release = asyncio.Event()
        self.finished = False

    async def generate_json(self, **kwargs):
        self.started.set()
        try:
            await self.release.wait()
            return LLMResponse(data={"ok": True})
        finally:
            self.finished = True


@pytest.mark.asyncio
async def test_activity_tracks_provider_execution_but_not_local_queue():
    clients = [WaitingClient(), WaitingClient()]
    factory = _deadline_client_factory(lambda **kw: clients.pop(0),
                                       deadline=asyncio.get_running_loop().time() + 2)
    first, second = factory(timeout=1), factory(timeout=1)
    events = []
    assert first.enforces_activity_callbacks is True
    first.set_generation_activity_callback(lambda active: events.append(("first", active)))
    second.set_generation_activity_callback(lambda active: events.append(("second", active)))
    a = asyncio.create_task(first.generate_json())
    await first._client.started.wait()
    b = asyncio.create_task(second.generate_json())
    await asyncio.sleep(0)
    assert events == [("first", True)] and not second.request_started
    first._client.release.set()
    await a
    await second._client.started.wait()
    assert events == [("first", True), ("first", False), ("second", True)]
    second._client.release.set()
    await b
    assert events[-1] == ("second", False)


@pytest.mark.asyncio
async def test_queued_cancellation_has_no_activity_but_started_cancellation_balances_callback():
    factory = _deadline_client_factory(lambda **kw: WaitingClient(),
                                       deadline=asyncio.get_running_loop().time() + 2)
    first, second = factory(timeout=1), factory(timeout=1)
    events = []
    first.set_generation_activity_callback(lambda active: events.append(("first", active)))
    second.set_generation_activity_callback(lambda active: events.append(("second", active)))
    a = asyncio.create_task(first.generate_json())
    await first._client.started.wait()
    b = asyncio.create_task(second.generate_json())
    await asyncio.sleep(0)
    b.cancel()
    with pytest.raises(asyncio.CancelledError):
        await b
    assert not second.request_started and events == [("first", True)]
    a.cancel()
    with pytest.raises(asyncio.CancelledError):
        await a
    assert first._client.finished and events == [("first", True), ("first", False)]
    # Cancellation releases the semaphore as well as the active-time counter.
    second._client.release.set()
    await second.generate_json()
    assert events[-2:] == [("second", True), ("second", False)]


@pytest.mark.asyncio
async def test_timeout_balances_activity_and_expired_queue_never_starts_it():
    factory = _deadline_client_factory(lambda **kw: WaitingClient(),
                                       deadline=asyncio.get_running_loop().time() + .02)
    first, second = factory(timeout=1), factory(timeout=1)
    first_events, second_events = [], []
    first.set_generation_activity_callback(first_events.append)
    second.set_generation_activity_callback(second_events.append)
    a = asyncio.create_task(first.generate_json())
    await first._client.started.wait()
    with pytest.raises(PlanDetailDeadlineExceeded):
        await second.generate_json()
    result = await a
    assert "TimeoutError" in result.error
    assert first_events == [True, False] and first._client.finished
    assert second_events == [] and not second.request_started


@pytest.mark.asyncio
async def test_provider_exception_still_balances_activity_callback():
    class BrokenClient:
        async def generate_json(self, **kwargs):
            raise RuntimeError("offline failure")

    factory = _deadline_client_factory(lambda **kw: BrokenClient(),
                                       deadline=asyncio.get_running_loop().time() + 2)
    client = factory(timeout=1)
    events = []
    client.set_generation_activity_callback(events.append)
    with pytest.raises(RuntimeError, match="offline failure"):
        await client.generate_json()
    assert events == [True, False]
