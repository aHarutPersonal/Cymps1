"""Task/Step/Part/Question list labels are structure, not numeric claims."""
import pytest

from app.services.planning.lesson_review import _numeric_span_occurrences
from app.services.planning.numeric_metadata import (
    mask_structural_ordinals, structural_ordinal_intervals,
)

# Real instructions of the accounting_novice_evidence smoke run (pre-redraft).
ARTIFACT = (
    "Compute the month's net cash change using only what actually happened to cash this month, "
    "then answer the owner's question.\n\n"
    "Task 1: classify each line — does it belong to this month's accrual activity, this month's "
    "cash flows, or both — and compute net cash change for the month.\n\n"
    "Task 2: the owner looks only at the bank balance and feels the month went badly. "
    "Which single number is being misjudged, and why?")


def masked(source: str, units=()) -> str:
    return mask_structural_ordinals(source, source=source, start=0, units=units)


def test_artifact_task_labels_are_not_numeric_spans():
    assert list(_numeric_span_occurrences(ARTIFACT)) == []
    view = masked(ARTIFACT)
    assert "Task" in view and "1" not in view and "2" not in view and len(view) == len(ARTIFACT)


@pytest.mark.parametrize("label", ["Task", "Step", "Part", "Question", "task", "STEP"])
@pytest.mark.parametrize("mark", [":", ")", "."])
def test_complete_in_order_label_sequence_is_structural(label, mark):
    source = f"{label} 1{mark} describe the receipts.\n{label} 2{mark} explain the gap between them."
    assert list(_numeric_span_occurrences(source)) == []
    assert [source[a:b] for a, b in structural_ordinal_intervals(source)] == ["1", "2"]


def test_sequence_at_sentence_start_on_one_line():
    source = "Task 1: list the lines. Task 2: explain the gap. Task 3: decide what to do."
    assert list(_numeric_span_occurrences(source)) == []


def test_quantities_inside_labeled_items_stay_claims():
    source = "Task 1: pay 40 dollars today.\nTask 2: explain why."
    view = masked(source)
    assert "40" in view and view.startswith("Task")
    assert [span for _, span in _numeric_span_occurrences(source)] == ["Task 1: pay 40 dollars today."]


@pytest.mark.parametrize("source", [
    "Task 3: review the figures carefully.",                         # lone, not 1..N
    "Task 2: review the figures.\nTask 3: explain the gap.",          # does not start at 1
    "Task 1: review the figures.\nTask 3: explain the gap.",          # gap
    "Task 1: review the figures.\nTask 1: explain the gap.",         # repeated
    "Task 2: explain the gap.\nTask 1: review the figures.",          # out of order
    "Step 2 costs $40 and Step 3 costs $60.",                        # no label punctuation
    "The cost is $40. Step 2 costs $40.",                            # prose claim
    "Task 1: 200 + 300\nTask 2: explain.",                            # item starts with a quantity
    "Task 1: cm of fabric\nTask 2: explain.",                         # item starts with a unit
    'Say "Task 1: review it. Task 2: explain it." aloud.',            # quoted
    "Task 1: review it. See also the note on Task 2: explain it.",   # second label not at a boundary
])
def test_incomplete_or_ambiguous_sequences_remain_numeric_claims(source):
    assert masked(source) == source
    assert structural_ordinal_intervals(source) == []
    assert list(_numeric_span_occurrences(source))


def test_labels_of_different_words_do_not_complete_each_other():
    source = "Task 1: review the figures.\nStep 2: explain the gap."
    assert masked(source) == source


def test_label_sequences_do_not_cross_source_fields():
    first, second = "Task 1: review the figures.", "Task 2: explain the gap."
    assert masked(first) == first and masked(second) == second
