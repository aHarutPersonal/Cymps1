"""Tests for PRD-aligned content depth thresholds."""

from app.services.content_resources import MIN_BOOK_MODULE_WORDS
from app.tasks.plans import MIN_PLAN_DETAIL_LESSON_WORDS, MIN_PLAN_DETAIL_MATERIAL_WORDS


def test_content_quality_thresholds_match_prd_minimums():
    assert MIN_BOOK_MODULE_WORDS == 2500
    assert MIN_PLAN_DETAIL_LESSON_WORDS == 500
    assert MIN_PLAN_DETAIL_MATERIAL_WORDS == 600
