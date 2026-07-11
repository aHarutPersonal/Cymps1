"""Tests for PRD-aligned content depth thresholds."""

from app.services.content_resources import MIN_BOOK_MODULE_WORDS
from app.services.content_quality import evaluate_book_module
from app.tasks.plans import MIN_PLAN_DETAIL_LESSON_WORDS, MIN_PLAN_DETAIL_MATERIAL_WORDS


def test_content_quality_thresholds_match_prd_minimums():
    assert MIN_BOOK_MODULE_WORDS == 3200
    # Aligned with the tightened plan_item_details.txt ceilings (lessons 250-550,
    # materials 400-600) after the prompt review reduced word maxima to avoid
    # truncation and padded filler.
    assert MIN_PLAN_DETAIL_LESSON_WORDS == 250
    assert MIN_PLAN_DETAIL_MATERIAL_WORDS == 350


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
