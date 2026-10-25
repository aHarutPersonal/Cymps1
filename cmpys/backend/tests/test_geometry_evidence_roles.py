"""Formula syntax is not an extra quantity; unrelated quantities stay checked."""
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
from app.services.planning.package_review import review_package
from tests.lesson_package_fixtures import package_payload


def triangle_package(solution):
    payload = package_payload()
    activity = payload["workbook"]["activities"][0]
    activity["data"] = [{"id": "base", "label": "Base", "value": 18},
                        {"id": "height", "label": "Height", "value": 9}]
    activity["fields"].append({"id": "area", "kind": "number", "label": "Area",
                               "expression": "base * height / 2"})
    activity["worked_solution"] = solution + "\nExplain why the geometric operation fits the original shape."
    return LessonPackage.model_validate(payload)


def check(*, expression="base * height / 2", value=81, span="n1"):
    return {"claim_ids": [span], "case_id": "practice.guided",
            "expression": expression, "claimed_result": value}


def review(*checks):
    return LessonReview.model_validate({"acceptable": True, "issues": [], "practice_minutes": 40,
        "contains_calculations": bool(checks), "calculations": [
            {**entry, "location": ", ".join(entry["claim_ids"])} for entry in checks]})


@pytest.mark.parametrize("source,checks", [
    ("162 / 2 = 81.", [check()]),
    ("18 × 9 / 2 = 81.", [check()]),
    ("81 × 2 = 162, then 162 / 9 = 18.", [
        check(expression="(base * height / 2) * 2", value=162),
        check(expression="base * height / height", value=18)]),
])
def test_exact_displayed_partial_evaluation_needs_no_invented_coefficient_proof(source, checks):
    package = triangle_package(source)
    verdict = review(*checks)
    assert not grounded_failures(verdict, {}, package.review_context())
    assert not verdict.failures()


@pytest.mark.parametrize("source", [
    "999 - 918 = 81.",  # Same result is insufficient: operation tree differs.
    "(999 - 837) / 2 = 81.",  # A nested invented intermediate also differs.
    "160 / 2 = 81.",  # The displayed intermediate is wrong.
    "162 / 3 = 81.",  # A changed divisor cannot inherit the proof's coefficient.
    "162 / 2 = 18, while the area is 81.",  # Another correct answer is not this equality's RHS.
    "162 / 2 = 9, while the area is 81.",
    "162 / 2 = 81 = 18.",
    "162 / 2 = 81%.",
    "162 / 2 = 81 percent.",
    "162 / 2 = 81 hundred.",
    "162 / 2 = 81 thousand.",
    "162 / 2 = 81 cm.",
    "162 / 2 = 81, with an unrelated charge of 2.",
    "162 / 2 = 81, with an unrelated rate of 162.",
])
def test_arbitrary_or_incorrect_expression_and_separate_equal_quantity_remain_unverified(source):
    verdict = review(check())
    assert grounded_failures(verdict, {}, triangle_package(source).review_context())


@pytest.mark.parametrize("proof", [
    check(expression="base * height", value=81),
    check(expression="base * height / 2", value=80),
    {**check(), "case_id": "practice.unknown"},
])
def test_wrong_review_proof_cannot_authorize_displayed_numeric_roles(proof):
    verdict = review(proof)
    failures = grounded_failures(verdict, {}, triangle_package("162 / 2 = 81.").review_context())
    assert failures or verdict.failures()


@pytest.mark.parametrize("source", [
    "Area = (base × height) / 2, using perpendicular lengths.",
    "Մակերեսը = (հիմք × բարձրություն) / 2, ըստ եռանկյան կառուցվածքի։",
    "Explain why we divide by 2 when finding the triangle area.",
    "Բացատրիր, թե ինչու ենք բաժանում 2-ի։",
    "Ստուգիր լուծումը՝ բաժանելով 2-ի։",
    "Նկատիր, թե ինչ կփոխվի, եթե բաժանես 2-ով։",
])
def test_formula_coefficients_remain_in_inventory_until_independently_bound(source):
    package = triangle_package(source)
    if "հիմք" in source:
        package.workbook.activities[0].data[0].label = "Հիմք"
        package.workbook.activities[0].data[1].label = "Բարձրություն"
    assert len(numeric_spans({}, package.review_context())) == 1


