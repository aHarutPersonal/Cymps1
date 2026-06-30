"""Mission-task completion detection: daily habits never gate completion."""
from types import SimpleNamespace

from app.api.v1.plans import _count_remaining_missions, _should_clear_completed_at, MISSION_TYPES
from app.models.plan import PlanItemType


def _item(item_id, type_):
    return SimpleNamespace(id=item_id, type=type_)


def test_mission_types_are_project_course_reading():
    assert MISSION_TYPES == {
        PlanItemType.PROJECT, PlanItemType.COURSE, PlanItemType.READING
    }


def test_remaining_counts_only_incomplete_missions():
    items = [
        _item("a", PlanItemType.PROJECT),
        _item("b", PlanItemType.READING),
        _item("c", PlanItemType.HABIT),   # daily — ignored
        _item("d", PlanItemType.PRACTICE),  # daily — ignored
    ]
    # only "a" completed; "b" mission still open; habits irrelevant
    assert _count_remaining_missions(items, {"a"}) == 1


def test_remaining_zero_when_all_missions_done():
    items = [
        _item("a", PlanItemType.PROJECT),
        _item("c", PlanItemType.HABIT),
    ]
    assert _count_remaining_missions(items, {"a"}) == 0


def test_clears_when_set_and_no_next_cycle():
    assert _should_clear_completed_at(True, False) is True


def test_sticky_when_next_cycle_exists():
    assert _should_clear_completed_at(True, True) is False


def test_no_clear_when_never_completed():
    assert _should_clear_completed_at(False, False) is False
