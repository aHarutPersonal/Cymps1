"""Tests for PRD-aligned content depth thresholds."""

from app.api.v1.plans import _lesson_details_meet_quality
from app.services.content_resources import MIN_BOOK_MODULE_WORDS
from app.services.content_quality import evaluate_book_module
from app.tasks.plans import (
    MIN_PLAN_DETAIL_LESSON_WORDS,
    MIN_PLAN_DETAIL_MATERIAL_WORDS,
    normalize_lesson_durations,
)


def test_content_quality_thresholds_match_prd_minimums():
    assert MIN_BOOK_MODULE_WORDS == 3200
    assert MIN_PLAN_DETAIL_LESSON_WORDS == 1200
    assert MIN_PLAN_DETAIL_MATERIAL_WORDS == 350


def test_lesson_duration_is_derived_from_reading_and_practice():
    details = {
        "steps": [
            {
                "lesson_content": "word " * 1600,
                "estimate_minutes": 45,
                "practice_minutes": 35,
            }
        ]
    }

    normalized = normalize_lesson_durations(details)
    step = normalized["steps"][0]

    assert step["reading_minutes"] == 8
    assert step["practice_minutes"] == 35
    assert step["estimate_minutes"] == 43


def test_legacy_short_lesson_is_upgraded_when_opened():
    assert not _lesson_details_meet_quality(
        {"steps": [{"lesson_content": "word " * 500}]}
    )
    assert _lesson_details_meet_quality(
        {"steps": [{"lesson_content": "word " * 1200}]}
    )


def test_book_quality_gate_requires_structure_not_only_length():
    report = evaluate_book_module(
        {
            "content_markdown": "word " * 3000,
            "sections": [],
            "ideas": [],
        }
    )

    assert report.passed is False
    assert any("sections" in issue for issue in report.issues)
    assert any("Practice This" in issue for issue in report.issues)


def test_book_grounding_gate_rejects_attributed_quote_missing_from_source():
    invented = (
        'The author writes, "This entirely invented sentence contains enough words '
        'to qualify as a direct attributed quotation in the generated lesson."'
    )
    report = evaluate_book_module(
        {
            "content_markdown": invented + "\n\n" + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context="source material " * 500,
    )

    assert report.metrics["source_grounding_eligible"] == 1
    assert report.metrics["unmatched_attributed_quote_count"] == 1
    assert any("quotation" in issue for issue in report.issues)


def test_book_grounding_gate_accepts_quote_present_in_source():
    quotation = (
        "This sentence appears exactly in the supplied source and therefore may be "
        "attributed safely in the generated lesson."
    )
    report = evaluate_book_module(
        {
            "content_markdown": f'The author writes, "{quotation}"\n\n' + "word " * 2800,
            "sections": [],
            "ideas": [],
        },
        source_context=("source material " * 500) + quotation,
    )

    assert report.metrics["unmatched_attributed_quote_count"] == 0
