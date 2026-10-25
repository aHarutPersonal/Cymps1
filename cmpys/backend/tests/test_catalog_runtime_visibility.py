"""Focused runtime visibility tests for personalized catalog lessons."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.models.curriculum import (
    AssignmentStatus,
    CurriculumSkillStatus,
    PersonalizedLessonStatus,
    VersionStatus,
)
from app.services.curriculum.hashing import sha256_json
from app.services.planning import catalog_lessons as catalog
from app.services.planning.catalog_lessons import (
    catalog_details_are_personalized_and_ready,
    catalog_details_are_ready_in_database,
    invalidate_catalog_version_dependents,
)


class _ScalarResult:
    def __init__(self, values: list[object]) -> None:
        self._values = values

    def scalars(self) -> _ScalarResult:
        return self

    def all(self) -> list[object]:
        return self._values


class _SingleResult:
    def __init__(self, value: object) -> None:
        self._value = value

    def scalar_one_or_none(self) -> object:
        return self._value


def _catalog_details(*version_ids: str) -> dict:
    steps = [
        {
            "id": f"step-{index}",
            "title": f"Session {index}",
            "personalized_lesson_version_id": version_id,
        }
        for index, version_id in enumerate(version_ids, start=1)
    ]
    return {
        "steps": steps,
        "_generation": {
            "content_origin": "catalog_personalized",
            "status": "ready",
            "personalization_status": "ready",
            "personalized_lesson_version_id": version_ids[0] if version_ids else None,
            "personalized_lesson_version_ids": list(version_ids),
        },
    }


def _technique_manifest() -> list[dict]:
    return [
        {
            "technique_key": "retrieval_practice",
            "version_id": "technique-version-1",
            "version_number": 1,
            "content_hash": "a" * 64,
            "source_hash": "b" * 64,
        }
    ]


def _technique_row(*, revoked: bool = False) -> SimpleNamespace:
    return SimpleNamespace(
        id="technique-version-1",
        technique_key="retrieval_practice",
        version_number=1,
        content_hash="a" * 64,
        source_hash="b" * 64,
        status=VersionStatus.PUBLISHED,
        revoked_at=object() if revoked else None,
    )


def _canonical_version(version_id: str = "canonical-version-1") -> SimpleNamespace:
    manifest = _technique_manifest()
    retrieval = {
        "technique_version_manifest": manifest,
        "technique_version_manifest_hash": sha256_json(manifest),
    }
    return SimpleNamespace(
        id=version_id,
        module_id="module-1",
        status=VersionStatus.PUBLISHED,
        revoked_at=None,
        revocation_reason=None,
        retrieval_metadata_json=retrieval,
        retrieval_metadata_hash=sha256_json(retrieval),
    )


def _stored_version(version_id: str, delivered_step: dict) -> SimpleNamespace:
    stored_step = dict(delivered_step)
    stored_step.pop("personalized_lesson_version_id", None)
    content = {"step": stored_step}
    learner_snapshot = {"current_capability": "reads a balance sheet"}
    mentor_snapshot = {"mentor_id": None, "claims": []}
    return SimpleNamespace(
        id=version_id,
        status=PersonalizedLessonStatus.READY,
        revoked_at=None,
        model_name="gemini-quality",
        module_version_id="canonical-version-1",
        content_json=content,
        content_hash=catalog._content_hash(content),
        learner_state_snapshot_json=learner_snapshot,
        learner_state_hash=catalog._content_hash(learner_snapshot),
        mentor_evidence_snapshot_json=mentor_snapshot,
        mentor_evidence_hash=catalog._content_hash(mentor_snapshot),
    )


@pytest.mark.parametrize(
    ("details", "expected"),
    [
        (None, False),
        ({}, True),
        ({"_generation": {"content_origin": "bespoke"}}, True),
        ({"_generation": {"content_origin": "catalog"}}, False),
        ({"_generation": {"content_origin": "catalog_canonical"}}, False),
        (
            {
                "_generation": {
                    "content_origin": "catalog_personalized",
                    "status": "generating",
                    "personalization_status": "ready",
                    "personalized_lesson_version_id": "version-1",
                }
            },
            False,
        ),
        (
            {
                "_generation": {
                    "content_origin": "catalog_personalized",
                    "status": "ready",
                    "personalization_status": "ready",
                    "personalized_lesson_version_id": None,
                }
            },
            False,
        ),
        (_catalog_details("version-1"), True),
    ],
)
def test_catalog_details_require_a_ready_personalized_derivative(
    details: object,
    expected: bool,
) -> None:
    assert catalog_details_are_personalized_and_ready(details) is expected


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("details", "expected"),
    [
        ({"steps": [{"id": "legacy-step"}]}, True),
        ({"_generation": {"content_origin": "bespoke"}}, True),
        ({"_generation": {"content_origin": "catalog_canonical"}}, False),
    ],
)
async def test_database_visibility_preserves_legacy_bespoke_and_rejects_canonical(
    details: dict,
    expected: bool,
) -> None:
    db = AsyncMock()

    assert await catalog_details_are_ready_in_database(db, details) is expected
    db.execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_database_visibility_requires_every_ready_version_and_assignment() -> (
    None
):
    details = _catalog_details("version-1", "version-2")
    versions = [
        _stored_version(version_id, step)
        for version_id, step in zip(
            ("version-1", "version-2"),
            details["steps"],
            strict=True,
        )
    ]
    db = AsyncMock()
    db.execute.side_effect = [
        _ScalarResult(versions),
        _ScalarResult([_canonical_version()]),
        _ScalarResult([_technique_row()]),
        _ScalarResult(["version-1", "version-2"]),
    ]

    assert await catalog_details_are_ready_in_database(
        db,
        details,
        user_id="user-1",
        plan_item_id="item-1",
    )
    assert db.execute.await_count == 4

    version_query = str(db.execute.await_args_list[0].args[0])
    assert "personalized_lesson_versions.status" in version_query
    assert "personalized_lesson_versions.revoked_at IS NULL" in version_query
    assert "personalized_lesson_versions.model_name IS NOT NULL" in version_query
    assert "personalized_lesson_versions.user_id" in version_query
    assignment_query = str(db.execute.await_args_list[3].args[0])
    assert "plan_lesson_assignments.status IN" in assignment_query


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "corrupted_field",
    ["content_hash", "learner_state_hash", "mentor_evidence_hash"],
)
async def test_database_visibility_recomputes_persisted_integrity_hashes(
    corrupted_field: str,
) -> None:
    details = _catalog_details("version-1")
    version = _stored_version("version-1", details["steps"][0])
    setattr(version, corrupted_field, "0" * 64)
    db = AsyncMock()
    db.execute.return_value = _ScalarResult([version])

    assert not await catalog_details_are_ready_in_database(db, details)
    assert db.execute.await_count == 1


@pytest.mark.asyncio
async def test_database_visibility_rejects_terminal_assignment_history() -> None:
    details = _catalog_details("version-1")
    version = _stored_version("version-1", details["steps"][0])
    db = AsyncMock()
    db.execute.side_effect = [
        _ScalarResult([version]),
        _ScalarResult([_canonical_version()]),
        _ScalarResult([_technique_row()]),
        # PostgreSQL filters a SKIPPED/REPLACED row out via the visibility
        # predicate, leaving no active assignment for the rendered artifact.
        _ScalarResult([]),
    ]

    assert not await catalog_details_are_ready_in_database(
        db,
        details,
        plan_item_id="item-1",
    )
    assignment_query = str(db.execute.await_args_list[3].args[0])
    assert "plan_lesson_assignments.status IN" in assignment_query


@pytest.mark.asyncio
@pytest.mark.parametrize("filtered_reason", ["missing", "revoked", "model_name"])
async def test_database_visibility_rejects_any_version_filtered_by_safety_predicates(
    filtered_reason: str,
) -> None:
    details = _catalog_details("version-1", "version-2")
    visible_version = _stored_version("version-1", details["steps"][0])
    db = AsyncMock()
    # PostgreSQL omits the second row for each of these cases: no matching ID,
    # revoked_at is set, or model_name is NULL. The runtime must then reject the
    # complete artifact instead of exposing only the surviving session.
    db.execute.return_value = _ScalarResult([visible_version])

    assert not await catalog_details_are_ready_in_database(db, details)

    version_query = str(db.execute.await_args.args[0])
    assert "personalized_lesson_versions.id IN" in version_query
    if filtered_reason == "revoked":
        assert "personalized_lesson_versions.revoked_at IS NULL" in version_query
    if filtered_reason == "model_name":
        assert "personalized_lesson_versions.model_name IS NOT NULL" in version_query


@pytest.mark.asyncio
async def test_database_visibility_allows_lesson_with_no_mentor_evidence() -> None:
    details = _catalog_details("version-1")
    version = _stored_version("version-1", details["steps"][0])
    db = AsyncMock()
    db.execute.side_effect = [
        _ScalarResult([version]),
        _ScalarResult([_canonical_version()]),
        _ScalarResult([_technique_row()]),
    ]

    assert await catalog_details_are_ready_in_database(db, details)
    assert db.execute.await_count == 3


@pytest.mark.asyncio
async def test_database_visibility_rejects_omitted_relevant_mentor_evidence() -> None:
    details = _catalog_details("version-1")
    version = _stored_version("version-1", details["steps"][0])
    version.mentor_evidence_snapshot_json = {
        "mentor_id": "idol-1",
        "claims": [{"evidence_id": "evidence-1"}],
    }
    version.mentor_evidence_hash = catalog._content_hash(
        version.mentor_evidence_snapshot_json
    )
    db = AsyncMock()
    db.execute.side_effect = [
        _ScalarResult([version]),
        _ScalarResult([_canonical_version()]),
        _ScalarResult([_technique_row()]),
    ]

    assert not await catalog_details_are_ready_in_database(db, details)


@pytest.mark.asyncio
async def test_database_visibility_fails_closed_after_technique_revocation() -> None:
    details = _catalog_details("version-1")
    version = _stored_version("version-1", details["steps"][0])
    db = AsyncMock()
    # The published/non-revoked SQL predicates filter the revoked technique out.
    db.execute.side_effect = [
        _ScalarResult([version]),
        _ScalarResult([_canonical_version()]),
        _ScalarResult([]),
    ]

    assert not await catalog_details_are_ready_in_database(db, details)
    technique_query = str(db.execute.await_args_list[2].args[0])
    assert "learning_technique_versions.status" in technique_query
    assert "learning_technique_versions.revoked_at IS NULL" in technique_query


@pytest.mark.asyncio
async def test_database_visibility_rejects_missing_or_revoked_mentor_evidence() -> None:
    details = _catalog_details("version-1")
    details["steps"][0]["used_mentor_evidence_ids"] = ["evidence-1"]
    version = _stored_version("version-1", details["steps"][0])
    version.content_json["personalization"] = {"mentor_evidence_ids": ["evidence-1"]}
    version.mentor_evidence_snapshot_json = {
        "mentor_id": "idol-1",
        "claims": [{"evidence_id": "evidence-1"}],
    }
    version.content_hash = catalog._content_hash(version.content_json)
    version.mentor_evidence_hash = catalog._content_hash(
        version.mentor_evidence_snapshot_json
    )
    db = AsyncMock()
    # A missing row and a row filtered out because it is revoked are
    # intentionally indistinguishable to the fail-closed runtime gate.
    db.execute.side_effect = [
        _ScalarResult([version]),
        _ScalarResult([_canonical_version()]),
        _ScalarResult([_technique_row()]),
        _ScalarResult([]),
    ]

    assert not await catalog_details_are_ready_in_database(db, details)
    evidence_query = str(db.execute.await_args_list[3].args[0])
    assert "mentor_evidence_claims.verification_status" in evidence_query
    assert "mentor_evidence_claims.revoked_at IS NULL" in evidence_query


@pytest.mark.asyncio
async def test_database_visibility_requires_expected_mentor_owner() -> None:
    details = _catalog_details("version-1")
    details["steps"][0]["used_mentor_evidence_ids"] = ["evidence-1"]
    version = _stored_version("version-1", details["steps"][0])
    version.content_json["personalization"] = {"mentor_evidence_ids": ["evidence-1"]}
    version.mentor_evidence_snapshot_json = {
        "mentor_id": "idol-1",
        "claims": [{"evidence_id": "evidence-1"}],
    }
    version.content_hash = catalog._content_hash(version.content_json)
    version.mentor_evidence_hash = catalog._content_hash(
        version.mentor_evidence_snapshot_json
    )
    wrong_owner = SimpleNamespace(id="evidence-1", idol_id="idol-2")
    db = AsyncMock()
    db.execute.side_effect = [
        _ScalarResult([version]),
        _ScalarResult([_canonical_version()]),
        _ScalarResult([_technique_row()]),
        _ScalarResult([wrong_owner]),
    ]

    assert not await catalog_details_are_ready_in_database(db, details)

    current_owner = SimpleNamespace(id="evidence-1", idol_id="idol-1")
    current_db = AsyncMock()
    current_db.execute.side_effect = [
        _ScalarResult([version]),
        _ScalarResult([_canonical_version()]),
        _ScalarResult([_technique_row()]),
        _ScalarResult([current_owner]),
    ]
    assert await catalog_details_are_ready_in_database(current_db, details)


@pytest.mark.asyncio
async def test_invalidation_revokes_lessons_skips_active_assignments_and_plan_details(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    lessons = [
        SimpleNamespace(
            id=f"version-{index}",
            status=PersonalizedLessonStatus.READY,
            revoked_at=None,
            revocation_reason=None,
        )
        for index in (1, 2)
    ]
    plan_item = SimpleNamespace(
        id="item-1",
        details_json={
            "steps": [{"id": "step-1"}],
            "_generation": {
                "content_origin": "catalog_personalized",
                "status": "ready",
                "personalization_status": "ready",
            },
        },
    )
    assignments = [
        SimpleNamespace(
            id=f"assignment-{index}",
            plan_id="plan-1",
            plan_item_id="item-1",
            personalized_lesson_version_id=f"version-{min(index, 2)}",
            status=status,
            plan_item=plan_item,
        )
        for index, status in enumerate(
            (
                AssignmentStatus.SCHEDULED,
                AssignmentStatus.AVAILABLE,
                AssignmentStatus.IN_PROGRESS,
                AssignmentStatus.COMPLETED,
            ),
            start=1,
        )
    ]
    db = AsyncMock()
    db.execute.side_effect = [
        _ScalarResult(lessons),
        _ScalarResult([plan_item]),
    ]
    mutation_lock = AsyncMock(return_value=assignments)
    monkeypatch.setattr(
        catalog,
        "lock_catalog_assignments_for_mutation",
        mutation_lock,
    )

    result = await invalidate_catalog_version_dependents(
        db,
        module_version_id="module-version-1",
        reason="source was retracted",
    )

    assert result == {
        "personalized_versions": 2,
        "assignments": 4,
        "plan_items": 1,
    }
    assert all(lesson.status == PersonalizedLessonStatus.REVOKED for lesson in lessons)
    assert all(lesson.revoked_at is not None for lesson in lessons)
    assert all(lesson.revocation_reason == "source was retracted" for lesson in lessons)
    assert [assignment.status for assignment in assignments] == [
        AssignmentStatus.SKIPPED,
        AssignmentStatus.SKIPPED,
        AssignmentStatus.SKIPPED,
        AssignmentStatus.COMPLETED,
    ]
    assert plan_item.details_json["steps"] == [{"id": "step-1"}]
    assert plan_item.details_json["_generation"]["status"] == "revoked"
    assert plan_item.details_json["_generation"]["personalization_status"] == "revoked"
    assert (
        plan_item.details_json["_generation"]["revocation_reason"]
        == "source was retracted"
    )
    assert plan_item.details_json["_generation"]["revoked_at"]
    db.flush.assert_awaited_once_with()
    mutation_lock.assert_awaited_once_with(
        db,
        personalized_lesson_version_ids=["version-1", "version-2"],
    )


@pytest.mark.asyncio
async def test_revoke_locks_module_before_version_and_preserves_newer_publication(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    module = SimpleNamespace(
        id="module-1",
        status=CurriculumSkillStatus.ACTIVE,
        current_published_version_id="newer-version",
    )
    target = _canonical_version("target-version")
    db = AsyncMock()
    db.execute.side_effect = [
        _SingleResult(target),
        _ScalarResult([_technique_row()]),
        _SingleResult(module),
        _SingleResult(target),
    ]
    invalidate = AsyncMock(
        return_value={
            "personalized_versions": 0,
            "assignments": 0,
            "plan_items": 0,
        }
    )
    monkeypatch.setattr(catalog, "invalidate_catalog_version_dependents", invalidate)

    result = await catalog.revoke_canonical_module_version_and_invalidate(
        db,
        module_version_id=target.id,
        reason="source was retracted",
    )

    statements = [str(call.args[0]) for call in db.execute.await_args_list]
    assert "FROM canonical_module_versions" in statements[0]
    assert "FOR UPDATE" not in statements[0]
    assert "FROM learning_technique_versions" in statements[1]
    assert "FOR UPDATE" in statements[1]
    assert "FROM canonical_modules" in statements[2]
    assert "FOR UPDATE" in statements[2]
    assert "FROM canonical_module_versions" in statements[3]
    assert "FOR UPDATE" in statements[3]
    assert module.current_published_version_id == "newer-version"
    assert module.status is CurriculumSkillStatus.ACTIVE
    assert target.status is VersionStatus.REVOKED
    assert target.revoked_at is not None
    assert target.revocation_reason == "source was retracted"
    invalidate.assert_awaited_once_with(
        db,
        module_version_id=target.id,
        reason="source was retracted",
    )
    assert result == {
        "personalized_versions": 0,
        "assignments": 0,
        "plan_items": 0,
    }


@pytest.mark.asyncio
async def test_revoke_flushes_current_pointer_detach_before_version_transition(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    module = SimpleNamespace(
        id="module-1",
        status=CurriculumSkillStatus.ACTIVE,
        current_published_version_id="target-version",
    )
    target = _canonical_version("target-version")
    flush_snapshots: list[tuple[object, object]] = []

    async def capture_flush() -> None:
        flush_snapshots.append((module.current_published_version_id, target.status))

    db = AsyncMock()
    db.execute.side_effect = [
        _SingleResult(target),
        _ScalarResult([_technique_row()]),
        _SingleResult(module),
        _SingleResult(target),
    ]
    db.flush.side_effect = capture_flush
    monkeypatch.setattr(
        catalog,
        "invalidate_catalog_version_dependents",
        AsyncMock(
            return_value={
                "personalized_versions": 0,
                "assignments": 0,
                "plan_items": 0,
            }
        ),
    )

    await catalog.revoke_canonical_module_version_and_invalidate(
        db,
        module_version_id=target.id,
        reason="source was retracted",
    )

    assert flush_snapshots == [
        (None, VersionStatus.PUBLISHED),
        (None, VersionStatus.REVOKED),
    ]
    assert module.status is CurriculumSkillStatus.RETIRED


@pytest.mark.asyncio
async def test_revoke_refreshes_locked_version_and_preserves_existing_audit_metadata(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    pre_version = _canonical_version("target-version")
    locked_version = _canonical_version("target-version")
    existing_revoked_at = object()
    locked_version.status = VersionStatus.REVOKED
    locked_version.revoked_at = existing_revoked_at
    locked_version.revocation_reason = "first verified reason"
    module = SimpleNamespace(
        id="module-1",
        status=CurriculumSkillStatus.RETIRED,
        current_published_version_id=None,
    )
    db = AsyncMock()
    db.execute.side_effect = [
        _SingleResult(pre_version),
        _ScalarResult([_technique_row()]),
        _SingleResult(module),
        _SingleResult(locked_version),
    ]
    monkeypatch.setattr(
        catalog,
        "invalidate_catalog_version_dependents",
        AsyncMock(
            return_value={
                "personalized_versions": 0,
                "assignments": 0,
                "plan_items": 0,
            }
        ),
    )

    await catalog.revoke_canonical_module_version_and_invalidate(
        db,
        module_version_id="target-version",
        reason="second competing reason",
    )

    locked_statement = db.execute.await_args_list[3].args[0]
    assert locked_statement.get_execution_options()["populate_existing"] is True
    assert locked_version.revoked_at is existing_revoked_at
    assert locked_version.revocation_reason == "first verified reason"
