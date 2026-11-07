"""Regressions from the 120-minute writing-plan simulator run."""
import pytest
from app.services.planning.generator import (
    public_plan_copy_issues, validate_plan_contract, validate_plan_backbone,
)
from app.services.llm.schemas import PlanBackboneResponse
from tests.test_plan_execution_contract import _plan


@pytest.mark.parametrize("text", [
    "Complete three short tutorials and save a claim.",
    "Complete 14 tutorials and revise the draft.",
    "Your needs_review result requires another attempt.",
])
def test_week_expansion_rejects_premature_counts_and_internal_states(text):
    plan = _plan([1])
    plan.weeks[0].binary_tasks[0].description += " " + text
    issues = validate_plan_contract(plan, duration_weeks=1, hours_per_week=6)
    assert len(issues) == 1
    assert "description" in issues[0]


def test_backbone_rejects_raw_state_in_success_criterion():
    plan = PlanBackboneResponse.model_validate({
        "roadmap_thesis": "Improve claim clarity through supported practice.",
        "anti_goals": ["Avoid polishing before the claim is clear."],
        "weeks": [{"week_number": 1, "phase": "foundation",
            "primary_mission": "Make a bounded claim.", "outcome": "One checked claim.",
            "tasks": [
                {"title": "Write a bounded claim", "type": "project", "estimated_hours": 1.5,
                 "success_metric": "Resolve the needs_review claim."},
                {"title": "Review attempted claims", "type": "practice", "estimated_hours": 0.5,
                 "success_metric": "Save a correction."}]}]})
    issues = validate_plan_backbone(plan, duration_weeks=1, weekly_minutes=120)
    assert len(issues) == 1 and "success_metric" in issues[0]


def test_valid_artifact_counts_and_metadata_are_not_rejected():
    assert public_plan_copy_issues({
        "description": "Use the tutorial sequence to compare three claims and save one revision.",
        "success_metric": "A saved revision identifies the claim and evidence link.",
        "status": "needs_review", "phase": "foundation",
    }, location="week") == []


@pytest.mark.parametrize("metric", [
    "Three of four sessions produce a corrected claim.",
    "Four sessions re-sort two fresh items from memory.",
    "Trace a fresh reader-confusion case to its sentence.",
])
def test_routine_criteria_cannot_override_runtime_schedule_or_generate_cases(metric):
    assert public_plan_copy_issues({"type": "practice", "success_metric": metric}, location="week 1")


def test_reader_completion_criterion_requires_explicit_execution_mode():
    assert public_plan_copy_issues({"success_metric": "Reader summary states the claim accurately."}, location="week 12")
    for metric in ["A labeled simulated reader summary matches the claim in-app.",
                   "The agreed real reader identifies the claim accurately.",
                   "The saved answer identifies the claim and supporting evidence."]:
        assert public_plan_copy_issues({"success_metric": metric}, location="week 12") == []


@pytest.mark.parametrize("metric", [
    "Reviews recheck revised passages against the reader-restatement criteria with corrections saved.",
    "Each scheduled review predicts what a reader would take from a sample paragraph and corrects one wrong prediction.",
])
def test_review_of_reader_reasoning_does_not_require_an_external_reader(metric):
    assert public_plan_copy_issues({"type": "practice", "success_metric": metric}, location="week 9") == []


def test_week_copy_failures_keep_localized_repair_address():
    issues = public_plan_copy_issues({"weeks": [{"week_number": 12, "tasks": [
        {"type": "project", "success_metric": "A reader summarizes the claim correctly."}]}]}, location="backbone")
    import re
    assert len(issues) == 1
    assert re.match(r"week (\d+)\b", issues[0]).group(1) == "12"
