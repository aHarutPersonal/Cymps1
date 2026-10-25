import asyncio
import ast
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import (
    LessonPackage, TeachingCase, digest, render_package_results, persist_prepared_workbooks,
)
from app.services.planning.lesson_review import review_lesson
from app.services.practice.contracts import lesson_version
from tests.lesson_package_fixtures import package_payload


def case():
    return TeachingCase(id="cafe", assumptions="All amounts are fictional dollars; expenses are paid immediately.",
        data=[{"id": "receipts", "label": "Cash receipts", "value": 475, "unit": "USD"},
              {"id": "expenses", "label": "Paid expenses", "value": 185, "unit": "USD"}],
        results=[{"id": "cash", "label": "Net cash", "expression": "receipts-expenses", "unit": "USD", "decimal_places": 2}])


def review_payload(**changes):
    return {"acceptable": True, "issues": [], "practice_minutes": 40,
            "contains_calculations": False, "calculations": [], **changes}


@pytest.mark.asyncio
@pytest.mark.parametrize("review", [
    review_payload(),
    review_payload(contains_calculations=True, calculations=[{
        "location": "invented", "expression": "1+1", "claimed_result": 2}]),
    review_payload(contains_calculations=True, calculations=[{
        "location": "case", "source_quote": "4 plus 5 equals 999.", "expression": "999", "claimed_result": 999}]),
    review_payload(contains_calculations=True, calculations=[{
        "location": "case", "source_quote": "4 plus 5 equals 999.", "expression": "9*111", "claimed_result": 999}]),
    review_payload(literal_fact_ids=["n1"]),
])
async def test_saved_and_fabricated_derivation_probes_fail_closed(review):
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=review)))
    errors, _, _ = await review_lesson({"lesson_content": "4 plus 5 equals 999."},
        client_factory=lambda **kw: client, context={})
    assert errors
    assert 1 <= client.generate_json.await_count <= 2


def test_package_computes_results_and_renders_only_known_complete_bindings():
    package = LessonPackage.model_validate(package_payload())
    package.teaching_cases = [case()]
    assert case().computed()["results"][0]["display_value"] == "290.00"
    assert render_package_results({"worked_example": "Net cash is [[result:cafe.cash]] USD."}, package, require_all=False) == {
        "worked_example": "Net cash is 290.00 USD."}
    with pytest.raises(ValueError, match="Every teaching result"):
        render_package_results({"worked_example": "Net cash is 555."}, package)
    with pytest.raises(ValueError, match="Unknown teaching result"):
        render_package_results({"worked_example": "[[result:invented.cash]]"}, package)
    invalid = case().model_dump()
    invalid["results"][0]["expression"] = "290"
    with pytest.raises(ValueError, match="named facts"):
        TeachingCase.model_validate(invalid)


def test_writer_never_receives_private_practice_answers_or_hints():
    package = LessonPackage.model_validate(package_payload())
    public = json.dumps(package.writer_context())
    private = package.review_context()["private_workbook"]
    for activity in private["activities"]:
        assert activity["worked_solution"] not in public
        assert activity["hint"] not in public
    for forbidden in ("correct_choice", '"expression"', '"criteria"', '"tolerance"'):
        assert forbidden not in public


def test_public_teaching_case_cannot_reveal_a_transfer_answer():
    payload = package_payload()
    payload["teaching_cases"] = [case().model_dump()]
    payload["workbook"]["activities"][1]["data"] = [
        {"id": "renamed_receipts", "label": "Receipts", "value": 475, "unit": "USD"},
        {"id": "renamed_expenses", "label": "Expenses", "value": 185, "unit": "USD"}]
    with pytest.raises(ValueError, match="Transfer inputs"):
        LessonPackage.model_validate(payload)


