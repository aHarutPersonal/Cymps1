"""Fresh authoring requires typed solutions; old approved strings remain readable."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.prompt_loader import load_and_render
from app.services.planning.lesson_package import LessonPackage, PrivatePackageRepair, generate_package, parse_package_response
from app.services.planning.package_builder import LessonPackageActivity
from app.services.practice.contracts import Activity, SolutionDocument
from app.services.practice.solution_compiler import compile_worked_solution, render_worked_solution
from tests.lesson_package_fixtures import package_payload
from tests.test_scoped_activity_repair import structured_package
from tests.section_client_fixture import activity_draft_fixture


@pytest.mark.parametrize("name", ["lesson_activity_generate.txt", "lesson_package_generate.txt"])
def test_solution_prompt_matches_root_equation_renderer_and_retains_authored_evidence(name):
    prompt = " ".join(load_and_render(name, {}, strict=False).split())
    assert "one complete substituted equation and its result for each numeric field" in prompt
    assert "It does not render separate intermediate calculations." in prompt
    assert "retyping those computed equations/results" in prompt or "Do not retype those computed equations/results" in prompt
    assert "Only for an additional task-essential numerical claim not already rendered" in prompt
    assert "Such claims still require independent evidence." in prompt
    assert "equations and intermediate arithmetic" not in prompt
    assert "Give each result/comparison a separate sentence" not in prompt
    assert "Keep each numerical result or comparison in its own sentence" not in prompt

    source = structured_package().workbook.activities[0].model_dump(mode="json")
    source["data"] = [{"id": "revenue", "label": "Revenue", "value": 100},
                      {"id": "cost", "label": "Cost", "value": 20},
                      {"id": "rate", "label": "Rate", "value": 0.3}]
    source["fields"] = [{"id": "share", "label": "Calculate the share", "kind": "number",
                         "expression": "(revenue - cost) * rate"}]
    source["worked_solution"] = {"version": 1, "steps": [{"field_id": "share",
        "explanation": "Subtract the cost before applying the rate because the share depends on the remaining revenue."}]}
    compiled = compile_worked_solution(source)
    assert len(compiled.records) == 1
    assert compiled.records[0].node_path == ()
    assert compiled.records[0].text == "((100 - 20) * 0.3) = 24"
    assert compiled.text.endswith(source["worked_solution"]["steps"][0]["explanation"])


def test_transfer_prompt_uses_activity_facts_without_overriding_supplied_requirements():
    prompt = " ".join(load_and_render("lesson_activity_generate.txt", {}, strict=False).split())
    assert "Use this activity's declared raw facts and preserve task-required supplied facts" in prompt
    assert "raw inputs different from EVERY public teaching case" in prompt
    assert "Use the supplied public case facts" not in prompt


def test_legacy_strings_are_read_unchanged_but_cannot_be_new_components():
    legacy = package_payload()
    package = parse_package_response(copy.deepcopy(legacy))
    for old, activity in zip(legacy["workbook"]["activities"], package.workbook.activities):
        assert isinstance(activity.worked_solution, str)
        assert render_worked_solution(activity) == old["worked_solution"]
        with pytest.raises(ValueError):
            LessonPackageActivity.model_validate(old)


def test_generation_and_patch_wire_schemas_require_document_without_changing_storage_union():
    schema = LessonPackage.model_json_schema()
    assert schema["$defs"]["Activity"]["properties"]["worked_solution"] == {"$ref": "#/$defs/SolutionDocument"}
    assert PrivatePackageRepair.model_json_schema()["$defs"]["PrivateSolutionPatch"]["properties"]["worked_solution"] == {"$ref": "#/$defs/SolutionDocument"}
    assert "anyOf" in Activity.model_json_schema()["properties"]["worked_solution"]


def test_review_context_binds_rendered_text_to_exact_private_document():
    package = structured_package()
    projected = package.review_context()["private_workbook"]["activities"]
    for activity, value in zip(package.workbook.activities, projected):
        assert value["worked_solution_document"] == activity.worked_solution.model_dump(mode="json")
        assert value["worked_solution"] == render_worked_solution(activity)
    assert all("worked_solution" not in activity and "worked_solution_document" not in activity
               for activity in package.writer_context()["practice"]["activities"])


@pytest.mark.parametrize("mutation", ["missing", "order", "duplicate", "version", "short"])
def test_new_solution_document_requires_exact_complete_field_mapping(mutation):
    value = structured_package().workbook.activities[0].model_dump(mode="json")
    doc = value["worked_solution"]
    if mutation == "missing": doc["steps"].pop()
    elif mutation == "order": doc["steps"].reverse()
    elif mutation == "duplicate": doc["steps"][1]["field_id"] = doc["steps"][0]["field_id"]
    elif mutation == "version": doc["version"] = True
    elif mutation == "short": doc["steps"][0]["explanation"] = "Too short"
    with pytest.raises(ValueError):
        LessonPackageActivity.model_validate(value)


def test_unrenderable_component_is_rejected_before_checkpoint(monkeypatch):
    source = structured_package().workbook.activities[0].model_dump(mode="json")
    def invalid(_):
        raise ValueError("Rendered solution exceeds the supported bound")
    monkeypatch.setattr("app.services.practice.solution_compiler.compile_worked_solution", invalid)
    with pytest.raises(ValueError, match="supported bound"):
        LessonPackageActivity.model_validate(source)


@pytest.mark.asyncio
async def test_whole_package_generation_never_accepts_new_legacy_solution_response(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=package_payload()), LLMResponse(data=package_payload())]))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kwargs: client)
    assert package is None and response.error and client.generate_json.await_count == 2


@pytest.mark.asyncio
async def test_complete_structured_package_passes_generation_without_approval():
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=structured_package().model_dump(mode="json"))))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kwargs: client)
    assert package is not None and not response.error
    assert all(isinstance(activity.worked_solution, SolutionDocument) for activity in package.workbook.activities)
    assert response.semantic_accepted is None


@pytest.mark.asyncio
@pytest.mark.parametrize("legacy", [False, True])
async def test_real_builder_never_checkpoints_plain_string_generated_solutions(monkeypatch, legacy):
    from app.services.planning import package_builder as builder
    telemetry = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", telemetry)
    source = package_payload() if legacy else structured_package().model_dump(mode="json")
    requests, checkpoints = [], []

    class Client:
        model = "offline-typed-activity"
        async def generate_json(self, **request):
            requests.append(request)
            if request["output_model"] is builder.LessonPackageSeed:
                value = {"workbook_title": source["workbook"]["title"], "teaching_cases": [],
                         "activity_briefs": [{"id": activity["id"], "kind": activity["kind"],
                             "scope": activity["instructions"]} for activity in source["workbook"]["activities"]]}
            else:
                activity_id = json.loads(request["user_prompt"])["activity_brief"]["id"]
                value = next(activity for activity in source["workbook"]["activities"] if activity["id"] == activity_id)
                if not legacy:
                    value = activity_draft_fixture(value)
            return LLMResponse(data=value, finish_reason="stop", total_tokens=12)

    async def save(parts):
        checkpoints.append(copy.deepcopy(parts))

    package, response, _ = await builder.generate_initial_package({}, {},
        client_factory=lambda **kwargs: Client(), on_parts=save)
    assert telemetry.await_count == len(requests) <= 4
    if legacy:
        assert package is None and response.error
        assert checkpoints and all(not part["activities"] for part in checkpoints)
    else:
        assert package is not None and not response.error and len(requests) == 3
        assert len(checkpoints[-1]["activities"]) == 2
        assert all(isinstance(activity["worked_solution"], dict) for activity in checkpoints[-1]["activities"].values())
