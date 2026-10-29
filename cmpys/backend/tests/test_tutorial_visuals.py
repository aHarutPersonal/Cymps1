"""tutorial_v1 reader blocks: one line grammar per fence, checked after rendering.

The Flutter reader (Task D5) mirrors this grammar. Examples come from the v3
design's LESSON data (owner earnings, Harbor Bakeries, the $50m quick check).
"""
import copy

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.schemas import (
    PlanTutorialLessonSectionsOutput, plan_detail_step_model, plan_detail_step_quality_issues,
)
from app.services.planning.lesson_package import LessonPackage, render_package_results
from app.services.planning.tutorial_visuals import (
    ChartBlock, CheckBlock, FormulaBlock, StepsBlock, parse_chart, parse_check, parse_formula,
    parse_steps, tutorial_visual_issues,
)
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import structured_package_fixture

FORMULA = """```formula
title: Owner earnings
= Net income
+ Depreciation & amortisation
− Maintenance capex
± Change in working capital
```"""

WATERFALL = """```chart
type: waterfall
title: Reported $80m → owner earnings
unit: $m
Net | 80
+D&A | 22
−Maint. | −30
−WC | −4
= Owner | 68
```"""

STEPS = """```steps
title: Harbor Bakeries (fictional case)
unit: $m
Net income | 80 | From the income statement.
+ Depreciation & amortisation | 22 | Non-cash: the ovens were paid for years ago.
− Maintenance capex | −30 | Total capex was 48. Management says 18 opened new stores, so 30 kept the old ones running.
− Working capital increase | −4 | More flour and inventory on hand ties up cash.
= Owner earnings | 68
```"""

CHECK = """```check
Q: A company reports $50m profit and $10m depreciation. It spends $25m on capex, $15m of it on new factories. Ignoring working capital, what are owner earnings?
- [ ] $35m
- [ ] $40m
- [x] $50m
- [ ] $60m
Why: Maintenance capex is 25 − 15 = 10. So 50 + 10 − 10 = 50. Subtracting all 25 would give 35, the most common mistake.
```"""

COMPARISON = """```comparison
Reported profit
- Counts depreciation as a cost
- Ignores reinvestment needs
vs
Owner earnings
- Adds back non-cash charges
- Subtracts maintenance capex
```"""


def body(fence: str) -> str:
    return fence.split("\n", 1)[1].rsplit("\n", 1)[0]


def harbor_package() -> LessonPackage:
    raw = structured_package_fixture(package_payload())
    for activity in raw["workbook"]["activities"]:
        activity.update(minutes_min=1, minutes_max=2)
    raw["teaching_cases"] = [{
        "id": "harbor",
        "assumptions": "Harbor Bakeries is a fictional bakery chain; all figures are one year in USD millions.",
        "data": [{"id": "net_income", "label": "Net income", "value": 80, "unit": "$m"},
                 {"id": "da", "label": "Depreciation and amortisation", "value": 22, "unit": "$m"},
                 {"id": "total_capex", "label": "Total capex", "value": 48, "unit": "$m"},
                 {"id": "growth_capex", "label": "Capex for new stores", "value": 18, "unit": "$m"},
                 {"id": "wc_increase", "label": "Working capital increase", "value": 4, "unit": "$m"}],
        "results": [{"id": "maintenance_capex", "label": "Maintenance capex",
                     "expression": "total_capex - growth_capex", "unit": "$m", "decimal_places": 0},
                    {"id": "owner_earnings", "label": "Owner earnings",
                     "expression": "net_income + da - (total_capex - growth_capex) - wc_increase",
                     "unit": "$m", "decimal_places": 0}]}]
    return LessonPackage.model_validate(raw)