def test_package_identity_preserves_answers_across_jobs_but_not_key_changes():
    step = {"id": "step_1", "lesson_content": "Same approved content"}
    generation = {"job_id": "one", "lesson_package_version": 1,
                  "lesson_validation": {"step_1": {"package_hash": "approved-key"}}}
    item = SimpleNamespace(details_json={"_generation": generation})
    original = lesson_version(item, step)
    generation["job_id"] = "retry"
    assert lesson_version(item, step) == original
    generation["lesson_validation"]["step_1"]["package_hash"] = "changed-key"
    assert lesson_version(item, step) != original


def test_stored_package_approval_survives_normalization_but_rejects_content_or_gate_changes():
    from app.tasks.ingestion import _normalize_plan_item_details
    from app.services.planning.lesson_package import provenance, validation_identity, current_package_approval
    from app.services.llm.schemas import PlanDetailStepOutput
    from tests.test_plan_detail_output_schema import _valid_payload
    payload = _valid_payload(lesson_count=1, material_count=1)
    package = LessonPackage.model_validate(package_payload())
    step = PlanDetailStepOutput.model_validate(payload["steps"][0]).model_dump(mode="json")
    payload["steps"] = [step]
    payload = _normalize_plan_item_details(copy.deepcopy(payload))
    payload["steps"][0]["estimate_minutes"] = payload["steps"][0]["estimateMinutes"]
    payload["_generation"] = {"lesson_package_version": 1, "validation_identity": validation_identity(),
                              "lesson_validation": {"step_1": provenance(step, package)}}
    assert current_package_approval(payload)
    changed = copy.deepcopy(payload)
    changed["steps"][0]["lesson_content"] += " Unreviewed change."
    assert not current_package_approval(changed)
    payload["_generation"]["validation_identity"]["review_version"] = 0
    assert not current_package_approval(payload)


@pytest.mark.asyncio
async def test_prepared_practice_insert_cannot_overwrite_learner_work():
    package = LessonPackage.model_validate(package_payload())
    from app.services.llm.schemas import PlanDetailStepOutput
    from app.services.planning.lesson_package import provenance
    from tests.test_plan_detail_output_schema import _valid_payload
    step = PlanDetailStepOutput.model_validate(_valid_payload()["steps"][0]).model_dump(mode="json")
    item = SimpleNamespace(id="item", details_json={"steps": [step], "_generation": {
        "lesson_package_version": 1, "lesson_validation": {"step_1": provenance(step, package)}}})
    db = SimpleNamespace(execute=AsyncMock())
    await persist_prepared_workbooks(db, item, {"step_1": package}, user_id="learner")
    statement = db.execute.call_args.args[0]
    assert "ON CONFLICT ON CONSTRAINT uq_lesson_practice_version DO NOTHING" in str(statement)
    assert "DO UPDATE" not in str(statement)
    assert "worked_solution" in json.dumps(statement.compile().params["workbook_json"])
    assert "worked_solution" not in json.dumps(item.details_json)


@pytest.mark.parametrize("hours", [3, 4, 6, 8, 12, 60])
def test_required_workload_is_truthful_at_every_capacity(hours):
    from app.tasks.plans import normalize_lesson_durations
    result = normalize_lesson_durations({"steps": [{"lesson_content": "word " * 2400, "practice_minutes": 30}]}, mission_hours=hours)
    assert result["workload"]["required_minutes"] == 42
    assert result["workload"]["unallocated_minutes"] == hours * 60 - 42
    assert result["steps"][0]["estimate_minutes"] == 42
    with pytest.raises(ValueError, match="exceeds"):
        normalize_lesson_durations({"steps": [{"lesson_content": "word " * 2400, "practice_minutes": 250}]}, mission_hours=3)


@pytest.mark.asyncio
async def test_private_worked_solution_is_part_of_numeric_review_coverage():
    package = LessonPackage.model_validate(package_payload())
    package.workbook.activities[0].worked_solution = "The calculation uses 4 plus 5 and equals 999. This is the complete worked solution."
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=review_payload())))
    errors, _, _ = await review_lesson({"lesson_content": "Non-numerical teaching prose"},
        client_factory=lambda **kw: client, context={"lesson_package": package.review_context()})
    assert errors


