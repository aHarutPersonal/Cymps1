"""Pilot budget guard: what a call is booked at when its usage is unknown."""
import asyncio
import json
from types import SimpleNamespace

import pytest

from app.services.llm.client import LLMResponse
from scripts.pilot_generation import Budget, guard_client

RATES = (1.0, 4.0)  # USD per million input / output tokens


def _rows(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


class FakeProvider:
    """Mimics the streaming client: a cancellation leaves a cancelled last_attempt."""

    model, max_tokens, provider_name = "fake-model", 1000, "fake"

    def __init__(self, *, streamed_before_cancel=False, response=None):
        self.last_attempt = None
        self.calls = 0
        self.started = asyncio.Event()
        self.streamed_before_cancel = streamed_before_cancel
        self.response = response

    async def generate_json(self, *, system_prompt, user_prompt, output_model=None, **kwargs):
        self.calls += 1
        if self.response is not None:
            self.last_attempt = self.response
            return self.response
        self.started.set()
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            streamed = self.streamed_before_cancel
            self.last_attempt = LLMResponse(data={}, error="cancelled", duration_ms=12.0,
                first_event_ms=2000.0 if streamed else None, first_content_ms=2500.0 if streamed else None,
                response_chars=500 if streamed else 0)
            raise


def _guard(tmp_path, provider):
    """Wraps provider.generate_json in place, as the pilot factory does."""
    budget = Budget(tmp_path / "usage.jsonl", 5)
    guard_client(provider, budget=budget, stage={"scenario_id": "s", "run_id": "candidate-1"},
                 output_dir=tmp_path, token_rates=lambda bound: RATES, reasoning_reserve=200,
                 estimate_cost=lambda response: (response.prompt_tokens * RATES[0]
                     + response.completion_tokens * RATES[1]) / 1_000_000)
    return budget


def _expected_parts(system_prompt, user_prompt):
    input_bound = len((system_prompt + user_prompt + json.dumps({})).encode()) + 8192
    output_bound = FakeProvider.max_tokens + 200
    return input_bound * RATES[0] / 1e6 * 1.25, output_bound * RATES[1] / 1e6 * 1.25


async def _cancel_after_start(provider):
    task = asyncio.create_task(provider.generate_json(system_prompt="sys", user_prompt="user"))
    await provider.started.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task


@pytest.mark.asyncio
async def test_cancelled_before_any_response_books_only_the_input_part(tmp_path):
    provider = FakeProvider()
    budget = _guard(tmp_path, provider)
    await _cancel_after_start(provider)
    reserved, finished = _rows(tmp_path / "usage.jsonl")
    input_part, output_part = _expected_parts("sys", "user")
    assert reserved["reserved_usd"] == pytest.approx(input_part + output_part)
    assert finished["charged_basis"] == "input_only_cancelled"
    assert finished["charged_usd"] == pytest.approx(input_part)
    assert finished["usage_unknown"] is True and finished["response_received"] is False
    assert budget.spent == pytest.approx(input_part) and not budget.pending
    # A restart books the same amount from the ledger.
    assert Budget(tmp_path / "usage.jsonl", 5).spent == pytest.approx(input_part)


@pytest.mark.asyncio
async def test_cancelled_after_streaming_started_keeps_the_full_reservation(tmp_path):
    provider = FakeProvider(streamed_before_cancel=True)
    budget = _guard(tmp_path, provider)
    await _cancel_after_start(provider)
    reserved, finished = _rows(tmp_path / "usage.jsonl")
    assert finished["charged_basis"] == "full_reserve"
    assert finished["charged_usd"] == reserved["reserved_usd"] == budget.spent


@pytest.mark.asyncio
async def test_error_response_with_unknown_usage_keeps_the_full_reservation(tmp_path):
    failed = LLMResponse(data={}, error="zai request failed (ValueError; finish=missing)",
                         raw_response='{"partial"', first_event_ms=10.0, response_chars=10)
    provider = FakeProvider(response=failed)
    _guard(tmp_path, provider)
    response = await provider.generate_json(system_prompt="sys", user_prompt="user")
    assert response.error.startswith("zai request failed")
    reserved, finished = _rows(tmp_path / "usage.jsonl")
    assert finished["charged_basis"] == "full_reserve"
    assert finished["charged_usd"] == reserved["reserved_usd"]


@pytest.mark.asyncio
async def test_known_usage_is_charged_at_the_actual_estimate(tmp_path):
    done = LLMResponse(data={"ok": True}, finish_reason="stop", prompt_tokens=1000,
                       completion_tokens=100, total_tokens=1100)
    provider = FakeProvider(response=done)
    _guard(tmp_path, provider)
    await provider.generate_json(system_prompt="sys", user_prompt="user")
    _, finished = _rows(tmp_path / "usage.jsonl")
    assert finished["charged_basis"] == "actual"
    assert finished["charged_usd"] == pytest.approx((1000 * 1.0 + 100 * 4.0) / 1e6)
    assert finished["usage_unknown"] is False


def test_budget_finish_input_only_is_capped_by_the_reservation_and_validated(tmp_path):
    path = tmp_path / "usage.jsonl"
    budget = Budget(path, 1)
    request = budget.reserve(.2, {})
    for invalid in (float("nan"), float("inf"), -.01):
        with pytest.raises(ValueError, match="Invalid"):
            budget.finish(request, None, {}, input_only_usd=invalid)
    assert budget.pending[request] == .2
    budget.finish(request, None, {}, input_only_usd=.5)
    row = _rows(path)[-1]
    assert row["charged_usd"] == .2 and row["charged_basis"] == "input_only_cancelled"
    other = budget.reserve(.1, {})
    budget.finish(other, .03, {}, input_only_usd=.05)
    assert _rows(path)[-1]["charged_basis"] == "actual" and _rows(path)[-1]["charged_usd"] == .03
    legacy = budget.reserve(.1, {})
    budget.finish(legacy, None, {})
    assert _rows(path)[-1]["charged_basis"] == "full_reserve" and _rows(path)[-1]["charged_usd"] == .1
