"""Explicit math roles prove formula syntax, never erase measured quantities."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import (
    LessonReview, MathRoleCheck, ReviewEvidencePatch, grounded_failures, numeric_spans, review_lesson,
)
from app.services.planning.package_review import review_package
from tests.lesson_package_fixtures import package_payload


def package_for(source="", expression="base * height / 2", *, same_neighbor=False):
    data = package_payload()
    activity = data["workbook"]["activities"][0]
    activity["data"] = [{"id": "base", "label": "Base", "value": 18},
                        {"id": "height", "label": "Height", "value": 9},
                        {"id": "decoy", "label": "Unrelated length", "value": 18}]
    activity["fields"] = [{"id": "area", "kind": "number", "label": "Area", "expression": expression}]
    activity["worked_solution"] = source + "\nExplain why the operation applies to the supplied shape."
    if same_neighbor:
        neighbor = data["workbook"]["activities"][1]
        neighbor["data"] = copy.deepcopy(activity["data"])
        neighbor["fields"] = copy.deepcopy(activity["fields"])
    return LessonPackage.model_validate(data)


def role(*, span="n1", quote="(b × h) / 2", kind="symbolic_formula", coefficient=2,
         bindings=None, case="practice.guided", field="area"):
    return {"claim_id": span, "case_id": case, "field_id": field,
            "role": kind, "coefficient": coefficient, "source_quote": quote,
            "symbol_bindings": ({"b": "base", "h": "height"}
                                if bindings is None and kind == "symbolic_formula" else bindings or {})}


def approved(*roles):
    return {"acceptable": True, "issues": [], "contains_calculations": False,
            "calculations": [], "math_roles": list(roles)}


def failures(package, roles=(), *, lesson=None):
    verdict = LessonReview.model_validate({**approved(*roles), "practice_minutes": 40})
    return grounded_failures(verdict, lesson or {}, package.review_context()) + verdict.failures()


@pytest.mark.parametrize("source,expression,evidence", [
    ("Use (b × h) / 2 for the triangle.", "base * height / 2", role()),
    ("Օգտագործիր (հիմք × բարձրություն) / 2 բանաձևը։", "base * height / 2",
     role(quote="(հիմք × բարձրություն) / 2", bindings={"հիմք": "base", "բարձրություն": "height"})),
    ("Explain why we divide by 2 for this operation.", "base * height / 2",
     role(kind="divisor", quote="divide by 2")),
    ("To reverse the operation, multiply the area by 2.", "base * height / 2",
     role(kind="inverse_multiplier", quote="multiply the area by 2")),
    ("To perform the operation, multiply by 2.", "base * 2",
     role(kind="multiplier", quote="multiply by 2")),
    ("To reverse the operation, divide by 2.", "base * 2",
     role(kind="inverse_divisor", quote="divide by 2")),
    ("For the proportion, use b / 100.", "base / 100",
     role(quote="b / 100", coefficient=100, bindings={"b": "base"})),
])
def test_explicit_role_proves_only_owned_formula_coefficient(source, expression, evidence):
    # Public prose has no implicit private-field metadata exemption. Every role
    # here must be supplied by the independent reviewer and checked explicitly.
    package = package_for(expression=expression)
    lesson = {"lesson_content": source}
    assert numeric_spans(lesson, package.review_context()) == {"n1": source}
    assert failures(package, lesson=lesson)
    assert failures(package, [evidence], lesson=lesson) == []


@pytest.mark.parametrize("change", [
    {"claim_id": "unknown"}, {"case_id": "practice.missing"}, {"field_id": "missing"},
    {"coefficient": 1}, {"symbol_bindings": {"b": "height", "h": "base"}},
    {"symbol_bindings": {"b": "decoy", "h": "height"}},  # Equal value is not field provenance.
    {"symbol_bindings": {"b": "base", "h": "base"}},
    {"symbol_bindings": {"b": "base"}},
    {"symbol_bindings": {"b": "base", "h": "height", "unused": "decoy"}},
    {"source_quote": "(b * h) / 2"},  # Equivalent syntax is not an exact quote.
    {"source_quote": "2 / b", "symbol_bindings": {"b": "base"}},
])
def test_wrong_symbol_or_owner_binding_never_uses_numeric_coincidence(change):
    package = package_for("Use (b × h) / 2 for this shape.")
    assert failures(package, [{**role(), **change}])


def test_identical_neighbor_formula_cannot_authorize_another_activitys_source():
    package = package_for("Use (b × h) / 2 for this shape.", same_neighbor=True)
    assert failures(package, [role(case="practice.transfer")])
    assert failures(package, [role()]) == []


@pytest.mark.parametrize("source", [
    "Use (b × h) / 2, then compare with (b × h) / 2 for the same shape.",
    "Use base * (b × h) / 2 for this shape.",  # Quote must cover the whole expression.
    "Use (b × h) / 2 + height for this shape.",
    "Use -(b × h) / 2 for this shape.",
    "Use sqrt((b × h) / 2) for this shape.",
    "Use (b × h) / 2 / base for this shape.",
    "Use (b × h) / 2, while the unrelated height is 2.",
    "Use (b × h) / 2, while the unrelated charge is 7.",
])
def test_role_quote_is_unique_complete_and_never_erases_other_occurrences(source):
    assert failures(package_for(source), [role()])


@pytest.mark.parametrize("expression,evidence", [
    ("base * height / 100", role(kind="divisor", quote="divide by 2")),
    ("base / 2 + height", role(kind="inverse_multiplier", quote="multiply by 2")),
    ("base * 2 + height", role(kind="inverse_divisor", quote="divide by 2")),
    ("base * height / 2", role(kind="multiplier", quote="multiply by 2")),
    ("base * 2", role(kind="divisor", quote="divide by 2")),
])
def test_direct_and_inverse_roles_require_correct_canonical_operator_position(expression, evidence):
    package = package_for(expression=expression)
    assert failures(package, [evidence], lesson={"lesson_content": f"Explain why we {evidence['source_quote']} here."})


@pytest.mark.parametrize("quote", ["is 2", "value 2", "2", "2 and 2"])
def test_bare_values_and_multiple_numbers_cannot_be_math_roles(quote):
    if len(quote) < 3:
        with pytest.raises(ValueError):
            MathRoleCheck.model_validate(role(kind="divisor", quote=quote))
    else:
        assert failures(package_for(expression="base / 2"), [role(kind="divisor", quote=quote)],
                        lesson={"lesson_content": f"The quantity {quote}."})


@pytest.fixture(autouse=True)
def telemetry(monkeypatch):
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    return record


async def run_review(kind, source, initial, patch=None):
    package = package_for(source)
    if kind == "final":
        initial = {**initial, "practice_minutes": 40, "advisories": ["Keep the original editorial note."]}
    responses = [LLMResponse(data=copy.deepcopy(initial))]
    if patch is not None:
        responses.append(LLMResponse(data=copy.deepcopy(patch)))
    client = SimpleNamespace(model="offline", generate_json=AsyncMock(side_effect=responses))
    factory = Mock(return_value=client)
    if kind == "preflight":
        result = await review_package(package, {}, {}, client_factory=factory)
    else:
        result = await review_lesson({"lesson_content": "Use the supplied method and explain each assumption."},
            context={"lesson_package": package.review_context()}, client_factory=factory)
    return result, client


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["preflight", "final"])
async def test_scoped_role_patch_retains_valid_role_and_original_verdict(kind):
    source = "To reverse the operation, multiply the area by 2.\nUse (b × h) / 2 for the triangle."
    retained = role(kind="inverse_multiplier", quote="multiply the area by 2")
    broken = role(span="n2", case="practice.unknown")
    replacement = role(span="n2")
    (errors, response, _), client = await run_review(kind, source, approved(retained, broken),
                                                    {"math_roles": [replacement]})
    assert errors == [] and response.error is None
    assert response.data["acceptable"] is True and response.data["issues"] == []
    assert response.data["math_roles"] == [retained, replacement]
    if kind == "final":
        assert response.data["practice_minutes"] == 40
        assert response.data["advisories"] == ["Keep the original editorial note."]
    assert client.generate_json.await_count == 2
    repair = client.generate_json.call_args.kwargs
    assert issubclass(repair["output_model"], ReviewEvidencePatch)
    payload = json.loads(repair["user_prompt"])
    assert set(payload["numeric_spans"]) == {"n2"}
    assert payload["prior_evidence"]["math_roles"] == [broken]


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["preflight", "final"])
async def test_negative_semantic_verdict_is_terminal_even_with_unverified_role(kind):
    initial = {**approved(role(case="practice.unknown")), "acceptable": False,
               "issues": ["The activity teaches the wrong operation."]}
    (errors, response, _), client = await run_review(kind, "Use (b × h) / 2 for the triangle.", initial)
    assert errors and "The activity teaches the wrong operation." in errors
    assert response.data["acceptable"] is False and client.generate_json.await_count == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("kind", ["preflight", "final"])
@pytest.mark.parametrize("patch", [
    {"math_roles": [role()], "acceptable": True},
    {"math_roles": [role(case="practice.unknown")]},
    {"math_roles": [role(span="n999")]},
    {},
])
async def test_invalid_role_patch_stops_after_existing_correction_without_approval(kind, patch):
    (errors, response, _), client = await run_review(kind, "Use (b × h) / 2 for the triangle.", approved(), patch)
    assert errors and response.error and client.generate_json.await_count == 2
