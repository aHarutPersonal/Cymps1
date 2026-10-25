"""Private package pieces survive retries without granting public readiness."""
import asyncio
import copy
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from app.services.planning.lesson_package import LessonPackage, digest
from app.services.planning.package_builder import LessonPackageSeed, LessonPackageActivity, validate_package_parts
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import structured_activity_fixture
from tests.test_private_generation_checkpoint import Database, Result, STEP_ID, STEP_HASH


def parts(*completed, extra=False, title=None):
    payload = package_payload()
    guided, transfer = payload["workbook"]["activities"]
    brief_ids = ["guided", "another", "transfer"] if extra else ["guided", "transfer"]
    seed = LessonPackageSeed.model_validate({
        "workbook_title": title or payload["workbook"]["title"], "teaching_cases": [],
        "activity_briefs": [{"id": key, "kind": "transfer" if key == "transfer" else "practice",
            "scope": "Test a substantive objection to a different argument and revise it with evidence."}
            for key in brief_ids],
    }).model_dump(mode="json")
    activities = {key: LessonPackageActivity.model_validate(structured_activity_fixture({
        **(guided if key == "guided" else transfer), "id": key, "kind": "transfer" if key == "transfer" else "practice",
    })).model_dump(mode="json") for key in completed}
    return validate_package_parts({"version": 2, "seed": seed, "seed_hash": digest(seed), "activities": activities})


def assembled(snapshot):
    seed = snapshot["seed"]
    return LessonPackage.model_validate({"teaching_cases": seed["teaching_cases"], "workbook": {
        "title": seed["workbook_title"], "activities": [
            snapshot["activities"][brief["id"]] for brief in seed["activity_briefs"]
        ],
    }}).model_dump(mode="json")


@pytest.mark.asyncio
async def test_failed_job_components_resume_privately_and_complete_package_replaces_them():
    database = Database()
    old = database.new_job()
    store = database.store(old)
    seed = parts()
    assert await store.save_package_parts(STEP_ID, STEP_HASH, seed)
    assert await store.load_step(STEP_ID, STEP_HASH) is None
    assert old.result_json == {"ready_lesson_count": 0} and old.progress_percent == 0
    old.status = "failed"
    current = database.new_job()
    resumed = database.store(current)
    restored = await resumed.load_package_parts(STEP_ID, STEP_HASH)
    assert restored == seed
    restored["seed"]["workbook_title"] = "Outside mutation"
    assert await resumed.load_package_parts(STEP_ID, STEP_HASH) == seed
    finished = parts("guided", "transfer")
    assert await resumed.save_package_parts(STEP_ID, STEP_HASH, finished,
                                             expected_seed_hash=seed["seed_hash"])
    assert old.private_checkpoint_json["package_parts"][STEP_ID]["parts"] == seed
    assert await resumed.save_package(STEP_ID, STEP_HASH, assembled(finished), expected_parts_hash=digest(finished))
    assert not (await resumed.load_step(STEP_ID, STEP_HASH))["preflight_passed"]
    assert await resumed.load_package_parts(STEP_ID, STEP_HASH) is None
    assert STEP_ID not in current.private_checkpoint_json["package_parts"]
    assert not await resumed.save_package_parts(STEP_ID, STEP_HASH, seed)
    assert current.result_json == old.result_json == {"ready_lesson_count": 0}


@pytest.mark.asyncio
async def test_delayed_complete_promotion_cannot_replace_newer_seed_or_component_snapshot():
    database = Database()
    job = database.new_job()
    store = database.store(job)
    first = parts("guided", "transfer")
    second = parts(title="Newer package seed")
    assert await store.save_package_parts(STEP_ID, STEP_HASH, first)
    assert await store.save_package_parts(STEP_ID, STEP_HASH, second,
                                          expected_seed_hash=first["seed_hash"])
    assert not await store.save_package(STEP_ID, STEP_HASH, assembled(first))
    assert not await store.save_package(STEP_ID, STEP_HASH, assembled(first),
                                        expected_parts_hash=digest(first))
    assert await store.load_step(STEP_ID, STEP_HASH) is None
    assert await store.load_package_parts(STEP_ID, STEP_HASH) == second

    complete = parts("guided", "transfer", title="Newer package seed")
    assert await store.save_package_parts(STEP_ID, STEP_HASH, complete,
                                          expected_seed_hash=second["seed_hash"])
    assert not await store.save_package(STEP_ID, STEP_HASH, assembled(complete),
                                        expected_parts_hash=digest(second))
    assert await store.save_package(STEP_ID, STEP_HASH, assembled(complete),
                                    expected_parts_hash=digest(complete))
    assert (await store.load_step(STEP_ID, STEP_HASH))["package"] == assembled(complete)


