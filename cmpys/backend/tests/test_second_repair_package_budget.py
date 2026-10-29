"""A tutorial may spend a second, precisely targeted package repair.

``TUTORIAL_PACKAGE_REPAIRS=2`` lets a tutorial repair its exercise package a
second time only when the recheck (preflight path) or the final review (review
path) names the defects with validated repair targets. Every second repair is
followed by the same full recheck as the first. An untargeted or unavailable
verdict still ends the run, there is never a third repair, and the default (1)
keeps today's single repair and call order exactly.
"""
import pytest
from types import SimpleNamespace

from app.core.config import Settings, settings
from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from tests.test_short_tutorial_pipeline import short_package
from tests.test_tutorial_speculative_writer import DRAFT, RETRY_DRAFT, Harness, RecordingStore, run, stages

PREFIX = "parallel_lesson_step_1_"
REPAIR, REPAIR_2 = PREFIX + "package_repair", PREFIX + "package_repair_2"
THIRD_DRAFT = PREFIX + "draft_3_tutorial_1"
GUIDED = {"failures": ["practice.guided: the answer key contradicts its criteria"], "targets": ["practice.guided"]}
TRANSFER = {"failures": ["practice.transfer: the data omit the stated total"], "targets": ["practice.transfer"]}
UNTARGETED = {"failures": ["The package asks for more than the outline promises"]}
UNAVAILABLE = {"failures": ["Package preflight unavailable"], "targets": ["practice.transfer"], "error": True}


def revised_package(number):
    raw = short_package().model_dump(mode="json")
    raw["workbook"]["activities"][0]["instructions"] = (
        f"Inspect the supplied claim (revision {number}) and identify its stated scope in the answer field.")
    return LessonPackage.model_validate(raw)


class RepairHarness(Harness):
    """Each repair returns a new public package; verdicts are scripted."""

    def __init__(self, *, verdicts, reviews=(), recorded_preflight=False, **kwargs):
        super().__init__(verdicts=verdicts, **kwargs)
        self.reviews = list(reviews)
        self.repairs = 0
        self.repair_contexts = []
        self.recorded_preflight = recorded_preflight

    async def preflight(self, package, step, context, *, client_factory, existing_review=None, on_review=None):
        verdict = self.verdicts[0]
        failures, response, client = await super().preflight(
            package, step, context, client_factory=client_factory,
            existing_review=existing_review, on_review=on_review)
        if verdict.get("error"):
            response.error = "Package preflight unavailable"
        if self.recorded_preflight:
            # A provider-backed verdict is recorded in step_calls by stage name.
            response.effective_parameters = {key: value for key, value in response.effective_parameters.items()
                                             if key != "synthetic_local_validation"}
            client = SimpleNamespace(model="offline")
        return failures, response, client

    async def repair(self, step, context, *, prior_package, defects, **kwargs):
        self.events.append("package_repair")
        self.repairs += 1
        self.repair_contexts.append({"defects": list(defects), "targets": kwargs.get("repair_targets")})
        return revised_package(self.repairs), LLMResponse(data={}), SimpleNamespace(model="offline")

    async def review(self, lesson, **kwargs):
        self.events.append("final_review")
        self.writer_packages.append(kwargs["context"]["lesson_package"])
        verdict = self.reviews.pop(0) if self.reviews else {}
        issues = verdict.get("package_issues", [])
        targets = verdict.get("targets")
        return list(issues), LLMResponse(
            data={"practice_minutes": 3, "package_issues": issues},
            effective_parameters={"validated_repair_targets": targets} if targets else {},
        ), SimpleNamespace(model="offline")


GUIDED_REVIEW = {"package_issues": ["practice.guided: the answer key contradicts its criteria"],
                 "targets": ["practice.guided"]}
TRANSFER_REVIEW = {"package_issues": ["practice.transfer: the data omit the stated total"],
                   "targets": ["practice.transfer"]}
UNTARGETED_REVIEW = {"package_issues": ["The package asks for more than the outline promises"]}


@pytest.fixture(autouse=True)
def sequential(monkeypatch):
    # Speculation is covered separately; these tests pin the repair order.
    monkeypatch.setattr(settings, "tutorial_speculative_writer", False)


def two_repairs(monkeypatch):
    monkeypatch.setattr(settings, "tutorial_package_repairs", 2, raising=False)


def test_setting_defaults_to_one_and_accepts_only_one_or_two(monkeypatch):
    monkeypatch.delenv("TUTORIAL_PACKAGE_REPAIRS", raising=False)
    assert Settings(_env_file=None).tutorial_package_repairs == 1
    monkeypatch.setenv("TUTORIAL_PACKAGE_REPAIRS", "2")
    assert Settings(_env_file=None).tutorial_package_repairs == 2
    for invalid in ("0", "3"):
        monkeypatch.setenv("TUTORIAL_PACKAGE_REPAIRS", invalid)
        with pytest.raises(ValueError):
            Settings(_env_file=None)


# --- Default (1): today's behaviour and call order --------------------------------

