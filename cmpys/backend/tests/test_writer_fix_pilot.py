"""Pilot harness: complete outline titles, and the writer budget it exercises."""
import importlib.util
import json
from pathlib import Path

from app.services.llm.schemas import PlanDetailStepOutlineOutput
from app.services.planning.tutorial_capacity import pending_tutorial_allocation

ROOT = Path(__file__).resolve().parents[1]


def _pilot():
    spec = importlib.util.spec_from_file_location("pilot_generation", ROOT / "scripts" / "pilot_generation.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_outline_titles_are_complete_phrases_within_the_contract():
    pilot = _pilot()
    limit = PlanDetailStepOutlineOutput.model_fields["title"].metadata[0].max_length
    scenarios = json.loads((ROOT / "tests" / "fixtures" / "generation_scenarios.json").read_text())
    dangling = {"a", "an", "the", "and", "or", "of", "to", "for", "from", "with", "using", "in", "on", "by"}
    titles = {}
    for case in scenarios:
        title = pilot.tutorial_outline(case)["steps"][0]["title"]
        assert len(title) <= limit
        assert title.split()[-1].lower() not in dangling, title
        assert case["goal"].startswith(title), title
        titles[case["goal"]] = title
    assert titles["Distinguish accrual profit from cash using a fictional cafe ledger"] == \
        "Distinguish accrual profit from cash"
    assert titles["Derive a triangle area from stated perpendicular measurements"] == "Derive a triangle area"
    assert titles["Compare two defensible interpretations of a short supplied argument"] == \
        "Compare two defensible interpretations"
    assert titles["Design and test an idempotent job handler"] == "Design and test an idempotent job handler"


def test_pilot_writer_budget_matches_a_production_tutorial_job():
    """H2: the 0.1 h pilot mission and ordinary production missions both leave
    the writer's allotted_lesson_minutes unset (no capacity reallocation), so
    the pilot exercises the same two-call writer budget and length rule."""
    # Pilot: 0.1 h -> 6 allocated minutes, one tutorial planned at 6 minutes.
    assert pending_tutorial_allocation([], 0.1, pending_count=1, planned_minutes=6) is None
    # Production: 1 h over ten 6-minute tutorials, and 2 h over twenty.
    assert pending_tutorial_allocation([], 1.0, pending_count=10, planned_minutes=6) is None
    assert pending_tutorial_allocation([], 2.0, pending_count=20, planned_minutes=6) is None
