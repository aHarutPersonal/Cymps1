"""An unavailable reviewer cannot turn saved lessons into new writing work."""
import copy
import json
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_review import LessonReview
from app.tasks.plans import _generate_plan_item_details_parallel
from tests.test_lesson_pipeline_reliability import MemoryPrivateStore, Scenario, ScenarioClient, run_scenario
from tests.test_plan_detail_output_schema import _outline_payload


async def resume(scenario, checkpoint, packages, store, validations):
    return await _generate_plan_item_details_parallel(
        system_prompt="Teach accurately.", task_title="Build an argument", mission_hours=1,
        user_goal="learn to examine arguments", learning_preferences="reading and practice",
        idol_name="Mentor", idol_domain="critical thinking", idol_evidence={}, session_context="",
        active_tier="balanced", routing_reason="reliability_test", client_factory=scenario.factory,
        existing_checkpoint=checkpoint, prepared_packages=packages,
        private_checkpoint_store=store, validation_records=validations,
    )


class UnavailableScenario(Scenario):
    def __init__(self, error):
        super().__init__("review_unavailable")
        self.error = error

    def factory(self, **kwargs):
        scenario = self

        class Client(ScenarioClient):
            async def generate_json(self, *, output_model, user_prompt, **options):
                if issubclass(output_model, LessonReview):
                    scenario.counts["LessonReview"] += 1
                    scenario.order.append("LessonReview")
                    scenario.reviewed.append(copy.deepcopy(json.loads(user_prompt)["lesson"]))
                    return LLMResponse(data={}, error=scenario.error,
                        attempt_id=f"unavailable-{scenario.counts['LessonReview']}",
                        model=self.model, prompt_tokens=17, completion_tokens=9)
                return await super().generate_json(output_model=output_model,
                    user_prompt=user_prompt, **options)

        return Client(self)


@pytest.mark.asyncio
@pytest.mark.parametrize("error,attempts", [
    ("zai request failed (TimeoutError; finish=missing)", 2),
    ("zai request failed (JSONProtocolError; finish=stop)", 2),
    ("GenerationUnavailable: provider credits exhausted", 1),
])
async def test_saved_lesson_review_outage_preserves_work_and_stops_before_rewriting(monkeypatch, error, attempts):
    telemetry = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    store = MemoryPrivateStore()
    packages, original_validations = {}, {}
    accepted, _, setup_error = await run_scenario(Scenario("accepted"),
        prepared_packages=packages, validation_records=original_validations,
        private_checkpoint_store=store)
    assert setup_error is None and accepted["steps"][0]["lesson_content"]
    checkpoint = {**accepted, "_generation": {
        "outline": _outline_payload(lesson_count=1, material_count=1),
        "lesson_validation": {"step_1": {**original_validations["step_1"], "review_version": 0}},
    }}
    checkpoint_before = copy.deepcopy(checkpoint)
    packages_before = {key: package.model_dump(mode="json") for key, package in packages.items()}
    saved_before = copy.deepcopy(store.steps)
    assert saved_before and all(saved["sections"] for saved in saved_before.values())
    store.clear_sections = AsyncMock(wraps=store.clear_sections)
    store.save_sections = AsyncMock(wraps=store.save_sections)
    telemetry.reset_mock()
    unavailable = UnavailableScenario(error)
    new_validations = {}

    result, calls, failure = await resume(unavailable, checkpoint, packages, store, new_validations)

    assert failure and "Content review unavailable" in failure
    assert not result["steps"][0].get("lesson_content")
    assert unavailable.counts == {"LessonReview": attempts}
    assert unavailable.order == ["LessonReview"] * attempts
    assert all(lesson["lesson_content"] == accepted["steps"][0]["lesson_content"]
               for lesson in unavailable.reviewed)
    assert len(calls) == 1 and calls[0][0] == "parallel_lesson_step_1_revalidation"
    assert calls[0][1].attempt_id == f"unavailable-{attempts}"
    assert calls[0][1].prompt_tokens == 17 and calls[0][1].completion_tokens == 9
    assert telemetry.await_count == attempts - 1  # The first retry is recorded inside review_lesson.
    if attempts == 2:
        assert telemetry.await_args.kwargs["response"].attempt_id == "unavailable-1"
    assert new_validations == {}
    assert checkpoint == checkpoint_before
    assert {key: package.model_dump(mode="json") for key, package in packages.items()} == packages_before
    assert store.steps == saved_before
    store.clear_sections.assert_not_awaited()
    store.save_sections.assert_not_awaited()

    # An operational retry can approve the exact saved lesson without any
    # package construction, private correction, or section-writing request.
    available = Scenario("accepted")
    recovered, recovery_calls, failure = await resume(
        available, checkpoint, packages, store, new_validations)
    assert failure is None
    assert recovered["steps"][0]["lesson_content"] == accepted["steps"][0]["lesson_content"]
    assert available.counts == {"LessonReview": 1}
    assert len(recovery_calls) == 1 and "revalidation" in recovery_calls[0][0]
    assert "step_1" in new_validations
    assert store.steps == saved_before and checkpoint == checkpoint_before
