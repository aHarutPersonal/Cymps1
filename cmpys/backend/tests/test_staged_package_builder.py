"""Offline contracts for smaller package requests and private resumability."""
import asyncio
import copy
import json
from collections import Counter
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning import package_builder as builder
from app.services.planning.lesson_package import LessonPackage, digest
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import activity_draft_fixture, structured_activity_fixture


def components(count=2, *, numeric=False):
    package = package_payload()
    first, transfer = package["workbook"]["activities"]
    activities = [first]
    for index in range(1, count):
        activity = copy.deepcopy(transfer)
        activity.update(id="transfer" if index == count - 1 else f"practice_{index}",
                        kind="transfer" if index == count - 1 else "practice")
        activities.append(activity)
    cases = []
    if numeric:
        cases = [{"id": "example", "assumptions": "A fictional quantity is doubled with matching units.",
                  "data": [{"id": "base", "label": "Base quantity", "value": 10, "unit": "m"}],
                  "results": [{"id": "double", "label": "Doubled quantity", "expression": "base * 2",
                               "unit": "m", "decimal_places": 1}]}]
        for index, activity in enumerate(activities):
            activity["data"] = [{"id": "amount", "label": "Input quantity", "value": 12 + index, "unit": "m"}]
            activity["fields"] = [{"id": "double", "kind": "number", "label": "Doubled quantity",
                                   "expression": "amount * 2", "unit": "m"}]
    seed = {"workbook_title": package["workbook"]["title"], "teaching_cases": cases,
            "activity_briefs": [
                {"id": activity["id"], "kind": activity["kind"], "scope": activity["instructions"]}
                for activity in activities]}
    return seed, {activity["id"]: structured_activity_fixture(activity) for activity in activities}


def snapshot(seed, activities=None):
    canonical = builder.LessonPackageSeed.model_validate(seed).model_dump(mode="json")
    return builder.validate_package_parts({"version": 2, "seed": canonical,
        "seed_hash": digest(canonical), "activities": activities or {}})


class Factory:
    def __init__(self, responses, *, wrapped=False, started=True):
        self.responses = {key: list(values) for key, values in responses.items()}
        self.options = []
        self.requests = []
        self.counts = Counter()
        self.active = self.max_active = 0
        self.wrapped, self.started = wrapped, started

    def __call__(self, **options):
        factory = self
        self.options.append(options)

        class Client:
            model = "offline-package-model"
            provider_name = "dummy"
            enforces_shared_deadline = factory.wrapped
            request_started = factory.started
            last_attempt = None

            async def generate_json(self, **request):
                data = json.loads(request["user_prompt"])
                key = "seed" if request["output_model"] is builder.LessonPackageSeed else data["activity_brief"]["id"]
                factory.counts[key] += 1
                factory.requests.append((key, request, data))
                self.last_attempt = LLMResponse(data={}, attempt_id=f"{key}-{factory.counts[key]}", provider="dummy")
                factory.active += 1
                factory.max_active = max(factory.max_active, factory.active)
                try:
                    item = factory.responses[key].pop(0)
                    if callable(item):
                        item = await item()
                    if isinstance(item, BaseException):
                        raise item
                    response = item if isinstance(item, LLMResponse) else LLMResponse(
                        data=copy.deepcopy(item), finish_reason="stop", prompt_tokens=5, completion_tokens=8,
                        total_tokens=13, provider="dummy", attempt_id=self.last_attempt.attempt_id)
                    if (request["output_model"].__name__ in {"LessonActivityDraft", "TutorialActivityDraft"}
                            and isinstance(response.data, dict) and "worked_solution" in response.data):
                        response = response.model_copy(deep=True)
                        response.data = activity_draft_fixture(response.data)
                    self.last_attempt = response
                    return response
                finally:
                    factory.active -= 1

        return Client()


@pytest.fixture
def usage(monkeypatch):
    recorder = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", recorder)
    return recorder


async def run(factory, **kwargs):
    return await builder.generate_initial_package({"id": "step_1", "title": "Learn a skill"},
        {"locale": "hy", "goal": "Apply it independently", "target_practice_minutes": 35},
        client_factory=factory, **kwargs)


