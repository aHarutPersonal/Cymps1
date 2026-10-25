"""One known fresh-provider extra field is preserved, never silently ignored."""
import copy
import json
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.prompt_loader import load_and_render
from app.services.planning import package_builder as builder
from app.services.planning.lesson_package import digest
from tests.test_seed_case_identity import missing_seed
from tests.test_staged_package_builder import Factory, components, run


def with_note(*, numeric=False):
    seed, activities = components(numeric=numeric)
    seed["activity_briefs"][1]["kind_note"] = "  Փոխանցում․ explain the independent choice.\nRetain this entire rationale.  "
    return seed, activities


def test_note_relocation_is_lossless_deterministic_and_does_not_change_public_tuple_api():
    source, _ = with_note()
    before = copy.deepcopy(source)
    result = builder.parse_initial_seed_response(source)
    assert len(result) == 2
    seed, identity_count = result
    expected = copy.deepcopy(source)
    note = expected["activity_briefs"][1].pop("kind_note")
    expected["activity_briefs"][1]["scope"] += "\n" + note
    assert seed == builder.LessonPackageSeed.model_validate(expected)
    assert identity_count == 0
    assert source == before
    assert builder.parse_initial_seed_response(source) == result
    assert builder.parse_initial_seed_response(seed.model_dump(mode="json")) == result


@pytest.mark.parametrize("length", [4000, 4001])
def test_combined_scope_uses_existing_exact_limit_without_truncation(length):
    source, _ = with_note()
    brief = source["activity_briefs"][1]
    brief["scope"] = "x" * 40
    brief["kind_note"] = "y" * (length - 41)
    before = copy.deepcopy(source)
    if length == 4000:
        seed, _ = builder.parse_initial_seed_response(source)
        assert seed.activity_briefs[1].scope == "x" * 40 + "\n" + "y" * 3959
    else:
        with pytest.raises(ValueError):
            builder.parse_initial_seed_response(source)
    assert source == before


@pytest.mark.parametrize("note", [None, " \n\t ", 0, True, [], {}, ["rationale"], "x" * 4001])
def test_nontext_whitespace_or_oversized_note_is_never_discarded(note):
    source, _ = with_note()
    source["activity_briefs"][1]["kind_note"] = note
    before = copy.deepcopy(source)
    with pytest.raises(ValueError):
        builder.parse_initial_seed_response(source)
    assert source == before


@pytest.mark.parametrize("defect", ["unknown_extra", "root_note", "case_note", "missing_scope",
                                   "short_scope", "invalid_kind", "duplicate_brief_id", "bad_formula"])
def test_note_relocation_cannot_hide_other_contract_errors(defect):
    source, _ = with_note(numeric=True)
    brief = source["activity_briefs"][1]
    if defect == "unknown_extra":
        brief["notes"] = "Must not silently accept any other extra property."
    elif defect == "root_note":
        source["kind_note"] = brief.pop("kind_note")
    elif defect == "case_note":
        source["teaching_cases"][0]["kind_note"] = brief.pop("kind_note")
    elif defect == "missing_scope":
        brief.pop("scope")
    elif defect == "short_scope":
        brief["scope"] = "short"
    elif defect == "invalid_kind":
        brief["kind"] = "other"
    elif defect == "duplicate_brief_id":
        brief["id"] = source["activity_briefs"][0]["id"]
    else:
        source["teaching_cases"][0]["results"][0]["expression"] = "unknown * 2"
    before = copy.deepcopy(source)
    with pytest.raises(ValueError):
        builder.parse_initial_seed_response(source)
    assert source == before


def test_note_and_missing_ids_combine_without_losing_reference_ambiguity_checks():
    source, _ = missing_seed()
    source["activity_briefs"][1]["kind_note"] = "Keep this rationale in the independent activity."
    parsed, identity_count = builder.parse_initial_seed_response(source)
    assert identity_count == 2
    assert parsed.activity_briefs[1].scope.endswith("\n" + source["activity_briefs"][1]["kind_note"])
    source["activity_briefs"][1]["kind_note"] += " Use teaching.old_case."
    with pytest.raises(ValueError):
        builder.parse_initial_seed_response(source)


def test_canonical_and_saved_seed_contracts_still_reject_the_extra_property():
    source, _ = with_note()
    parsed, _ = builder.parse_initial_seed_response(source)
    with pytest.raises(ValueError):
        builder.LessonPackageSeed.model_validate(source)
    with pytest.raises(ValueError):
        builder.validate_package_parts({"version": 2, "seed": source,
            "seed_hash": digest(parsed.model_dump(mode="json")), "activities": {}})


