"""Source-context boundaries for coefficient evidence, without provider calls."""
import pytest

from app.services.planning.lesson_review import (
    LessonReview, MathRoleCheck, _math_role_diagnostic, grounded_failures,
    numeric_span_occurrences,
)


def case(expression="base * height / 2"):
    return {"id": "guided", "data": [
        {"id": "base", "label": "Base", "value": 18},
        {"id": "height", "label": "Height", "value": 9},
    ], "fields": [{"id": "area", "label": "Area", "kind": "number", "expression": expression}]}


def diagnostic(source, *, quote=None, role="divisor", expression="base * height / 2"):
    evidence = MathRoleCheck(claim_id="n1", case_id="practice.guided", field_id="area",
                             role=role, coefficient=2, source_quote=source if quote is None else quote)
    owner = case(expression)
    return _math_role_diagnostic(evidence, source, owner, owner, set())


@pytest.mark.parametrize("source", [
    "Divide the product by 2.",
    "Divide the product by 2, before writing the answer.",
    "Divide the product by 2 for the triangle.",
    "բաժանելով արտադրյալը 2-ի։",
    "բաժանիր արտադրյալը 2-ի՝ ստանալու մակերեսը։",
])
def test_complete_exact_positive_operation_has_one_owned_coefficient(source):
    interval, error = diagnostic(source)
    assert error is None
    assert source[interval[0]:interval[1]] == "2"


@pytest.mark.parametrize("source", [
    "Divide the product by 2 before writing the answer.",
    "բաժանելով արտադրյալը 2-ի ստանում ենք մակերեսը։",
])
def test_complete_exact_continuation_is_not_a_clipped_unit_or_scale(source):
    interval, error = diagnostic(source)
    assert error is None
    assert source[interval[0]:interval[1]] == "2"


@pytest.mark.parametrize("operation", ["բաժանելը", "բաժանման"])
def test_observed_genitive_coefficient_followed_by_complete_division_form(operation):
    source = "2-ի " + operation + " քայլը։"
    interval, error = diagnostic(source, quote="2-ի " + operation)
    assert error is None
    assert source[interval[0]:interval[1]] == "2"


@pytest.mark.parametrize("operation", ["բաժանելը", "բաժանման"])
@pytest.mark.parametrize("source_template", [
    "2-ով {operation}։",                  # These observed forms require the genitive.
    "2-ի սմ {operation}։",              # A unit cannot occupy the operation gap.
    "2-ի million {operation}։",         # Nor a scale or an unverified word.
    "2-ի\n{operation}։",                # The observed operation must be contiguous.
    "Մի՛: 2-ի {operation}։",            # No clipped or full-quote negation.
    "2-ի {operation} և բազմապատկիր։",   # No second operation in this role quote.
])
def test_new_division_forms_do_not_accept_ambiguous_inflection_gap_or_operation(operation, source_template):
    source = source_template.format(operation=operation)
    interval, error = diagnostic(source)
    assert interval is None and error


@pytest.mark.parametrize("operation", ["բաժանելը", "բաժանման"])
def test_new_division_forms_do_not_allow_numeral_only_or_partial_word_quotes(operation):
    source = "2-ի " + operation + "։"
    for quote in ["2-ի", "2-ի " + operation[:-1]]:
        interval, error = diagnostic(source, quote=quote)
        assert interval is None and error


@pytest.mark.parametrize("suffix", ["unverifiedword", "նշանակում", "beforehand", "ստանումներ"])
@pytest.mark.parametrize("clipped", [False, True])
def test_unclassified_continuations_remain_rejected_even_with_complete_quote(suffix, clipped):
    source = "Divide the product by 2 " + suffix + "."
    interval, error = diagnostic(source, quote="Divide the product by 2" if clipped else source)
    assert interval is None and error


def test_canonical_inverse_eligibility_does_not_relabel_literal_division():
    source = "բաժանիր արտադրյալը 2-ի։"
    interval, error = diagnostic(source, role="inverse_multiplier")
    assert interval is None and "matching multiplication or division" in error
    interval, error = diagnostic(source, role="divisor")
    assert error is None and interval is not None


@pytest.mark.parametrize("suffix", ["cm", " cm", " hundred", " million", "%", " percent", " m²"])
@pytest.mark.parametrize("clipped", [False, True])
def test_unit_or_scale_cannot_be_hidden_by_clipping_the_quote(suffix, clipped):
    operation = "Divide the product by 2"
    source = operation + suffix + "."
    interval, error = diagnostic(source, quote=operation if clipped else source)
    assert interval is None and error


@pytest.mark.parametrize("prefix", ["Do not ", "Never ", "Don't ", "Don’t ", "You cannot ",
                                   "You mustn't ", "You mustn’t ", "Without ", "Neither ",
                                   "Do not, e.g., ", "Do not use method 2.1 to "])
@pytest.mark.parametrize("clipped", [False, True])
def test_english_negation_in_the_source_clause_cannot_be_clipped_away(prefix, clipped):
    operation = "divide the product by 2"
    source = prefix + operation + "."
    interval, error = diagnostic(source, quote=operation if clipped else source)
    assert interval is None and error