@pytest.mark.asyncio
async def test_plan_and_two_independent_requests_assemble_canonical_package_and_bill_each_once(usage):
    seed, activities = components()
    factory = Factory({"seed": [seed], **{key: [value] for key, value in activities.items()}})
    snapshots = []

    async def save(value):
        snapshots.append(value)

    package, response, client = await run(factory, on_parts=save)
    expected = package_payload()
    expected["workbook"]["activities"] = list(activities.values())
    assert package == LessonPackage.model_validate(expected)
    assert package.teaching_cases == []
    assert response.error is None and client is None
    assert response.effective_parameters == {
        "synthetic_local_validation": True, "staged_package_assembly": True,
        "planned_components": 3, "component_requests": 3, "requested_output_tokens": 10200,
        "max_component_requests": 4, "output_token_budget": 14200,
        "shared_correction_used": False, "stage_timeout_seconds": 240.0,
        "stage_timeout_basis": "provider_active_union", "usage_records_incomplete": 0,
        "normalized_seed_case_id_count": 0}
    assert [options["max_tokens"] for options in factory.options] == [2200, 4000, 4000]
    assert [options["timeout"] for options in factory.options] == [90, 90, 90]
    assert all(options["thinking_level"] == "low" and not options["allow_fallback"] for options in factory.options)
    assert usage.await_count == 3
    assert all(call.kwargs["response"].total_tokens == 13 for call in usage.await_args_list)
    assert len(snapshots) == 3 and snapshots[0]["activities"] == {}
    assert set(snapshots[-1]["activities"]) == {"guided", "transfer"}


def test_wire_schemas_are_shallow_and_keep_conditional_required_fields():
    seed = builder.LessonPackageSeed.model_json_schema()
    activity = builder.LessonPackageActivity.model_json_schema()
    assert set(seed["properties"]) == {"workbook_title", "teaching_cases", "activity_briefs"}
    assert "title" in activity["properties"]
    assert "data" in activity["required"]
    assert activity["properties"]["data"]["description"]
    assert not {"LessonPackageActivity", "AnswerField", "Activity"} & seed["$defs"].keys()
    assert seed["properties"]["activity_briefs"]["minItems"] == 2
    assert seed["properties"]["activity_briefs"]["maxItems"] == 6
    kinds = {branch["properties"]["kind"]["const"]: branch for branch in activity["$defs"]["AnswerField"]["oneOf"]}
    assert set(kinds["number"]["required"]) == {"id", "label", "kind", "expression"}
    assert set(kinds["text"]["required"]) == {"id", "label", "kind", "criteria"}
    assert set(kinds["choice"]["required"]) == {"id", "label", "kind", "choices", "correct_choice"}
    # The request aid does not mutate the canonical schema or relax validation.
    canonical = LessonPackage.model_json_schema()["$defs"]["AnswerField"]
    assert canonical["oneOf"][2]["required"] == ["criteria"]
    assert set(canonical["required"]) == {"id", "label", "kind"}
    assert "default" not in activity["$defs"]["AnswerField"]["properties"]["expression"]
    assert "title" not in activity["$defs"]["AnswerField"]["properties"]["label"]


@pytest.mark.parametrize("defect", ["one", "seven", "duplicate", "first_transfer", "last_practice", "private_activity"])
def test_seed_plan_requires_complete_ordered_scope_without_private_activity_payload(defect):
    seed, activities = components(6 if defect == "seven" else 2)
    if defect == "one":
        seed["activity_briefs"] = seed["activity_briefs"][:1]
    elif defect == "seven":
        seed["activity_briefs"].insert(1, {**seed["activity_briefs"][0], "id": "extra"})
    elif defect == "duplicate":
        seed["activity_briefs"][-1]["id"] = seed["activity_briefs"][0]["id"]
    elif defect == "first_transfer":
        seed["activity_briefs"][0]["kind"] = "transfer"
    elif defect == "last_practice":
        seed["activity_briefs"][-1]["kind"] = "practice"
    else:
        seed["guided_activity"] = activities["guided"]
    with pytest.raises(ValueError):
        builder.LessonPackageSeed.model_validate(seed)


def test_focused_field_target_does_not_reduce_canonical_assessment_capacity():
    seed, activities = components()
    activity = activities["guided"]
    activity["fields"] = [{**copy.deepcopy(activity["fields"][0]), "id": f"answer_{index}"}
                          for index in range(5)]
    explanation = activity["worked_solution"]["steps"][0]["explanation"]
    activity["worked_solution"]["steps"] = [
        {"field_id": field["id"], "explanation": explanation} for field in activity["fields"]]
    parts = snapshot(seed, activities)
    assert len(parts["activities"]["guided"]["fields"]) == 5
    assert builder.LessonPackageActivity.model_json_schema()["properties"]["fields"]["maxItems"] == 10


