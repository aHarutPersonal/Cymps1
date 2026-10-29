"""``GET /plan-items/{id}/detailed`` carries the mission's done-definition.

Outline/details generation and catalog composition already store
``definition_of_done`` and ``mental_model`` in ``details_json``. The mission
screen shows them as the "Definition of done" checklist and the night
"Mental model" card, so the detail response must pass them through. Both stay
optional so older stored lessons without them still parse.
"""

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.api.v1 import plans
from app.models.plan import PlanItem, PlanItemStatus, PlanItemType
from app.schemas.plan import DetailsStatus, ItemDetails, ItemProgress

JOB_ID = "33333333-3333-4333-8333-333333333333"


def _item(details_json: dict) -> PlanItem:
    now = datetime.now(timezone.utc)
    return PlanItem(
        id="mission-1",
        plan_id="plan-1",
        title="Write a one-page owner’s memo",
        type=PlanItemType.PROJECT,
        description="A concrete task description for detail coverage.",
        week_start=1,
        week_end=1,
        success_metric="A one-page memo a reviewer can act on",
        estimated_hours=1,
        status=PlanItemStatus.NOT_STARTED,
        progress_percent=0,
        meta_json=None,
        details_json=details_json,
        created_at=now,
        updated_at=now,
    )


class _Result:
    def scalar_one_or_none(self):
        return None


def _db() -> AsyncMock:
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = _Result()
    return db


async def _read(item: PlanItem):
    with (
        patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)),
        patch.object(
            plans,
            "_item_progress_snapshot",
            AsyncMock(return_value=(ItemProgress(), False, [])),
        ),
        patch.object(
            plans,
            "_lesson_details_meet_runtime_quality",
            AsyncMock(return_value=True),
        ),
    ):
        return await plans.get_plan_item_detailed(
            "mission-1", _db(), SimpleNamespace(id="user-1"), peek=True
        )


def _ready_details(**extra) -> dict:
    return {
        "steps": [
            {
                "id": "step_1",
                "title": "Ready lesson",
                "lesson_content": "substance " * 2200,
            }
        ],
        "_generation": {"job_id": JOB_ID, "status": "ready"},
        **extra,
    }


@pytest.mark.asyncio
async def test_detail_response_carries_definition_of_done_and_mental_model() -> None:
    details = _ready_details(
        definition_of_done="- Memo names one decision\n- A reviewer signs off",
        mental_model="Owner’s view: decide what the reader must do next.",
    )

    response = await _read(_item(details))

    assert response.details_status == DetailsStatus.AVAILABLE
    assert response.details is not None
    assert (
        response.details.definition_of_done
        == "- Memo names one decision\n- A reviewer signs off"
    )
    assert (
        response.details.mental_model
        == "Owner’s view: decide what the reader must do next."
    )
    body = response.model_dump(mode="json")
    assert body["details"]["definition_of_done"].startswith("- Memo")
    assert body["details"]["mental_model"].startswith("Owner’s view")


@pytest.mark.asyncio
async def test_detail_response_without_the_keys_still_parses() -> None:
    response = await _read(_item(_ready_details()))

    assert response.details is not None
    assert response.details.definition_of_done is None
    assert response.details.mental_model is None


def test_item_details_fields_are_optional_and_ignore_non_strings() -> None:
    assert ItemDetails().definition_of_done is None
    assert ItemDetails().mental_model is None
    parsed = plans._parse_item_details(
        {
            "steps": [{"id": "step_1", "title": "T"}],
            "definition_of_done": ["not", "a", "string"],
            "mental_model": "  ",
        }
    )
    assert parsed is not None
    assert parsed.definition_of_done is None
    assert parsed.mental_model is None