def harbor_sections() -> dict:
    """A new-format tutorial: no guided_practice, result tokens inside fences."""
    steps = (STEPS.replace("| −30 |", "| −[[result:harbor.maintenance_capex]] |")
             .replace("so 30 kept", "so the rest kept")
             .replace("= Owner earnings | 68", "= Owner earnings | [[result:harbor.owner_earnings]]"))
    chart = (WATERFALL.replace("| −30", "| −[[result:harbor.maintenance_capex]]")
             .replace("= Owner | 68", "= Owner | [[result:harbor.owner_earnings]]"))
    return {
        "why_this_matters": "A company can report a profit and still need every dollar of it to stand still. " * 2,
        "core_framework": "Start with reported net income and adjust it. " * 18 + "\n\n" + FORMULA,
        "worked_example": "Walk the fictional Harbor Bakeries case one line at a time. " * 12
                          + "\n\n" + steps + "\n\n" + chart,
        "failure_modes": "Subtracting total capex treats growth spending as a cost of standing still. " * 3,
        "check_your_understanding": "Try one quick check before you practise.\n\n" + CHECK,
        "references": "The Berkshire Hathaway 1986 letter appendix defines the term owner earnings.",
    }


def assemble(sections: dict, package: LessonPackage, title: str = "Estimate owner earnings") -> LLMResponse:
    from app.tasks.plans import _assemble_parallel_lesson_response
    from tests.test_short_tutorial_pipeline import outline
    step = {**outline(1)["steps"][0], "title": title}
    response = LLMResponse(data=render_package_results(sections, package))
    _assemble_parallel_lesson_response(response, step=step, material_titles={"Resource 1"}, target_minutes=6)
    return response


def test_formula_fence_valid_and_invalid():
    block = parse_formula(body(FORMULA))
    assert isinstance(block, FormulaBlock)
    assert block.title == "Owner earnings"
    assert [(term.sign, term.label) for term in block.terms] == [
        ("=", "Net income"), ("+", "Depreciation & amortisation"),
        ("−", "Maintenance capex"), ("±", "Change in working capital")]
    # ASCII hyphen is accepted and normalized to the Unicode minus.
    assert parse_formula(body(FORMULA).replace("− Maintenance", "- Maintenance")).terms[2].sign == "−"
    assert parse_formula("title: Unit cost\n= Total cost\n÷ Units made\n× 100").terms[1].sign == "÷"
    invalid = [
        "= Net income\n+ Depreciation",                                   # no title line
        "title: Owner earnings\n+ Net income\n+ Depreciation",            # first sign is not =
        "title: Owner earnings\n= Net income",                            # one term
        "title: Owner earnings\n" + "\n".join(f"+ Term {i}" for i in range(7)).replace("+", "=", 1),
        "title: " + "T" * 61 + "\n= A\n+ B",                              # long title
        "title: Owner earnings\n= Net income\n+ " + "L" * 61,              # long label
        "title: Owner earnings\n= Net income\n* Depreciation",            # unknown sign
        "title: Owner earnings\n= Net income\n+Depreciation",             # sign needs a space
        "title: Owner earnings\n= Net income\nDepreciation",              # no sign
        "title: Owner earnings\n= Net income\n+ Depreciation {non-cash}",  # braces
        "title: Owner earnings\n= Net income\n+ Depreciation; amortisation",
        "title: Owner earnings\n= Net income\n+ <b>Depreciation</b>",
        "= Net income\ntitle: Owner earnings\n+ Depreciation",            # title must come first
    ]
    for value in invalid:
        assert parse_formula(value) is None, value