def test_initial_seed_prompt_explicitly_requires_complete_case_metadata():
    from app.services.llm.prompt_loader import load_and_render

    schema = builder.LessonPackageSeed.model_json_schema()
    assert set(schema["$defs"]["TeachingCase"]["required"]) == {"id", "assumptions", "data", "results"}
    prompt = load_and_render("lesson_package_seed.txt", {})
    assert "Each teaching case has exactly id, assumptions, data and results." in prompt
    assert "required even when it is the only case" in prompt
    assert "Each result has id, label, expression, unit and decimal_places." in prompt
    assert "every required fact, assessment and reasoning demand" in prompt
    assert "Do not generate activity solutions in the planning request" in prompt
    assert "not a guaranteed visible-text allowance" in " ".join(prompt.split())
    activity_prompt = load_and_render("lesson_activity_generate.txt", {})
    assert "must explain EVERY required answer from raw facts" in activity_prompt
    assert "not a guaranteed visible-text allowance" in activity_prompt
    assert "Target 2-4 meaningful answer fields" in activity_prompt
    assert "not a hard\nlimit" in activity_prompt
    assert "plan another\nactivity for a distinct learning demand" in prompt
    assert "For writing or interpretive goals, set teaching_cases to []" in prompt
    assert "Never invent a numerical teaching" in prompt
    assert "exact expression result" in activity_prompt
    assert "absolute tolerance of 0.01 by default" in activity_prompt
    assert "set this field's tolerance explicitly" in activity_prompt
    assert "EVERY field, including text, requires id, label, kind and explanation" in activity_prompt
    assert '"kind":"text","criteria"' in activity_prompt
    assert "Each brief has exactly id, kind and scope. Include necessary rationale in scope." in prompt
    assert "kind_note" not in prompt
    assert "ONE practice target shared across ALL planned activities" in prompt
    assert "never treat that reference as a required duration or minimum" in " ".join(activity_prompt.split())


@pytest.mark.asyncio
async def test_workload_payload_has_one_shared_target_and_each_activity_only_its_share(usage):
    from app.services.planning.workload_contract import build_workload_contract

    seed, activities = components(3)
    factory = Factory({"seed": [seed], **{key: [value] for key, value in activities.items()}})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    plan = factory.requests[0][2]["workload_plan"]
    ledger = build_workload_contract(list(activities.values()))
    assert plan["reading_minutes_range"] == ledger["reading_minutes_range"]
    assert plan["allowed_total_minutes_range"] == ledger["allowed_total_minutes_range"]
    assert plan["requested_practice_minutes"] == plan["planning_practice_minutes"] == 35
    requests = [request for key, _, request in factory.requests if key != "seed"]
    assert all(request["workload_plan"] == plan for request in requests)
    assert {request["activity_workload"]["position"] for request in requests} == {1, 2, 3}
    assert all(request["activity_workload"]["planned_activity_count"] == 3 for request in requests)
    assert sum(request["activity_workload"]["equal_share_reference_minutes"] for request in requests) == pytest.approx(35)
    assert all("not a minimum or forced estimate" in request["activity_workload"]["reference_rule"] for request in requests)
    assert factory.counts == {"seed": 1, "guided": 1, "practice_1": 1, "transfer": 1}


@pytest.mark.asyncio
async def test_missing_text_label_uses_existing_correction_without_fabricating_questions(usage):
    seed, activities = components()
    missing = copy.deepcopy(activities["transfer"])
    for field in missing["fields"]:
        field.pop("label")
    factory = Factory({"seed": [seed], "guided": [activities["guided"]],
                       "transfer": [missing, activities["transfer"]]})
    saved = []

    async def save(value):
        saved.append(value)

    package, response, _ = await run(factory, on_parts=save)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 2}
    errors = next(data["correction"]["validation_errors"] for key, _, data in factory.requests
                  if key == "transfer" and "correction" in data)
    assert all(error["loc"][:1] == ["fields"] and error["loc"][-1] == "label" for error in errors)
    assert all("label" in field for value in saved for activity in value["activities"].values()
               for field in activity["fields"])
    assert usage.await_count == 4


@pytest.mark.asyncio
async def test_unknown_extra_seed_note_then_missing_labels_fails_with_one_shared_correction(usage):
    seed, activities = components()
    extra = copy.deepcopy(seed)
    extra["activity_briefs"][-1]["unsupported_note"] = "An unknown field still requires a complete correction."
    missing = copy.deepcopy(activities["transfer"])
    for field in missing["fields"]:
        field.pop("label")
    factory = Factory({"seed": [extra, seed], "guided": [activities["guided"]], "transfer": [missing]})
    saved = []

    async def save(value):
        saved.append(value)

    package, response, _ = await run(factory, on_parts=save)
    assert package is None and response.error and response.data == {}
    assert factory.counts == {"seed": 2, "guided": 1, "transfer": 1}
    assert response.effective_parameters["shared_correction_used"] is True
    assert response.effective_parameters["max_component_requests"] == 4
    assert set(saved[-1]["activities"]) == {"guided"}
    assert all("unsupported_note" not in brief for value in saved for brief in value["seed"]["activity_briefs"])
    assert usage.await_count == 4


