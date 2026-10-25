"""Production-path regressions for bounded recovery and saved drafting work."""
import asyncio
import copy
import json
from collections import Counter
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanDetailSectionsRepairOutput
from app.services.planning.lesson_package import LessonPackage, PrivatePackageRepair, digest
from app.services.planning.package_builder import LessonPackageSeed
from app.services.planning.activity_draft import LessonActivityDraft
from app.services.planning.lesson_review import LessonReview
from app.services.planning.package_preflight import PackageSemanticReview, merge_preflight_states
from app.tasks.plans import (
    PlanDetailDeadlineExceeded, _deadline_client_factory,
    _generate_plan_item_details_parallel,
)
from tests.lesson_package_fixtures import package_payload as legacy_package_payload
from tests.section_client_fixture import activity_draft_fixture, structured_package_fixture
from tests.test_plan_detail_output_schema import _lesson_sections_payload, _outline_payload


def package_payload():
    return structured_package_fixture(legacy_package_payload())


class ScenarioClient:
    model = "synthetic-reliability-test"

    def __init__(self, scenario):
        self.scenario = scenario

    async def generate_json(self, *, output_model, user_prompt, **kwargs):
        case = self.scenario
        name = "LessonReview" if issubclass(output_model, LessonReview) else output_model.__name__
        case.counts[name] += 1
        case.order.append(name)
        attempt = case.counts[name]
        if output_model is LessonPackage:
            data = package_payload()
        elif output_model is LessonPackageSeed:
            package = package_payload()
            data = {"workbook_title": package["workbook"]["title"], "teaching_cases": [],
                    "activity_briefs": [{"id": activity["id"], "kind": activity["kind"],
                        "scope": activity["instructions"]} for activity in package["workbook"]["activities"]]}
        elif output_model is LessonActivityDraft:
            activity_id = json.loads(user_prompt)["activity_brief"]["id"]
            case.activity_counts[activity_id] += 1
            if case.mode == "package_activity_outage" and activity_id == "transfer":
                return LLMResponse(data={}, error="zai request failed (TimeoutError; finish=missing)")
            data = activity_draft_fixture(next(activity for activity in package_payload()["workbook"]["activities"]
                        if activity["id"] == activity_id))
        elif issubclass(output_model, PackageSemanticReview):
            bad = case.mode in {"preflight_repair", "preflight_rejected"} and (
                attempt == 1 or case.mode == "preflight_rejected")
            data = {"acceptable": not bad, "issues": [{"target": "practice.guided",
                "description": "The worked solution contradicts the supplied task criteria; correct its reasoning."}] if bad else []}
        elif output_model is PrivatePackageRepair:
            solution = package_payload()["workbook"]["activities"][0]["worked_solution"]
            for step in solution["steps"]:
                step["explanation"] = "A corrected claim names its conditions, tests the objection against those conditions, and narrows the conclusion using the supplied evidence."
            data = {"solution_patches": [{"activity_id": "guided", "worked_solution": solution}]}
        elif name.startswith("LessonSectionGroup_"):
            if name.endswith("mechanism") and (case.mode.startswith("timeout_") or case.mode == "exhausted"):
                if attempt == 1 or case.mode == "exhausted":
                    return LLMResponse(data={}, error="zai request failed (TimeoutError; finish=missing)")
            source = _lesson_sections_payload()
            data = {field: source[field] for field in output_model.model_fields}
        elif output_model is PlanDetailSectionsRepairOutput:
            data = {"sections": [{"field_name": "core_framework", "content": "corrected mechanism " * 350}]}
        elif issubclass(output_model, LessonReview):
            request = json.loads(user_prompt)
            case.reviewed.append(copy.deepcopy(request["lesson"]))
            if case.mode == "review_unavailable" or (case.mode.endswith("_then_outage") and attempt > 1):
                return LLMResponse(data={}, error="zai request failed (TimeoutError; finish=missing)")
            private_defect = case.mode in {"timeout_package", "timeout_package_then_outage"} and attempt == 1
            prose_defect = case.mode in {"timeout_semantic", "timeout_semantic_then_outage"} and attempt == 1
            data = {"acceptable": not (private_defect or prose_defect),
                    "issues": ["core_framework: the mechanism reverses the stated distinction"] if prose_defect else [],
                    "package_issues": ["guided worked solution contradicts its criteria"] if private_defect else [],
                    "affected_sections": ["core_framework"] if prose_defect else [],
                    "practice_minutes": 40, "contains_calculations": False,
                    "calculations": [], "literal_fact_ids": list(request["numeric_spans"])}
        else:
            raise AssertionError(f"Unexpected paid operation: {name}")
        return LLMResponse(data=data, model=self.model, prompt_tokens=10,
                           completion_tokens=10, finish_reason="stop")


