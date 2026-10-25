import pytest

from app.services.planning.numeric_metadata import reviewed_sentence_reference_intervals
from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans


def test_sentence_references_stay_in_inventory_and_require_review():
    text = "Sentence 1 shows an action. Sentence 2 explains the motive."
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson))
    assert ids
    missing = LessonReview(acceptable=True, issues=[], practice_minutes=1, contains_calculations=False, calculations=[])
    assert grounded_failures(missing, lesson)
    reviewed = missing.model_copy(update={"literal_fact_ids": ids})
    assert not grounded_failures(reviewed, lesson)


@pytest.mark.parametrize("text", [
    'The quoted passage is "Sentence 3 costs 20 dollars."',
    "The sentence 3 years long has no ordinal reference.",
    "Sentence 3.5 explains the motive.",
    "Sentence 3kg is not a sentence reference.",
    "Sentence 3 / 2 is a quotient.",
    "Unclosed quote: 'Sentence 3 is a claim.",
])
def test_quantities_quoted_or_ambiguous_text_are_not_references(text):
    assert reviewed_sentence_reference_intervals(text) == []


def test_reference_never_hides_an_attached_case_quantity():
    package = {"private_workbook": {"activities": [{"id": "example", "data": [],
        "instructions": "Sentence 3 says the rent is 200 dollars overdue."}]}}
    ids = list(numeric_spans({}, package))
    reviewed = LessonReview(acceptable=True, issues=[], practice_minutes=1, contains_calculations=False, calculations=[], literal_fact_ids=ids)
    assert grounded_failures(reviewed, {}, package)


def test_possessive_apostrophe_cannot_open_or_close_an_instructional_quote():
    text = "The example says 'her father's tools'. Sentence 3 explains her motive."
    ranges = reviewed_sentence_reference_intervals(text)
    assert [text[a:b] for a, b in ranges] == ["3"]
    quoted = "The example says 'her father's sentence 3 costs 200 dollars'."
    assert reviewed_sentence_reference_intervals(quoted) == []


def test_numbered_detail_labels_require_independent_coverage_and_complete_sequence():
    text = "• Physical detail 1: the flour tin conceals the letter.\n• Physical detail 2: the hand-wiping implies shame."
    package = {"private_workbook": {"activities": [{"id": "guided", "data": [], "instructions": text}]}}
    ids = list(numeric_spans({}, package))
    assert len(ids) == 2
    missing = LessonReview(acceptable=True, issues=[], practice_minutes=1, contains_calculations=False, calculations=[])
    assert grounded_failures(missing, {}, package)
    assert not grounded_failures(missing.model_copy(update={"literal_fact_ids": ids}), {}, package)


@pytest.mark.parametrize("text", [
    "Physical detail 1: a lone label.",
    "Physical detail 1: first.\nPhysical detail 3: missing second.",
    "Physical detail 1: first.\nExample 2: mixed labels.",
    '"Physical detail 1: quoted.\nPhysical detail 2: still quoted."',
    "An unclosed quote: 'earlier.\nPhysical detail 1: inside.\nPhysical detail 2: inside.",
    "Physical detail 1.5: decimal.\nPhysical detail 2: second.",
    "Physical detail 1 kg: quantity.\nPhysical detail 2 kg: quantity.",
])
def test_ambiguous_labeled_ordinals_are_not_metadata(text):
    from app.services.planning.numeric_metadata import reviewed_labeled_ordinal_intervals
    assert reviewed_labeled_ordinal_intervals(text) == []


def test_numbered_detail_labels_do_not_hide_case_quantities_or_join_source_fields():
    text = "Physical detail 1: the fee is 200 dollars.\nPhysical detail 2: the letter is hidden."
    package = {"private_workbook": {"activities": [{"id": "guided", "data": [], "instructions": text}]}}
    ids = list(numeric_spans({}, package))
    verdict = LessonReview(acceptable=True, issues=[], practice_minutes=1, contains_calculations=False, calculations=[], literal_fact_ids=ids)
    assert grounded_failures(verdict, {}, package)
    separate = {"private_workbook": {"activities": [{"id": "guided", "data": [], "instructions": "Physical detail 1: the letter.", "hint": "Physical detail 2: the tin."}]}}
    ids = list(numeric_spans({}, separate))
    assert grounded_failures(verdict.model_copy(update={"literal_fact_ids": ids}), {}, separate)


