"""One-ahead tutorial generation: write the current tutorial and the next, one at a time."""
import asyncio
import copy
from types import SimpleNamespace

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanTutorialOutlineOutput
from app.services.planning.generation_window import generation_window
from app.tasks.plans import _generate_plan_item_details_parallel
from tests.test_short_tutorial_pipeline import outline, sections, short_package


class _Store:
    """Private checkpoint store that records the step hash each write resumes with."""

    def __init__(self):
        self.hashes: dict[str, list[str]] = {}

    async def load_step(self, step_id, step_hash):
        self.hashes.setdefault(step_id, []).append(step_hash)
        return None

    async def load_package_parts(self, step_id, step_hash):
        return None

    async def save_package_parts(self, *args, **kwargs):
        return True

    async def save_package(self, *args, **kwargs):
        return True

    async def save_review_state(self, *args, **kwargs):
        return True

    async def clear_review_state(self, *args, **kwargs):
        return True

    async def save_sections(self, *args, **kwargs):
        return True

    async def clear_sections(self, *args, **kwargs):
        return True


def _pipeline(monkeypatch, rejected: set[str] | None = None):
    rejected = rejected if rejected is not None else set()
    state = {"active": 0, "max_active": 0, "built": [], "stages": []}

    async def build(step, context, **kwargs):
        state["built"].append(step["id"])
        state["active"] += 1
        state["max_active"] = max(state["max_active"], state["active"])
        try:
            for _ in range(3):
                await asyncio.sleep(0)
        finally:
            state["active"] -= 1
        if step["id"] in rejected:
            return None, LLMResponse(data={}, error="Exercise contract rejected"), SimpleNamespace(model="offline")
        return short_package(), LLMResponse(data={}), SimpleNamespace(model="offline")

    async def preflight(*args, **kwargs):
        return [], LLMResponse(data={}), SimpleNamespace(model="offline")

    async def review(step, **kwargs):
        return [], LLMResponse(data={"practice_minutes": 3}), SimpleNamespace(model="offline")

    class Client:
        model = "offline"

        async def generate_json(self, **kwargs):
            if kwargs["output_model"] is PlanTutorialOutlineOutput:
                return LLMResponse(data=outline(), finish_reason="stop")
            return LLMResponse(data=sections(), finish_reason="stop")

    async def checkpoint(payload, stage):
        state["stages"].append(stage)

    monkeypatch.setattr("app.services.planning.package_builder.generate_initial_package", build)
    monkeypatch.setattr("app.services.planning.package_preflight.review_package", preflight)
    monkeypatch.setattr("app.services.planning.lesson_review.review_lesson", review)
    validations: dict = {}
    packages: dict = {}
    common = dict(system_prompt="Teach", task_title="Claim sequence", mission_hours=36 / 60,
        user_goal="Reason", learning_preferences="examples", idol_name="Mentor", idol_domain="writing",
        idol_evidence={}, session_context="", active_tier="balanced", routing_reason="test",
        client_factory=lambda **kwargs: Client(), prepared_packages=packages,
        validation_records=validations, on_checkpoint=checkpoint)
    return state, common, validations


def _ready(payload):
    return [step["id"] for step in payload["steps"] if step.get("lesson_content")]


def _saved(payload, validations):
    clean = {key: value for key, value in payload.items() if not key.startswith("_")}
    return {**clean, "_generation": {"outline": outline(), "outline_contract_version": 3,
                                     "lesson_validation": copy.deepcopy(validations)}}


def _completed(*step_ids):
    async def read():
        return set(step_ids)
    return read


@pytest.mark.asyncio
async def test_fresh_mission_writes_t1_then_t2_one_at_a_time_and_parks(monkeypatch):
    state, common, _ = _pipeline(monkeypatch)

    payload, _, error = await _generate_plan_item_details_parallel(
        **common, lesson_format="tutorial_v1", learner_completed_step_ids=_completed())

    assert error is None
    assert payload.pop("_tutorial_waiting_for_learner") is True
    assert "_tutorial_continuation" not in payload
    assert state["built"] == ["step_1", "step_2"]  # Never T3.
    assert state["max_active"] == 1  # One writer at a time.
    assert _ready(payload) == ["step_1", "step_2"]
    assert state["stages"] == ["outline_ready", "step_1_ready", "step_2_ready"]