@pytest.mark.asyncio
async def test_actual_zai_wire_caps_include_reasoning_in_one_bounded_output_limit(monkeypatch, usage):
    from app.core.config import settings
    from tests.test_json_generation_errors import client_for
    from tests.test_openlux import chunk, transport

    monkeypatch.setattr(settings, "llm_admission_limits", {})
    monkeypatch.setattr(settings, "zai_reasoning_token_reserve", 2048)
    seed, activities = components()
    values = [seed, activity_draft_fixture(activities["guided"]), activity_draft_fixture(activities["transfer"])]
    requests = []
    clients = []

    def factory(**options):
        client = client_for("zai")
        client.timeout = options["timeout"]
        client.max_tokens = options["max_tokens"]
        client.thinking_level = options["thinking_level"]
        stream, request = transport(monkeypatch, client, [chunk(json.dumps(values.pop(0)), "stop")])
        requests.append(request)
        clients.append((client, stream))
        return client

    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    assert [request["max_tokens"] for request in requests] == [4248, 6048, 6048]
    assert all(request["reasoning_effort"] == "low" for request in requests)
    assert all(client.timeout == 90 and stream.closed for client, stream in clients)
    assert response.effective_parameters["max_component_requests"] == 4
    assert response.effective_parameters["stage_timeout_seconds"] == 240
    assert response.effective_parameters["stage_timeout_basis"] == "provider_active_union"
    assert usage.await_count == 3


@pytest.mark.asyncio
async def test_absent_initial_case_id_is_assigned_without_rewriting_valid_content(usage):
    seed, activities = components(numeric=True)
    missing_id = copy.deepcopy(seed)
    missing_id["teaching_cases"][0].pop("id")
    factory = Factory({"seed": [missing_id], "guided": [activities["guided"]], "transfer": [activities["transfer"]]})
    saved = []

    async def save(value):
        saved.append(value)

    package, response, _ = await run(factory, on_parts=save)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 1}
    assert all(value["seed"]["teaching_cases"][0]["id"] == "teaching_case_1" for value in saved)
    assert "id" not in missing_id["teaching_cases"][0]
    assert response.effective_parameters["requested_output_tokens"] == 10200
    assert response.effective_parameters["normalized_seed_case_id_count"] == 1
    assert response.effective_parameters["shared_correction_used"] is False
    assert usage.await_count == 3


@pytest.mark.asyncio
async def test_more_output_headroom_does_not_add_a_second_correction_or_accept_truncation(usage):
    seed, activities = components()
    truncated_seed = LLMResponse(data=seed, finish_reason="length")
    truncated_activity = LLMResponse(data=activities["transfer"], finish_reason="length")
    factory = Factory({"seed": [truncated_seed, seed], "guided": [activities["guided"]], "transfer": [truncated_activity]})
    package, response, _ = await run(factory)
    assert package is None and response.error and response.data == {}
    assert factory.counts == {"seed": 2, "guided": 1, "transfer": 1}
    assert response.effective_parameters["shared_correction_used"] is True
    assert response.effective_parameters["component_requests"] == 4
    assert response.effective_parameters["requested_output_tokens"] == 12400
    assert response.effective_parameters["output_token_budget"] == 14200
    assert usage.await_count == 4


@pytest.mark.asyncio
async def test_all_activity_requests_use_only_plan_and_public_teaching_context(usage):
    seed, activities = components()
    for activity in activities.values():
        activity.update(hint="PRIVATE_HINT must stay private")
        for step in activity["worked_solution"]["steps"]:
            step["explanation"] = "PRIVATE_SOLUTION " * 5
        activity["fields"][0]["criteria"] = ["PRIVATE_CRITERION is satisfied"]
    factory = Factory({"seed": [seed], **{key: [value] for key, value in activities.items()}})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    requests = [data for key, _, data in factory.requests if key != "seed"]
    assert {request["activity_brief"]["id"] for request in requests} == {"guided", "transfer"}
    assert "PRIVATE_" not in json.dumps(requests)
    assert all(set(request["public_seed"]) == {
        "workbook_title", "teaching_cases", "activity_briefs"} for request in requests)


