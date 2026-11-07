"""Regression guards for the November tutorial prompt audit; no provider calls."""
import json
import pytest

from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning import package_builder as builder
from app.services.planning.tutorial_blocks import fence_errors
from tests.test_staged_package_builder import components


@pytest.mark.parametrize("title,term", [
    ("Accrual profit", "Accrual profit"),
    (" ACCRUAL   PROFIT ", "Accrual profit"),
    ("Հաշվապահական շահույթ", "Հաշվապահական շահույթ"),
])
def test_circular_formula_is_rejected_before_semantic_review(title, term):
    errors = fence_errors("formula", f"title: {title}\n= {term}\n+ Revenue\n− Costs")
    assert any("circular formula" in error and "first input" in error for error in errors)


@pytest.mark.parametrize("body", [
    "title: Profit\n= Revenue\n− Costs",
    "title: Gross profit margin\n= Gross profit\n÷ Revenue",
])
def test_valid_formula_preserves_distinct_quantities(body):
    assert not fence_errors("formula", body)


def test_multiple_equations_in_one_formula_are_rejected():
    assert fence_errors("formula", "title: Profit\n= Revenue\n− Costs\n= Margin")


def seed_with_assumptions(assumptions):
    raw, _ = components()
    raw["teaching_cases"] = [{"id": "case", "assumptions": assumptions, "data": [], "results": []}]
    return builder.LessonPackageSeed.model_validate(raw)


@pytest.mark.parametrize("assumptions", [
    "Original fictional case: 8000 minus 7500 leaves 500.",
    "Original fictional study: measure repeat booking within 30 days.",
    "Original fictional case: a balance of −８３０ credits.",
    "Original fictional analysis: (1) Record 30 days. (2) Compare the outcome.",
    "Original fictional costs: (1) dollars of revenue. (2) dollars of expense.",
])
def test_undeclared_seed_numbers_use_early_correction(assumptions):
    seed = seed_with_assumptions(assumptions)
    with pytest.raises(builder.TutorialTeachingCaseError, match="numeric facts but data is empty"):
        builder.validate_tutorial_seed(seed, "tutorial_v1")
    assert builder.validate_tutorial_seed(seed, None) == seed


@pytest.mark.parametrize("assumptions", [
    "Original fictional notice: invite volunteers and state how to reply.",
    "Original fictional analysis: (1) Identify the event. (2) Check whether cash arrived.",
    "Original fictional case INV-42. Step 1: distinguish evidence from conclusions.",
    "Original fictional lesson cites IAS 1 without inventing a quantitative case.",
])
def test_qualitative_seed_and_incidental_identifiers_remain_valid(assumptions):
    seed = seed_with_assumptions(assumptions)
    assert builder.validate_tutorial_seed(seed, "tutorial_v1") == seed


def test_both_seed_examples_are_complete_valid_seeds():
    prompt = resolve_prompt_text("tutorial_package_seed.txt")
    examples = [json.loads(line) for line in prompt.splitlines() if line.startswith('{"workbook_title"')]
    assert len(examples) == 2
    seeds = [builder.validate_tutorial_seed(builder.LessonPackageSeed.model_validate(raw), "tutorial_v1") for raw in examples]
    assert {bool(seed.teaching_cases[0].data) for seed in seeds} == {True, False}
    numeric = next(seed for seed in seeds if seed.teaching_cases[0].data)
    assert numeric.teaching_cases[0].computed()["results"][0]["display_value"] == "50"


def test_transfer_principle_is_shared_verbatim():
    from app.services.planning import lesson_review, lesson_writer, package_preflight
    from app.services.planning.tutorial_rules import TUTORIAL_TRANSFER_RULE
    assert TUTORIAL_TRANSFER_RULE in resolve_prompt_text("tutorial_package_seed.txt")
    assert TUTORIAL_TRANSFER_RULE in resolve_prompt_text("tutorial_activity_generate.txt")
    assert TUTORIAL_TRANSFER_RULE in lesson_writer._tutorial_contract()
    assert TUTORIAL_TRANSFER_RULE in package_preflight._SEMANTIC_PROMPT
    assert lesson_review.TUTORIAL_TRANSFER_RULE == TUTORIAL_TRANSFER_RULE
    from app.services.planning.tutorial_rules import tutorial_review_rules
    review_prompt = package_preflight._SEMANTIC_PROMPT + tutorial_review_rules()
    assert review_prompt.count(TUTORIAL_TRANSFER_RULE) == 1
    assert "For novices, near transfer" in TUTORIAL_TRANSFER_RULE
    assert "quote the public sentence" in TUTORIAL_TRANSFER_RULE


