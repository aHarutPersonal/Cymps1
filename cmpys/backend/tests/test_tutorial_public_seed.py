"""A tutorial writer must receive a distinct approved public example."""
from unittest.mock import AsyncMock
import pytest
from app.services.planning import package_builder as builder
from tests.test_staged_package_builder import components, snapshot, Factory


@pytest.mark.asyncio
async def test_empty_tutorial_seed_uses_only_one_bounded_seed_correction(monkeypatch):
    monkeypatch.setattr(builder, "record_llm_response", AsyncMock())
    seed, _ = components()
    factory = Factory({"seed": [seed, seed]})
    saved = AsyncMock()
    package, response, _ = await builder.generate_initial_package(
        {"id": "step_1", "lesson_format": "tutorial_v1"}, {},
        client_factory=factory, on_parts=saved)
    assert package is None and response.error
    assert factory.counts == {"seed": 2}
    saved.assert_not_awaited()
    assert "public teaching case" in str(factory.requests[-1][2]["correction"])


@pytest.mark.asyncio
async def test_cached_empty_tutorial_seed_stops_before_paid_calls():
    seed, _ = components()
    factory = Factory({})
    package, response, _ = await builder.generate_initial_package(
        {"id": "step_1", "lesson_format": "tutorial_v1"}, {},
        client_factory=factory, existing_parts=snapshot(seed))
    assert package is None and response.error == "Saved package components failed validation"
    assert not factory.requests


def test_public_qualitative_case_is_valid_and_legacy_empty_seed_stays_readable():
    raw, _ = components()
    empty = builder.LessonPackageSeed.model_validate(raw)
    assert builder.validate_tutorial_seed(empty, None) == empty
    raw["teaching_cases"] = [{"id": "public_notice", "assumptions":
        "Original fictional notice: Please return library books by Friday. The revision names the action and deadline so a reader can act.",
        "data": [], "results": []}]
    seed = builder.LessonPackageSeed.model_validate(raw)
    assert builder.validate_tutorial_seed(seed, "tutorial_v1") == seed
