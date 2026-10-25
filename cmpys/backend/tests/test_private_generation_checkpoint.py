"""Recovery/privacy regression tests without paid provider calls or a shared DB."""

import asyncio
import copy
import importlib.util
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from sqlalchemy import inspect, select, text
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import undefer

from app.models.item_detail_job import PlanItemDetailJob
from app.services.planning.lesson_package import LessonPackage, digest
from app.services.planning.private_checkpoint import PrivateGenerationCheckpointStore
from tests.lesson_package_fixtures import package_payload


class Result:
    def __init__(self, values):
        self.values = values

    def scalar_one_or_none(self):
        return self.values[0] if self.values else None

    def scalars(self):
        return self

    def all(self):
        return self.values


class Transaction:
    def __init__(self, session):
        self.session = session

    async def __aenter__(self):
        self.session.in_transaction = True

    async def __aexit__(self, exc_type, *_):
        if self.session.locked:
            self.session.database.item_lock.release()
        self.session.database.transactions += 1
        self.session.in_transaction = False


class Session:
    """Emulate item locking across independent sessions; retain SQL for assertions."""

    def __init__(self, database):
        self.database = database
        self.locked = False
        self.in_transaction = False

    async def __aenter__(self):
        self.database.sessions.append(self)
        return self

    async def __aexit__(self, *_):
        assert not self.in_transaction

    def begin(self):
        return Transaction(self)

    async def execute(self, statement):
        assert self.in_transaction
        compiled = statement.compile(dialect=postgresql.dialect())
        sql, params = str(compiled), compiled.params
        self.database.queries.append((sql, params))
        if sql.startswith("SELECT plan_items.id"):
            await self.database.item_lock.acquire()
            self.locked = True
            await asyncio.sleep(0)
            owned = (
                params["id_1"] == self.database.item_id
                and params["user_id_1"] == self.database.user_id
            )
            return Result([self.database.item_id] if owned else [])
        assert self.locked
        jobs = [job for job in self.database.jobs
                if job.plan_item_id == params["plan_item_id_1"]
                and job.user_id == params["user_id_1"]]
        if " ->> " in sql:
            jobs = [job for job in jobs if (
                job.id != params["id_1"] and job.status == params["status_1"]
                and isinstance(job.private_checkpoint_json, dict)
                and job.private_checkpoint_json.get("input_hash") == params["param_1"]
                and job.private_checkpoint_json.get("validation_identity_hash") in params["param_2"]
            )]
        jobs.sort(key=lambda row: (row.artifact_epoch_at, row.id), reverse=True)
        return Result(jobs[:params.get("param_3", params.get("param_1", 1))]
                      if " ->> " not in sql else jobs[:20])


class Database:
    def __init__(self):
        self.user_id = str(uuid4())
        self.item_id = str(uuid4())
        self.item_lock = asyncio.Lock()
        self.jobs = []
        self.queries = []
        self.sessions = []
        self.transactions = 0

    def new_job(self, *, status="running"):
        job = PlanItemDetailJob(
            id=str(uuid4()), user_id=self.user_id, plan_item_id=self.item_id,
            status=status, progress_percent=0, step="generating_details",
            thinking_text="Preparing your lesson", result_json={"ready_lesson_count": 0},
            artifact_epoch_at=datetime.now(timezone.utc) + timedelta(seconds=len(self.jobs)),
        )
        self.jobs.append(job)
        return job

    def session(self):
        return Session(self)

    def store(self, job, **overrides):
        args = dict(job_id=job.id, plan_item_id=self.item_id, user_id=self.user_id,
                    input_hash=digest("inputs"), validation_identity={"review_version": 7},
                    session_factory=self.session)
        args.update(overrides)
        return PrivateGenerationCheckpointStore(**args)


STEP_HASH = digest("exact lesson outline, time budget and prompt context")
STEP_ID = "step_1"


def package():
    return LessonPackage.model_validate(package_payload()).model_dump(mode="json")


