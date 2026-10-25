"""Initial package requests prevent the recorded JSON envelope mistakes."""
import copy
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.prompt_loader import load_and_render
from app.services.planning.lesson_package import LessonPackage, generate_package
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import structured_package_fixture


def test_initial_structure_guidance_matches_the_actual_wire_schema():
    prompt = load_and_render("lesson_package_generate.txt", {})
    schema = LessonPackage.model_json_schema()
    assert set(schema["properties"]) == {"teaching_cases", "workbook"}
    assert set(schema["$defs"]["Workbook"]["properties"]) == {"title", "activities"}
    assert {"hint", "worked_solution", "minutes_min", "minutes_max"} <= set(
        schema["$defs"]["Activity"]["properties"])
    compact = " ".join(prompt.split())
    assert "root has exactly teaching_cases and workbook" in compact
    assert "workbook object has exactly title and activities" in compact
    assert "hint, worked_solution, minutes_min and minutes_max INSIDE their activity" in compact
    assert "Write workbook.title once" in compact
    assert "Every object must have unique keys" in compact
    assert "finite JSON numbers" in compact
    assert "never NaN, Infinity, -Infinity or quoted numbers" in compact
    assert "Formulas remain expression strings" in compact


@pytest.mark.asyncio
async def test_first_generation_request_has_envelope_guards_without_needing_a_retry():
    payload = structured_package_fixture(package_payload())
    client = SimpleNamespace(model="offline-fake", generate_json=AsyncMock(
        return_value=LLMResponse(data=copy.deepcopy(payload))))
    package, response, returned_client = await generate_package(
        {"id": "step_1", "title": "Practice the skill"}, {"goal": "Learn the skill"},
        client_factory=lambda **kwargs: client,
    )
    client.generate_json.assert_awaited_once()
    request = client.generate_json.call_args.kwargs
    assert request["output_model"] is LessonPackage
    assert request["system_prompt"] == load_and_render("lesson_package_generate.txt", {})
    assert "JSON structure:" in request["system_prompt"]
    assert "Every object must have unique keys" in request["system_prompt"]
    assert "finite JSON numbers" in request["system_prompt"]
    assert package == LessonPackage.model_validate(payload)
    assert response.error is None and returned_client is client
    # Envelope guidance does not replace the substantive assessment contract.
    compact = " ".join(request["system_prompt"].split())
    assert "ending in independent transfer" in compact
    assert "Private worked solutions must explain every required answer from raw facts" in compact
    assert "Do not inflate labels to meet a requested time allocation" in compact
    assert "cannot see private solutions" in compact
