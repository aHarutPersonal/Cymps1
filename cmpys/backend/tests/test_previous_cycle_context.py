"""Previous-cycle block is empty for cycle 1, populated for cycle >= 2."""
from app.tasks.plans import build_previous_cycle_block


def test_cycle_one_is_empty():
    assert build_previous_cycle_block(1, "thesis", ["m"], ["a"]) == ""


def test_cycle_two_includes_directive_and_data():
    block = build_previous_cycle_block(
        2, "Master fundamentals", ["Read Security Analysis"], ["Wrote a teardown"]
    )
    assert "cycle 1" in block.lower()
    assert "Master fundamentals" in block
    assert "Read Security Analysis" in block
    assert "Wrote a teardown" in block
    assert "assume mastery" in block.lower()