@pytest.mark.parametrize("separator", ["—", "–", ":"])
def test_action_beat_labels_require_complete_same_field_sequence_and_explicit_review(separator):
    text = (f"A strong response reads like this: Beat 1 {separator} Dev hid the notice. "
            f"Beat 2 {separator} He set cups on the table.")
    package = {"private_workbook": {"activities": [{"id": "guided", "data": [], "worked_solution": text}]}}
    ids = list(numeric_spans({}, package))
    missing = LessonReview(acceptable=True, issues=[], practice_minutes=1, contains_calculations=False, calculations=[])
    assert ids and grounded_failures(missing, {}, package)
    assert not grounded_failures(missing.model_copy(update={"literal_fact_ids": ids}), {}, package)


@pytest.mark.parametrize("text", [
    "Beat 1 — Dev hid the notice.",
    "Beat 1 — Dev hid the notice. Beat 3 — He set cups on the table.",
    '"Beat 1 — Dev hid the notice. Beat 2 — He set cups on the table."',
    "Beat 1 — dollars. Beat 2 — dollars.",
    "Beat 1 — 200 dollars. Beat 2 — 100 dollars.",
    "They beat 1 — competitor. They beat 2 — competitors.",
    "Beat 1 — Dev hid the notice. Example 2: He set cups on the table.",
])
def test_ambiguous_action_beat_labels_are_not_metadata(text):
    from app.services.planning.numeric_metadata import reviewed_labeled_ordinal_intervals
    assert reviewed_labeled_ordinal_intervals(text) == []


def test_action_beat_labels_preserve_quantities_and_do_not_join_fields():
    for activity in [
        {"instructions": "Beat 1 — Dev owes 200 dollars. Beat 2 — He hid the notice."},
        {"instructions": "Beat 1 — Dev hid the notice.", "hint": "Beat 2 — He set cups on the table."},
    ]:
        package = {"private_workbook": {"activities": [{"id": "guided", "data": [], **activity}]}}
        ids = list(numeric_spans({}, package))
        review = LessonReview(acceptable=True, issues=[], practice_minutes=1,
                              contains_calculations=False, calculations=[], literal_fact_ids=ids)
        assert ids and grounded_failures(review, {}, package)


@pytest.mark.parametrize("text", [
    "Line A fails criterion 1: it describes the setting with no character action.",
    "Line B fails criterion 1 in a different way: it reports a feeling directly.",
    "Model: 'Beat 1 is action; it shows concealment. Beat 2 named no feeling, but needs clearer motive.' This resolves the confusion.",
    "A strong response follows. Model: Beat 1: Dev hid the notice. Beat 2: He covered it. An honest check follows. Model: 'Beat 1 is action. Beat 2 named no feeling.'",
])
def test_reviewed_criteria_and_complete_model_beat_references(text):
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson))
    review = LessonReview(acceptable=True, issues=[], practice_minutes=1, contains_calculations=False, calculations=[])
    assert ids and grounded_failures(review, lesson, {})
    assert not grounded_failures(review.model_copy(update={"literal_fact_ids": ids}), lesson, {})


