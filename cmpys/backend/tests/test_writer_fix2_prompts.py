"""Writer prompt rules from the second smoke run (fixes 1 and 7, writer part)."""
from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning.lesson_writer import _TUTORIAL_GROUP, _prompt, _tutorial_contract
from tests.test_tutorial_visuals import harbor_package
from tests.test_tutorial_workload_profile import short_package

# Contract length before these rules were added: new lines are paid for by
# tighter wording elsewhere, never by dropping a rule.
CONTRACT_CHARS_BEFORE = 5743
GROUP_CHARS_BEFORE = 498


def _flat(text: str) -> str:
    return " ".join(text.split())


def test_totals_instruction_is_scoped_to_cases_with_numbers():
    group = _flat(_TUTORIAL_GROUP.instructions)
    assert 'With case numbers, the steps fence totals the main result on one final "=" row' in group
    assert 'Without case numbers, step values stay empty and no row starts with "="' in group
    qualitative = [line for line in resolve_prompt_text("tutorial_domain_qualitative.txt").splitlines()
                   if line.startswith("- Lesson blocks")]
    assert qualitative and "step values stay empty" in qualitative[0]
    assert len(_TUTORIAL_GROUP.instructions) <= GROUP_CHARS_BEFORE + 80


def test_contract_steps_rule_is_scoped_and_labels_hold_no_numerals():
    contract = _flat(_tutorial_contract())
    assert 'with numbers, a final "= <label> | <number>" row' in contract
    assert "Labels hold no numerals: the value cell carries the number" in contract
    assert '"Half of it | −12 | <why>"' in contract and "÷ 2 (" not in contract
    assert "(value in the note)" in contract
    # The qualitative domain line reaches the writer contract too.
    assert "walks the example in steps whose notes carry the reasoning; step values stay empty" in contract


def test_contract_states_check_formulas_and_offsetting_items():
    contract = _flat(_tutorial_contract())
    assert "A formula in the question is written in words or shows its result" in contract
    assert "When items offset each other, state each item's effect on its own, then the net" in contract


def test_contract_stays_within_its_previous_length():
    assert len(_tutorial_contract()) <= CONTRACT_CHARS_BEFORE


def test_prompt_names_the_no_numbers_case_only_when_the_package_has_none():
    marker = "This package has no case numbers"
    qualitative = _prompt(_TUTORIAL_GROUP, "context", short_package().writer_context(), [])
    numeric = _prompt(_TUTORIAL_GROUP, "context", harbor_package().writer_context(), [])
    assert marker in qualitative and "do not score or count" in qualitative
    assert marker not in numeric