@pytest.mark.asyncio
async def test_resuming_never_sends_checkpointed_private_answers_to_another_activity(usage):
    seed, activities = components()
    activities["guided"]["worked_solution"]["steps"][0]["explanation"] = "PRIVATE_CHECKPOINTED_SOLUTION " * 3
    parts = snapshot(seed, {"guided": activities["guided"]})
    factory = Factory({"transfer": [activities["transfer"]]})
    package, response, _ = await run(factory, existing_parts=parts)
    assert package is not None and response.error is None
    assert factory.counts == {"transfer": 1} and usage.await_count == 1
    assert "PRIVATE_CHECKPOINTED" not in json.dumps(factory.requests[0][2])


@pytest.mark.asyncio
async def test_first_practice_and_transfer_start_independently_after_the_plan(usage):
    seed, activities = components()
    entered = set()
    together = asyncio.Event()

    def simultaneous(identifier):
        async def finish():
            entered.add(identifier)
            if len(entered) == 2:
                together.set()
            await asyncio.wait_for(together.wait(), 0.2)
            return activities[identifier]
        return finish

    factory = Factory({"seed": [seed], "guided": [simultaneous("guided")],
                       "transfer": [simultaneous("transfer")]})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    assert factory.max_active == 2 and entered == {"guided", "transfer"}
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 1}


@pytest.mark.asyncio
async def test_invalid_first_practice_is_corrected_without_repeating_transfer(usage):
    seed, activities = components(numeric=True)
    malformed = copy.deepcopy(activities["guided"])
    malformed["data"] = []
    factory = Factory({"seed": [seed], "guided": [malformed, activities["guided"]],
                       "transfer": [activities["transfer"]]})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 1, "guided": 2, "transfer": 1}
    assert response.effective_parameters["requested_output_tokens"] == 14200
    assert response.effective_parameters["output_token_budget"] == 14200
    assert usage.await_count == 4


@pytest.mark.asyncio
@pytest.mark.parametrize("defect", ["nesting", "constant", "missing_raw", "derived_id", "public_copy", "wrong_id", "wrong_kind"])
async def test_only_failed_activity_is_corrected_with_exact_private_source(defect, usage):
    seed, activities = components(numeric=True)
    good = activities["transfer"]
    bad = copy.deepcopy(good)
    bad["worked_solution"] = "PRIVATE_REJECTED_SOURCE " * 3
    if defect == "nesting":
        bad = {"workbook": {"activities": [bad]}}
    elif defect == "constant":
        bad["fields"][0]["expression"] = "2"
    elif defect == "missing_raw":
        bad["data"] = []
    elif defect == "derived_id":
        bad["fields"][0]["expression"] = "double * 2"
    elif defect == "public_copy":
        bad["data"][0]["value"] = 10
    elif defect == "wrong_id":
        bad["id"] = "unassigned"
    else:
        bad["kind"] = "practice"
    factory = Factory({"seed": [seed], "guided": [activities["guided"]], "transfer": [bad, good]})
    saved = []

    async def save(value):
        saved.append(value)

    package, response, _ = await run(factory, on_parts=save)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 2}
    assert "correction" in factory.requests[-1][2]
    correction = factory.requests[-1][2]["correction"]
    expected_draft = bad if "worked_solution" not in bad else activity_draft_fixture(bad)
    assert correction["rejected_component"] == expected_draft
    assert "untrusted reference data" in correction["instruction"]
    assert "PRIVATE_REJECTED_SOURCE" not in json.dumps(saved)
    assert "PRIVATE_REJECTED_SOURCE" not in json.dumps(response.effective_parameters)
    assert len(saved) == 3 and usage.await_count == 4
    assert response.effective_parameters["requested_output_tokens"] == 14200


@pytest.mark.asyncio
async def test_malformed_seed_uses_the_shared_slot_and_never_persists_fragment(usage):
    seed, activities = components()
    factory = Factory({"seed": [{"workbook": {"title": "PRIVATE_FRAGMENT"}}, seed],
                       "guided": [activities["guided"]], "transfer": [activities["transfer"]]})
    saved = []

    async def save(value):
        saved.append(value)

    package, response, _ = await run(factory, on_parts=save)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 2, "guided": 1, "transfer": 1}
    assert response.effective_parameters["requested_output_tokens"] == 12400
    assert len(saved) == 3
    assert factory.requests[1][2]["correction"]["rejected_component"] == {"workbook": {"title": "PRIVATE_FRAGMENT"}}
    assert "PRIVATE_FRAGMENT" not in json.dumps(saved)
    assert "PRIVATE_FRAGMENT" not in json.dumps(response.effective_parameters)


