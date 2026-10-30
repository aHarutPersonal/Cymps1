"""Offline coverage for goal-aligned response formats and prompt delivery.

These tests verify executable contracts and privacy, not learning effectiveness.
"""
import copy
import json

import pytest
from pydantic import ValidationError

from app.services.llm.prompt_loader import extract_placeholders, load_and_render, resolve_prompt_text
from app.services.planning.activity_draft import (
    TutorialActivityDraft, parse_activity_repair_draft,
)
from app.services.planning.lesson_writer import _tutorial_contract
from app.services.practice.contracts import GeneratedWorkbook, Workbook, public_workbook
from tests.test_activity_draft import draft_payload


@pytest.mark.parametrize("kind,index", [("number", 0), ("choice", 1), ("text", 2)])
def test_single_response_survives_draft_repair_storage_and_public_projection(kind, index):
    raw = draft_payload()
    raw["fields"] = [raw["fields"][index]]
    TutorialActivityDraft.model_validate(raw)
    canonical = parse_activity_repair_draft(raw, tutorial=True)
    assert canonical.fields[0].kind == kind
    assert canonical.worked_solution.steps[0].explanation == raw["fields"][0]["explanation"]
    transfer = canonical.model_copy(update={"id": "new_case", "kind": "transfer"})
    workbook = GeneratedWorkbook(title="Explain the decision", activities=[canonical, transfer])
    stored = Workbook.model_validate(workbook.model_dump(mode="json"))
    assert stored.model_dump(mode="json") == workbook.model_dump(mode="json")
    public = public_workbook(stored)
    field = public["activities"][0]["fields"][0]
    assert field["kind"] == kind
    assert {"expression", "correct_choice", "explanation", "criteria"}.isdisjoint(field)
    assert "worked_solution" not in public["activities"][0]


def test_text_only_exemplar_has_owned_solution_and_observable_criteria():
    raw = json.loads(resolve_prompt_text("tutorial_exemplar_qualitative.txt").split("\n", 1)[1])
    canonical = parse_activity_repair_draft(raw, tutorial=True)
    assert [field.kind for field in canonical.fields] == ["text"]
    assert len(canonical.fields[0].criteria) >= 2
    assert canonical.worked_solution.steps[0].field_id == canonical.fields[0].id
    without_criteria = copy.deepcopy(raw)
    without_criteria["fields"][0]["criteria"] = []
    with pytest.raises(ValidationError):
        TutorialActivityDraft.model_validate(without_criteria)


@pytest.mark.parametrize("name", ["plan_item_tutorial_outline.txt", "plan_item_details_outline.txt"])
def test_sequence_contract_reaches_rendered_outline_without_new_schema_fields(name):
    source = resolve_prompt_text(name)
    values = {key: "provided-context" for key in extract_placeholders(source)}
    rendered = load_and_render(name, values, strict=True)
    contract = resolve_prompt_text("learning_sequence_contract.txt").rstrip("\n")
    assert rendered.count(contract) == 1
    assert "{{include:" not in rendered
    assert not extract_placeholders(rendered)
    # Sequence guidance uses existing descriptions; it cannot invent a scheduler
    # or assume that independently generated activities share learner answers.
    assert "existing output fields" in rendered
    assert "unless that input is explicitly supplied" in rendered
    assert "short lessons or sequential unlocks do not" in rendered


def test_generation_and_repair_contracts_agree_on_response_flexibility():
    for name in ("tutorial_activity_generate.txt", "tutorial_package_seed.txt",
                 "lesson_practice_generate.txt"):
        prompt = load_and_render(name, {})
        assert "text-only" in prompt
        assert "every activity needs at least one number" not in prompt
        assert "rather than recall" not in prompt
    schema = TutorialActivityDraft.model_json_schema()["properties"]["fields"]
    assert schema["minItems"] == 1 and schema["maxItems"] == 2
    assert schema["minContains"] == 0 and schema["maxContains"] == 1
    assert schema["contains"]["properties"]["kind"] == {"const": "text"}


def test_writer_keeps_quick_check_within_reader_capabilities():
    prompt = _tutorial_contract()
    assert "supported numeric or choice response" in prompt
    assert "reader reveals it after an answer" in prompt
    assert "Keep independent workbook answers private" in prompt
