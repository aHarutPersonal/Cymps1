"""Bare native-block label lines are fenced before validation (pilot 2026-11-03).

native-luna drafts wrote ``steps:`` / ``check`` / ``formula`` label lines with
no backticks, so every draft failed "found 0" although the block bodies were
valid. Snippets below are quoted from those saved drafts (d72b486c, 82ea247d).
"""
import pytest

from app.services.planning.lesson_writer import _normalize_tutorial_fence_layout
from app.services.planning.tutorial_visuals import (
    native_fences, tutorial_section_issues, wrap_bare_block_labels,
)

# native-luna writing_novice_evidence d72b486c (abridged prose, exact blocks).
WRITING = {
    "core_framework": (
        "An evidence-backed argument joins three parts: a manageable action, a reason grounded in the "
        "supplied evidence, and a boundary around what the evidence does not establish.\n\n"
        "comparison:\nBroad claim\n- Implies a general problem or guaranteed outcome\n"
        "- Leaves the audience unsure what action to judge\nvs\nBounded proposal\n"
        "- Names a manageable action and its reason\n"
        "- Links the evidence to interest, while limiting claims about success\n\n"
        "The method works when evidence directly matches the claim’s predicate and population."),
    "worked_example": (
        "The revision therefore preserves the proposal, narrows its claim, and states a review point.\n\n"
        "steps:\ntitle: Community garden revision\n"
        "The proposed action |  | Add a Saturday tool-sharing table.\n"
        "The evidence-based reason |  | Several visitors have asked whether tools are available.\n"
        "The evidence boundary |  | The evidence does not establish frequency, feasibility, guaranteed demand, or success.\n"
        "The audience-fit next step |  | Let the association review participation after the trial.\n\n"
        "This decision meets the stated revision aim."),
    "check_your_understanding": (
        "Classify the supplied sentence: “Several visitors have asked whether tools are available.”\n\n"
        "check:\nQ: Which description best fits this sentence?\n"
        "- [ ] It is only a topic because it gives no recommendation.\n"
        "- [x] It is a factual claim that can support interest in the proposed table.\n"
        "- [ ] It proves the table will be feasible and successful.\n\n"
        "Why: The sentence asserts that visitors asked, so it is a claim. It supports interest, but it "
        "does not establish feasibility or guaranteed success."),
}

# native-luna geometry_novice_evidence 82ea247d: bare labels with an indented first line.
GEOMETRY = {
    "core_framework": ("A triangle’s area is half the area of a rectangle with the same base and height.\n\n"
                       "formula\n title: Triangle area\n= Triangle area\n+ Base × perpendicular height ÷ 2\n\n"
                       "Keep the right-angle condition visible in your reasoning."),
    "worked_example": ("Multiply first, then take half.\n\nsteps\n title: Triangular sign\n unit: cm²\n"
                       " Base × perpendicular height | 40 | 8 × 5 gives the matching rectangle’s area.\n"
                       "− Half removed from the rectangle | −20 | Taking half leaves the triangle’s area.\n"
                       "= Triangle area | [[result:triangle_case.area_cm2]]\n\nThe unit is square centimetres."),
    "check_your_understanding": ("What is its area?\n\ncheck\nQ: Which calculation gives the triangle’s area?\n"
                                 "- [ ] 8 × 5 = 40 square centimetres\n- [x] 8 × 5 ÷ 2 = 20 square centimetres\n"
                                 "- [ ] 8 + 5 = 13 square centimetres\n"
                                 "Why: The first option omits the half factor. The selected option applies the formula."),
}


def _wrapped(sections):
    return _normalize_tutorial_fence_layout(sections)


def test_real_bare_label_drafts_were_rejected_as_missing_blocks():
    issues = tutorial_section_issues(WRITING, case_has_numbers=False)
    assert sum("found 0" in issue for issue in issues) == 3


def test_writing_draft_bare_labels_become_valid_fences():
    wrapped = _wrapped(WRITING)
    assert tutorial_section_issues(wrapped, case_has_numbers=False) == []
    # The Why paragraph after one blank line belongs to the check.
    [(kind, body)] = native_fences(wrapped["check_your_understanding"])
    assert kind == "check" and body.rstrip().splitlines()[-1].startswith("Why: The sentence asserts")
    assert wrapped["core_framework"].endswith("population.")


def test_geometry_draft_bare_labels_with_indented_headers_become_valid_fences():
    wrapped = _wrapped(GEOMETRY)
    rendered = {key: value.replace("[[result:triangle_case.area_cm2]]", "20") for key, value in wrapped.items()}
    # Wrapping preserves the captured text; it must not hide its circular formula.
    issues = tutorial_section_issues(rendered)
    assert len(issues) == 1 and "circular formula" in issues[0]
    corrected = {**rendered, "core_framework": rendered["core_framework"].replace(
        "= Triangle area\n+ Base × perpendicular height ÷ 2",
        "= Base × perpendicular height\n÷ Two")}
    assert tutorial_section_issues(corrected) == []
    assert "```steps\ntitle: Triangular sign\nunit: cm²\n" in wrapped["worked_example"]