@pytest.mark.asyncio
async def test_first_response_note_keeps_one_correction_and_records_counts_only(monkeypatch):
    usage = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", usage)
    source, activities = with_note()
    raw = LLMResponse(data=copy.deepcopy(source), finish_reason="stop", total_tokens=37,
                      effective_parameters={"existing": True})
    bad = copy.deepcopy(activities["transfer"])
    bad["fields"][0].pop("label")
    factory = Factory({"seed": [raw], "guided": [activities["guided"]],
                       "transfer": [bad, activities["transfer"]]})
    saved = []

    async def save(snapshot):
        saved.append(snapshot)

    package, response, _ = await run(factory, on_parts=save)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 1, "guided": 1, "transfer": 2}
    assert response.effective_parameters["normalized_seed_scope_note_count"] == 1
    assert response.effective_parameters["normalized_seed_case_id_count"] == 0
    assert response.effective_parameters["shared_correction_used"] is True
    assert response.effective_parameters["max_component_requests"] == 4
    assert response.effective_parameters["requested_output_tokens"] == 14200
    recorded = usage.await_args_list[0].kwargs["response"]
    assert recorded.data == source
    assert recorded.total_tokens == 37
    assert recorded.effective_parameters == {"existing": True, "normalized_seed_case_id_count": 0,
                                             "normalized_seed_scope_note_count": 1}
    assert source["activity_briefs"][1]["kind_note"] not in json.dumps(recorded.effective_parameters)
    assert usage.await_count == 4
    assert all(options["timeout"] == 90 for options in factory.options)
    assert [options["max_tokens"] for options in factory.options] == [2200, 4000, 4000, 4000]
    assert "kind_note" not in saved[0]["seed"]["activity_briefs"][1]
    transfer_requests = [data for key, _, data in factory.requests if key == "transfer"]
    assert all(data["activity_brief"]["scope"].endswith("\n" + source["activity_briefs"][1]["kind_note"])
               for data in transfer_requests)
    resumed_factory = Factory({})
    resumed, resumed_response, _ = await run(resumed_factory, existing_parts=saved[-1])
    assert resumed == package and not resumed_factory.counts
    assert resumed_response.effective_parameters.get("normalized_seed_scope_note_count", 0) == 0


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["length", "duplicate_json", "transport"])
async def test_incomplete_or_protocol_failed_seed_never_enters_normalization(failure, monkeypatch):
    usage = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, "record_llm_response", usage)
    source, activities = with_note()
    valid = builder.parse_initial_seed_response(source)[0].model_dump(mode="json")
    failed = LLMResponse(data=source, finish_reason="length" if failure == "length" else "stop",
        error=(None if failure == "length" else
               "zai request failed (JSONProtocolError; duplicate keys)" if failure == "duplicate_json" else
               "zai request failed (TimeoutError; unavailable)"))
    factory = Factory({"seed": [failed, valid], **{key: [value] for key, value in activities.items()}})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    assert factory.counts == {"seed": 2, "guided": 1, "transfer": 1}
    assert response.effective_parameters.get("normalized_seed_scope_note_count", 0) == 0
    assert "normalized_seed_scope_note_count" not in failed.effective_parameters
    assert response.effective_parameters["shared_correction_used"] is True


def test_seed_prompt_names_only_the_allowed_brief_fields():
    prompt = " ".join(load_and_render("lesson_package_seed.txt", {}).split())
    assert "Each brief has exactly id, kind and scope. Include necessary rationale in scope." in prompt
    assert "kind_note" not in prompt
    assert "no commentary, fences, fragments or duplicate keys" in prompt


@pytest.mark.parametrize("key", ["id_note", "id_hint"])
def test_known_id_annotations_preserve_scope_and_identity(key):
    from app.services.planning.package_builder import parse_initial_seed_response
    from tests.test_lesson_pipeline_reliability import package_payload
    from app.services.planning.lesson_package import LessonPackage
    package = LessonPackage.model_validate(package_payload())
    source = {"workbook_title": package.workbook.title, "teaching_cases": [],
              "activity_briefs": [{"id": a.id, "kind": a.kind, "scope": a.instructions}
                                  for a in package.workbook.activities]}
    source["activity_briefs"][0][key] = "Preserve this descriptive annotation."
    original = copy.deepcopy(source)
    parsed, count = parse_initial_seed_response(source)
    assert count == 0 and source == original
    assert parsed.activity_briefs[0].id == source["activity_briefs"][0]["id"]
    assert parsed.activity_briefs[0].scope == source["activity_briefs"][0]["scope"] + "\n" + source["activity_briefs"][0][key]