@pytest.mark.asyncio
async def test_retry_recovers_package_and_sections_without_publication_or_aliasing():
    db = Database()
    failed = db.new_job()
    original = db.store(failed)
    payload = package()
    assert await original.save_package(STEP_ID, STEP_HASH, payload, preflight_passed=True)
    assert await original.save_sections(STEP_ID, STEP_HASH, digest(payload), {
        "why_this_matters": "The completed introduction remains private.",
        "references": "The approved reading source remains private.",
    })
    failed.status = "failed"
    current = db.new_job()
    resumed = db.store(current)
    restored = await resumed.load_step(STEP_ID, STEP_HASH)
    assert restored["package"] == payload
    assert restored["preflight_passed"] is True
    assert restored["sections"]["why_this_matters"].startswith("The completed")
    restored["package"]["workbook"]["title"] = "mutation outside store"
    assert (await resumed.load_step(STEP_ID, STEP_HASH))["package"] == payload
    assert await resumed.save_sections(STEP_ID, STEP_HASH, digest(payload), {
        "core_framework": "Newly finished prose is added to the recovered introduction."
    })
    saved = await resumed.load_step(STEP_ID, STEP_HASH)
    assert set(saved["sections"]) == {"why_this_matters", "references", "core_framework"}
    assert current.private_checkpoint_json["job_id"] == current.id
    assert failed.result_json == current.result_json == {"ready_lesson_count": 0}
    assert "core_framework" not in failed.private_checkpoint_json["steps"][STEP_ID]["sections"]
    assert db.transactions == len(db.sessions)


@pytest.mark.asyncio
@pytest.mark.parametrize("mismatch", ["user", "item", "inputs", "validation", "step", "step_id"])
async def test_recovery_never_crosses_owner_item_or_generation_identity(mismatch):
    db = Database()
    prior = db.new_job()
    assert await db.store(prior).save_package(STEP_ID, STEP_HASH, package())
    prior.status = "failed"
    current = db.new_job()
    overrides = {}
    step_id, step_hash = STEP_ID, STEP_HASH
    if mismatch == "user":
        overrides["user_id"] = str(uuid4())
    elif mismatch == "item":
        overrides["plan_item_id"] = str(uuid4())
    elif mismatch == "inputs":
        overrides["input_hash"] = digest("changed inputs")
    elif mismatch == "validation":
        overrides["validation_identity"] = {"review_version": 8}
    elif mismatch == "step":
        step_hash = digest("changed outline")
    else:
        step_id = "step_2"
    assert await db.store(current, **overrides).load_step(step_id, step_hash) is None


@pytest.mark.asyncio
@pytest.mark.parametrize("status", ["completed", "cancelled", "running", "queued"])
async def test_recovery_selects_only_failed_predecessors(status):
    db = Database()
    prior = db.new_job()
    assert await db.store(prior).save_package(STEP_ID, STEP_HASH, package())
    prior.status = status
    current = db.new_job()
    assert await db.store(current).load_step(STEP_ID, STEP_HASH) is None


@pytest.mark.asyncio
async def test_parallel_section_saves_are_serialized_and_cumulative_snapshots_cannot_regress():
    db = Database()
    job = db.new_job()
    store = db.store(job)
    payload = package()
    await store.save_package(STEP_ID, STEP_HASH, payload)
    sections = {
        "why_this_matters": "Introduction", "core_framework": "Framework",
        "worked_example": "Worked example", "failure_modes": "Symptoms and repairs",
        "guided_practice": "Practice", "check_your_understanding": "Knowledge check",
        "references": "References", "substeps": ["Do an action"],
    }
    assert all(await asyncio.gather(*(
        store.save_sections(STEP_ID, STEP_HASH, digest(payload), {key: value})
        for key, value in sections.items()
    )))
    assert (await store.load_step(STEP_ID, STEP_HASH))["sections"] == sections
    assert await store.save_sections(STEP_ID, STEP_HASH, digest(payload), {
        "why_this_matters": "Introduction"
    })
    assert not await store.save_sections(STEP_ID, STEP_HASH, digest(payload), {
        "why_this_matters": "An older conflicting version"
    })
    assert (await store.load_step(STEP_ID, STEP_HASH))["sections"] == sections
    assert len({id(session) for session in db.sessions}) == len(db.sessions)
    assert all("FOR UPDATE OF plan_items" in sql for sql, _ in db.queries
               if sql.startswith("SELECT plan_items.id"))
    assert all("FOR UPDATE OF plan_item_detail_jobs" in sql for sql, _ in db.queries
               if sql.startswith("SELECT plan_item_detail_jobs.") and " ->> " not in sql)


