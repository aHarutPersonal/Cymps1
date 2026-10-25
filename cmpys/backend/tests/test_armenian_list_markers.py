"""Armenian list punctuation must not create or hide numerical claims."""
import pytest

from app.services.planning.numeric_metadata import mask_structural_ordinals, structural_ordinal_intervals
from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans


@pytest.mark.parametrize("separator", ["\n", "։ ", "․ "])
def test_complete_armenian_sequence_masks_only_exact_markers(separator):
    source = "**Հրահանգներ։**\n" + separator.join([
        "1․ Կարդացեք օրինակը", "2․ Բացատրեք ընտրությունը", "3․ Վերանայեք պատասխանը", "4․ Ստուգեք աշխատանքը",
    ])
    ranges = structural_ordinal_intervals(source)
    assert [source[start:end] for start, end in ranges] == ["1․", "2․", "3․", "4․"]
    masked = mask_structural_ordinals(source, source=source, start=0)
    changed = {position for start, end in ranges for position in range(start, end)}
    assert len(masked) == len(source)
    assert all(value == (" " if index in changed else source[index]) for index, value in enumerate(masked))
    assert numeric_spans({"lesson_content": source}) == {}


@pytest.mark.parametrize("source", [
    "1․ Կարդացեք օրինակը։",
    "1․ Read it։ 3․ Revise it։",
    "1․ Read it։ 2) Revise it։",
    "(1) Read it։ 2․ Revise it։",
    "0․1․ Read it։ 0․2․ Revise it։",
    "0.1․ Read it։ 0.2․ Revise it։",
    "1․20 cm, 2․30 cm",
    "-1․ Read it։ +2․ Revise it։",
    "1․ cm, 2․ cm",
    "1․ million dollars, 2․ million dollars",
    "1․ x + 10, 2․ y + 20",
    "«1․ Read it։ 2․ Revise it։»",
    "```\n1․ Read it\n2․ Revise it\n```",
    "Use 1․ Read it and 2․ Revise it.",
])
def test_ambiguous_sequences_are_not_exempted(source):
    assert structural_ordinal_intervals(source) == []
    assert mask_structural_ordinals(source, source=source, start=0) == source


def test_mixed_facts_and_markers_still_require_signed_case_binding():
    source = "1․ Opening amount is 10։ 2․ Following amount is -20։ 3․ Explain the difference։"
    lesson = {"lesson_content": source}
    context = {"teaching_cases": [{"id": "case", "data": [
        {"id": "opening", "label": "Opening amount", "value": 10},
        {"id": "following", "label": "Following amount", "value": -20},
    ]}]}
    spans = numeric_spans(lesson, context)
    assert len(spans) == 2
    facts = [dict(claim_id=key, case_id="teaching.case", datum_ids=[datum])
             for key, datum in zip(spans, ["opening", "following"])]
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
                          contains_calculations=False, calculations=[], literal_facts=facts)
    assert grounded_failures(review, lesson, context) == []
    context["teaching_cases"][0]["data"][1]["value"] = 20
    assert grounded_failures(review, lesson, context)


def test_claims_and_custom_units_remain_visible():
    source = "1․ Revenue is 999։ 2․ Explain why 10 + 20 = 99։"
    spans = numeric_spans({"lesson_content": source})
    assert "999" in " ".join(spans.values()) and "10 + 20 = 99" in " ".join(spans.values())
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
                          contains_calculations=False, calculations=[], literal_fact_ids=list(spans))
    assert grounded_failures(review, {"lesson_content": source}, {})
    assert structural_ordinal_intervals("1․ widgets, 2․ widgets", units=["widgets"]) == []