@pytest.mark.parametrize("text", [
    "Line A fails criterion 1 kg.",
    "Criterion 1 + 2 equals 5.",
    "Model: 'Beat 1 is action; the payment is 200 dollars. Beat 2 named no feeling.'",
    "Model: 'Beat 1 is action; Beat 3 named no feeling.'",
    "Model: 'Beat 1 is action; Beat 2 named no feeling.",
    "A witness said: 'Beat 1 is action; Beat 2 named no feeling.'",
    "Model: 'Beat 1 kg is heavy; Beat 2 kg is heavier.'",
])
def test_model_and_criterion_references_keep_ambiguous_or_real_quantities(text):
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson))
    review = LessonReview(acceptable=True, issues=[], practice_minutes=1,
                         contains_calculations=False, calculations=[], literal_fact_ids=ids)
    assert ids and grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "Common misconception: an action inside a sentence does not make it shown — one motive-naming clause (sentences 1 and 4) is enough to make the sentence told.",
    "Compare sentences 1, 2, and 4 before revising.",
    "Check criteria 1 or 3 against the draft.",
    "Revisit sentences 2, 4, 7 for the contrast.",
])
def test_plural_references_keep_inventory_and_require_independent_coverage(text):
    from app.services.planning.package_review import _metadata_candidate_ids
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson))
    missing = LessonReview(acceptable=True, issues=[], practice_minutes=1,
                           contains_calculations=False, calculations=[])
    assert ids and grounded_failures(missing, lesson, {})
    assert _metadata_candidate_ids({}, lesson=lesson) == ids
    assert not grounded_failures(missing.model_copy(update={"literal_fact_ids": ids}), lesson, {})


@pytest.mark.parametrize("text", [
    'A witness said "sentences 1 and 4 explain the motive."',
    "Unclosed quote: 'sentences 1 and 4 are claims.",
    "Sentences 1 and 4 years are the penalties.",
    "Criteria 1 and 4 kg are quantities.",
    "Sentences 1 and 4.5 are not ordinal labels.",
    "Sentences 1 and 4kg are quantities.",
    "Sentences 1 and 4 / 2 form a quotient.",
    "Sentences 1 and 4 + 3 form a sum.",
    "Sentences 1 and 4, 7.5 contain an ambiguous final item.",
    "Sentences 1-4 are an unsupported range.",
])
def test_plural_reference_does_not_hide_quoted_or_quantitative_values(text):
    assert reviewed_sentence_reference_intervals(text) == []


def test_plural_reference_preserves_surrounding_quantities_and_custom_units():
    text = "Sentences 1 and 4 say the fee is 200 dollars."
    assert [text[a:b] for a, b in reviewed_sentence_reference_intervals(text)] == ["1", "4"]
    lesson = {"lesson_content": text}
    review = LessonReview(acceptable=True, issues=[], practice_minutes=1,
                          contains_calculations=False, calculations=[],
                          literal_fact_ids=list(numeric_spans(lesson)))
    assert grounded_failures(review, lesson, {})
    assert reviewed_sentence_reference_intervals("Criteria 1 and 4 widgets.", ["widgets"]) == []


@pytest.mark.parametrize("text", [
    "Give the correct stimulus-then-reaction order of sentences (1) and (2), quoting each by its opening words.",
    "Compare sentences (1), (2), and (4) before revising.",
    "Revisit sentence (3) to remove the telling clause.",
    "Check criteria (1) or (3) against the draft.",
])
def test_parenthesized_references_require_explicit_review(text):
    test_plural_references_keep_inventory_and_require_independent_coverage(text)


@pytest.mark.parametrize("text", [
    'A witness said "sentences (1) and (4) explain the motive."',
    "Sentences (1) and (4) years are the penalties.",
    "Criteria (1) and (4) kg are quantities.",
    "Sentences (1) and (4.5) are not ordinal labels.",
    "Sentences (1) and (4) / 2 form a quotient.",
    "Sentences (1) and (4), (7.5) contain an ambiguous final item.",
    "Sentence (3).5 is not an ordinal.",
    "Sentences (1 and (4) are malformed.",
])
def test_parenthesized_references_preserve_ambiguous_values(text):
    assert reviewed_sentence_reference_intervals(text) == []


def test_parenthesized_reference_preserves_surrounding_quantity():
    text = "Sentences (1) and (4) say the fee is 200 dollars."
    assert [text[a:b] for a, b in reviewed_sentence_reference_intervals(text)] == ["1", "4"]
    lesson = {"lesson_content": text}
    review = LessonReview(acceptable=True, issues=[], practice_minutes=1,
                          contains_calculations=False, calculations=[],
                          literal_fact_ids=list(numeric_spans(lesson)))
    assert grounded_failures(review, lesson, {})
    assert reviewed_sentence_reference_intervals("Criteria (1) and (4) widgets.", ["widgets"]) == []


