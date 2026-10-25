"""Activity requests prevent ambiguous evidence without changing lesson data."""
import copy
from unittest.mock import AsyncMock

import pytest

from app.services.llm.prompt_loader import load_and_render
from app.services.planning import package_builder as builder
from app.services.planning.lesson_package import LessonPackage
from tests.test_staged_package_builder import Factory, components, run


def test_activity_prompt_keeps_source_bound_quantities_and_complete_reasoning():
    prompt = " ".join(load_and_render("lesson_activity_generate.txt", {}).split())
    assert "quantity, signed value and exact declared unit (if any), then terminal punctuation" in prompt
    assert "Explain their meaning." in prompt
    assert "Derive any separate unsigned magnitude explicitly; never silently discard a negative sign" in prompt
    assert "retaining its intermediate reasoning" in prompt
    assert "descriptive field labels, not invented question/step numbers" in prompt
    assert "Preserve task-essential counts and quantities" in prompt
    assert "never change digits to words or omit reasoning to avoid numerical verification" in prompt
    # Source readability must not trade away the assessment or transfer contract.
    assert "explain EVERY required answer from raw facts" in prompt
    assert "name every contributing term, its sign and why it belongs" in prompt
    assert "raw inputs different from EVERY public teaching case" in prompt
    assert "Do not invent word/sentence quotas, phase timers or deadlines" in prompt


@pytest.mark.asyncio
@pytest.mark.parametrize("numeric", [False, True], ids=["qualitative", "numeric"])
async def test_first_activity_requests_use_source_style_without_new_calls_or_rewriting(numeric, monkeypatch):
    usage = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", usage)
    seed, activities = components(numeric=numeric)
    original = copy.deepcopy(activities)
    factory = Factory({"seed": [seed], **{key: [value] for key, value in activities.items()}})

    package, response, _ = await run(factory)

    assert response.error is None
    assert factory.counts == {"seed": 1, **{key: 1 for key in activities}}
    assert response.effective_parameters["component_requests"] == 3
    assert response.effective_parameters["shared_correction_used"] is False
    assert response.effective_parameters["output_token_budget"] == 14200
    assert [options["max_tokens"] for options in factory.options] == [2200, 4000, 4000]
    assert all(options["timeout"] == 90 for options in factory.options)
    assert usage.await_count == 3
    activity_requests = [request for key, request, _ in factory.requests if key != "seed"]
    assert len(activity_requests) == 2
    for request in activity_requests:
        assert request["system_prompt"] == load_and_render("lesson_activity_generate.txt", {})
        assert "Explain their meaning." in request["system_prompt"]
    # Prompt guidance never silently changes accepted task content or its keys.
    expected = LessonPackage.model_validate({"teaching_cases": seed["teaching_cases"],
        "workbook": {"title": seed["workbook_title"], "activities": list(original.values())}})
    assert package == expected
    assert activities == original
