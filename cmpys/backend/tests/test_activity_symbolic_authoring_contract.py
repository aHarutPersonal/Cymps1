"""A clearer authoring shape still needs exact independent mathematical proof."""
import copy
from unittest.mock import AsyncMock

import pytest

from app.services.llm.prompt_loader import load_and_render
from app.services.planning import package_builder
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import (
    MathRoleCheck, compiled_solution_evidence, grounded_failures,
    math_quote_candidates, numeric_spans,
)
from tests.test_compiled_solution_evidence import whole_review
from tests.test_math_role_evidence import package_for
from tests.test_staged_package_builder import Factory, components, run


SOURCE = (
    "Here b denotes the supplied base length and h its perpendicular height.\n\n"
    "(b × h) / 2\n\n"
    "The division follows from the relationship between a triangle and a "
    "parallelogram sharing that base and height."
)


def structured_source(source=SOURCE, expression="base * height / 2"):
    value = package_for(expression=expression).model_dump(mode="json")
    value["workbook"]["activities"][0]["worked_solution"] = {
        "version": 1, "steps": [{"field_id": "area", "explanation": source}],
    }
    return LessonPackage.model_validate(value)


def reviewed(package, *, quote="(b × h) / 2", bindings=None):
    context = package.review_context()
    spans = numeric_spans({}, context)
    claim = next(key for key, span in spans.items() if span == quote)
    review = whole_review(compiled_solution_evidence({}, context))
    role = MathRoleCheck(claim_id=claim, case_id="practice.guided", field_id="area",
        role="symbolic_formula", coefficient=2, source_quote=quote,
        symbol_bindings=bindings or {"b": "base", "h": "height"})
    review.math_roles = [role]
    return review, claim, spans


def test_standalone_formula_keeps_natural_explanation_and_requires_explicit_binding():
    package = structured_source()
    context = package.review_context()
    before = copy.deepcopy(context)
    review, claim, spans = reviewed(package)
    assert math_quote_candidates(spans)[claim][0]["source_quote"] == "(b × h) / 2"
    verified = review.model_copy(deep=True)
    assert grounded_failures(verified, {}, context) == []
    assert verified.failures() == []
    assert SOURCE in context["private_workbook"]["activities"][0]["worked_solution"]
    assert context == before
    review.math_roles = []
    assert grounded_failures(review, {}, context)  # Compiler owns only its rendered numeric equation.


@pytest.mark.parametrize("bindings", [
    {"b": "height", "h": "base"}, {"b": "decoy", "h": "height"},
    {"b": "base", "h": "base"},
])
def test_format_never_approves_wrong_or_equal_value_symbol_ownership(bindings):
    package = structured_source()
    review, _, _ = reviewed(package, bindings=bindings)
    assert grounded_failures(review, {}, package.review_context())


def test_extra_quantity_and_algebraic_rewrite_do_not_gain_formula_coverage():
    package = structured_source(SOURCE + "\n\nAn additional measurement is 7 cm.")
    review, _, _ = reviewed(package)
    assert grounded_failures(review, {}, package.review_context())
    package = structured_source(SOURCE.replace("(b × h) / 2", "b × (h / 2)"))
    review, _, _ = reviewed(package, quote="b × (h / 2)")
    assert grounded_failures(review, {}, package.review_context())


def test_multicoefficient_formula_retains_unsupported_role_obligation():
    quote = "(b × h) / 2 / 100"
    package = structured_source(SOURCE.replace("(b × h) / 2", quote), "base * height / 2 / 100")
    review, _, _ = reviewed(package, quote=quote)
    assert grounded_failures(review, {}, package.review_context())


@pytest.mark.asyncio
async def test_initial_activity_request_gets_conditional_format_without_new_calls_or_private_context(monkeypatch):
    usage = AsyncMock(return_value=True)
    monkeypatch.setattr(package_builder, "record_llm_response", usage)
    seed, activities = components(numeric=True)
    factory = Factory({"seed": [seed], **{key: [value] for key, value in activities.items()}})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    assert len(factory.requests) == usage.await_count == 3
    assert [options["max_tokens"] for options in factory.options] == [2200, 4000, 4000]
    assert all(options["timeout"] == 90 and not options["allow_fallback"] for options in factory.options)
    assert response.effective_parameters["stage_timeout_seconds"] == 240
    assert response.effective_parameters["shared_correction_used"] is False
    prompt = load_and_render("lesson_activity_generate.txt", {})
    assert "that field's\nexpression contains exactly one literal number, a positive factor or divisor of\n1, 2 or 100" in prompt
    assert "no function call" in prompt
    assert "same field's operators and grouping" in prompt
    assert "This presentation does not approve the formula" in prompt
    assert "Preserve separate inverse steps, intermediate results" in prompt
    assert "do not force multi-coefficient formulas" in prompt
    assert "never change digits to words or omit\nreasoning to avoid numerical verification" in prompt
    for key, request, payload in factory.requests:
        if key == "seed": continue
        assert prompt in request["system_prompt"]
        assert "amount * 2" not in request["user_prompt"]  # Its private formula is authored in the response.
        assert "private_workbook" not in payload
        assert payload["activity_brief"]["id"] == key