@pytest.mark.parametrize("source", [
    "Area = (base × height) / 3.",
    "Area = (base + height) / 2.",
    "Area = (base × base) / 2.",
    "Area = (base × height) * 2.",
    "Area = (base × height) / 2 * base.",
    "Area = height * (base × height) / 2.",
    "Area = (hypotenuse × height) / 2.",
    "Area = (cost × revenue) / 2.",
    "Մակերեսը = (գին × եկամուտ) / 2։",
    "The height is 2.",
    "Divide by 3 when finding the triangle area.",
    "Բացատրիր, թե ինչու ենք բաժանում 3-ի։",
    "Նկատիր, թե ինչ կփոխվի, եթե բաժանես -2-ով։",
    "Բաժանում 2-ի, երբ բարձրությունը 2 է։",
    "Մակերեսը = (հիմք × բարձրություն) / 2, իսկ բարձրությունը 2 է։",
])
def test_wrong_formula_constant_or_separate_quantity_is_still_in_inventory(source):
    package = triangle_package(source)
    assert len(numeric_spans({}, package.review_context())) == 1


def test_formula_coefficient_is_owned_by_its_activity_not_a_neighbor():
    package = triangle_package("Explain why we divide by 2 for this triangle.")
    package.workbook.activities[1].worked_solution = "Explain why we divide by 2 for this different problem."
    spans = numeric_spans({}, package.review_context())
    assert len(spans) == 2
    assert spans["n2"] == package.workbook.activities[1].worked_solution


def test_symbolic_operand_label_must_resolve_to_exactly_one_owned_datum():
    package = triangle_package("Area = (length × height) / 2.")
    package.workbook.activities[0].data[0].label = "Length"
    assert numeric_spans({}, package.review_context())
    package.workbook.activities[0].data[1].label = "Length"
    assert numeric_spans({}, package.review_context())


@pytest.mark.parametrize("source", [
    "Round to 1 decimal place.",
    "կլորացում պահանջվում է մինչև 1 նշանակալի թվանշան տասնորդականից հետո։",
])
def test_explicit_decimal_precision_is_metadata_when_it_preserves_the_actual_grading_contract(source):
    package = triangle_package(source)
    assert numeric_spans({}, package.review_context()) == {}


@pytest.mark.parametrize("source", [
    "Round to 1 significant figure.",
    "կլորացում պահանջվում է մինչև 1 նշանակալի թվանշան։",
    "Round to 7 decimal places.",
    "Round to -1 decimal places.",
    "Round to 1 decimal place; the margin is 1.",
])
def test_ambiguous_precision_and_separate_values_keep_their_numeric_evidence_requirement(source):
    assert numeric_spans({}, triangle_package(source).review_context())


def test_decimal_precision_incompatible_with_any_answer_tolerance_stays_rejected():
    package = triangle_package("Round to 1 decimal place.")
    package.workbook.activities[0].data[0].value = 7.88  # Area35.46 rounds to35.5.
    assert numeric_spans({}, package.review_context())
    package.workbook.activities[0].fields[-1].tolerance = .05
    assert numeric_spans({}, package.review_context()) == {}


def test_decimal_precision_uses_same_float_boundary_as_actual_fixed_grader():
    from app.services.practice.contracts import grade_fixed
    package = triangle_package("Round to 1 decimal place.")
    activity = package.workbook.activities[0]
    activity.data[0].value = .7  # 3.15 with floating point distance to3.2 above.05.
    activity.fields = [activity.fields[-1]]
    activity.fields[0].tolerance = .05
    assert grade_fixed(activity, {"guided.area": "3.2"})[0]["passed"] is False
    assert numeric_spans({}, package.review_context())