@pytest.mark.asyncio
async def test_package_repair_invalidates_previous_prose_and_late_callbacks():
    db = Database()
    job = db.new_job()
    store = db.store(job)
    first = package()
    await store.save_package(STEP_ID, STEP_HASH, first, preflight_passed=True)
    await store.save_sections(STEP_ID, STEP_HASH, digest(first), {"core_framework": "Old content"})
    repaired = copy.deepcopy(first)
    repaired["workbook"]["activities"][0]["worked_solution"] += " Clarified private explanation."
    assert await store.save_package(STEP_ID, STEP_HASH, repaired, expected_package_hash=digest(first))
    entry = await store.load_step(STEP_ID, STEP_HASH)
    assert entry["sections"] == {}
    assert entry["preflight_passed"] is False
    assert not await store.save_sections(STEP_ID, STEP_HASH, digest(first), {"references": "Late callback"})
    await store.save_package(STEP_ID, STEP_HASH, repaired, preflight_passed=True)
    await store.save_package(STEP_ID, STEP_HASH, repaired)
    assert (await store.load_step(STEP_ID, STEP_HASH))["preflight_passed"] is True


@pytest.mark.asyncio
async def test_rejected_sections_do_not_resurrect_from_failed_predecessor():
    db = Database()
    old = db.new_job()
    prior = db.store(old)
    payload = package()
    await prior.save_package(STEP_ID, STEP_HASH, payload)
    await prior.save_sections(STEP_ID, STEP_HASH, digest(payload), {"core_framework": "Rejected prose"})
    old.status = "failed"
    current = db.new_job()
    store = db.store(current)
    assert await store.clear_sections(STEP_ID, STEP_HASH, digest(payload))
    assert (await store.load_step(STEP_ID, STEP_HASH))["sections"] == {}
    assert await store.save_sections(STEP_ID, STEP_HASH, digest(payload), {"core_framework": "Corrected prose"})
    assert (await store.load_step(STEP_ID, STEP_HASH))["sections"] == {"core_framework": "Corrected prose"}


@pytest.mark.asyncio
@pytest.mark.parametrize("newer_status", ["queued", "running", "failed", "cancelled", "completed"])
async def test_new_job_creation_blocks_stale_checkpoint_updates_even_if_new_job_failed(newer_status):
    db = Database()
    old = db.new_job()
    store = db.store(old)
    payload = package()
    await store.save_package(STEP_ID, STEP_HASH, payload)
    saved = copy.deepcopy(old.private_checkpoint_json)
    await db.item_lock.acquire()
    pending = asyncio.create_task(store.save_sections(
        STEP_ID, STEP_HASH, digest(payload), {"references": "Stale callback"}
    ))
    await asyncio.sleep(0)
    db.new_job(status=newer_status)
    db.item_lock.release()
    assert await pending is False
    assert old.private_checkpoint_json == saved
    assert await store.load_step(STEP_ID, STEP_HASH) is None


@pytest.mark.asyncio
@pytest.mark.parametrize("corruption", ["package", "sections", "owner", "job", "step", "identity", "unknown"])
async def test_stored_payload_tampering_is_a_cache_miss(corruption):
    db = Database()
    job = db.new_job()
    store = db.store(job)
    await store.save_package(STEP_ID, STEP_HASH, package())
    envelope = job.private_checkpoint_json
    entry = envelope["steps"][STEP_ID]
    if corruption == "package":
        entry["package"]["workbook"]["title"] = "Different package without matching hash"
    elif corruption == "sections":
        entry["sections"] = {"core_framework": "Different content without matching hash"}
    elif corruption == "owner":
        envelope["user_id"] = str(uuid4())
    elif corruption == "job":
        envelope["job_id"] = str(uuid4())
    elif corruption == "step":
        entry["step_hash"] = digest("different step")
    elif corruption == "identity":
        envelope["validation_identity"] = {"review_version": 6}
    else:
        entry["independently_approved"] = True
    assert await store.load_step(STEP_ID, STEP_HASH) is None


