"""A failed tutorial gets fresh, independent attempts within its deadline (plan Phase 4.1)."""
import asyncio

import pytest

from app.services.llm.client import LLMResponse
from app.tasks.plans import _generate_plan_item_details_parallel
from tests.test_tutorial_lookahead_failures import _pipeline, _ready


class RecordingStore:
    """A private checkpoint store that only records which step hashes are loaded."""

    def __init__(self):
        self.loaded = []

    async def load_step(self, step_id, step_hash):
        self.loaded.append((step_id, step_hash))
        return None

    async def load_package_parts(self, step_id, step_hash):
        return None

    async def __call__(self, *args, **kwargs):
        return True

    def __getattr__(self, name):
        return self


def failing(monkeypatch, failures: int, error="Exercise contract rejected"):
    """The package build rejects step_1 for its first ``failures`` attempts."""
    built, common, validations = _pipeline(monkeypatch, set())
    from app.services.planning import package_builder
    succeed = package_builder.generate_initial_package

    async def build(step, context, **kwargs):
        if step["id"] == "step_1" and built.count("step_1") < failures:
            built.append(step["id"])
            return None, LLMResponse(data={}, error=error), None
        return await succeed(step, context, **kwargs)

    monkeypatch.setattr("app.services.planning.package_builder.generate_initial_package", build)
    return built, common


@pytest.mark.asyncio
async def test_a_failed_tutorial_publishes_on_a_fresh_attempt(monkeypatch):
    monkeypatch.setattr("app.core.config.settings.tutorial_fresh_attempts", 2)
    built, common = failing(monkeypatch, 2)
    attempts, store = [], RecordingStore()
    payload, _, error = await _generate_plan_item_details_parallel(
        **common, lesson_format="tutorial_v1", repair_attempts=attempts, private_checkpoint_store=store)
    assert error is None and "step_1" in _ready(payload)
    assert built.count("step_1") == 3
    assert [entry["kind"] for entry in attempts if entry["step_id"] == "step_1"] == ["fresh_attempt"] * 2
    # Each attempt reads its own private checkpoints, never the failed attempt's.
    hashes = [step_hash for step_id, step_hash in store.loaded if step_id == "step_1"]
    assert len(hashes) == 3 and len(set(hashes)) == 3


@pytest.mark.asyncio
async def test_fresh_attempts_are_bounded_and_the_last_error_is_reported(monkeypatch):
    monkeypatch.setattr("app.core.config.settings.tutorial_fresh_attempts", 2)
    built, common = failing(monkeypatch, 9)
    _, _, error = await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1")
    assert error and error.startswith("step_1:") and built.count("step_1") == 3


@pytest.mark.asyncio
async def test_no_fresh_attempt_without_time_for_a_whole_tutorial(monkeypatch):
    monkeypatch.setattr("app.core.config.settings.tutorial_fresh_attempts", 2)
    built, common = failing(monkeypatch, 9)
    deadline = asyncio.get_running_loop().time() + 120  # Below the 150 s a tutorial needs.
    _, _, error = await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1", deadline=deadline)
    assert error and built.count("step_1") == 1


@pytest.mark.asyncio
async def test_a_started_tutorial_is_never_regenerated(monkeypatch):
    monkeypatch.setattr("app.core.config.settings.tutorial_fresh_attempts", 2)
    built, common = failing(monkeypatch, 9)

    async def protected():
        return {"step_1"}

    _, _, error = await _generate_plan_item_details_parallel(
        **common, lesson_format="tutorial_v1", capacity_protected_steps=protected)
    assert error and built.count("step_1") == 1


@pytest.mark.asyncio
async def test_fresh_attempts_are_off_by_default(monkeypatch):
    built, common = failing(monkeypatch, 9)
    attempts = []
    _, _, error = await _generate_plan_item_details_parallel(
        **common, lesson_format="tutorial_v1", repair_attempts=attempts)
    assert error and built.count("step_1") == 1 and not attempts


@pytest.mark.asyncio
async def test_without_time_here_the_next_attempt_is_handed_to_a_requeued_job(monkeypatch):
    monkeypatch.setattr("app.core.config.settings.tutorial_fresh_attempts", 2)
    built, common = failing(monkeypatch, 9)
    attempts = []
    deadline = asyncio.get_running_loop().time() + 120
    payload, _, error = await _generate_plan_item_details_parallel(
        **common, lesson_format="tutorial_v1", deadline=deadline, repair_attempts=attempts)
    assert error and payload["_tutorial_retry"] == {"step_id": "step_1", "next_attempt": 1}
    assert [entry["kind"] for entry in attempts] == ["background_attempt"]


@pytest.mark.asyncio
async def test_a_requeued_job_starts_at_its_saved_attempt_and_never_resumes_the_failed_one(monkeypatch):
    monkeypatch.setattr("app.core.config.settings.tutorial_fresh_attempts", 2)
    built, common = failing(monkeypatch, 9)
    store = RecordingStore()
    payload, _, error = await _generate_plan_item_details_parallel(
        **common, lesson_format="tutorial_v1", tutorial_attempts={"step_1": 2}, private_checkpoint_store=store)
    # Attempt 3 is the last: one build, no marker, and not the first attempt's checkpoints.
    assert error and built.count("step_1") == 1 and "_tutorial_retry" not in payload
    first_attempt = RecordingStore()
    await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1",
                                               private_checkpoint_store=first_attempt)
    assert store.loaded[0] != first_attempt.loaded[0]


@pytest.mark.asyncio
async def test_a_finding_that_mentions_credit_is_still_retried(monkeypatch):
    # Pilot 2026-11-05: "the 120 beans bought on credit" stopped the retry as if the account had no credit.
    monkeypatch.setattr("app.core.config.settings.tutorial_fresh_attempts", 2)
    built, common = failing(monkeypatch, 1, error="teaching.cafe_month has no raw datum for the 120 beans bought on credit")
    payload, _, error = await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1")
    assert error is None and built.count("step_1") == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("provider_error", [
    "Your credit balance is too low to access the API",
    "credit_balance_exhausted",
    "insufficient_quota",
    "quota exceeded",
])
async def test_an_exhausted_provider_balance_is_retried_on_the_other_model(monkeypatch, provider_error):
    # One model out of credit is no stop: the fresh attempt runs on the other
    # model, and every call inside one attempt stays on that attempt's model.
    from app.services.llm.routes import current_tutorial_provider
    from app.services.planning import package_builder

    monkeypatch.setattr("app.core.config.settings.tutorial_fresh_attempts", 2)
    monkeypatch.setattr("app.core.config.settings.llm_route_overrides", {})
    built, common = failing(monkeypatch, 1, error=provider_error)
    failing_build = package_builder.generate_initial_package
    providers = []

    async def recording(step, context, **kwargs):
        if step["id"] == "step_1":
            providers.append(current_tutorial_provider())
        return await failing_build(step, context, **kwargs)

    monkeypatch.setattr("app.services.planning.package_builder.generate_initial_package", recording)
    attempts = []
    payload, _, error = await _generate_plan_item_details_parallel(
        **common, lesson_format="tutorial_v1", repair_attempts=attempts)
    assert error is None and "step_1" in _ready(payload)
    assert built.count("step_1") == 2
    assert providers == ["anthropic", "openai"]  # Haiku first, then luna
    assert [entry["kind"] for entry in attempts if entry["step_id"] == "step_1"] == ["fresh_attempt"]
