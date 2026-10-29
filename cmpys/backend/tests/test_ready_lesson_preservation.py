"""Previously approved lessons cannot disappear during replacement generation."""
import asyncio
import copy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from app.models.plan import PlanItemStatus
from app.services.llm.client import LLMResponse
from app.services.llm.schemas import PlanDetailStepOutput
from app.services.planning.lesson_package import LessonPackage, digest, provenance
from app.services.planning.lesson_review import LessonReview
from app.tasks import plans
from tests.lesson_package_fixtures import package_payload
from tests.test_plan_detail_output_schema import _outline_payload, _valid_payload
from tests.test_previous_release_read_compatibility import PRODUCTION_V7_IDENTITY


def ready_prior_artifact():
    details = _valid_payload(lesson_count=3, material_count=1)
    package = LessonPackage.model_validate(package_payload())
    approvals = {}
    for step in details["steps"]:
        canonical = PlanDetailStepOutput.model_validate(step).model_dump(mode="json")
        step.clear(); step.update(canonical)
        if step["id"] == "step_2":
            step.pop("lesson_content")
        else:
            approvals[step["id"]] = {**PRODUCTION_V7_IDENTITY,
                "content_hash": digest(canonical),
                "package_hash": digest(package.model_dump(mode="json"))}
    details["_generation"] = {
        "job_id": "1ad07768-c897-4495-a780-7485fefb5423", "status": "partial",
        "lesson_package_version": 1, "ready_step_ids": ["step_1", "step_3"],
        "validation_identity": copy.deepcopy(PRODUCTION_V7_IDENTITY),
        "lesson_validation": approvals,
        "outline": _outline_payload(lesson_count=3, material_count=1),
    }
    return details, package


def locked_artifact(monkeypatch):
    details, package = ready_prior_artifact()
    item = SimpleNamespace(id="item", details_json=details,
                           status=PlanItemStatus.COMPLETED, progress_percent=100)
    job = SimpleNamespace(id="b07bac93-a2e1-4740-9e1e-32e70e0f55fa", status="running",
                          supersedes_artifact=False, result_json={})
    plan = SimpleNamespace(id="plan", completed_at="existing completion")
    monkeypatch.setattr(plans, "_lock_current_detail_artifact_publication",
                        AsyncMock(return_value=(plan, item, job)))
    return plan, item, job, package


@pytest.mark.parametrize("mutation", [
    "steps_not_array", "step_not_mapping", "materials_not_array",
    "generation_not_mapping", "identity_not_mapping", "approvals_not_mapping",
    "step_approval_not_mapping", "step_approval_missing",
])
def test_malformed_predecessor_is_rejected_before_approval_hashing(mutation):
    details, _ = ready_prior_artifact()
    if mutation == "steps_not_array":
        details["steps"] = "malformed"
    elif mutation == "step_not_mapping":
        details["steps"][0] = None
    elif mutation == "materials_not_array":
        details["materials"] = {"title": "malformed"}
    elif mutation == "generation_not_mapping":
        details["_generation"] = ["malformed"]
    elif mutation == "identity_not_mapping":
        details["_generation"]["validation_identity"] = ["malformed"]
    elif mutation == "approvals_not_mapping":
        details["_generation"]["lesson_validation"] = ["malformed"]
    elif mutation == "step_approval_not_mapping":
        details["_generation"]["lesson_validation"]["step_1"] = None
    else:
        del details["_generation"]["lesson_validation"]["step_1"]
    original = copy.deepcopy(details)
    assert plans._approved_readable_step_ids(details) == frozenset()
    assert details == original


async def claim(item, job, approved):
    return await plans._prepare_current_detail_artifact_publication(
        AsyncMock(), plan_id="plan", item_id="item", user_id="owner", job_id=str(job.id),
        candidate_approved_step_ids=approved,
    )