def test_waterfall_total_must_match_running_sum():
    chart = parse_chart(body(WATERFALL))
    assert isinstance(chart, ChartBlock)
    assert (chart.type, chart.title, chart.unit) == ("waterfall", "Reported $80m → owner earnings", "$m")
    assert [(row.label, str(row.value), row.total) for row in chart.rows] == [
        ("Net", "80", False), ("+D&A", "22", False), ("−Maint.", "-30", False),
        ("−WC", "-4", False), ("Owner", "68", True)]
    assert parse_chart(body(WATERFALL).replace("= Owner | 68", "= Owner | 70")) is None
    assert parse_chart(body(WATERFALL).replace("−WC | −4", "−WC | -4")) is not None
    # Within 0.5% of the stated total is accepted; beyond it is not.
    big = "type: waterfall\ntitle: Large\nBase | 1000\nChange | 0\n= End | {}"
    assert parse_chart(big.format(1004)) is not None
    assert parse_chart(big.format(1006)) is None
    assert parse_chart(body(WATERFALL).replace("= Owner | 68", "Owner | 68")) is None  # no total row
    assert parse_chart(body(WATERFALL).replace("+D&A | 22", "= D&A | 22")) is None     # total not last
    bars = "type: bars\ntitle: Capex split\nunit: $m\nMaintenance | 30\nGrowth | 18"
    assert parse_chart(bars).rows[1].total is False
    assert parse_chart(bars + "\n= Total | 48") is None   # bars carry no total row
    for value in [
        "type: waterfall\ntitle: One\n= End | 5",                        # one row
        "type: bars\ntitle: Many\n" + "\n".join(f"R{i} | {i}" for i in range(9)),
        "type: pie\ntitle: Shares\nA | 1\nB | 2",
        "title: No type\nA | 1\nB | 2",
        "type: bars\nA | 1\nB | 2",
        "type: bars\ntitle: " + "T" * 81 + "\nA | 1\nB | 2",
        "type: bars\ntitle: Units\nunit: " + "u" * 13 + "\nA | 1\nB | 2",
        "type: bars\ntitle: Labels\n" + "L" * 25 + " | 1\nB | 2",
        "type: bars\ntitle: Comma decimal\nA | 4,5\nB | 2",
        "type: bars\ntitle: Units in value\nA | $30m\nB | 2",
        "type: bars\ntitle: Missing\nA |\nB | 2",
        "type: bars\ntitle: Cells\nA | 1 | extra\nB | 2",
        "type: bars\ntitle: Token\nA | [[result:harbor.owner_earnings]]\nB | 2",
    ]:
        assert parse_chart(value) is None, value


def test_steps_total_must_match():
    steps = parse_steps(body(STEPS))
    assert isinstance(steps, StepsBlock)
    assert (steps.title, steps.unit) == ("Harbor Bakeries (fictional case)", "$m")
    assert [str(row.value) for row in steps.rows] == ["80", "22", "-30", "-4"]
    assert steps.rows[2].note.startswith("Total capex was 48.")
    assert (steps.total.label, str(steps.total.value)) == ("Owner earnings", "68")
    assert parse_steps(body(STEPS).replace("= Owner earnings | 68", "= Owner earnings | 70")) is None
    # A steps total allows display rounding only (half a unit of the coarsest
    # decimal shown), never the waterfall's 0.5%: the running total must agree.
    big = "title: Large\nBase | 1000 | Note.\nChange | -5 | Note.\n= End | {}"
    assert parse_steps(big.format("995")) is not None
    assert parse_steps(big.format("1000")) is None
    assert parse_steps(big.format("995.4")) is not None   # within half a unit of the integer rows
    assert parse_steps(big.format("995.6")) is None
    rounded = "title: Rounded\nA | 12.5 | Note.\nB | 3.33 | Note.\n= Total | {}"
    assert parse_steps(rounded.format("15.83")) is not None
    assert parse_steps(rounded.format("15.88")) is not None  # the coarsest value shows one decimal
    assert parse_steps(rounded.format("15.9")) is None
    assert parse_steps(body(STEPS).replace("| −30 |", "| -30 |")).total is not None
    no_total = parse_steps(body(STEPS).replace("\n= Owner earnings | 68", ""))
    assert no_total is not None and no_total.total is None
    # Qualitative steps carry reasoning without values; then no total applies.
    qualitative = ("title: Sharpen a call to action\nName the action | | Readers must know what to do.\n"
                   "Add a time | | A deadline turns interest into a plan.\nGive a response path | | Say how to reply.")
    assert [row.value for row in parse_steps(qualitative).rows] == [None, None, None]
    assert parse_steps(qualitative + "\n= Total | 0") is None
    for value in [
        "title: One row\nNet income | 80 | From the income statement.",
        "title: Seven rows\n" + "\n".join(f"Row {i} | {i} | Note {i}." for i in range(7)),
        "Net income | 80 | Note.\nD&A | 22 | Note.",                                  # no title
        "title: Notes\nNet income | 80 | " + "n" * 161 + "\nD&A | 22 | Note.",
        "title: Notes\nNet income | 80 |\nD&A | 22 | Note.",                         # empty note
        "title: Cells\nNet income | 80\nD&A | 22 | Note.",
        "title: Labels\n" + "L" * 61 + " | 80 | Note.\nD&A | 22 | Note.",
        "title: Total first\n= Total | 102\nNet income | 80 | Note.\nD&A | 22 | Note.",
        "title: Total note\nNet income | 80 | Note.\nD&A | 22 | Note.\n= Total | 102 | Note.",
        "title: Bad number\nNet income | eighty | Note.\nD&A | 22 | Note.",
    ]:
        assert parse_steps(value) is None, value


