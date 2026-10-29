"""F17: an outline-targeted preflight issue never makes every repair impossible.

Live run G2 (attempt 5): the semantic preflight flagged (a) the plan-time
outline ("numbers, sources, checks, verdict ... the five sections": four named,
five counted) and (b) practice.transfer. No package repair may change the
outline, so the whole repair aborted with "Exercise repair lacks an exact
independently validated activity scope", on every regeneration.

Ruling: activity-targeted issues are repaired as before. Outline-targeted
issues become reconciling guidance for the activity repair and the lesson
writer ("the outline wording is inconsistent: ...; teach one consistent version
and do not repeat the inconsistency"), and an outline-only issue no longer
fails the package: the independent lesson review still checks the lesson.
"""

import copy
import json

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.prompt_loader import PROMPTS_DIR
from app.services.planning import package_preflight as preflight
from app.services.planning.lesson_package import PrivatePackageRepair
from app.services.planning.package_preflight import PackageSemanticReview
from tests.test_lesson_pipeline_reliability import Scenario, ScenarioClient, run_scenario
from tests.test_package_split_preflight import Harness, isolate, package, run  # noqa: F401

OUTLINE_ISSUE = (
    "The outline names four memo sections (numbers, sources, checks, verdict) "
    "but asks the learner to label five."
)
TRANSFER_ISSUE = "The instructions say the check section is missing, but the memo contains a check sentence."
RECONCILE = "The outline wording is inconsistent: " + OUTLINE_ISSUE.rstrip(".")


def _semantic(*issues):
    return {"acceptable": not issues, "issues": [
        {"target": target, "description": description} for target, description in issues]}


# ── the preflight decision ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_outline_only_issue_is_guidance_and_the_package_is_approved():
    harness = Harness(semantic=[_semantic(("outline", OUTLINE_ISSUE))])
    (failures, response, _), snapshots = await run(harness)

    assert failures == [] and response.error is None
    assert response.data["acceptable"] is True
    # The numeric evidence stages still ran: approval is not a shortcut.
    assert harness.counts == {"semantic": 1, "a0": 1, "a1": 1}
    saved = snapshots[-1]
    assert saved["semantic"] == {"acceptable": True, "issues": []}
    assert saved["rejection"] is None
    assert saved["outline_guidance"] == [OUTLINE_ISSUE]
    assert preflight.outline_guidance(saved) == [OUTLINE_ISSUE]


@pytest.mark.asyncio
async def test_mixed_issues_repair_the_activity_with_outline_guidance():
    harness = Harness(semantic=[_semantic(("outline", OUTLINE_ISSUE), ("practice.a1", TRANSFER_ISSUE))])
    (failures, response, _), snapshots = await run(harness)

    assert response.error is None and response.data["acceptable"] is False
    # Only the activity is a repair target; the outline is never one.
    assert response.effective_parameters["validated_repair_targets"] == ["practice.a1"]
    assert failures[0] == "practice.a1: " + TRANSFER_ISSUE
    (guidance,) = failures[1:]
    assert RECONCILE in guidance
    assert "teach one consistent version and do not repeat the inconsistency" in guidance
    saved = snapshots[-1]
    assert [issue["target"] for issue in saved["rejection"]["issues"]] == ["practice.a1"]
    assert saved["outline_guidance"] == [OUTLINE_ISSUE]

    # A resumed run returns the same verdict, guidance included, for free.
    repeated = Harness()
    (again, cached, _), _ = await run(repeated, existing=saved)
    assert again == failures and repeated.requests == []
    assert cached.effective_parameters["validated_repair_targets"] == ["practice.a1"]


def test_guidance_state_merges_and_old_states_still_parse():
    harness_state = {"outline_guidance": [OUTLINE_ISSUE]}
    assert preflight.outline_guidance(harness_state) == [OUTLINE_ISSUE]
    assert preflight.outline_guidance({}) == []
    assert preflight.outline_guidance(None) == []


@pytest.mark.asyncio
async def test_saved_guidance_survives_a_merge_with_later_scopes():
    harness = Harness(semantic=[_semantic(("outline", OUTLINE_ISSUE))])
    (_, _, _), snapshots = await run(harness)
    first, last = snapshots[0], snapshots[-1]
    merged = preflight.merge_preflight_states(first, last)
    assert merged["outline_guidance"] == [OUTLINE_ISSUE]
    assert preflight.parse_preflight_state({k: v for k, v in merged.items() if k != "outline_guidance"})