@pytest.mark.asyncio
async def test_complete_promotion_requires_all_components_and_exact_canonical_assembly():
    database = Database()
    job = database.new_job()
    store = database.store(job)
    seed = parts()
    complete = parts("guided", "transfer")
    assert await store.save_package_parts(STEP_ID, STEP_HASH, seed)
    assert not await store.save_package(STEP_ID, STEP_HASH, assembled(complete),
                                        expected_parts_hash=digest(seed))
    guided_only = parts("guided")
    assert await store.save_package_parts(STEP_ID, STEP_HASH, guided_only)
    assert not await store.save_package(STEP_ID, STEP_HASH, assembled(complete),
                                        expected_parts_hash=digest(guided_only))
    assert await store.save_package_parts(STEP_ID, STEP_HASH, complete)
    mismatched = assembled(complete)
    mismatched["workbook"]["title"] = "Uncheckpointed replacement"
    assert not await store.save_package(STEP_ID, STEP_HASH, mismatched,
                                        expected_parts_hash=digest(complete))
    assert await store.load_package_parts(STEP_ID, STEP_HASH) == complete
    assert await store.load_step(STEP_ID, STEP_HASH) is None


@pytest.mark.asyncio
async def test_newer_completed_predecessor_supersedes_older_components_across_three_jobs():
    database = Database()
    first = database.new_job()
    seed = parts()
    assert await database.store(first).save_package_parts(STEP_ID, STEP_HASH, seed)
    first.status = "failed"
    second = database.new_job()
    second_store = database.store(second)
    complete = parts("guided", "transfer")
    assert await second_store.save_package_parts(STEP_ID, STEP_HASH, complete,
                                                expected_seed_hash=seed["seed_hash"])
    assert await second_store.save_package(STEP_ID, STEP_HASH, assembled(complete),
                                          expected_parts_hash=digest(complete), preflight_passed=True)
    assert await second_store.save_sections(STEP_ID, STEP_HASH, digest(assembled(complete)),
                                           {"core_framework": "Already completed private prose"})
    second.status = "failed"
    third = database.new_job()
    third_store = database.store(third)
    saved = await third_store.load_step(STEP_ID, STEP_HASH)
    assert saved["package"] == assembled(complete)
    assert await third_store.load_package_parts(STEP_ID, STEP_HASH) is None
    assert await third_store.save_package(STEP_ID, STEP_HASH, saved["package"],
                                         expected_package_hash=saved["package_hash"])
    assert (await third_store.load_step(STEP_ID, STEP_HASH))["sections"] == saved["sections"]
    assert (await third_store.load_step(STEP_ID, STEP_HASH))["preflight_passed"] is True


@pytest.mark.asyncio
async def test_newer_parts_do_not_resurrect_an_older_completed_contract():
    database = Database()
    old = database.new_job()
    old_package = assembled(parts("guided", "transfer"))
    assert await database.store(old).save_package(STEP_ID, STEP_HASH, old_package)
    old.status = "failed"
    newer = database.new_job()
    snapshot = parts("guided", "transfer", title="Changed current contract")
    assert await database.store(newer).save_package_parts(STEP_ID, STEP_HASH, snapshot)
    assert await database.store(newer).load_step(STEP_ID, STEP_HASH) is None
    newer.status = "failed"
    resumed = database.store(database.new_job())
    assert await resumed.load_step(STEP_ID, STEP_HASH) is None
    assert await resumed.load_package_parts(STEP_ID, STEP_HASH) == snapshot
    assert not await resumed.save_package(STEP_ID, STEP_HASH, old_package,
                                         expected_package_hash=digest(old_package))
    assert await resumed.save_package(STEP_ID, STEP_HASH, assembled(snapshot),
                                     expected_parts_hash=digest(snapshot))


