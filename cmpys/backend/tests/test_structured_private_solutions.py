import copy
import hashlib
import json
from dataclasses import FrozenInstanceError
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.services.practice.contracts import Activity, SolutionDocument, Workbook, public_workbook
from app.services.practice.solution_compiler import compile_worked_solution, render_worked_solution


def _raw_activity(*, solution=None, expression="sales - collections - unpaid"):
    return {
        "id": "cash_case", "title": "Explain the cash difference", "kind": "practice",
        "instructions": "Use the supplied period-specific facts to explain the cash difference and check your reasoning.",
        "data": [
            {"id": "sales", "label": "Uncollected current sales", "value": 300000.0, "unit": "AMD"},
            {"id": "collections", "label": "Prior-period collections", "value": 150000.0, "unit": "AMD"},
            {"id": "unpaid", "label": "Unpaid current expenses", "value": 100000.0, "unit": "AMD"},
        ],
        "fields": [{"id": "gap", "label": "Cash difference", "kind": "number", "unit": "AMD",
                    "choices": [], "expression": expression, "correct_choice": None,
                    "tolerance": .01, "criteria": [], "rubric_criterion": None}],
        "hint": "Keep current-period amounts separate from collections for earlier periods.",
        "worked_solution": solution if solution is not None else {
            "version": 1, "steps": [{"field_id": "gap", "explanation":
                "Distinguish current uncollected sales from collections of earlier debts; account for unpaid expenses separately."}]},
        "minutes_min": 12, "minutes_max": 20, "diagram": None,
    }