@pytest.mark.asyncio
async def test_correction_exhaustion_never_publishes_partial_and_resume_reuses_valid_seed(usage):
    seed, activities = components()
    bad = {"id": "transfer"}
    factory = Factory({"seed": [seed], "guided": [activities["guided"]], "transfer": [bad, bad]})
    saved = []

    async def save(value):
        saved.append(value)

    package, response, _ = await run(factory, on_parts=save)
    assert package is None and response.error and response.data == {}
    assert response.effective_parameters["synthetic_local_validation"] is True
    assert len(saved) == 2 and usage.await_count == 4
    assert set(saved[-1]["activities"]) == {"guided"}
    resumed = Factory({"transfer": [activities["transfer"]]})
    package, response, _ = await run(resumed, existing_parts=saved[-1])
    assert package is not None and response.error is None
    assert resumed.counts == {"transfer": 1} and usage.await_count == 5


@pytest.mark.asyncio
async def test_complete_snapshot_needs_no_provider_and_preserves_activity_order(usage):
    seed, activities = components(4)
    parts = snapshot(seed, dict(reversed(list(activities.items()))))
    package, response, _ = await run(Factory({}), existing_parts=parts)
    assert response.error is None and usage.await_count == 0
    assert [activity.id for activity in package.workbook.activities] == ["guided", "practice_1", "practice_2", "transfer"]


@pytest.mark.parametrize("defect", ["hash", "version", "unknown", "kind", "raw", "transfer_copy"])
def test_saved_parts_fail_closed_for_corruption_and_cross_component_contracts(defect):
    seed, activities = components(numeric=True)
    parts = snapshot(seed, activities)
    if defect == "hash":
        parts["seed_hash"] = "changed"
    elif defect == "version":
        parts["version"] = True
    elif defect == "unknown":
        parts["activities"]["other"] = parts["activities"].pop("transfer")
    elif defect == "kind":
        parts["activities"]["transfer"]["kind"] = "practice"
    elif defect == "raw":
        parts["activities"]["transfer"]["fields"][0]["expression"] = "2"
    else:
        parts["activities"]["transfer"]["data"][0]["value"] = 10
    with pytest.raises(ValueError):
        builder.validate_package_parts(parts)


@pytest.mark.asyncio
async def test_invalid_saved_parts_return_before_paid_calls(usage):
    factory = Factory({})
    package, response, _ = await run(factory, existing_parts={})
    assert package is None and response.error and not factory.requests and usage.await_count == 0


@pytest.mark.asyncio
@pytest.mark.parametrize("old_shape", [False, True])
async def test_old_parts_versions_or_guided_seed_shape_fail_closed_before_provider(old_shape, usage):
    seed, activities = components()
    if old_shape:
        seed = {"workbook_title": seed["workbook_title"], "teaching_cases": seed["teaching_cases"],
                "guided_activity": activities["guided"],
                "remaining_activity_briefs": seed["activity_briefs"][1:]}
    parts = {"version": 2 if old_shape else 1, "seed": seed,
             "seed_hash": digest(seed), "activities": {}}
    factory = Factory({})
    package, response, _ = await run(factory, existing_parts=parts)
    assert package is None and response.error
    assert factory.counts == {} and usage.await_count == 0


@pytest.mark.asyncio
async def test_two_concurrent_failures_share_only_one_correction(usage):
    seed, activities = components(4)

    async def bad():
        await asyncio.sleep(0.01)
        return {"id": "incomplete"}

    factory = Factory({"seed": [seed], "guided": [activities["guided"]], "practice_1": [bad, activities["practice_1"]],
        "practice_2": [bad, activities["practice_2"]], "transfer": [activities["transfer"]]})
    package, response, _ = await run(factory)
    assert package is None and response.error
    assert sum(max(0, count - 1) for count in factory.counts.values()) <= 1
    assert all(count <= 2 for count in factory.counts.values())
    assert factory.max_active <= 2 and factory.active == 0
    assert usage.await_count == len(factory.requests)


@pytest.mark.asyncio
async def test_six_activity_scope_has_explicit_bound_and_no_silent_dropped_components(usage):
    seed, activities = components(6)

    def delayed(value):
        async def finish():
            await asyncio.sleep(0.005)
            return value
        return finish

    factory = Factory({"seed": [seed], **{key: [delayed(value)] for key, value in activities.items()}})
    package, response, _ = await run(factory)
    assert len(package.workbook.activities) == 6 and response.error is None
    assert response.effective_parameters["max_component_requests"] == 8
    assert response.effective_parameters["output_token_budget"] == 30200
    assert response.effective_parameters["requested_output_tokens"] == 26200
    assert factory.max_active == 2 and usage.await_count == 7


