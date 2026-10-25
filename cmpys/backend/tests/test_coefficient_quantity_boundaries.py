"""A role cannot clip quantity qualifiers from its exact owning source."""
import pytest

from app.services.planning.lesson_review import (
    LessonReview, MathRoleCheck, _math_role_diagnostic, grounded_failures,
    numeric_span_occurrences,
)
from tests.test_coefficient_source_boundaries import case


OPERATION = "Divide the product by 2"


def role(quote, claim_id="n1"):
    return MathRoleCheck(claim_id=claim_id, case_id="practice.guided", field_id="area",
                         role="divisor", coefficient=2, source_quote=quote)


def check(source, quote):
    owner = case()
    return _math_role_diagnostic(role(quote), source, owner, owner, set())


@pytest.mark.parametrize("suffix", [
    " (cm)", "(hundred)", " [kg]", " {million}", " （cm）",
    " (unfamiliar_unit)", " (check the diagram)",
])
@pytest.mark.parametrize("clipped", [False, True])
def test_adjacent_parenthetical_quantity_is_not_approved_as_dimensionless(suffix, clipped):
    source = OPERATION + suffix + "."
    interval, error = check(source, OPERATION if clipped else source)
    assert interval is None and "parenthetical quantity qualifier" in error


@pytest.mark.parametrize("suffix", [
    " and a half", " and one-half", " and three quarters", " plus one third",
    " and a hundredth", " and ½", " ½", "½", " 1/2", " and 1/2", " and 1⁄2",
    " և կես", " ու կես", " և մեկ երրորդ", " և երեք քառորդ",
])
@pytest.mark.parametrize("clipped", [False, True])
def test_mixed_fraction_is_not_the_integer_coefficient(suffix, clipped):
    source = OPERATION + suffix + "."
    interval, error = check(source, OPERATION if clipped else source)
    assert interval is None and error


@pytest.mark.parametrize("suffix", [" (սմ)", " (հարյուր)", " և կեսի", " և մեկ երրորդի"])
@pytest.mark.parametrize("clipped", [False, True])
def test_armenian_inflection_cannot_hide_parenthetical_or_fractional_quantity(suffix, clipped):
    operation = "բաժանիր արտադրյալը 2-ի"
    source = operation + suffix + "։"
    interval, error = check(source, operation if clipped else source)
    assert interval is None and error


@pytest.mark.parametrize("suffix", [
    ".", ", then check the diagram.", " before writing the answer.",
    " and then check the diagram.", " and a half-page note explains the method.",
    ". (A separate note checks the diagram.)", ". A half is a useful comparison.",
    "; a half is a useful comparison.",
])
@pytest.mark.parametrize("clipped", [False, True])
def test_standalone_operation_and_known_nonquantity_continuations_remain_valid(suffix, clipped):
    source = OPERATION + suffix
    interval, error = check(source, OPERATION if clipped else source)
    assert error is None and source[interval[0]:interval[1]] == "2"


def grounding(source, *, claim_ids=None, extra_fields=None):
    owner = case() | {"instructions": source, **(extra_fields or {})}
    package = {"teaching_cases": [], "private_workbook": {"activities": [owner]}}
    records = numeric_span_occurrences({}, package)
    evidence = [role(OPERATION, record.claim_id) for record in records
                if claim_ids is None or record.claim_id in claim_ids]
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30,
                          contains_calculations=False, calculations=[], math_roles=evidence)
    return records, grounded_failures(review, {}, package, expected_claim_ids=claim_ids)


@pytest.mark.parametrize("suffix", [" (cm).", " (hundred).", " and a half.", " և կես."])
@pytest.mark.parametrize("separator", ["", "\n", "\n\n", "\t"])
def test_full_grounding_rejects_same_field_wrapped_qualifiers_after_clipped_quote(suffix, separator):
    source = OPERATION + separator + suffix
    records, errors = grounding(source, claim_ids={"n1"})
    assert records[0].source == source
    assert any("mathematical role invalid" in error for error in errors)


@pytest.mark.parametrize("negative_first", [False, True])
def test_identical_spans_keep_their_own_following_context(negative_first):
    negative, positive = OPERATION + "\n(cm).", OPERATION + "\nThen check the diagram."
    source = "\n".join([negative, positive] if negative_first else [positive, negative])
    records, _ = grounding(source)
    assert len(records) == 2 and records[0].span == records[1].span == OPERATION
    negative_id = records[0 if negative_first else 1].claim_id
    positive_id = records[1 if negative_first else 0].claim_id
    _, negative_errors = grounding(source, claim_ids={negative_id})
    _, positive_errors = grounding(source, claim_ids={positive_id})
    assert any("parenthetical quantity qualifier" in error for error in negative_errors)
    assert positive_errors == []


@pytest.mark.parametrize("source", [
    OPERATION + ".\n(cm).", OPERATION + ".\nand a half.",
    "(cm).\n" + OPERATION + ".", "A half was considered. " + OPERATION + ".",
])
def test_other_sentences_do_not_qualify_this_coefficient(source):
    _, errors = grounding(source)
    assert errors == []


def test_following_private_field_cannot_supply_a_quantity_qualifier():
    _, errors = grounding(OPERATION, extra_fields={"hint": "(cm); and a half."})
    assert errors == []


def test_unknown_word_continuation_remains_unapproved():
    interval, error = check(OPERATION + " unclassifiedpredicate.", OPERATION)
    assert interval is None and "ambiguous following" in error
