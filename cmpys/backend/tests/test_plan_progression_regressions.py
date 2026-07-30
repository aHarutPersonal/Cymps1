"""Regression coverage for daily rhythms, week unlocks, and detail failures."""

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import select

from app.api.v1 import plans
from app.api.v1.daily_tasks import _execution_focus_week
from app.models.curriculum import AssignmentStatus
from app.models.item_detail_job import PlanItemDetailJob
from app.models.plan import PlanItem, PlanItemStatus, PlanItemType
from app.schemas.plan import DetailsStatus, ItemProgress, PlanItemUpdate
from app.services.planning.artifact_identity import (
    allocate_detail_artifact_epoch,
    artifact_job_reference_is_valid,
    artifact_job_id_from_details,
    current_artifact_job_reference_join_predicate,
    current_item_completion_artifact_status_join_predicate,
    current_item_completion_join_predicate,
    new_plan_item_detail_job,
    progress_eligible_step_ids,
    validated_lesson_materials,
    validated_lesson_steps,
)
from app.services.planning.progress import (
    compute_item_progress as compute_service_item_progress,
    compute_plan_progress,
    compute_week_progress,
)
from app.tasks import plans as plan_tasks


JOB_A = "11111111-1111-4111-8111-111111111111"
JOB_B = "22222222-2222-4222-8222-222222222222"
JOB_CURRENT = "33333333-3333-4333-8333-333333333333"
JOB_MISSING = "44444444-4444-4444-8444-444444444444"
JOB_WITH_HEX = "abcdefab-cdef-4abc-8def-abcdefabcdef"

NONCANONICAL_JOB_IDS = [
    pytest.param(JOB_WITH_HEX.upper(), id="uppercase"),
    pytest.param(JOB_WITH_HEX.replace("-", ""), id="hyphenless"),
    pytest.param(f"{{{JOB_WITH_HEX}}}", id="braced"),
]

MALFORMED_LESSON_STEPS = [
    pytest.param(None, id="null"),
    pytest.param({}, id="object"),
    pytest.param("broken", id="scalar"),
    pytest.param(7, id="number"),
    pytest.param([{"lesson_content": "substance " * 2200}], id="missing-id"),
    pytest.param(
        [{"id": "", "lesson_content": "substance " * 2200}],
        id="empty-id",
    ),
    pytest.param(
        [{"id": "   ", "lesson_content": "substance " * 2200}],
        id="whitespace-id",
    ),
    pytest.param(
        [{"id": 7, "lesson_content": "substance " * 2200}],
        id="numeric-id",
    ),
    pytest.param(
        [{"id": " padded ", "lesson_content": "substance " * 2200}],
        id="untrimmed-id",
    ),
    pytest.param(
        [{"id": "\vstep_1\v", "lesson_content": "substance " * 2200}],
        id="vertical-tab-padded-id",
    ),
    pytest.param(
        [{"id": "x" * 101, "lesson_content": "substance " * 2200}],
        id="overlong-id",
    ),
    pytest.param(
        [{"id": "step_1", "title": 7, "lesson_content": "substance " * 2200}],
        id="numeric-title",
    ),
    pytest.param(
        [
            {
                "id": "step_1",
                "resources": "broken",
                "lesson_content": "substance " * 2200,
            }
        ],
        id="scalar-resources",
    ),
    pytest.param(
        [{"id": "step_1", "substeps": 7, "lesson_content": "substance " * 2200}],
        id="numeric-substeps",
    ),
    pytest.param(
        [
            {"id": "duplicate", "lesson_content": "substance " * 2200},
            {"id": "duplicate", "lesson_content": "practice " * 2200},
        ],
        id="duplicate-id",
    ),
]

MALFORMED_LESSON_MATERIALS = [
    pytest.param("broken", id="scalar"),
    pytest.param([7], id="non-object-entry"),
    pytest.param(
        [{"title": "Source", "ideas": "broken"}],
        id="nested-ideas-scalar",
    ),
    pytest.param(
        [{"title": "Source", "ideas": [7]}],
        id="nested-ideas-entry",
    ),
]

FALSY_INVALID_TIMING_ALIAS_CASES = [
    pytest.param(
        "estimate_minutes",
        "estimateMinutes",
        invalid_value,
        id=f"snake-{case_id}",
    )
    for case_id, invalid_value in (
        ("boolean", False),
        ("empty-string", ""),
        ("empty-list", []),
        ("empty-object", {}),
    )
] + [
    pytest.param(
        "estimateMinutes",
        "estimate_minutes",
        invalid_value,
        id=f"camel-{case_id}",
    )
    for case_id, invalid_value in (
        ("boolean", False),
        ("empty-string", ""),
        ("empty-list", []),
        ("empty-object", {}),
    )
]


def _item(
    item_id: str,
    item_type: PlanItemType,
    week: int,
    *,
    status: PlanItemStatus = PlanItemStatus.NOT_STARTED,
    meta_json: dict | None = None,
) -> PlanItem:
    now = datetime.now(timezone.utc)
    return PlanItem(
        id=item_id,
        plan_id="plan-1",
        title=f"Task {item_id}",
        type=item_type,
        description="A concrete task description for regression coverage.",
        week_start=week,
        week_end=week,
        success_metric="Completed as specified",
        estimated_hours=1,
        status=status,
        progress_percent=0,
        meta_json=meta_json,
        created_at=now,
        updated_at=now,
    )


def _plan(*, completed_at: datetime | None = None) -> SimpleNamespace:
    return SimpleNamespace(
        id="plan-1",
        user_id="user-1",
        completed_at=completed_at,
    )


def test_execution_week_advances_after_week_one_missions_complete() -> None:
    items = [
        _item("mission-1", PlanItemType.PROJECT, 1),
        _item("daily-1", PlanItemType.PRACTICE, 1),
        _item("mission-2", PlanItemType.READING, 2),
        _item("daily-2", PlanItemType.HABIT, 2),
    ]

    assert _execution_focus_week(items, set(), 12) == 1
    assert _execution_focus_week(items, {"mission-1"}, 12) == 2


def test_daily_rhythms_never_gate_execution_week() -> None:
    items = [
        _item("mission-1", PlanItemType.PROJECT, 1),
        _item("practice-1", PlanItemType.PRACTICE, 1),
        _item("mission-2", PlanItemType.COURSE, 2),
    ]

    assert _execution_focus_week(items, {"mission-1"}, 12) == 2


def test_current_plan_response_hydrates_completion_records() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)

    response = plans._item_to_response(
        item,
        completed_item_ids={"mission-1"},
    )

    assert response.status.value == "completed"
    assert response.progressPercent == 100


def test_current_plan_response_does_not_fall_back_to_stale_terminal_cache() -> None:
    item = _item(
        "mission-1",
        PlanItemType.PROJECT,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100

    response = plans._item_to_response(item, completed_item_ids=set())

    assert response.status == PlanItemStatus.NOT_STARTED
    assert response.progressPercent == 0


def test_daily_item_never_uses_permanent_completion_state() -> None:
    item = _item(
        "daily-1",
        PlanItemType.PRACTICE,
        1,
        status=PlanItemStatus.COMPLETED,
    )

    response = plans._item_to_response(
        item,
        completed_item_ids={"daily-1"},
    )

    assert response.status.value == "not_started"
    assert response.progressPercent == 0


def test_plan_item_patch_contract_rejects_direct_status_and_progress_writes() -> None:
    with pytest.raises(ValidationError):
        PlanItemUpdate.model_validate({"status": "completed"})
    with pytest.raises(ValidationError):
        PlanItemUpdate.model_validate({"progressPercent": 100})

    update = PlanItemUpdate.model_validate({"notes": "Keep the worked example."})
    assert update.notes == "Keep the worked example."


@pytest.mark.asyncio
@pytest.mark.parametrize("endpoint", ["get", "patch"])
async def test_generic_item_routes_lock_and_refresh_b_before_progress(
    endpoint: str,
) -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {
        "steps": [{"id": "b_step_1"}, {"id": "b_step_2"}],
        "_generation": {"job_id": JOB_B, "status": "ready"},
    }
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=item)
    exact_progress = ItemProgress(completed_steps=1, total_steps=2, percent=50)

    async def progress_for_locked_b(*_args, **_kwargs):
        assert plans._details_generation_job_id(item) == JOB_B
        return exact_progress, False

    with (
        patch.object(plans, "_latest_active_detail_job", AsyncMock(return_value=None)),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(side_effect=progress_for_locked_b),
        ),
    ):
        if endpoint == "get":
            response = await plans.get_plan_item(
                "mission-1",
                db,
                SimpleNamespace(id="user-1"),
            )
        else:
            response = await plans.update_plan_item(
                "mission-1",
                PlanItemUpdate(notes="Keep artifact B."),
                db,
                SimpleNamespace(id="user-1"),
            )

    assert response.status == PlanItemStatus.IN_PROGRESS
    assert response.progressPercent == 50
    item_statement = db.execute.await_args_list[0].args[0]
    assert item_statement._for_update_arg is not None
    assert item_statement.get_execution_options()["populate_existing"] is True
    db.commit.assert_not_awaited()
    if endpoint == "patch":
        assert item.notes == "Keep artifact B."
        db.flush.assert_awaited_once_with()
        db.refresh.assert_awaited_once_with(item)


@pytest.mark.asyncio
@pytest.mark.parametrize("endpoint", ["get", "patch"])
@pytest.mark.parametrize(
    ("stored_plan_item_id", "stored_user_id"),
    [
        pytest.param(None, None, id="missing-job"),
        pytest.param("other-item", "user-1", id="wrong-item"),
        pytest.param("mission-1", "other-user", id="wrong-user"),
    ],
)
async def test_generic_item_routes_fail_closed_for_unowned_artifact_reference(
    endpoint: str,
    stored_plan_item_id: str | None,
    stored_user_id: str | None,
) -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": JOB_WITH_HEX, "status": "ready"},
    }
    db = AsyncMock()

    async def reference_is_owned(*_args, **kwargs):
        return (
            stored_plan_item_id is not None
            and kwargs["plan_item_id"] == stored_plan_item_id
            and kwargs["user_id"] == stored_user_id
        )

    reference_check = AsyncMock(side_effect=reference_is_owned)
    with (
        patch.object(
            plans,
            "_get_item_for_user",
            AsyncMock(return_value=item),
        ),
        patch.object(plans, "_latest_active_detail_job", AsyncMock(return_value=None)),
        patch.object(
            plans,
            "artifact_job_reference_is_valid",
            reference_check,
        ),
    ):
        if endpoint == "get":
            response = await plans.get_plan_item(
                "mission-1",
                db,
                SimpleNamespace(id="user-1"),
            )
        else:
            response = await plans.update_plan_item(
                "mission-1",
                PlanItemUpdate(notes="Keep this note."),
                db,
                SimpleNamespace(id="user-1"),
            )

    assert response.status == PlanItemStatus.NOT_STARTED
    assert response.progressPercent == 0
    assert item.status == PlanItemStatus.COMPLETED
    assert item.progress_percent == 100
    reference_check.assert_awaited_once()
    db.execute.assert_not_awaited()
    db.commit.assert_not_awaited()
    if endpoint == "patch":
        assert item.notes == "Keep this note."
        db.flush.assert_awaited_once_with()
        db.refresh.assert_awaited_once_with(item)


@pytest.mark.asyncio
@pytest.mark.parametrize("endpoint", ["get", "patch"])
async def test_generic_item_routes_count_only_ready_progressive_steps(
    endpoint: str,
) -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "step_1", "lesson_content": "ready " * 2200},
            {"id": "step_2", "lesson_content": "hidden " * 2200},
        ],
        "_generation": {
            "job_id": JOB_WITH_HEX,
            "status": "partial",
            "ready_step_ids": ["step_1"],
        },
    }
    db = AsyncMock()
    db.execute.side_effect = [
        SimpleNamespace(scalar=lambda: 1),
        _Result(scalar_one=None),
    ]

    with (
        patch.object(
            plans,
            "_get_item_for_user",
            AsyncMock(return_value=item),
        ),
        patch.object(
            plans,
            "_latest_active_detail_job",
            AsyncMock(return_value=SimpleNamespace(id=JOB_WITH_HEX)),
        ),
        patch.object(
            plans,
            "artifact_job_reference_is_valid",
            AsyncMock(return_value=True),
        ),
    ):
        if endpoint == "get":
            response = await plans.get_plan_item(
                "mission-1",
                db,
                SimpleNamespace(id="user-1"),
            )
        else:
            response = await plans.update_plan_item(
                "mission-1",
                PlanItemUpdate(notes="Keep the checkpoint."),
                db,
                SimpleNamespace(id="user-1"),
            )

    assert response.status == PlanItemStatus.IN_PROGRESS
    assert response.progressPercent == 50
    count_statement = db.execute.await_args_list[0].args[0]
    parameters = count_statement.compile().params.values()
    assert ["step_1"] in parameters
    assert ["step_1", "step_2"] not in parameters