@pytest.mark.asyncio
async def test_book_fidelity_rejects_unbound_evidence_and_unknown_sources(monkeypatch):
    from app.services.book_fidelity import review_book_fidelity
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data={
        "identity_matches": True, "sufficient_source": True, "coverage_complete": True, "issues": [],
        "claims": [{"kind": "book_specific", "guide_span_id": "b1", "source_span_ids": ["s9999"]}]})))
    module = {"content_markdown": "The book teaches a fabricated technique."}
    missing = await review_book_fidelity(module, source="Catalog description", source_id="book", client_factory=lambda **kw: client)
    assert not missing["passed"]
    client.generate_json.assert_not_awaited()
    unbound = await review_book_fidelity(module, source="Verified source words and supported explanations. " * 80,
                                        source_id="book", client_factory=lambda **kw: client)
    assert not unbound["passed"]
    assert any("anchor" in issue for issue in unbound["issues"])


def test_catalog_shortlist_is_bounded_and_finds_late_matching_skill():
    from app.services.planning.catalog_lessons import shortlist_catalog_candidates
    candidates = [{"module_key": f"generic.{i}", "title": "Unrelated cooking"} for i in range(10000)]
    candidates.append({"module_key": "zz.last", "title": "Cash flow reconciliation"})
    assert shortlist_catalog_candidates("Cash flow reconciliation", candidates) == [candidates[-1]]


def test_release_set_has_six_domains_holdout_and_all_capacity_bands():
    cases = json.loads((Path(__file__).parent / "fixtures/generation_scenarios.json").read_text())
    assert len(cases) == len({c["id"] for c in cases}) == 24
    assert len({c["domain"] for c in cases}) == 6
    assert sum(c["split"] == "holdout" for c in cases) == 6
    assert {c["weekly_hours"] for c in cases} == {3, 4, 6, 8, 12, 60}
    coffee = cases[0]["regression_inputs"]["coffee_cart"]
    inputs = {k: v for event in coffee["events"] for k, v in event.items()}
    assert inputs["cash_sales"] - inputs["paid_rent"] - inputs["paid_grinder"] + inputs["additional_cash_sales"] == coffee["expected_cash"]
    assert inputs["cash_sales"] + inputs["earned_unpaid_catering"] - inputs["paid_rent"] - inputs["beans_consumed_on_account"] + inputs["additional_cash_sales"] == coffee["expected_profit"]
    from app.services.llm.evaluation import summarize_runs, promotion_decision
    rows = [{"scenario_id": c["id"], "accepted": True, "adjudicated": True,
             "quality_score": .95, "usable_ms": 1000, "cost_usd": .1}
            for c in cases for _ in range(3)]
    baseline = summarize_runs(rows, cases)
    candidate = summarize_runs([{**r, "usable_ms": 900} for r in rows], cases)
    assert promotion_decision(candidate, baseline)["promote"]
    broken = copy.deepcopy(rows)
    broken[0].update(critical_defects=["wrong transfer answer"], accepted=False, cost_usd=None)
    failed = summarize_runs(broken, cases)
    assert failed["cost_per_accepted"] is None
    assert not promotion_decision(failed, baseline)["promote"]
    assert not summarize_runs(rows[:-1], cases)["eligible_for_comparison"]


def test_release_comparison_cannot_hide_a_domain_regression():
    from app.services.llm.evaluation import summarize_runs, promotion_decision
    cases = [{"id": "math", "domain": "math"}, {"id": "writing", "domain": "writing"}]
    rows = [{"scenario_id": c["id"], "run_id": i, "accepted": True, "adjudicated": True,
             "quality_score": .8, "usable_ms": 1000, "cost_usd": .1} for c in cases for i in range(3)]
    baseline = summarize_runs(rows, cases)
    candidate = summarize_runs([{**r, "quality_score": .7 if r["scenario_id"] == "math" else 1,
                                 "usable_ms": 500} for r in rows], cases)
    assert not promotion_decision(candidate, baseline)["promote"]
    with pytest.raises(ValueError, match="Duplicate"):
        summarize_runs(rows + [rows[0]], cases)
    with pytest.raises(ValueError, match="Invalid"):
        summarize_runs([{**rows[0], "cost_usd": float("nan")}], cases)


