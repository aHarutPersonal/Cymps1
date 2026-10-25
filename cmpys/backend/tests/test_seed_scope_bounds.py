"""Planning prose has a bounded safety ceiling, not a brittle style rejection."""
import copy
from unittest.mock import AsyncMock

import pytest

from app.services.planning import package_builder as builder
from app.services.planning.lesson_package import LessonPackage, digest
from app.services.practice.contracts import Activity
from tests.test_staged_package_builder import Factory, components, run


def seed_with_scope(length):
    seed, activities = components(numeric=True)
    original = seed["activity_briefs"][1]["scope"]
    seed["activity_briefs"][1]["scope"] = original + "\n" + "Մ" * (length - len(original) - 1)
    assert len(seed["activity_briefs"][1]["scope"]) == length
    return seed, activities


def test_scope_wire_bound_matches_activity_instructions_and_retains_minimum():
    scope = builder.LessonPackageSeed.model_json_schema()["$defs"]["ActivityBrief"]["properties"]["scope"]
    instructions = Activity.model_json_schema()["properties"]["instructions"]
    assert scope["maxLength"] == instructions["maxLength"] == 4000
    assert scope["minLength"] == instructions["minLength"] == 40


@pytest.mark.parametrize("length", [1083, 4000])
def test_complete_scope_is_accepted_verbatim_without_normalization(length):
    source, _ = seed_with_scope(length)
    before = copy.deepcopy(source)
    seed, identity_count = builder.parse_initial_seed_response(source)
    assert identity_count == 0
    assert seed.model_dump(mode="json") == builder.LessonPackageSeed.model_validate(before).model_dump(mode="json")
    assert seed.activity_briefs[1].scope == source["activity_briefs"][1]["scope"]
    assert source == before


def test_oversized_scope_is_rejected_in_fresh_and_saved_paths_without_truncation():
    source, _ = seed_with_scope(4001)
    before = copy.deepcopy(source)
    with pytest.raises(ValueError):
        builder.parse_initial_seed_response(source)
    with pytest.raises(ValueError):
        builder.validate_package_parts({"version": 2, "seed": source,
            "seed_hash": digest(source), "activities": {}})
    assert source == before


@pytest.mark.parametrize("defect", ["assumptions_objects", "unknown_formula_operand", "unknown_property"])
def test_longer_scope_does_not_relax_other_seed_contracts(defect):
    source, _ = seed_with_scope(1083)
    if defect == "assumptions_objects":
        source["teaching_cases"][0]["assumptions"] = [{"basis": "A descriptive assumption"}]
    elif defect == "unknown_formula_operand":
        source["teaching_cases"][0]["results"][0]["expression"] = "unknown * 2"
    else:
        source["activity_briefs"][1]["unsupported"] = "Do not ignore this extra property."
    before = copy.deepcopy(source)
    with pytest.raises(ValueError):
        builder.parse_initial_seed_response(source)
    assert source == before


@pytest.mark.asyncio
@pytest.mark.parametrize("length", [1083, 4000])
async def test_longer_scope_needs_no_retry_and_resumes_exact_saved_components(length, monkeypatch):
    usage = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", usage)
    source, activities = seed_with_scope(length)
    factory = Factory({"seed": [source], **{key: [value] for key, value in activities.items()}})
    saved = []

    async def save(snapshot):
        saved.append(snapshot)

    package, response, _ = await run(factory, on_parts=save)
    assert response.error is None
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 1}
    assert response.effective_parameters["shared_correction_used"] is False
    assert response.effective_parameters["component_requests"] == 3
    assert response.effective_parameters["requested_output_tokens"] == 10200
    assert response.effective_parameters["output_token_budget"] == 14200
    assert response.effective_parameters["stage_timeout_seconds"] == 240
    assert [options["max_tokens"] for options in factory.options] == [2200, 4000, 4000]
    assert all(options["timeout"] == 90 for options in factory.options)
    assert usage.await_count == 3
    expected_scope = source["activity_briefs"][1]["scope"]
    assert all(snapshot["seed"]["activity_briefs"][1]["scope"] == expected_scope for snapshot in saved)
    for key, _, payload in factory.requests:
        if key != "seed":
            assert payload["public_seed"]["activity_briefs"][1]["scope"] == expected_scope
        if key == "transfer":
            assert payload["activity_brief"]["scope"] == expected_scope
    expected = LessonPackage.model_validate({"teaching_cases": source["teaching_cases"],
        "workbook": {"title": source["workbook_title"], "activities": list(activities.values())}})
    assert package == expected
    resume_factory = Factory({})
    resumed, resumed_response, _ = await run(resume_factory, existing_parts=saved[-1])
    assert resumed == package and resumed_response.error is None
    assert not resume_factory.counts
    assert resumed_response.effective_parameters["component_requests"] == 0
    assert usage.await_count == 3