@pytest.mark.asyncio
@pytest.mark.parametrize("endpoint", ["get", "patch"])
@pytest.mark.parametrize(
    ("ready_step_ids", "include_ready_key"),
    [
        pytest.param(None, False, id="missing"),
        pytest.param("step_1", True, id="non-array"),
        pytest.param(["step_1", "step_1"], True, id="duplicate"),
        pytest.param(["unknown"], True, id="unknown"),
    ],
)
async def test_generic_item_routes_fail_closed_for_invalid_progressive_ready_ids(
    endpoint: str,
    ready_step_ids: object,
    include_ready_key: bool,
) -> None:
    generation = {"job_id": JOB_WITH_HEX, "status": "partial"}
    if include_ready_key:
        generation["ready_step_ids"] = ready_step_ids
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "step_1", "lesson_content": "ready " * 2200},
            {"id": "step_2", "lesson_content": "hidden " * 2200},
        ],
        "_generation": generation,
    }
    db = AsyncMock()
    db.execute.side_effect = [
        SimpleNamespace(scalar=lambda: 0),
        _Result(scalar_one=None),
    ]

    with (
        patch.object(
            plans,
            "_get_item_for_user",
            AsyncMock(return_value=item),
        ),
        patch.object(
            plans,
            "_latest_active_detail_job",
            AsyncMock(return_value=SimpleNamespace(id=JOB_WITH_HEX)),
        ),
        patch.object(
            plans,
            "artifact_job_reference_is_valid",
            AsyncMock(return_value=True),
        ),
    ):
        if endpoint == "get":
            response = await plans.get_plan_item(
                "mission-1",
                db,
                SimpleNamespace(id="user-1"),
            )
        else:
            response = await plans.update_plan_item(
                "mission-1",
                PlanItemUpdate(notes="Do not expose hidden progress."),
                db,
                SimpleNamespace(id="user-1"),
            )

    assert response.status == PlanItemStatus.NOT_STARTED
    assert response.progressPercent == 0
    count_statement = db.execute.await_args_list[0].args[0]
    assert [] in count_statement.compile().params.values()


@pytest.mark.asyncio
@pytest.mark.parametrize("endpoint", ["get", "patch"])
@pytest.mark.parametrize("status_value", [None, "failed", "unknown"])
async def test_generic_item_routes_hide_rows_for_invalid_modern_status(
    endpoint: str,
    status_value: str | None,
) -> None:
    generation = {"job_id": JOB_WITH_HEX}
    if status_value is not None:
        generation["status"] = status_value
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "stale " * 2200}],
        "_generation": generation,
    }
    db = AsyncMock()
    db.execute.side_effect = [
        SimpleNamespace(scalar=lambda: 0),
        _Result(scalar_one=None),
    ]

    with (
        patch.object(
            plans,
            "_get_item_for_user",
            AsyncMock(return_value=item),
        ),
        patch.object(plans, "_latest_active_detail_job", AsyncMock(return_value=None)),
        patch.object(
            plans,
            "artifact_job_reference_is_valid",
            AsyncMock(return_value=True),
        ),
    ):
        if endpoint == "get":
            response = await plans.get_plan_item(
                "mission-1",
                db,
                SimpleNamespace(id="user-1"),
            )
        else:
            response = await plans.update_plan_item(
                "mission-1",
                PlanItemUpdate(notes="Keep stale rows hidden."),
                db,
                SimpleNamespace(id="user-1"),
            )

    assert response.status == PlanItemStatus.NOT_STARTED
    assert response.progressPercent == 0
    assert [] in db.execute.await_args_list[0].args[0].compile().params.values()
    assert "WHERE false" in str(db.execute.await_args_list[1].args[0])


@pytest.mark.asyncio
async def test_daily_detail_is_immediate_and_uses_daily_completion() -> None:
    item = _item(
        "practice-1",
        PlanItemType.PRACTICE,
        1,
        meta_json={"daily_instructions": "Practice the drill for twenty minutes."},
    )
    db = AsyncMock()
    db.scalar.return_value = 1
    original_get = plans._get_item_for_user
    plans._get_item_for_user = AsyncMock(return_value=item)
    try:
        response = await plans.get_plan_item_detailed(
            "practice-1",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get

    assert response.details_status == DetailsStatus.AVAILABLE
    assert response.job_id is None
    assert response.completed_today is True
    assert response.daily_instructions == "Practice the drill for twenty minutes."
    db.execute.assert_not_awaited()


class _Result:
    def __init__(
        self,
        *,
        scalars: list | None = None,
        scalar_one=None,
        rows: list | None = None,
    ):
        self._scalars = scalars or []
        self._scalar_one = scalar_one
        self._rows = rows or []

    def scalars(self):
        return SimpleNamespace(all=lambda: self._scalars)

    def scalar_one_or_none(self):
        return self._scalar_one

    def fetchall(self):
        return self._rows


@pytest.mark.asyncio
async def test_progress_fails_closed_when_step_identity_array_is_malformed() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "current-1"},
            {"id": "current-2"},
            {"id": "current-2"},
            {"title": "Malformed step without an ID"},
        ]
    }
    db = AsyncMock()
    db.execute.side_effect = [
        SimpleNamespace(scalar=lambda: 7),
        _Result(scalar_one=None),
    ]

    progress, completed = await plans._compute_item_progress(db, "user-1", item)

    assert completed is False
    assert progress.completed_steps == 0
    assert progress.total_steps == 0
    assert progress.percent == 0


@pytest.mark.asyncio
async def test_detailed_progress_snapshot_hides_rows_for_broken_job_reference() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": JOB_WITH_HEX, "status": "ready"},
    }
    db = AsyncMock()

    with patch.object(
        plans,
        "artifact_job_reference_is_valid",
        AsyncMock(return_value=False),
    ):
        progress, completed, completed_step_ids = await plans._item_progress_snapshot(
            db,
            item=item,
            user_id="user-1",
        )

    assert completed is False
    assert completed_step_ids == []
    assert progress.completed_steps == 0
    assert progress.total_steps == 0
    assert progress.percent == 0
    db.execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_detailed_progress_snapshot_excludes_hidden_progressive_completion() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "step_1", "lesson_content": "ready " * 2200},
            {"id": "step_2", "lesson_content": "hidden " * 2200},
        ],
        "_generation": {
            "job_id": JOB_WITH_HEX,
            "status": "partial",
            "ready_step_ids": ["step_1"],
        },
    }
    db = AsyncMock()
    db.execute.side_effect = [
        SimpleNamespace(scalar=lambda: 1),
        _Result(scalar_one=None),
        _Result(scalars=["step_1"]),
    ]

    with patch.object(
        plans,
        "artifact_job_reference_is_valid",
        AsyncMock(return_value=True),
    ):
        progress, completed, completed_step_ids = await plans._item_progress_snapshot(
            db,
            item=item,
            user_id="user-1",
        )

    assert completed is False
    assert completed_step_ids == ["step_1"]
    assert progress.completed_steps == 1
    assert progress.total_steps == 2
    assert progress.percent == 50
    for call_index in (0, 2):
        parameters = db.execute.await_args_list[call_index].args[0].compile().params
        assert ["step_1"] in parameters.values()
        assert ["step_1", "step_2"] not in parameters.values()


@pytest.mark.asyncio
async def test_exact_item_completion_cannot_render_completed_with_zero_progress() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}, {"id": "step_2"}],
        "_generation": {"job_id": JOB_CURRENT},
    }
    db = AsyncMock()
    db.execute.side_effect = [
        SimpleNamespace(scalar=lambda: 0),
        _Result(scalar_one=SimpleNamespace(id="completion-current")),
    ]

    progress, completed = await plans._compute_item_progress(db, "user-1", item)

    assert completed is True
    assert progress.completed_steps == 2
    assert progress.total_steps == 2
    assert progress.percent == 100


def test_current_step_filter_is_scoped_to_exact_artifact() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "generated_at": "2026-07-29T12:30:00+00:00",
        "_generation": {
            "job_id": JOB_B,
            "status": "ready",
            "updated_at": "2026-07-29T12:30:00+00:00",
        },
    }

    predicates = plans._current_step_completion_predicates(
        item,
        user_id="user-1",
    )
    statement = plans.select(plans.PlanItemStepCompletion.step_id).where(*predicates)
    rendered = str(statement)
    parameters = statement.compile().params

    assert "artifact_job_id" in rendered
    assert "plan_item_detail_jobs" in rendered
    assert "CAST(plan_item_detail_jobs.id AS VARCHAR)" in rendered
    assert "completed_at >=" not in rendered
    assert JOB_B in parameters.values()
    assert "mission-1" in parameters.values()
    assert "user-1" in parameters.values()
    assert ["step_1"] in parameters.values()
    assert "coalesce" not in rendered.lower()
    assert "2026-07-29" not in parameters.values()


def test_current_item_filter_requires_owned_current_artifact_job() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": JOB_WITH_HEX, "status": "ready"},
    }

    statement = select(plans.PlanItemCompletion.id).where(
        *plans.current_item_completion_predicates(item, user_id="user-1")
    )
    rendered = str(statement)
    parameters = statement.compile().params.values()

    assert "plan_item_detail_jobs" in rendered
    assert "CAST(plan_item_detail_jobs.id AS VARCHAR)" in rendered
    assert JOB_WITH_HEX in parameters
    assert "mission-1" in parameters
    assert "user-1" in parameters
    assert "status" not in rendered


@pytest.mark.parametrize(
    "raw_job_id",
    [None, "", "not-a-uuid", *NONCANONICAL_JOB_IDS],
)
def test_present_invalid_job_marker_never_matches_legacy_completion(
    raw_job_id: str | None,
) -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": raw_job_id},
    }

    marker = artifact_job_id_from_details(item.details_json)
    statement = select(plans.PlanItemCompletion.id).where(
        *plans.current_item_completion_predicates(item, user_id="user-1")
    )

    assert marker is not None
    assert plans.artifact_job_marker_is_invalid(item.details_json) is True
    assert "WHERE false" in str(statement)


@pytest.mark.parametrize("generation", [None, [], "broken", 7])
def test_non_object_generation_metadata_never_matches_legacy_completion(
    generation: object,
) -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": generation,
    }

    statement = select(plans.PlanItemCompletion.id).where(
        *plans.current_item_completion_predicates(item, user_id="user-1")
    )

    assert plans.artifact_job_marker_is_invalid(item.details_json) is True
    assert artifact_job_id_from_details(item.details_json) == ""
    assert "WHERE false" in str(statement)


@pytest.mark.asyncio
async def test_job_reference_lookup_requires_exact_item_and_user_without_uuid_cast() -> (
    None
):
    details = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": JOB_WITH_HEX, "status": "ready"},
    }
    db = AsyncMock()
    db.scalar.return_value = JOB_WITH_HEX

    assert await artifact_job_reference_is_valid(
        db,
        details,
        plan_item_id="mission-1",
        user_id="user-1",
    )

    statement = db.scalar.await_args.args[0]
    rendered = str(statement)
    parameters = statement.compile().params.values()
    assert "CAST(plan_item_detail_jobs.id AS VARCHAR)" in rendered
    assert "plan_item_detail_jobs.plan_item_id" in rendered
    assert "plan_item_detail_jobs.user_id" in rendered
    assert "status" not in rendered
    assert JOB_WITH_HEX in parameters
    assert "mission-1" in parameters
    assert "user-1" in parameters


@pytest.mark.asyncio
async def test_missing_or_wrong_owner_job_reference_fails_closed() -> None:
    details = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": JOB_WITH_HEX, "status": "ready"},
    }
    db = AsyncMock()
    # Missing rows and rows belonging to another item/user all produce no row
    # because every ownership column is part of the exact lookup above.
    db.scalar.return_value = None

    assert not await artifact_job_reference_is_valid(
        db,
        details,
        plan_item_id="mission-1",
        user_id="user-1",
    )


@pytest.mark.asyncio
async def test_legacy_absent_marker_remains_valid_without_job_lookup() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {"steps": [{"id": "step_1"}]}
    db = AsyncMock()

    assert await artifact_job_reference_is_valid(
        db,
        item.details_json,
        plan_item_id="mission-1",
        user_id="user-1",
    )
    assert progress_eligible_step_ids(item.details_json) == ("step_1",)
    db.scalar.assert_not_awaited()

    item_statement = select(plans.PlanItemCompletion.id).where(
        *plans.current_item_completion_predicates(item, user_id="user-1")
    )
    step_statement = select(plans.PlanItemStepCompletion.id).where(
        *plans._current_step_completion_predicates(item, user_id="user-1")
    )
    assert "artifact_job_id IS NULL" in str(item_statement)
    assert "artifact_job_id IS NULL" in str(step_statement)
    assert "WHERE false" not in str(item_statement)
    assert "WHERE false" not in str(step_statement)

    aggregate_reference = str(
        current_artifact_job_reference_join_predicate(user_id="user-1")
    )
    assert "NOT coalesce" in aggregate_reference
    assert "details_json" in aggregate_reference