def test_pilot_budget_retains_unknown_usage_and_survives_restart(tmp_path):
    from scripts.pilot_generation import Budget
    path = tmp_path / "usage.jsonl"
    budget = Budget(path, 1)
    request = budget.reserve(.4, {})
    budget.finish(request, None, {})
    budget.reserve(.5, {})
    resumed = Budget(path, 1)
    with pytest.raises(RuntimeError, match="budget exhausted"):
        resumed.reserve(.2, {})
    assert resumed.spent == .4 and sum(resumed.pending.values()) == .5


def test_pilot_budget_counts_concurrent_reservations_and_protects_ledger(tmp_path):
    from scripts.pilot_generation import Budget
    path = tmp_path / "usage.jsonl"
    budget = Budget(path, 1)
    request = budget.reserve(.6, {"id": "bad", "status": "finished", "reserved_usd": 0})
    with pytest.raises(RuntimeError, match="budget exhausted"):
        budget.reserve(.5, {})
    for invalid in (float("nan"), float("inf"), -.01):
        with pytest.raises(ValueError, match="Invalid billed cost"):
            budget.finish(request, invalid, {})
    assert Budget(path, 1).pending[request] == .6
    budget.finish(request, None, {"charged_usd": 0, "usage_unknown": False})
    resumed = Budget(path, 1)
    assert resumed.spent == .6 and not resumed.pending
    with pytest.raises(RuntimeError, match="budget exhausted"):
        resumed.reserve(.5, {})


@pytest.mark.asyncio
async def test_shared_admission_releases_cancelled_inference(monkeypatch):
    from app.core.config import settings
    from app.services.llm.admission import provider_permit, admission_scope, ACQUIRE, RELEASE
    monkeypatch.setattr(settings, "llm_admission_limits", {"test:model": 3})
    redis = SimpleNamespace(eval=AsyncMock(return_value=1), aclose=AsyncMock())
    monkeypatch.setattr("redis.asyncio.Redis.from_url", lambda *a, **kw: redis)
    entered = asyncio.Event()
    async def run():
        with admission_scope("background", "private-user"):
            async with provider_permit("test", "model", timeout=10):
                entered.set()
                await asyncio.Future()
    task = asyncio.create_task(run())
    await entered.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    first = redis.eval.call_args_list[0].args
    assert first[0] == ACQUIRE and first[-3] == "background"
    assert "private-user" not in str(first)
    assert redis.eval.call_args_list[-1].args[0] == RELEASE
    redis.aclose.assert_awaited_once()


