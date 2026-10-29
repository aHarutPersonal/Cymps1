"""A rejected lookahead tutorial waits for the next batch instead of failing the job."""
import asyncio
import copy
from types import SimpleNamespace

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanTutorialOutlineOutput
from app.tasks.plans import _generate_plan_item_details_parallel
from tests.test_short_tutorial_pipeline import outline, sections, short_package


def _pipeline(monkeypatch, rejected: set[str]):
    """Offline tutorial pipeline whose package build rejects the ids in ``rejected``."""
    built: list[str] = []

    async def build(step, context, **kwargs):
        built.append(step["id"])
        await asyncio.sleep(0)
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

    monkeypatch.setattr("app.services.planning.package_builder.generate_initial_package", build)
    monkeypatch.setattr("app.services.planning.package_preflight.review_package", preflight)
    monkeypatch.setattr("app.services.planning.lesson_review.review_lesson", review)
    validations: dict = {}
    common = dict(system_prompt="Teach", task_title="Claim sequence", mission_hours=36 / 60,
        user_goal="Reason", learning_preferences="examples", idol_name="Mentor", idol_domain="writing",
        idol_evidence={}, session_context="", active_tier="balanced", routing_reason="test",
        client_factory=lambda **kwargs: Client(), prepared_packages={}, validation_records=validations)
    return built, common, validations


def _ready(payload):
    return [step["id"] for step in payload["steps"] if step.get("lesson_content")]


def _saved(payload, validations):
    return {**payload, "_generation": {"outline": outline(), "outline_contract_version": 3,
                                       "lesson_validation": copy.deepcopy(validations)}}


@pytest.mark.asyncio
async def test_rejected_lookahead_tutorial_continues_and_is_retried_first(monkeypatch):
    rejected = {"step_2"}
    built, common, validations = _pipeline(monkeypatch, rejected)

    first, _, error = await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1")

    assert error is None
    assert first.pop("_tutorial_continuation") is True
    assert _ready(first) == ["step_1", "step_3"]
    rejected.clear()
    second, _, error = await _generate_plan_item_details_parallel(**common, existing_checkpoint=_saved(first, validations))
    assert error is None
    assert built[3] == "step_2"  # The deferred tutorial is the next batch's priority.
    assert _ready(second)[:3] == ["step_1", "step_2", "step_3"]


@pytest.mark.asyncio
async def test_a_tutorial_rejected_again_as_priority_still_stops_the_job(monkeypatch):
    built, common, validations = _pipeline(monkeypatch, {"step_2"})
    first, _, error = await _generate_plan_item_details_parallel(**common, lesson_format="tutorial_v1")
    assert error is None and first.pop("_tutorial_continuation") is True

    second, _, error = await _generate_plan_item_details_parallel(**common, existing_checkpoint=_saved(first, validations))

    assert error and error.startswith("step_2:")
    assert built.count("step_2") == 2  # Bounded: one lookahead attempt, one priority attempt.
    assert _ready(second) == ["step_1", "step_3"]  # Ready tutorials stay readable.