@pytest.mark.parametrize("prefix", [
    "Do not: ", "Do not\n", "Do not:\n", "Never:\n", "Don't\n", "Don’t:\n",
    "Do not:\nunder these conditions ", "Do not:\nWith no rounding, ",
    "Do not:\nunder these conditions:\n",
])
@pytest.mark.parametrize("clipped", [False, True])
def test_bare_negation_still_governs_operation_after_colon_or_newline(prefix, clipped):
    operation = "divide the product by 2"
    source = prefix + operation + "."
    interval, error = diagnostic(source, quote=operation if clipped else source)
    assert interval is None and error


@pytest.mark.parametrize("source", [
    "With no rounding, divide the product by 2.",
    "Without rounding, divide the product by 2.",
    "Divide the product by 2, without rounding.",
    "Divide the product by 2, with no rounding.",
])
@pytest.mark.parametrize("clipped", [False, True])
def test_complete_rounding_modifier_does_not_negate_division(source, clipped):
    quote = "divide the product by 2" if source.startswith(("With", "Without")) else "Divide the product by 2"
    interval, error = diagnostic(source, quote=quote if clipped else source)
    assert error is None and interval is not None


@pytest.mark.parametrize("source", [
    "With no rounding, do not divide the product by 2.",
    "Do not divide the product by 2, without rounding.",
    "Without rounding or dividing the product by 2.",
    "Without rounding, or dividing the product by 2.",
    "Without rounding; nor dividing the product by 2.",
    "With no rounding or dividing the product by 2.",
    "With no rounding, never divide the product by 2.",
])
@pytest.mark.parametrize("clipped", [False, True])
def test_rounding_modifier_does_not_hide_real_or_coordinated_negation(source, clipped):
    verb = "dividing" if "dividing" in source else "divide"
    quote = verb + " the product by 2"
    interval, error = diagnostic(source, quote=quote if clipped else source)
    assert interval is None and error


@pytest.mark.parametrize("role,operation,expression", [
    ("divisor", "divide the product by 2", "base * height / 2"),
    ("multiplier", "multiply the base by 2", "base * 2"),
    ("inverse_multiplier", "multiply the area by 2", "base * height / 2"),
    ("inverse_divisor", "divide the result by 2", "base * 2"),
])
def test_negation_guard_applies_to_each_prose_role(role, operation, expression):
    interval, error = diagnostic("Do not " + operation + ".", quote=operation,
                                 role=role, expression=expression)
    assert interval is None and error


@pytest.mark.parametrize("prefix", ["Մի ", "Մի՛ ", "ոչ թե ", "առանց "])
@pytest.mark.parametrize("clipped", [False, True])
def test_armenian_negation_remains_rejected(prefix, clipped):
    operation = "բաժանիր արտադրյալը 2-ի"
    source = prefix + operation + "։"
    interval, error = diagnostic(source, quote=operation if clipped else source)
    assert interval is None and error


@pytest.mark.parametrize("prefix", ["Մի՛\n", "Մի՛: ", "ոչ թե\n", "առանց:\n", "Մի՛:\nայստեղ:\n"])
@pytest.mark.parametrize("clipped", [False, True])
def test_armenian_bare_negative_introduction_survives_colon_and_newline(prefix, clipped):
    operation = "բաժանիր արտադրյալը 2-ի"
    source = prefix + operation + "։"
    interval, error = diagnostic(source, quote=operation if clipped else source)
    assert interval is None and error


def test_existing_armenian_operation_after_coefficient_has_same_negation_guard():
    source = "Մի՛: 2-ի բաժանումը։"
    interval, error = diagnostic(source, quote="2-ի բաժանումը")
    assert interval is None and error


@pytest.mark.parametrize("source,quote", [
    ("Do not copy the answer. Divide the product by 2.", "Divide the product by 2"),
    ("Never guess; divide the product by 2.", "divide the product by 2"),
    ("Do not copy the answer\ndivide the product by 2.", "divide the product by 2"),
    ("Մի՛ պատճենիր պատասխանը։ բաժանիր արտադրյալը 2-ի։", "բաժանիր արտադրյալը 2-ի"),
    ("Մի՛ պատճենիր պատասխանը\nբաժանիր արտադրյալը 2-ի։", "բաժանիր արտադրյալը 2-ի"),
])
def test_negative_instruction_in_a_previous_clause_does_not_negate_current_operation(source, quote):
    interval, error = diagnostic(source, quote=quote)
    assert error is None and interval is not None


def test_long_prefix_cannot_hide_english_negation_outside_the_bounded_quote():
    operation = "divide the product by 2"
    source = "Do not " + "under these conditions " * 30 + operation + "."
    interval, error = diagnostic(source, quote=operation)
    assert interval is None and error


@pytest.mark.parametrize("expression,role", [
    ("base * height / 100", "divisor"),
    ("base * height * 2", "divisor"),
    ("base + height / 2", "inverse_multiplier"),
])
def test_legitimate_prose_still_requires_the_correct_canonical_operator(expression, role):
    source = "Multiply the area by 2." if role == "inverse_multiplier" else "Divide the product by 2."
    interval, error = diagnostic(source, expression=expression, role=role)
    assert interval is None and error


