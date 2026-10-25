"""Durable review reuse: additive concurrency, negative retention and exact scope."""
import asyncio
import copy
import os
from uuid import uuid4

import pytest

from app.services.planning.lesson_package import digest
from app.services.planning.private_checkpoint import PrivateGenerationCheckpointStore
from tests.test_private_generation_checkpoint import Database, STEP_HASH, STEP_ID, package


def review_state(payload=None):
    identities = {
        "package_hash": digest(payload or package()),
        "input_hash": digest({"outline": {}, "context": {}}),
        "contract_hash": digest("synthetic-review-contract"),
    }
    return {
        "version": 1, **identities, "identity_hash": digest(identities),
        "semantic": {"acceptable": True, "issues": []}, "scopes": {},
        "rejection": None, "correction_used": False,
    }


def with_scope(state, activity, claim):
    result = copy.deepcopy(state)
    result["scopes"][activity] = {
        "claim_ids": [claim], "evidence": {"literal_fact_ids": [claim]},
    }
    return result


async def setup():
    database = Database()
    job = database.new_job()
    store = database.store(job)
    payload = package()
    assert await store.save_package(STEP_ID, STEP_HASH, payload)
    return database, job, store, payload


@pytest.mark.asyncio
async def test_parallel_review_snapshots_merge_scopes_without_losing_correction_or_privacy():
    db, job, store, payload = await setup()
    state = review_state(payload)
    left = with_scope(state, "guided", "n1")
    right = with_scope(state, "transfer", "n2")
    right["correction_used"] = True
    assert all(await asyncio.gather(*[
        store.save_review_state(STEP_ID, STEP_HASH, digest(payload), candidate)
        for candidate in (left, right, state, left)
    ]))
    entry = await store.load_step(STEP_ID, STEP_HASH)
    assert set(entry["review_state"]["scopes"]) == {"guided", "transfer"}
    assert entry["review_state"]["correction_used"] is True
    assert entry["review_state_hash"] == digest(entry["review_state"])
    assert entry["preflight_passed"] is False
    assert job.result_json == {"ready_lesson_count": 0}
    entry["review_state"]["scopes"].clear()
    assert len((await store.load_step(STEP_ID, STEP_HASH))["review_state"]["scopes"]) == 2
    assert db.transactions == len(db.sessions)


@pytest.mark.asyncio
async def test_known_negative_survives_older_success_callback_and_cannot_be_approved():
    _, _, store, payload = await setup()
    accepted = review_state(payload)
    assert await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), accepted)
    assert await store.save_package(STEP_ID, STEP_HASH, payload, preflight_passed=True)
    negative = copy.deepcopy(accepted)
    negative["rejection"] = {
        "unavailable": True,
        "issues": [{"target": "package", "description": "A prior reviewer returned an invalid negative diagnosis."}],
    }
    assert await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), negative)
    assert await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), accepted)
    entry = await store.load_step(STEP_ID, STEP_HASH)
    assert entry["review_state"]["rejection"] == negative["rejection"]
    assert entry["preflight_passed"] is False
    assert not await store.save_package(STEP_ID, STEP_HASH, payload, preflight_passed=True)


@pytest.mark.asyncio
async def test_retry_recovers_review_and_stale_job_or_package_cannot_write():
    db, old, store, payload = await setup()
    state = with_scope(review_state(payload), "guided", "n1")
    assert await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), state)
    old.status = "failed"
    current = db.new_job()
    resumed = db.store(current)
    assert (await resumed.load_step(STEP_ID, STEP_HASH))["review_state"]["scopes"]
    assert not await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), state)
    assert await resumed.save_package(STEP_ID, STEP_HASH, payload)
    changed = copy.deepcopy(payload)
    changed["workbook"]["activities"][0]["worked_solution"] += " This private correction needs a fresh review."
    assert await resumed.save_package(
        STEP_ID, STEP_HASH, changed, expected_package_hash=digest(payload),
    )
    entry = await resumed.load_step(STEP_ID, STEP_HASH)
    assert "review_state" not in entry and "review_state_hash" not in entry
    assert not await resumed.save_review_state(STEP_ID, STEP_HASH, digest(payload), state)


@pytest.mark.asyncio
async def test_incompatible_identity_or_conflicting_scope_does_not_replace_success():
    _, _, store, payload = await setup()
    state = with_scope(review_state(payload), "guided", "n1")
    assert await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), state)
    incompatible = copy.deepcopy(state)
    incompatible["input_hash"] = digest("changed outline/context")
    incompatible["identity_hash"] = digest({
        key: incompatible[key] for key in ("package_hash", "input_hash", "contract_hash")
    })
    assert not await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), incompatible)
    conflict = with_scope(review_state(payload), "guided", "n2")
    assert not await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), conflict)
    assert (await store.load_step(STEP_ID, STEP_HASH))["review_state"]["scopes"]["guided"]["claim_ids"] == ["n1"]


@pytest.mark.asyncio
async def test_invalidation_is_compare_and_swap_and_same_package_save_retains_review():
    _, _, store, payload = await setup()
    state = review_state(payload)
    assert await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), state)
    old = await store.load_step(STEP_ID, STEP_HASH)
    assert await store.save_package(STEP_ID, STEP_HASH, payload)
    assert (await store.load_step(STEP_ID, STEP_HASH))["review_state"] == old["review_state"]
    newer = with_scope(state, "guided", "n1")
    assert await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), newer)
    assert not await store.clear_review_state(STEP_ID, STEP_HASH, digest(payload), old["review_state_hash"])
    latest = await store.load_step(STEP_ID, STEP_HASH)
    assert await store.clear_review_state(STEP_ID, STEP_HASH, digest(payload), latest["review_state_hash"])
    assert "review_state" not in (await store.load_step(STEP_ID, STEP_HASH))


