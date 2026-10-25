"""Private, resumable lesson preparation; never a publication or approval path.

Every operation owns its short database session. Item/job row locks serialize
parallel section callbacks and retry creation, including across worker processes.
Callers must not hold an item/job lock in another session while awaiting this
store. A new job can reuse only a failed predecessor with identical owner, item,
generation inputs, validation contract and per-lesson context. Reused prose still
passes writer validation and independent review before public persistence.
"""

from __future__ import annotations

import json
import re
from collections.abc import Callable
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import undefer

from app.models.item_detail_job import PlanItemDetailJob
from app.models.plan import Plan, PlanItem
from app.services.planning.lesson_package import (LessonPackage, digest, compatible_prepared_identity,
    _CAPACITY_REVIEW_PREDECESSORS)

CHECKPOINT_VERSION = 1
MAX_CHECKPOINT_BYTES = 4 * 1024 * 1024
MAX_STEP_BYTES = 1024 * 1024
MAX_STEPS = 128
_HASH = re.compile(r"[0-9a-f]{64}\Z")
_STEP_ID = re.compile(r"[A-Za-z0-9_.:-]{1,128}\Z")
_SECTION_FIELDS = frozenset({
    "why_this_matters", "core_framework", "worked_example", "failure_modes",
    "guided_practice", "check_your_understanding", "references", "substeps",
})
_ENTRY_KEYS = frozenset({
    "step_hash", "package", "package_hash", "preflight_passed", "sections",
    "sections_hash",
})
_REVIEW_ENTRY_KEYS = frozenset({"review_state", "review_state_hash"})
_PARTS_ENTRY_KEYS = frozenset({"step_hash", "parts", "parts_hash"})


def _json_copy(value: Any, *, max_bytes: int) -> Any:
    """Bound and isolate the exact JSON value persisted in PostgreSQL."""
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    if len(encoded.encode("utf-8")) > max_bytes:
        raise ValueError("Private lesson checkpoint exceeds its storage limit")
    # PostgreSQL text/JSONB cannot contain NUL, including within nested keys.
    if "\\u0000" in encoded:
        raise ValueError("Private lesson checkpoint contains an unsupported character")
    return json.loads(encoded)


def _require_hash(value: str) -> str:
    if not isinstance(value, str) or not _HASH.fullmatch(value):
        raise ValueError("Private checkpoint identity must be a SHA-256 digest")
    return value


def _validate_sections(value: Any) -> dict:
    if not isinstance(value, dict) or not value.keys() <= _SECTION_FIELDS:
        raise ValueError("Private checkpoint has unknown lesson sections")
    for name, content in value.items():
        if name == "substeps":
            if (not isinstance(content, list) or not content
                    or any(not isinstance(item, str) or not item.strip() for item in content)):
                raise ValueError("Private checkpoint has invalid lesson actions")
        elif not isinstance(content, str) or not content.strip():
            raise ValueError("Private checkpoint has invalid lesson prose")
    return _json_copy(value, max_bytes=MAX_STEP_BYTES)


def _review_rejected(state: dict) -> bool:
    semantic = state.get("semantic")
    return state.get("rejection") is not None or bool(
        semantic is not None and (semantic["acceptable"] is False or semantic["issues"])
    )