class Scenario:
    def __init__(self, mode):
        self.mode = mode
        self.counts = Counter()
        self.activity_counts = Counter()
        self.order = []
        self.reviewed = []

    def factory(self, **kwargs):
        return ScenarioClient(self)


async def run_scenario(scenario, **kwargs):
    lesson_count = kwargs.pop("lesson_count", 1)
    return await _generate_plan_item_details_parallel(
        system_prompt="Teach accurately.", task_title="Build an argument",
        mission_hours=1 if lesson_count == 1 else 5, user_goal="learn to examine arguments",
        learning_preferences="reading and practice", idol_name="Mentor",
        idol_domain="critical thinking", idol_evidence={}, session_context="",
        active_tier="balanced", routing_reason="reliability_test",
        client_factory=scenario.factory,
        existing_checkpoint={"_generation": {"outline": _outline_payload(lesson_count=lesson_count, material_count=1)}},
        **kwargs,
    )


@pytest.fixture(autouse=True)
def no_live_telemetry(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())


@pytest.mark.asyncio
async def test_section_timeout_does_not_consume_private_package_repair():
    case = Scenario("timeout_package")
    payload, calls, error = await run_scenario(case)
    assert error is None
    assert payload["steps"][0]["lesson_content"]
    assert case.counts["LessonSectionGroup_mechanism"] == 2
    assert all(case.counts["LessonSectionGroup_" + group] == 1 for group in ("framing", "worked", "practice"))
    assert case.counts["PrivatePackageRepair"] == 1
    assert case.counts["LessonReview"] == 2
    assert case.reviewed[0]["lesson_content"] == case.reviewed[1]["lesson_content"]
    assert not any(getattr(response, "effective_parameters", {}).get("synthetic_section_merge") for _, response, *_ in calls)
    assert len([stage for stage, *_ in calls if "_draft_" in stage]) == 5


@pytest.mark.asyncio
async def test_section_timeout_does_not_consume_semantic_repair_or_repeat_good_groups():
    case = Scenario("timeout_semantic")
    payload, calls, error = await run_scenario(case)
    assert error is None and payload["steps"][0]["lesson_content"]
    assert case.counts["PlanDetailSectionsRepairOutput"] == 1
    assert case.counts["LessonReview"] == 2
    assert case.counts["LessonSectionGroup_mechanism"] == 2
    assert sum(case.counts[name] for name in case.counts if name.startswith("LessonSectionGroup_")) == 5
    before, after = [lesson["lesson_content"] for lesson in case.reviewed]
    assert before != after
    assert before.split("## Worked Example", 1)[1] == after.split("## Worked Example", 1)[1]
    assert any(stage.endswith("semantic_review") for stage, *_ in calls)


@pytest.mark.asyncio
async def test_exhausted_section_transport_never_repeats_whole_lesson():
    case = Scenario("exhausted")
    payload, calls, error = await run_scenario(case)
    assert "Section drafting failed" in error
    assert not payload["steps"][0].get("lesson_content")
    assert case.counts["LessonSectionGroup_mechanism"] == 2
    assert case.counts["LessonReview"] == 0
    assert not any("_draft_2_" in stage for stage, *_ in calls)
    assert all(case.counts["LessonSectionGroup_" + group] <= 1 for group in ("framing", "worked", "practice"))