def test_check_fence_single_multi_numeric():
    single = parse_check(body(CHECK))
    assert isinstance(single, CheckBlock)
    assert single.question.startswith("A company reports $50m profit")
    assert [(option.text, option.correct) for option in single.options] == [
        ("$35m", False), ("$40m", False), ("$50m", True), ("$60m", False)]
    assert single.answer is None and not single.select_all
    assert single.why.startswith("Maintenance capex is 25 − 15 = 10.")
    multi = parse_check("Q: Which charges cost no cash this year?\n- [x] Depreciation\n- [X] Amortisation\n"
                        "- [ ] Wages\nWhy: Both spread an earlier purchase over time.")
    assert multi.select_all and [option.correct for option in multi.options] == [True, True, False]
    numeric = parse_check("Q: What are Harbor's owner earnings?\nanswer: 68 | unit: $m | tolerance: 0.5\n"
                          "Why: 80 + 22 − 30 − 4 = 68.")
    assert numeric.options == () and not numeric.select_all
    assert (str(numeric.answer.value), numeric.answer.unit, str(numeric.answer.tolerance)) == ("68", "$m", "0.5")
    assert parse_check("Q: Ratio?\nanswer: −1.5 | unit: | tolerance: 0\nWhy: Unitless.").answer.unit == ""
    question, why = body(CHECK).split("\n")[0], body(CHECK).split("\n")[-1]
    for value in [
        question + "\n- [ ] $35m\n- [ ] $40m\n" + why,                               # nothing correct
        question + "\n- [x] $50m\n" + why,                                           # one option
        question + "\n" + "\n".join(f"- [ ] ${n}m" for n in range(5)).replace("[ ]", "[x]", 1) + "\n" + why,
        question + "\n- [ ] $35m\n- [x] $50m",                                       # no Why
        why + "\n- [ ] $35m\n- [x] $50m\n" + question,                               # wrong order
        question + "\n- [ ] $35m\n- [x] $50m\nanswer: 50 | unit: $m | tolerance: 0\n" + why,
        "Q: " + "q" * 241 + "\n- [ ] A\n- [x] B\n" + why,
        question + "\n- [ ] A\n- [x] B\nWhy: " + "w" * 281,
        question + "\n* [ ] A\n- [x] B\n" + why,
        question + "\nanswer: 50 | unit: $m | tolerance: -1\n" + why,
        question + "\nanswer: 50 | tolerance: 0.5\n" + why,
        question + "\nanswer: fifty | unit: $m | tolerance: 0.5\n" + why,
        question + "\nanswer: 50 | unit: " + "u" * 13 + " | tolerance: 0.5\n" + why,
    ]:
        assert parse_check(value) is None, value


