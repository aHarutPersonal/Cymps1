"""Real task/preflight/store integration with synthetic provider responses only."""
import copy
import json
from collections import Counter
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanItemDetailsOutlineOutput
from app.services.planning.lesson_package import LessonPackage, digest
from app.services.planning.lesson_review import LessonReview, ReviewEvidencePatch
from app.services.planning.package_preflight import PackageSemanticReview
from tests.test_lesson_pipeline_reliability import Scenario, ScenarioClient, run_scenario
from tests.test_package_preflight_patch import package_with_spans
from tests.test_plan_detail_output_schema import _outline_payload
from tests.test_private_generation_checkpoint import Database


def quantitative_package():
    payload = package_with_spans("Receipts exceed revenue by 20.").model_dump(mode="json")
    transfer = payload["workbook"]["activities"][1]
    transfer["data"] = [{"id": "receipts", "label": "Receipts", "value": 160},
                        {"id": "revenue", "label": "Revenue", "value": 135}]
    transfer["worked_solution"] = (
        "Receipts exceed revenue by 25. Explain how the supplied inputs support this interpretation."
    )
    return LessonPackage.model_validate(payload)


def task_step_hash():
    outline = PlanItemDetailsOutlineOutput.model_validate(
        _outline_payload(lesson_count=1, material_count=1),
    ).model_dump(mode="json")
    return digest({
        "step": outline["steps"][0], "system": "Teach accurately.",
        "materials": outline["materials"], "goal": "learn to examine arguments",
        "preferences": "reading and practice", "mentor": "Mentor",
        "domain": "critical thinking", "evidence": {}, "context": "", "minutes": 60,
    })


def calculations(request):
    result = []
    for claim_id, span in request["numeric_spans"].items():
        if "Receipts exceed revenue by" not in span:
            continue
        owner = "guided" if "20" in span else "transfer"
        result.append({"claim_ids": [claim_id], "case_id": "practice." + owner,
                       "expression": "receipts - revenue", "claimed_result": 20 if owner == "guided" else 25})
    return result


class ResumeScenario(Scenario):
    def __init__(self):
        super().__init__("accepted")
        self.evidence_calls = Counter()
        self.transfer_unavailable = True

    def factory(self, **kwargs):
        scenario = self

        class Client(ScenarioClient):
            async def generate_json(self, *, output_model, user_prompt, **options):
                if issubclass(output_model, ReviewEvidencePatch):
                    request = json.loads(user_prompt)
                    owners = set(request["numeric_span_owners"].values())
                    assert len(owners) == 1
                    owner = next(iter(owners)).removeprefix("practice.")
                    scenario.evidence_calls[owner] += 1
                    if owner == "transfer" and scenario.transfer_unavailable:
                        return LLMResponse(data={}, error="Synthetic evidence provider unavailable", retryable=False)
                    return LLMResponse(data={"calculations": calculations(request)}, finish_reason="stop")
                response = await super().generate_json(
                    output_model=output_model, user_prompt=user_prompt, **options,
                )
                if issubclass(output_model, LessonReview) and not response.error:
                    request = json.loads(user_prompt)
                    proofs = calculations(request)
                    covered = {key for proof in proofs for key in proof["claim_ids"]}
                    response.data.update(contains_calculations=True, calculations=proofs,
                                         literal_fact_ids=[key for key in request["numeric_spans"] if key not in covered])
                return response

        return Client(self)