class PrivateGenerationCheckpointStore:
    """Recover paid work without exposing or independently approving any of it.

    A false mutation result means the job/package was superseded. Malformed
    caller payloads raise ValueError; corrupt or incompatible stored payloads
    are cache misses. Database errors propagate so callers can report a storage
    outage rather than silently promising work was saved.
    """

    def __init__(
        self,
        *,
        job_id: str,
        plan_item_id: str,
        user_id: str,
        input_hash: str,
        validation_identity: dict,
        session_factory: Callable | None = None,
    ):
        self.job_id = str(UUID(str(job_id)))
        self.plan_item_id = str(UUID(str(plan_item_id)))
        self.user_id = str(UUID(str(user_id)))
        self.input_hash = _require_hash(input_hash)
        if not isinstance(validation_identity, dict) or not validation_identity:
            raise ValueError("A private checkpoint requires the validation identity")
        self.validation_identity = _json_copy(validation_identity, max_bytes=8192)
        self.validation_identity_hash = digest(self.validation_identity)
        if session_factory is None:
            from app.core.db import async_session_maker
            session_factory = async_session_maker
        self.session_factory = session_factory

    def _scope(self, job_id: str) -> dict:
        return {
            "version": CHECKPOINT_VERSION,
            "job_id": job_id,
            "plan_item_id": self.plan_item_id,
            "user_id": self.user_id,
            "input_hash": self.input_hash,
            "validation_identity": self.validation_identity,
            "validation_identity_hash": self.validation_identity_hash,
        }

    def _envelope(self, job: PlanItemDetailJob) -> dict | None:
        if (str(job.plan_item_id) != self.plan_item_id or str(job.user_id) != self.user_id):
            return None
        try:
            raw = _json_copy(job.private_checkpoint_json, max_bytes=MAX_CHECKPOINT_BYTES)
            expected = self._scope(str(job.id))
            if (isinstance(raw, dict) and isinstance(raw.get("validation_identity"), dict)
                    and raw.get("validation_identity_hash") == digest(raw["validation_identity"])
                    and compatible_prepared_identity(raw["validation_identity"], self.validation_identity)):
                # Normalize only the contract envelope in memory. Recovered
                # private review state keeps its old identity and is rechecked.
                raw = {**raw, "validation_identity": self.validation_identity,
                       "validation_identity_hash": self.validation_identity_hash}
            if (not isinstance(raw, dict)
                    or not (expected.keys() | {"steps"}) <= raw.keys()
                    or raw.keys() - expected.keys() - {"steps", "package_parts"}
                    or any(raw.get(key) != value for key, value in expected.items())
                    or not isinstance(raw["steps"], dict)
                    or not isinstance(raw.get("package_parts", {}), dict)
                    or len(raw["steps"].keys() | raw.get("package_parts", {}).keys()) > MAX_STEPS):
                return None
            return raw
        except (TypeError, ValueError, OverflowError, RecursionError):
            return None

    def _step(self, envelope: dict | None, step_id: str, step_hash: str) -> dict | None:
        if envelope is None:
            return None
        try:
            entry = _json_copy(envelope["steps"].get(step_id), max_bytes=MAX_STEP_BYTES)
            if (not isinstance(entry, dict) or not _ENTRY_KEYS <= entry.keys()
                    or entry.keys() - _ENTRY_KEYS - _REVIEW_ENTRY_KEYS
                    or entry["step_hash"] != step_hash
                    or not isinstance(entry["preflight_passed"], bool)
                    or digest(entry["package"]) != entry["package_hash"]
                    or digest(entry["sections"]) != entry["sections_hash"]):
                return None
            LessonPackage.model_validate(entry["package"])
            _validate_sections(entry["sections"])
            if entry.keys() & _REVIEW_ENTRY_KEYS:
                from app.services.planning.package_preflight import parse_preflight_state
                try:
                    if (not _REVIEW_ENTRY_KEYS <= entry.keys()
                            or digest(entry["review_state"]) != entry["review_state_hash"]):
                        raise ValueError("Invalid private review checkpoint hash")
                    state = parse_preflight_state(entry["review_state"])
                    if state["package_hash"] != entry["package_hash"]:
                        raise ValueError("Private review belongs to a different package")
                    entry["review_state"] = state
                    if _review_rejected(state):
                        entry["preflight_passed"] = False
                except (KeyError, TypeError, ValueError, OverflowError, RecursionError):
                    # A corrupt optional review does not erase useful private
                    # package/prose work, but it cannot confer approval.
                    entry.pop("review_state", None)
                    entry.pop("review_state_hash", None)
                    entry["preflight_passed"] = False
            return entry
        except (KeyError, TypeError, ValueError, OverflowError, RecursionError):
            return None

    def _parts(self, envelope: dict | None, step_id: str, step_hash: str) -> dict | None:
        if envelope is None:
            return None
        try:
            from app.services.planning.package_builder import validate_package_parts
            entry = _json_copy(envelope.get("package_parts", {}).get(step_id), max_bytes=MAX_STEP_BYTES)
            if (not isinstance(entry, dict) or entry.keys() != _PARTS_ENTRY_KEYS
                    or entry["step_hash"] != step_hash
                    or digest(entry["parts"]) != entry["parts_hash"]):
                return None
            return validate_package_parts(entry["parts"])
        except (KeyError, TypeError, ValueError, OverflowError, RecursionError):
            return None

    @staticmethod
    def _validate_step_identity(step_id: str, step_hash: str) -> None:
        if not isinstance(step_id, str) or not _STEP_ID.fullmatch(step_id):
            raise ValueError("Invalid private checkpoint step identifier")
        _require_hash(step_hash)

    async def _lock_current_job(self, db: Any) -> PlanItemDetailJob | None:
        # Retry creation also locks this item before allocating the next job's
        # artifact_epoch_at. Checking every status prevents an old worker from
        # writing even when its newer successor already failed or was cancelled.
        owned_item = await db.execute(
            select(PlanItem.id)
            .join(Plan, Plan.id == PlanItem.plan_id)
            .where(PlanItem.id == self.plan_item_id, Plan.user_id == self.user_id)
            .with_for_update(of=PlanItem)
        )
        if owned_item.scalar_one_or_none() is None:
            return None
        latest = await db.execute(
            select(PlanItemDetailJob)
            .options(undefer(PlanItemDetailJob.private_checkpoint_json))
            .where(PlanItemDetailJob.plan_item_id == self.plan_item_id,
                   PlanItemDetailJob.user_id == self.user_id)
            .order_by(PlanItemDetailJob.artifact_epoch_at.desc(), PlanItemDetailJob.id.desc())
            .limit(1)
            .execution_options(populate_existing=True)
            .with_for_update(of=PlanItemDetailJob)
        )
        job = latest.scalar_one_or_none()
        if job is None or str(job.id) != self.job_id or job.status != "running":
            return None
        return job

    async def _load_step(self, db: Any, job: PlanItemDetailJob,
                         step_id: str, step_hash: str) -> dict | None:
        envelope = self._envelope(job)
        entry = self._step(envelope, step_id, step_hash)
        if entry is not None:
            return entry
        if self._parts(envelope, step_id, step_hash) is not None:
            return None
        for predecessor in await self._predecessors(db):
            envelope = self._envelope(predecessor)
            entry = self._step(envelope, step_id, step_hash)
            if entry is not None:
                return entry
            if self._parts(envelope, step_id, step_hash) is not None:
                return None  # One newest compatible snapshot wins across representations.
        return None

    async def _predecessors(self, db: Any) -> list[PlanItemDetailJob]:
        previous = await db.execute(
            select(PlanItemDetailJob)
            .options(undefer(PlanItemDetailJob.private_checkpoint_json))
            .where(
                PlanItemDetailJob.plan_item_id == self.plan_item_id,
                PlanItemDetailJob.user_id == self.user_id,
                PlanItemDetailJob.id != self.job_id,
                PlanItemDetailJob.status == "failed",
                PlanItemDetailJob.private_checkpoint_json["input_hash"].astext == self.input_hash,
                PlanItemDetailJob.private_checkpoint_json["validation_identity_hash"].astext.in_(
                    [self.validation_identity_hash, *_CAPACITY_REVIEW_PREDECESSORS]),
            )
            .order_by(PlanItemDetailJob.artifact_epoch_at.desc(), PlanItemDetailJob.id.desc())
            .limit(20)
        )
        return previous.scalars().all()

    async def _load_parts(self, db: Any, job: PlanItemDetailJob,
                          step_id: str, step_hash: str) -> dict | None:
        envelope = self._envelope(job)
        if self._step(envelope, step_id, step_hash) is not None:
            return None  # A durable complete package supersedes its draft components.
        parts = self._parts(envelope, step_id, step_hash)
        if parts is not None:
            return parts
        for predecessor in await self._predecessors(db):
            envelope = self._envelope(predecessor)
            if self._step(envelope, step_id, step_hash) is not None:
                return None
            parts = self._parts(envelope, step_id, step_hash)
            if parts is not None:
                return parts
        return None

    def _persist(self, job: PlanItemDetailJob, step_id: str, entry: dict) -> None:
        envelope = self._envelope(job) or {**self._scope(self.job_id), "steps": {}}
        envelope["steps"][step_id] = _json_copy(entry, max_bytes=MAX_STEP_BYTES)
        if len(envelope["steps"].keys() | envelope.get("package_parts", {}).keys()) > MAX_STEPS:
            raise ValueError("Too many private lesson checkpoints for one job")
        job.private_checkpoint_json = _json_copy(envelope, max_bytes=MAX_CHECKPOINT_BYTES)

    async def load_step(self, step_id: str, step_hash: str) -> dict | None:
        self._validate_step_identity(step_id, step_hash)
        async with self.session_factory() as db:
            async with db.begin():
                job = await self._lock_current_job(db)
                if job is None:
                    return None
                return await self._load_step(db, job, step_id, step_hash)

    async def load_package_parts(self, step_id: str, step_hash: str) -> dict | None:
        self._validate_step_identity(step_id, step_hash)
        async with self.session_factory() as db:
            async with db.begin():
                job = await self._lock_current_job(db)
                if job is None:
                    return None
                return await self._load_parts(db, job, step_id, step_hash)

    async def save_package_parts(self, step_id: str, step_hash: str, parts: dict,
                                 *, expected_seed_hash: str | None = None) -> bool:
        """Add validated private components; no component confers approval."""
        from app.services.planning.package_builder import validate_package_parts
        self._validate_step_identity(step_id, step_hash)
        if expected_seed_hash is not None:
            _require_hash(expected_seed_hash)
        parts = validate_package_parts(_json_copy(parts, max_bytes=MAX_STEP_BYTES))
        async with self.session_factory() as db:
            async with db.begin():
                job = await self._lock_current_job(db)
                if job is None:
                    return False
                envelope = self._envelope(job) or {**self._scope(self.job_id), "steps": {}}
                if self._step(envelope, step_id, step_hash) is not None:
                    return False  # A delayed callback cannot resurrect completed drafts.
                previous = await self._load_parts(db, job, step_id, step_hash)
                if previous is not None:
                    if previous["seed_hash"] != parts["seed_hash"]:
                        if expected_seed_hash != previous["seed_hash"]:
                            return False
                    else:
                        if any(key in previous["activities"] and previous["activities"][key] != value
                               for key, value in parts["activities"].items()):
                            return False
                        parts = validate_package_parts({**parts, "activities": {
                            **previous["activities"], **parts["activities"],
                        }})
                elif expected_seed_hash is not None:
                    return False
                envelope.setdefault("package_parts", {})[step_id] = _json_copy({
                    "step_hash": step_hash, "parts": parts, "parts_hash": digest(parts),
                }, max_bytes=MAX_STEP_BYTES)
                if len(envelope["steps"].keys() | envelope["package_parts"].keys()) > MAX_STEPS:
                    raise ValueError("Too many private lesson checkpoints for one job")
                job.private_checkpoint_json = _json_copy(envelope, max_bytes=MAX_CHECKPOINT_BYTES)
                return True

    async def save_package(self, step_id: str, step_hash: str, package_json: dict,
                           *, preflight_passed: bool = False,
                           expected_parts_hash: str | None = None,
                           expected_package_hash: str | None = None) -> bool:
        self._validate_step_identity(step_id, step_hash)
        if not isinstance(preflight_passed, bool):
            raise ValueError("Invalid package preflight flag")
        if expected_parts_hash is not None:
            _require_hash(expected_parts_hash)
        if expected_package_hash is not None:
            _require_hash(expected_package_hash)
        if expected_parts_hash is not None and expected_package_hash is not None:
            raise ValueError("Package promotion and repair have different checkpoint identities")
        package = LessonPackage.model_validate(package_json).model_dump(mode="json")
        package = _json_copy(package, max_bytes=MAX_STEP_BYTES)
        package_hash = digest(package)
        async with self.session_factory() as db:
            async with db.begin():
                job = await self._lock_current_job(db)
                if job is None:
                    return False
                parts = await self._load_parts(db, job, step_id, step_hash)
                if parts is not None:
                    # Promotion owns the exact completed snapshot, not just its
                    # seed. A later component or seed replacement must win over
                    # an older worker that is finishing local assembly.
                    if expected_parts_hash != digest(parts):
                        return False
                    seed = parts["seed"]
                    try:
                        assembled = LessonPackage.model_validate({
                            "teaching_cases": seed["teaching_cases"],
                            "workbook": {"title": seed["workbook_title"], "activities": [
                                parts["activities"][brief["id"]]
                                for brief in seed["activity_briefs"]
                            ]},
                        }).model_dump(mode="json")
                    except (KeyError, ValueError):
                        return False
                    if digest(assembled) != package_hash:
                        return False
                elif expected_parts_hash is not None:
                    return False
                previous = await self._load_step(db, job, step_id, step_hash)
                same_package = previous is not None and previous["package_hash"] == package_hash
                if expected_package_hash is not None:
                    if previous is None or previous["package_hash"] != expected_package_hash:
                        return False
                elif previous is not None and not same_package:
                    return False  # Changed complete packages require explicit compare-and-swap.
                sections = previous["sections"] if same_package else {}
                if (preflight_passed and same_package and "review_state" in previous
                        and _review_rejected(previous["review_state"])):
                    return False
                entry = {
                    "step_hash": step_hash,
                    "package": package,
                    "package_hash": package_hash,
                    "preflight_passed": preflight_passed or bool(
                        same_package and previous["preflight_passed"]
                    ),
                    "sections": sections,
                    "sections_hash": digest(sections),
                }
                if same_package and "review_state" in previous:
                    entry.update({key: previous[key] for key in _REVIEW_ENTRY_KEYS})
                self._persist(job, step_id, entry)
                envelope = self._envelope(job)
                if envelope is not None and step_id in envelope.get("package_parts", {}):
                    envelope["package_parts"].pop(step_id)
                    job.private_checkpoint_json = _json_copy(envelope, max_bytes=MAX_CHECKPOINT_BYTES)
                return True

    async def save_review_state(self, step_id: str, step_hash: str,
                                package_hash: str, state: dict) -> bool:
        """Retain typed private review work without granting publication approval.

        Concurrent cumulative callbacks merge under the same item/job locks as
        package repairs. An older snapshot can add missing scopes but cannot
        erase a success, a consumed correction, or a known negative verdict.
        """
        from app.services.planning.package_preflight import (
            merge_preflight_states, parse_preflight_state,
        )
        self._validate_step_identity(step_id, step_hash)
        _require_hash(package_hash)
        state = parse_preflight_state(_json_copy(state, max_bytes=MAX_STEP_BYTES))
        if state["package_hash"] != package_hash:
            raise ValueError("Private review does not match its package identity")
        async with self.session_factory() as db:
            async with db.begin():
                job = await self._lock_current_job(db)
                if job is None:
                    return False
                entry = await self._load_step(db, job, step_id, step_hash)
                if entry is None or entry["package_hash"] != package_hash:
                    return False
                if "review_state" in entry:
                    try:
                        state = merge_preflight_states(entry["review_state"], state)
                    except ValueError:
                        return False
                entry["review_state"] = state
                entry["review_state_hash"] = digest(state)
                if _review_rejected(state):
                    entry["preflight_passed"] = False
                self._persist(job, step_id, entry)
                return True

    async def clear_review_state(self, step_id: str, step_hash: str,
                                 package_hash: str, expected_review_state_hash: str) -> bool:
        """Invalidate an incompatible review with an exact snapshot comparison."""
        self._validate_step_identity(step_id, step_hash)
        _require_hash(package_hash)
        _require_hash(expected_review_state_hash)
        async with self.session_factory() as db:
            async with db.begin():
                job = await self._lock_current_job(db)
                if job is None:
                    return False
                entry = await self._load_step(db, job, step_id, step_hash)
                if (entry is None or entry["package_hash"] != package_hash
                        or entry.get("review_state_hash") != expected_review_state_hash):
                    return False
                entry.pop("review_state", None)
                entry.pop("review_state_hash", None)
                entry["preflight_passed"] = False
                self._persist(job, step_id, entry)
                return True

    async def save_sections(self, step_id: str, step_hash: str, package_hash: str,
                            sections: dict) -> bool:
        self._validate_step_identity(step_id, step_hash)
        _require_hash(package_hash)
        sections = _validate_sections(sections)
        async with self.session_factory() as db:
            async with db.begin():
                job = await self._lock_current_job(db)
                if job is None:
                    return False
                entry = await self._load_step(db, job, step_id, step_hash)
                if entry is None or entry["package_hash"] != package_hash:
                    return False
                # Additive snapshots can arrive out of order across callbacks.
                # Conflicting prose requires explicit invalidation first.
                if any(key in entry["sections"] and entry["sections"][key] != value
                       for key, value in sections.items()):
                    return False
                entry["sections"].update(sections)
                entry["sections_hash"] = digest(entry["sections"])
                self._persist(job, step_id, entry)
                return True

    async def clear_sections(self, step_id: str, step_hash: str, package_hash: str) -> bool:
        """Invalidate rejected prose while preserving its private exercise package."""
        self._validate_step_identity(step_id, step_hash)
        _require_hash(package_hash)
        async with self.session_factory() as db:
            async with db.begin():
                job = await self._lock_current_job(db)
                if job is None:
                    return False
                entry = await self._load_step(db, job, step_id, step_hash)
                if entry is None or entry["package_hash"] != package_hash:
                    return False
                entry["sections"] = {}
                entry["sections_hash"] = digest({})
                self._persist(job, step_id, entry)
                return True