def test_typed_raw_fact_binding_can_also_have_redundant_untyped_id():
    package = triangle_package("The supplied lengths are 18 and 9.")
    verdict = review()
    verdict.literal_fact_ids = ["n1"]
    from app.services.planning.lesson_review import LiteralFactCheck
    verdict.literal_facts = [LiteralFactCheck(claim_id="n1", case_id="practice.guided",
                                            datum_ids=["base", "height"])]
    assert not grounded_failures(verdict, {}, package.review_context())


@pytest.mark.parametrize("source,datums", [
    ("The supplied lengths are 18 and 9, with another value 2.", ["base", "height"]),
    ("The supplied lengths are 18 and 9.", ["base"]),
    ("The total is 18.", ["base"]),
    ("The difference is 9.", ["height"]),
])
def test_redundant_fact_id_never_supplies_missing_or_derived_evidence(source, datums):
    package = triangle_package(source)
    verdict = review()
    verdict.literal_fact_ids = ["n1"]
    from app.services.planning.lesson_review import LiteralFactCheck
    verdict.literal_facts = [LiteralFactCheck(claim_id="n1", case_id="practice.guided", datum_ids=datums)]
    assert grounded_failures(verdict, {}, package.review_context())


@pytest.mark.asyncio
async def test_correct_geometry_first_preflight_needs_no_paid_evidence_or_content_retry(monkeypatch):
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    client = SimpleNamespace(model="offline", generate_json=AsyncMock(return_value=LLMResponse(data={
        "acceptable": True, "issues": [], "contains_calculations": True, "calculations": [check()],
    })))
    failures, response, _ = await review_package(triangle_package("162 / 2 = 81."), {}, {},
                                                client_factory=Mock(return_value=client))
    assert failures == [] and response.error is None
    assert client.generate_json.await_count == 1
    record.assert_not_awaited()


@pytest.mark.parametrize("unit,source", [
    ("cm²", "162 / 2 = 81 cm²."),
    ("սմ²", "162 / 2 = 81սմ²."),
    ("սմ²", "162 / 2 = 81 սմ²."),
])
def test_exact_canonical_result_unit_binds_same_equality_and_precision(unit, source):
    package = triangle_package(source)
    package.workbook.activities[0].fields[-1].unit = unit
    verdict = review(check())
    assert not grounded_failures(verdict, {}, package.review_context())
    assert not verdict.failures()


@pytest.mark.parametrize("source", [
    "162 / 2 = 81 cm²XYZ.", "162 / 2 = 81 cm² hundred.",
    "162 / 2 = 81 cm²%.", "162 / 2 = 81 cm.",
    "162 / 2 = 81 mm².", "162 / 2 = 18 cm², while the area is 81 cm².",
    "162 / 2 = 81 cm², with another area 999cm².",
])
def test_wrong_or_scaled_unit_cannot_approve_a_scalar_prefix(source):
    package = triangle_package(source)
    package.workbook.activities[0].fields[-1].unit = "cm²"
    assert grounded_failures(review(check()), {}, package.review_context())


def test_equal_result_from_different_canonical_expression_does_not_supply_unit():
    package = triangle_package("162 / 2 = 81 cm².")
    package.workbook.activities[0].fields[-1].unit = "cm²"
    # Numerically equal does not provide the canonical result's unit contract.
    verdict = review(check(expression="height * height"))
    assert grounded_failures(verdict, {}, package.review_context())


def test_attached_unrecognized_unit_is_in_numeric_inventory():
    package = triangle_package("The area is 999զզ.")
    assert numeric_spans({}, package.review_context())
    assert grounded_failures(review(), {}, package.review_context())


@pytest.mark.parametrize("source,quote,role_name", [
    ("Multiply the area by 2%.", "Multiply the area by 2", "inverse_multiplier"),
    ("Multiply the area by 2 hundred.", "Multiply the area by 2 hundred", "inverse_multiplier"),
    ("Multiply the area by 2cm².", "Multiply the area by 2", "inverse_multiplier"),
    ("Multiply the area by 2 * base.", "Multiply the area by 2", "inverse_multiplier"),
    ("Area = (cost × revenue) / 2.", "/ 2", "divisor"),
    ("Area = height * (b × h) / 2.", "/ 2", "divisor"),
])
def test_explicit_role_never_consumes_scaled_or_operator_only_prefix(source, quote, role_name):
    from app.services.planning.lesson_review import MathRoleCheck
    package = triangle_package(source)
    verdict = review()
    verdict.math_roles = [MathRoleCheck(claim_id="n1", case_id="practice.guided", field_id="area",
        role=role_name, coefficient=2, source_quote=quote)]
    assert grounded_failures(verdict, {}, package.review_context())