@pytest.mark.asyncio
async def test_repair_and_preflight_saves_compare_prior_package_without_losing_newer_progress():
    database = Database()
    job = database.new_job()
    store = database.store(job)
    first = assembled(parts("guided", "transfer"))
    second = copy.deepcopy(first)
    second["workbook"]["activities"][0]["worked_solution"]["steps"][0]["explanation"] += " A corrected private rationale."
    assert await store.save_package(STEP_ID, STEP_HASH, first)
    assert not await store.save_package(STEP_ID, STEP_HASH, second)
    assert await store.save_package(STEP_ID, STEP_HASH, second, expected_package_hash=digest(first))
    assert await store.save_package(STEP_ID, STEP_HASH, second, preflight_passed=True,
                                    expected_package_hash=digest(second))
    assert await store.save_sections(STEP_ID, STEP_HASH, digest(second), {"core_framework": "New prose"})
    assert not await store.save_package(STEP_ID, STEP_HASH, first, preflight_passed=True,
                                        expected_package_hash=digest(first))
    assert not await store.save_package(STEP_ID, STEP_HASH, second, preflight_passed=True,
                                        expected_package_hash=digest(first))
    assert await store.save_package(STEP_ID, STEP_HASH, second)  # Identical resume is idempotent.
    saved = await store.load_step(STEP_ID, STEP_HASH)
    assert saved["package"] == second and saved["preflight_passed"] is True
    assert saved["sections"] == {"core_framework": "New prose"}


@pytest.mark.asyncio
async def test_concurrent_component_snapshots_merge_without_losing_completed_work():
    database = Database()
    job = database.new_job()
    store = database.store(job)
    initial = parts(extra=True)
    assert await store.save_package_parts(STEP_ID, STEP_HASH, initial)
    assert all(await asyncio.gather(*(
        store.save_package_parts(STEP_ID, STEP_HASH, parts(key, extra=True),
                                 expected_seed_hash=initial["seed_hash"])
        for key in ("guided", "another", "transfer")
    )))
    assert set((await store.load_package_parts(STEP_ID, STEP_HASH))["activities"]) == {"guided", "another", "transfer"}
    assert await store.save_package_parts(STEP_ID, STEP_HASH, initial)  # Late seed-only callback is additive.
    assert set((await store.load_package_parts(STEP_ID, STEP_HASH))["activities"]) == {"guided", "another", "transfer"}
    assert len({id(session) for session in database.sessions}) == len(database.sessions)
    assert database.transactions == len(database.sessions)


@pytest.mark.asyncio
async def test_conflicting_activity_is_rejected_and_seed_replacement_uses_compare_and_set():
    database = Database()
    job = database.new_job()
    store = database.store(job)
    first = parts("guided", "transfer")
    assert await store.save_package_parts(STEP_ID, STEP_HASH, first)
    conflicting = copy.deepcopy(first)
    conflicting["activities"]["transfer"]["worked_solution"]["steps"][0]["explanation"] += " A conflicting late replacement."
    assert not await store.save_package_parts(STEP_ID, STEP_HASH, conflicting)
    second = parts(title="A corrected seed with a different scope")
    assert not await store.save_package_parts(STEP_ID, STEP_HASH, second)
    assert not await store.save_package_parts(STEP_ID, STEP_HASH, second, expected_seed_hash=digest("unknown"))
    assert await store.save_package_parts(STEP_ID, STEP_HASH, second, expected_seed_hash=first["seed_hash"])
    assert not await store.save_package_parts(STEP_ID, STEP_HASH, first, expected_seed_hash=first["seed_hash"])
    assert await store.load_package_parts(STEP_ID, STEP_HASH) == second


@pytest.mark.asyncio
@pytest.mark.parametrize("mismatch", ["user", "item", "input", "validation", "step", "step_id"])
async def test_package_components_never_cross_scope(mismatch):
    database = Database()
    old = database.new_job()
    assert await database.store(old).save_package_parts(STEP_ID, STEP_HASH, parts())
    old.status = "failed"
    current = database.new_job()
    overrides = {}
    step_id, step_hash = STEP_ID, STEP_HASH
    if mismatch == "user": overrides["user_id"] = str(uuid4())
    elif mismatch == "item": overrides["plan_item_id"] = str(uuid4())
    elif mismatch == "input": overrides["input_hash"] = digest("changed inputs")
    elif mismatch == "validation": overrides["validation_identity"] = {"review_version": 99}
    elif mismatch == "step": step_hash = digest("changed step")
    else: step_id = "step_2"
    assert await database.store(current, **overrides).load_package_parts(step_id, step_hash) is None


