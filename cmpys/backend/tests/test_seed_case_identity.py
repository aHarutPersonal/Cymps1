"""Fresh-response namespace repair cannot alter facts or persisted contracts."""
import copy
import json
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning import package_builder as builder
from app.services.planning.lesson_package import LessonPackage, digest
from tests.test_staged_package_builder import Factory, components, run


@pytest.fixture
def usage(monkeypatch):
    recorder = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", recorder)
    return recorder


def missing_seed():
    seed, activities = components(numeric=True)
    seed["teaching_cases"].append(copy.deepcopy(seed["teaching_cases"][0]))
    seed["teaching_cases"][1]["data"][0]["value"] = 11
    for case in seed["teaching_cases"]:
        case.pop("id")
    return seed, activities


def test_only_absent_case_identity_changes_and_inputs_are_not_mutated():
    source, _ = missing_seed()
    before = copy.deepcopy(source)
    seed, count = builder.parse_initial_seed_response(source)
    assert count == 2
    expected = copy.deepcopy(source)
    for index, case in enumerate(expected["teaching_cases"]):
        case["id"] = f"teaching_case_{index + 1}"
    assert seed == builder.LessonPackageSeed.model_validate(expected)
    assert source == before
    repeated, count_again = builder.parse_initial_seed_response(source)
    assert repeated == seed and count_again == count
    assert digest(repeated.model_dump(mode="json")) == digest(seed.model_dump(mode="json"))
    assert [case.computed()["results"][0]["claim_id"] for case in seed.teaching_cases] == [
        "teaching_case_1.double", "teaching_case_2.double"]
    assert [case.computed()["results"][0]["display_value"] for case in seed.teaching_cases] == ["20.0", "22.0"]


def test_valid_supplied_ids_and_mixed_seed_are_preserved():
    source, _ = missing_seed()
    source["teaching_cases"][0]["id"] = "original_case"
    seed, count = builder.parse_initial_seed_response(source)
    assert [case.id for case in seed.teaching_cases] == ["original_case", "teaching_case_2"]
    assert count == 1
    complete = seed.model_dump(mode="json")
    repeated, count = builder.parse_initial_seed_response(complete)
    assert repeated == seed and count == 0


@pytest.mark.parametrize("identifier", [None, "", "bad-id", 4, True, {}, []])
def test_explicit_invalid_id_is_never_replaced(identifier):
    source, _ = missing_seed()
    source["teaching_cases"][0]["id"] = identifier
    before = copy.deepcopy(source)
    with pytest.raises(ValueError):
        builder.parse_initial_seed_response(source)
    assert source == before


@pytest.mark.parametrize("defect", ["collision", "duplicate_supplied"])
def test_collision_and_duplicate_supplied_ids_are_not_renamed(defect):
    source, _ = missing_seed()
    if defect == "collision":
        source["teaching_cases"][1]["id"] = "teaching_case_1"
    else:
        source["teaching_cases"][0]["id"] = "duplicate"
        source["teaching_cases"][1]["id"] = "duplicate"
        source["teaching_cases"].append(copy.deepcopy(source["teaching_cases"][0]))
        source["teaching_cases"][-1].pop("id")
    before = copy.deepcopy(source)
    with pytest.raises(ValueError):
        builder.parse_initial_seed_response(source)
    assert source == before


@pytest.mark.parametrize("reference", [
    "[[result:old_case.double]]", "[[result:unfinished", "[[practice:guided.answer]]",
    "teaching.old_case", "teaching . old_case", "old_case.double", "teaching_cases[0].results",
    "case_id is old_case", "claim_id is old_case.double", "display_token is missing",
])
def test_explicit_identity_references_make_missing_namespace_ambiguous(reference):
    source, _ = missing_seed()
    source["activity_briefs"][0]["scope"] += " Use " + reference
    with pytest.raises(ValueError):
        builder.parse_initial_seed_response(source)


def test_ordinary_sentences_and_decimal_values_do_not_imply_identity_references():
    source, _ = missing_seed()
    source["teaching_cases"][0]["assumptions"] = (
        "The fictional length is 10.5 metres. Use the stated units. Compare the result independently.")
    source["teaching_cases"][0]["data"][0]["value"] = 10.5
    seed, count = builder.parse_initial_seed_response(source)
    assert count == 2 and seed.teaching_cases[0].data[0].value == 10.5


@pytest.mark.parametrize("defect", ["missing_label", "missing_value", "missing_result_id", "extra_key",
                                   "foreign_operand", "constant_answer", "zero_denominator", "duplicate_data"])