@pytest.mark.parametrize("result", [81, 999])
def test_one_valid_coefficient_never_proves_an_additional_derived_result(result):
    source = f"Divide the product by 2; the area is {result}."
    evidence = MathRoleCheck(claim_id="n1", case_id="practice.guided", field_id="area",
                             role="divisor", coefficient=2, source_quote="Divide the product by 2")
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
                          contains_calculations=False, calculations=[], math_roles=[evidence])
    package = {"teaching_cases": [], "private_workbook": {"activities": [case()]}}
    errors = grounded_failures(review, {"lesson_content": source}, package)
    assert errors
    assert any("unverified values" in error or "coverage is incomplete" in error for error in errors)


def grounded_operation_errors(activity, *, expected_claim_ids=None, quote="divide the product by 2"):
    package = {"teaching_cases": [], "private_workbook": {"activities": [activity]}}
    records = numeric_span_occurrences({}, package)
    evidence = [MathRoleCheck(claim_id=record.claim_id, case_id="practice.guided", field_id="area",
                             role="divisor", coefficient=2, source_quote=quote)
                for record in records if expected_claim_ids is None or record.claim_id in expected_claim_ids]
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
                          contains_calculations=False, calculations=[], math_roles=evidence)
    return records, grounded_failures(review, {}, package, expected_claim_ids=expected_claim_ids)


@pytest.mark.parametrize("prefix", ["Do not: ", "Do not\n", "Do not:\n", "Never:\n", "Don't\n"])
def test_full_grounding_uses_owning_source_when_inventory_splits_negative_prefix(prefix):
    activity = case() | {"instructions": prefix + "divide the product by 2."}
    records, errors = grounded_operation_errors(activity)
    assert len(records) == 1
    assert records[0].source == activity["instructions"]
    assert any("mathematical role invalid" in error and "negated" in error for error in errors)


@pytest.mark.parametrize("prefix", ["Մի՛\n", "Մի՛: ", "ոչ թե\n", "առանց:\n"])
def test_full_grounding_preserves_armenian_negative_introduction(prefix):
    operation = "բաժանիր արտադրյալը 2-ի"
    activity = case() | {"instructions": prefix + operation + "."}
    records, errors = grounded_operation_errors(activity, quote=operation)
    assert len(records) == 1
    assert any("mathematical role invalid" in error and "negated" in error for error in errors)


@pytest.mark.parametrize("separator", ["։ ", "\n", "; "])
def test_full_grounding_preserves_independent_armenian_instruction(separator):
    operation = "բաժանիր արտադրյալը 2-ի"
    activity = case() | {"instructions": "Մի՛ պատճենիր պատասխանը" + separator + operation + "."}
    _, errors = grounded_operation_errors(activity, quote=operation)
    assert errors == []


@pytest.mark.parametrize("negative_first", [False, True])
def test_equal_span_text_does_not_select_a_different_occurrences_context(negative_first):
    operation = "divide the product by 2."
    pieces = ["Do not\n" + operation, operation] if negative_first else [operation, "Do not\n" + operation]
    activity = case() | {"instructions": "\n".join(pieces)}
    records, errors = grounded_operation_errors(activity)
    assert len(records) == 2 and records[0].span == records[1].span
    assert records[0].start != records[1].start
    negative_id = records[0 if negative_first else 1].claim_id
    positive_id = records[1 if negative_first else 0].claim_id
    assert any(error.startswith(negative_id + ":") and "negated" in error for error in errors)
    assert not any(error.startswith(positive_id + ":") for error in errors)
    _, scoped_errors = grounded_operation_errors(activity, expected_claim_ids={positive_id})
    assert scoped_errors == []


@pytest.mark.parametrize("source", [
    "With no rounding, divide the product by 2.",
    "Without rounding, divide the product by 2.",
    "divide the product by 2, without rounding.",
    "Do not copy the answer. divide the product by 2.",
    "Do not copy the answer\ndivide the product by 2.",
    "Never guess; divide the product by 2.",
])
def test_full_grounding_preserves_positive_context_controls(source):
    _, errors = grounded_operation_errors(case() | {"instructions": source})
    assert errors == []


def test_negation_context_cannot_cross_owning_source_fields():
    _, errors = grounded_operation_errors(case() | {
        "instructions": "Do not", "hint": "divide the product by 2.",
    })
    assert errors == []


@pytest.mark.parametrize("source_start", [-1, 0, 1, True])
def test_supplied_source_context_must_match_exact_inventory_location(source_start):
    span = "divide the product by 2."
    evidence = MathRoleCheck(claim_id="n1", case_id="practice.guided", field_id="area",
                             role="divisor", coefficient=2, source_quote=span)
    interval, error = _math_role_diagnostic(evidence, span, case(), case(), set(),
                                          source="Do not\n" + span, source_start=source_start)
    assert interval is None and "exact owning source location" in error