@pytest.mark.asyncio
@pytest.mark.parametrize("mode,accepted", [("preflight_repair", True), ("preflight_rejected", False)])
async def test_private_contract_is_corrected_before_prose(mode, accepted):
    case = Scenario(mode)
    payload, _, error = await run_scenario(case)
    assert bool(error) is not accepted
    assert case.counts["PackageSemanticReview"] == 2
    assert case.counts["PrivatePackageRepair"] == 1
    writer_events = [name for name in case.order if name.startswith("LessonSectionGroup_")]
    assert len(writer_events) == (4 if accepted else 0)
    if accepted:
        assert case.order[:6] == ["LessonPackageSeed", "LessonActivityDraft", "LessonActivityDraft",
                                 "PackageSemanticReview", "PrivatePackageRepair", "PackageSemanticReview"]
        assert case.activity_counts == {"guided": 1, "transfer": 1}
        assert case.counts["LessonReview"] == 1  # Preflight never replaces final review.
    else:
        assert not payload["steps"][0].get("lesson_content")


@pytest.mark.asyncio
async def test_shared_deadline_cancels_request_and_prevents_new_paid_calls():
    cancelled = asyncio.Event()
    started = 0

    class HungClient:
        model = "test"
        async def generate_json(self, **kwargs):
            nonlocal started
            started += 1
            try:
                await asyncio.Event().wait()
            finally:
                cancelled.set()

    factory = _deadline_client_factory(lambda **kw: HungClient(), deadline=asyncio.get_running_loop().time() + .02)
    client = factory(timeout=120)
    result = await client.generate_json()
    assert result.error and "TimeoutError" in result.error
    assert cancelled.is_set()
    assert result.total_tokens is None  # Unknown charges must not be erased.
    with pytest.raises(PlanDetailDeadlineExceeded):
        await client.generate_json()
    with pytest.raises(PlanDetailDeadlineExceeded):
        factory(timeout=120)
    assert started == 1


class MemoryPrivateStore:
    """Only storage is replaced; the actual section writer and gates still run."""
    def __init__(self):
        self.steps = {}
        self.parts = {}

    async def load_package_parts(self, step_id, step_hash):
        return copy.deepcopy(self.parts.get((step_id, step_hash)))

    async def save_package_parts(self, step_id, step_hash, parts, *, expected_seed_hash=None):
        self.parts[(step_id, step_hash)] = copy.deepcopy(parts)
        return True

    async def load_step(self, step_id, step_hash):
        saved = self.steps.get((step_id, step_hash))
        return copy.deepcopy(saved)

    async def save_package(self, step_id, step_hash, package, *, preflight_passed=False,
                           expected_parts_hash=None, expected_package_hash=None):
        key = (step_id, step_hash)
        old = self.steps.get(key, {})
        package_hash = digest(package)
        same = old.get("package_hash") == package_hash
        self.steps[key] = {"package": copy.deepcopy(package), "package_hash": package_hash,
                           "preflight_passed": preflight_passed or (same and old.get("preflight_passed", False)),
                           "sections": old.get("sections", {}) if same else {}}
        if same and "review_state" in old:
            self.steps[key].update(review_state=copy.deepcopy(old["review_state"]),
                                   review_state_hash=old["review_state_hash"])
        self.parts.pop(key, None)
        return True

    async def save_review_state(self, step_id, step_hash, package_hash, state):
        entry = self.steps.get((step_id, step_hash))
        if entry is None or entry["package_hash"] != package_hash or state["package_hash"] != package_hash:
            return False
        try:
            merged = merge_preflight_states(entry.get("review_state"), state)
        except ValueError:
            return False
        entry.update(review_state=copy.deepcopy(merged), review_state_hash=digest(merged))
        return True

    async def clear_review_state(self, step_id, step_hash, package_hash, expected_review_state_hash):
        entry = self.steps.get((step_id, step_hash))
        if (entry is None or entry["package_hash"] != package_hash
                or entry.get("review_state_hash") != expected_review_state_hash):
            return False
        entry.pop("review_state", None)
        entry.pop("review_state_hash", None)
        entry["preflight_passed"] = False
        return True

    async def save_sections(self, step_id, step_hash, package_hash, sections):
        self.steps[(step_id, step_hash)]["sections"] = copy.deepcopy(sections)
        return True

    async def clear_sections(self, step_id, step_hash, package_hash):
        self.steps[(step_id, step_hash)]["sections"] = {}
        return True


