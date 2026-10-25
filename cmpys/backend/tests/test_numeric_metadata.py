"""Only complete field-owned structural list markers can be masked."""
import re

import pytest

from app.services.planning.numeric_metadata import (
    mask_structural_ordinals, structural_ordinal_intervals,
)


@pytest.mark.parametrize("source,markers", [
    ("Intro: (1) Explain the choice։ (2) Revise the sentence։ (3) Check the result։", ["(1)", "(2)", "(3)"]),
    ("(1) Ընտրեք մոտեցումը։ (2) Բացատրեք պատճառը։ (3) Ստուգեք պատասխանը։", ["(1)", "(2)", "(3)"]),
    ("Հրահանգ՝ (1) Ընտրեք մոտեցումը։ (2) Ստուգեք պատասխանը։", ["(1)", "(2)"]),
    ("Intro․1) Explain the distinction,2) Apply it,3) Check your reasoning։", ["1)", "2)", "3)"]),
    ("Intro: (1) opening amount 10, (2) following amount 20, (3) compare the amounts.", ["(1)", "(2)", "(3)"]),
    ("(1) Explain the reasoning.\n    (2) Revise the response.\n(3) Check the result.", ["(1)", "(2)", "(3)"]),
])
def test_complete_consistent_lists_across_sentences_keep_exact_offsets(source, markers):
    intervals = structural_ordinal_intervals(source)
    assert [source[start:end] for start, end in intervals] == markers
    masked = mask_structural_ordinals(source, source=source, start=0)
    assert len(masked) == len(source)
    changed = {index for start, end in intervals for index in range(start, end)}
    assert all(masked[index] == (" " if index in changed else char) for index, char in enumerate(source))


def test_mixed_quantities_and_wrong_equation_are_retained_byte_for_byte():
    source = "Tasks: (1) Revenue is 999։ (2) Explain why 10 + 20 = 99 is wrong։ (3) Compare 20% and 25%։"
    masked = mask_structural_ordinals(source, source=source, start=0)
    assert len(structural_ordinal_intervals(source)) == 3
    assert "Revenue is 999։" in masked
    assert "10 + 20 = 99" in masked
    assert "20% and 25%" in masked
    assert re.findall(r"\d+", masked) == ["999", "10", "20", "99", "20", "25"]


@pytest.mark.parametrize("source", [
    "(1) Explain the choice։",  # one item cannot prove a sequence
    "(2) Explain the choice։ (3) Revise the response։",
    "(1) Explain the choice։ (3) Revise the response։",
    "(1) Explain the choice։ (2) Revise the response։ (2) Check again։",
    "(2) Explain the choice։ (1) Revise the response։",
    "(1) Explain the choice։ 2) Revise the response։",
    "(0) Explain the choice։ (1) Revise the response։",
    "Intro: (1) cm, (2) cm",
    "Intro: (1) million dollars, (2) million dollars",
    "Intro: (1) kg of salt, (2) kg of flour",
    "Չափումներ՝ (1) սմ, (2) սմ",
    "Չափումներ՝ (1) միլիոն դրամ, (2) միլիոն դրամ",
    "Intro: 1) 20kg, 2) 30kg",
    "Intro: (1) x + 2, (2) y + 3",
    "(1) + (2) = 3",
    "(1) times x, (2) times y",
    "(1) / (2)",
    "Prices: $1) apple, $2) pear",
    "Values: 0.1) item, 0.2) item",
    "Values: -1) item, +2) item",
    "Use (1) kg then (2) kg for the mixture.",
    "See (1) first reference and (2) second reference.",
    "f(1) increases while f(2) decreases.",
    'A learner wrote "(1) Explain the choice։ (2) Revise the response։"',
    'A learner wrote "\n(1) Explain the choice։\n(2) Revise the response։\n"',
    "An example: «(1) Explain the choice։ (2) Revise the response։»",
    "An example:\n```\n(1) Explain the choice։\n(2) Revise the response։\n```",
])
def test_ambiguous_sequences_quantities_formulas_references_and_quotes_remain_visible(source):
    assert structural_ordinal_intervals(source) == []
    assert mask_structural_ordinals(source, source=source, start=0) == source


@pytest.mark.parametrize("unit", ["widgets", "mW", "MW", "քառ․ մ", "custom units"])
def test_declared_units_block_amount_like_items_without_converting_units(unit):
    source = f"Amounts: (1) {unit}, (2) {unit}"
    assert structural_ordinal_intervals(source, units=[unit]) == []
    assert mask_structural_ordinals(source, source=source, start=0, units=[unit]) == source


@pytest.mark.parametrize("unit", ["dollar", "dollars", "metre", "metres", "kilogram", "kilograms",
                                "milligram", "milligrams", "litre", "litres", "hour", "hours"])
def test_common_singular_and_plural_measurements_remain_visible_without_declared_data(unit):
    source = f"Amounts: (1) {unit}, (2) {unit}"
    assert structural_ordinal_intervals(source) == []
    assert mask_structural_ordinals(source, source=source, start=0) == source