@pytest.mark.asyncio
@pytest.mark.parametrize("approved", [frozenset(), frozenset({"step_1"}), frozenset({"step_2"})])
async def test_outline_and_incomplete_replacements_never_reset_existing_ready_artifact(monkeypatch, approved):
    plan, item, job, _ = locked_artifact(monkeypatch)
    before = copy.deepcopy(item.details_json)
    with pytest.raises(plans.DetailArtifactPublicationDeferred) as error:
        await claim(item, job, approved)
    assert error.value.ready_step_ids == {"step_1", "step_3"}
    assert item.details_json == before
    assert item.status == PlanItemStatus.COMPLETED and item.progress_percent == 100
    assert plan.completed_at == "existing completion"
    assert not job.supersedes_artifact


@pytest.mark.asyncio
async def test_candidate_requires_current_exact_approval_for_every_previously_ready_id(monkeypatch):
    _, item, job, package = locked_artifact(monkeypatch)
    payload = copy.deepcopy(item.details_json)
    packages = {"step_1": package, "step_3": package}
    # Merely retaining old prose or changing its declared version is not approval.
    old_approvals = payload["_generation"]["lesson_validation"]
    assert plans._approved_candidate_step_ids(payload, packages, old_approvals) == frozenset()
    approvals = {step["id"]: provenance(step, package) for step in payload["steps"] if step["id"] in packages}
    payload["steps"][2]["lesson_content"] += " Unapproved mutation."
    approved = plans._approved_candidate_step_ids(payload, packages, approvals)
    assert approved == {"step_1"}
    with pytest.raises(plans.DetailArtifactPublicationDeferred):
        await claim(item, job, approved)


@pytest.mark.asyncio
async def test_complete_new_approval_coverage_can_replace_prior_artifact(monkeypatch):
    _, item, job, package = locked_artifact(monkeypatch)
    payload = copy.deepcopy(item.details_json)
    packages = {"step_1": package, "step_3": package}
    approvals = {step["id"]: provenance(step, package) for step in payload["steps"] if step["id"] in packages}
    approved = plans._approved_candidate_step_ids(payload, packages, approvals)
    assert approved == {"step_1", "step_3"}
    _, _, _, changed, supersedes = await claim(item, job, approved)
    assert changed and supersedes
    # Existing artifact-transition semantics apply only after complete coverage.
    assert item.status == PlanItemStatus.NOT_STARTED and item.progress_percent == 0


@pytest.mark.asyncio
@pytest.mark.parametrize("cancel", [False, True])
async def test_failed_or_cancelled_generation_keeps_prior_public_lessons(monkeypatch, cancel):
    _, item, job, package = locked_artifact(monkeypatch)
    original = copy.deepcopy(item.details_json)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    outline_seen = asyncio.Event()
    records = {}

    class UnavailableClient:
        model = "synthetic"
        async def generate_json(self, *, output_model, **kwargs):
            if cancel and output_model is LessonReview:
                await asyncio.Event().wait()
            return LLMResponse(data={}, error="zai request failed (GenerationUnavailable; provider unavailable)")

    async def checkpoint(payload, stage):
        approved = plans._approved_candidate_step_ids(payload, {"step_1": package, "step_3": package}, records)
        with pytest.raises(plans.DetailArtifactPublicationDeferred):
            await claim(item, job, approved)
        outline_seen.set()

    task = asyncio.create_task(plans._generate_plan_item_details_parallel(
        system_prompt="Teach accurately", task_title="Learn a validated skill",
        mission_hours=5, user_goal="Practice the skill", learning_preferences="",
        idol_name="Mentor", idol_domain="science", idol_evidence={}, session_context="",
        active_tier="balanced", routing_reason="test",
        client_factory=lambda **kw: UnavailableClient(),
        existing_checkpoint=copy.deepcopy(original),
        prepared_packages={"step_1": package, "step_3": package}, validation_records=records,
        on_checkpoint=checkpoint,
    ))
    await asyncio.wait_for(outline_seen.wait(), timeout=2)
    if cancel:
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await asyncio.wait_for(task, timeout=.5)
    else:
        _, _, error = await task
        assert error
    assert item.details_json == original
    assert item.status == PlanItemStatus.COMPLETED and item.progress_percent == 100
    assert not job.supersedes_artifact
    assert plans._approved_readable_step_ids(item.details_json) == {"step_1", "step_3"}


