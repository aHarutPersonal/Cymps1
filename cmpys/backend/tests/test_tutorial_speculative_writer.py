"""The first tutorial draft overlaps its package preflight, never its approval.

The writer starts once the preflight sends its first request. Its draft is used
only when the preflight approves and every writer input (prompt, public package,
saved sections, tier) is unchanged; otherwise the speculative task is cancelled,
its usage recorded as discarded, and the lesson continues exactly as before.
Nothing speculative is checkpointed before approval.
"""
import asyncio
import copy
from types import SimpleNamespace

import pytest
from pydantic import BaseModel

from app.core.config import settings
from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanTutorialLessonSectionsOutput
from app.services.planning.lesson_package import LessonPackage
from app.tasks.plans import _generate_plan_item_details_parallel
from tests.test_lesson_pipeline_reliability import MemoryPrivateStore
from tests.test_short_tutorial_pipeline import outline, sections, short_package

DRAFT = "parallel_lesson_step_1_draft_1_tutorial_1"
RETRY_DRAFT = "parallel_lesson_step_1_draft_2_tutorial_1"
SPECULATIVE = "parallel_lesson_step_1_speculative_draft_1_tutorial_1"
GUIDANCE = "The outline names four memo sections but asks the learner to label five of them."


class _Probe(BaseModel):
    """Stands in for a preflight provider request."""


def repaired_package():
    raw = short_package().model_dump(mode="json")
    raw["workbook"]["activities"][0]["instructions"] = (
        "Inspect the supplied claim and identify its stated scope in the answer field.")
    return LessonPackage.model_validate(raw)


class Harness:
    def __init__(self, *, verdicts, writer=(), wait_for_writer=False):
        self.verdicts = list(verdicts)
        self.writer = list(writer)
        self.wait_for_writer = wait_for_writer
        self.events = []
        self.writer_prompts = []
        self.writer_packages = []
        self.preflights = 0
        self.overlapped = False
        self.writer_started = asyncio.Event()
        self.preflight_waiting = asyncio.Event()
        self.writer_cancelled = False
        self.review_error = False

    def factory(self, **kwargs):
        harness = self

        class Client:
            model = "offline"

            async def generate_json(self, *, output_model, user_prompt, **options):
                if output_model is _Probe:
                    if harness.wait_for_writer:
                        # Only a writer started during the preflight can release it.
                        await asyncio.wait_for(harness.writer_started.wait(), 5)
                        harness.overlapped = True
                    return LLMResponse(data={}, finish_reason="stop")
                assert issubclass(output_model, PlanTutorialLessonSectionsOutput)
                index = len(harness.writer_prompts)
                harness.writer_prompts.append(user_prompt)
                harness.events.append("write")
                harness.writer_started.set()
                behaviour = harness.writer[index] if index < len(harness.writer) else "ok"
                if behaviour == "hang":
                    try:
                        await asyncio.Event().wait()
                    finally:
                        harness.writer_cancelled = True
                if behaviour == "error":
                    return LLMResponse(data={}, error="provider refused the request", finish_reason="stop")
                if behaviour == "raise":
                    raise RuntimeError("provider exploded")
                return LLMResponse(data=sections(), finish_reason="stop", prompt_tokens=4700, completion_tokens=900)

        return Client()

    async def preflight(self, package, step, context, *, client_factory, existing_review=None, on_review=None):
        self.preflights += 1
        verdict = self.verdicts.pop(0)
        if verdict.get("request", True):
            self.events.append("preflight_start")
            client = client_factory(tier="balanced", timeout=30, max_tokens=100,
                                    thinking_level="low", allow_fallback=False)
            await client.generate_json(system_prompt="preflight", user_prompt="preflight", output_model=_Probe)
        if verdict.get("hang"):
            self.preflight_waiting.set()
            await asyncio.Event().wait()
        if verdict.get("guidance"):
            await on_review({"outline_guidance": verdict["guidance"]})
        self.events.append("preflight_end")
        failures = verdict.get("failures", [])
        targets = verdict.get("targets")
        return failures, LLMResponse(
            data={"acceptable": not failures},
            effective_parameters={"synthetic_local_validation": True,
                                  **({"validated_repair_targets": targets} if targets else {})},
        ), None

    async def build(self, step, context, **kwargs):
        return short_package(), LLMResponse(data={}, effective_parameters={"synthetic_local_validation": True}), None

    async def repair(self, step, context, *, prior_package, defects, **kwargs):
        self.events.append("package_repair")
        return repaired_package(), LLMResponse(data={}), SimpleNamespace(model="offline")

    async def review(self, lesson, **kwargs):
        self.events.append("final_review")
        self.writer_packages.append(kwargs["context"]["lesson_package"])
        if self.review_error:
            return ["Content review unavailable"], LLMResponse(data={}, error="review unavailable"), None
        return [], LLMResponse(data={"practice_minutes": 3}), SimpleNamespace(model="offline")