@pytest.mark.parametrize("label", ["steps", "steps:", "Steps:", "  steps  "])
def test_label_variants(label):
    text = f"Intro.\n\n{label}\ntitle: Plot\nBase | | 6 cm\n= Area | 24"
    assert wrap_bare_block_labels(text) == "Intro.\n\n```steps\ntitle: Plot\nBase | | 6 cm\n= Area | 24\n```"


def test_wrapping_is_idempotent_and_leaves_existing_fences_alone():
    once = wrap_bare_block_labels(WRITING["worked_example"])
    assert wrap_bare_block_labels(once) == once
    fenced = "Intro.\n\n```check\nQ: Pick one\n- [x] A\n- [ ] B\nWhy: Because.\n```"
    assert wrap_bare_block_labels(fenced) == fenced


@pytest.mark.parametrize("text", [
    "We check our work twice.\n\ncheck\n- Re-read the claim\n- Compare it with the evidence",  # prose list
    "Next come the steps:\ntitle: Plot\nBase | | 6",               # label not at a paragraph start
    "Intro.\n\nsteps:\n1. Read the case\n2. Name the action",     # no title or row cells
    "Intro.\n\ncomparison:\n- Broad claim\n- Narrow claim",       # no heading before the items
    "Intro.\n\nformula:\nThe area is half the product.",          # no title or signed term
    "Intro.\n\nsteps:",                                          # no body at all
])
def test_prose_that_does_not_open_the_block_grammar_is_untouched(text):
    assert wrap_bare_block_labels(text) == text


def test_an_unfenced_draft_without_a_block_body_still_fails_found_zero():
    sections = {**WRITING, "check_your_understanding": "We check our work twice.\n\ncheck\n- Re-read the claim"}
    issues = tutorial_section_issues(_wrapped(sections), case_has_numbers=False)
    assert "check_your_understanding must include exactly one valid check fence; found 0" in issues


def test_a_wrapped_but_malformed_body_is_still_rejected_by_the_grammar():
    sections = {**WRITING, "check_your_understanding": "Pick.\n\ncheck:\nQ: Which one?\n- [ ] A\n- [ ] B\nWhy: None."}
    issues = tutorial_section_issues(_wrapped(sections), case_has_numbers=False)
    assert any("check fence is invalid" in issue and "mark at least one correct option" in issue for issue in issues)


# haiku-12 accounting_novice_evidence f1f860cf: a complete check with no label at all.
UNLABELED = ("Q: In the Maple Cup case, select every item that makes March cash flow lower than accrual profit.\n"
             "- [x] The unpaid March catering invoice\n- [x] Stock paid for in March but kept for April\n"
             "- [ ] The 800 collected for February's invoice\n- [ ] Rent paid, which equals rent expense\n"
             "Why: Both selected items raise the gap. Rent paid equals rent expense, so it adds no gap.")
# luna geometry_novice_missing 6f0fa8c1: the label and the question share a line.
SAME_LINE = ("Գործնականում կտեսնեք նոր տրված չափումներ։\n\n"
             "check: Q: Ո՞րն է դրա մակերեսը։\n- [ ] 60 քառակուսի սանտիմետր\n- [x] 30 քառակուսի սանտիմետր\n"
             "Why: 60-ը միայն հիմք × բարձրություն արտադրյալն է։")


@pytest.mark.parametrize("text", [UNLABELED, SAME_LINE])
def test_label_less_and_same_line_checks_become_fences(text):
    wrapped = wrap_bare_block_labels(text)
    [(kind, body)] = native_fences(wrapped)
    assert kind == "check" and body.startswith("Q: ") and body.rstrip().splitlines()[-1].startswith("Why: ")
    assert tutorial_section_issues({**_wrapped(WRITING), "check_your_understanding": wrapped},
                                   case_has_numbers=False) == []


@pytest.mark.parametrize("text", [
    "Q: Which option fits?\n- [x] A\n- [ ] B",                                 # no Why line
    "Q: Which option fits?\nThink about the case first.\n- [x] A\n- [ ] B\nWhy: A fits.",   # prose inside
    "Q: Which option fits?\nWhy: A fits.",                                      # no options
    "Intro.\nQ: Which option fits?\n- [x] A\n- [ ] B\nWhy: A fits.",            # not a paragraph start
])
def test_q_paragraphs_that_are_not_exactly_a_check_stay_prose(text):
    assert wrap_bare_block_labels(text) == text
