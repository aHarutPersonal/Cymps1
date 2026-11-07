"""Numerals that name or enumerate are not numeric claims (pilot 2026-11-03).

Snippets are quoted from saved pilot outputs: glm accounting References
("IAS 1" / "թիվ 1"), haiku-12 check explanation ("Option 1 counts ..."),
luna geometry ("... at 90 degrees"), native-luna software ("INV-42",
"badge-req-7"), native-luna writing ("more than 20 minutes" inside a datum
label), luna software ("Reason 1:", "Gap 1:"). A quantity beside such a label,
a different angle, or a number outside the datum label is still a claim.
"""
import pytest

import json

from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning.activity_draft import parse_activity_draft
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
from app.services.planning.numeric_metadata import incidental_numeral_intervals
from app.services.planning.package_builder import UndeclaredNumbersError, require_declared_numbers
from tests.lesson_package_fixtures import package_payload


def masked(text, labels=(), values=()):
    return [text[a:b] for a, b in incidental_numeral_intervals(text, labels, values)]


def activity(instructions, data=()):
    payload = package_payload()
    item = payload["workbook"]["activities"][0]
    item["instructions"], item["data"] = instructions, list(data)
    return item


def tutorial_activity(instructions):
    """The qualitative exemplar (data []) with these instructions."""
    draft = json.loads(resolve_prompt_text("tutorial_exemplar_qualitative.txt").split("\n", 1)[1])
    return parse_activity_draft({**draft, "instructions": instructions + " Answer in your own words."})


def spans_of(instructions, data=()):
    return list(numeric_spans({}, {"private_workbook": {"activities": [activity(instructions, data)]}}).values())


# --- identifiers and citations -----------------------------------------------------------

def test_identifiers_and_standard_citations_are_masked():
    text = "Invoice INV-42 and request badge-req-7 follow IAS 1 and ISO 8601."
    assert masked(text) == ["42", "7", "1", "8601"]


@pytest.mark.parametrize("text", ["The x-2 shift moves the graph.", "A 3-4-5 triangle.", "Pay $42 for INV.",
                                  "The ratio is 3:1."])
def test_algebra_and_quantities_are_not_identifiers(text):
    assert masked(text) == []


def test_identifier_spans_leave_the_inventory_but_counts_stay():
    assert spans_of("The retry for INV-42 found the stored key for badge-req-7.") == []
    assert spans_of("INV-42 was charged 3 times.") == ["INV-42 was charged 3 times."]


def test_references_section_digits_are_citations():
    lesson = {"lesson_content": (
        "## Core Framework\n\nCash and profit differ.\n\n## References\n\n"
        "Հաշվապահական հաշվառման միջազգային չափորոշիչներ (IFRS), թիվ 1 «Ֆինանսական հաշվետվությունների ներկայացում»:"
        "\nIAS 1 Presentation of Financial Statements, 2007 edition.")}
    assert numeric_spans(lesson) == {}
    # The same sentence outside References is still a claim.
    claim = {"lesson_content": "## Core Framework\n\nThe shop earned 40 dollars, see թիվ 1.\n\n## References\n\nNone."}
    assert list(numeric_spans(claim).values()) == ["The shop earned 40 dollars, see թիվ 1."]


# --- ordinal labels ------------------------------------------------------------------------

def test_option_labels_in_a_check_explanation_are_not_numbers():
    why = ("Why: Revenue follows earning. Option 1 counts this cash as revenue. Option 3 mislabels it. "
           "Option 4 wrongly ties it to March invoices.")
    assert numeric_spans({"lesson_content": why}) == {}


def test_reason_and_gap_labels_need_no_declared_data():
    text = "Reason 1: the key is claimed first.\nGap 1: the send may never happen.\nGap 2: no retry exists."
    require_declared_numbers(tutorial_activity(text))   # luna software: no raise


@pytest.mark.parametrize("text,kept", [
    ("Option 2 gives 41 cups.", ["41"]),
    ("Step 2 costs $40.", ["40"]),
])
def test_a_quantity_beside_a_label_is_still_a_claim(text, kept):
    assert masked(text) == [text.split()[1]]
    assert spans_of(text) == [text]
    with pytest.raises(UndeclaredNumbersError):
        require_declared_numbers(tutorial_activity(text))


# "the 3 options" is a structural count since 2026-11-06 (test_geometry_novice_fixes.py).
@pytest.mark.parametrize("text", ["We sold option 3 times.", "The reason is 5 percent.", "Gap 2.5 m wide.",
                                  "Option 2% fee."])
def test_labels_must_open_a_sentence_and_name_an_item(text):
    assert masked(text) == []


# --- angle constants -----------------------------------------------------------------------

def test_right_angle_constant_beside_its_geometric_wording():
    text = "The right-angle marker at D shows that AD meets the line containing BC at 90 degrees, so it is the height."
    assert masked(text) == ["90"]
    assert masked("AD is perpendicular to BC, meeting it at 90°.") == ["90"]


@pytest.mark.parametrize("text", ["The marker at D shows AD meets BC at 90 degrees.",   # no right-angle wording
                                  "The perpendicular meets BC at 80 degrees.",
                                  "The angles of the triangle add to 360 degrees.",
                                  "The perpendicular height is 90 cm."])
def test_other_angles_and_unqualified_constants_stay_claims(text):
    assert masked(text) == []


# --- numbers inside the owning datum's label ------------------------------------------------

SURVEY = [{"id": "evening_wait_share", "label": "Share of surveyed evening riders waiting more than 20 minutes",
           "value": 68, "unit": "%"}]


def test_number_from_a_datum_label_is_part_of_its_definition():
    text = "68% of surveyed evening riders waited more than 20 minutes."
    assert masked(text, [SURVEY[0]["label"]], [68]) == ["20"]
    pkg = LessonPackage.model_validate({"teaching_cases": [], "workbook": {"title": "W", "activities": [
        activity(text, SURVEY), {**activity("Revise the claim for a new audience using the supplied facts."), "id": "transfer",
                                 "kind": "transfer"}]}})
    ids = list(numeric_spans({}, pkg.review_context()))
    review = LessonReview.model_validate({"acceptable": True, "issues": [], "practice_minutes": 3,
        "contains_calculations": False, "calculations": [], "literal_facts": [
            {"claim_id": ids[0], "case_id": "practice.guided", "datum_ids": ["evening_wait_share"]}]})
    assert grounded_failures(review, {}, pkg.review_context()) == []


def test_other_numbers_or_words_are_not_covered_by_a_label():
    label = SURVEY[0]["label"]
    assert masked("Riders waited more than 25 minutes.", [label], [68]) == []
    assert masked("Riders waited 20 hours.", [label], [68]) == []
    # A label number equal to a datum value is never hidden by its label.
    assert masked("The base is 8 cm.", ["Base 8 cm"], [8]) == []