class RecordingStore(MemoryPrivateStore):
    def __init__(self, harness):
        super().__init__()
        self.harness = harness
        self.section_saves = []

    async def save_sections(self, step_id, step_hash, package_hash, sections):
        self.harness.events.append("save_sections")
        self.section_saves.append(self.steps[(step_id, step_hash)]["preflight_passed"])
        return await super().save_sections(step_id, step_hash, package_hash, sections)

    async def save_review_state(self, step_id, step_hash, package_hash, state):
        self.steps[(step_id, step_hash)].update(review_state=copy.deepcopy(state), review_state_hash="fake")
        return True


@pytest.fixture(autouse=True)
def offline(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    monkeypatch.setattr(settings, "tutorial_speculative_writer", True, raising=False)


async def run(harness, monkeypatch, *, store=None):
    monkeypatch.setattr("app.services.planning.package_builder.generate_initial_package", harness.build)
    monkeypatch.setattr("app.services.planning.package_preflight.review_package", harness.preflight)
    monkeypatch.setattr("app.services.planning.lesson_review.review_lesson", harness.review)
    monkeypatch.setattr("app.tasks.plans.generate_package", harness.repair)
    return await _generate_plan_item_details_parallel(
        system_prompt="Teach", task_title="Claim", mission_hours=0.1,
        user_goal="Reason", learning_preferences="examples", idol_name="Mentor", idol_domain="writing",
        idol_evidence={}, session_context="", active_tier="balanced", routing_reason="test",
        client_factory=harness.factory, prepared_packages={}, validation_records={},
        private_checkpoint_store=store,
        existing_checkpoint={"_generation": {"outline": outline(1), "outline_contract_version": 3}})


def stages(calls):
    return [stage for stage, *_ in calls]


@pytest.mark.asyncio
async def test_approved_preflight_uses_the_overlapping_draft_without_a_second_writer_call(monkeypatch):
    harness = Harness(verdicts=[{}], wait_for_writer=True)
    store = RecordingStore(harness)
    payload, calls, error = await run(harness, monkeypatch, store=store)

    assert error is None and payload["steps"][0]["lesson_content"]
    assert harness.overlapped  # the preflight could only finish after the writer started
    assert harness.events == ["preflight_start", "write", "preflight_end", "save_sections", "final_review"]
    assert len(harness.writer_prompts) == 1
    assert stages(calls) == [DRAFT, "parallel_lesson_step_1_review_1"]
    assert calls[0][3] == "lesson_section_draft" and calls[0][1].semantic_accepted is True
    # Sections are checkpointed only once the package is approved.
    assert store.section_saves == [True]


async def _baseline_after_repair(monkeypatch):
    monkeypatch.setattr(settings, "tutorial_speculative_writer", False)
    harness = Harness(verdicts=[{"failures": ["practice.guided: contradicts its criteria"],
                                 "targets": ["practice.guided"]}, {"request": False}])
    payload, calls, error = await run(harness, monkeypatch)
    monkeypatch.setattr(settings, "tutorial_speculative_writer", True)
    assert error is None
    return payload, calls, harness


@pytest.mark.asyncio
async def test_rejected_preflight_cancels_the_draft_records_it_and_writes_the_repaired_package(monkeypatch):
    baseline, baseline_calls, baseline_harness = await _baseline_after_repair(monkeypatch)
    harness = Harness(verdicts=[{"failures": ["practice.guided: contradicts its criteria"],
                                 "targets": ["practice.guided"]}, {"request": False}],
                      writer=["hang"], wait_for_writer=True)
    store = RecordingStore(harness)
    payload, calls, error = await run(harness, monkeypatch, store=store)

    assert error is None
    assert payload["steps"][0] == baseline["steps"][0]
    assert harness.events == ["preflight_start", "write", "preflight_end", "package_repair",
                              "preflight_end", "write", "save_sections", "final_review"]
    # The cancelled request is recorded as discarded usage, never as the draft.
    (discarded,) = [call for call in calls if call[0] == SPECULATIVE]
    assert discarded[3] == "lesson_section_speculative_discarded"
    assert "cancelled" in discarded[1].error
    assert stages(calls) == [SPECULATIVE] + stages(baseline_calls)
    # The real writer saw the repaired public package.
    assert harness.writer_packages == baseline_harness.writer_packages
    assert store.section_saves == [True]


@pytest.mark.asyncio
async def test_outline_guidance_from_an_approval_discards_the_completed_speculative_draft(monkeypatch):
    harness = Harness(verdicts=[{"guidance": [GUIDANCE]}], wait_for_writer=True)
    store = RecordingStore(harness)
    payload, calls, error = await run(harness, monkeypatch, store=store)

    assert error is None and payload["steps"][0]["lesson_content"]
    assert len(harness.writer_prompts) == 2
    assert GUIDANCE.rstrip(".") not in harness.writer_prompts[0]
    assert GUIDANCE.rstrip(".") in harness.writer_prompts[1]
    assert harness.events == ["preflight_start", "write", "preflight_end", "write", "save_sections", "final_review"]
    assert stages(calls) == [SPECULATIVE, DRAFT, "parallel_lesson_step_1_review_1"]
    assert calls[0][1].error is None and calls[0][1].semantic_accepted is not True
    assert calls[1][1].semantic_accepted is True
    # The discarded draft was never checkpointed.
    assert store.section_saves == [True]


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["error", "raise"])
async def test_failed_speculative_draft_falls_back_to_the_normal_writer_budget(monkeypatch, failure):
    harness = Harness(verdicts=[{}], writer=[failure], wait_for_writer=True)
    store = RecordingStore(harness)
    payload, calls, error = await run(harness, monkeypatch, store=store)

    assert error is None and payload["steps"][0]["lesson_content"]
    assert harness.events == ["preflight_start", "write", "preflight_end", "write", "save_sections", "final_review"]
    assert stages(calls) == [SPECULATIVE, DRAFT, "parallel_lesson_step_1_review_1"]
    assert calls[0][1].error and calls[0][3] == "lesson_section_speculative_discarded"
    assert store.section_saves == [True]