@pytest.mark.asyncio
async def test_payload_limits_and_non_json_values_are_rejected_before_storage(monkeypatch):
    from app.services.planning import private_checkpoint
    db = Database()
    job = db.new_job()
    store = db.store(job)
    payload = package()
    await store.save_package(STEP_ID, STEP_HASH, payload)
    saved = copy.deepcopy(job.private_checkpoint_json)
    with pytest.raises(ValueError):
        await store.save_sections(STEP_ID, STEP_HASH, digest(payload), {"unexpected": "secret"})
    with pytest.raises(ValueError):
        await store.save_sections(STEP_ID, STEP_HASH, digest(payload), {"substeps": "not an array"})
    with pytest.raises(ValueError):
        await store.save_sections(STEP_ID, STEP_HASH, digest(payload), {"references": "NUL\x00"})
    monkeypatch.setattr(private_checkpoint, "MAX_STEP_BYTES", 30)
    with pytest.raises(ValueError):
        await store.save_sections(STEP_ID, STEP_HASH, digest(payload), {"references": "x" * 100})
    assert job.private_checkpoint_json == saved
    with pytest.raises(ValueError):
        db.store(job, input_hash="not-a-hash")
    with pytest.raises(ValueError):
        db.store(job, validation_identity={"numeric": float("nan")})


@pytest.mark.asyncio
async def test_job_polling_never_serializes_private_checkpoint():
    from app.api.v1.jobs import JobStatusResponse, get_job_status
    db = Database()
    job = db.new_job()
    await db.store(job).save_package(STEP_ID, STEP_HASH, package(), preflight_passed=True)
    api_db = SimpleNamespace(execute=AsyncMock(return_value=Result([job])))
    response = await get_job_status(job.id, api_db, SimpleNamespace(id=db.user_id), job_type="plan_detail")
    public = response.model_dump_json()
    assert "private_checkpoint_json" not in JobStatusResponse.model_fields
    assert "private_checkpoint" not in public
    assert "worked_solution" not in public
    assert response.results == {"ready_lesson_count": 0}
    assert PlanItemDetailJob.__table__.c.private_checkpoint_json.nullable is True
    assert inspect(PlanItemDetailJob).attrs.private_checkpoint_json.deferred is True
    assert "private_checkpoint_json" not in str(select(PlanItemDetailJob))


def test_migration_is_nullable_additive_and_preserves_nonempty_checkpoints_on_downgrade(monkeypatch):
    path = Path(__file__).parents[1] / "migrations/versions/n5o6p7q8r9s0_private_detail_checkpoints.py"
    spec = importlib.util.spec_from_file_location("private_checkpoint_migration", path)
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    calls = []
    monkeypatch.setattr(migration.op, "add_column", lambda *args: calls.append(args))
    migration.upgrade()
    assert migration.down_revision == "m4n5o6p7q8r9"
    assert len(calls) == 1
    table, column = calls[0]
    assert table == "plan_item_detail_jobs"
    assert column.name == "private_checkpoint_json"
    assert column.nullable and column.server_default is None
    assert isinstance(column.type, postgresql.JSONB)
    monkeypatch.setattr(migration.op, "get_bind", lambda: SimpleNamespace(
        execute=lambda _: SimpleNamespace(scalar=lambda: True)
    ))
    monkeypatch.setattr(migration.op, "drop_column", lambda *_: pytest.fail("Must preserve saved work"))
    with pytest.raises(RuntimeError, match="Cannot discard"):
        migration.downgrade()


@pytest.mark.asyncio
@pytest.mark.skipif(not os.getenv("PRIVATE_CHECKPOINT_TEST_DATABASE_URL"),
                    reason="Requires an explicitly selected disposable PostgreSQL database")