@pytest.mark.asyncio
async def test_default_preflight_path_ends_after_its_single_repair(monkeypatch):
    harness = RepairHarness(verdicts=[GUIDED, TRANSFER], recorded_preflight=True)
    _, calls, error = await run(harness, monkeypatch)

    assert error == "step_1: " + TRANSFER["failures"][0]
    assert harness.events == ["preflight_start", "preflight_end", "package_repair",
                              "preflight_start", "preflight_end"]
    assert stages(calls) == [PREFIX + "package_preflight", REPAIR, PREFIX + "package_preflight_recheck"]


@pytest.mark.asyncio
async def test_default_review_path_ends_after_its_single_repair(monkeypatch):
    harness = RepairHarness(verdicts=[{"request": False}], reviews=[GUIDED_REVIEW, TRANSFER_REVIEW])
    _, calls, error = await run(harness, monkeypatch)

    assert error == "step_1: " + "Exercise contract review failed after correction: " + TRANSFER_REVIEW["package_issues"][0]
    assert harness.events == ["preflight_end", "write", "final_review", "package_repair", "write", "final_review"]
    assert stages(calls) == [DRAFT, PREFIX + "review_1", REPAIR, RETRY_DRAFT, PREFIX + "review_2"]


@pytest.mark.asyncio
async def test_default_successful_preflight_repair_keeps_todays_order(monkeypatch):
    harness = RepairHarness(verdicts=[GUIDED, {}], recorded_preflight=True)
    payload, calls, error = await run(harness, monkeypatch)

    assert error is None and payload["steps"][0]["lesson_content"]
    assert stages(calls) == [PREFIX + "package_preflight", REPAIR, PREFIX + "package_preflight_recheck",
                             DRAFT, PREFIX + "review_1"]


# --- Preflight path ---------------------------------------------------------------

@pytest.mark.asyncio
async def test_second_repair_rescues_a_recheck_that_finds_a_new_targeted_defect(monkeypatch):
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[GUIDED, TRANSFER, {}], recorded_preflight=True)
    payload, calls, error = await run(harness, monkeypatch)

    assert error is None and payload["steps"][0]["lesson_content"]
    assert harness.events == ["preflight_start", "preflight_end", "package_repair",
                              "preflight_start", "preflight_end", "package_repair",
                              "preflight_start", "preflight_end", "write", "final_review"]
    assert stages(calls) == [PREFIX + "package_preflight", REPAIR, PREFIX + "package_preflight_recheck",
                             REPAIR_2, PREFIX + "package_preflight_recheck_2", DRAFT, PREFIX + "review_1"]
    # The second repair is scoped to the recheck's own validated targets and
    # the writer and final review see the twice-repaired package.
    assert harness.repair_contexts[1] == {"defects": TRANSFER["failures"], "targets": ["practice.transfer"]}
    assert harness.writer_packages[-1] == revised_package(2).review_context()


@pytest.mark.asyncio
async def test_there_is_never_a_third_repair(monkeypatch):
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[GUIDED, TRANSFER, GUIDED])
    _, calls, error = await run(harness, monkeypatch)

    assert error == "step_1: " + GUIDED["failures"][0]
    assert harness.repairs == 2 and harness.preflights == 3
    assert "write" not in harness.events
    assert stages(calls) == [REPAIR, REPAIR_2]


@pytest.mark.asyncio
@pytest.mark.parametrize("recheck", [UNTARGETED, UNAVAILABLE], ids=["untargeted", "unavailable"])
async def test_untargeted_or_unavailable_recheck_still_ends_the_run(monkeypatch, recheck):
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[GUIDED, recheck])
    _, calls, error = await run(harness, monkeypatch)

    assert error == "step_1: " + recheck["failures"][0]
    assert harness.repairs == 1 and harness.preflights == 2
    assert stages(calls) == [REPAIR]


@pytest.mark.asyncio
async def test_first_repair_rules_are_unchanged_with_two_repairs(monkeypatch):
    # The first repair never required targets and still does not; only an
    # unavailable preflight ends the run before any repair.
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[UNTARGETED, {}])
    payload, _, error = await run(harness, monkeypatch)
    assert error is None and payload["steps"][0]["lesson_content"] and harness.repairs == 1

    harness = RepairHarness(verdicts=[UNAVAILABLE])
    _, calls, error = await run(harness, monkeypatch)
    assert error == "step_1: " + UNAVAILABLE["failures"][0] and harness.repairs == 0 and calls == []


@pytest.mark.asyncio
async def test_rejected_speculative_draft_is_still_discarded_and_rechecks_never_speculate(monkeypatch):
    two_repairs(monkeypatch)
    monkeypatch.setattr(settings, "tutorial_speculative_writer", True)
    harness = RepairHarness(verdicts=[GUIDED, TRANSFER, {}], writer=["hang"], wait_for_writer=True)
    payload, calls, error = await run(harness, monkeypatch, store=RecordingStore(harness))

    assert error is None and payload["steps"][0]["lesson_content"]
    assert harness.writer_cancelled
    # One cancelled speculative request; the rechecks start no writer.
    assert harness.events == ["preflight_start", "write", "preflight_end", "package_repair",
                              "preflight_start", "preflight_end", "package_repair",
                              "preflight_start", "preflight_end", "write", "save_sections", "final_review"]
    assert stages(calls) == [PREFIX + "speculative_draft_1_tutorial_1", REPAIR, REPAIR_2, DRAFT, PREFIX + "review_1"]