@pytest.mark.asyncio
@pytest.mark.parametrize("started", [True, False])
async def test_stage_timeout_cleans_up_requests_and_never_bills_local_queue(started, monkeypatch, usage):
    monkeypatch.setattr(builder, "_STAGE_SECONDS", 0.02)

    async def blocked():
        await asyncio.sleep(5)

    factory = Factory({"seed": [blocked]}, started=started, wrapped=True)
    package, response, _ = await run(factory)
    assert package is None and "deadline" in response.error
    assert factory.active == 0
    assert usage.await_count == int(started)
    if started:
        recorded = usage.await_args.kwargs["response"]
        assert recorded.attempt_id == "seed-1" and recorded.total_tokens is None


@pytest.mark.asyncio
async def test_shared_deadline_wrapper_owns_queue_wait_not_component_request_timer(monkeypatch, usage):
    monkeypatch.setattr(builder, "_REQUEST_SECONDS", 0.005)
    seed, activities = components()

    async def queued_seed():
        await asyncio.sleep(0.015)
        return seed

    factory = Factory({"seed": [queued_seed], "guided": [activities["guided"]], "transfer": [activities["transfer"]]}, wrapped=True)
    package, response, _ = await run(factory)
    assert package is not None and response.error is None and usage.await_count == 3
    assert factory.counts["seed"] == 1


@pytest.mark.asyncio
async def test_unwrapped_request_timeout_gets_one_bounded_retry_and_unknown_usage(monkeypatch, usage):
    monkeypatch.setattr(builder, "_REQUEST_SECONDS", 0.005)
    seed, activities = components()

    async def slow():
        await asyncio.sleep(5)

    factory = Factory({"seed": [slow, seed], "guided": [activities["guided"]], "transfer": [activities["transfer"]]})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None and usage.await_count == 4
    assert usage.await_args_list[0].kwargs["response"].total_tokens is None
    assert factory.active == 0


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [
    LLMResponse(data={}, error="zai request failed (GenerationUnavailable; redacted)", retryable=False),
    LLMResponse(data={}, error="zai request failed (RateLimitError; redacted)", retryable=True, retry_after_seconds=30),
])
async def test_permanent_or_long_backoff_failure_does_not_retry(failure, usage):
    factory = Factory({"seed": [failure]})
    package, response, _ = await run(factory)
    assert package is None and response.error and factory.counts == {"seed": 1}
    assert usage.await_count == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("error", [RuntimeError("superseded"), TimeoutError("storage unavailable")])
async def test_storage_failures_propagate_without_fresh_generation(error, usage):
    seed, _ = components()
    factory = Factory({"seed": [seed]})

    async def failed_save(value):
        raise error

    with pytest.raises(type(error), match=str(error)):
        await run(factory, on_parts=failed_save)
    assert factory.counts == {"seed": 1} and usage.await_count == 1


@pytest.mark.asyncio
async def test_external_cancellation_is_not_converted_into_local_success(usage):
    entered = asyncio.Event()

    async def blocked():
        entered.set()
        await asyncio.sleep(5)

    factory = Factory({"seed": [blocked]})
    task = asyncio.create_task(run(factory))
    await entered.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert factory.active == 0 and usage.await_count == 1


@pytest.mark.asyncio
async def test_cancelled_reused_client_does_not_reuse_an_old_request_bill(usage):
    entered = asyncio.Event()

    class ReusedClient:
        model = "offline-model"
        request_started = True
        last_attempt = LLMResponse(data={}, attempt_id="old-paid-call", prompt_tokens=100,
                                   completion_tokens=200, total_tokens=300)

        async def generate_json(self, **kwargs):
            entered.set()
            await asyncio.sleep(5)

    task = asyncio.create_task(run(lambda **kwargs: ReusedClient()))
    await entered.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert usage.await_count == 1
    response = usage.await_args.kwargs["response"]
    assert response.attempt_id is None and response.total_tokens is None


@pytest.mark.asyncio
async def test_cancellation_during_usage_persistence_records_received_response_once(monkeypatch):
    seed, _ = components()
    recording = asyncio.Event()
    recorded = []

    async def persist(**kwargs):
        recording.set()
        await asyncio.sleep(0.01)
        recorded.append(kwargs["response"])

    monkeypatch.setattr(builder, "record_llm_response", persist)
    factory = Factory({"seed": [seed]})
    task = asyncio.create_task(run(factory))
    await recording.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert len(recorded) == 1 and recorded[0].total_tokens == 13
    assert recorded[0].attempt_id == "seed-1"
    assert factory.counts == {"seed": 1}


