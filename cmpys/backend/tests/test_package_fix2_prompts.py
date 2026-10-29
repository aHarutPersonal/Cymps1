"""Fixes 7 and 8 (smoke2): seed/activity authoring rules and a one-pass semantic review.

accounting_novice: an explanation gave one item's $400 effect as the whole gap (net $50).
geometry: a question carried a bare formula ("24 × 9 ÷ 2?") with no result.
writing: a qualitative worked example invented "40 adults" with data [].
software: overlapping multi_choice options, and the first review flagged one activity only.
Budgets stay enforced by tests/test_tutorial_prompt_layers.py::test_rendered_prompt_budget.
"""
from app.services.llm.prompt_loader import load_and_render
from app.services.planning.package_preflight import _SEMANTIC_PROMPT

SEED, ACTIVITY = "tutorial_package_seed.txt", "tutorial_activity_generate.txt"


def rendered(name: str) -> str:
    return " ".join(load_and_render(name, {}).split())


def test_activity_prompt_states_effects_formulas_and_qualitative_evidence():
    text = rendered(ACTIVITY)
    assert "each item's effect on its own and the net where items offset" in text
    # In words only: a shown numeric result would be an undeclared derived number
    # and could leak a field's answer (review 5b).
    assert "A question names any formula in words, never as a bare numeric expression" in text
    assert "with its result" not in text
    assert "so a qualitative worked example uses digits only as declared data" in text


def test_activity_prompt_requires_atomic_multi_choice_options_and_a_whole_set_rubric():
    text = rendered(ACTIVITY)
    assert "each option one atomic action whose label contains no other option's action" in text
    assert "for multi_choice, the skill the whole correct set shows" in text
    # The rubric still never names the answer itself (answer-leak gate unchanged).
    assert "never the answer itself" in text


def test_seed_prompt_plans_the_same_rules():
    text = rendered(SEED)
    assert "Qualitative worked examples give evidence in words, with digits only when declared as data" in text
    assert "with its result" not in text


def test_semantic_preflight_reviews_every_activity_in_one_pass():
    text = " ".join(_SEMANTIC_PROMPT.split())
    assert "Review every activity and list all of its issues in this one pass" in text
    assert "multi_choice option that contains another option's action" in text
