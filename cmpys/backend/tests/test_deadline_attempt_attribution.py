"""A new deadline failure must never inherit a previous provider charge."""
import asyncio

import pytest

from app.core.config import settings
from app.services.llm.client import LLMResponse
from app.tasks.plans import _deadline_client_factory


@pytest.fixture(autouse=True)
def local_capacity(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})


class ReusedClient:
    model = "offline-model"

    def __init__(self, mode):
        self.mode = mode
        self.last_attempt = None
        self.calls = 0

    async def generate_json(self, **kwargs):
        self.calls += 1
        if self.calls == 1:
            self.last_attempt = LLMResponse(
                data={"first": True}, attempt_id="first-attempt", prompt_tokens=10,
                completion_tokens=20, total_tokens=30, first_content_ms=2,
                raw_response="OLD DRAFT", effective_parameters={"previous": True},
            )
            return self.last_attempt
        try:
            await asyncio.sleep(1)
        except asyncio.CancelledError:
            if self.mode == "fresh":
                self.last_attempt = LLMResponse(
                    data={}, error="cancelled", attempt_id="second-attempt",
                    prompt_tokens=40, completion_tokens=50, total_tokens=90,
                    first_content_ms=3, effective_parameters={"current": True},
                )
            elif self.mode == "copied_old":
                self.last_attempt = self.last_attempt.model_copy(deep=True)
            raise


@pytest.mark.asyncio
@pytest.mark.parametrize("mode", ["unchanged", "copied_old"])
async def test_cancelled_retry_keeps_unknown_usage_instead_of_reusing_previous_attempt(mode):
    underlying = ReusedClient(mode)
    factory = _deadline_client_factory(lambda **kwargs: underlying,
                                       deadline=asyncio.get_running_loop().time() + 1)
    client = factory(timeout=.01)
    previous = await client.generate_json(system_prompt="system", user_prompt="first")
    timed_out = await client.generate_json(system_prompt="system", user_prompt="second")
    assert previous.attempt_id == "first-attempt" and previous.total_tokens == 30
    assert "TimeoutError" in timed_out.error
    assert timed_out.attempt_id is None
    assert timed_out.prompt_tokens is None and timed_out.completion_tokens is None
    assert timed_out.total_tokens is None and timed_out.first_content_ms is None
    assert timed_out.raw_response is None and timed_out.data == {}
    assert "previous" not in timed_out.effective_parameters
    assert timed_out.model == underlying.model and timed_out.duration_ms > 0
    assert underlying.calls == 2


@pytest.mark.asyncio
async def test_fresh_cancelled_attempt_preserves_its_own_identity_usage_and_timing():
    underlying = ReusedClient("fresh")
    factory = _deadline_client_factory(lambda **kwargs: underlying,
                                       deadline=asyncio.get_running_loop().time() + 1)
    client = factory(timeout=.01)
    await client.generate_json(system_prompt="system", user_prompt="first")
    timed_out = await client.generate_json(system_prompt="system", user_prompt="second")
    assert "TimeoutError" in timed_out.error
    assert timed_out.attempt_id == "second-attempt" and timed_out.total_tokens == 90
    assert timed_out.prompt_tokens == 40 and timed_out.completion_tokens == 50
    assert timed_out.first_content_ms == 3 and timed_out.effective_parameters["current"] is True
    assert "previous" not in timed_out.effective_parameters
    assert underlying.calls == 2
