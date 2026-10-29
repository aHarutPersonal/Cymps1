"""The mission syllabus is visible while tutorial 1 prepares; lesson text never is."""
import pytest

from app.api.v1.plans import _syllabus_details
from tests.test_short_tutorial_pipeline import outline


def _generating(steps, **generation):
    return {**outline(3), "steps": steps,
            "_generation": {"status": "generating", "ready_step_ids": [], "job_id": "job-1", **generation}}


def test_outline_steps_are_served_while_the_first_tutorial_prepares():
    details = _syllabus_details(_generating(outline(3)["steps"]))
    assert [step.title for step in details.steps] == [step["title"] for step in outline(3)["steps"]]
    assert all(not step.lesson_content for step in details.steps)


def test_unapproved_lesson_text_is_never_exposed():
    steps = outline(3)["steps"]
    steps[0] = {**steps[0], "lesson_content": "## Why This Matters\nUnreviewed draft text."}
    details = _syllabus_details(_generating(steps))
    assert all(not step.lesson_content for step in details.steps)


def test_syllabus_only_applies_before_any_approved_tutorial():
    assert _syllabus_details(_generating(outline(3)["steps"], ready_step_ids=["step_1"])) is None
    assert _syllabus_details(_generating(outline(3)["steps"], status="partial")) is None
    assert _syllabus_details(_generating([])) is None
    assert _syllabus_details(None) is None


@pytest.mark.asyncio
async def test_detailed_endpoint_serves_the_syllabus_while_the_owning_job_runs(monkeypatch):
    from types import SimpleNamespace
    from unittest.mock import AsyncMock, MagicMock
    from uuid import uuid4
    from datetime import datetime, timezone
    from app.api.v1 import plans as api
    from app.models.plan import PlanItemType
    from app.schemas.plan import DetailsStatus, ItemProgress
    from tests.test_plan_progression_regressions import _Result, _item

    now = datetime.now(timezone.utc)
    job = SimpleNamespace(id=str(uuid4()), status="running", step="outline_ready", progress_percent=62,
                          error_message=None, created_at=now, updated_at=now)
    item = _item(str(uuid4()), PlanItemType.PROJECT, 1)
    steps = outline(3)["steps"]
    steps[0] = {**steps[0], "lesson_content": "## Why This Matters\nUnreviewed draft text."}
    item.details_json = _generating(steps, job_id=job.id)
    db = AsyncMock()
    db.add = MagicMock()
    db.scalar.return_value = job.id
    db.execute.side_effect = [_Result(scalars=[]), _Result(scalar_one=job), _Result(scalar_one=job)]
    monkeypatch.setattr(api, "_get_item_for_user", AsyncMock(return_value=item))
    monkeypatch.setattr(api, "_compute_item_progress", AsyncMock(return_value=(
        ItemProgress(completed_steps=0, total_steps=3, percent=0.0), False)))
    response = await api.get_plan_item_detailed(item.id, db, SimpleNamespace(id=str(uuid4())))
    assert response.details_status == DetailsStatus.GENERATING
    assert [step.title for step in response.details.steps] == [step["title"] for step in outline(3)["steps"]]
    assert all(not step.lesson_content for step in response.details.steps)
    assert response.artifact_job_id is None
