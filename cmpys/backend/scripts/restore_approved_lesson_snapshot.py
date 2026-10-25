"""Dry-run first recovery of one exact, previously approved public lesson.

This tool is deliberately pinned to the inspected QA copy and original mission.
It neither generates nor approves content. Run with PYTHONPATH=. from the backend.
Without --apply it uses a read-only repeatable snapshot and writes no files.

Applying requires separate operator authorization, every expected hash emitted by
the dry-run, and an existing private --backup-dir on the backend host. The backup
contains private learner state: keep it private. This script never prints text,
answers, user identifiers, connection settings, or backup contents.
"""

from __future__ import annotations

import argparse
import asyncio
import copy
import json
import os
import stat
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace


SOURCE_ITEM_ID = "d6d6e6b4-62e7-403c-a4a1-2910ba1f47ce"
TARGET_ITEM_ID = "99f5a87b-065c-49bb-8f83-7c8695b61658"
STEP_ID = "step_1"
ACTIVE_STATUSES = frozenset({"pending", "queued", "running"})


@dataclass(frozen=True)
class ApprovedPins:
    content_hash: str
    package_hash: str
    lesson_version: str
    identity_hash: str


PINS = ApprovedPins(
    "8c3758a53bad2377c6ec63b3579509d0585467321ebc170b15cb743f6a694e4f",
    "fc03f3d23778d55a4b4da132b7354979cd2ddddd5d8a60ff315cdbd673cb2b02",
    "d602a9a074d0e46943534800396d7f2e854a330b525ca10918a2543d493d3128",
    "ad0ab6d7f70c6b2a1e5a39fead3c9f01502e3d3fbb5d2be60825a2f57927a07b",
)