@pytest.mark.asyncio
@pytest.mark.parametrize("raw_job_id", NONCANONICAL_JOB_IDS)
async def test_noncanonical_job_marker_fails_read_and_mutation_guards(
    raw_job_id: str,
) -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": raw_job_id, "status": "ready"},
    }
    db = AsyncMock()

    assert not await artifact_job_reference_is_valid(
        db,
        item.details_json,
        plan_item_id="mission-1",
        user_id="user-1",
    )
    with pytest.raises(HTTPException) as exc_info:
        await plans._validate_expected_artifact(
            db,
            item,
            user_id="user-1",
            expected_job_id=raw_job_id,
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.STEP_COMPLETION_CONFLICT_DETAIL
    db.scalar.assert_not_awaited()


def test_set_based_completion_requires_absent_key_for_legacy_and_no_active_replacement() -> (
    None
):
    statement = (
        select(plans.PlanItemCompletion.plan_item_id)
        .join(
            PlanItem,
            plans.PlanItemCompletion.plan_item_id == PlanItem.id,
        )
        .where(
            *plans.current_item_completion_query_predicates(user_id="user-1")
        )
    )
    rendered = str(statement)
    join_rendered = str(current_item_completion_join_predicate())
    reference_rendered = str(
        current_artifact_job_reference_join_predicate(user_id="user-1")
    )
    status_predicate = current_item_completion_artifact_status_join_predicate()
    status_statement = select(PlanItem.id).where(status_predicate)
    status_rendered = str(status_statement)

    assert "jsonb_extract_path" in join_rendered
    assert "jsonb_typeof" in join_rendered
    assert " ? " in join_rendered
    assert "nullif" not in join_rendered.lower()
    assert "plan_item_detail_jobs" in rendered
    assert "artifact_epoch_at" in rendered
    assert "NOT (EXISTS" in rendered
    assert "IS DISTINCT FROM" in rendered
    assert "plan_item_detail_jobs" in reference_rendered
    assert "plan_item_detail_jobs_1.plan_item_id = plan_items.id" in reference_rendered
    assert "plan_item_detail_jobs_1.user_id" in reference_rendered
    assert "CAST(plan_item_detail_jobs_1.id AS VARCHAR)" in reference_rendered
    assert "jsonb_extract_path_text" in reference_rendered
    assert "status" not in reference_rendered
    assert "jsonb_extract_path_text" in status_rendered
    assert " IN " in status_rendered
    assert ["ready", "revoked"] in status_statement.compile().params.values()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "surface",
    ["current-plan", "week-service", "plan-service", "week-api", "reconcile"],
)
async def test_set_based_progress_surfaces_require_owned_current_job(
    surface: str,
) -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": JOB_WITH_HEX, "status": "ready"},
    }
    plan = _plan()
    db = AsyncMock()

    if surface == "current-plan":
        now = datetime.now(timezone.utc)
        response_plan = SimpleNamespace(
            id="plan-1",
            user_id="user-1",
            idol_id=None,
            idol=None,
            target_age=30,
            duration_weeks=12,
            weekly_hours=5,
            cycle_number=1,
            items=[item],
            created_at=now,
            roadmap_json=None,
        )
        db.execute.side_effect = [
            _Result(scalar_one=None),
            _Result(scalar_one=response_plan),
            _Result(scalars=[]),
        ]
        response = await plans.get_current_plan(
            db,
            SimpleNamespace(id="user-1"),
        )
        aggregate_statement = db.execute.await_args_list[2].args[0]
        assert response is not None
        assert response.completedItems == 0
        assert response.overallProgress == 0
        assert response.items[0].status == PlanItemStatus.NOT_STARTED
    elif surface == "week-service":
        db.execute.side_effect = [
            _Result(rows=[("mission-1",)]),
            SimpleNamespace(scalar=lambda: 0),
        ]
        response = await compute_week_progress(db, "user-1", "plan-1", 1)
        aggregate_statement = db.execute.await_args_list[1].args[0]
        assert response.completed_items == 0
        assert response.percent == 0
    elif surface == "plan-service":
        db.execute.side_effect = [
            SimpleNamespace(scalar=lambda: 1),
            SimpleNamespace(scalar=lambda: 0),
        ]
        response = await compute_plan_progress(db, "user-1", "plan-1")
        aggregate_statement = db.execute.await_args_list[1].args[0]
        assert response.completed_items == 0
        assert response.percent == 0
    elif surface == "week-api":
        db.execute.side_effect = [
            _Result(scalar_one=plan),
            _Result(rows=[("mission-1",)]),
            SimpleNamespace(scalar=lambda: 0),
        ]
        response = await plans.get_week_summary(
            "plan-1",
            1,
            db,
            SimpleNamespace(id="user-1"),
        )
        aggregate_statement = db.execute.await_args_list[2].args[0]
        assert response.completed_items == 0
        assert response.percent == 0
    else:
        db.execute.side_effect = [
            _Result(scalars=[item]),
            _Result(scalars=[]),
        ]
        completed, remaining = await plans._reconcile_plan_completion(
            db,
            plan=plan,
            user_id="user-1",
        )
        aggregate_statement = db.execute.await_args_list[1].args[0]
        assert completed is False
        assert remaining == 1
        assert plan.completed_at is None

    rendered = str(aggregate_statement)
    assert "plan_item_detail_jobs" in rendered
    assert ".plan_item_id = plan_items.id" in rendered
    assert "CAST(" in rendered
    assert " AS VARCHAR) = jsonb_extract_path_text" in rendered
    assert "CAST(jsonb_extract_path_text" not in rendered
    assert "user-1" in aggregate_statement.compile().params.values()


@pytest.mark.asyncio
async def test_shared_progress_uses_exact_current_artifact_ids() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}, {"id": "step_2"}],
        "generated_at": "2099-01-01T00:00:00+00:00",
        "_generation": {
            "job_id": JOB_CURRENT,
            "status": "ready",
            "updated_at": "2099-01-01T00:00:00+00:00",
        },
    }
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalar_one=item),
        _Result(scalar_one=None),
        SimpleNamespace(scalar=lambda: 8),
        _Result(scalar_one=None),
    ]

    progress = await compute_service_item_progress(db, "user-1", "mission-1")

    assert progress.completed_steps == 2
    assert progress.total_steps == 2
    assert progress.percent == 100
    count_statement = db.execute.await_args_list[2].args[0]
    rendered = str(count_statement)
    parameters = count_statement.compile().params
    assert "artifact_job_id" in rendered
    assert "completed_at >=" not in rendered
    assert "coalesce" not in rendered.lower()
    assert ["step_1", "step_2"] in parameters.values()
    assert JOB_CURRENT in parameters.values()
    assert not any("2099-01-01" in str(value) for value in parameters.values())
    item_statement = db.execute.await_args_list[0].args[0]
    assert item_statement._for_update_arg is not None
    assert item_statement.get_execution_options()["populate_existing"] is True


@pytest.mark.asyncio
async def test_shared_progress_excludes_hidden_progressive_completion() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "step_1", "lesson_content": "ready " * 2200},
            {"id": "step_2", "lesson_content": "hidden " * 2200},
        ],
        "_generation": {
            "job_id": JOB_WITH_HEX,
            "status": "generating",
            "ready_step_ids": ["step_1"],
        },
    }
    db = AsyncMock()
    db.scalar.return_value = JOB_WITH_HEX
    db.execute.side_effect = [
        _Result(scalar_one=item),
        _Result(scalar_one=SimpleNamespace(id=JOB_WITH_HEX, status="running")),
        SimpleNamespace(scalar=lambda: 1),
        _Result(scalar_one=None),
    ]

    progress = await compute_service_item_progress(db, "user-1", "mission-1")

    assert progress.completed_steps == 1
    assert progress.total_steps == 2
    assert progress.percent == 50
    assert progress.is_completed is False
    count_statement = db.execute.await_args_list[2].args[0]
    parameters = count_statement.compile().params.values()
    assert ["step_1"] in parameters
    assert ["step_1", "step_2"] not in parameters


@pytest.mark.asyncio
@pytest.mark.parametrize("status_value", [None, "failed", "unknown"])
async def test_shared_progress_hides_rows_for_invalid_modern_status(
    status_value: str | None,
) -> None:
    generation = {"job_id": JOB_WITH_HEX}
    if status_value is not None:
        generation["status"] = status_value
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "stale " * 2200}],
        "_generation": generation,
    }
    db = AsyncMock()
    db.scalar.return_value = JOB_WITH_HEX
    db.execute.side_effect = [
        _Result(scalar_one=item),
        _Result(scalar_one=SimpleNamespace(id=JOB_WITH_HEX, status="completed")),
        SimpleNamespace(scalar=lambda: 0),
        _Result(scalar_one=None),
    ]

    progress = await compute_service_item_progress(db, "user-1", "mission-1")

    assert progress.completed_steps == 0
    assert progress.total_steps == 1
    assert progress.percent == 0
    assert progress.is_completed is False
    assert [] in db.execute.await_args_list[2].args[0].compile().params.values()
    assert "WHERE false" in str(db.execute.await_args_list[3].args[0])


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("stored_plan_item_id", "stored_user_id"),
    [
        pytest.param(None, None, id="missing-job"),
        pytest.param("other-item", "user-1", id="wrong-item"),
        pytest.param("mission-1", "other-user", id="wrong-user"),
    ],
)
async def test_shared_progress_fails_closed_before_completion_reads(
    stored_plan_item_id: str | None,
    stored_user_id: str | None,
) -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": JOB_WITH_HEX, "status": "ready"},
    }
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=item)

    async def reference_is_owned(*_args, **kwargs):
        return (
            stored_plan_item_id is not None
            and kwargs["plan_item_id"] == stored_plan_item_id
            and kwargs["user_id"] == stored_user_id
        )

    reference_check = AsyncMock(side_effect=reference_is_owned)

    with patch(
        "app.services.planning.progress.artifact_job_reference_is_valid",
        reference_check,
    ):
        progress = await compute_service_item_progress(db, "user-1", "mission-1")

    assert progress.completed_steps == 0
    assert progress.total_steps == 0
    assert progress.percent == 0
    assert progress.is_completed is False
    assert db.execute.await_count == 1
    item_statement = db.execute.await_args.args[0]
    assert item_statement._for_update_arg is not None
    reference_check.assert_awaited_once()


@pytest.mark.asyncio
async def test_shared_progress_suppresses_artifact_during_active_replacement() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": {"job_id": JOB_A},
    }
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalar_one=item),
        _Result(scalar_one=SimpleNamespace(id=JOB_B, status="running")),
    ]

    progress = await compute_service_item_progress(db, "user-1", "mission-1")

    assert progress.completed_steps == 0
    assert progress.total_steps == 0
    assert progress.percent == 0
    assert progress.is_completed is False
    assert db.execute.await_count == 2


@pytest.mark.asyncio
async def test_shared_progress_refreshes_terminal_b_under_item_lock() -> None:
    item_b = _item("mission-1", PlanItemType.COURSE, 1)
    item_b.details_json = {
        "steps": [{"id": "b_step"}],
        "_generation": {"job_id": JOB_B, "status": "ready"},
    }
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalar_one=item_b),
        _Result(scalar_one=SimpleNamespace(id=JOB_B, status="completed")),
        SimpleNamespace(scalar=lambda: 0),
        _Result(scalar_one=None),
    ]

    progress = await compute_service_item_progress(db, "user-1", "mission-1")

    assert progress.total_steps == 1
    assert progress.completed_steps == 0
    item_statement = db.execute.await_args_list[0].args[0]
    assert item_statement._for_update_arg is not None
    assert item_statement.get_execution_options()["populate_existing"] is True
    completion_statement = db.execute.await_args_list[-1].args[0]
    assert JOB_B in completion_statement.compile().params.values()


@pytest.mark.asyncio
async def test_completion_timestamp_uses_wall_clock_statement_time() -> None:
    database_time = datetime(2026, 7, 29, 12, 1, tzinfo=timezone.utc)
    db = AsyncMock()
    db.scalar.return_value = database_time

    result = await plans._database_completion_time(db)

    assert result == database_time
    statement = db.scalar.await_args.args[0]
    assert "clock_timestamp" in str(statement)


@pytest.mark.asyncio
async def test_detail_job_epoch_allocator_advances_past_future_prior_epoch() -> None:
    allocated = datetime(2099, 1, 1, 0, 0, 0, 1, tzinfo=timezone.utc)
    db = AsyncMock()
    db.scalar.return_value = allocated

    result = await allocate_detail_artifact_epoch(
        db,
        plan_item_id="mission-1",
        user_id="user-1",
    )

    assert result == allocated
    statement = db.scalar.await_args.args[0]
    rendered = str(statement)
    parameters = statement.compile().params
    assert "greatest" in rendered.lower()
    assert rendered.lower().count("clock_timestamp") == 2
    assert "max(plan_item_detail_jobs.artifact_epoch_at)" in rendered.lower()
    assert "INTERVAL '1 microsecond'" in rendered
    assert "mission-1" in parameters.values()
    assert "user-1" in parameters.values()

    db.scalar.reset_mock()
    job = await new_plan_item_detail_job(
        db,
        plan_item_id="mission-1",
        user_id="user-1",
        status="queued",
    )
    assert job.artifact_epoch_at == allocated
    assert job.plan_item_id == "mission-1"
    assert job.user_id == "user-1"
    db.scalar.assert_awaited_once()


def test_detail_job_and_completion_models_version_artifacts() -> None:
    default = PlanItemDetailJob.__table__.c.artifact_epoch_at.server_default

    assert default is not None
    assert "clock_timestamp" in str(default.arg)
    assert PlanItemDetailJob.__table__.c.supersedes_artifact is not None
    assert plans.PlanItemStepCompletion.__table__.c.artifact_job_id is not None
    assert plans.PlanItemCompletion.__table__.c.artifact_job_id is not None
    assert PlanItemDetailJob.__table__.c.created_at is not None


@pytest.mark.asyncio
async def test_latest_active_job_orders_by_wall_clock_epoch_not_transaction_time() -> None:
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=None)

    await plans._latest_active_detail_job(
        db,
        item_id="mission-1",
        user_id="user-1",
    )

    statement = db.execute.await_args.args[0]
    rendered = str(statement)
    assert "artifact_epoch_at DESC" in rendered
    assert "created_at DESC" not in rendered
    assert "status IN" not in rendered


@pytest.mark.asyncio
async def test_newer_terminal_job_fences_older_active_job_in_api_selection() -> None:
    latest_terminal = SimpleNamespace(id=JOB_B, status="completed")
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=latest_terminal)

    active = await plans._latest_active_detail_job(
        db,
        item_id="mission-1",
        user_id="user-1",
    )

    assert active is None


