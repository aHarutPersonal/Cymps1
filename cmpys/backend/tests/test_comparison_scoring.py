"""normalize_comparison_scores always yields the 5 fixed dims, clamped."""
from app.services.comparison.scoring import (
    normalize_comparison_scores,
    FIXED_DIMENSIONS,
)

FIXED_IDS = ["capital", "knowledge", "habits", "network", "clarity"]


def test_fixed_dimensions_are_the_five_ids():
    assert [d["id"] for d in FIXED_DIMENSIONS] == FIXED_IDS


def test_none_returns_full_seed_five_dims():
    out = normalize_comparison_scores(None)
    assert [d["id"] for d in out["dimensions"]] == FIXED_IDS
    assert out["milestones"] == []


def test_clamps_scores_and_fills_missing_dims():
    raw = {
        "dimensions": [
            {"id": "capital", "label": "Capital", "you": 250, "idol": -5,
             "you_note": "a", "idol_note": "b"},
            {"id": "knowledge", "label": "Knowledge", "you": 30, "idol": 80,
             "you_note": "c", "idol_note": "d"},
        ],
        "milestones": [{"text": "Wrote a philosophy", "hit_by_age": 21}],
    }
    out = normalize_comparison_scores(raw)
    assert [d["id"] for d in out["dimensions"]] == FIXED_IDS  # all 5 present
    cap = next(d for d in out["dimensions"] if d["id"] == "capital")
    assert cap["you"] == 100 and cap["idol"] == 0  # clamped
    assert out["milestones"][0]["id"] == "m1"
    assert out["milestones"][0]["label"] == "Wrote a philosophy"


def test_milestones_capped_at_five():
    raw = {"milestones": [{"text": f"m{i}"} for i in range(9)]}
    out = normalize_comparison_scores(raw)
    assert len(out["milestones"]) == 5
