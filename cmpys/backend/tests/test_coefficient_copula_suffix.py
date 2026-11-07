"""A copula after a divisor coefficient is a word, not a unit (pilot 2026-11-03).

Quotes from saved native-luna evidence responses (geometry_experienced_evidence
e9cccf34, geometry_novice_missing 0fd73827). Units, scales and negation stay
rejected.
"""
import pytest

from tests.test_coefficient_source_boundaries import diagnostic


@pytest.mark.parametrize("source,quote", [
    ("Dividing by 2 is essential because a triangle occupies half the corresponding base-and-height rectangle.",
     "Dividing by 2"),
    ("Dividing by 2 is essential because a triangle occupies half the corresponding base-and-height rectangle.",
     None),
    ("A response that uses the correct declared measurements but omits the division by 2 has not completed "
     "the triangle-area derivation.", "division by 2"),
    ("Բաժանումը 2-ի անհրաժեշտ է, քանի որ եռանկյունը կազմում է համապատասխան ուղղանկյան կեսը։", None),
    ("Բաժանումը 2-ի անհրաժեշտ է, քանի որ եռանկյունը կազմում է համապատասխան ուղղանկյան կեսը։", "Բաժանումը 2-ի"),
])
def test_copula_after_the_coefficient_is_accepted(source, quote):
    interval, error = diagnostic(source, quote=quote)
    assert error is None and source[interval[0]:interval[1]] == "2"


@pytest.mark.parametrize("source", [
    "Divide the product by 2 cm.",
    "Divide the product by 2 thousand.",
    "Divide the product by 2 hours is wrong.",
    "Divide the product by 2 isosceles halves.",      # "is" must be a whole word
    "Do not divide the product by 2 is the rule.",     # negation still governs
    "Բաժանումը 2-ի սմ անհրաժեշտ է։",
])
def test_unit_scale_partial_word_and_negation_stay_rejected(source):
    interval, error = diagnostic(source)
    assert interval is None and error