def test_fence_values_rendered_from_result_tokens():
    package = harbor_package()
    sections = harbor_sections()
    sections["check_your_understanding"] = (
        "Use the case once more.\n\n```check\nQ: What are Harbor's owner earnings in $m?\n"
        "answer: [[result:harbor.owner_earnings]] | unit: $m | tolerance: 0.5\n"
        "Why: Add back D&A, then subtract maintenance capex and the working capital increase.\n```")
    before = copy.deepcopy(sections)
    rendered = render_package_results(sections, package)
    assert sections == before
    assert "| −30 |" in rendered["worked_example"] and "= Owner earnings | 68" in rendered["worked_example"]
    assert "−Maint. | −30" in rendered["worked_example"] and "= Owner | 68" in rendered["worked_example"]
    assert "answer: 68 | unit: $m" in rendered["check_your_understanding"]
    assert "[[" not in "".join(rendered.values())
    response = assemble(sections, package)
    assert response.error is None
    assert tutorial_visual_issues(response.data["lesson_content"]) == []
    # Arithmetic is checked only after rendering: raw tokens are not numbers.
    unrendered = response.data["lesson_content"].replace("| −30 |", "| −[[result:harbor.maintenance_capex]] |")
    assert any("worked_example" in issue and "steps" in issue for issue in tutorial_visual_issues(unrendered))
    # A wrong binding renders to a value whose total no longer adds up.
    wrong = copy.deepcopy(sections)
    wrong["worked_example"] = wrong["worked_example"].replace(
        "−[[result:harbor.maintenance_capex]] | Total", "−[[result:harbor.owner_earnings]] | Total")
    response = assemble(wrong, package)
    assert response.error and "steps" in response.error


def test_new_tutorial_without_guided_practice_passes():
    package = harbor_package()
    sections = harbor_sections()
    parsed = PlanTutorialLessonSectionsOutput.model_validate(sections)
    assert parsed.guided_practice is None
    schema = PlanTutorialLessonSectionsOutput.model_json_schema()
    assert "guided_practice" not in schema["properties"] and "guided_practice" not in schema["required"]
    # Practice bindings live in the workbook only: rendering does not demand them.
    response = assemble(sections, package)
    assert response.error is None, response.error
    step = response.data
    assert "## Guided Practice" not in step["lesson_content"]
    assert 380 <= len(step["lesson_content"].split()) <= 740
    assert plan_detail_step_quality_issues(plan_detail_step_model(step).model_validate(step)) == []
    # One issue per missing or invalid required fence.
    bare = step["lesson_content"]
    for fence in (FORMULA, CHECK):
        bare = bare.replace(fence, "")
    worked = render_package_results({"x": harbor_sections()["worked_example"]}, package, require_all=False)["x"]
    assert worked in bare
    bare = bare.replace(worked, "Walk the case.")
    issues = tutorial_visual_issues(bare)
    assert len(issues) == 3
    assert [issue.split()[0] for issue in issues] == [
        "core_framework", "worked_example", "check_your_understanding"]
    twice = step["lesson_content"].replace(FORMULA, FORMULA + "\n\n" + COMPARISON)
    assert any("exactly one valid primary visual" in issue for issue in tutorial_visual_issues(twice))
    misplaced = step["lesson_content"].replace(
        "## References\n", "## References\n" + CHECK + "\n\n")
    assert any(issue.startswith("references") for issue in tutorial_visual_issues(misplaced))
    # Too long for a new-format tutorial (380-740 words).
    long = {**step, "lesson_content": step["lesson_content"] + " extra" * 300}
    assert any("380-740" in issue for issue in
               plan_detail_step_quality_issues(plan_detail_step_model(long).model_validate(long)))


