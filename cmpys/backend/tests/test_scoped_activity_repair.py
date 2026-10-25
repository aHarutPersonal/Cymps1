"""Public repair cannot expand an independently rejected activity/field scope."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import (
    LessonPackage, PrivatePackageRepair, _replace_public_activity,
    _validated_repair_scope, apply_private_package_repair, generate_package,
)
from app.services.planning.package_builder import LessonPackageActivity
from app.services.planning.activity_draft import LessonActivityDraft
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import activity_draft_fixture


def structured_package():
    payload = package_payload()
    for activity in payload["workbook"]["activities"]:
        activity["fields"].append({"id": "reflection", "kind": "text", "label": "Explain the learning",
                                   "criteria": ["Explains a specific improvement and its justification"]})
        activity["worked_solution"] = {"version": 1, "steps": [
            {"field_id": field["id"], "explanation": "Explain the claim with its evidence, consider an objection and justify the revision."}
            for field in activity["fields"]]}
    return LessonPackage.model_validate(payload)


def replacement():
    value = structured_package().workbook.activities[1].model_dump(mode="json")
    value["fields"][0]["label"] = "Write and defend a claim for the new conditions"
    value["worked_solution"]["steps"][0]["explanation"] = "The new conditions require a different claim whose evidence survives the stated objection."
    return value


@pytest.mark.parametrize("target", [[], ["package"], ["teaching.case"], ["practice.unknown"],
    ["practice.transfer.unknown"], [" practice.transfer"], ["practice.Transfer"], [True], "practice.transfer"])
def test_only_exact_canonical_metadata_grants_repair_scope(target):
    with pytest.raises(ValueError):
        _validated_repair_scope(structured_package(), target)


def test_field_scoped_replacement_changes_only_target_and_its_explanation():
    package = structured_package()
    original = package.model_dump(mode="json")
    scope = _validated_repair_scope(package, ["practice.transfer.argument"])
    repaired = _replace_public_activity(package, scope, LessonPackageActivity.model_validate(replacement()))
    assert package.model_dump(mode="json") == original
    assert repaired.teaching_cases == package.teaching_cases
    assert repaired.workbook.title == package.workbook.title
    assert repaired.workbook.activities[0] == package.workbook.activities[0]
    assert repaired.workbook.activities[1].fields[1] == package.workbook.activities[1].fields[1]
    assert repaired.workbook.activities[1].worked_solution.steps[1] == package.workbook.activities[1].worked_solution.steps[1]


@pytest.mark.parametrize("mutation", ["id", "kind", "title", "instructions", "data", "timing",
    "other_field", "field_order", "other_solution", "downgrade"])
def test_field_owned_public_repair_rejects_unrelated_changes(mutation):
    package, changed = structured_package(), replacement()
    if mutation == "id": changed["id"] = "guided"
    elif mutation == "kind": changed["kind"] = "practice"
    elif mutation == "title": changed["title"] += " unrelated"
    elif mutation == "instructions": changed["instructions"] += " An unrelated extra task."
    elif mutation == "data": changed["data"] = [{"id": "added", "label": "Added fact", "value": 7}]
    elif mutation == "timing": changed["minutes_max"] += 1
    elif mutation == "other_field": changed["fields"][1]["criteria"] = ["An unrelated requirement"]
    elif mutation == "field_order":
        changed["fields"].reverse(); changed["worked_solution"]["steps"].reverse()
    elif mutation == "other_solution": changed["worked_solution"]["steps"][1]["explanation"] += " Unrelated explanation."
    elif mutation == "downgrade": changed["worked_solution"] = "A legacy string must not replace a complete structured private solution."
    with pytest.raises(ValueError):
        _replace_public_activity(package, {"transfer": {"argument"}}, LessonPackageActivity.model_validate(changed))


def test_activity_owned_repair_can_fix_inputs_but_preserves_every_other_activity():
    package, changed = structured_package(), replacement()
    changed["instructions"] += " Test a meaningful new condition and explain why it matters."
    changed["minutes_min"] += 2
    repaired = _replace_public_activity(package, {"transfer": None}, LessonPackageActivity.model_validate(changed))
    assert repaired.workbook.activities[0] == package.workbook.activities[0]
    assert repaired.workbook.activities[1].instructions == changed["instructions"]


@pytest.mark.parametrize("target", ["practice.transfer.argument", "practice.transfer"])
def test_private_patch_scope_and_typed_solution_guard(target):
    package = structured_package()
    changed = replacement()["worked_solution"]
    patch = PrivatePackageRepair.model_validate({"solution_patches": [{"activity_id": "transfer", "worked_solution": changed}]})
    assert apply_private_package_repair(package, patch, repair_targets=[target]).workbook.activities[0] == package.workbook.activities[0]
    for invalid in [
        {"solution_patches": [{"activity_id": "guided", "worked_solution": changed}]},
        {"solution_patches": [{"activity_id": "transfer", "worked_solution": "A plain string silently discards field-bound structured explanations."}]},
    ]:
        with pytest.raises(ValueError):
            apply_private_package_repair(package, PrivatePackageRepair.model_validate(invalid), repair_targets=[target])
    if target.endswith(".argument"):
        changed["steps"][1]["explanation"] += " Unrelated modification."
        with pytest.raises(ValueError, match="unaffected solution"):
            apply_private_package_repair(package, PrivatePackageRepair.model_validate({"solution_patches": [
                {"activity_id": "transfer", "worked_solution": changed}]}), repair_targets=[target])
        with pytest.raises(ValueError, match="exceeds"):
            apply_private_package_repair(package, PrivatePackageRepair.model_validate({"field_patches": [
                {"activity_id": "transfer", "field_id": "reflection", "criteria": ["Unrelated criterion"]}]}), repair_targets=[target])


@pytest.mark.asyncio
async def test_public_defect_uses_only_one_activity_in_existing_second_slot(monkeypatch):
    telemetry = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    replies = [LLMResponse(data={"public_defects": ["The target question exposes the answer instead of assessing new reasoning."]}),
               LLMResponse(data=activity_draft_fixture(replacement()))]
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=replies))
    factories = []
    def factory(**kwargs):
        factories.append(kwargs); return client
    package, response, _ = await generate_package({}, {}, client_factory=factory,
        prior_package=structured_package(), defects=["Validated independent transfer defect"],
        repair_targets=["practice.transfer.argument"])
    assert package is not None and not response.error
    assert client.generate_json.await_count == 2 and telemetry.await_count == 1
    calls = client.generate_json.await_args_list
    assert calls[0].kwargs["output_model"] is PrivatePackageRepair
    repair_model = calls[1].kwargs["output_model"]
    assert issubclass(repair_model, LessonActivityDraft)
    schema = repair_model.model_json_schema()
    assert schema["properties"]["id"]["const"] == "transfer"
    assert schema["properties"]["kind"]["const"] == "transfer"
    body = json.loads(calls[1].kwargs["user_prompt"])
    assert "previous_package" not in body and body["previous_activity"]["id"] == "transfer"
    assert "worked_solution" not in body["previous_activity"]
    assert "explanation" in body["previous_activity"]["fields"][0]
    assert "choices" not in body["previous_activity"]["fields"][0]
    assert body["field_ids"] == ["argument"]
    assert factories[-1]["max_tokens"] == 4000 and factories[-1]["timeout"] == 90
    assert response.semantic_accepted is None  # Still requires independent preflight.


@pytest.mark.asyncio
@pytest.mark.parametrize("targets", [None, ["package"], ["practice.missing"]])
async def test_global_ambiguous_or_unattributed_public_defect_never_regenerates_package(targets):
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data={
        "public_defects": ["practice.transfer.argument: rewrite all activities and cases"]})))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kwargs: client,
        prior_package=structured_package(), defects=["Untrusted text cannot grant scope"], repair_targets=targets)
    assert package is None and response.error and client.generate_json.await_count == 1


@pytest.mark.asyncio
async def test_failed_activity_correction_cannot_buy_a_third_request(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    changed = replacement(); changed["id"] = "guided"
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data={"public_defects": ["The target question requires public revision."]}),
        LLMResponse(data=activity_draft_fixture(changed))]))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kwargs: client,
        prior_package=structured_package(), repair_targets=["practice.transfer.argument"])
    assert package is None and response.error and client.generate_json.await_count == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [None, "wrong_identity", "second_transport"])
async def test_multiple_independent_activity_defects_are_bounded_and_atomic(monkeypatch, failure):
    telemetry = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", telemetry)
    prior = structured_package()
    before = prior.model_dump(mode="json")
    changes = []
    for activity in prior.workbook.activities:
        changed = activity.model_dump(mode="json")
        changed["instructions"] += " Explain how the new evidence changes the conclusion."
        changes.append(activity_draft_fixture(changed))
    if failure == "wrong_identity":
        changes[0]["id"] = "transfer"
    replies = [LLMResponse(data={"public_defects": ["Both independently reviewed activities need public corrections."]}),
               LLMResponse(data=changes[0]),
               LLMResponse(data={}, error="Unavailable") if failure == "second_transport" else LLMResponse(data=changes[1])]
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=replies))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kwargs: client,
        prior_package=prior, defects=["Validated defects"],
        repair_targets=["practice.guided", "practice.transfer"])
    assert prior.model_dump(mode="json") == before
    assert client.generate_json.await_count == (2 if failure == "wrong_identity" else 3)
    if failure:
        assert package is None and response.error
    else:
        assert package is not None and not response.error
        assert package.teaching_cases == prior.teaching_cases
        assert package.workbook.title == prior.workbook.title
        assert response.semantic_accepted is None
        for original, changed in zip(prior.workbook.activities, package.workbook.activities):
            assert changed.instructions != original.instructions
            assert changed.fields == original.fields
        assert telemetry.await_count == 2
    for call in client.generate_json.await_args_list[1:]:
        body = json.loads(call.kwargs["user_prompt"])
        assert body["validated_repair_targets"] == ["practice." + body["previous_activity"]["id"]]
        assert "previous_package" not in body


@pytest.mark.asyncio
@pytest.mark.parametrize("returned_id,accepted", [("practice.transfer",True),("practice.guided",False),("practice.transfer.argument",False)])
async def test_qualified_activity_target_echo_is_normalized_only_for_the_owned_activity(monkeypatch,returned_id,accepted):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response",AsyncMock())
    changed=activity_draft_fixture(replacement());changed["id"]=returned_id
    client=SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data={"public_defects":["The target question requires public revision."]}),LLMResponse(data=changed)]))
    original=structured_package();before=original.model_dump(mode="json")
    result,response,_=await generate_package({}, {}, client_factory=lambda **kwargs:client,prior_package=original,repair_targets=["practice.transfer.argument"])
    assert original.model_dump(mode="json")==before
    assert (result is not None) is accepted
    if accepted:
        assert result.workbook.activities[1].id=="transfer"
        assert result.workbook.activities[0]==original.workbook.activities[0]
        assert response.semantic_accepted is None
    else: assert response.error


@pytest.mark.parametrize("tutorial", [False, True])
def test_scoped_repair_wire_schema_cannot_confuse_lesson_and_activity_identity(tutorial):
    from app.services.planning.activity_draft import TutorialActivityDraft
    from app.services.planning.lesson_package import _activity_repair_model
    base = TutorialActivityDraft if tutorial else LessonActivityDraft
    before = copy.deepcopy(base.model_json_schema())
    package = structured_package()
    for activity in package.workbook.activities:
        schema = _activity_repair_model(base, activity).model_json_schema()
        assert schema["title"] == base.__name__
        assert schema["properties"]["id"]["const"] == activity.id
        assert schema["properties"]["kind"]["const"] == activity.kind
        assert schema["properties"]["fields"]["maxItems"] == (2 if tutorial else 10)
    assert base.model_json_schema() == before