@pytest.mark.asyncio
async def test_transport_attempt_identity_survives_semantic_failure(monkeypatch):
    from app.core.config import settings
    from app.services.llm.tracing import traced_operation
    from app.services.llm.telemetry import usage_record_from_response
    from app.services.llm.zai import ZaiLLMClient
    from tests.test_openlux import chunk, transport
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    recorder = AsyncMock(return_value=True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", recorder)
    client = ZaiLLMClient(api_key="test", model="glm-5.3", base_url="https://api.z.ai/api/paas/v4", max_tokens=500)
    _, request = transport(monkeypatch, client, [chunk('{"ok":true}', "stop")])
    @traced_operation("lesson_test")
    async def run():
        return await client.generate_json("S", "U")
    response = await run()
    assert recorder.await_count == 2
    assert recorder.call_args_list[0].kwargs["response"].attempt_id == response.attempt_id
    assert response.effective_parameters["max_tokens"] == request["max_tokens"] == 2548
    assert "messages" not in response.effective_parameters
    response.semantic_accepted, response.critical_defect, response.error = False, True, "Incorrect answer"
    record = usage_record_from_response(operation="lesson_test", response=response)
    assert record.metadata["transport_success"] is True
    assert record.metadata["semantic_accepted"] is False
    assert record.event_id == response.attempt_id


@pytest.mark.asyncio
async def test_canonical_block_repair_preserves_unaffected_content(monkeypatch):
    from app.services.curriculum import generation
    from app.services.curriculum.schemas import BlockRepairResult
    from tests.test_curriculum_pipeline import _draft, _manifest, _plan, _outline, _target
    draft = _draft()
    replacement = draft.blocks[0].model_copy(update={"content_markdown": draft.blocks[0].content_markdown + " Corrected explanation."})
    result = generation.GeneratedArtifact(value=BlockRepairResult(repaired_blocks=[replacement], addressed_issue_codes=["wrong_fact"]),
        model_name="test", provider="test", input_tokens=1, output_tokens=1, total_tokens=2)
    generate = AsyncMock(return_value=result)
    monkeypatch.setattr(generation, "_generate", generate)
    repaired = await generation.repair_module_draft(module_target=_target(), manifest=_manifest(),
        technique_plan=_plan(), outline=_outline(), draft=draft, tier="balanced", repair_attempt=1,
        issues=[{"code": "wrong_fact", "block_id": replacement.block_id}])
    assert repaired.value.blocks[0] == replacement
    assert repaired.value.blocks[1:] == draft.blocks[1:]
    assert repaired.value.session_workbooks == draft.session_workbooks
    assert repaired.value.rubric == draft.rubric
    assert generate.call_args.kwargs["max_tokens"] == 10000


@pytest.mark.asyncio
async def test_parallel_reviews_reuse_only_the_same_draft(monkeypatch):
    from app.core.config import settings
    from app.tasks import curriculum as task
    from app.services.curriculum.generation import GeneratedArtifact
    from app.services.curriculum.schemas import QualityReview
    from tests.test_curriculum_pipeline import _draft, _manifest, _plan, _outline, _target, PipelineStage
    monkeypatch.setattr(settings, "curriculum_parallel_reviews", True)
    calls = []
    async def review(**kwargs):
        calls.append(kwargs["reviewer"])
        return GeneratedArtifact(value=QualityReview(reviewer=kwargs["reviewer"], passed=True, score=1),
            model_name="test", provider="test", input_tokens=1, output_tokens=1, total_tokens=2)
    monkeypatch.setattr(task, "review_module", review)
    checkpoint = {"source_manifest": _manifest().model_dump(mode="json"), "technique_plan": _plan().model_dump(mode="json"),
                  "outline": _outline().model_dump(mode="json"), "draft": _draft().model_dump(mode="json")}
    async def stage(name):
        return await task._run_stage(stage=name, job_input={"module_target": _target()}, checkpoints=checkpoint,
            repair_attempts=0, module_id=None, job_id="parallel-test")
    result = await stage(PipelineStage.FACTUAL_REVIEW)
    checkpoint.update(result.updates)
    assert set(calls) == {"factual", "pedagogy"}
    await stage(PipelineStage.PEDAGOGY_REVIEW)
    assert len(calls) == 2
    checkpoint["draft"]["summary"] += " Changed assumptions."
    await stage(PipelineStage.PEDAGOGY_REVIEW)
    assert len(calls) == 3

@pytest.mark.asyncio
async def test_outline_checkpoint_retains_private_package_without_publishing_unapproved_practice():
    package=LessonPackage.model_validate(package_payload())
    item=SimpleNamespace(id='item',details_json={'steps':[{'id':'step_1','description':'Draft pending'}],
        '_generation':{'lesson_package_version':1,'lesson_validation':{}}})
    db=SimpleNamespace(execute=AsyncMock())
    await persist_prepared_workbooks(db,item,{'step_1':package},user_id='learner')
    db.execute.assert_not_awaited()