@pytest.mark.asyncio
@pytest.mark.parametrize("corruption", ["hash", "identity", "package", "partial_keys"])
async def test_corrupt_review_is_a_review_miss_without_erasing_saved_package(corruption):
    _, job, store, payload = await setup()
    state = review_state(payload)
    assert await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), state)
    assert await store.save_package(STEP_ID, STEP_HASH, payload, preflight_passed=True)
    entry = job.private_checkpoint_json["steps"][STEP_ID]
    if corruption == "hash":
        entry["review_state_hash"] = digest("corrupt")
    elif corruption == "partial_keys":
        entry.pop("review_state_hash")
    else:
        entry["review_state"]["identity_hash" if corruption == "identity" else "package_hash"] = digest("corrupt")
        entry["review_state_hash"] = digest(entry["review_state"])
    restored = await store.load_step(STEP_ID, STEP_HASH)
    assert restored["package"] == payload
    assert "review_state" not in restored and "review_state_hash" not in restored
    assert restored["preflight_passed"] is False


@pytest.mark.asyncio
async def test_malformed_caller_state_is_rejected_before_any_write():
    db, _, store, payload = await setup()
    state = review_state(payload)
    state["unexpected_private_field"] = "must not persist"
    count = db.transactions
    with pytest.raises(ValueError):
        await store.save_review_state(STEP_ID, STEP_HASH, digest(payload), state)
    assert db.transactions == count


@pytest.mark.asyncio
@pytest.mark.skipif(not os.getenv("PRIVATE_CHECKPOINT_TEST_DATABASE_URL"),
                    reason="Requires an explicitly selected disposable PostgreSQL database")
async def test_postgresql_review_merges_negative_retention_supersession_and_clear_cas():
    """Independent DB sessions contend on real rows in a unique synthetic schema."""
    from sqlalchemy import select, text
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    from app.models.plan import PlanItem

    schema = "review_checkpoint_test_" + uuid4().hex
    engine = create_async_engine(
        os.environ["PRIVATE_CHECKPOINT_TEST_DATABASE_URL"],
        connect_args={"options": f"-csearch_path={schema}"}, pool_size=10,
    )
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    user_id, plan_id, item_id, job_id = (str(uuid4()) for _ in range(4))

    def store_for(identity):
        return PrivateGenerationCheckpointStore(
            job_id=identity, plan_item_id=item_id, user_id=user_id,
            input_hash=digest("review test inputs"), validation_identity={"review_version": 20},
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
        store = store_for(job_id)
        payload = package()
        state = review_state(payload)
        assert await store.save_package(STEP_ID, STEP_HASH, payload)
        assert all(await asyncio.gather(*[
            store.save_review_state(STEP_ID, STEP_HASH, digest(payload), candidate)
            for candidate in (with_scope(state, "guided", "n1"),
                              with_scope(state, "transfer", "n2"), state)
        ]))
        assert await store.save_package(STEP_ID, STEP_HASH, payload, preflight_passed=True)
        negative = copy.deepcopy(state)
        negative["rejection"] = {"unavailable": True, "issues": [
            {"target": "package", "description": "A known negative review remains unavailable and must be preserved."},
        ]}
        negative["correction_used"] = True
        assert all(await asyncio.gather(*[
            store.save_review_state(STEP_ID, STEP_HASH, digest(payload), candidate)
            for candidate in (negative, state, with_scope(state, "guided", "n1"))
        ]))
        saved = await store.load_step(STEP_ID, STEP_HASH)
        assert saved["review_state"]["rejection"] == negative["rejection"]
        assert saved["review_state"]["correction_used"] is True
        assert set(saved["review_state"]["scopes"]) == {"guided", "transfer"}
        assert saved["preflight_passed"] is False

        successor_id = str(uuid4())
        async with sessions() as session:
            async with session.begin():
                await session.execute(select(PlanItem.id).where(PlanItem.id == item_id).with_for_update(of=PlanItem))
                late_save = asyncio.create_task(store.save_review_state(
                    STEP_ID, STEP_HASH, digest(payload), negative,
                ))
                with pytest.raises(asyncio.TimeoutError):
                    await asyncio.wait_for(asyncio.shield(late_save), timeout=0.05)
                await session.execute(text("UPDATE plan_item_detail_jobs SET status='failed' WHERE id=:id"),
                                      {"id": job_id})
                await session.execute(text("""
                    INSERT INTO plan_item_detail_jobs (id, plan_item_id, user_id, status)
                    VALUES (:id, :item_id, :user_id, 'running')
                """), {"id": successor_id, "item_id": item_id, "user_id": user_id})
        assert await asyncio.wait_for(late_save, timeout=5) is False
        resumed = store_for(successor_id)
        restored = await resumed.load_step(STEP_ID, STEP_HASH)
        assert restored["review_state"] == saved["review_state"]
        assert not await resumed.clear_review_state(STEP_ID, STEP_HASH, digest(payload), digest("stale"))
        assert await resumed.clear_review_state(STEP_ID, STEP_HASH, digest(payload), restored["review_state_hash"])
        cleared = await resumed.load_step(STEP_ID, STEP_HASH)
        assert "review_state" not in cleared and cleared["package"] == payload
        assert cleared["preflight_passed"] is False
        async with sessions() as session:
            rows = (await session.execute(text("SELECT result_json FROM plan_item_detail_jobs"))).all()
        assert all(row[0] is None for row in rows)
    finally:
        # Only this test's randomly named schema and synthetic rows are removed.
        async with engine.begin() as connection:
            await connection.execute(text(f"DROP SCHEMA IF EXISTS {schema} CASCADE"))
        await engine.dispose()
