"""Cycle summary degrades to a count-based narrative with no capstone."""
from app.services.achievements.suggestion import fallback_cycle_summary


def test_fallback_uses_count_and_no_capstone():
    out = fallback_cycle_summary(14)
    assert "14" in out["narrative"]
    assert out["capstoneTitle"] is None


def test_fallback_handles_zero():
    out = fallback_cycle_summary(0)
    assert out["narrative"]
    assert out["capstoneTitle"] is None
