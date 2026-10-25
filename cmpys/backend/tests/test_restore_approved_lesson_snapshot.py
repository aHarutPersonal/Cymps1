"""Safety contracts for the opt-in, exact-artifact recovery operator script."""

import copy
import json
import stat
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from scripts import restore_approved_lesson_snapshot as recovery
from app.services.llm.schemas import PlanDetailStepOutput
from app.services.planning.lesson_package import LessonPackage, validation_identity
from app.services.practice.contracts import lesson_version
from tests.lesson_package_fixtures import package_payload
from tests.test_plan_detail_output_schema import _valid_payload


@pytest.fixture
def snapshot(monkeypatch):
    package = LessonPackage.model_validate(package_payload())
    step = PlanDetailStepOutput.model_validate(_valid_payload()["steps"][0]).model_dump(mode="json")
    identity = validation_identity()
    approval = {**identity, "content_hash": recovery.fingerprint(step),
                "package_hash": recovery.fingerprint(package.model_dump(mode="json"))}
    step.update(completed=False, estimateMinutes=step["estimate_minutes"])
    source = {"steps": [step], "materials": [], "meta": {"unchanged": True}, "_generation": {
        "job_id": "source-job", "input_hash": "qa-input", "qa_fixture": True,
        "status": "ready", "lesson_package_version": 1, "practice_required": True,
        "validation_identity": identity, "content_review_version": identity["review_version"],
        "lesson_validation": {"step_1": approval}, "teaching_cases": {"step_1": []},
        "ready_step_ids": ["step_1"], "practice_ready_step_ids": ["step_1"],
    }}
    version = lesson_version(SimpleNamespace(details_json=source), step)
    monkeypatch.setattr(recovery, "PINS", recovery.ApprovedPins(
        approval["content_hash"], approval["package_hash"], version, recovery.fingerprint(identity)))
    outline_step = {key: value for key, value in step.items() if key != "estimateMinutes"}
    target = {"steps": [{**copy.deepcopy(outline_step), "id": "step_" + str(i), "lesson_content": ""} for i in (1, 2, 3)],
              "materials": [], "meta": {"keep": ["unaltered"]}, "_generation": {
                  "job_id": "target-job", "input_hash": "original-input", "status": "failed",
                  "validation_identity": {"review_version": -1}, "content_review_version": -1,
                  "practice_required": True, "lesson_package_version": 1,
                  "ready_step_ids": [], "practice_ready_step_ids": [], "ready_lesson_count": 0,
                  "total_lesson_count": 3, "lesson_validation": {}, "teaching_cases": {},
                  "supersedes_artifact": True, "outline": {"keep": "original outline"},
              }}
    owners = {recovery.SOURCE_ITEM_ID: "qa-owner", recovery.TARGET_ITEM_ID: "learner-owner"}
    practices = [{"id": "book-" + item_id, "plan_item_id": item_id, "user_id": owner,
                  "step_id": "step_1", "state": "ready", "lesson_version": version,
                  "workbook_json": package.workbook.model_dump(mode="json"),
                  "answers_json": {"saved": "answer"}, "hints_json": ["seen"],
                  "attempts_json": [{"immutable": True}], "revision": 4}
                 for item_id, owner in owners.items()]
    return {"items": {recovery.SOURCE_ITEM_ID: {"id": recovery.SOURCE_ITEM_ID, "details_json": source},
                      recovery.TARGET_ITEM_ID: {"id": recovery.TARGET_ITEM_ID, "details_json": target,
                                                "status": "in_progress", "updated_at": "original timestamp"}},
            "owners": owners, "practices": practices,
            "jobs": [{"id": "source-job", "plan_item_id": recovery.SOURCE_ITEM_ID,
                      "user_id": "qa-owner", "status": "ready"},
                     {"id": "target-job", "plan_item_id": recovery.TARGET_ITEM_ID,
                      "user_id": "learner-owner", "status": "failed"}],
            "step_completions": [{"id": "completion", "user_id": "learner-owner",
                                  "plan_item_id": recovery.TARGET_ITEM_ID, "completed_at": "saved"}],
            "item_completions": []}