@pytest.mark.asyncio
async def test_without_a_completion_reader_the_window_is_the_first_two(monkeypatch):
    state, common, _ = _pipeline(monkeypatch)
    payload, _, error = await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1")
    assert error is None and payload.pop("_tutorial_waiting_for_learner") is True
    assert state["built"] == ["step_1", "step_2"]


@pytest.mark.asyncio
async def test_completing_t1_writes_only_t3(monkeypatch):
    state, common, validations = _pipeline(monkeypatch)
    first, _, _ = await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1")
    state["built"].clear()

    second, _, error = await _generate_plan_item_details_parallel(
        **common, existing_checkpoint=_saved(first, validations),
        learner_completed_step_ids=_completed("step_1"))

    assert error is None and second.pop("_tutorial_waiting_for_learner") is True
    assert state["built"] == ["step_3"]
    assert _ready(second) == ["step_1", "step_2", "step_3"]
    assert second["steps"][:2] == first["steps"][:2]  # Ready tutorials are untouched.


@pytest.mark.asyncio
async def test_a_window_that_is_already_ready_writes_nothing(monkeypatch):
    state, common, validations = _pipeline(monkeypatch)
    first, _, _ = await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1")
    state["built"].clear()

    again, calls, error = await _generate_plan_item_details_parallel(
        **common, existing_checkpoint=_saved(first, validations),
        learner_completed_step_ids=_completed())

    assert error is None and again.pop("_tutorial_waiting_for_learner") is True
    assert state["built"] == [] and calls == []


@pytest.mark.asyncio
async def test_a_completion_during_the_job_extends_the_window(monkeypatch):
    state, common, _ = _pipeline(monkeypatch)
    completed: set[str] = set()

    async def read():
        return set(completed)

    original = common["on_checkpoint"]

    async def checkpoint(payload, stage):
        await original(payload, stage)
        if stage == "step_2_ready":
            completed.add("step_1")  # The learner finished T1 while T2 was written.

    payload, _, error = await _generate_plan_item_details_parallel(
        **{**common, "on_checkpoint": checkpoint}, lesson_format="tutorial_v1",
        learner_completed_step_ids=read)

    assert error is None and payload.pop("_tutorial_waiting_for_learner") is True
    assert state["built"] == ["step_1", "step_2", "step_3"]
    assert state["max_active"] == 1


@pytest.mark.asyncio
async def test_last_tutorial_is_written_when_the_one_before_it_is_completed(monkeypatch):
    state, common, validations = _pipeline(monkeypatch)
    checkpoint = None
    done: list[str] = []
    built_per_run = []
    for index in range(1, 6):
        before = len(state["built"])
        payload, _, error = await _generate_plan_item_details_parallel(
            **common, lesson_format="tutorial_v1" if checkpoint is None else None,
            existing_checkpoint=checkpoint, learner_completed_step_ids=_completed(*done))
        assert error is None
        built_per_run.append(state["built"][before:])
        checkpoint = _saved(payload, validations)
        done.append(f"step_{index}")
    # Each completion of TN writes exactly T(N+2); completing T4 writes the
    # last tutorial (T6) and the final merge runs.
    assert built_per_run == [["step_1", "step_2"], ["step_3"], ["step_4"], ["step_5"], ["step_6"]]
    assert "_tutorial_waiting_for_learner" not in payload
    assert len(_ready(payload)) == 6
    assert state["max_active"] == 1


@pytest.mark.asyncio
async def test_failed_window_tutorial_is_reported_with_its_step(monkeypatch):
    state, common, _ = _pipeline(monkeypatch, rejected={"step_2"})

    payload, _, error = await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1")

    assert error and error.startswith("step_2:")
    assert payload.pop("_window_step_failed") == "step_2"
    assert _ready(payload) == ["step_1"]  # T1 stays published.
    assert state["built"] == ["step_1", "step_2"]


