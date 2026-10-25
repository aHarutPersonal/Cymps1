"""List formatting must not become a numerical claim or conceal a real one."""
import copy

import pytest

from app.services.planning.lesson_review import (
    LessonReview, _numeric_span_records, grounded_failures, numeric_spans,
)


def verdict(**evidence):
    return LessonReview(acceptable=True, issues=[], practice_minutes=30,
                        contains_calculations=False, calculations=[], **evidence)


@pytest.mark.parametrize("source", [
    "(1) Կարդացեք ամբողջ տեքստը։ (2) Վերանայեք հիմնական պնդումը։",
    "Intro: (1) Read the supplied text. (2) Revise the main claim.",
    "Intro: (1) Read the supplied text。 (2) Revise the main claim。",
])
def test_complete_field_list_is_recognized_before_sentence_splitting(source):
    assert numeric_spans({"lesson_content": source}) == {}


def test_mixed_list_and_data_preserves_raw_spans_and_requires_exact_facts():
    source = "(1) Opening amount is 10։ (2) Following amount is 20։"
    lesson = {"lesson_content": source}
    package = {"teaching_cases": [{"id": "case", "data": [
        {"id": "opening", "label": "Opening amount", "value": 10},
        {"id": "following", "label": "Following amount", "value": 20},
    ]}]}
    spans = numeric_spans(lesson)
    assert len(spans) == 2
    for _, span, offset, original, _ in _numeric_span_records(lesson):
        assert original == source and original[offset:offset + len(span)] == span
        assert span.startswith("(")
    facts = [{"claim_id": key, "case_id": "teaching.case", "datum_ids": [datum]}
             for key, datum in zip(spans, ("opening", "following"))]
    assert grounded_failures(verdict(literal_facts=facts), lesson, copy.deepcopy(package)) == []
    facts[1]["datum_ids"] = ["opening"]
    assert grounded_failures(verdict(literal_facts=facts), lesson, copy.deepcopy(package))


@pytest.mark.parametrize("source", [
    "(1) Read the supplied text։ (2) The profit is 999։",
    "(1) cm, (2) cm",
    "(1) million dollars, (2) million dollars",
    "(1) Read the supplied text։ (3) Revise the main claim։",
    "(2) Read the supplied text։ (3) Revise the main claim։",
])
def test_list_recognition_does_not_exempt_real_or_ambiguous_quantities(source):
    lesson = {"lesson_content": source}
    spans = numeric_spans(lesson)
    assert spans
    assert grounded_failures(verdict(literal_fact_ids=list(spans)), lesson, {"teaching_cases": []})


def test_sequences_in_separate_fields_cannot_establish_list_provenance():
    lesson = {"lesson_content": "(1) Read the supplied text։",
              "substeps": ["(2) Revise the main claim։"]}
    spans = numeric_spans(lesson)
    assert len(spans) == 2
    assert grounded_failures(verdict(literal_fact_ids=list(spans)), lesson, {"teaching_cases": []})


@pytest.mark.parametrize("separator", [", ", "։ "])
@pytest.mark.parametrize("unit_source", ["data", "fields", "results"])
def test_declared_custom_units_cannot_be_remasked_without_owning_context(separator, unit_source):
    source = "(1) widgets" + separator + "(2) widgets"
    lesson = {"lesson_content": source}
    case = {"id": "case", unit_source: [{"id": "amount", "unit": "widgets", "value": 123}]}
    package = {"teaching_cases": [case]}
    spans = numeric_spans(lesson, package)
    assert spans
    assert grounded_failures(verdict(literal_fact_ids=list(spans)), lesson, package)


def test_quoted_items_with_explanatory_tails_keep_field_owned_numbering():
    source = (
        "Responses: (1) «Explain the opening claim» is the first response։ "
        "(2) Revise the supporting reason։ "
        "(3) «Check the ending» describes the next response։ "
        "(4) «Review the argument» completes the task։"
    )
    assert numeric_spans({"lesson_content": source}) == {}


@pytest.mark.parametrize("source", [
    "Tasks: (1) «The profit is 999» is the claim։ (2) Review the reasoning։",
    "Tasks: (1) «Explain why 10 + 20 = 99» is the example։ (2) Review it։",
    "Tasks: (1) «Review the claim» concerns a loss of 999։ (2) Revise it։",
])
def test_quoted_item_content_and_following_quantities_still_need_proof(source):
    lesson = {"lesson_content": source}
    spans = numeric_spans(lesson)
    assert spans
    assert grounded_failures(verdict(literal_fact_ids=list(spans)), lesson, {"teaching_cases": []})
    for _, span, offset, original, _ in _numeric_span_records(lesson):
        assert original == source and original[offset:offset + len(span)] == span


@pytest.mark.parametrize("rationale_sentences", [5, 1000])
def test_full_field_quote_ownership_work_does_not_scale_with_nonnumeric_sentences(
    monkeypatch, rationale_sentences,
):
    from app.services.planning import numeric_metadata

    source = ("Tasks: (1) «Explain the opening claim» with reasons։ "
              "(2) Revise the example։ "
              + "Teaching rationale. " * rationale_sentences
              + "The opening amount is 999. The following amount is 1001.")
    original_scanner = numeric_metadata._ambiguous_paired_quotes
    full_field_scans = 0

    def counted_scanner(text):
        nonlocal full_field_scans
        if text == source:
            full_field_scans += 1
        return original_scanner(text)

    monkeypatch.setattr(numeric_metadata, "_ambiguous_paired_quotes", counted_scanner)
    records = list(_numeric_span_records({"lesson_content": source}))

    assert [(key, span) for key, span, *_ in records] == [
        ("n1", "The opening amount is 999."),
        ("n2", "The following amount is 1001."),
    ]
    for _, span, offset, original, _ in records:
        assert original == source and source[offset:offset + len(span)] == span
    # One inventory scan plus at most one refinement per actual numeric span.
    # Adding nonnumeric prose must not add whole-field quote/list scans. This
    # bound permits a future single-view implementation without timing tests.
    assert 1 <= full_field_scans <= 1 + len(records)


def test_marker_free_prose_skips_full_quote_ownership_scanner(monkeypatch):
    from app.services.planning import numeric_metadata

    def unexpected_scan(_source):
        pytest.fail("Marker-free prose must not enter the Python quote ownership scan")

    monkeypatch.setattr(numeric_metadata, "_ambiguous_paired_quotes", unexpected_scan)
    source = '"Teaching rationale". ' * 1000 + "The actual amount is 999."
    assert numeric_spans({"lesson_content": source}) == {"n1": "The actual amount is 999."}