@pytest.mark.asyncio
async def test_review_outage_resumes_saved_prose_without_repeating_paid_writing():
    store = MemoryPrivateStore()
    case = Scenario("review_unavailable")
    payload, _, error = await run_scenario(case, private_checkpoint_store=store)
    assert "Content review unavailable" in error
    assert not payload["steps"][0].get("lesson_content")
    saved = next(iter(store.steps.values()))
    assert saved["preflight_passed"] is True
    assert saved["review_state"]["semantic"] == {"acceptable": True, "issues": []}
    assert saved["review_state"]["scopes"] == {}  # This qualitative package has no numeric claims.
    assert saved["review_state_hash"] == digest(saved["review_state"])
    before = copy.deepcopy(case.counts)
    case.mode = "accepted"
    result, calls, error = await run_scenario(case, private_checkpoint_store=store)
    assert error is None and result["steps"][0]["lesson_content"]
    assert case.counts["LessonPackageSeed"] == before["LessonPackageSeed"]
    assert case.counts["LessonActivityDraft"] == before["LessonActivityDraft"]
    assert case.counts["PackageSemanticReview"] == before["PackageSemanticReview"]
    assert all(case.counts[name] == count for name, count in before.items() if name.startswith("LessonSectionGroup_"))
    assert len(calls) == 1 and calls[0][3] == "independent_content_review"


@pytest.mark.asyncio
async def test_qualitative_package_runs_one_whole_semantic_review_before_writer_and_final_review(monkeypatch):
    preflight_usage = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", preflight_usage)
    case = Scenario("accepted")
    payload, calls, error = await run_scenario(case)
    assert error is None and payload["steps"][0]["lesson_content"]
    assert case.order[:4] == ["LessonPackageSeed", "LessonActivityDraft", "LessonActivityDraft",
                              "PackageSemanticReview"]
    assert case.counts["PackageSemanticReview"] == 1 and case.counts["LessonReview"] == 1
    assert len(case.order) == 9  # Seed + two activities + semantic + four sections + final review.
    assert not any("preflight" in stage for stage, *_ in calls)  # Actual preflight calls record their own usage.
    preflight_usage.assert_awaited_once()
    assert preflight_usage.await_args.kwargs["operation"] == "package_preflight_semantic"
    assert preflight_usage.await_args.kwargs["response"].completion_tokens == 10


@pytest.mark.asyncio
async def test_activity_outage_resumes_private_plan_and_completed_activity_without_repeating_either():
    store = MemoryPrivateStore()
    case = Scenario("package_activity_outage")
    payload, calls, error = await run_scenario(case, private_checkpoint_store=store)
    assert error and not payload["steps"][0].get("lesson_content")
    assert len(store.parts) == 1 and not store.steps
    parts = next(iter(store.parts.values()))
    assert parts["version"] == 2
    assert set(parts["activities"]) == {"guided"}
    assert set(parts["seed"]) == {"workbook_title", "teaching_cases", "activity_briefs"}
    assert case.counts["LessonPackageSeed"] == 1
    assert case.counts["LessonActivityDraft"] == 3
    assert case.activity_counts == {"guided": 1, "transfer": 2}
    assert case.counts["PackageSemanticReview"] == 0 and case.counts["LessonReview"] == 0
    assert calls == []  # Component calls are recorded by the builder, never as a synthetic merge.
    case.mode = "accepted"
    result, calls, error = await run_scenario(case, private_checkpoint_store=store)
    assert error is None and result["steps"][0]["lesson_content"]
    assert case.counts["LessonPackageSeed"] == 1 and case.counts["LessonActivityDraft"] == 4
    assert case.activity_counts == {"guided": 1, "transfer": 3}
    assert case.counts["PackageSemanticReview"] == 1 and case.counts["LessonReview"] == 1
    assert not store.parts and len(store.steps) == 1
    assert not any(response.effective_parameters.get("synthetic_local_validation") for _, response, *_ in calls)