def test_candidate_restores_only_exact_lesson_and_readiness_metadata(snapshot):
    original = copy.deepcopy(snapshot)
    candidate, report = recovery.inspect_snapshot(snapshot)
    target = snapshot["items"][recovery.TARGET_ITEM_ID]["details_json"]
    source = snapshot["items"][recovery.SOURCE_ITEM_ID]["details_json"]
    assert snapshot == original
    assert candidate["steps"][0] == source["steps"][0]
    assert candidate["steps"][1:] == target["steps"][1:]
    assert candidate["materials"] == target["materials"] and candidate["meta"] == target["meta"]
    allowed = {"validation_identity", "content_review_version", "lesson_validation", "teaching_cases",
               "status", "ready_step_ids", "practice_ready_step_ids", "ready_lesson_count"}
    assert {k: v for k, v in candidate["_generation"].items() if k not in allowed} == {
        k: v for k, v in target["_generation"].items() if k not in allowed}
    assert candidate["_generation"]["lesson_validation"]["step_1"] == source["_generation"]["lesson_validation"]["step_1"]
    assert candidate["_generation"]["status"] == "partial"
    assert report["ready_after_count"] == 1 and report["remaining_missing_count"] == 2
    assert all(isinstance(value, int) or (isinstance(value, str) and len(value) == 64) for value in report.values())


@pytest.mark.parametrize("defect", ["public_text", "private_key", "approval", "identity", "owner",
                                    "latest_job", "active_job", "target_content", "workbook_version"])
def test_refuses_nonexact_or_unsafe_snapshot(snapshot, defect):
    source = snapshot["items"][recovery.SOURCE_ITEM_ID]["details_json"]
    target = snapshot["items"][recovery.TARGET_ITEM_ID]["details_json"]
    if defect == "public_text":
        source["steps"][0]["lesson_content"] += " altered"
    elif defect == "private_key":
        snapshot["practices"][1]["workbook_json"]["activities"][0]["worked_solution"] += " changed"
    elif defect == "approval":
        source["_generation"]["lesson_validation"]["step_1"]["content_hash"] = "0" * 64
    elif defect == "identity":
        source["_generation"]["validation_identity"]["review_version"] = -2
    elif defect == "owner":
        snapshot["practices"][1]["user_id"] = "another-owner"
    elif defect == "latest_job":
        target["_generation"]["job_id"] = "older-job"
    elif defect == "active_job":
        snapshot["jobs"][1]["status"] = "running"
    elif defect == "target_content":
        target["steps"][2]["lesson_content"] = "Existing public content must not be displaced"
    else:
        snapshot["practices"][1]["lesson_version"] = "0" * 64
    with pytest.raises(recovery.RecoveryRefused):
        recovery.inspect_snapshot(snapshot)


def test_apply_requires_all_hashes_and_rejects_changed_learner_progress(snapshot):
    _, report = recovery.inspect_snapshot(snapshot)
    args = SimpleNamespace(**{"expected_" + key + "_hash": report[key + "_sha256"] for key in recovery.EXPECTED_FIELDS})
    recovery.check_expected(args, report)
    snapshot["practices"][1]["answers_json"]["saved"] = "a later learner answer"
    _, later = recovery.inspect_snapshot(snapshot)
    with pytest.raises(recovery.RecoveryRefused, match="stale"):
        recovery.check_expected(args, later)
    with pytest.raises(SystemExit):
        recovery.parse_args(["--apply"])


def test_stale_generating_outline_requires_a_failed_latest_owned_job(snapshot):
    snapshot["items"][recovery.TARGET_ITEM_ID]["details_json"]["_generation"]["status"] = "generating"
    candidate, _ = recovery.inspect_snapshot(snapshot)
    assert candidate["_generation"]["status"] == "partial"
    snapshot["jobs"][1]["status"] = "ready"
    with pytest.raises(recovery.RecoveryRefused, match="must be failed"):
        recovery.inspect_snapshot(snapshot)


@pytest.mark.parametrize("field,value", [("completed", True), ("progress", {"done": True}),
                                         ("extension", "must not disappear")])
def test_target_step_progress_or_extensions_cannot_be_replaced_by_qa_flags(snapshot, field, value):
    target = snapshot["items"][recovery.TARGET_ITEM_ID]["details_json"]
    target["steps"][0][field] = value
    with pytest.raises(recovery.RecoveryRefused, match="per-step progress"):
        recovery.inspect_snapshot(snapshot)


def test_legacy_estimate_alias_must_equal_canonical_generated_estimate(snapshot):
    snapshot["items"][recovery.SOURCE_ITEM_ID]["details_json"]["steps"][0]["estimateMinutes"] = 42
    with pytest.raises(recovery.RecoveryRefused, match="duration alias"):
        recovery.inspect_snapshot(snapshot)


def test_backup_is_new_private_and_contains_exact_prechange_state(tmp_path, snapshot):
    tmp_path.chmod(0o700)
    _, report = recovery.inspect_snapshot(snapshot)
    result = recovery.write_private_backup(tmp_path, snapshot, report)
    paths = list(tmp_path.iterdir())
    assert len(paths) == 1 and stat.S_IMODE(paths[0].stat().st_mode) == 0o600
    stored = json.loads(paths[0].read_text())
    assert stored["snapshot"] == snapshot and result == recovery.fingerprint(stored)
    tmp_path.chmod(0o755)
    with pytest.raises(recovery.RecoveryRefused, match="0700"):
        recovery.write_private_backup(tmp_path, snapshot, report)


