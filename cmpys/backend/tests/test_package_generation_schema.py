"""The provider must see semantic required keys before writing a package."""
import copy
import json

import pytest
from pydantic import ValidationError

from app.core.config import settings
from app.services.llm.zai import ZaiLLMClient
from app.services.planning.lesson_package import LessonPackage, _generation_package_schema
from app.services.practice.contracts import AnswerField, Workbook
from tests.lesson_package_fixtures import package_payload
from tests.test_openlux import chunk, transport


def branches():
    schema = LessonPackage.model_json_schema()["$defs"]["AnswerField"]
    return {branch["properties"]["kind"]["const"]: branch for branch in schema["oneOf"]}


def test_wire_number_requires_a_nonempty_expression_and_own_activity_facts():
    number = branches()["number"]
    assert "expression" in number["required"]
    assert number["properties"]["expression"] == {"type": "string", "minLength": 1}
    activity = LessonPackage.model_json_schema()["$defs"]["Activity"]
    assert "data" in activity["required"]
    assert "default" not in activity["properties"]["data"]
    conditional = activity["allOf"][0]
    assert conditional["if"]["properties"]["fields"]["contains"] == {
        "properties": {"kind": {"const": "number"}}, "required": ["kind"],
    }
    assert conditional["then"]["properties"]["data"]["minItems"] == 1


def test_wire_choice_and_text_require_their_actual_assessment_keys():
    variants = branches()
    assert set(variants) == {"number", "choice", "text", "multi_choice"}
    assert set(variants["choice"]["required"]) == {"choices", "correct_choice"}
    assert set(variants["multi_choice"]["required"]) == {"choices", "correct_choices"}
    assert variants["multi_choice"]["properties"]["correct_choices"]["minItems"] == 1
    assert variants["choice"]["properties"]["choices"]["minItems"] == 2
    assert variants["choice"]["properties"]["correct_choice"] == {"type": "string", "minLength": 1}
    assert variants["text"]["required"] == ["criteria"]
    assert variants["text"]["properties"]["criteria"]["minItems"] == 1
    assert variants["text"]["properties"]["criteria"]["items"]["pattern"] == r"\S"
    field = LessonPackage.model_json_schema()["$defs"]["AnswerField"]
    assert "kind" in field["required"]  # The oneOf branches are disjoint.
    assert field["additionalProperties"] is False


@pytest.mark.parametrize("data", [None, []])
def test_recorded_truncation_shape_cannot_validate_numeric_activities_without_data(data):
    # The captured first response emitted a complete activity with four numeric
    # fields and one choice, but omitted its data. Reproduce that structure
    # without bringing the backend's private synthetic draft into this fixture.
    payload = package_payload()
    activity = payload["workbook"]["activities"][0]
    activity["fields"] = [{
        "id": name, "label": name.replace("_", " "), "kind": "number", "expression": expression,
    } for name, expression in (
        ("revenue", "current_sales"), ("profit", "current_sales - current_costs"),
        ("cash_flow", "cash_receipts - cash_payments"), ("gap", "current_sales - cash_receipts"),
    )] + [{"id": "classification", "label": "Which period?", "kind": "choice",
           "choices": [{"id": "current", "label": "Current"}, {"id": "prior", "label": "Prior"}],
           "correct_choice": "current"}]
    if data is None:
        activity.pop("data")
    else:
        activity["data"] = data
    with pytest.raises(ValidationError):
        LessonPackage.model_validate(payload)


@pytest.mark.parametrize("field", [
    {"id": "answer", "label": "Amount", "kind": "number"},
    {"id": "answer", "label": "Amount", "kind": "number", "expression": None},
    {"id": "answer", "label": "Choose", "kind": "choice", "choices": [], "correct_choice": "a"},
    {"id": "answer", "label": "Explain", "kind": "text", "criteria": []},
])
def test_wire_guidance_does_not_replace_existing_assessment_validation(field):
    with pytest.raises(ValidationError):
        AnswerField.model_validate(field)


def test_schema_adapter_preserves_canonical_defaults_constraints_and_model_identity():
    payload = package_payload()
    for activity in payload["workbook"]["activities"]:
        activity.pop("data")  # Existing qualitative persisted packages remain readable.
    assert LessonPackage.model_validate(payload).workbook.activities[0].data == []
    canonical = Workbook.model_json_schema()
    assert "data" not in canonical["$defs"]["Activity"]["required"]
    assert "oneOf" not in AnswerField.model_json_schema()
    wire = LessonPackage.model_json_schema()
    original = copy.deepcopy(wire)
    adapted = _generation_package_schema(wire)
    adapted["$defs"]["Activity"]["required"].append("mutation")
    assert wire == original
    assert wire["title"] == LessonPackage.__name__ == "LessonPackage"
    assert wire["$defs"]["Activity"]["properties"]["fields"]["maxItems"] == 10
    assert wire["$defs"]["Workbook"]["properties"]["activities"]["maxItems"] == 6
    assert LessonPackage.model_json_schema() == original


@pytest.mark.asyncio
async def test_zai_json_object_wire_contains_the_conditional_package_schema(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    client = ZaiLLMClient(model="glm-5.3", api_key="fake-test-key",
                          base_url="https://api.z.ai/api/paas/v4", thinking_level="low")
    _, request = transport(monkeypatch, client, [chunk(json.dumps(package_payload()), "stop")])
    response = await client.generate_json("Package instructions", "Reference context", output_model=LessonPackage)
    assert response.error is None
    assert LessonPackage.model_validate(response.data)
    assert request["response_format"] == {"type": "json_object"}
    schema = json.loads(request["messages"][0]["content"].rsplit("\n", 1)[-1])
    assert schema == LessonPackage.model_json_schema()
    assert "oneOf" in schema["$defs"]["AnswerField"]
    assert "data" in schema["$defs"]["Activity"]["required"]
