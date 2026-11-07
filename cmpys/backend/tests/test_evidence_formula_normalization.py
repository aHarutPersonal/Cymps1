"""Reviewer formula spelling the evidence gate now reads (pilot 2026-11-03).

Each case is a correct calculation the gate rejected. The expressions are
quoted from saved ReviewEvidencePatch responses (luna 1a6d6d3c, native-luna
4603b461 / fad61f24, haiku-12 1b07905d, native-luna 56a5229d). Wrong numbers,
unbound operands and unverified intermediates must still fail.
"""
import pytest

from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import LessonReview, grounded_failures
from tests.lesson_package_fixtures import package_payload


def package(data, solution, expression):
    payload = package_payload()
    activity = payload["workbook"]["activities"][0]
    activity["data"] = data
    activity["fields"].append({"id": "answer", "kind": "number", "label": "Answer", "expression": expression})
    activity["worked_solution"] = solution + "\nExplain why each step follows from the supplied case."
    return LessonPackage.model_validate(payload)


def check(expression, value, span="n1"):
    return {"claim_ids": [span], "case_id": "practice.guided", "expression": expression, "claimed_result": value}


def failures(pkg, *checks):
    review = LessonReview.model_validate({"acceptable": True, "issues": [], "practice_minutes": 40,
        "contains_calculations": True, "calculations": [
            {**entry, "location": ", ".join(entry["claim_ids"])} for entry in checks]})
    return grounded_failures(review, {}, pkg.review_context()) + review.failures()


LEDGER = [{"id": "shop_earned_sales", "label": "Earned sales", "value": 1850, "unit": "USD"},
          {"id": "shop_incurred_expenses", "label": "Incurred expenses", "value": 1250, "unit": "USD"}]


def ledger(solution="Accrual profit is $1,850 − $1,250 = $600."):
    return package(LEDGER, solution, "shop_earned_sales - shop_incurred_expenses")


# --- B1: one derivation written twice around "=" -----------------------------------------

@pytest.mark.parametrize("expression", [
    "shop_earned_sales - shop_incurred_expenses = 1850 - 1250",   # luna 1a6d6d3c
    "1850 - 1250 = shop_earned_sales - shop_incurred_expenses",
    "1850-1250=600",                                             # native-luna fad61f24 form
    "shop_earned_sales − shop_incurred_expenses = 600",
])
def test_equation_written_both_ways_is_one_verified_derivation(expression):
    assert failures(ledger(), check(expression, 600)) == []


def test_equation_sides_must_agree():
    errors = failures(ledger(), check("shop_earned_sales - shop_incurred_expenses = 1850 - 1150", 600))
    assert any("formula is not derived from the bound case inputs" in error for error in errors)


def test_equation_with_a_wrong_claimed_result_still_fails():
    pkg = ledger("Accrual profit is $1,850 − $1,250 = $999.")
    errors = failures(pkg, check("shop_earned_sales - shop_incurred_expenses = 999", 999))
    assert any("formula is not derived from the bound case inputs" in error for error in errors)
    errors = failures(pkg, check("shop_earned_sales - shop_incurred_expenses", 999))
    assert any("= 600, not 999" in error for error in errors)


def test_equation_with_an_unbound_operand_still_fails():
    errors = failures(ledger(), check("shop_earned_sales - 1250 = 1850 - 1250", 600))
    assert any("formula is not derived from the bound case inputs" in error for error in errors)


# --- B2: powers in a consistency check ---------------------------------------------------

SLANT = [{"id": "horizontal_offset", "label": "Horizontal offset", "value": 3, "unit": "m"},
         {"id": "vertical_drop", "label": "Vertical drop", "value": 4, "unit": "m"}]


@pytest.mark.parametrize("expression", ["sqrt(horizontal_offset ^ 2 + vertical_drop ^ 2)",   # haiku-12 1b07905d
                                        "sqrt(horizontal_offset ** 2 + vertical_drop ** 2)"])
def test_square_root_of_squares_is_evaluated(expression):
    pkg = package(SLANT, "The slanted side is √(3² + 4²) = 5 m long.", "horizontal_offset * vertical_drop / 2")
    assert failures(pkg, check(expression, 5)) == []


def test_power_with_a_wrong_result_or_exponent_still_fails():
    pkg = package(SLANT, "The slanted side is √(3² + 4²) = 6 m long.", "horizontal_offset * vertical_drop / 2")
    assert any("not 6" in error for error in failures(pkg, check("sqrt(horizontal_offset ^ 2 + vertical_drop ^ 2)", 6)))
    pkg = package(SLANT, "The slanted side is 5 m long.", "horizontal_offset * vertical_drop / 2")
    assert failures(pkg, check("sqrt(horizontal_offset ^ 4 + vertical_drop)", 5))  # ^4 stays unsupported


# --- B4: a verified intermediate in the same span ----------------------------------------

# The saved activity declared its halving factor as a datum, as here.
TRIANGLE = [{"id": "base_cm", "label": "Base", "value": 8, "unit": "cm"},
            {"id": "height_cm", "label": "Height", "value": 6, "unit": "cm"},
            {"id": "half_factor", "label": "Halving factor", "value": 2}]
CHAIN = "8 × 6 = 48 cm², and 48 ÷ 2 = 24 cm²."    # native-luna geometry_novice_missing n3


def triangle(solution=CHAIN):
    return package(TRIANGLE, solution, "base_cm * height_cm / half_factor")


def test_chained_intermediate_result_binds():           # native-luna 56a5229d
    assert failures(triangle(), check("8 × 6", 48), check("48 ÷ 2", 24)) == []


def test_intermediate_without_its_own_verified_check_still_fails():
    errors = failures(triangle(), check("48 / 2", 24))
    assert any("formula is not derived from the bound case inputs" in error for error in errors)


def test_wrong_intermediate_cannot_feed_a_later_step():
    pkg = triangle("8 × 6 = 50 cm², and 50 ÷ 2 = 25 cm².")
    errors = failures(pkg, check("8 * 6", 50), check("50 / 2", 25))
    assert any("= 48, not 50" in error for error in errors)
    assert any("formula is not derived from the bound case inputs" in error for error in errors)


def test_intermediate_from_another_span_is_not_an_operand():
    pkg = triangle("The rectangle is 8 × 6 = 48 cm².\nHalf of it, 48 ÷ 2, is 24 cm².")
    errors = failures(pkg, check("8 * 6", 48, "n1"), check("48 / 2", 24, "n2"))
    assert any("formula is not derived from the bound case inputs" in error for error in errors)