def test_backup_rejects_symlink_directory(tmp_path, snapshot):
    private = tmp_path / "private"
    private.mkdir(mode=0o700)
    link = tmp_path / "link"
    link.symlink_to(private, target_is_directory=True)
    _, report = recovery.inspect_snapshot(snapshot)
    with pytest.raises(recovery.RecoveryRefused, match="real directory"):
        recovery.write_private_backup(link, snapshot, report)


@pytest.mark.asyncio
async def test_dry_run_never_locks_writes_backups_updates_or_commits(monkeypatch, snapshot):
    db = SimpleNamespace(execute=AsyncMock(), rollback=AsyncMock(), commit=AsyncMock())
    class Session:
        async def __aenter__(self): return db
        async def __aexit__(self, *args): return False
    loader = AsyncMock(return_value=snapshot)
    monkeypatch.setattr(recovery, "load_snapshot", loader)
    monkeypatch.setattr(recovery, "write_private_backup", lambda *args: pytest.fail("dry-run wrote a backup"))
    report = await recovery.run(recovery.parse_args([]), session_factory=Session)
    assert report["applied_count"] == 0
    loader.assert_awaited_once_with(db, lock=False)
    assert all("UPDATE" not in str(call.args[0]) for call in db.execute.await_args_list)
    assert "READ ONLY" in str(db.execute.await_args_list[0].args[0])
    db.commit.assert_not_awaited()
    db.rollback.assert_awaited_once()


@pytest.mark.asyncio
async def test_apply_requires_backup_before_single_update_and_preserves_every_other_row(monkeypatch, snapshot, tmp_path):
    candidate, report = recovery.inspect_snapshot(snapshot)
    args = SimpleNamespace(apply=True, backup_dir=tmp_path,
                           **{"expected_" + key + "_hash": report[key + "_sha256"] for key in recovery.EXPECTED_FIELDS})
    after = copy.deepcopy(snapshot)
    after["items"][recovery.TARGET_ITEM_ID]["details_json"] = candidate
    loader = AsyncMock(side_effect=[copy.deepcopy(snapshot), after])
    events = []
    async def execute(statement, *params):
        if str(statement).startswith("UPDATE"):
            assert events == ["backup"]
            events.append("update")
        return SimpleNamespace(rowcount=1)
    db = SimpleNamespace(execute=AsyncMock(side_effect=execute), rollback=AsyncMock(), commit=AsyncMock())
    class Session:
        async def __aenter__(self): return db
        async def __aexit__(self, *args): return False
    monkeypatch.setattr(recovery, "load_snapshot", loader)
    monkeypatch.setattr(recovery, "write_private_backup", lambda *args: events.append("backup") or "b" * 64)
    result = await recovery.run(args, session_factory=Session)
    assert events == ["backup", "update"] and result["applied_count"] == 1
    assert all(call.kwargs["lock"] is True for call in loader.await_args_list)
    updates = [str(call.args[0]) for call in db.execute.await_args_list if str(call.args[0]).startswith("UPDATE")]
    assert len(updates) == 1 and "SET details_json=" in updates[0]
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_apply_rolls_back_if_any_protected_state_changed(monkeypatch, snapshot, tmp_path):
    candidate, report = recovery.inspect_snapshot(snapshot)
    args = SimpleNamespace(apply=True, backup_dir=tmp_path,
                           **{"expected_" + key + "_hash": report[key + "_sha256"] for key in recovery.EXPECTED_FIELDS})
    after = copy.deepcopy(snapshot)
    after["items"][recovery.TARGET_ITEM_ID]["details_json"] = candidate
    after["practices"][1]["hints_json"].append("unexpected change")
    db = SimpleNamespace(execute=AsyncMock(return_value=SimpleNamespace(rowcount=1)),
                         rollback=AsyncMock(), commit=AsyncMock())
    class Session:
        async def __aenter__(self): return db
        async def __aexit__(self, *args): return False
    monkeypatch.setattr(recovery, "load_snapshot", AsyncMock(side_effect=[copy.deepcopy(snapshot), after]))
    monkeypatch.setattr(recovery, "write_private_backup", lambda *args: "b" * 64)
    with pytest.raises(recovery.RecoveryRefused, match="Protected learner state"):
        await recovery.run(args, session_factory=Session)
    db.rollback.assert_awaited_once()
    db.commit.assert_not_awaited()