# ── the production lesson path ────────────────────────────────────────────


class _GuidanceCase(Scenario):
    """Scenario whose semantic preflight answers come from a queue."""

    def __init__(self, semantic):
        super().__init__("accepted")
        self.semantic = list(semantic)
        self.writer_prompts = []
        self.repairs = []

    def factory(self, **kwargs):
        case = self

        class Client(ScenarioClient):
            async def generate_json(self, *, output_model, user_prompt, **options):
                if issubclass(output_model, PackageSemanticReview):
                    case.counts["PackageSemanticReview"] += 1
                    data = case.semantic.pop(0) if case.semantic else _semantic()
                    return LLMResponse(data=copy.deepcopy(data), model=self.model, finish_reason="stop")
                if output_model.__name__ == "LessonOutlineDescriptionRepair":
                    raise AssertionError("The outline is never repaired; it becomes guidance")
                if output_model is PrivatePackageRepair:
                    # generate_package appends the review as one JSON document.
                    case.repairs.append(json.loads(user_prompt.rsplit("identify public_defects. ", 1)[1]))
                if output_model.__name__.startswith("LessonSectionGroup_"):
                    case.writer_prompts.append(user_prompt)
                return await super().generate_json(output_model=output_model, user_prompt=user_prompt, **options)

        return Client(case)


@pytest.mark.asyncio
async def test_outline_only_issue_reaches_the_writer_and_the_lesson_publishes():
    case = _GuidanceCase([_semantic(("outline", OUTLINE_ISSUE))])
    payload, calls, error = await run_scenario(case)

    assert error is None and payload["steps"][0]["lesson_content"]
    assert case.counts["PackageSemanticReview"] == 1
    assert not any("outline_repair" in stage for stage, *_ in calls)
    assert case.writer_prompts and all(RECONCILE in prompt for prompt in case.writer_prompts)


@pytest.mark.asyncio
async def test_mixed_issue_repairs_the_activity_then_publishes_with_guidance():
    case = _GuidanceCase([
        _semantic(("outline", OUTLINE_ISSUE), ("practice.guided", TRANSFER_ISSUE)),
        _semantic(("outline", OUTLINE_ISSUE)),  # the re-check: the outline is unchanged
    ])
    payload, calls, error = await run_scenario(case)

    assert error is None and payload["steps"][0]["lesson_content"]
    (repair,) = case.repairs
    assert repair["validated_repair_targets"] == ["practice.guided"]
    assert any(RECONCILE in defect for defect in repair["blocking_defects"])
    assert case.counts["PackageSemanticReview"] == 2
    assert case.writer_prompts and all(RECONCILE in prompt for prompt in case.writer_prompts)


def test_tutorial_outline_prompt_asks_counts_to_match_the_items_named():
    prompt = " ".join((PROMPTS_DIR / "plan_item_tutorial_outline.txt").read_text().split())
    assert "a count in a description equals the items it names" in prompt.casefold()


# ── F18 wiring: an exhausted evidence scope reaches the activity repair ─────


@pytest.mark.asyncio
async def test_exhausted_evidence_scope_runs_the_bounded_activity_repair(monkeypatch):
    from app.services.planning import package_preflight as module

    defect = ("practice.guided: " + module._evidence_defect_description(
        module._evidence_diagnosis(["n3", "n5"], errors=["n3: derived result cannot be classified as a literal fact"])))
    verdicts = [
        ([defect], LLMResponse(data={"acceptable": False, "issues": [defect]}, effective_parameters={
            "synthetic_local_validation": True, "validated_repair_targets": ["practice.guided"]}), None),
        ([], LLMResponse(data={"acceptable": True, "issues": []},
                         effective_parameters={"synthetic_local_validation": True}), None),
    ]

    async def fake_review(*_args, **_kwargs):
        return verdicts.pop(0)

    monkeypatch.setattr(module, "review_package", fake_review)
    case = _GuidanceCase([])
    payload, calls, error = await run_scenario(case)

    assert error is None and payload["steps"][0]["lesson_content"]
    (repair,) = case.repairs
    assert repair["validated_repair_targets"] == ["practice.guided"]
    assert repair["blocking_defects"] == [defect]
    assert verdicts == []  # the repaired package was preflighted again