def lesson_verdict(**overrides):
    return {"acceptable": True, "issues": [], "practice_minutes": 3,
            "contains_calculations": False, "calculations": [], **overrides}


@pytest.mark.parametrize("defect", [
    "A calculated answer is numerically wrong.",
    "The conclusion contradicts the supplied facts.",
    "The public worked example leaks the transfer answer.",
    "The lesson is English when Armenian was requested.",
    "The exercise needs missing facts and cannot be passed.",
    "The lesson invents a quotation and source.",
])
def test_old_review_findings_default_to_blocking(defect):
    from app.services.planning.lesson_review import LessonReview
    from app.services.planning.package_preflight import PackageSemanticReview
    review = LessonReview.model_validate(lesson_verdict(issues=[defect]))
    assert defect in review.failures()
    package = PackageSemanticReview.model_validate({"acceptable": False,
        "issues": [{"target": "package", "description": defect}]})
    assert package.blocking_issues[0].severity == "blocking"


def test_advisory_severities_keep_only_blocking_repair_targets():
    from app.services.planning.lesson_review import LessonReview
    review = LessonReview.model_validate(lesson_verdict(acceptable=False,
        issues=["Optional stylistic improvement"], issue_severities=["advisory"],
        package_issues=["Optional wording change", "The answer is mathematically incorrect"],
        package_issue_severities=["advisory", "blocking"],
        package_issue_targets=["practice.guided", "practice.transfer.answer"]))
    assert review.failures() == ["The answer is mathematically incorrect"]
    assert review.package_issue_targets == ["practice.transfer.answer"]
    assert review.advisories == ["Optional stylistic improvement", "Optional wording change"]
    assert LessonReview.model_validate(review.model_dump()).model_dump() == review.model_dump()


def test_advisories_cannot_hide_unchecked_calculations_or_server_defects():
    from app.services.planning.lesson_review import LessonReview
    review = LessonReview.model_validate(lesson_verdict(acceptable=False,
        issues=["Optional stylistic improvement"], issue_severities=["advisory"],
        contains_calculations=True))
    assert review.acceptable and "Numeric examples were not checked" in review.failures()
    review.issues.append("Independent numeric check found a wrong answer")
    reparsed = LessonReview.model_validate(review.model_dump())
    assert "Independent numeric check found a wrong answer" in reparsed.failures()


@pytest.mark.parametrize("overrides", [
    {"issues": ["Missing severity"], "issue_severities": ["advisory", "blocking"]},
    {"package_issues": ["Missing severity"], "package_issue_severities": ["advisory", "blocking"]},
    {"issues": ["Invalid severity"], "issue_severities": ["optional"]},
    {"package_issues": ["An advisory", "A blocker"],
     "package_issue_severities": ["advisory", "blocking"], "package_issue_targets": ["package"]},
])
def test_invalid_severity_metadata_fails_closed(overrides):
    from pydantic import ValidationError
    from app.services.planning.lesson_review import LessonReview
    with pytest.raises(ValidationError):
        LessonReview.model_validate(lesson_verdict(**overrides))


def test_unexplained_rejection_is_not_approved_by_an_advisory_channel():
    from app.services.planning.lesson_review import LessonReview
    review = LessonReview.model_validate(lesson_verdict(acceptable=False, advisories=["Optional wording"]))
    assert "Reviewer did not approve this lesson" in review.failures()