@pytest.mark.asyncio
async def test_capacity_hash_is_stable_across_one_at_a_time_retries(monkeypatch):
    rejected = {"step_2"}
    state, common, validations = _pipeline(monkeypatch, rejected=rejected)
    store = _Store()
    first, _, error = await _generate_plan_item_details_parallel(
        **common, lesson_format="tutorial_v1", private_checkpoint_store=store)
    assert error and first.pop("_window_step_failed") == "step_2"
    rejected.clear()

    second, _, error = await _generate_plan_item_details_parallel(
        **common, existing_checkpoint=_saved(first, validations), private_checkpoint_store=store)

    assert error is None and second.pop("_tutorial_waiting_for_learner") is True
    # The retry resumes the same private step identity: the ready set it is
    # allocated against did not change between attempts.
    assert len(store.hashes["step_2"]) == 2 and len(set(store.hashes["step_2"])) == 1
    assert store.hashes.keys() == {"step_1", "step_2"}  # T1 is reused, not rewritten.
    assert second["steps"][0] == first["steps"][0]


def test_window_is_first_incomplete_step_and_the_one_after():
    steps = ["step_1", "step_2", "step_3"]
    assert generation_window(steps, set()).step_ids == ("step_1", "step_2")
    assert generation_window(steps, {"step_1"}).step_ids == ("step_2", "step_3")
    assert generation_window(steps, {"step_1", "step_2"}).step_ids == ("step_3",)
    assert generation_window(steps, set(steps)).step_ids == ()


async def _four_ready_with_learner_on_t4(monkeypatch, state, common, validations):
    checkpoint = None
    done: list[str] = []
    for index in range(1, 4):
        payload, _, error = await _generate_plan_item_details_parallel(
            **common, lesson_format="tutorial_v1" if checkpoint is None else None,
            existing_checkpoint=checkpoint, learner_completed_step_ids=_completed(*done))
        assert error is None
        checkpoint = _saved(payload, validations)
        done.append(f"step_{index}")
    assert _ready(payload) == ["step_1", "step_2", "step_3", "step_4"]
    state["built"].clear()
    return checkpoint


@pytest.mark.asyncio
async def test_capacity_overrun_on_t5_corrects_only_t5_never_the_current_t4(monkeypatch):
    state, common, validations = _pipeline(monkeypatch)
    checkpoint = await _four_ready_with_learner_on_t4(monkeypatch, state, common, validations)
    shortened, protected_seen = [], []

    def targets(steps, mission_hours, protected, *, pending_count=0):
        protected_seen.append(set(protected))
        ids = [step["id"] for step in steps]
        if "step_5" not in ids or shortened:
            return []
        # An honest helper: the first editable ready tutorial absorbs the excess.
        return [step_id for step_id in ids if step_id not in protected][:1]

    async def shorten(step, package, context, **kwargs):
        shortened.append(step["id"])
        return {**step}, None

    monkeypatch.setattr("app.services.planning.tutorial_capacity.reading_capacity_targets", targets)
    monkeypatch.setattr("app.services.planning.tutorial_capacity.shorten_tutorial_reading", shorten)
    payload, _, error = await _generate_plan_item_details_parallel(
        **common, existing_checkpoint=checkpoint,
        learner_completed_step_ids=_completed("step_1", "step_2", "step_3"))

    assert error is None and payload.pop("_tutorial_waiting_for_learner") is True
    assert state["built"] == ["step_5"]
    assert shortened == ["step_5"]  # T4 (current) and T1-T3 are never rewritten.
    assert {"step_1", "step_2", "step_3", "step_4"} <= protected_seen[0]
    assert payload["steps"][3] == checkpoint["steps"][3]


@pytest.mark.asyncio
async def test_persistent_capacity_overrun_of_a_window_tutorial_takes_the_retry_path(monkeypatch):
    state, common, validations = _pipeline(monkeypatch)
    checkpoint = await _four_ready_with_learner_on_t4(monkeypatch, state, common, validations)

    def targets(steps, mission_hours, protected, *, pending_count=0):
        if any(step["id"] == "step_5" for step in steps):
            raise ValueError("Mission capacity requires rescheduling or changing exercise scope; protected work is retained")
        return []

    monkeypatch.setattr("app.services.planning.tutorial_capacity.reading_capacity_targets", targets)
    for _attempt in range(2):  # The automatic retry fails the same way.
        payload, _, error = await _generate_plan_item_details_parallel(
            **common, existing_checkpoint=checkpoint,
            learner_completed_step_ids=_completed("step_1", "step_2", "step_3"))
        assert payload.pop("_window_step_failed") == "step_5"
        assert error.startswith("step_5: Tutorial workload correction failed")
        assert _ready(payload) == ["step_1", "step_2", "step_3", "step_4"]  # Nothing else changed.