@pytest.mark.parametrize("suffix", ["սմ²", "cm²", "զզ"])
def test_valid_role_never_hides_extra_attached_unit_quantity(suffix):
    from app.services.planning.lesson_review import MathRoleCheck
    package = triangle_package(f"Multiply the area by 2, with another area 999{suffix}.")
    package.workbook.activities[0].fields[-1].unit = "սմ²"
    verdict = review()
    verdict.math_roles = [MathRoleCheck(claim_id="n1", case_id="practice.guided", field_id="area",
        role="inverse_multiplier", coefficient=2, source_quote="Multiply the area by 2")]
    assert grounded_failures(verdict, {}, package.review_context())


def test_armenian_reverse_division_and_inverse_multiplication_are_explicit_roles():
    from app.services.planning.lesson_review import MathRoleCheck
    for source, quote, name in [
        ("Բացատրիր 2-ի բաժանումը։", "2-ի բաժանումը", "divisor"),
        ("Մակերեսը բազմապատկես 2-ով և բաժանես հիմքին։", "բազմապատկես 2-ով", "inverse_multiplier"),
    ]:
        verdict = review()
        verdict.math_roles = [MathRoleCheck(claim_id="n1", case_id="practice.guided", field_id="area",
            role=name, coefficient=2, source_quote=quote)]
        assert not grounded_failures(verdict, {}, triangle_package(source).review_context())


@pytest.mark.parametrize("suffix", ["սմ²", "cm²", "զզ"])
@pytest.mark.parametrize("evidence", ["metadata", "raw_fact", "other_calculation"])
def test_attached_unbound_quantity_cannot_hide_via_any_evidence_class(suffix, evidence):
    from app.services.planning.lesson_review import LiteralFactCheck
    source = f"The area is 999{suffix}."
    if evidence == "other_calculation":
        source = f"The area is 81, and the unrelated amount is 999{suffix}."
    package = triangle_package(source)
    package.workbook.activities[0].fields[-1].unit = "սմ²"
    verdict = review(check()) if evidence == "other_calculation" else review()
    if evidence == "metadata":
        verdict.literal_fact_ids = ["n1"]
    elif evidence == "raw_fact":
        verdict.literal_facts = [LiteralFactCheck(claim_id="n1", case_id="practice.guided", datum_ids=["base"])]
    assert grounded_failures(verdict, {}, package.review_context())


@pytest.mark.parametrize("ending", [" hundred.", " thousand.", "%.", "XYZ.", " / base."])
def test_attached_declared_unit_source_literal_is_not_a_scaled_prefix(ending):
    package = triangle_package("Area is 81cm²" + ending)
    package.workbook.activities[0].fields[-1].unit = "cm²"
    assert grounded_failures(review(check()), {}, package.review_context())


def test_attached_declared_unit_plain_source_result_is_checkable():
    package = triangle_package("Area is 81cm².")
    package.workbook.activities[0].fields[-1].unit = "cm²"
    assert not grounded_failures(review(check()), {}, package.review_context())


def test_legacy_field_without_id_cannot_supply_a_typed_formula_role():
    from app.services.planning.lesson_review import MathRoleCheck
    context = triangle_package("Use (b × h) / 2 for this shape.").review_context()
    context["private_workbook"]["activities"][0]["fields"][-1].pop("id")
    verdict = review()
    verdict.math_roles = [MathRoleCheck(claim_id="n1", case_id="practice.guided", field_id="area",
        role="symbolic_formula", coefficient=2, source_quote="(b × h) / 2",
        symbol_bindings={"b": "base", "h": "height"})]
    assert grounded_failures(verdict, {}, context)