def test_each_sentence_uses_its_exact_owning_field_offsets():
    source = "Intro: (1) Explain the choice։ (2) Revenue is 999։ (3) Revise the response։"
    span = "(2) Revenue is 999։"
    start = source.index(span)
    masked = mask_structural_ordinals(span, source=source, start=start)
    assert masked == "    Revenue is 999։"
    assert len(masked) == len(span)
    assert mask_structural_ordinals(span, source=source, start=0) == span
    # A source substring beginning inside a marker does not own the full marker.
    assert mask_structural_ordinals(span[1:], source=source, start=start + 1) == span[1:]


def test_separate_source_fields_cannot_complete_each_others_sequence():
    first = "Intro: (1) Explain the choice։"
    second = "(2) Revise the response։"
    assert structural_ordinal_intervals(first) == []
    assert structural_ordinal_intervals(second) == []
    assert mask_structural_ordinals(first, source=first, start=0) == first
    assert mask_structural_ordinals(second, source=second, start=0) == second


def test_identical_quoted_and_unquoted_occurrences_never_share_a_mask():
    quoted = '"(1) Explain the choice։ (2) Revise the response։"'
    actual = "(1) Explain the choice։ (2) Revise the response։"
    source = quoted + "\n" + actual
    intervals = structural_ordinal_intervals(source)
    assert len(intervals) == 2 and all(start > len(quoted) for start, _ in intervals)
    quoted_span = "(1) Explain the choice։"
    assert mask_structural_ordinals(quoted_span, source=source, start=1) == quoted_span
    actual_start = len(quoted) + 1
    assert mask_structural_ordinals(quoted_span, source=source, start=actual_start).startswith("    Explain")


def test_quote_inside_real_item_does_not_hide_a_second_quantitative_occurrence():
    source = 'Tasks: (1) Explain the quoted measurement "(2) cm"։ (2) Revise the response։'
    intervals = structural_ordinal_intervals(source)
    assert [source[start:end] for start, end in intervals] == ["(1)", "(2)"]
    masked = mask_structural_ordinals(source, source=source, start=0)
    assert '"(2) cm"' in masked


@pytest.mark.parametrize("opening,closing", [("«", "»"), ("“", "”"), ('"', '"'), ("‘", "’"), ("'", "'")])
def test_complete_quoted_item_starts_mix_with_plain_items_and_preserve_tails(opening, closing):
    source = (f"Tasks: (1) {opening}Explain the opening claim{closing} and justify it։ "
              f"(2) Revise the example։ (3) {opening}Check the conclusion{closing} against the task։ "
              f"(4) {opening}Describe the revision{closing} with a reason։")
    intervals = structural_ordinal_intervals(source)
    assert [source[start:end] for start, end in intervals] == ["(1)", "(2)", "(3)", "(4)"]
    masked = mask_structural_ordinals(source, source=source, start=0)
    changed = {index for start, end in intervals for index in range(start, end)}
    assert len(masked) == len(source)
    assert all(masked[index] == (" " if index in changed else char) for index, char in enumerate(source))


def test_quoted_item_content_and_after_quote_quantities_remain_exact():
    source = ('Tasks: (1) «Explain why 10 + 20 = 99 is wrong» and compare 25%։ '
              '(2) «Check the measurement (2) cm» using 30 cm։')
    intervals = structural_ordinal_intervals(source)
    assert [source[start:end] for start, end in intervals] == ["(1)", "(2)"]
    masked = mask_structural_ordinals(source, source=source, start=0)
    assert '«Explain why 10 + 20 = 99 is wrong» and compare 25%' in masked
    assert '«Check the measurement (2) cm» using 30 cm' in masked
    assert re.findall(r"\d+", masked) == ["10", "20", "99", "25", "2", "30"]
    span = '(2) «Check the measurement (2) cm» using 30 cm։'
    start = source.index(span)
    assert mask_structural_ordinals(span, source=source, start=start) == '    «Check the measurement (2) cm» using 30 cm։'
    assert mask_structural_ordinals(span, source=source, start=0) == span


def test_word_internal_apostrophes_do_not_make_plain_list_ownership_ambiguous():
    source = "Tasks: (1) Explain the learner’s claim։ (2) Revise the author’s answer։"
    assert [source[start:end] for start, end in structural_ordinal_intervals(source)] == ["(1)", "(2)"]


@pytest.mark.parametrize("item", ["20 words", "cm", "mW", "million dollars", "custom units", "x + 2"])
def test_quoted_numeric_unit_scale_and_formula_starts_remain_visible(item):
    source = f'Items: (1) «{item}» with context։ (2) «{item}» with more context։'
    assert structural_ordinal_intervals(source, units=["mW", "custom units"]) == []
    assert mask_structural_ordinals(source, source=source, start=0,
                                    units=["mW", "custom units"]) == source