def test_legacy_workbook_serialization_and_solution_bytes_are_unchanged():
    legacy = "  Current sales remain distinct from previous-period collections.\nThe signed difference is 50000 AMD.  "
    raw = _raw_activity(solution=legacy)
    expected = copy.deepcopy(raw)
    activity = Activity.model_validate(raw)
    assert activity.model_dump(mode="json") == expected
    compiled = compile_worked_solution(activity)
    assert compiled.text == legacy
    assert not compiled.records
    assert compiled.rendered_hash == hashlib.sha256(legacy.encode()).hexdigest()
    encoded = json.dumps(expected, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
    assert compiled.source_hash == hashlib.sha256(encoded.encode()).hexdigest()


def test_compiler_preserves_every_signed_term_in_one_exact_root_calculation():
    raw = _raw_activity()
    original = copy.deepcopy(raw)
    compiled = compile_worked_solution(raw)
    assert raw == original
    assert [record.expression for record in compiled.records] == ["sales - collections - unpaid"]
    assert [record.result for record in compiled.records] == [50000]
    assert [record.node_path for record in compiled.records] == [()]
    assert compiled.records[-1].text == "((300000 - 150000) - 100000) = 50000"
    assert compiled.records[-1].unit == "AMD"
    for record in compiled.records:
        assert compiled.text[record.start:record.end] == record.text
        assert record.activity_id == "cash_case"
        assert record.case_id == "practice.cash_case"
        assert record.field_id == "gap" and record.step_index == 0
        assert record.source_path == ("worked_solution",)
    assert raw["worked_solution"]["steps"][0]["explanation"] in compiled.text
    with pytest.raises(FrozenInstanceError):
        compiled.records[0].start = 0


def test_parentheses_and_negative_raw_inputs_are_not_simplified():
    raw = _raw_activity(expression="sales - (collections - unpaid)")
    raw["data"][0]["value"] = -300000
    compiled = compile_worked_solution(raw)
    assert compiled.records[-1].expression == "sales - (collections - unpaid)"
    assert compiled.records[-1].text == "((-300000) - (150000 - 100000)) = -350000"
    assert compiled.records[-1].result == -350000


def test_equal_values_keep_distinct_field_ownership_without_intermediate_bloat():
    raw = _raw_activity(expression="(sales - collections) + (sales - collections)")
    other = copy.deepcopy(raw["fields"][0])
    other["id"] = "other_gap"
    raw["fields"].append(other)
    raw["worked_solution"]["steps"].append({"field_id": "other_gap", "explanation":
        "This second quantity deliberately has its own field identity, even when the computed value is equal."})
    compiled = compile_worked_solution(raw)
    assert len(compiled.records) == 2
    assert compiled.records[0].text == compiled.records[1].text
    assert compiled.records[0].start != compiled.records[1].start
    assert compiled.records[0].field_id == "gap"
    assert compiled.records[1].field_id == "other_gap"


@pytest.mark.parametrize("expression", ["sales", "100"])
def test_nonderived_output_is_rendered_without_invented_arithmetic_proof(expression):
    compiled = compile_worked_solution(_raw_activity(expression=expression))
    assert not compiled.records
    assert ("300000" if expression == "sales" else "100") in compiled.text


def test_square_root_keeps_full_raw_input_derivation_in_one_record():
    raw = _raw_activity(expression="sqrt(sales * sales + collections * collections)")
    raw["data"][0]["value"], raw["data"][1]["value"] = 3, 4
    compiled = compile_worked_solution(raw)
    assert [record.result for record in compiled.records] == [5]
    assert compiled.records[-1].expression == "sqrt(sales * sales + collections * collections)"
    assert compiled.records[-1].text == "sqrt(((3 * 3) + (4 * 4))) = 5"


def test_rendered_numbers_preserve_float_precision_without_scientific_notation():
    raw = _raw_activity(expression="sales / collections")
    raw["data"][0]["value"], raw["data"][1]["value"] = 1, 3
    record = compile_worked_solution(raw).records[-1]
    assert record.literal == "0.3333333333333333"
    assert float(record.literal) == record.result
    raw["data"][1]["value"] = 1e10
    record = compile_worked_solution(raw).records[-1]
    assert record.literal == "0.0000000001"


@pytest.mark.parametrize("change", ["data", "expression", "label", "unit", "explanation"])
def test_source_and_rendered_identity_track_actual_input(change):
    raw = _raw_activity()
    original = compile_worked_solution(raw)
    if change == "data":
        raw["data"][0]["value"] += 1
    elif change == "expression":
        raw["fields"][0]["expression"] = "sales - (collections - unpaid)"
    elif change == "label":
        raw["fields"][0]["label"] += " after adjustments"
    elif change == "unit":
        raw["fields"][0]["unit"] = "EUR"
    else:
        raw["worked_solution"]["steps"][0]["explanation"] += " Check the period carefully."
    revised = compile_worked_solution(raw)
    assert revised.source_hash != original.source_hash
    assert revised.rendered_hash != original.rendered_hash


@pytest.mark.parametrize("version", [True, "1", 1.0, 2])
def test_document_version_is_explicit_and_strict(version):
    raw = _raw_activity()
    raw["worked_solution"]["version"] = version
    with pytest.raises(ValidationError):
        Activity.model_validate(raw)


@pytest.mark.parametrize("change", ["missing", "unknown", "duplicate", "extra", "empty", "oversized"])
def test_solution_contract_rejects_incomplete_or_ambiguous_field_ownership(change):
    raw = _raw_activity()
    doc = raw["worked_solution"]
    if change == "missing":
        doc["steps"] = []
    elif change == "unknown":
        doc["steps"][0]["field_id"] = "other_case_gap"
    elif change == "duplicate":
        doc["steps"].append(copy.deepcopy(doc["steps"][0]))
    elif change == "extra":
        doc["steps"][0]["claimed_result"] = 50000
    elif change == "empty":
        doc["steps"][0]["explanation"] = " " * 50
    else:
        doc["steps"][0]["explanation"] = "x" * 4001
    with pytest.raises(ValidationError):
        Activity.model_validate(raw)


def test_document_enforces_original_field_order_and_total_bound():
    raw = _raw_activity()
    raw["fields"].append({"id": "reason", "label": "Explain the period", "kind": "text", "criteria": ["Distinguishes periods"]})
    raw["worked_solution"]["steps"].append({"field_id": "reason", "explanation": "Different reporting periods must remain distinguishable in the final explanation."})
    assert isinstance(Activity.model_validate(raw).worked_solution, SolutionDocument)
    raw["worked_solution"]["steps"].reverse()
    with pytest.raises(ValidationError, match="exact order"):
        Activity.model_validate(raw)
    raw["worked_solution"]["steps"].reverse()
    for step in raw["worked_solution"]["steps"]:
        step["explanation"] = "x" * 2500
    with pytest.raises(ValidationError, match="Combined"):
        Activity.model_validate(raw)


def test_compiler_revalidates_mutated_models_instead_of_trusting_instances():
    activity = Activity.model_validate(_raw_activity())
    activity.worked_solution.steps[0].field_id = "nonexistent"
    with pytest.raises(ValidationError):
        compile_worked_solution(activity)


def test_authored_numbers_quotes_code_and_units_never_receive_compiler_records():
    raw = _raw_activity()
    raw["fields"][0]["label"] = 'Unverified label 555 and quote "2 + 2 = 9"'
    raw["fields"][0]["unit"] = "unit 777"
    explanation = 'A false claim says 999999.\n```text\n42 + 1 = 100\n```\nPreserve this exact authored text for independent rejection.'
    raw["worked_solution"]["steps"][0]["explanation"] = explanation
    compiled = compile_worked_solution(raw)
    assert explanation in compiled.text
    for record in compiled.records:
        assert not any(token in record.text for token in ("555", "777", "999999", "42 + 1"))
        assert compiled.text[record.start:record.end] == record.text
    for token in ("555", "777", "999999", "42 + 1"):
        index = compiled.text.index(token)
        assert not any(record.start <= index < record.end for record in compiled.records)


def test_public_workbook_hides_entire_structured_source_and_answer_keys():
    first = Activity.model_validate(_raw_activity())
    other_raw = _raw_activity(solution="This legacy private answer stays private and must not enter the learner's workbook.")
    other_raw.update(id="other_case", kind="transfer")
    workbook = Workbook(title="Period practice", activities=[first, Activity.model_validate(other_raw)])
    public = public_workbook(workbook)
    for activity in public["activities"]:
        assert "worked_solution" not in activity and "hint" not in activity
        assert "expression" not in activity["fields"][0]
    assert "steps" not in json.dumps(public)
    assert isinstance(workbook.activities[0].worked_solution, SolutionDocument)


@pytest.mark.asyncio
@pytest.mark.parametrize("tried", [False, True])
async def test_hint_solution_api_keeps_attempt_gate_and_plain_string(monkeypatch, tried):
    from app.api.v1 import practice as api
    from app.services.practice.contracts import SubmitRequest

    activity = Activity.model_validate(_raw_activity())
    row = SimpleNamespace(revision=1, attempts_json=[{"activity_id": activity.id}] if tried else [], hints_json=[])
    db = SimpleNamespace(commit=AsyncMock())
    monkeypatch.setattr(api, "_load", AsyncMock(return_value=(None, None, row, None)))
    monkeypatch.setattr(api, "_ready", lambda row: None)
    monkeypatch.setattr(api, "_activity", lambda row, workbook, activity_id: activity)
    monkeypatch.setattr(api, "view", lambda row: {"hints": row.hints_json})
    data = SubmitRequest(revision=1, request_id="request_123", activity_id=activity.id)
    if not tried:
        with pytest.raises(HTTPException) as failure:
            await api.get_hint("item", "step", data, db, SimpleNamespace(id="user"), solution=True)
        assert failure.value.status_code == 409
        db.commit.assert_not_awaited()
    else:
        result = await api.get_hint("item", "step", data, db, SimpleNamespace(id="user"), solution=True)
        assert result["hints"][0]["content"] == render_worked_solution(activity)
        assert isinstance(result["hints"][0]["content"], str)
        assert row.revision == 2
        db.commit.assert_awaited_once()
