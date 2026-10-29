"""R1-I1: the habit detail reports the same per-session minutes as Today.

``estimatedMinutes`` on a daily item is the WEEKLY allocation. Today shows one
session (``daily_tasks._session_minutes``); the detail screen must be able to
show that same number, so the daily branch of ``GET /plan-items/{id}/detailed``
adds an optional ``session_minutes`` to its item payload.
"""

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest

from app.api.v1 import plans
from app.api.v1.daily_tasks import _session_minutes
from app.models.plan import PlanItem, PlanItemStatus, PlanItemType
from app.schemas.plan import PlanItemResponse


def _item(item_type: PlanItemType, *, minutes: int, hours: int) -> PlanItem:
    now = datetime.now(timezone.utc)
    return PlanItem(
        id="habit-1",
        plan_id="plan-1",
        title="Read one annual report section",
        type=item_type,
        description="Read and note one owner-earnings detail.",
        week_start=1,
        week_end=1,
        success_metric="A dated note",
        estimated_hours=hours,
        status=PlanItemStatus.NOT_STARTED,
        progress_percent=0,
        meta_json={"estimated_minutes": minutes},
        created_at=now,
        updated_at=now,
    )


async def _detail(item: PlanItem):
    db = AsyncMock()
    db.scalar.return_value = 0
    with patch.object(plans, "_get_item_for_user", AsyncMock(return_value=item)):
        return await plans.get_plan_item_detailed(
            item.id, db, SimpleNamespace(id="user-1")
        )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("item_type", "minutes", "hours", "expected"),
    [
        # 60 weekly minutes: four 15-minute sessions (not round(60 / 7) = 9).
        (PlanItemType.HABIT, 60, 1, 15),
        # Under an hour: three sessions.
        (PlanItemType.PRACTICE, 45, 1, 15),
        # 105 weekly minutes: four sessions of 26.25, halves round up -> 26.
        (PlanItemType.HABIT, 105, 2, 26),
    ],
)
async def test_daily_detail_item_carries_todays_session_minutes(
    item_type, minutes, hours, expected
) -> None:
    item = _item(item_type, minutes=minutes, hours=hours)

    response = await _detail(item)

    assert response.item.estimatedMinutes == minutes  # still the weekly allocation
    assert response.item.session_minutes == expected
    assert response.item.session_minutes == _session_minutes(item)
    payload = response.model_dump(mode="json")
    assert payload["item"]["session_minutes"] == expected


def test_session_minutes_is_optional_and_absent_by_default() -> None:
    field = PlanItemResponse.model_fields["session_minutes"]
    assert field.is_required() is False and field.default is None