@pytest.mark.parametrize("source", [
    'Tasks: (1) «Explain the claim։ (2) Revise the answer։',
    'Tasks: (1) «Explain the claim»։ (2) «Revise the answer։',
    'Example: «(1) Explain the claim։ (2) Revise the answer։»',
    'Example: ««Intro»\n(1) «First» explanation։ (2) «Second» explanation։»',
    'Example: ““Intro”\n(1) “First” explanation։ (2) “Second” explanation։”',
    'Tasks: (1) «Explain the claim”։ (2) «Revise the answer»։',
    'Tasks: (1) `Explain the claim`։ (2) `Revise the answer`։',
    'Tasks: (1) "20 words"։ (2) Revise the answer։',
    'Tasks: (1) "Explain the claim"։ (3) "Revise the answer"։',
    'Tasks: (1) "Explain the claim"։ (2) "Revise the answer"։ (2) Check again։',
])
def test_quoted_items_do_not_relax_quote_ownership_or_sequence_requirements(source):
    assert structural_ordinal_intervals(source) == []
    assert mask_structural_ordinals(source, source=source, start=0) == source


@pytest.mark.parametrize("source,markers", [
    ("**Heading.** 1) Explain the claim, 2) Revise the response, 3) Check the answer.", ["1)", "2)", "3)"]),
    ('**Heading.** (1) «Explain the claim»։ (2) Revise the response։ (3) «Check the answer».', ["(1)", "(2)", "(3)"]),
    ("  **Հրահանգ՝** (1) Ընտրեք մոտեցումը։ (2) Ստուգեք արդյունքը։", ["(1)", "(2)"]),
    ("Prior paragraph.\n\t**Heading:**\t(1) Explain the choice։ (2) Revise it։", ["(1)", "(2)"]),
])
def test_balanced_standalone_bold_label_keeps_its_underlying_boundary(source, markers):
    intervals = structural_ordinal_intervals(source)
    assert [source[start:end] for start, end in intervals] == markers
    masked = mask_structural_ordinals(source, source=source, start=0)
    changed = {index for start, end in intervals for index in range(start, end)}
    assert len(masked) == len(source)
    assert all(masked[index] == (" " if index in changed else char) for index, char in enumerate(source))


def test_bold_boundary_does_not_hide_item_quantities_equations_or_quote_content():
    source = ('**Heading.** (1) «Explain why 10 + 20 = 99 is wrong»։ '
              '(2) Compare revenue 999 and expense 12։ (3) Check the measurement (2) cm։')
    intervals = structural_ordinal_intervals(source)
    assert [source[start:end] for start, end in intervals] == ["(1)", "(2)", "(3)"]
    masked = mask_structural_ordinals(source, source=source, start=0)
    assert masked.startswith("**Heading.**")
    assert '«Explain why 10 + 20 = 99 is wrong»' in masked
    assert "revenue 999 and expense 12" in masked
    assert "measurement (2) cm" in masked
    assert re.findall(r"\d+", masked) == ["10", "20", "99", "999", "12", "2"]
    span = '(2) Compare revenue 999 and expense 12։'
    start = source.index(span)
    assert mask_structural_ordinals(span, source=source, start=start) == '    Compare revenue 999 and expense 12։'
    assert mask_structural_ordinals(span, source=source, start=0) == span


@pytest.mark.parametrize("prefix", [
    "**", "Heading.**", "***Heading.***", "**Heading**", "**Heading. **",
    "** Heading.**", "**Heading.* **", "**Outer **Heading.**", "**Heading:** trailing prose",
    "Prose **Heading.**", "**2.**", "**0.1.**", "**x + y.**", "**x.**", "**base * height.**",
    "**rate / time.**", "2 ** Heading.**", "**rate^power.**", "\\**Heading.**",
])
def test_arbitrary_delimiters_formulas_and_unbalanced_markdown_are_not_boundaries(prefix):
    source = prefix + " (1) Explain the claim։ (2) Revise the answer։"
    assert structural_ordinal_intervals(source) == []
    assert mask_structural_ordinals(source, source=source, start=0) == source


@pytest.mark.parametrize("source,units", [
    ('Example: «**Heading.** (1) Explain the claim։ (2) Revise the answer։»', ()),
    ('"**Heading.** (1) Explain the claim։ (2) Revise the answer։"', ()),
    ('```\n**Heading.** (1) Explain the claim։ (2) Revise the answer։\n```', ()),
    ('**Heading.** (1) cm։ (2) cm։', ()),
    ('**Heading.** (1) "20 words"։ (2) Explain the result։', ()),
    ('**Heading.** (1) custom units։ (2) custom units։', ("custom units",)),
    ('**Heading.** (1) Explain the claim։ (3) Revise the answer։', ()),
    ('**Heading.** (1) Explain the claim։ (2) Revise the answer։ (2) Check it։', ()),
    ('**Heading.** (1) Explain the claim։', ()),
])
def test_markdown_boundary_keeps_quote_quantity_and_sequence_guards(source, units):
    assert structural_ordinal_intervals(source, units=units) == []
    assert mask_structural_ordinals(source, source=source, start=0, units=units) == source