@pytest.mark.asyncio
async def test_telemetry_stall_cannot_hold_cancellation_indefinitely(monkeypatch):
    monkeypatch.setattr(builder, "_USAGE_FINALIZATION_SECONDS", 0.02)
    seed, _ = components()
    recording = asyncio.Event()
    attempts = []

    async def stalled(**kwargs):
        attempts.append(kwargs["response"])
        recording.set()
        await asyncio.sleep(5)

    monkeypatch.setattr(builder, "record_llm_response", stalled)
    task = asyncio.create_task(run(Factory({"seed": [seed]})))
    await recording.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await asyncio.wait_for(task, 0.2)
    assert len(attempts) == 1 and attempts[0].total_tokens == 13


@pytest.mark.asyncio
async def test_telemetry_stall_is_bounded_and_reported_without_retrying_paid_work(monkeypatch):
    monkeypatch.setattr(builder, "_USAGE_FINALIZATION_SECONDS", 0.005)
    seed, activities = components()

    async def stalled(**kwargs):
        await asyncio.sleep(5)

    recorder = AsyncMock(side_effect=stalled)
    monkeypatch.setattr(builder, "record_llm_response", recorder)
    factory = Factory({"seed": [seed], "guided": [activities["guided"]], "transfer": [activities["transfer"]]})
    package, response, _ = await asyncio.wait_for(run(factory), 0.3)
    assert package is not None and response.error is None
    assert response.effective_parameters["usage_records_incomplete"] == 3
    assert recorder.await_count == 3 and factory.counts == {"seed": 1, "guided": 1, "transfer": 1}


@pytest.mark.asyncio
async def test_three_healthy_lessons_share_two_slots_without_spending_stage_budget_in_queue(monkeypatch, usage):
    from app.core.config import settings
    from app.tasks.plans import _deadline_client_factory

    monkeypatch.setattr(settings, "llm_provider", "dummy")
    monkeypatch.setattr(settings, "llm_admission_limits", {"dummy:test": 3})
    monkeypatch.setattr(settings, "llm_admission_per_user", 2)
    monkeypatch.setattr(settings, "llm_admission_foreground_reserve", 1)
    monkeypatch.setattr(builder, "_STAGE_SECONDS", 2.4)
    monkeypatch.setattr(builder, "_REQUEST_SECONDS", 2.0)
    seed, activities = components()

    def delayed(value):
        async def finish():
            # Even with all three requests serialized, this lesson spends at
            # most 2.1s active. Shared queueing takes wall time beyond 2.4s.
            # Leave scheduling headroom in containerized test environments.
            await asyncio.sleep(0.7)
            return value
        return finish

    factory = Factory({"seed": [delayed(seed) for _ in range(3)],
                       "guided": [delayed(activities["guided"]) for _ in range(3)],
                       "transfer": [delayed(activities["transfer"]) for _ in range(3)]})
    shared = _deadline_client_factory(factory, deadline=asyncio.get_running_loop().time() + 15)
    outcomes = await asyncio.gather(*(run(shared) for _ in range(3)))
    assert all(package is not None and response.error is None for package, response, _ in outcomes)
    assert max(response.duration_ms for _, response, _ in outcomes) > 2400
    assert factory.max_active == 2 and usage.await_count == 9
    assert factory.counts == {"seed": 3, "guided": 3, "transfer": 3}


@pytest.mark.asyncio
async def test_overlapping_activity_requests_consume_union_time_not_sum(monkeypatch, usage):
    monkeypatch.setattr(builder, "_STAGE_SECONDS", 0.13)
    monkeypatch.setattr(builder, "_REQUEST_SECONDS", 0.12)
    seed, activities = components(2)

    def delayed(value, seconds):
        async def finish():
            await asyncio.sleep(seconds)
            return value
        return finish

    factory = Factory({"seed": [delayed(seed, 0.02)],
        **{key: [delayed(value, 0.07)] for key, value in activities.items()}})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    assert factory.max_active == 2 and usage.await_count == 3


@pytest.mark.asyncio
async def test_good_parallel_component_is_not_generated_twice_when_peer_needs_correction(usage):
    seed, activities = components(3)
    factory = Factory({"seed": [seed], "guided": [activities["guided"]], "practice_1": [activities["practice_1"]],
                       "transfer": [{"id": "incomplete"}, activities["transfer"]]})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 1, "guided": 1, "practice_1": 1, "transfer": 2}
    assert usage.await_count == 5
