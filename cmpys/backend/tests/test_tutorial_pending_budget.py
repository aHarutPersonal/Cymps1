"""Remaining mission capacity scopes unpublished tutorials before paid drafting."""
import copy
from types import SimpleNamespace

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanTutorialLessonSectionsOutput
from app.services.planning.lesson_package import digest, provenance
from app.services.planning.tutorial_capacity import TutorialCapacityError, pending_tutorial_allocation
from app.tasks.plans import _generate_plan_item_details_parallel
from tests.test_short_tutorial_pipeline import complete_step, outline, short_package, sections
from tests.test_lesson_review_contract import _review


def ready_sequence(extra_minutes):
    steps = [complete_step(step) for step in outline(20)["steps"][:19]]
    for step in steps[:extra_minutes]:
        step["lesson_content"] += " substantive" * 100
        step.update(reading_minutes=4, estimate_minutes=7)
    return steps


@pytest.mark.parametrize("used_extra,pending,planned,expected", [
    (0, 1, 6, None), (13, 1, 6, 5), (11, 1, 6, None),
])
def test_only_capacity_pressure_constrains_pending_scope(used_extra, pending, planned, expected):
    ready = ready_sequence(used_extra)
    before = copy.deepcopy(ready)
    assert pending_tutorial_allocation(ready, 2, pending_count=pending, planned_minutes=planned) == expected
    assert ready == before
    assert pending_tutorial_allocation([], 2, pending_count=20, planned_minutes=6) is None


def test_reserves_capacity_for_every_concurrent_pending_writer_and_fails_closed():
    ready = ready_sequence(14)
    # Eighteen ready steps consume 122 minutes, leaving five for each writer.
    assert pending_tutorial_allocation(ready[:-1], 2, pending_count=2, planned_minutes=6) == 5
    with pytest.raises(TutorialCapacityError, match="rescheduling"):
        pending_tutorial_allocation(ready, 2, pending_count=1, planned_minutes=6)


@pytest.mark.asyncio
@pytest.mark.parametrize("reviewed_minutes,accepted", [(2, True), (3, False)])
async def test_remaining_budget_reaches_package_writer_review_and_invalidates_oversized_cache(
        monkeypatch, reviewed_minutes, accepted):
    from app.services.planning.lesson_review import LessonReview, ReviewEvidencePatch
    from app.services.planning.lesson_writer import generate_lesson_sections as real_writer

    package = short_package()
    full_outline = outline(20)
    ready = ready_sequence(13)
    before = copy.deepcopy(ready)
    packages = {step["id"]: package for step in ready}
    validations = {step["id"]: provenance(step, package) for step in ready}
    checkpoint = {**full_outline, "steps": [*ready, full_outline["steps"][-1]],
                  "_generation": {"outline": full_outline, "outline_contract_version": 3,
                                  "lesson_validation": copy.deepcopy(validations)}}
    final_step = full_outline["steps"][-1]
    old_hash = digest({"step": final_step, "system": "Teach", "materials": full_outline["materials"],
        "goal": "Reason", "preferences": "examples", "mentor": "Mentor", "domain": "writing",
        "evidence": {}, "context": "", "minutes": 6, "tutorial_workload_policy": "honest_5_to_8_minutes"})
    observed = {"build": [], "preflight": [], "writer": [], "load": []}

    class Store:
        async def load_step(self, step_id, step_hash):
            observed["load"].append((step_id, step_hash))
            # The old six-minute draft must not enter the five-minute pipeline.
            if step_hash == old_hash:
                return {"package": package.model_dump(mode="json"), "preflight_passed": True,
                        "sections": sections()}
            return None
        async def load_package_parts(self, *args): return None
        async def save_package(self, *args, **kwargs): return True
        async def save_sections(self, *args, **kwargs): return True
        async def clear_sections(self, *args, **kwargs): return True

    async def build(step, context, **kwargs):
        observed["build"].append(copy.deepcopy(context))
        assert step["id"] == "step_20"
        assert context["allotted_lesson_minutes"] == 5
        assert context["target_practice_minutes"] == 2
        return package, LLMResponse(data={}), SimpleNamespace(model="offline")

    async def preflight(package, step, context, **kwargs):
        observed["preflight"].append(context["allotted_lesson_minutes"])
        assert context["allotted_lesson_minutes"] == 5
        return [], LLMResponse(data={}), SimpleNamespace(model="offline")

    async def writer(**kwargs):
        observed["writer"].append(kwargs["allotted_lesson_minutes"])
        assert kwargs["allotted_lesson_minutes"] == 5
        return await real_writer(**kwargs)

    class Client:
        model = "offline"
        async def generate_json(self, **kwargs):
            if issubclass(kwargs["output_model"], PlanTutorialLessonSectionsOutput):
                return LLMResponse(data=sections(), finish_reason="stop")
            if kwargs["output_model"].__name__ == ReviewEvidencePatch.__name__:
                return LLMResponse(data={"practice_minutes": reviewed_minutes}, finish_reason="stop")
            assert issubclass(kwargs["output_model"], LessonReview)
            # Real independent-review validation must reject honest work that
            # exceeds capacity; mocked provider acceptance cannot waive it.
            return LLMResponse(data=_review(practice_minutes=reviewed_minutes), finish_reason="stop")

    async def no_shortening(*args, **kwargs):
        raise AssertionError("Already published work must not need shortening")

    async def reject_repair(*args, **kwargs):
        return None, LLMResponse(data={}, error="Offline scope correction unavailable"), SimpleNamespace(model="offline")

    async def learner_on_step_19():
        # One-ahead: step_20 is written only once it enters the learner's window.
        return {f"step_{index}" for index in range(1, 19)}

    monkeypatch.setattr("app.services.planning.package_builder.generate_initial_package", build)
    monkeypatch.setattr("app.services.planning.package_preflight.review_package", preflight)
    monkeypatch.setattr("app.services.planning.lesson_writer.generate_lesson_sections", writer)
    monkeypatch.setattr("app.services.planning.tutorial_capacity.shorten_tutorial_reading", no_shortening)
    monkeypatch.setattr("app.services.planning.lesson_package.generate_package", reject_repair)
    payload, calls, error = await _generate_plan_item_details_parallel(
        system_prompt="Teach", task_title="Claim", mission_hours=2,
        user_goal="Reason", learning_preferences="examples", idol_name="Mentor", idol_domain="writing",
        idol_evidence={}, session_context="", active_tier="balanced", routing_reason="test",
        client_factory=lambda **kwargs: Client(), prepared_packages=packages,
        validation_records=validations, existing_checkpoint=checkpoint,
        private_checkpoint_store=Store(), learner_completed_step_ids=learner_on_step_19)
    assert observed["build"] and observed["preflight"] and observed["writer"]
    assert observed["load"] == [("step_20", observed["load"][0][1])]
    assert observed["load"][0][1] != old_hash
    assert payload["steps"][:19] == before
    assert checkpoint["steps"][:19] == before
    if accepted:
        assert error is None
        assert len(payload["steps"]) == 20
        assert payload["steps"][-1]["estimate_minutes"] == 5
        assert sum(step["estimate_minutes"] for step in payload["steps"]) == 132
    else:
        assert error
        assert "lesson_content" not in payload["steps"][-1]