def test_legacy_tutorial_with_guided_practice_still_valid():
    """Review Focus 3: stored lessons keep the old section and fence rules."""
    from tests.test_short_tutorial_pipeline import short_package
    from tests.test_tutorial_reading_budget import legacy_sections
    from app.services.planning.tutorial_capacity import _render, _sections
    package = short_package()
    sections = legacy_sections()
    assert "[[practice:guided.argument]]" in sections["guided_practice"]
    assert PlanTutorialLessonSectionsOutput.model_validate(sections).guided_practice
    # Legacy lessons still render and require their practice bindings.
    with pytest.raises(ValueError, match="Every teaching result and practice field"):
        render_package_results({**sections, "guided_practice": "No bindings here."}, package)
    response = assemble(sections, package, title="Read the motive")
    assert response.error is None, response.error
    step = response.data
    assert "## Guided Practice" in step["lesson_content"]
    assert "Guided argument — Claim, reason, objection and revision" in step["lesson_content"]
    assert tutorial_visual_issues(step["lesson_content"]) == []
    assert plan_detail_step_quality_issues(plan_detail_step_model(step).model_validate(step)) == []
    # The legacy rule: a valid comparison or diagram anywhere; no new blocks required.
    assert tutorial_visual_issues(step["lesson_content"].replace("vs\n", "versus?\n"))
    # Legacy lessons keep their 450-800 word range.
    long = {**step, "lesson_content": step["lesson_content"] + " extra" * (780 - len(step["lesson_content"].split()))}
    assert plan_detail_step_quality_issues(plan_detail_step_model(long).model_validate(long)) == []
    # Capacity correction can still split and rebuild both shapes byte for byte.
    assert _render(step["title"], _sections(step)) == step["lesson_content"]
    assert "guided_practice" in _sections(step)
    new = assemble(harbor_sections(), harbor_package()).data
    assert "guided_practice" not in _sections(new)
    assert _render(new["title"], _sections(new)) == new["lesson_content"]


@pytest.mark.parametrize("kind", ["formula", "chart", "steps", "check"])
def test_capacity_edits_retain_every_reviewed_block(kind):
    from app.services.planning.tutorial_capacity import _retain_native_visuals
    fence = {"formula": FORMULA, "chart": WATERFALL, "steps": STEPS, "check": CHECK}[kind]
    original = "Long original explanation.\n\n" + fence
    rewritten = "Short explanation.\n\n" + fence.replace("Net", "Gross").replace("$50m", "$5m")
    assert _retain_native_visuals(original, rewritten) == "Short explanation.\n\n" + fence
    with pytest.raises(ValueError, match="retain every native visual"):
        _retain_native_visuals(original, "Short explanation without the block.")


def test_writer_validates_blocks_after_rendering_without_practice_bindings():
    from app.services.planning.lesson_writer import _TUTORIAL_GROUP, _tokens, _validated_group
    context = harbor_package().writer_context()
    data = harbor_sections()
    result, issues = _validated_group(LLMResponse(data=data), _TUTORIAL_GROUP, PlanTutorialLessonSectionsOutput,
        *_tokens(context), package_context=context, allotted_lesson_minutes=6, lesson_title="Estimate owner earnings")
    assert issues == [] and "guided_practice" not in result
    assert "guided_practice" not in _TUTORIAL_GROUP.fields
    wrong = {**data, "worked_example": data["worked_example"].replace("| 22 |", "| 23 |")}
    result, issues = _validated_group(LLMResponse(data=wrong), _TUTORIAL_GROUP, PlanTutorialLessonSectionsOutput,
        *_tokens(context), package_context=context, allotted_lesson_minutes=6, lesson_title="Estimate owner earnings")
    assert result is None and any(issue.startswith("worked_example steps fence is invalid") for issue in issues)
    missing = {**data, "worked_example": data["worked_example"].replace(
        "[[result:harbor.owner_earnings]]", "68")}
    result, issues = _validated_group(LLMResponse(data=missing), _TUTORIAL_GROUP, PlanTutorialLessonSectionsOutput,
        *_tokens(context), package_context=context, allotted_lesson_minutes=6, lesson_title="Estimate owner earnings")
    assert result is None and "worked_example must include [[result:harbor.owner_earnings]]" in issues