@pytest.mark.asyncio
async def test_final_deferred_successor_preserves_input_metadata_and_paid_usage(monkeypatch):
    plan, item, job, _ = locked_artifact(monkeypatch)
    original = copy.deepcopy(item.details_json)
    plan.id = str(uuid4())
    plan.idol = None
    plan.roadmap_json = {}
    item.id = str(uuid4())
    item.plan = plan
    item.title = "Practice a validated skill"
    item.description = "Work through one example"
    item.type = SimpleNamespace(value="project")
    item.estimated_hours = 5
    item.success_metric = "Explain the result"
    job.plan_item = item
    job.user_id = str(uuid4())
    job.created_at = datetime.now(timezone.utc)
    job.result_json = {"provider_call_count": 6, "unknown_usage_count": 1}
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        SimpleNamespace(rowcount=1),
        SimpleNamespace(scalar_one_or_none=lambda: job),
        SimpleNamespace(scalar_one_or_none=lambda: None),
        SimpleNamespace(rowcount=1),
    ]
    context = AsyncMock()
    context.__aenter__.return_value = db
    monkeypatch.setattr(plans, "async_session_maker", lambda: context)
    monkeypatch.setattr(plans.settings, "lesson_catalog_first_enabled", False)
    monkeypatch.setattr(plans, "_load_session_context", AsyncMock(return_value={}))
    monkeypatch.setattr(plans, "_resolve_plan_detail_materials", AsyncMock(return_value=[]))
    monkeypatch.setattr("app.services.llm.routing.choose_llm_tier", AsyncMock(
        return_value=SimpleNamespace(tier="balanced", reason="test")))
    usage = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_usage_records", usage)
    paid_response = LLMResponse(data={}, prompt_tokens=23, completion_tokens=11)
    paid_calls = [("parallel_lesson_step_1_draft_1_framing_attempt_1", paid_response,
                   "balanced", "lesson_section_draft", "synthetic")]

    async def incomplete_candidate(**kwargs):
        payload = _valid_payload(lesson_count=1, material_count=1)
        await kwargs["on_checkpoint"](payload, "lesson_ready")
        return payload, paid_calls, None

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", incomplete_candidate)
    result = await plans._regenerate_plan_item_details_async(str(job.id))
    assert result["reason"] == "existing_lessons_preserved"
    assert plans._load_session_context.await_args.kwargs["exclude_practice_plan_item_id"] == str(item.id)
    assert item.details_json == original
    assert item.status == PlanItemStatus.COMPLETED and item.progress_percent == 100
    final_statement = db.execute.call_args.args[0]
    metadata = final_statement.compile().params["result_json"]
    assert len(metadata["input_hash"]) == 64
    assert metadata["input_hash"] == job.result_json["input_hash"]
    assert metadata["provider_call_count"] == 6
    assert metadata["unknown_usage_count"] == 1
    assert metadata["candidate_ready_step_ids"] == ["step_1"]
    assert metadata["preserved_ready_step_ids"] == ["step_1", "step_3"]
    assert metadata["total_lesson_count"] == 1
    assert final_statement.compile().params["status"] == "failed"
    usage.assert_awaited_once()
    records = usage.call_args.args[0]
    assert len(records) == 1
    assert records[0].prompt_tokens == 23 and records[0].completion_tokens == 11
    assert records[0].metadata["plan_item_id"] == str(item.id)