@pytest.mark.asyncio
@pytest.mark.parametrize("acceptable", [True, False])
async def test_advisory_only_preflight_retains_audits_and_survives_resume(monkeypatch, acceptable):
    from tests.test_teaching_case_audit import package, verdict, run_review
    from app.services.planning.package_preflight import validate_preflight_state
    import copy
    value = package(True, isolate_teaching=True)
    data = verdict(True)
    data.update(acceptable=acceptable, issues=[{"target": "package", "severity": "advisory",
        "description": "Optional wording improvement; the stated skill is fully assessed."}])
    (failures, response, _), client, snapshots = await run_review(monkeypatch, value, data)
    assert not failures and response.semantic_accepted
    assert client.generate_json.await_count == 1
    saved = snapshots[-1]
    assert saved["semantic"]["issues"][0]["severity"] == "advisory"
    validate_preflight_state(saved, package=value, outline={"lesson_format": "tutorial_v1"}, context={})
    incomplete = copy.deepcopy(saved)
    incomplete["semantic"]["teaching_case_audits"] = []
    with pytest.raises(ValueError, match="Teaching-case audit"):
        validate_preflight_state(incomplete, package=value, outline={"lesson_format": "tutorial_v1"}, context={})


@pytest.mark.asyncio
@pytest.mark.parametrize("audit_fault", ["missing", "contradiction"])
async def test_advisory_summary_cannot_bypass_teaching_audit(monkeypatch, audit_fault):
    from tests.test_teaching_case_audit import package, verdict, run_review, teaching_audit
    data = verdict(True)
    data["issues"] = [{"target": "package", "severity": "advisory",
        "description": "Optional stylistic suggestion without impact on learning."}]
    data["teaching_case_audits"] = [] if audit_fault == "missing" else [teaching_audit(False)]
    (failures, response, _), _, _ = await run_review(monkeypatch, package(True, isolate_teaching=True), data)
    assert failures and not response.semantic_accepted


@pytest.mark.parametrize("reason", ["semantic", "binding", "under_length"])
def test_repairs_obey_reason_and_fence_caps(reason):
    from app.tasks.plans import _plan_detail_sections_repair_prompt
    prompt = _plan_detail_sections_repair_prompt(task_title="A tutorial", step={}, materials=[],
        sections={"worked_example": "A sound explanation."}, field_names=["worked_example"],
        lesson_format="tutorial_v1", repair_reason=reason)
    assert "Q <= 480" in prompt and "Why <= 280" in prompt and "each choice <= 120" in prompt
    if reason == "under_length":
        assert '"target_words"' in prompt and "Reach its target_words" in prompt
    else:
        assert "target_words" not in prompt
        assert "Fix only the named defect" in prompt and "do not expand unrelated text" in prompt


def test_unknown_repair_reason_is_not_silently_treated_as_expansion():
    from app.tasks.plans import _plan_detail_sections_repair_prompt
    with pytest.raises(ValueError, match="Unknown section repair reason"):
        _plan_detail_sections_repair_prompt(task_title="Test", step={}, materials=[], sections={},
            field_names=[], repair_reason="typo")


@pytest.mark.parametrize("field,pattern", [("question", r"Q <= (\d+)"),
                                         ("why", r"Why <= (\d+)"),
                                         ("option", r"each choice <= (\d+)")])
def test_repair_prompt_limits_agree_with_actual_parser_boundaries(field, pattern):
    import re
    from app.tasks.plans import _plan_detail_sections_repair_prompt
    prompt = _plan_detail_sections_repair_prompt(task_title="Test", step={}, materials=[],
        sections={"worked_example": "A sound explanation."}, field_names=["worked_example"],
        lesson_format="tutorial_v1", repair_reason="semantic")
    limit = int(re.search(pattern, prompt)[1])
    values = {"question": "Which follows?", "why": "This uses the stated rule.", "option": "Valid answer"}
    def body(length):
        selected = {**values, field: "a" * length}
        return (f"Q: {selected['question']}\n- [x] {selected['option']}\n- [ ] Other\n"
                f"Why: {selected['why']}")
    assert not fence_errors("check", body(limit))
    assert fence_errors("check", body(limit + 1))