@pytest.mark.asyncio
async def test_manual_item_and_initial_detail_job_commit_atomically() -> None:
    plan = _plan()
    plan.start_date = None
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=plan)
    db.add = MagicMock()
    now = datetime.now(timezone.utc)

    def assign_ids(row) -> None:
        if isinstance(row, PlanItem):
            row.id = "mission-new"
            row.created_at = now
            row.updated_at = now
        elif isinstance(row, PlanItemDetailJob):
            row.id = JOB_A

    db.add.side_effect = assign_ids

    with patch("app.tasks.plans.regenerate_plan_item_details.delay") as enqueue:
        response = await plans.create_plan_item(
            "plan-1",
            plans.PlanItemCreate(
                title="A useful mission",
                description="Build and verify one concrete deliverable.",
            ),
            db,
            SimpleNamespace(id="user-1"),
        )

    assert response.id == "mission-new"
    assert db.add.call_count == 2
    db.flush.assert_awaited_once_with()
    db.commit.assert_awaited_once_with()
    enqueue.assert_called_once_with(JOB_A)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "daily_type",
    [PlanItemType.HABIT, PlanItemType.PRACTICE],
)
async def test_manual_daily_item_persists_script_without_detail_generation(
    daily_type: PlanItemType,
) -> None:
    plan = _plan()
    plan.start_date = None
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=plan)
    db.add = MagicMock()
    now = datetime.now(timezone.utc)

    def assign_item_id(row) -> None:
        assert isinstance(row, PlanItem)
        row.id = "daily-new"
        row.created_at = now
        row.updated_at = now

    db.add.side_effect = assign_item_id

    with patch("app.tasks.plans.regenerate_plan_item_details.delay") as enqueue:
        response = await plans.create_plan_item(
            "plan-1",
            plans.PlanItemCreate(
                title="A useful daily rhythm",
                description="Practice one concrete behavior every day.",
                type=daily_type,
                dailyInstructions="  Practice deliberately for 20 minutes.  ",
            ),
            db,
            SimpleNamespace(id="user-1"),
        )

    created_item = db.add.call_args.args[0]
    assert response.id == "daily-new"
    assert created_item.meta_json == {
        "daily_instructions": "Practice deliberately for 20 minutes."
    }
    assert db.add.call_count == 1
    db.flush.assert_awaited_once_with()
    db.commit.assert_awaited_once_with()
    db.refresh.assert_awaited_once_with(created_item)
    enqueue.assert_not_called()

    detail_db = AsyncMock()
    detail_db.scalar.return_value = 0
    with patch.object(
        plans,
        "_get_item_for_user",
        AsyncMock(return_value=created_item),
    ):
        detailed = await plans.get_plan_item_detailed(
            "daily-new",
            detail_db,
            SimpleNamespace(id="user-1"),
        )

    assert detailed.details_status == DetailsStatus.AVAILABLE
    assert detailed.daily_instructions == "Practice deliberately for 20 minutes."
    assert detailed.job_id is None
    detail_db.execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_current_week_reserves_high_priority_for_first_mission() -> None:
    missions = [
        _item("mission-1", PlanItemType.PROJECT, 1),
        _item("mission-2", PlanItemType.READING, 1),
    ]
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        _Result(scalars=missions),
        _Result(scalars=[]),
    ]

    async def assign_job_ids() -> None:
        for index, call in enumerate(db.add.call_args_list, start=1):
            call.args[0].id = f"detail-job-{index}"

    db.flush.side_effect = assign_job_ids

    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue:
        job_ids = await plan_tasks._enqueue_plan_week_details_generation_async(
            db,
            plan_id="plan-1",
            user_id="user-1",
            week=1,
            priority="high",
        )

    assert job_ids == ["detail-job-1", "detail-job-2"]
    assert [call.args[0].status for call in db.add.call_args_list] == [
        "queued",
        "queued",
    ]
    assert [call.args[0].step for call in db.add.call_args_list] == [
        "background_queued",
        "background_queued",
    ]
    assert enqueue.call_count == 2
    assert [call.kwargs["queue"] for call in enqueue.call_args_list] == [
        "high_priority",
        "default",
    ]
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_duplicate_plan_delivery_is_skipped_before_context_loading() -> None:
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(rowcount=0)
    db.get.return_value = SimpleNamespace(
        status="running",
        step="structuring_curriculum",
        plan_id=None,
    )

    class SessionContext:
        async def __aenter__(self):
            return db

        async def __aexit__(self, *args):
            return None

    with patch(
        "app.tasks.plans.async_session_maker",
        return_value=SessionContext(),
    ):
        result = await plan_tasks._run_plan_generation_async("job-1")

    assert result == {
        "status": "skipped",
        "job_status": "running",
        "plan_id": None,
    }
    db.commit.assert_awaited_once()
    db.execute.assert_awaited_once()


@pytest.mark.asyncio
async def test_week_prefetch_reuses_active_jobs_instead_of_duplicating() -> None:
    missions = [
        _item("mission-1", PlanItemType.PROJECT, 2),
        _item("mission-2", PlanItemType.READING, 2),
    ]
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        _Result(scalars=missions),
        _Result(scalars=["mission-1", "mission-2"]),
    ]

    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue:
        job_ids = await plan_tasks._enqueue_plan_week_details_generation_async(
            db,
            plan_id="plan-1",
            user_id="user-1",
            week=2,
            priority="low",
        )

    assert job_ids == []
    db.add.assert_not_called()
    enqueue.assert_not_called()
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("initial_status", "initial_step"),
    [
        ("pending", "prefetch_queued"),
        ("queued", "background_queued"),
    ],
)
async def test_opening_prefetched_detail_promotes_it_once(
    initial_status: str,
    initial_step: str,
) -> None:
    job = SimpleNamespace(
        id="job-prefetch",
        plan_item_id="mission-1",
        status=initial_status,
        step=initial_step,
        error_message=None,
    )
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(rowcount=1)

    with patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue:
        result = await plans._promote_prefetched_detail_job(db, job)

    assert result == "promoted"
    assert job.status == "queued"
    enqueue.assert_called_once_with(args=["job-prefetch"], queue="high_priority")
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_prefetch_publish_failure_becomes_terminal() -> None:
    job = SimpleNamespace(
        id="job-prefetch",
        plan_item_id="mission-1",
        status="pending",
        step="prefetch_queued",
        error_message=None,
    )
    db = AsyncMock()
    db.execute.side_effect = [
        SimpleNamespace(rowcount=1),
        SimpleNamespace(rowcount=1),
    ]

    with patch(
        "app.tasks.plans.regenerate_plan_item_details.apply_async",
        side_effect=RuntimeError("broker unavailable"),
    ):
        result = await plans._promote_prefetched_detail_job(db, job)

    assert result == "failed"
    assert job.status == "failed"
    assert db.commit.await_count == 2


@pytest.mark.asyncio
async def test_failed_detail_job_is_returned_instead_of_requeued_forever() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    failed_job = SimpleNamespace(
        id="job-1",
        status="failed",
        step="error",
        progress_percent=60,
        error_message="provider failed",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalars=[]),
        _Result(scalar_one=failed_job),
    ]
    original_get = plans._get_item_for_user
    original_progress = plans._compute_item_progress
    plans._get_item_for_user = AsyncMock(return_value=item)
    plans._compute_item_progress = AsyncMock(return_value=(ItemProgress(), False))
    try:
        response = await plans.get_plan_item_detailed(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get
        plans._compute_item_progress = original_progress

    assert response.details_status == DetailsStatus.FAILED
    assert response.job_id == "job-1"
    assert response.details_error
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_active_detail_job_exposes_first_checkpointed_lesson() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "title": "Ready lesson",
                "description": "Ready to read.",
                "lesson_content": "substance " * 2000,
                "resources": ["Reference"],
                "substeps": [
                    "Complete one specific timed action and verify the saved output against the stated success criterion."
                ],
            },
            {
                "id": "step_2",
                "title": "Next lesson",
                "description": "Still being written.",
                "resources": ["Reference"],
            },
            {
                "id": "step_3",
                "title": "Final lesson",
                "description": "Still being written.",
                "resources": ["Reference"],
            },
        ],
        "materials": [{"title": "Reference", "type": "book"}],
        "_generation": {
            "job_id": JOB_A,
            "status": "partial",
            "ready_step_ids": ["step_1"],
        },
    }
    now = datetime.now(timezone.utc)
    active_job = SimpleNamespace(
        id=JOB_A,
        status="running",
        step="first_lesson_ready",
        progress_percent=70,
        error_message=None,
        created_at=now,
        updated_at=now,
    )
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalars=[]),
        _Result(scalar_one=active_job),
    ]
    original_get = plans._get_item_for_user
    original_progress = plans._compute_item_progress
    plans._get_item_for_user = AsyncMock(return_value=item)
    plans._compute_item_progress = AsyncMock(return_value=(ItemProgress(), False))
    try:
        response = await plans.get_plan_item_detailed(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get
        plans._compute_item_progress = original_progress

    assert response.details_status == DetailsStatus.PARTIAL
    assert response.job_id == JOB_A
    assert response.artifact_job_id == JOB_A
    assert response.details is not None
    assert response.details.steps[0].lesson_content
    assert response.details.steps[1].lesson_content is None


@pytest.mark.asyncio
async def test_active_replacement_suppresses_previous_partial_artifact() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "title": "Artifact A lesson",
                "lesson_content": "substance " * 2200,
            },
            {"id": "step_2", "title": "Still writing"},
        ],
        "_generation": {
            "job_id": JOB_A,
            "status": "partial",
            "ready_step_ids": ["step_1"],
        },
    }
    now = datetime.now(timezone.utc)
    replacement_job = SimpleNamespace(
        id=JOB_B,
        status="running",
        step="generating_lessons",
        progress_percent=65,
        error_message=None,
        created_at=now,
        updated_at=now,
    )
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalars=["step_1"]),
        _Result(scalar_one=replacement_job),
    ]

    with (
        patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(
                return_value=(
                    ItemProgress(completed_steps=1, total_steps=2, percent=50),
                    False,
                )
            ),
        ),
    ):
        response = await plans.get_plan_item_detailed(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )

    assert response.details_status == DetailsStatus.GENERATING
    assert response.job_id == JOB_B
    assert response.details is None
    assert response.artifact_job_id is None
    assert response.completed_step_ids == []
    assert response.progress.percent == 0


@pytest.mark.asyncio
async def test_detailed_get_locks_b_before_any_terminal_progress_snapshot() -> None:
    item_a = _item("mission-1", PlanItemType.PROJECT, 1)
    item_a.details_json = {
        "steps": [{"id": "step_1", "title": "Old lesson"}],
        "_generation": {"job_id": JOB_A, "status": "partial"},
    }
    item_b = _item("mission-1", PlanItemType.PROJECT, 1)
    item_b.details_json = {
        "steps": [
            {
                "id": "step_1",
                "title": "Replacement lesson",
                "lesson_content": "substance " * 2200,
            },
            {
                "id": "step_2",
                "title": "Replacement practice",
                "lesson_content": "practice " * 2200,
            },
        ],
        "_generation": {"job_id": JOB_B, "status": "ready"},
    }
    new_snapshot = (ItemProgress(completed_steps=0, total_steps=2, percent=0), False, [])
    get_item = AsyncMock(side_effect=[item_a, item_b])

    with (
        patch.object(
            plans,
            "_get_item_for_user",
            get_item,
        ),
        patch.object(
            plans,
            "_item_progress_snapshot",
            AsyncMock(return_value=new_snapshot),
        ) as snapshot,
        patch.object(
            plans,
            "_lesson_details_meet_runtime_quality",
            AsyncMock(return_value=True),
        ),
    ):
        response = await plans.get_plan_item_detailed(
            "mission-1",
            AsyncMock(),
            SimpleNamespace(id="user-1"),
        )

    assert snapshot.await_count == 1
    assert snapshot.await_args.kwargs["item"] is item_b
    assert get_item.await_args_list[1].kwargs["for_update"] is True
    assert response.details_status == DetailsStatus.AVAILABLE
    assert response.artifact_job_id == JOB_B
    assert response.completed is False
    assert response.completed_step_ids == []
    assert response.progress.total_steps == 2
    assert response.progress.percent == 0
    assert response.item.status == PlanItemStatus.NOT_STARTED


