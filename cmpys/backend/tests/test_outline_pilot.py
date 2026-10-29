"""The outline pilot measures the production outline request; no provider calls here."""
import json
from pathlib import Path

from app.tasks.plans import _plan_detail_lesson_count_bounds
from scripts.pilot_generation import OUTLINE_MISSIONS, outline_mission, summarize_outline_runs

CASES = {case["id"]: case for case in json.loads(
    (Path(__file__).parent / "fixtures/generation_scenarios.json").read_text())}


def test_outline_missions_cover_two_to_three_hour_sequences():
    assert [hours for _, hours in OUTLINE_MISSIONS] == [2.0, 2.5, 3.0]
    for scenario_id, hours in OUTLINE_MISSIONS:
        mission = outline_mission(CASES[scenario_id], hours)
        assert mission["title"] == CASES[scenario_id]["goal"]
        assert f"{hours:g} hours" in mission["description"]
    # The 3 h mission asks for the largest sequence the live run timed out on.
    assert _plan_detail_lesson_count_bounds(3.0, lesson_format="tutorial_v1") == (23, 36)


def test_summary_counts_only_valid_outlines_inside_the_cap():
    rows = [
        {"arm": "medium", "duration_ms": 50_000, "error": None, "cost_usd": 0.02, "lessons": 30},
        {"arm": "medium", "duration_ms": 30_000, "error": "timeout", "cost_usd": None, "lessons": 0},
        {"arm": "low", "duration_ms": 20_000, "error": None, "cost_usd": 0.01, "lessons": 20},
        {"arm": "low", "duration_ms": 40_000, "error": "", "cost_usd": 0.01, "lessons": 30},
    ]
    summary = summarize_outline_runs(rows)
    assert summary["medium"] == {"runs": 2, "valid": 1, "valid_within_cap": 0, "median_ms": 40_000,
                                 "max_ms": 50_000, "cost_usd": 0.02, "mean_lessons": 30.0}
    assert summary["low"]["valid_within_cap"] == 2
    assert summary["low"]["mean_lessons"] == 25.0