async def test_postgresql_sessions_serialize_recovery_and_supersession():
    """Use real row locks; a unique schema cannot touch another suite's tables."""
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    from app.models.plan import PlanItem

    schema = "checkpoint_test_" + uuid4().hex
    engine = create_async_engine(
        os.environ["PRIVATE_CHECKPOINT_TEST_DATABASE_URL"],
        connect_args={"options": f"-csearch_path={schema}"},
        pool_size=10,
    )
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    user_id, plan_id, item_id, job_id = (str(uuid4()) for _ in range(4))
    store = PrivateGenerationCheckpointStore(
        job_id=job_id, plan_item_id=item_id, user_id=user_id,
        input_hash=digest("db inputs"), validation_identity={"review_version": 7},
        session_factory=sessions,
    )
    try:
        async with engine.begin() as connection:
            await connection.execute(text(f"CREATE SCHEMA {schema}"))
            await connection.execute(text("CREATE TABLE plans (id UUID PRIMARY KEY, user_id UUID NOT NULL)"))
            await connection.execute(text("CREATE TABLE plan_items (id UUID PRIMARY KEY, plan_id UUID NOT NULL)"))
            await connection.execute(text("""
                CREATE TABLE plan_item_detail_jobs (
                    id UUID PRIMARY KEY, plan_item_id UUID NOT NULL, user_id UUID NOT NULL,
                    artifact_epoch_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
                    supersedes_artifact BOOLEAN NOT NULL DEFAULT false,
                    status TEXT NOT NULL, step TEXT, progress_percent INTEGER NOT NULL DEFAULT 0,
                    error_message TEXT, thinking_text TEXT, result_json JSONB,
                    private_checkpoint_json JSONB,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
            """))
            await connection.execute(text("INSERT INTO plans VALUES (:id, :user_id)"),
                                     {"id": plan_id, "user_id": user_id})
            await connection.execute(text("INSERT INTO plan_items VALUES (:id, :plan_id)"),
                                     {"id": item_id, "plan_id": plan_id})
            await connection.execute(text("""
                INSERT INTO plan_item_detail_jobs (id, plan_item_id, user_id, status)
                VALUES (:id, :item_id, :user_id, 'running')
            """), {"id": job_id, "item_id": item_id, "user_id": user_id})

        payload = package()
        assert await store.save_package(STEP_ID, STEP_HASH, payload, preflight_passed=True)
        sections = {"why_this_matters": "Introduction", "core_framework": "Mechanism",
                    "worked_example": "Example", "references": "Reading"}
        assert all(await asyncio.gather(*(
            store.save_sections(STEP_ID, STEP_HASH, digest(payload), {key: value})
            for key, value in sections.items()
        )))
        assert (await store.load_step(STEP_ID, STEP_HASH))["sections"] == sections

        new_job_id = str(uuid4())
        async with sessions() as db:
            async with db.begin():
                await db.execute(select(PlanItem.id).where(PlanItem.id == item_id).with_for_update(of=PlanItem))
                late_save = asyncio.create_task(store.save_sections(
                    STEP_ID, STEP_HASH, digest(payload), {"failure_modes": "Late old worker"}
                ))
                with pytest.raises(asyncio.TimeoutError):
                    await asyncio.wait_for(asyncio.shield(late_save), timeout=0.05)
                await db.execute(text("UPDATE plan_item_detail_jobs SET status='failed' WHERE id=:id"),
                                 {"id": job_id})
                await db.execute(text("""
                    INSERT INTO plan_item_detail_jobs (id, plan_item_id, user_id, status)
                    VALUES (:id, :item_id, :user_id, 'running')
                """), {"id": new_job_id, "item_id": item_id, "user_id": user_id})
        assert await asyncio.wait_for(late_save, timeout=5) is False
        resumed = PrivateGenerationCheckpointStore(
            job_id=new_job_id, plan_item_id=item_id, user_id=user_id,
            input_hash=digest("db inputs"), validation_identity={"review_version": 7},
            session_factory=sessions,
        )
        recovered = await resumed.load_step(STEP_ID, STEP_HASH)
        assert recovered["sections"] == sections
        assert recovered["preflight_passed"] is True
        assert await resumed.save_sections(STEP_ID, STEP_HASH, digest(payload), {
            "failure_modes": "Fresh current worker"
        })
        async with sessions() as db:
            rows = (await db.execute(select(PlanItemDetailJob)
                                    .options(undefer(PlanItemDetailJob.private_checkpoint_json))
                                    .order_by(PlanItemDetailJob.artifact_epoch_at))).scalars().all()
        assert all(row.result_json is None for row in rows)
        assert "failure_modes" not in rows[0].private_checkpoint_json["steps"][STEP_ID]["sections"]
        assert rows[1].private_checkpoint_json["steps"][STEP_ID]["sections"]["failure_modes"] == "Fresh current worker"
    finally:
        # This schema contains only this test's randomly named synthetic rows.
        async with engine.begin() as connection:
            await connection.execute(text(f"DROP SCHEMA IF EXISTS {schema} CASCADE"))
        await engine.dispose()