@pytest.mark.asyncio
async def test_unready_checkpoint_step_cannot_be_completed() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "title": "Still writing",
                "lesson_content": None,
            }
        ]
    }
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=None)
    with patch.object(
        plans,
        "_lock_plan_item_toggle_state",
        AsyncMock(return_value=(_plan(), item, None)),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await plans.toggle_step_complete(
                "mission-1",
                "step_1",
                db,
                SimpleNamespace(id="user-1"),
            )

    assert exc_info.value.status_code == 409
    assert "still being prepared" in str(exc_info.value.detail)


@pytest.mark.asyncio
@pytest.mark.parametrize("toggle_kind", ["item", "step"])
@pytest.mark.parametrize("artifact_stage", ["outline", "partial"])
async def test_catalog_outline_or_partial_artifact_cannot_create_completion_state(
    toggle_kind: str,
    artifact_stage: str,
) -> None:
    first_lesson = "substance " * 2200 if artifact_stage == "partial" else None
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "lesson_content": first_lesson,
                "personalized_lesson_version_id": "lesson-1",
            },
            {
                "id": "step_2",
                "personalized_lesson_version_id": "lesson-2",
            },
        ],
        "_generation": {
            "job_id": JOB_A,
            "status": "partial",
            "content_origin": "catalog_personalized",
            "personalization_status": "ready",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1", "lesson-2"],
            "ready_step_ids": ["step_1"] if first_lesson else [],
        },
    }
    assignments = tuple(
        SimpleNamespace(
            personalized_lesson_version_id=lesson_id,
            status=AssignmentStatus.AVAILABLE,
            started_at=None,
            completed_at=None,
        )
        for lesson_id in ("lesson-1", "lesson-2")
    )
    scope = plans._CatalogAssignmentCompletionScope(
        frozenset({"lesson-1", "lesson-2"}),
        assignments,
    )
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result(scalar_one=None)

    with patch.object(
        plans,
        "_lock_plan_item_toggle_state",
        AsyncMock(return_value=(_plan(), item, scope)),
    ):
        with pytest.raises(HTTPException) as exc_info:
            if toggle_kind == "item":
                await plans.toggle_item_complete(
                    "mission-1",
                    db,
                    SimpleNamespace(id="user-1"),
                    artifact_job_id=JOB_A,
                )
            else:
                await plans.toggle_step_complete(
                    "mission-1",
                    "step_1",
                    db,
                    SimpleNamespace(id="user-1"),
                    artifact_job_id=JOB_A,
                )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.CATALOG_ASSIGNMENT_CONFLICT_DETAIL
    assert item.status == PlanItemStatus.NOT_STARTED
    assert item.progress_percent == 0
    assert all(row.status == AssignmentStatus.AVAILABLE for row in assignments)
    assert all(row.started_at is None for row in assignments)
    assert all(row.completed_at is None for row in assignments)
    assert db.execute.await_count == 1
    db.add.assert_not_called()
    db.scalar.assert_not_awaited()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_ready_partial_step_can_complete_but_item_toggle_stays_blocked() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "step_1", "lesson_content": "substance " * 2200},
            {"id": "step_2", "lesson_content": None},
        ],
        "_generation": {
            "job_id": JOB_A,
            "status": "partial",
            "ready_step_ids": ["step_1"],
        },
    }
    plan = _plan()
    now = datetime.now(timezone.utc)
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result(scalar_one=None)
    db.scalar.side_effect = [now, 1]
    progress = ItemProgress(completed_steps=1, total_steps=2, percent=50)

    with (
        patch.object(
            plans,
            "_lock_plan_item_toggle_state",
            AsyncMock(return_value=(plan, item, None)),
        ),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(return_value=(progress, False)),
        ),
        patch.object(
            plans,
            "_reconcile_plan_completion",
            AsyncMock(return_value=(False, 1)),
        ),
        patch("app.tasks.plans.prefetch_plan_week_details.apply_async") as prefetch,
    ):
        response = await plans.toggle_step_complete(
            "mission-1",
            "step_1",
            db,
            SimpleNamespace(id="user-1"),
            artifact_job_id=JOB_A,
        )

    assert response.completed is True
    assert response.item_completed is False
    assert item.status == PlanItemStatus.IN_PROGRESS
    assert item.progress_percent == 50
    assert db.add.call_count == 1
    db.commit.assert_awaited_once_with()
    prefetch.assert_not_called()

    item_db = AsyncMock()
    item_db.add = MagicMock()
    item_db.execute.return_value = _Result(scalar_one=None)
    with patch.object(
        plans,
        "_lock_plan_item_toggle_state",
        AsyncMock(return_value=(plan, item, None)),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await plans.toggle_item_complete(
                "mission-1",
                item_db,
                SimpleNamespace(id="user-1"),
                artifact_job_id=JOB_A,
            )

    assert exc_info.value.status_code == 409
    item_db.add.assert_not_called()
    item_db.flush.assert_not_awaited()
    item_db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_partial_last_step_waits_for_ready_then_auto_completes_on_retry() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "step_1", "lesson_content": "substance " * 2200},
            {"id": "step_2", "lesson_content": "practice " * 2200},
        ],
        "_generation": {
            "job_id": JOB_A,
            "status": "partial",
            "ready_step_ids": ["step_1", "step_2"],
        },
    }
    plan = _plan()
    now = datetime.now(timezone.utc)
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        _Result(scalar_one=None),
        _Result(scalars=["step_1"]),
    ]
    db.scalar.return_value = now

    with patch.object(
        plans,
        "_lock_plan_item_toggle_state",
        AsyncMock(return_value=(plan, item, None)),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await plans.toggle_step_complete(
                "mission-1",
                "step_2",
                db,
                SimpleNamespace(id="user-1"),
                artifact_job_id=JOB_A,
            )

    assert exc_info.value.status_code == 409
    assert item.status == PlanItemStatus.NOT_STARTED
    assert item.progress_percent == 0
    assert plan.completed_at is None
    db.add.assert_not_called()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()

    item.details_json["_generation"]["status"] = "ready"
    retry_db = AsyncMock()
    retry_db.add = MagicMock()
    retry_db.execute.side_effect = [
        _Result(scalar_one=None),
        _Result(scalars=["step_1"]),
        _Result(scalar_one=SimpleNamespace(id=JOB_A, status="completed")),
        _Result(scalar_one=None),
    ]
    retry_db.scalar.side_effect = [now, JOB_A]
    ready_progress = ItemProgress(completed_steps=2, total_steps=2, percent=100)

    with (
        patch.object(
            plans,
            "_lock_plan_item_toggle_state",
            AsyncMock(return_value=(plan, item, None)),
        ),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(return_value=(ready_progress, False)),
        ),
        patch.object(
            plans,
            "_reconcile_plan_completion",
            AsyncMock(return_value=(True, 0)),
        ),
    ):
        response = await plans.toggle_step_complete(
            "mission-1",
            "step_2",
            retry_db,
            SimpleNamespace(id="user-1"),
            artifact_job_id=JOB_A,
        )

    assert response.completed is True
    assert response.item_completed is True
    assert item.status == PlanItemStatus.COMPLETED
    assert item.progress_percent == 100
    assert len(retry_db.add.call_args_list) == 2
    retry_db.flush.assert_awaited()
    retry_db.commit.assert_awaited_once_with()


@pytest.mark.asyncio
@pytest.mark.parametrize("toggle_kind", ["item", "step"])
@pytest.mark.parametrize("malformed_steps", MALFORMED_LESSON_STEPS)
async def test_completion_toggles_reject_malformed_steps_before_mutation(
    toggle_kind: str,
    malformed_steps: object,
) -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {"steps": malformed_steps}
    db = AsyncMock()
    db.add = MagicMock()

    with patch.object(
        plans,
        "_lock_plan_item_toggle_state",
        AsyncMock(return_value=(_plan(), item, None)),
    ):
        with pytest.raises(HTTPException) as exc_info:
            if toggle_kind == "item":
                await plans.toggle_item_complete(
                    "mission-1",
                    db,
                    SimpleNamespace(id="user-1"),
                )
            else:
                await plans.toggle_step_complete(
                    "mission-1",
                    "step_1",
                    db,
                    SimpleNamespace(id="user-1"),
                )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.STEP_COMPLETION_CONFLICT_DETAIL
    assert item.status == PlanItemStatus.COMPLETED
    assert item.progress_percent == 100
    db.execute.assert_not_awaited()
    db.scalar.assert_not_awaited()
    db.add.assert_not_called()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("toggle_kind", ["item", "step"])
@pytest.mark.parametrize("malformed_materials", MALFORMED_LESSON_MATERIALS)
async def test_completion_toggles_reject_malformed_materials_before_mutation(
    toggle_kind: str,
    malformed_materials: object,
) -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "lesson_content": "substance " * 2200,
                "personalized_lesson_version_id": "lesson-1",
            }
        ],
        "materials": malformed_materials,
        "_generation": {
            "job_id": JOB_A,
            "status": "partial",
            "content_origin": "catalog_personalized",
            "personalization_status": "ready",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1"],
            "ready_step_ids": ["step_1"],
        },
    }
    assignment = SimpleNamespace(
        personalized_lesson_version_id="lesson-1",
        status=AssignmentStatus.AVAILABLE,
        started_at=None,
        completed_at=None,
    )
    scope = plans._CatalogAssignmentCompletionScope(
        frozenset({"lesson-1"}),
        (assignment,),
    )
    db = AsyncMock()
    db.add = MagicMock()

    with patch.object(
        plans,
        "_lock_plan_item_toggle_state",
        AsyncMock(return_value=(_plan(), item, scope)),
    ):
        with pytest.raises(HTTPException) as exc_info:
            if toggle_kind == "item":
                await plans.toggle_item_complete(
                    "mission-1",
                    db,
                    SimpleNamespace(id="user-1"),
                    artifact_job_id=JOB_A,
                )
            else:
                await plans.toggle_step_complete(
                    "mission-1",
                    "step_1",
                    db,
                    SimpleNamespace(id="user-1"),
                    artifact_job_id=JOB_A,
                )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.STEP_COMPLETION_CONFLICT_DETAIL
    assert item.status == PlanItemStatus.NOT_STARTED
    assert item.progress_percent == 0
    assert assignment.status == AssignmentStatus.AVAILABLE
    assert assignment.started_at is None
    assert assignment.completed_at is None
    db.execute.assert_not_awaited()
    db.scalar.assert_not_awaited()
    db.add.assert_not_called()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("toggle_kind", ["item", "step"])
@pytest.mark.parametrize(
    ("invalid_alias", "valid_alias", "invalid_value"),
    FALSY_INVALID_TIMING_ALIAS_CASES,
)
async def test_completion_toggles_reject_falsy_invalid_timing_aliases(
    toggle_kind: str,
    invalid_alias: str,
    valid_alias: str,
    invalid_value: object,
) -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "lesson_content": "substance " * 2200,
                invalid_alias: invalid_value,
                valid_alias: 15,
            }
        ]
    }
    db = AsyncMock()
    db.add = MagicMock()

    with patch.object(
        plans,
        "_lock_plan_item_toggle_state",
        AsyncMock(return_value=(_plan(), item, None)),
    ):
        with pytest.raises(HTTPException) as exc_info:
            if toggle_kind == "item":
                await plans.toggle_item_complete(
                    "mission-1",
                    db,
                    SimpleNamespace(id="user-1"),
                )
            else:
                await plans.toggle_step_complete(
                    "mission-1",
                    "step_1",
                    db,
                    SimpleNamespace(id="user-1"),
                )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.STEP_COMPLETION_CONFLICT_DETAIL
    assert item.status == PlanItemStatus.COMPLETED
    assert item.progress_percent == 100
    db.execute.assert_not_awaited()
    db.scalar.assert_not_awaited()
    db.add.assert_not_called()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_catalog_step_completion_updates_only_its_pinned_assignment() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "step_1", "personalized_lesson_version_id": "lesson-1"},
            {"id": "step_2", "personalized_lesson_version_id": "lesson-2"},
        ],
        "_generation": {
            "content_origin": "catalog_personalized",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1", "lesson-2"],
        },
    }
    rows = [
        SimpleNamespace(
            personalized_lesson_version_id=lesson_id,
            status=AssignmentStatus.AVAILABLE,
            completed_at=None,
            started_at=None,
        )
        for lesson_id in ("lesson-1", "lesson-2")
    ]
    lock_rows = AsyncMock(return_value=rows)
    db = AsyncMock()
    now = datetime.now(timezone.utc)

    with patch(
        "app.services.planning.catalog_lessons.lock_catalog_assignments_for_mutation",
        lock_rows,
    ):
        await plans._sync_catalog_assignment_completion(
            db,
            item=item,
            user_id="user-1",
            completed=True,
            now=now,
            personalized_lesson_version_id="lesson-2",
        )

    lock_rows.assert_awaited_once_with(
        db,
        plan_id="plan-1",
        plan_item_id="mission-1",
        personalized_lesson_version_ids=["lesson-1", "lesson-2"],
        require_ready_personalized_version_ids=["lesson-1", "lesson-2"],
        expected_user_id="user-1",
    )
    assert rows[0].status == AssignmentStatus.AVAILABLE
    assert rows[0].completed_at is None
    assert rows[1].status == AssignmentStatus.COMPLETED
    assert rows[1].completed_at == now


@pytest.mark.asyncio
async def test_catalog_recompletion_preserves_original_completion_time() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "_generation": {
            "content_origin": "catalog_personalized",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1"],
        }
    }
    original_completed_at = datetime(2026, 1, 2, tzinfo=timezone.utc)
    row = SimpleNamespace(
        personalized_lesson_version_id="lesson-1",
        status=AssignmentStatus.COMPLETED,
        completed_at=original_completed_at,
        started_at=original_completed_at,
    )

    with patch(
        "app.services.planning.catalog_lessons.lock_catalog_assignments_for_mutation",
        AsyncMock(return_value=[row]),
    ):
        await plans._sync_catalog_assignment_completion(
            AsyncMock(),
            item=item,
            user_id="user-1",
            completed=True,
            now=datetime(2026, 2, 3, tzinfo=timezone.utc),
        )

    assert row.status == AssignmentStatus.COMPLETED
    assert row.completed_at == original_completed_at