@pytest.mark.parametrize("prefix", ["", "Original: \"She closed the ledger.\" ", "Original: “She closed the ledger.” "])
def test_revision_pass_labels_require_complete_sequence_and_review(prefix):
    text = prefix + "Pass 1: delete the explaining sentence. Pass 2: sharpen the action beats. Pass 3: adjust dialogue."
    test_plural_references_keep_inventory_and_require_independent_coverage(text)


@pytest.mark.parametrize("text", [
    "Pass 1: delete a sentence.",
    "Pass 1: delete a sentence. Pass 3: adjust dialogue.",
    "Pass 1: delete a sentence. Pass 2: adjust dialogue. Pass 2: repeated.",
    '\"Pass 1: delete a sentence. Pass 2: adjust dialogue.\"',
    "Unclosed quote: 'Pass 1: delete a sentence. Pass 2: adjust dialogue.",
    "They pass 1: competitor. They pass 2: competitors.",
    "Pass 1 kg: weight. Pass 2 kg: weight.",
    "Pass 1: dollars. Pass 2: dollars.",
    "Pass 1.5: fractional. Pass 2: a label.",
    "Pass 1 + 2: a sum. Pass 2: a label.",
    "`Pass 1: delete a sentence. Pass 2: adjust dialogue.`",
])
def test_ambiguous_revision_passes_preserve_numeric_checks(text):
    from app.services.planning.numeric_metadata import _reviewed_revision_pass_intervals
    assert _reviewed_revision_pass_intervals(text) == []


def test_revision_pass_labels_preserve_real_quantities_and_field_ownership():
    for activity in [
        {"instructions": "Pass 1: pay 200 dollars. Pass 2: record the cost."},
        {"instructions": "Pass 1: delete a sentence.", "hint": "Pass 2: adjust dialogue."},
    ]:
        package = {"private_workbook": {"activities": [{"id": "guided", "data": [], **activity}]}}
        ids = list(numeric_spans({}, package))
        review = LessonReview(acceptable=True, issues=[], practice_minutes=1,
                              contains_calculations=False, calculations=[], literal_fact_ids=ids)
        assert ids and grounded_failures(review, {}, package)


@pytest.mark.parametrize("text", [
    'First, complete the practice "Spot the Fault" (1-2 minutes): read the excerpt and choose the strongest fault.',
    'Then, in the transfer activity "Diagnose Your Scene" (2-3 minutes), re-open your saved scene and write a revision map.',
    'Next, complete the transfer activity “Fresh Example” (3 minutes): explain the decision.',
    "Complete the practice 'Spot the Fault' (1-2 minutes): read the excerpt.",
])
def test_named_activity_duration_requires_independent_coverage(text):
    test_plural_references_keep_inventory_and_require_independent_coverage(text)


@pytest.mark.parametrize("text", [
    'The worker said to complete the practice "Spot the Fault" (1-2 minutes): then leave.',
    'Complete the practice "The pump takes 20 minutes" (1-2 minutes): explain it.',
    'First, complete the practice "Spot the Fault" (1-2 minutes): the fee is 200 dollars.',
    'Then, in the transfer activity "Diagnose Your Scene" (3-2 minutes), write a revision map.',
    'First, complete the practice "Spot the Fault" (181 minutes): read the excerpt.',
    'First, complete the practice "Spot the Fault (1-2 minutes): an unclosed title.',
    '"First, complete the practice ‘Spot the Fault’ (1-2 minutes): read the excerpt."',
    'In the transfer activity "Test" (1-2 minutes) the pump filled a tank.',
])
def test_named_activity_duration_cannot_hide_case_facts_or_ambiguous_text(text):
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson))
    review = LessonReview(acceptable=True, issues=[], practice_minutes=1,
                          contains_calculations=False, calculations=[], literal_fact_ids=ids)
    assert ids and grounded_failures(review, lesson, {})