def prior_artifact_for_read(*, full_ready=False):
    from app.models.plan import PlanItemType
    from tests.test_plan_progression_regressions import _item

    details, package = ready_prior_artifact()
    if full_ready:
        step = copy.deepcopy(details["steps"][0])
        step["id"] = "step_2"
        details["steps"][1] = step
        details["_generation"]["lesson_validation"]["step_2"] = {
            **PRODUCTION_V7_IDENTITY,
            "content_hash": digest(step),
            "package_hash": digest(package.model_dump(mode="json")),
        }
        details["_generation"]["status"] = "ready"
        details["_generation"]["ready_step_ids"] = ["step_1", "step_2", "step_3"]
    item = _item(str(uuid4()), PlanItemType.PROJECT, 1)
    item.details_json = details
    return item


@pytest.mark.asyncio
@pytest.mark.parametrize("latest_status", ["pending", "queued", "running", "failed", "cancelled"])
@pytest.mark.parametrize("full_ready", [False, True])
async def test_detailed_read_retains_owned_approved_artifact_during_or_after_replacement(
    monkeypatch, latest_status, full_ready,
):
    from app.api.v1 import plans as api
    from app.schemas.plan import DetailsStatus, ItemProgress
    from tests.test_plan_progression_regressions import _Result

    item = prior_artifact_for_read(full_ready=full_ready)
    original = copy.deepcopy(item.details_json)
    artifact_id = original["_generation"]["job_id"]
    now = datetime.now(timezone.utc)
    successor = SimpleNamespace(id=str(uuid4()), status=latest_status,
                                step="generating_lessons", progress_percent=70,
                                error_message=None, created_at=now, updated_at=now)
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.return_value = artifact_id
    results = [_Result(scalars=["step_1"])]
    if full_ready:
        results.append(_Result(scalar_one=successor))  # Runtime readiness lookup.
    results.append(_Result(scalar_one=successor))  # Retained-read/job-status lookup.
    db.execute.side_effect = results
    monkeypatch.setattr(api, "_get_item_for_user", AsyncMock(return_value=item))
    monkeypatch.setattr(api, "_compute_item_progress", AsyncMock(return_value=(
        ItemProgress(completed_steps=1, total_steps=3, percent=33.3), False,
    )))
    owner = str(uuid4())
    response = await api.get_plan_item_detailed(item.id, db, SimpleNamespace(id=owner))

    assert response.details_status == (DetailsStatus.AVAILABLE if full_ready else DetailsStatus.PARTIAL)
    assert response.details.steps[0].lesson_content == original["steps"][0]["lesson_content"]
    assert response.details.steps[2].lesson_content == original["steps"][2]["lesson_content"]
    assert response.artifact_job_id == artifact_id
    if not full_ready or latest_status in {"pending", "queued", "running"}:
        assert response.job_id == successor.id
    assert response.progress.percent == 33.3
    assert response.completed_step_ids == ["step_1"]
    assert item.details_json == original
    db.add.assert_not_called()
    db.commit.assert_not_awaited()
    reference_parameters = db.scalar.call_args.args[0].compile().params
    assert artifact_id in reference_parameters.values()
    assert owner in reference_parameters.values()
    assert item.id in reference_parameters.values()