@pytest.mark.asyncio
async def test_catalog_completion_rejects_incomplete_assignment_coverage() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "_generation": {
            "content_origin": "catalog_personalized",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1", "lesson-2"],
        }
    }
    row = SimpleNamespace(
        personalized_lesson_version_id="lesson-1",
        status=AssignmentStatus.AVAILABLE,
        completed_at=None,
        started_at=None,
    )
    lock_rows = AsyncMock(return_value=[row])

    with patch(
        "app.services.planning.catalog_lessons.lock_catalog_assignments_for_mutation",
        lock_rows,
    ):
        with pytest.raises(HTTPException) as exc_info:
            await plans._sync_catalog_assignment_completion(
                AsyncMock(),
                item=item,
                user_id="user-1",
                completed=True,
                now=datetime.now(timezone.utc),
            )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.CATALOG_ASSIGNMENT_CONFLICT_DETAIL
    assert row.status == AssignmentStatus.AVAILABLE


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "terminal_status",
    [AssignmentStatus.SKIPPED, AssignmentStatus.REPLACED],
)
async def test_catalog_completion_rejects_terminal_assignment(
    terminal_status: AssignmentStatus,
) -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "_generation": {
            "content_origin": "catalog_personalized",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1"],
        }
    }
    row = SimpleNamespace(
        personalized_lesson_version_id="lesson-1",
        status=terminal_status,
        completed_at=None,
        started_at=None,
    )

    with patch(
        "app.services.planning.catalog_lessons.lock_catalog_assignments_for_mutation",
        AsyncMock(return_value=[row]),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await plans._sync_catalog_assignment_completion(
                AsyncMock(),
                item=item,
                user_id="user-1",
                completed=True,
                now=datetime.now(timezone.utc),
            )

    assert exc_info.value.status_code == 409
    assert row.status == terminal_status


@pytest.mark.asyncio
async def test_catalog_lifecycle_race_maps_to_friendly_conflict() -> None:
    from app.services.planning.catalog_lessons import PersonalizationQualityError

    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "_generation": {
            "content_origin": "catalog_personalized",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1"],
        }
    }

    with patch(
        "app.services.planning.catalog_lessons.lock_catalog_assignments_for_mutation",
        AsyncMock(
            side_effect=PersonalizationQualityError(
                "a personalized lesson pin was revoked before assignment mutation"
            )
        ),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await plans._sync_catalog_assignment_completion(
                AsyncMock(),
                item=item,
                user_id="user-1",
                completed=True,
                now=datetime.now(timezone.utc),
            )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.CATALOG_ASSIGNMENT_CONFLICT_DETAIL


@pytest.mark.asyncio
async def test_toggle_state_locks_catalog_before_refreshing_plan_item() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "_generation": {
            "content_origin": "catalog_personalized",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1"],
        }
    }
    scope = plans._CatalogAssignmentCompletionScope(
        frozenset({"lesson-1"}),
        (),
    )
    events: list[str] = []

    async def get_item(*_args, for_update=False, **_kwargs):
        events.append("plan_item_lock" if for_update else "item_read")
        return item

    async def lock_catalog(*_args, **_kwargs):
        events.append("catalog_lock")
        return scope

    db = AsyncMock()

    async def lock_plan(statement):
        events.append("plan_lock")
        assert statement._for_update_arg is not None
        return _Result(scalar_one=_plan())

    db.execute.side_effect = lock_plan
    with (
        patch.object(plans, "_get_item_for_user", AsyncMock(side_effect=get_item)),
        patch.object(
            plans,
            "_lock_catalog_assignment_completion_scope",
            AsyncMock(side_effect=lock_catalog),
        ),
        patch.object(
            plans,
            "_latest_active_detail_job",
            AsyncMock(return_value=None),
        ),
    ):
        (
            locked_plan,
            locked_item,
            locked_scope,
        ) = await plans._lock_plan_item_toggle_state(
            db,
            item_id="mission-1",
            user_id="user-1",
        )

    assert locked_plan.id == "plan-1"
    assert locked_item is item
    assert locked_scope is scope
    assert events == ["item_read", "catalog_lock", "plan_lock", "plan_item_lock"]


@pytest.mark.asyncio
async def test_toggle_state_rejects_plan_item_reparenting() -> None:
    initial_item = _item("mission-1", PlanItemType.PROJECT, 1)
    moved_item = _item("mission-1", PlanItemType.PROJECT, 1)
    moved_item.plan_id = "plan-2"
    get_item = AsyncMock(side_effect=[initial_item, moved_item])
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=_plan())

    with (
        patch.object(plans, "_get_item_for_user", get_item),
        patch.object(
            plans,
            "_lock_catalog_assignment_completion_scope",
            AsyncMock(return_value=None),
        ),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await plans._lock_plan_item_toggle_state(
                db,
                item_id="mission-1",
                user_id="user-1",
            )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.PLAN_COMPLETION_CONFLICT_DETAIL


@pytest.mark.asyncio
@pytest.mark.parametrize("toggle_kind", ["item", "step"])
async def test_active_replacement_blocks_both_completion_endpoints(
    toggle_kind: str,
) -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {"job_id": JOB_A, "status": "partial"},
    }
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalar_one=_plan()),
        _Result(scalar_one=SimpleNamespace(id=JOB_B, status="running")),
    ]

    with patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)):
        with pytest.raises(HTTPException) as exc_info:
            if toggle_kind == "item":
                await plans.toggle_item_complete(
                    "mission-1",
                    db,
                    SimpleNamespace(id="user-1"),
                    artifact_job_id=JOB_A,
                )
            else:
                await plans.toggle_step_complete(
                    "mission-1",
                    "step_1",
                    db,
                    SimpleNamespace(id="user-1"),
                    artifact_job_id=JOB_A,
                )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.STEP_COMPLETION_CONFLICT_DETAIL
    assert db.execute.await_count == 2
    db.scalar.assert_not_awaited()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("toggle_kind", ["item", "step"])
@pytest.mark.parametrize("provided_artifact_job_id", [None, JOB_A])
async def test_missing_or_cached_token_cannot_mutate_replacement_checkpoint(
    toggle_kind: str,
    provided_artifact_job_id: str | None,
) -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {
            "job_id": JOB_B,
            "status": "partial",
            "supersedes_artifact": True,
        },
    }
    db = AsyncMock()
    db.scalar.side_effect = [JOB_B, JOB_A]
    db.execute.side_effect = [
        _Result(scalar_one=_plan()),
        _Result(scalar_one=SimpleNamespace(id=JOB_B, status="running")),
    ]

    with patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)):
        with pytest.raises(HTTPException) as exc_info:
            if toggle_kind == "item":
                await plans.toggle_item_complete(
                    "mission-1",
                    db,
                    SimpleNamespace(id="user-1"),
                    artifact_job_id=provided_artifact_job_id,
                )
            else:
                await plans.toggle_step_complete(
                    "mission-1",
                    "step_1",
                    db,
                    SimpleNamespace(id="user-1"),
                    artifact_job_id=provided_artifact_job_id,
                )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.STEP_COMPLETION_CONFLICT_DETAIL
    assert db.execute.await_count == 2
    if provided_artifact_job_id is None:
        assert db.scalar.await_count == 1
    else:
        db.scalar.assert_not_awaited()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_current_artifact_token_passes_serialized_toggle_gate() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {"job_id": JOB_B, "status": "partial"},
    }
    plan = _plan()
    active_job = SimpleNamespace(id=JOB_B, status="running")
    db = AsyncMock()
    db.scalar.return_value = JOB_B
    db.execute.side_effect = [
        _Result(scalar_one=plan),
        _Result(scalar_one=active_job),
    ]

    with patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)):
        locked_plan, locked_item, scope = await plans._lock_plan_item_toggle_state(
            db,
            item_id="mission-1",
            user_id="user-1",
            expected_artifact_job_id=JOB_B,
        )

    assert locked_plan is plan
    assert locked_item is item
    assert scope is None
    db.scalar.assert_awaited_once()


@pytest.mark.asyncio
async def test_first_generation_remains_compatible_without_artifact_token() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {"job_id": JOB_A, "status": "partial"},
    }
    plan = _plan()
    active_job = SimpleNamespace(id=JOB_A, status="running")
    db = AsyncMock()
    db.scalar.side_effect = [JOB_A, None]
    db.execute.side_effect = [
        _Result(scalar_one=plan),
        _Result(scalar_one=active_job),
    ]

    with patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)):
        locked_plan, locked_item, scope = await plans._lock_plan_item_toggle_state(
            db,
            item_id="mission-1",
            user_id="user-1",
        )

    assert locked_plan is plan
    assert locked_item is item
    assert scope is None
    assert db.scalar.await_count == 1


@pytest.mark.asyncio
async def test_failed_unpublished_job_does_not_remove_first_artifact_compatibility() -> (
    None
):
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {
            "job_id": JOB_B,
            "status": "ready",
            "supersedes_artifact": False,
        },
    }
    db = AsyncMock()
    # JOB_A may exist as failed history, but only B's durable publication marker
    # determines whether a tokenless client is ambiguous.
    db.scalar.return_value = JOB_B

    await plans._validate_expected_artifact(
        db,
        item,
        user_id="user-1",
        expected_job_id=None,
    )

    db.scalar.assert_awaited_once()


@pytest.mark.asyncio
async def test_second_item_toggle_reads_completion_only_after_serialization() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    plan = _plan()
    completion = SimpleNamespace(completed_at=datetime.now(timezone.utc))
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.return_value = datetime.now(timezone.utc)
    db.execute.side_effect = [
        _Result(scalar_one=completion),
    ]

    async def serialize_before_read(*_args, **_kwargs):
        assert db.execute.await_count == 0
        return plan, item, None

    lock_state = AsyncMock(side_effect=serialize_before_read)
    progress = ItemProgress(completed_steps=0, total_steps=0, percent=0)
    with (
        patch.object(plans, "_lock_plan_item_toggle_state", lock_state),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(return_value=(progress, False)),
        ),
        patch.object(
            plans,
            "_reconcile_plan_completion",
            AsyncMock(return_value=(False, 1)),
        ),
    ):
        response = await plans.toggle_item_complete(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )

    assert response.completed is False
    assert completion.completed_at is None
    db.add.assert_not_called()
    db.commit.assert_awaited_once_with()
    completion_query = db.execute.await_args_list[0].args[0]
    assert completion_query._for_update_arg is not None


@pytest.mark.asyncio
async def test_revoked_catalog_item_cannot_be_locally_uncompleted() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1"}],
        "_generation": {
            "content_origin": "catalog_personalized",
            "status": "revoked",
            "personalization_status": "revoked",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1"],
        },
    }
    assignment = SimpleNamespace(
        personalized_lesson_version_id="lesson-1",
        status=AssignmentStatus.COMPLETED,
        completed_at=datetime.now(timezone.utc),
        started_at=None,
    )
    scope = plans._CatalogAssignmentCompletionScope(
        frozenset({"lesson-1"}),
        (assignment,),
    )
    completion = SimpleNamespace(completed_at=datetime.now(timezone.utc))
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result(scalar_one=completion)

    with patch.object(
        plans,
        "_lock_plan_item_toggle_state",
        AsyncMock(return_value=(_plan(), item, scope)),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await plans.toggle_item_complete(
                "mission-1",
                db,
                SimpleNamespace(id="user-1"),
            )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.CATALOG_ASSIGNMENT_CONFLICT_DETAIL
    assert completion.completed_at is not None
    assert assignment.status == AssignmentStatus.COMPLETED
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_item_uncomplete_keeps_steps_and_assignments_completed() -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {
        "steps": [
            {"id": "step_1", "personalized_lesson_version_id": "lesson-1"},
            {"id": "step_2", "personalized_lesson_version_id": "lesson-2"},
        ],
        "_generation": {
            "content_origin": "catalog_personalized",
            "status": "ready",
            "personalization_status": "ready",
            "personalized_lesson_version_id": "lesson-1",
            "personalized_lesson_version_ids": ["lesson-1", "lesson-2"],
        },
    }
    now = datetime.now(timezone.utc)
    assignments = tuple(
        SimpleNamespace(
            personalized_lesson_version_id=lesson_id,
            status=AssignmentStatus.COMPLETED,
            completed_at=now,
            started_at=now,
        )
        for lesson_id in ("lesson-1", "lesson-2")
    )
    scope = plans._CatalogAssignmentCompletionScope(
        frozenset({"lesson-1", "lesson-2"}),
        assignments,
    )
    completion = SimpleNamespace(completed_at=now)
    plan = _plan(completed_at=now)
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.return_value = now
    db.execute.return_value = _Result(scalar_one=completion)
    progress = ItemProgress(completed_steps=2, total_steps=2, percent=100)

    with (
        patch.object(
            plans,
            "_lock_plan_item_toggle_state",
            AsyncMock(return_value=(plan, item, scope)),
        ),
        patch(
            "app.services.planning.catalog_lessons."
            "catalog_details_are_personalized_and_ready",
            return_value=True,
        ),
        patch(
            "app.services.planning.catalog_lessons."
            "catalog_details_are_ready_in_database",
            AsyncMock(return_value=True),
        ),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(return_value=(progress, False)),
        ),
        patch.object(
            plans,
            "_reconcile_plan_completion",
            AsyncMock(return_value=(False, 1)),
        ),
    ):
        response = await plans.toggle_item_complete(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )

    assert response.completed is False
    assert response.progress.percent == 100
    assert completion.completed_at is None
    assert item.status == PlanItemStatus.IN_PROGRESS
    assert item.progress_percent == 100
    assert all(row.status == AssignmentStatus.COMPLETED for row in assignments)
    assert all(row.completed_at == now for row in assignments)
    assert db.flush.await_count == 2
    db.commit.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_reused_step_id_creates_new_artifact_completion() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    database_completion_time = datetime(2026, 7, 1, 12, 1, tzinfo=timezone.utc)
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "lesson_content": "substance " * 2200,
            }
        ],
        # Deliberately skewed application metadata must not affect a modern
        # artifact whose authoritative epoch is the database job row.
        "generated_at": "2099-01-01T00:00:00+00:00",
        "_generation": {
            "job_id": JOB_B,
            "status": "ready",
            "updated_at": "2099-01-01T00:00:00+00:00",
        },
    }
    plan = _plan()
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.side_effect = [
        database_completion_time,
        1,
        1,
    ]
    db.execute.side_effect = [
        _Result(scalar_one=None),
        _Result(scalar_one=SimpleNamespace(id=JOB_B, status="completed")),
        _Result(scalar_one=None),
        _Result(scalars=[item]),
        _Result(scalars=["mission-1"]),
    ]
    progress = ItemProgress(completed_steps=1, total_steps=1, percent=100)

    with (
        patch.object(
            plans,
            "_lock_plan_item_toggle_state",
            AsyncMock(return_value=(plan, item, None)),
        ),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(return_value=(progress, False)),
        ),
    ):
        response = await plans.toggle_step_complete(
            "mission-1",
            "step_1",
            db,
            SimpleNamespace(id="user-1"),
            artifact_job_id=JOB_B,
        )

    assert response.completed is True
    assert response.item_completed is True
    added_rows = [call.args[0] for call in db.add.call_args_list]
    assert len(added_rows) == 2
    assert added_rows[0].artifact_job_id == JOB_B
    assert added_rows[1].artifact_job_id == JOB_B
    db.commit.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_old_prior_step_cannot_unlock_replacement_lesson() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "step_1", "lesson_content": "substance " * 2200},
            {"id": "step_2", "lesson_content": "substance " * 2200},
        ],
        "generated_at": "2026-07-29T12:30:00+00:00",
        "_generation": {
            "job_id": JOB_B,
            "status": "ready",
            "updated_at": "2026-07-29T12:30:00+00:00",
        },
    }
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalar_one=None),
        _Result(scalars=[]),
    ]

    with patch.object(
        plans,
        "_lock_plan_item_toggle_state",
        AsyncMock(return_value=(_plan(), item, None)),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await plans.toggle_step_complete(
                "mission-1",
                "step_2",
                db,
                SimpleNamespace(id="user-1"),
                artifact_job_id=JOB_B,
            )

    assert exc_info.value.status_code == 409
    assert "earlier lessons" in str(exc_info.value.detail)
    prior_statement = db.execute.await_args_list[1].args[0]
    rendered = str(prior_statement)
    assert "artifact_job_id" in rendered
    assert "completed_at >=" not in rendered
    assert JOB_B in prior_statement.compile().params.values()
    assert ["step_1"] in prior_statement.compile().params.values()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_missing_modern_job_get_queues_recovery_even_if_item_was_complete() -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "title": "Orphaned lesson",
                "lesson_content": "substance " * 2200,
            }
        ],
        "_generation": {"job_id": JOB_MISSING, "status": "ready"},
    }
    db = AsyncMock()
    db.add = MagicMock(side_effect=lambda row: setattr(row, "id", JOB_B))
    db.execute.return_value = _Result(scalar_one=None)
    snapshot = (
        ItemProgress(completed_steps=1, total_steps=1, percent=100),
        True,
        ["step_1"],
    )

    with (
        patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)),
        patch.object(
            plans,
            "_item_progress_snapshot",
            AsyncMock(return_value=snapshot),
        ),
        patch.object(
            plans,
            "_lesson_details_meet_runtime_quality",
            AsyncMock(return_value=False),
        ),
        patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue,
    ):
        response = await plans.get_plan_item_detailed(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )

    assert response.details_status == DetailsStatus.PENDING
    assert response.job_id == JOB_B
    assert response.completed is False
    assert response.item.status == PlanItemStatus.NOT_STARTED
    enqueue.assert_called_once()


