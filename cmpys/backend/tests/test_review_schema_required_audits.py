"""Audits the server requires are required in the review schema (Sonnet 5.5 pilot, 2026-11-06).

A model that follows a structured-output schema literally omitted the defaulted
public_sections list on every review and its correction, so the server rejected
an otherwise complete review as "public-section audit incomplete".
"""
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning import lesson_review as review
from app.services.planning.lesson_review import PackagedLessonReview, scoped_review_model
from tests.test_public_section_review import _conflict


def test_required_items_are_required_with_their_exact_count():
    schema = scoped_review_model(PackagedLessonReview, {}, required_items={
        "public_sections": 3, "public_check_options": 4}).model_json_schema()
    assert {"public_sections", "public_check_options"} <= set(schema["required"])
    assert (schema["properties"]["public_sections"]["minItems"], schema["properties"]["public_sections"]["maxItems"]) == (3, 3)
    assert schema["properties"]["public_check_options"]["minItems"] == 4


def test_lists_with_nothing_to_audit_stay_optional():
    schema = scoped_review_model(PackagedLessonReview, {}, required_items={
        "public_sections": 0, "public_check_options": 0}).model_json_schema()
    assert "public_sections" not in schema.get("required", [])
    assert "minItems" not in schema["properties"]["public_sections"]


@pytest.mark.asyncio
async def test_a_tutorial_review_requires_one_audit_per_public_section_and_option(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    captured = _conflict()
    lesson, context = captured["lesson"], captured["context"]
    seen = {}

    async def generate_json(**kwargs):
        seen["schema"] = kwargs["output_model"].model_json_schema()
        return LLMResponse(data={}, error="offline stop")

    await review._review_lesson_full(lesson, context=context,
                                     client_factory=lambda **kwargs: SimpleNamespace(model="x", generate_json=generate_json))
    sections = review.public_section_inventory(lesson)
    options = sum(len(check["options"]) for check in review.public_check_inventory(lesson))
    assert sections and "public_sections" in seen["schema"]["required"]
    assert seen["schema"]["properties"]["public_sections"]["minItems"] == len(sections)
    if options:
        assert seen["schema"]["properties"]["public_check_options"]["minItems"] == options