@pytest.mark.asyncio
async def test_task_resume_reuses_semantic_and_successful_activity_scope_without_duplicate_usage(monkeypatch):
    telemetry = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    db = Database()
    first = db.new_job()
    store = db.store(first)
    package = quantitative_package()
    step_hash = task_step_hash()
    assert await store.save_package("step_1", step_hash, package.model_dump(mode="json"))
    scenario = ResumeScenario()

    result, calls, error = await run_scenario(scenario, private_checkpoint_store=store)

    assert error and not result["steps"][0].get("lesson_content")
    saved = await store.load_step("step_1", step_hash)
    assert saved["preflight_passed"] is False
    assert saved["review_state"]["semantic"] == {"acceptable": True, "issues": []}
    assert set(saved["review_state"]["scopes"]) == {"guided"}
    assert saved["review_state"]["rejection"] is None
    assert scenario.evidence_calls == {"guided": 1, "transfer": 1}
    assert scenario.counts["PackageSemanticReview"] == 1
    assert calls == []  # Real preflight calls record usage inside the coordinator.
    guided_evidence = copy.deepcopy(saved["review_state"]["scopes"]["guided"])
    first.status = "failed"
    successor = db.new_job()
    resumed_store = db.store(successor)
    scenario.transfer_unavailable = False

    result, calls, error = await run_scenario(scenario, private_checkpoint_store=resumed_store)

    assert error is None and result["steps"][0]["lesson_content"]
    assert scenario.counts["PackageSemanticReview"] == 1
    assert scenario.evidence_calls == {"guided": 1, "transfer": 2}
    assert not scenario.counts["LessonPackageSeed"] and not scenario.counts["LessonActivityDraft"]
    saved = await resumed_store.load_step("step_1", step_hash)
    assert saved["preflight_passed"] is True
    assert saved["review_state"]["scopes"]["guided"] == guided_evidence
    assert set(saved["review_state"]["scopes"]) == {"guided", "transfer"}
    assert not any("package_preflight" in stage for stage, *_ in calls)
    assert successor.result_json == {"ready_lesson_count": 0}


@pytest.mark.asyncio
@pytest.mark.parametrize("outage_stage", ["evidence", "final_review"])
async def test_repaired_package_timing_history_survives_outage_and_resume(monkeypatch, outage_stage):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock(return_value=True))
    semantic_contexts = []
    final_contexts = []
    repair_calls = []

    class TimingScenario(ResumeScenario):
        def factory(self, **kwargs):
            client = super().factory(**kwargs)
            generate = client.generate_json

            async def generate_json(*, output_model, user_prompt, **options):
                if issubclass(output_model, PackageSemanticReview):
                    request = json.loads(user_prompt)
                    semantic_contexts.append(copy.deepcopy(request["context"]))
                    if len(semantic_contexts) == 1:
                        return LLMResponse(data={"acceptable": False, "issues": [{
                            "target": "practice.guided", "description":
                            "The activity estimate needs a substantive workload review before approval.",
                        }]}, finish_reason="stop")
                if issubclass(output_model, LessonReview):
                    request = json.loads(user_prompt)
                    final_contexts.append(copy.deepcopy(request["context"]))
                return await generate(output_model=output_model, user_prompt=user_prompt, **options)

            client.generate_json = generate_json
            return client

    async def repair(step, context, *, prior_package, **kwargs):
        repair_calls.append(True)
        payload = prior_package.model_dump(mode="json")
        activity = payload["workbook"]["activities"][0]
        activity["minutes_min"] += 2
        activity["minutes_max"] += 2
        repaired = LessonPackage.model_validate(payload)
        return repaired, LLMResponse(data=repaired.model_dump(mode="json")), None

    monkeypatch.setattr("app.tasks.plans.generate_package", repair)
    db = Database()
    first = db.new_job()
    store = db.store(first)
    package = quantitative_package()
    step_hash = task_step_hash()
    assert await store.save_package("step_1", step_hash, package.model_dump(mode="json"))
    scenario = TimingScenario()
    scenario.transfer_unavailable = outage_stage == "evidence"
    scenario.mode = "review_unavailable" if outage_stage == "final_review" else "accepted"

    result, _, error = await run_scenario(scenario, private_checkpoint_store=store)

    assert error and not result["steps"][0].get("lesson_content")
    assert len(semantic_contexts) == 2 and repair_calls == [True]
    changes = semantic_contexts[-1]["activity_timing_changes"]
    assert changes[0]["unchanged_task"] is True
    saved = await store.load_step("step_1", step_hash)
    assert saved["review_state"]["activity_timing_changes"] == changes
    assert saved["preflight_passed"] is (outage_stage == "final_review")
    first.status = "failed"
    successor = db.new_job()
    scenario.transfer_unavailable = False
    scenario.mode = "accepted"

    result, _, error = await run_scenario(scenario, private_checkpoint_store=db.store(successor))

    assert error is None and result["steps"][0]["lesson_content"]
    assert len(semantic_contexts) == 2 and repair_calls == [True]
    assert final_contexts[-1]["activity_timing_changes"] == changes