@pytest.mark.asyncio
async def test_regenerate_does_not_short_circuit_on_orphaned_modern_artifact() -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {"job_id": JOB_MISSING, "status": "ready"},
    }
    db = AsyncMock()
    db.scalar.return_value = None
    db.execute.side_effect = [
        _Result(scalar_one=None),
        _Result(scalar_one="old-current-completion"),
    ]
    db.add = MagicMock(side_effect=lambda row: setattr(row, "id", JOB_B))

    with (
        patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)),
        patch.object(
            plans,
            "_lesson_details_meet_runtime_quality",
            AsyncMock(return_value=False),
        ),
        patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue,
    ):
        response = await plans.regenerate_item_details(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )

    assert response.job_id == JOB_B
    enqueue.assert_called_once_with(args=[JOB_B], queue="high_priority")


@pytest.mark.asyncio
async def test_malformed_modern_job_id_fails_closed_without_uuid_query() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {"job_id": "not-a-uuid", "status": "ready"},
    }
    db = AsyncMock()

    with pytest.raises(HTTPException) as exc_info:
        await plans._validate_expected_artifact(
            db,
            item,
            user_id="user-1",
            expected_job_id=None,
        )

    assert exc_info.value.status_code == 409
    db.scalar.assert_not_awaited()
    assert not await plans._lesson_details_meet_runtime_quality(
        db,
        item.details_json,
        user_id="user-1",
        plan_item_id="mission-1",
    )
    db.execute.assert_not_awaited()


@pytest.mark.parametrize("malformed_steps", MALFORMED_LESSON_STEPS)
def test_malformed_steps_fail_closed_across_detail_publication_guards(
    malformed_steps: object,
) -> None:
    details = {
        "steps": malformed_steps,
        "_generation": {
            "status": "partial",
            "ready_step_ids": ["step_1"],
        },
    }
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = details
    job = SimpleNamespace(id=JOB_B, supersedes_artifact=False)

    assert validated_lesson_steps(details) is None
    assert plans._parse_item_details(details) is None
    assert plans._current_step_ids(item) == ()
    assert plan_tasks._details_have_usable_lesson(details) is False
    assert plan_tasks._details_ready_for_prefetch(details) is False
    assert plans._lesson_details_meet_quality(details) is False
    assert plans._partial_lesson_details_available(details) is False
    assert plan_tasks._prepare_detail_artifact_publish(item, job) is False
    assert job.supersedes_artifact is False
    assert item.status == PlanItemStatus.NOT_STARTED
    assert item.progress_percent == 0


def test_lesson_step_invariant_accepts_unique_trimmed_string_ids() -> None:
    details = {
        "steps": [
            {"id": "step_1", "lesson_content": "substance " * 2200},
            {"id": "step_2", "lesson_content": "practice " * 2200},
            {"id": "valuation", "lesson_content": "reflection " * 2200},
        ]
    }
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = details

    steps = validated_lesson_steps(details)
    parsed = plans._parse_item_details(details)

    assert steps is not None
    assert tuple(step["id"] for step in steps) == (
        "step_1",
        "step_2",
        "valuation",
    )
    assert plans._current_step_ids(item) == ("step_1", "step_2", "valuation")
    assert parsed is not None
    assert [step.id for step in parsed.steps] == [
        "step_1",
        "step_2",
        "valuation",
    ]
    assert plans._lesson_details_meet_quality(details) is True
    assert plan_tasks._details_have_usable_lesson(details) is True
    assert plan_tasks._details_ready_for_prefetch(details) is True


@pytest.mark.parametrize(
    ("invalid_alias", "valid_alias", "invalid_value"),
    FALSY_INVALID_TIMING_ALIAS_CASES,
)
def test_lesson_timing_aliases_validate_each_present_value(
    invalid_alias: str,
    valid_alias: str,
    invalid_value: object,
) -> None:
    step = {
        "id": "step_1",
        "lesson_content": "substance " * 2200,
        invalid_alias: invalid_value,
        valid_alias: 15,
    }
    details = {"steps": [step]}

    assert validated_lesson_steps(details) is None
    assert plans._parse_item_details(details) is None
    assert plans._lesson_details_meet_quality(details) is False
    assert plan_tasks._details_have_usable_lesson(details) is False


@pytest.mark.parametrize(
    ("materials", "expected_valid"),
    [
        pytest.param(None, True, id="optional-null"),
        pytest.param("broken", False, id="scalar"),
        pytest.param([7], False, id="non-object-entry"),
        pytest.param([{"title": "Source", "ideas": "broken"}], False, id="ideas-scalar"),
        pytest.param([{"title": "Source", "ideas": [7]}], False, id="ideas-entry"),
    ],
)
def test_material_shape_is_parser_safe_or_fails_closed(
    materials: object,
    expected_valid: bool,
) -> None:
    details = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "materials": materials,
    }

    parsed_materials = validated_lesson_materials(details)

    assert (parsed_materials is not None) is expected_valid
    assert plans._lesson_details_meet_quality(details) is expected_valid
    assert (plans._parse_item_details(details) is not None) is expected_valid
    assert plan_tasks._details_have_usable_lesson(details) is expected_valid
    assert plan_tasks._details_ready_for_prefetch(details) is expected_valid


@pytest.mark.parametrize(
    "malformed_top_level",
    [
        {"generated_at": 7},
        {"generated_from_prompt_version": {"bad": "shape"}},
    ],
)
def test_detail_parser_and_readiness_fail_closed_on_schema_validation(
    malformed_top_level: dict,
) -> None:
    details = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {
            "status": "partial",
            "ready_step_ids": ["step_1"],
        },
        **malformed_top_level,
    }

    assert plans._parse_item_details(details) is None
    assert plans._lesson_details_meet_quality(details) is False
    assert plans._partial_lesson_details_available(details) is False


@pytest.mark.parametrize(
    "ready_step_ids",
    [
        None,
        "step_1",
        [7],
        [],
        ["   "],
        ["step_1", "step_1"],
        [" padded "],
        ["x" * 101],
        ["unknown"],
        ["step_1", "unknown"],
    ],
)
def test_partial_readiness_rejects_malformed_ready_step_ids(
    ready_step_ids: object,
) -> None:
    details = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {
            "job_id": JOB_WITH_HEX,
            "status": "partial",
            "ready_step_ids": ready_step_ids,
        },
    }

    assert plans._partial_lesson_details_available(details) is False
    assert progress_eligible_step_ids(details) == ()


def test_partial_readiness_rejects_missing_ready_step_ids() -> None:
    details = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {"job_id": JOB_WITH_HEX, "status": "partial"},
    }

    assert plans._partial_lesson_details_available(details) is False
    assert progress_eligible_step_ids(details) == ()


def test_partial_status_without_marker_still_requires_ready_checkpoint() -> None:
    details = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {"status": "partial"},
    }

    assert progress_eligible_step_ids(details) == ()
    assert plans._partial_lesson_details_available(details) is False


def test_progressive_eligible_steps_preserve_order_and_require_substance() -> None:
    details = {
        "steps": [
            {"id": "step_1", "lesson_content": "first " * 2200},
            {"id": "step_2", "lesson_content": "second " * 2200},
            {"id": "step_3", "lesson_content": "too short"},
            {"id": "step_4", "lesson_content": "hidden " * 2200},
        ],
        "_generation": {
            "job_id": JOB_WITH_HEX,
            "status": "partial",
            "ready_step_ids": ["step_2", "step_3", "step_1"],
        },
    }

    assert progress_eligible_step_ids(details) == ("step_1", "step_2")
    assert plans._partial_lesson_details_available(details) is True


def test_progressive_explicit_prior_query_cannot_count_hidden_step() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {"id": "step_1", "lesson_content": "hidden " * 2200},
            {"id": "step_2", "lesson_content": "ready " * 2200},
        ],
        "_generation": {
            "job_id": JOB_WITH_HEX,
            "status": "partial",
            "ready_step_ids": ["step_2"],
        },
    }

    predicates = plans._current_step_completion_predicates(
        item,
        user_id="user-1",
        step_ids=["step_1"],
    )
    statement = select(plans.PlanItemStepCompletion.id).where(*predicates)

    assert [] in statement.compile().params.values()


@pytest.mark.parametrize("status_value", [None, "failed", "outline", "unknown"])
def test_invalid_modern_generation_status_has_no_progress_eligible_steps(
    status_value: str | None,
) -> None:
    generation = {"job_id": JOB_WITH_HEX}
    if status_value is not None:
        generation["status"] = status_value
    details = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": generation,
    }
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = details

    assert progress_eligible_step_ids(details) == ()
    item_statement = select(plans.PlanItemCompletion.id).where(
        *plans.current_item_completion_predicates(item, user_id="user-1")
    )
    assert "WHERE false" in str(item_statement)


@pytest.mark.parametrize("status_value", [None, "failed", "outline", "unknown"])
def test_explicit_invalid_status_hides_legacy_step_rows_but_keeps_item_identity(
    status_value: str | None,
) -> None:
    details = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {"status": status_value},
    }
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = details

    assert progress_eligible_step_ids(details) == ()
    item_statement = select(plans.PlanItemCompletion.id).where(
        *plans.current_item_completion_predicates(item, user_id="user-1")
    )
    assert "WHERE false" not in str(item_statement)


@pytest.mark.parametrize("status_value", ["ready", "revoked"])
def test_terminal_modern_generation_status_preserves_full_progress_identity(
    status_value: str,
) -> None:
    details = {
        "steps": [
            {"id": "step_1", "lesson_content": "short"},
            {"id": "step_2", "lesson_content": None},
        ],
        "_generation": {"job_id": JOB_WITH_HEX, "status": status_value},
    }
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = details

    assert progress_eligible_step_ids(details) == ("step_1", "step_2")
    item_statement = select(plans.PlanItemCompletion.id).where(
        *plans.current_item_completion_predicates(item, user_id="user-1")
    )
    assert "WHERE false" not in str(item_statement)


@pytest.mark.asyncio
@pytest.mark.parametrize("raw_job_id", [None, ""])
async def test_falsy_modern_job_marker_never_uses_legacy_terminal_shortcut(
    raw_job_id: str | None,
) -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {"job_id": raw_job_id, "status": "ready"},
    }
    db = AsyncMock()
    db.add = MagicMock(side_effect=lambda row: setattr(row, "id", JOB_B))
    db.execute.return_value = _Result(scalar_one=None)
    completed_snapshot = (
        ItemProgress(completed_steps=1, total_steps=1, percent=100),
        True,
        ["step_1"],
    )

    with (
        patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)),
        patch.object(
            plans,
            "_item_progress_snapshot",
            AsyncMock(return_value=completed_snapshot),
        ),
        patch.object(
            plans,
            "_lesson_details_meet_runtime_quality",
            AsyncMock(return_value=False),
        ),
        patch("app.tasks.plans.regenerate_plan_item_details.apply_async") as enqueue,
    ):
        response = await plans.get_plan_item_detailed(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )

    assert response.details_status == DetailsStatus.PENDING
    assert response.completed is False
    assert response.item.status == PlanItemStatus.NOT_STARTED
    assert response.job_id == JOB_B
    enqueue.assert_called_once()


@pytest.mark.asyncio
async def test_first_job_replacing_legacy_artifact_requires_its_token() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "legacy " * 2200}],
    }
    job = SimpleNamespace(id=JOB_B, supersedes_artifact=False)

    marker = plan_tasks._prepare_detail_artifact_publish(item, job)

    assert marker is True
    assert job.supersedes_artifact is True
    assert item.status == PlanItemStatus.NOT_STARTED
    assert item.progress_percent == 0

    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "modern " * 2200}],
        "_generation": {
            "job_id": JOB_B,
            "status": "ready",
            "supersedes_artifact": marker,
        },
    }
    db = AsyncMock()
    db.scalar.return_value = JOB_B
    with pytest.raises(HTTPException) as exc_info:
        await plans._validate_expected_artifact(
            db,
            item,
            user_id="user-1",
            expected_job_id=None,
        )

    assert exc_info.value.status_code == 409