# --- Review path ------------------------------------------------------------------

@pytest.mark.asyncio
async def test_review_path_second_repair_rewrites_and_reviews_again(monkeypatch):
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[{"request": False}], reviews=[GUIDED_REVIEW, TRANSFER_REVIEW, {}])
    payload, calls, error = await run(harness, monkeypatch)

    assert error is None and payload["steps"][0]["lesson_content"]
    assert harness.events == ["preflight_end", "write", "final_review", "package_repair", "write", "final_review",
                              "package_repair", "write", "final_review"]
    assert stages(calls) == [DRAFT, PREFIX + "review_1", REPAIR, RETRY_DRAFT, PREFIX + "review_2",
                             REPAIR_2, THIRD_DRAFT, PREFIX + "review_3"]
    assert harness.repair_contexts[1]["targets"] == ["practice.transfer"]
    assert harness.writer_packages[-1] == revised_package(2).review_context()


@pytest.mark.asyncio
async def test_review_path_second_repair_needs_validated_targets(monkeypatch):
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[{"request": False}], reviews=[GUIDED_REVIEW, UNTARGETED_REVIEW])
    _, calls, error = await run(harness, monkeypatch)

    assert error == "step_1: " + "Exercise contract review failed after correction: " + UNTARGETED_REVIEW["package_issues"][0]
    assert harness.repairs == 1
    assert stages(calls) == [DRAFT, PREFIX + "review_1", REPAIR, RETRY_DRAFT, PREFIX + "review_2"]


@pytest.mark.asyncio
async def test_review_path_never_repairs_a_third_time(monkeypatch):
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[{"request": False}],
                            reviews=[GUIDED_REVIEW, TRANSFER_REVIEW, GUIDED_REVIEW])
    _, calls, error = await run(harness, monkeypatch)

    assert error == "step_1: " + "Exercise contract review failed after correction: " + GUIDED_REVIEW["package_issues"][0]
    assert harness.repairs == 2
    assert stages(calls)[-2:] == [THIRD_DRAFT, PREFIX + "review_3"]


@pytest.mark.asyncio
async def test_preflight_and_review_paths_share_one_repair_count(monkeypatch):
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[GUIDED, {}], reviews=[TRANSFER_REVIEW, {}])
    payload, calls, error = await run(harness, monkeypatch)
    assert error is None and payload["steps"][0]["lesson_content"]
    assert stages(calls) == [REPAIR, DRAFT, PREFIX + "review_1", REPAIR_2, RETRY_DRAFT, PREFIX + "review_2"]

    harness = RepairHarness(verdicts=[GUIDED, {}], reviews=[TRANSFER_REVIEW, GUIDED_REVIEW])
    _, calls, error = await run(harness, monkeypatch)
    assert error == "step_1: " + "Exercise contract review failed after correction: " + GUIDED_REVIEW["package_issues"][0]
    assert harness.repairs == 2


# --- Resume -----------------------------------------------------------------------

@pytest.mark.asyncio
async def test_resume_does_not_grant_a_fresh_second_repair(monkeypatch):
    # The repair count is not checkpointed. A resumed package may already have
    # spent repairs, so a restart gets at most today's single repair.
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[GUIDED, TRANSFER, GUIDED])
    store = RecordingStore(harness)
    _, calls, error = await run(harness, monkeypatch, store=store)
    assert error and stages(calls) == [REPAIR, REPAIR_2]

    harness.verdicts = [TRANSFER, GUIDED]
    harness.events.clear()
    _, calls, error = await run(harness, monkeypatch, store=store)
    assert error == "step_1: " + GUIDED["failures"][0]
    assert harness.events == ["preflight_start", "preflight_end", "package_repair",
                              "preflight_start", "preflight_end"]
    assert stages(calls) == [REPAIR]


@pytest.mark.asyncio
async def test_resume_of_an_approved_package_gets_only_one_review_repair(monkeypatch):
    two_repairs(monkeypatch)
    harness = RepairHarness(verdicts=[{}])
    store = RecordingStore(harness)

    async def unavailable_review(lesson, **kwargs):
        harness.events.append("final_review")
        return ["Content review unavailable"], LLMResponse(data={}, error="review unavailable"), None

    original_review = harness.review
    harness.review = unavailable_review
    _, _, error = await run(harness, monkeypatch, store=store)
    assert error

    harness.review = original_review
    harness.reviews = [GUIDED_REVIEW, TRANSFER_REVIEW]
    harness.events.clear()
    _, calls, error = await run(harness, monkeypatch, store=store)
    assert error == "step_1: " + "Exercise contract review failed after correction: " + TRANSFER_REVIEW["package_issues"][0]
    assert harness.repairs == 1 and REPAIR_2 not in stages(calls)
