"""Idempotency helper: an existing job for the parent is reused."""
from types import SimpleNamespace
import pytest

from app.api.v1.plans import _next_cycle_fields


def test_next_cycle_increments_and_links():
    prev = SimpleNamespace(
        id="p1", cycle_number=2, idol_id="i1", weekly_hours=10, target_age=25,
        duration_weeks=12,
    )
    fields = _next_cycle_fields(prev)
    assert fields["cycle_number"] == 3
    assert fields["previous_plan_id"] == "p1"
    assert fields["idol_id"] == "i1"
    assert fields["weekly_hours"] == 10