def test_id_assignment_cannot_conceal_other_schema_or_formula_defects(defect):
    source, _ = missing_seed()
    case = source["teaching_cases"][0]
    if defect == "missing_label":
        case["data"][0].pop("label")
    elif defect == "missing_value":
        case["data"][0].pop("value")
    elif defect == "missing_result_id":
        case["results"][0].pop("id")
    elif defect == "extra_key":
        case["notes"] = "An unsupported structural field"
    elif defect == "foreign_operand":
        case["results"][0]["expression"] = "unknown * 2"
    elif defect == "constant_answer":
        case["results"][0]["expression"] = "20"
    elif defect == "zero_denominator":
        case["results"][0]["expression"] = "base / 0"
    else:
        case["data"].append(copy.deepcopy(case["data"][0]))
    with pytest.raises((ValueError, SyntaxError)):
        builder.parse_initial_seed_response(source)


def test_canonical_models_and_saved_parts_still_reject_missing_ids():
    source, activities = missing_seed()
    parsed, _ = builder.parse_initial_seed_response(source)
    with pytest.raises(ValueError):
        builder.LessonPackageSeed.model_validate(source)
    with pytest.raises(ValueError):
        LessonPackage.model_validate({"teaching_cases": source["teaching_cases"],
            "workbook": {"title": source["workbook_title"], "activities": list(activities.values())}})
    # Even a digest of the would-be normalized seed cannot repair a corrupt saved
    # snapshot: the recovery path is deliberately stricter than fresh responses.
    with pytest.raises(ValueError):
        builder.validate_package_parts({"version": 2, "seed": source,
            "seed_hash": digest(parsed.model_dump(mode="json")), "activities": {}})


@pytest.mark.asyncio
async def test_initial_missing_ids_use_no_correction_and_log_counts_without_ids_or_content(usage):
    source, activities = missing_seed()
    raw_response = LLMResponse(data=copy.deepcopy(source), finish_reason="stop", total_tokens=37,
                              effective_parameters={"existing": True})
    factory = Factory({"seed": [raw_response], **{key: [value] for key, value in activities.items()}})
    saved = []

    async def save(value):
        saved.append(value)

    package, response, _ = await run(factory, on_parts=save)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 1}
    assert response.effective_parameters["shared_correction_used"] is False
    assert response.effective_parameters["normalized_seed_case_id_count"] == 2
    assert response.effective_parameters["requested_output_tokens"] == 10200
    assert usage.await_count == 3
    recorded = usage.await_args_list[0].kwargs["response"]
    assert recorded.total_tokens == 37
    assert recorded.data == source  # raw response is never rewritten to hide the defect
    assert recorded.effective_parameters == {"existing": True, "normalized_seed_case_id_count": 2}
    assert "teaching_case_1" not in json.dumps(recorded.effective_parameters)
    assert len(saved) == 3
    resumed_factory = Factory({})
    resumed, resumed_response, _ = await run(resumed_factory, existing_parts=saved[-1])
    assert resumed == package and not resumed_factory.counts
    assert resumed_response.effective_parameters["normalized_seed_case_id_count"] == 0


@pytest.mark.asyncio
async def test_normalized_seed_preserves_shared_correction_for_a_failed_activity(usage):
    source, activities = missing_seed()
    bad = copy.deepcopy(activities["transfer"])
    bad["fields"][0].pop("label")
    factory = Factory({"seed": [source], "guided": [activities["guided"]], "transfer": [bad, activities["transfer"]]})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 2}
    assert response.effective_parameters["shared_correction_used"] is True
    assert response.effective_parameters["normalized_seed_case_id_count"] == 2
    assert response.effective_parameters["max_component_requests"] == 4
    assert response.effective_parameters["requested_output_tokens"] == 14200
    assert all(options["timeout"] == 90 for options in factory.options)
    assert usage.await_count == 4


@pytest.mark.asyncio
@pytest.mark.parametrize("terminal", ["length", "provider_error"])
async def test_incomplete_or_errored_response_is_never_rescued_by_identity_assignment(terminal, usage):
    source, activities = missing_seed()
    valid = builder.parse_initial_seed_response(source)[0].model_dump(mode="json")
    failed = LLMResponse(data=source, finish_reason="length" if terminal == "length" else "stop",
                         error=None if terminal == "length" else "zai request failed (JSONProtocolError; invalid)")
    factory = Factory({"seed": [failed, valid], **{key: [value] for key, value in activities.items()}})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 2, "guided": 1, "transfer": 1}
    assert response.effective_parameters["normalized_seed_case_id_count"] == 0
    assert response.effective_parameters["shared_correction_used"] is True
    assert "normalized_seed_case_id_count" not in failed.effective_parameters