@pytest.mark.asyncio
async def test_failed_speculation_then_failed_writer_ends_as_today(monkeypatch):
    harness = Harness(verdicts=[{}], writer=["error", "error"], wait_for_writer=True)
    _, calls, error = await run(harness, monkeypatch)
    # Today a writer failure ends the lesson; speculation adds no retry and removes none.
    assert error and "Section drafting failed" in error
    assert stages(calls) == [SPECULATIVE, DRAFT]


@pytest.mark.asyncio
async def test_cancelled_lesson_cancels_the_speculative_request(monkeypatch):
    harness = Harness(verdicts=[{"hang": True}], writer=["hang"], wait_for_writer=True)
    store = RecordingStore(harness)
    job = asyncio.create_task(run(harness, monkeypatch, store=store))
    await harness.preflight_waiting.wait()
    assert harness.writer_started.is_set() and not harness.writer_cancelled
    job.cancel()
    with pytest.raises(asyncio.CancelledError):
        await job
    assert harness.writer_cancelled  # no orphan billable request
    assert store.section_saves == []


@pytest.mark.asyncio
async def test_kill_switch_restores_the_sequential_order(monkeypatch):
    monkeypatch.setattr(settings, "tutorial_speculative_writer", False)
    harness = Harness(verdicts=[{}])
    store = RecordingStore(harness)
    payload, calls, error = await run(harness, monkeypatch, store=store)

    assert error is None and payload["steps"][0]["lesson_content"]
    assert harness.events == ["preflight_start", "preflight_end", "write", "save_sections", "final_review"]
    assert stages(calls) == [DRAFT, "parallel_lesson_step_1_review_1"]


@pytest.mark.asyncio
async def test_preflight_without_a_provider_request_never_starts_the_writer(monkeypatch):
    # A local rejection or a saved verdict costs nothing; neither may speculation.
    harness = Harness(verdicts=[{"request": False}])
    payload, calls, error = await run(harness, monkeypatch)
    assert error is None and payload["steps"][0]["lesson_content"]
    assert harness.events == ["preflight_end", "write", "final_review"]
    assert stages(calls) == [DRAFT, "parallel_lesson_step_1_review_1"]


async def _resume_after_review_outage(monkeypatch, *, speculative):
    monkeypatch.setattr(settings, "tutorial_speculative_writer", speculative)
    harness = Harness(verdicts=[{}], wait_for_writer=speculative)
    harness.review_error = True
    store = RecordingStore(harness)
    _, _, error = await run(harness, monkeypatch, store=store)
    assert error and len(harness.writer_prompts) == 1
    assert store.section_saves == [True]

    harness.review_error = False
    harness.events.clear()
    payload, calls, error = await run(harness, monkeypatch, store=store)
    assert error is None and payload["steps"][0]["lesson_content"]
    return harness, calls


@pytest.mark.asyncio
async def test_resumed_job_with_an_approved_package_and_saved_sections_does_not_speculate(monkeypatch):
    harness, calls = await _resume_after_review_outage(monkeypatch, speculative=True)
    baseline, baseline_calls = await _resume_after_review_outage(monkeypatch, speculative=False)
    # The approved package skips the preflight; the saved sections are reused.
    assert harness.preflights == 1 and len(harness.writer_prompts) == 1
    assert "write" not in harness.events and "preflight_start" not in harness.events
    assert harness.events == baseline.events
    assert stages(calls) == stages(baseline_calls) and SPECULATIVE not in stages(calls)


@pytest.mark.asyncio
async def test_no_speculation_when_the_job_cannot_also_fit_the_preflight(monkeypatch):
    # Per-user admission (2) leaves no room beside the preflight's two requests.
    monkeypatch.setattr(settings, "llm_admission_limits", {settings.llm_provider + ":model": 3})
    harness = Harness(verdicts=[{}])
    payload, calls, error = await run(harness, monkeypatch)
    assert error is None and payload["steps"][0]["lesson_content"]
    assert harness.events == ["preflight_start", "preflight_end", "write", "final_review"]
    assert stages(calls) == [DRAFT, "parallel_lesson_step_1_review_1"]
