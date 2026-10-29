"""The writer is told the steps/formula shape it is validated against."""
from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning.lesson_writer import _TUTORIAL_GROUP, _tutorial_contract


def _flat(text: str) -> str:
    return " ".join(text.split())


def test_writer_contract_states_one_final_total_row_and_product_rows():
    contract = _flat(_tutorial_contract())
    assert 'Only the final line starts with "=", and nothing follows its number' in contract
    assert "inputs and factors such as base or height leave the number empty" in contract
    # Fix 7 (29 Oct, round 2): labels hold no numerals, so "÷ 2 (half)" became "Half of it".
    assert '"Base × height | 24 | 6 × 4"' in contract and '"Half of it | −12 |' in contract
    assert "With two results, total the main one and give the other its own valued row, the chart or prose" in contract
    assert 'never a second "=" row or a second steps fence' in contract
    assert "A formula fence holds one equation" in contract


def test_group_instructions_and_domain_line_carry_the_same_rules():
    group = _flat(_TUTORIAL_GROUP.instructions)
    assert 'one final "=" row' in group and "its own valued row, the chart or prose" in group
    [line] = [line for line in resolve_prompt_text("tutorial_domain_quantitative.txt").splitlines()
              if line.startswith("- Lesson blocks for numbers")]
    assert "one equation" in line and 'only "=" row' in line
    assert "inputs and factors leave the value empty" in line.lower() and "a product is one row" in line.lower()
    assert "its own valued row, the chart or prose" in line
