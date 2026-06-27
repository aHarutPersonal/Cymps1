"""Tests for PRD-aligned content depth thresholds."""

from app.services.content_resources import MIN_BOOK_MODULE_WORDS
from app.tasks.plans import MIN_PLAN_DETAIL_LESSON_WORDS, MIN_PLAN_DETAIL_MATERIAL_WORDS


def test_content_quality_thresholds_match_prd_minimums():
    assert MIN_BOOK_MODULE_WORDS == 2500
    # Aligned with the tightened plan_item_details.txt ceilings (lessons 250-550,
    # materials 400-600) after the prompt review reduced word maxima to avoid
    # truncation and padded filler.
    assert MIN_PLAN_DETAIL_LESSON_WORDS == 250
    assert MIN_PLAN_DETAIL_MATERIAL_WORDS == 350