@pytest.mark.asyncio
@pytest.mark.parametrize("configured,expected_max", [(False, 4), (True, 2)])
async def test_all_lesson_stages_share_bounded_job_concurrency(monkeypatch, configured, expected_max):
    from app.tasks.plans import settings
    monkeypatch.setattr(settings, "llm_provider", "dummy")
    monkeypatch.setattr(settings, "llm_admission_limits", {"dummy:test": 5} if configured else {})
    monkeypatch.setattr(settings, "llm_admission_per_user", 2)
    case = Scenario("accepted")
    active = maximum = 0

    class ObservedClient(ScenarioClient):
        async def generate_json(self, **kwargs):
            nonlocal active, maximum
            active += 1
            maximum = max(maximum, active)
            try:
                await asyncio.sleep(.005)
                return await super().generate_json(**kwargs)
            finally:
                active -= 1

    case.factory = lambda **kw: ObservedClient(case)
    payload, _, error = await run_scenario(case, lesson_count=3)
    assert error is None and len(payload["steps"]) == 3
    assert maximum == expected_max
    assert active == 0


@pytest.mark.asyncio
async def test_local_queue_deadline_starts_no_extra_provider_requests(monkeypatch):
    from app.tasks.plans import settings
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    started = 0
    active = 0

    class HungClient:
        model = "test"
        async def generate_json(self, **kwargs):
            nonlocal started, active
            started += 1
            active += 1
            try:
                await asyncio.Event().wait()
            finally:
                active -= 1

    factory = _deadline_client_factory(lambda **kw: HungClient(), deadline=asyncio.get_running_loop().time() + .025)
    clients = [factory(timeout=120) for _ in range(6)]
    results = await asyncio.gather(*(client.generate_json() for client in clients), return_exceptions=True)
    assert started == 4 and active == 0
    assert sum(isinstance(result, PlanDetailDeadlineExceeded) for result in results) == 2
    assert sum(client.request_started for client in clients) == 4


@pytest.mark.asyncio
@pytest.mark.parametrize("mode", ["timeout_package_then_outage", "timeout_semantic_then_outage"])
async def test_corrected_draft_survives_reviewer_outage_without_another_writer(mode):
    store = MemoryPrivateStore()
    case = Scenario(mode)
    payload, _, error = await run_scenario(case, private_checkpoint_store=store)
    assert "Content review unavailable" in error
    assert not payload["steps"][0].get("lesson_content")
    saved = next(iter(store.steps.values()))
    if "package" in mode:
        solution = saved["package"]["workbook"]["activities"][0]["worked_solution"]
        assert "corrected claim" in solution["steps"][0]["explanation"]
    else:
        assert saved["sections"]["core_framework"].startswith("corrected mechanism")
    before = copy.deepcopy(case.counts)
    case.mode = "accepted"
    result, _, error = await run_scenario(case, private_checkpoint_store=store)
    assert error is None and result["steps"][0]["lesson_content"]
    assert all(case.counts[name] == count for name, count in before.items() if name.startswith("LessonSectionGroup_"))
    assert case.counts["PrivatePackageRepair"] == before["PrivatePackageRepair"]
    assert case.counts["PlanDetailSectionsRepairOutput"] == before["PlanDetailSectionsRepairOutput"]


@pytest.mark.asyncio
async def test_invalid_saved_group_is_replaced_without_redoing_good_groups():
    store = MemoryPrivateStore()
    case = Scenario("review_unavailable")
    _, _, error = await run_scenario(case, private_checkpoint_store=store)
    assert "Content review unavailable" in error
    next(iter(store.steps.values()))["sections"]["core_framework"] = "Incomplete old section"
    before = copy.deepcopy(case.counts)
    case.mode = "accepted"
    result, _, error = await run_scenario(case, private_checkpoint_store=store)
    assert error is None and result["steps"][0]["lesson_content"]
    assert case.counts["LessonSectionGroup_mechanism"] == before["LessonSectionGroup_mechanism"] + 1
    assert all(case.counts["LessonSectionGroup_" + name] == before["LessonSectionGroup_" + name]
               for name in ("framing", "worked", "practice"))