@pytest.mark.asyncio
@pytest.mark.parametrize("latest_status", ["pending", "failed"])
@pytest.mark.parametrize("invalid", ["ownership", "content", "identity", "unapproved_outline"])
async def test_retained_read_never_exposes_unowned_or_unapproved_prior_artifact(
    monkeypatch, latest_status, invalid,
):
    from app.api.v1 import plans as api
    from app.schemas.plan import DetailsStatus, ItemProgress
    from tests.test_plan_progression_regressions import _Result

    item = prior_artifact_for_read()
    if invalid == "content":
        item.details_json["steps"][0]["lesson_content"] += " Changed after approval."
    elif invalid == "identity":
        item.details_json["_generation"]["validation_identity"]["prompt_hash"] = "unknown"
    elif invalid == "unapproved_outline":
        item.details_json["_generation"].pop("lesson_package_version")
        item.details_json["_generation"].pop("lesson_validation")
    now = datetime.now(timezone.utc)
    successor = SimpleNamespace(id=str(uuid4()), status=latest_status,
                                step="generating_lessons", progress_percent=70,
                                error_message=None, created_at=now, updated_at=now)
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.return_value = None if invalid == "ownership" else item.details_json["_generation"]["job_id"]
    db.execute.side_effect = (
        [] if invalid == "ownership" else [_Result(scalars=["step_1"])]
    ) + [_Result(scalar_one=successor)]
    monkeypatch.setattr(api, "_get_item_for_user", AsyncMock(return_value=item))
    monkeypatch.setattr(api, "_compute_item_progress", AsyncMock(return_value=(ItemProgress(), False)))
    monkeypatch.setattr(api, "_promote_prefetched_detail_job", AsyncMock())
    response = await api.get_plan_item_detailed(item.id, db, SimpleNamespace(id=str(uuid4())))

    assert response.details is None
    assert response.artifact_job_id is None
    assert response.details_status == (DetailsStatus.PENDING if latest_status == "pending" else DetailsStatus.FAILED)
    assert response.completed_step_ids == ([] if invalid == "ownership" or latest_status == "pending" else ["step_1"])
    db.add.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("maintenance", ["prefetch", "stale", "heartbeat_refreshed"])
async def test_retained_read_keeps_queue_maintenance_without_discarding_content(monkeypatch, maintenance):
    from app.api.v1 import plans as api
    from app.schemas.plan import DetailsStatus, ItemProgress
    from tests.test_plan_progression_regressions import _Result

    item = prior_artifact_for_read()
    original = copy.deepcopy(item.details_json)
    now = datetime.now(timezone.utc)
    stale = maintenance != "prefetch"
    successor = SimpleNamespace(id=str(uuid4()), status="running" if stale else "queued",
                                step="generating_lessons" if stale else "prefetch_queued",
                                progress_percent=40, error_message=None, created_at=now,
                                updated_at=now - timedelta(hours=1) if stale else now)
    db = AsyncMock()
    db.scalar.return_value = original["_generation"]["job_id"]
    db.execute.side_effect = [
        _Result(scalars=["step_1"]), _Result(scalar_one=successor),
        SimpleNamespace(rowcount=0 if maintenance == "heartbeat_refreshed" else 1),
    ]
    monkeypatch.setattr(api, "_get_item_for_user", AsyncMock(return_value=item))
    monkeypatch.setattr(api, "_compute_item_progress", AsyncMock(return_value=(
        ItemProgress(completed_steps=1, total_steps=3, percent=33.3), False,
    )))
    promote = AsyncMock()
    monkeypatch.setattr(api, "_promote_prefetched_detail_job", promote)
    response = await api.get_plan_item_detailed(item.id, db, SimpleNamespace(id=str(uuid4())))

    assert response.details_status == DetailsStatus.PARTIAL
    assert response.details.steps[0].lesson_content == original["steps"][0]["lesson_content"]
    assert response.completed_step_ids == ["step_1"]
    assert response.progress.percent == 33.3
    assert item.details_json == original
    if not stale:
        promote.assert_awaited_once_with(db, successor)
        db.commit.assert_not_awaited()
        assert response.details_error is None
    else:
        promote.assert_not_awaited()
        db.commit.assert_awaited_once()
        statement = db.execute.call_args.args[0]
        parameters = statement.compile().params
        assert successor.id in parameters.values()
        assert successor.updated_at in parameters.values()
        assert "plan_item_detail_jobs.updated_at =" in str(statement)
        if maintenance == "stale":
            assert response.details_step == "error"
            assert "not ready yet" in response.details_error
        else:
            assert response.details_step == "generating_lessons"
            assert response.details_error is None


