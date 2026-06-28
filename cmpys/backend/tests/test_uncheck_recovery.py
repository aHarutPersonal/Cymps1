"""Un-check recovery clears completed_at only when no next cycle exists."""
from app.api.v1.plans import _should_clear_completed_at


def test_clears_when_set_and_no_next_cycle():
    assert _should_clear_completed_at(True, False) is True


def test_sticky_when_next_cycle_exists():
    assert _should_clear_completed_at(True, True) is False


def test_noop_when_not_completed():
    assert _should_clear_completed_at(False, False) is False
    assert _should_clear_completed_at(False, True) is False