def test_writer_prompt_examples_satisfy_the_grammar():
    """Every example the writer sees must pass the validator it is held to."""
    from app.services.planning.lesson_package import render_public_package_results
    from app.services.planning.lesson_writer import _tutorial_contract
    from app.services.planning.tutorial_visuals import BLOCK_KINDS, fence_error, native_fences
    contract = _tutorial_contract()
    assert "{domain_blocks}" not in contract
    text = render_public_package_results({"x": contract}, harbor_package().writer_context(), require_all=False)["x"]
    fences = native_fences(text)
    assert sorted(kind for kind, _ in fences) == sorted(BLOCK_KINDS)
    assert {kind: fence_error(kind, fence_body) for kind, fence_body in fences} == dict.fromkeys(BLOCK_KINDS)


def test_crlf_fences_are_recognized():
    from app.services.planning.tutorial_visuals import native_fences
    assert native_fences(FORMULA.replace("\n", "\r\n")) == [("formula", body(FORMULA).replace("\n", "\r\n") + "\r\n")]
    assert parse_formula(body(FORMULA).replace("\n", "\r\n")) is not None


def drifted_sections() -> dict:
    data = harbor_sections()
    data["worked_example"] = data["worked_example"].replace(
        "[[result:harbor.owner_earnings]]", "[[result: harbor.owner_earnings]]")
    return data


def test_whitespace_drifted_token_is_a_correctable_issue_not_a_crash():
    from app.services.planning.lesson_writer import _TUTORIAL_GROUP, _tokens, _validated_group
    context = harbor_package().writer_context()
    for allotted in (None, 6):
        result, issues = _validated_group(LLMResponse(data=drifted_sections()), _TUTORIAL_GROUP,
            PlanTutorialLessonSectionsOutput, *_tokens(context), package_context=context,
            allotted_lesson_minutes=allotted, lesson_title="Estimate owner earnings")
        assert result is None
        assert any(issue.startswith("Unknown case/answer bindings")
                   and "[[result: harbor.owner_earnings]]" in issue for issue in issues)


def test_render_failure_becomes_a_validation_issue(monkeypatch):
    from app.services.planning.lesson_writer import _TUTORIAL_GROUP, _tokens, _validated_group
    context = harbor_package().writer_context()

    def broken(*args, **kwargs):
        raise ValueError("Unknown teaching result ID")

    monkeypatch.setattr("app.services.planning.lesson_package.render_public_package_results", broken)
    result, issues = _validated_group(LLMResponse(data=harbor_sections()), _TUTORIAL_GROUP,
        PlanTutorialLessonSectionsOutput, *_tokens(context), package_context=context,
        allotted_lesson_minutes=6, lesson_title="Estimate owner earnings")
    assert result is None and any("could not be rendered" in issue for issue in issues)


@pytest.mark.asyncio
async def test_drifted_token_triggers_a_correction_attempt_not_a_job_failure():
    from app.services.planning.lesson_writer import generate_lesson_sections
    context = harbor_package().writer_context()
    replies = [drifted_sections(), harbor_sections()]

    class Client:
        model = "offline"

        async def generate_json(self, **kwargs):
            return LLMResponse(data=replies.pop(0), finish_reason="stop")

    result, calls = await generate_lesson_sections(system_prompt="Teach", lesson_prompt="Owner earnings",
        package_context=context, lesson_format="tutorial_v1", allotted_lesson_minutes=6,
        lesson_title="Estimate owner earnings", client_factory=lambda **kwargs: Client())
    assert not result.error and len(calls) == 2 and replies == []
    assert "Unknown case/answer bindings" in calls[0][1].error
    assert "[[result:harbor.owner_earnings]]" in result.data["worked_example"]