@pytest.mark.asyncio
@pytest.mark.parametrize("change", [None, "content_hash", "package_hash", "missing_hash"])
async def test_retry_carries_completion_only_for_exact_approved_lesson_and_exercise(monkeypatch, change):
    _, item, job, _ = locked_artifact(monkeypatch)
    prior_id = item.details_json["_generation"]["job_id"]
    approvals = copy.deepcopy(item.details_json["_generation"]["lesson_validation"])
    if change == "missing_hash":
        approvals["step_1"].pop("package_hash")
    elif change:
        approvals["step_1"][change] = "changed"
    # Only step 1 has completed practice; step 3 is ready but not completed.
    timestamp = datetime.now(timezone.utc)
    completion = SimpleNamespace(step_id="step_1", completed_at=timestamp)
    db = AsyncMock(); db.add = MagicMock()
    def execute(statement):
        params = statement.compile().params
        assert "owner" in params.values() and "item" in params.values()
        assert prior_id in params.values()
        assert "plan_item_step_completions.completed_at IS NOT NULL" in str(statement)
        selected = next(v for v in params.values() if isinstance(v, list))
        return SimpleNamespace(scalars=lambda: SimpleNamespace(all=lambda: [completion] if "step_1" in selected else []))
    db.execute.side_effect = execute
    if change is not None:
        from app.services.planning.tutorial_capacity import TutorialCapacityError
        before = (item.status, item.progress_percent, copy.deepcopy(item.details_json))
        protected = AsyncMock(return_value={"step_1"})
        monkeypatch.setattr("app.services.planning.tutorial_capacity.protected_tutorial_ids", protected)
        with pytest.raises(TutorialCapacityError, match="Started tutorials"):
            await plans._prepare_current_detail_artifact_publication(
                db, plan_id="plan", item_id="item", user_id="owner", job_id=str(job.id),
                candidate_approved_step_ids=frozenset({"step_1", "step_3"}), candidate_validations=approvals,
            )
        assert (item.status, item.progress_percent, item.details_json) == before
        db.add.assert_not_called(); db.execute.assert_not_awaited()
        assert protected.await_args.kwargs["lock"] is True
        return
    await plans._prepare_current_detail_artifact_publication(
        db, plan_id="plan", item_id="item", user_id="owner", job_id=str(job.id),
        candidate_approved_step_ids=frozenset({"step_1", "step_3"}), candidate_validations=approvals,
    )
    if change is None:
        inherited = db.add.call_args.args[0]
        assert inherited.step_id == "step_1" and inherited.completed_at == timestamp
        assert inherited.artifact_job_id == str(job.id)
        assert item.status == PlanItemStatus.IN_PROGRESS and item.progress_percent == 33
    # Further checkpoints in the same job cannot duplicate the transferred row.
    item.details_json["_generation"]["job_id"] = str(job.id)
    db.reset_mock()
    await plans._prepare_current_detail_artifact_publication(
        db, plan_id="plan", item_id="item", user_id="owner", job_id=str(job.id),
        candidate_approved_step_ids=frozenset({"step_1", "step_3"}), candidate_validations=approvals,
    )
    db.execute.assert_not_awaited(); db.add.assert_not_called()


def test_tutorial_upgrade_revalidates_all_protected_steps_before_new_batches(monkeypatch):
    pending = [{"id": f"step_{i}"} for i in range(1, 9)]
    prior = {"marker": "saved artifact"}
    monkeypatch.setattr(plans, "_approved_readable_step_ids", lambda checkpoint: frozenset(
        {"step_1", "step_2", "step_3", "step_4", "step_5"}) if checkpoint is prior else frozenset())
    # Five old lessons must all pass the publication guard in one attempt.
    assert plans._detail_generation_batch(pending, prior, tutorial=True) == pending[:5]
    # Once revalidated, new tutorials come only from the learner's one-ahead
    # window (chosen by the generator), never from a batch.
    assert plans._detail_generation_batch(pending[5:], prior, tutorial=True) == []
    assert plans._detail_generation_batch(pending, None, tutorial=True) == []
    assert plans._detail_generation_batch(pending, prior, tutorial=False) == pending