class RecoveryRefused(RuntimeError):
    """A safe, content-free refusal; never include raw validation errors."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RecoveryRefused(message)


def fingerprint(value) -> str:
    from app.services.planning.lesson_package import digest

    return digest(value)


def build_candidate(source: dict, target: dict, source_book: dict, target_book: dict) -> dict:
    """Return a copy changing only the exact lesson and essential readiness data."""
    from app.api.v1.plans import _partial_lesson_details_available
    from app.services.llm.schemas import PlanDetailStepOutput
    from app.services.planning.artifact_identity import progressive_ready_step_ids
    from app.services.planning.lesson_package import LessonPackage, current_package_approval
    from app.services.practice.contracts import lesson_version

    source_g = source.get("_generation") or {}
    target_g = target.get("_generation") or {}
    require(source_g.get("qa_fixture") is True, "Source is not the inspected QA snapshot")
    require(not target_g.get("qa_fixture"), "Target cannot be a QA snapshot")
    require(source_g.get("lesson_package_version") == target_g.get("lesson_package_version") == 1,
            "Both artifacts must use the original package contract")
    require(source_g.get("practice_required") is True and target_g.get("practice_required") is True,
            "Both artifacts must require their prepared workbook")
    # The inspected failure left an outline marked generating even though its
    # latest owned job is failed. inspect_snapshot verifies that terminal job
    # and rejects any active job before this pure candidate builder is called.
    require(target_g.get("status") in {"failed", "partial", "generating"}, "Target is not a stopped partial artifact")
    require(isinstance(source_g.get("validation_identity"), dict), "Source identity is missing")
    require(fingerprint(source_g["validation_identity"]) == PINS.identity_hash,
            "Source approval identity differs from the inspected approval")
    source_steps, target_steps = source.get("steps"), target.get("steps")
    require(isinstance(source_steps, list) and isinstance(target_steps, list), "Step lists are missing")
    require(len(source_steps) == 1 and source_steps[0].get("id") == STEP_ID,
            "Source must contain only the inspected first lesson")
    require([step.get("id") for step in target_steps] == ["step_1", "step_2", "step_3"],
            "Target outline differs from the inspected mission")
    require(not any(step.get("lesson_content") for step in target_steps),
            "Target already contains public lesson content; reassessment is required")
    require(not target_g.get("ready_step_ids") and not target_g.get("practice_ready_step_ids"),
            "Target already advertises ready lessons")
    step = source_steps[0]
    # Stored per-step progress must never be imported from the QA account. Any
    # non-generation fields must already be exactly equal, including absence.
    # Copying different flags from the target would alter the raw-step version
    # binding, so such cases require a separate assessment rather than a merge.
    generation_fields = set(PlanDetailStepOutput.model_fields) - {
        "completed", "is_completed", "completed_at", "progress", "answers", "hints",
    }
    # The inspected approved snapshot carries this old presentation alias. It
    # is part of its exact raw-step version, not learner progress; keep it only
    # if it agrees with the canonical generated estimate.
    for stored_step in (step, target_steps[0]):
        require("estimateMinutes" not in stored_step or
                stored_step["estimateMinutes"] == stored_step.get("estimate_minutes"),
                "Stored duration alias conflicts with its canonical estimate")
    generation_fields.add("estimateMinutes")
    require({key: value for key, value in step.items() if key not in generation_fields} ==
            {key: value for key, value in target_steps[0].items() if key not in generation_fields},
            "Source and target per-step progress or extension fields differ")
    approval = (source_g.get("lesson_validation") or {}).get(STEP_ID)
    require(isinstance(approval, dict), "Exact source approval is missing")
    require(all(approval.get(k) == v for k, v in source_g["validation_identity"].items()),
            "Source approval does not carry its exact identity")
    try:
        canonical = PlanDetailStepOutput.model_validate(step).model_dump(mode="json")
        package = LessonPackage.model_validate({
            "teaching_cases": source_g["teaching_cases"][STEP_ID],
            "workbook": target_book["workbook_json"],
        })
    except (ValueError, KeyError, TypeError):
        raise RecoveryRefused("Source lesson or original package fails canonical validation") from None
    require(fingerprint(canonical) == approval.get("content_hash") == PINS.content_hash,
            "Approved public content hash does not match")
    require(fingerprint(package.model_dump(mode="json")) == approval.get("package_hash") == PINS.package_hash,
            "Original package hash does not match")
    require(source_book.get("workbook_json") == target_book.get("workbook_json"),
            "QA and original private workbooks differ")
    require(source_book.get("state") == target_book.get("state") == "ready", "Workbooks are not ready")
    require(source_book.get("step_id") == target_book.get("step_id") == STEP_ID,
            "Workbook step identities differ")
    require(source_book.get("lesson_version") == target_book.get("lesson_version") == PINS.lesson_version,
            "Original workbook version does not match")
    require(lesson_version(SimpleNamespace(details_json=source), step) == PINS.lesson_version,
            "Recovered lesson does not bind to the original workbook")
    require(current_package_approval(source, allow_compatible_read=True), "Source is not readable under compatibility gates")

    candidate = copy.deepcopy(target)
    candidate["steps"][0] = copy.deepcopy(step)  # Preserve exact stored bytes/fields, not a schema rewrite.
    generation = candidate["_generation"]
    # The only ready prose is approved v6. A global v7 identity would falsely
    # relabel that approval and fail the reader gate. Copy its original identity
    # and review version exactly; never copy the QA job, input hash, or QA flag.
    generation["validation_identity"] = copy.deepcopy(source_g["validation_identity"])
    generation["content_review_version"] = source_g["content_review_version"]
    generation.setdefault("lesson_validation", {})[STEP_ID] = copy.deepcopy(approval)
    generation.setdefault("teaching_cases", {})[STEP_ID] = copy.deepcopy(source_g["teaching_cases"][STEP_ID])
    generation.update(status="partial", ready_step_ids=[STEP_ID], practice_ready_step_ids=[STEP_ID],
                      ready_lesson_count=1)
    require(generation.get("job_id") == target_g.get("job_id") and generation.get("input_hash") == target_g.get("input_hash"),
            "Target generation lineage changed")
    require(current_package_approval(candidate, allow_compatible_read=True), "Candidate approval gate failed")
    require(progressive_ready_step_ids(candidate) == (STEP_ID,), "Candidate exposes an unexpected lesson set")
    require(_partial_lesson_details_available(candidate), "Candidate cannot pass the partial reader serializer")
    require(lesson_version(SimpleNamespace(details_json=candidate), candidate["steps"][0]) == PINS.lesson_version,
            "Candidate changed the original workbook binding")
    return candidate


def inspect_snapshot(snapshot: dict) -> tuple[dict, dict]:
    """Validate ownership and provenance, producing only hash/count diagnostics."""
    source = snapshot["items"][SOURCE_ITEM_ID]
    target = snapshot["items"][TARGET_ITEM_ID]
    owners = snapshot["owners"]
    require(set(owners) == {SOURCE_ITEM_ID, TARGET_ITEM_ID}, "Both plan ownership records are required")
    require(owners[SOURCE_ITEM_ID] != owners[TARGET_ITEM_ID], "QA and learner must be distinct owners")
    for row in snapshot["jobs"] + snapshot["practices"] + snapshot["step_completions"] + snapshot["item_completions"]:
        require(str(row.get("user_id")) == owners.get(str(row.get("plan_item_id"))),
                "Related row belongs to a different owner")
    jobs_by_item = {item_id: [row for row in snapshot["jobs"] if str(row["plan_item_id"]) == item_id]
                    for item_id in owners}
    for item_id, item in snapshot["items"].items():
        jobs = jobs_by_item[item_id]
        require(bool(jobs), "Artifact job history is missing")
        require(not any(job["status"] in ACTIVE_STATUSES for job in jobs), "Generation is active")
        require((item["details_json"].get("_generation") or {}).get("job_id") == str(jobs[0]["id"]),
                "Artifact does not reference its latest owned job")
        if item_id == TARGET_ITEM_ID:
            require(jobs[0]["status"] == "failed", "Target's latest owned job must be failed")
    source_books = [row for row in snapshot["practices"] if str(row["plan_item_id"]) == SOURCE_ITEM_ID
                    and row["step_id"] == STEP_ID and row["lesson_version"] == PINS.lesson_version]
    target_books = [row for row in snapshot["practices"] if str(row["plan_item_id"]) == TARGET_ITEM_ID
                    and row["step_id"] == STEP_ID and row["lesson_version"] == PINS.lesson_version]
    require(len(source_books) == len(target_books) == 1, "Exact source and target workbooks must each exist once")
    candidate = build_candidate(source["details_json"], target["details_json"], source_books[0], target_books[0])
    # Everything outside the sole UPDATE is fingerprinted, including all saved
    # answer/hint/attempt rows and completion history from both owners.
    protected = copy.deepcopy(snapshot)
    protected["items"][TARGET_ITEM_ID].pop("details_json")
    report = {
        "source_details_sha256": fingerprint(source["details_json"]),
        "target_details_sha256": fingerprint(target["details_json"]),
        "candidate_details_sha256": fingerprint(candidate),
        "source_owner_sha256": fingerprint(owners[SOURCE_ITEM_ID]),
        "target_owner_sha256": fingerprint(owners[TARGET_ITEM_ID]),
        "latest_job_sha256": fingerprint(jobs_by_item[TARGET_ITEM_ID][0]),
        "protected_state_sha256": fingerprint(protected),
        "approved_content_sha256": PINS.content_hash,
        "approved_package_sha256": PINS.package_hash,
        "approved_lesson_version_sha256": PINS.lesson_version,
        "approved_identity_sha256": PINS.identity_hash,
        "ready_before_count": 0,
        "ready_after_count": 1,
        "remaining_missing_count": 2,
        "practice_row_count": len(snapshot["practices"]),
        "step_completion_row_count": len(snapshot["step_completions"]),
        "item_completion_row_count": len(snapshot["item_completions"]),
    }
    return candidate, report


EXPECTED_FIELDS = ("source_details", "target_details", "source_owner", "target_owner", "latest_job", "protected_state")


def check_expected(args, report: dict) -> None:
    for field in EXPECTED_FIELDS:
        expected = getattr(args, "expected_" + field + "_hash", None)
        require(expected is not None and expected == report[field + "_sha256"],
                "Apply expectations are missing or stale; repeat the dry-run")


def write_private_backup(directory: Path, snapshot: dict, report: dict) -> str:
    """Durably create a new owner-only backup before any database update."""
    directory = Path(directory)
    require(directory.is_absolute() and not directory.is_symlink(), "Backup directory must be an absolute real directory")
    info = directory.stat()
    require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o700,
            "Backup directory must be owned by the process user with mode 0700")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    dir_fd = os.open(directory, flags)
    try:
        require(os.fstat(dir_fd).st_ino == info.st_ino and os.fstat(dir_fd).st_dev == info.st_dev,
                "Backup directory changed during validation")
        payload = {"created_at": datetime.now(timezone.utc).isoformat(), "snapshot": snapshot, "verified": report}
        data = json.dumps(payload, sort_keys=True, ensure_ascii=False, default=str).encode("utf-8")
        name = "approved-lesson-" + report["target_details_sha256"] + "-" + os.urandom(8).hex() + ".json"
        file_fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
        with os.fdopen(file_fd, "wb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.fsync(dir_fd)
        return fingerprint(payload)
    finally:
        os.close(dir_fd)


async def load_snapshot(db, *, lock: bool) -> dict:
    from sqlalchemy import text

    params = {"source": SOURCE_ITEM_ID, "target": TARGET_ITEM_ID}
    lock_rows = " FOR UPDATE OF r" if lock else ""
    # Discover parent IDs without locking children. Publication takes locks in
    # Plan -> PlanItem -> Job order; use the same order and then recheck parents.
    items = (await db.execute(text(
        "SELECT to_jsonb(r) FROM plan_items r WHERE r.id IN (:source, :target) ORDER BY r.id"
    ), params)).scalars().all()
    require(len(items) == 2, "Both inspected mission rows are required")
    items = {str(row["id"]): row for row in items}
    plan_params = {"source": items[SOURCE_ITEM_ID]["plan_id"], "target": items[TARGET_ITEM_ID]["plan_id"]}
    plans = (await db.execute(text(
        "SELECT to_jsonb(r) FROM plans r WHERE r.id IN (:source, :target) ORDER BY r.id" + lock_rows
    ), plan_params)).scalars().all()
    if lock:
        locked_items = (await db.execute(text(
            "SELECT to_jsonb(r) FROM plan_items r WHERE r.id IN (:source, :target) ORDER BY r.id" + lock_rows
        ), params)).scalars().all()
        locked_items = {str(row["id"]): row for row in locked_items}
        require({key: row["plan_id"] for key, row in locked_items.items()} ==
                {key: row["plan_id"] for key, row in items.items()},
                "Mission ownership scope changed while locking")
        items = locked_items
    owner_by_plan = {str(row["id"]): str(row["user_id"]) for row in plans}
    snapshot = {"items": items, "owners": {key: owner_by_plan.get(str(item["plan_id"])) for key, item in items.items()}}
    require(all(snapshot["owners"].values()), "Plan ownership is missing")
    for key, table in (("jobs", "plan_item_detail_jobs"), ("practices", "lesson_practices"),
                       ("step_completions", "plan_item_step_completions"), ("item_completions", "plan_item_completions")):
        # Names above are fixed, never user input. New job publishers lock the
        # same item row; row locks and SERIALIZABLE also protect this inspection.
        order = "r.artifact_epoch_at DESC, r.id DESC" if key == "jobs" else "r.id"
        snapshot[key] = (await db.execute(text(
            f"SELECT to_jsonb(r) FROM {table} r WHERE r.plan_item_id IN (:source, :target) ORDER BY {order}" + lock_rows
        ), params)).scalars().all()
    return snapshot


async def run(args, session_factory=None) -> dict:
    from sqlalchemy import text
    from app.core.db import async_session_maker

    require(not args.apply or args.backup_dir is not None, "Apply requires a private backend backup directory")
    async with (session_factory or async_session_maker)() as db:
        try:
            await db.execute(text("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE" if args.apply else
                                  "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"))
            await db.execute(text("SET LOCAL lock_timeout = '5s'"))
            await db.execute(text("SET LOCAL statement_timeout = '15s'"))
            before = await load_snapshot(db, lock=args.apply)
            candidate, report = inspect_snapshot(before)
            if not args.apply:
                await db.rollback()
                return {**report, "applied_count": 0}
            check_expected(args, report)
            backup_hash = write_private_backup(args.backup_dir, before, report)
            # Only the JSON column changes. No timestamp, status, job, workbook,
            # completion, answer, hint, or other mission column is updated.
            result = await db.execute(text(
                "UPDATE plan_items SET details_json=CAST(:candidate AS jsonb) "
                "WHERE id=:target AND details_json=CAST(:original AS jsonb)"
            ), {"target": TARGET_ITEM_ID, "candidate": json.dumps(candidate, ensure_ascii=False),
                "original": json.dumps(before["items"][TARGET_ITEM_ID]["details_json"], ensure_ascii=False)})
            require(result.rowcount == 1, "Target changed; update was not applied")
            after = await load_snapshot(db, lock=True)
            require(after["items"][TARGET_ITEM_ID]["details_json"] == candidate, "Stored candidate differs")
            after["items"][TARGET_ITEM_ID]["details_json"] = before["items"][TARGET_ITEM_ID]["details_json"]
            require(after == before, "Protected learner state changed; transaction is rolling back")
            await db.commit()
            return {**report, "backup_sha256": backup_hash, "applied_count": 1}
        except BaseException:
            await db.rollback()
            raise


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write only after separate operator authorization")
    parser.add_argument("--backup-dir", type=Path)
    for field in EXPECTED_FIELDS:
        parser.add_argument("--expected-" + field.replace("_", "-") + "-hash")
    args = parser.parse_args(argv)
    if args.apply and (args.backup_dir is None or any(getattr(args, "expected_" + field + "_hash") is None for field in EXPECTED_FIELDS)):
        parser.error("--apply requires --backup-dir and all six expected hashes from the reviewed dry-run")
    return args


if __name__ == "__main__":
    try:
        print(json.dumps(asyncio.run(asyncio.wait_for(run(parse_args()), timeout=60)), sort_keys=True))
    except RecoveryRefused as exc:
        print("Restoration refused: " + str(exc), file=sys.stderr)
        raise SystemExit(2) from None
    except Exception:
        # Provider, SQL, validation and OS exceptions can embed private values.
        print("Restoration stopped; transaction rolled back or commit outcome needs read-only verification.", file=sys.stderr)
        raise SystemExit(3) from None