@pytest.mark.asyncio
async def test_superseded_worker_cannot_claim_or_publish_newer_artifact_slot() -> None:
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "new B " * 2200}],
        "_generation": {"job_id": JOB_B, "status": "partial"},
    }
    original_details = item.details_json
    newer_job = SimpleNamespace(id=JOB_B, status="queued")
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalar_one=_plan()),
        _Result(scalar_one=item),
        _Result(scalar_one=newer_job),
    ]

    with pytest.raises(plan_tasks.DetailArtifactPublicationSuperseded):
        await plan_tasks._prepare_current_detail_artifact_publication(
            db,
            plan_id="plan-1",
            item_id="mission-1",
            user_id="user-1",
            job_id=JOB_A,
        )

    assert item.details_json is original_details
    assert item.status == PlanItemStatus.COMPLETED
    assert item.progress_percent == 100
    db.commit.assert_not_awaited()
    assert all(
        call.args[0]._for_update_arg is not None
        for call in db.execute.await_args_list
    )
    latest_job_statement = db.execute.await_args_list[-1].args[0]
    rendered = str(latest_job_statement)
    assert "artifact_epoch_at DESC" in rendered
    assert "status IN" not in rendered


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("successor_id", "expected_completed"),
    [(None, None), ("successor-plan", "preserved")],
)
async def test_replacement_checkpoint_resets_item_and_reconciles_plan_stamp(
    successor_id: str | None,
    expected_completed: str | None,
) -> None:
    completed_at = datetime.now(timezone.utc)
    plan = _plan(completed_at=completed_at)
    item = _item(
        "mission-1",
        PlanItemType.COURSE,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    item.progress_percent = 100
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "artifact A " * 2200}],
        "_generation": {"job_id": JOB_A, "status": "ready"},
    }
    job = SimpleNamespace(
        id=JOB_B,
        status="running",
        supersedes_artifact=False,
    )
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalar_one=plan),
        _Result(scalar_one=item),
        _Result(scalar_one=job),
    ]
    db.scalar.return_value = successor_id

    (
        locked_plan,
        locked_item,
        locked_job,
        artifact_changed,
        supersedes_artifact,
    ) = await plan_tasks._prepare_current_detail_artifact_publication(
        db,
        plan_id="plan-1",
        item_id="mission-1",
        user_id="user-1",
        job_id=JOB_B,
    )
    locked_item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "artifact B " * 2200}],
        "_generation": {"job_id": JOB_B, "status": "partial"},
    }
    await plan_tasks._reconcile_plan_after_detail_artifact_publish(
        db,
        plan=locked_plan,
        item=locked_item,
        artifact_changed=artifact_changed,
    )

    assert locked_job is job
    assert artifact_changed is True
    assert supersedes_artifact is True
    assert locked_item.status == PlanItemStatus.NOT_STARTED
    assert locked_item.progress_percent == 0
    if expected_completed is None:
        assert locked_plan.completed_at is None
    else:
        assert locked_plan.completed_at == completed_at
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "item_type",
    [PlanItemType.HABIT, PlanItemType.PRACTICE, PlanItemType.REFLECTION],
)
async def test_non_mission_detail_publication_never_reopens_completed_plan(
    item_type: PlanItemType,
) -> None:
    completed_at = datetime.now(timezone.utc)
    plan = _plan(completed_at=completed_at)
    item = _item("non-mission-1", item_type, 1)
    db = AsyncMock()

    await plan_tasks._reconcile_plan_after_detail_artifact_publish(
        db,
        plan=plan,
        item=item,
        artifact_changed=True,
    )

    assert plan.completed_at == completed_at
    db.scalar.assert_not_awaited()


@pytest.mark.asyncio
async def test_missing_generation_job_fails_before_step_mutation() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "generated_at": "2026-07-29T12:00:00+00:00",
        "_generation": {
            "job_id": JOB_MISSING,
            "status": "ready",
            "updated_at": "2026-07-29T12:30:00+00:00",
        },
    }
    db = AsyncMock()
    db.scalar.return_value = None
    db.execute.side_effect = [
        _Result(scalar_one=_plan()),
        _Result(scalar_one=None),
    ]

    with patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)):
        with pytest.raises(HTTPException) as exc_info:
            await plans.toggle_step_complete(
                "mission-1",
                "step_1",
                db,
                SimpleNamespace(id="user-1"),
                artifact_job_id=JOB_MISSING,
            )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.STEP_COMPLETION_CONFLICT_DETAIL
    assert db.execute.await_count == 2
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_item_completion_validates_missing_generation_job_before_mutation() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [{"id": "step_1", "lesson_content": "substance " * 2200}],
        "_generation": {
            "job_id": JOB_MISSING,
            "status": "ready",
        },
    }
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        _Result(scalar_one=_plan()),
        _Result(scalar_one=None),
    ]
    db.scalar.return_value = None

    with patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)):
        with pytest.raises(HTTPException) as exc_info:
            await plans.toggle_item_complete(
                "mission-1",
                db,
                SimpleNamespace(id="user-1"),
                artifact_job_id=JOB_MISSING,
            )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == plans.STEP_COMPLETION_CONFLICT_DETAIL
    assert item.status == PlanItemStatus.NOT_STARTED
    db.add.assert_not_called()
    db.flush.assert_not_awaited()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_step_uncomplete_reconciles_item_and_plan_in_one_commit() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "lesson_content": "substance " * 2200,
            }
        ]
    }
    now = datetime.now(timezone.utc)
    plan = _plan(completed_at=now)
    step_completion = SimpleNamespace(completed_at=now)
    item_completion = SimpleNamespace(completed_at=now)
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        _Result(scalar_one=step_completion),
        _Result(scalar_one=item_completion),
        _Result(scalars=[item]),
        _Result(scalars=[]),
    ]
    db.scalar.side_effect = [now, 0]

    async def serialize_before_read(*_args, **_kwargs):
        assert db.execute.await_count == 0
        return plan, item, None

    progress = ItemProgress(completed_steps=0, total_steps=1, percent=0)
    with (
        patch.object(
            plans,
            "_lock_plan_item_toggle_state",
            AsyncMock(side_effect=serialize_before_read),
        ),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(return_value=(progress, False)),
        ),
    ):
        response = await plans.toggle_step_complete(
            "mission-1",
            "step_1",
            db,
            SimpleNamespace(id="user-1"),
        )

    assert response.completed is False
    assert response.item_completed is False
    assert step_completion.completed_at is None
    assert item_completion.completed_at is None
    assert item.status == PlanItemStatus.NOT_STARTED
    assert plan.completed_at is None
    assert db.flush.await_count == 2
    db.commit.assert_awaited_once_with()
    assert db.execute.await_args_list[0].args[0]._for_update_arg is not None
    assert db.execute.await_args_list[1].args[0]._for_update_arg is not None


@pytest.mark.asyncio
async def test_last_step_completion_marks_item_and_plan_complete() -> None:
    item = _item("mission-1", PlanItemType.COURSE, 1)
    item.details_json = {
        "steps": [
            {
                "id": "step_1",
                "lesson_content": "substance " * 2200,
            }
        ]
    }
    plan = _plan()
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [
        _Result(scalar_one=None),
        _Result(scalar_one=None),
        _Result(scalar_one=None),
        _Result(scalars=[item]),
        _Result(scalars=["mission-1"]),
    ]
    # The one-week plan has no next week to prefetch after the commit.
    db.scalar.side_effect = [datetime.now(timezone.utc), 1]
    progress = ItemProgress(completed_steps=1, total_steps=1, percent=100)

    with (
        patch.object(
            plans,
            "_lock_plan_item_toggle_state",
            AsyncMock(return_value=(plan, item, None)),
        ),
        patch.object(
            plans,
            "_compute_item_progress",
            AsyncMock(return_value=(progress, False)),
        ),
    ):
        response = await plans.toggle_step_complete(
            "mission-1",
            "step_1",
            db,
            SimpleNamespace(id="user-1"),
        )

    assert response.completed is True
    assert response.item_completed is True
    assert item.status == PlanItemStatus.COMPLETED
    assert item.progress_percent == 100
    assert plan.completed_at is not None
    assert db.add.call_count == 2
    assert db.flush.await_count == 2
    db.commit.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_completed_legacy_mission_never_enqueues_or_polls_details() -> None:
    item = _item(
        "mission-complete",
        PlanItemType.PROJECT,
        1,
        status=PlanItemStatus.COMPLETED,
    )
    db = AsyncMock()
    db.execute.return_value = _Result(scalars=[])
    original_get = plans._get_item_for_user
    original_progress = plans._compute_item_progress
    plans._get_item_for_user = AsyncMock(return_value=item)
    plans._compute_item_progress = AsyncMock(
        return_value=(ItemProgress(percent=100), True)
    )
    try:
        response = await plans.get_plan_item_detailed(
            "mission-complete",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get
        plans._compute_item_progress = original_progress

    assert response.completed is True
    assert response.details_status == DetailsStatus.AVAILABLE
    assert response.job_id is None
    assert db.execute.await_count == 2
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_stale_detail_job_stops_and_requires_explicit_retry() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    stale_time = datetime(2020, 1, 1, tzinfo=timezone.utc)
    stale_job = SimpleNamespace(
        id="job-stale",
        status="running",
        step="generating",
        progress_percent=60,
        error_message=None,
        created_at=stale_time,
        updated_at=stale_time,
    )
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=None)
    db.execute.side_effect = [
        _Result(scalars=[]),
        _Result(scalar_one=stale_job),
    ]
    original_get = plans._get_item_for_user
    original_progress = plans._compute_item_progress
    plans._get_item_for_user = AsyncMock(return_value=item)
    plans._compute_item_progress = AsyncMock(return_value=(ItemProgress(), False))
    try:
        response = await plans.get_plan_item_detailed(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get
        plans._compute_item_progress = original_progress

    assert response.details_status == DetailsStatus.FAILED
    assert stale_job.status == "failed"
    assert db.add.call_count == 0
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_detail_retry_reuses_an_active_job() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    now = datetime.now(timezone.utc)
    active_job = SimpleNamespace(
        id="job-active",
        status="running",
        created_at=now,
        updated_at=now,
    )
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=active_job)
    original_get = plans._get_item_for_user
    get_item = AsyncMock(return_value=item)
    plans._get_item_for_user = get_item
    try:
        response = await plans.regenerate_item_details(
            "mission-1",
            db,
            SimpleNamespace(id="user-1"),
        )
    finally:
        plans._get_item_for_user = original_get

    assert response.job_id == "job-active"
    assert db.add.call_count == 0
    db.commit.assert_not_awaited()
    assert get_item.await_args.kwargs["for_update"] is True


@pytest.mark.asyncio
async def test_detail_retry_does_not_enqueue_when_lesson_is_already_ready() -> None:
    item = _item("mission-ready", PlanItemType.PROJECT, 1)
    item.details_json = {
        "steps": [
            {
                "id": f"step-{index}",
                "lesson_content": "word " * 2200,
            }
            for index in range(3)
        ]
    }
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=None)
    original_get = plans._get_item_for_user
    plans._get_item_for_user = AsyncMock(return_value=item)
    try:
        with patch(
            "app.tasks.plans.regenerate_plan_item_details.apply_async"
        ) as enqueue:
            response = await plans.regenerate_item_details(
                "mission-ready",
                db,
                SimpleNamespace(id="user-1"),
            )
    finally:
        plans._get_item_for_user = original_get

    assert response.job_id == ""
    enqueue.assert_not_called()
    db.execute.assert_awaited_once()
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_detail_retry_does_not_enqueue_an_authoritatively_completed_item() -> (
    None
):
    item = _item("mission-completed", PlanItemType.PROJECT, 1)
    completion = SimpleNamespace(id="completion-1")
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(scalar_one=None),  # no active detail job
        _Result(scalar_one=completion),  # authoritative completion record
    ]
    original_get = plans._get_item_for_user
    plans._get_item_for_user = AsyncMock(return_value=item)
    try:
        with patch(
            "app.tasks.plans.regenerate_plan_item_details.apply_async"
        ) as enqueue:
            response = await plans.regenerate_item_details(
                "mission-completed",
                db,
                SimpleNamespace(id="user-1"),
            )
    finally:
        plans._get_item_for_user = original_get

    assert response.job_id == ""
    enqueue.assert_not_called()
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_detail_retry_surfaces_prefetch_publish_failure_as_503() -> None:
    item = _item("mission-1", PlanItemType.PROJECT, 1)
    pending_job = SimpleNamespace(id="job-pending", status="pending")
    db = AsyncMock()
    db.execute.return_value = _Result(scalar_one=pending_job)
    original_get = plans._get_item_for_user
    original_promote = plans._promote_prefetched_detail_job
    plans._get_item_for_user = AsyncMock(return_value=item)
    plans._promote_prefetched_detail_job = AsyncMock(return_value="failed")
    try:
        with pytest.raises(HTTPException) as exc_info:
            await plans.regenerate_item_details(
                "mission-1",
                db,
                SimpleNamespace(id="user-1"),
            )
    finally:
        plans._get_item_for_user = original_get
        plans._promote_prefetched_detail_job = original_promote

    assert exc_info.value.status_code == 503
    assert db.add.call_count == 0


@pytest.mark.asyncio
async def test_detail_generation_lock_uses_owned_plan_item_row() -> None:
    item = _item("mission-locked", PlanItemType.PROJECT, 1)

    class Result:
        def scalar_one_or_none(self):
            return item

    class Database:
        statement = None

        async def execute(self, statement):
            self.statement = statement
            return Result()

    db = Database()
    result = await plans._get_item_for_user(
        db,
        "mission-locked",
        "user-1",
        for_update=True,
    )

    assert result is item
    assert db.statement._for_update_arg is not None
    assert "plans.user_id" in str(db.statement)
    assert "user-1" in db.statement.compile().params.values()