@pytest.mark.asyncio
@pytest.mark.parametrize("status", ["queued", "running", "failed", "cancelled", "completed"])
async def test_superseded_component_callback_cannot_overwrite_latest_job(status):
    database = Database()
    old = database.new_job()
    store = database.store(old)
    assert await store.save_package_parts(STEP_ID, STEP_HASH, parts())
    before = copy.deepcopy(old.private_checkpoint_json)
    await database.item_lock.acquire()
    pending = asyncio.create_task(store.save_package_parts(STEP_ID, STEP_HASH, parts("guided", "transfer")))
    await asyncio.sleep(0)
    database.new_job(status=status)
    database.item_lock.release()
    assert await pending is False
    assert old.private_checkpoint_json == before
    assert await store.load_package_parts(STEP_ID, STEP_HASH) is None


@pytest.mark.asyncio
@pytest.mark.parametrize("corruption", ["digest", "seed", "activity", "extra", "identity"])
async def test_tampered_component_drafts_are_cache_misses(corruption):
    database = Database()
    job = database.new_job()
    store = database.store(job)
    assert await store.save_package_parts(STEP_ID, STEP_HASH, parts("guided", "transfer"))
    entry = job.private_checkpoint_json["package_parts"][STEP_ID]
    if corruption == "digest": entry["parts_hash"] = digest("other")
    elif corruption == "seed":
        entry["parts"]["seed_hash"] = digest("other")
        entry["parts_hash"] = digest(entry["parts"])
    elif corruption == "activity":
        entry["parts"]["activities"]["invented"] = entry["parts"]["activities"].pop("transfer")
        entry["parts_hash"] = digest(entry["parts"])
    elif corruption == "extra": entry["approved"] = True
    else: job.private_checkpoint_json["validation_identity"] = {"review_version": 99}
    assert await store.load_package_parts(STEP_ID, STEP_HASH) is None


@pytest.mark.asyncio
async def test_component_map_preserves_complete_steps_and_stays_out_of_public_job_polling():
    from app.api.v1.jobs import get_job_status
    database = Database()
    job = database.new_job()
    store = database.store(job)
    complete = LessonPackage.model_validate(package_payload()).model_dump(mode="json")
    assert await store.save_package("completed_step", STEP_HASH, complete, preflight_passed=True)
    assert await store.save_sections("completed_step", STEP_HASH, digest(complete), {"references": "Existing draft"})
    before = await store.load_step("completed_step", STEP_HASH)
    assert await store.save_package_parts(STEP_ID, STEP_HASH, parts())
    assert await store.load_step("completed_step", STEP_HASH) == before
    response = await get_job_status(job.id, SimpleNamespace(execute=AsyncMock(return_value=Result([job]))),
                                    SimpleNamespace(id=database.user_id), job_type="plan_detail")
    public = response.model_dump_json()
    assert "package_parts" not in public and "worked_solution" not in public
    assert response.results == {"ready_lesson_count": 0}


@pytest.mark.asyncio
async def test_invalid_or_oversized_parts_never_mutate_storage(monkeypatch):
    from app.services.planning import private_checkpoint
    database = Database()
    job = database.new_job()
    store = database.store(job)
    assert await store.save_package_parts(STEP_ID, STEP_HASH, parts())
    before = copy.deepcopy(job.private_checkpoint_json)
    with pytest.raises(ValueError):
        await store.save_package_parts(STEP_ID, STEP_HASH, {"partial_json": "unfinished"})
    monkeypatch.setattr(private_checkpoint, "MAX_STEP_BYTES", 100)
    with pytest.raises(ValueError):
        await store.save_package_parts(STEP_ID, STEP_HASH, parts("guided", "transfer"))
    assert job.private_checkpoint_json == before


@pytest.mark.asyncio
async def test_old_component_version_is_not_reinterpreted_or_promoted():
    database = Database()
    job = database.new_job()
    store = database.store(job)
    old = parts("guided", "transfer")
    old["version"] = 1
    before = copy.deepcopy(job.private_checkpoint_json)
    with pytest.raises(ValueError):
        await store.save_package_parts(STEP_ID, STEP_HASH, old)
    assert job.private_checkpoint_json == before
