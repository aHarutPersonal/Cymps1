"""Review audits are not "incomplete" over quotation marks (pilot 2026-11-03).

native-terra wrapped every verbatim source_quote in typographic quotes
(0e23eec9, 50f4e157) and glm quoted a criteria list as a JSON array (7ae02b2b);
both reviews approved, yet the audit was marked incomplete. A paraphrase
(terra f478402c) or stitched text must still fail.
"""
import json

import pytest

from app.services.planning.lesson_review import (
    AlignmentOnlyReview, PublicAccuracyReview, _practice_alignment_failures, _public_section_audit_failures,
)

SECTIONS = {
    "why_this_matters": "A cafe can report a healthy April profit while its bank balance barely changes. Timing explains it.",
    "core_framework": "Collecting a pre-April customer debt adds cash but does not create April revenue.",
    "references": "Optional reading: “Optional background reference,” approved for context only.",
    "worked_example": ("Because the reservation and completed outcome commit together, a crash before commit "
                       "leaves neither a durable effect nor a completed record."),
}


def audit(section_id, quote, valid=True):
    return {"section_id": section_id, "source_quote": quote, "domain_valid": valid,
            "consistent_with_core": True, "reason": "Accurate and consistent with the supplied case."}


def section_errors(*audits):
    return _public_section_audit_failures(PublicAccuracyReview.model_validate({"public_sections": list(audits)}),
                                          SECTIONS)


def test_typographically_quoted_verbatim_quotes_are_found():
    errors, defects = section_errors(
        audit("why_this_matters", "“A cafe can report a healthy April profit while its bank balance barely changes.”"),
        audit("core_framework", "“Collecting a pre-April customer debt adds cash but does not create April revenue.”"),
        audit("references", "“Optional background reference,” approved for context only."),   # terra 50f4e157
        audit("worked_example", "\"a crash before commit leaves neither a durable effect\""))
    assert errors == [] and defects == []


def test_spacing_and_curly_quotes_inside_the_quote_fold():
    errors, _ = section_errors(*[audit(key, text) for key, text in SECTIONS.items() if key != "references"],
                               audit("references", 'Optional reading:  "Optional background reference," approved'))
    assert errors == []


@pytest.mark.parametrize("quote", [
    # terra f478402c: a paraphrase of the worked example.
    "Because the reservation and completed outcome commit together, a crash before commit leaves neither durable effect",
    "A cafe can report a healthy profit while its bank balance barely changes.",          # word dropped
    "“A cafe can report a healthy April profit … barely changes.”",                     # ellipsis stitch
])
def test_paraphrased_or_stitched_quotes_still_fail(quote):
    section = "worked_example" if quote.startswith("Because") else "why_this_matters"
    others = [audit(key, text) for key, text in SECTIONS.items() if key != section]
    errors, _ = section_errors(*others, audit(section, quote))
    assert errors == [f"Each public section audit must quote its own section exactly (not found in: {section})"]


def test_a_defect_found_with_a_quoted_quote_still_reaches_the_writer():
    others = [audit(key, text) for key, text in SECTIONS.items() if key != "core_framework"]
    errors, defects = section_errors(*others, audit("core_framework", "“adds cash but does not create April revenue”",
                                                    valid=False))
    assert errors == []
    assert defects == [("core_framework", "Public section core_framework: correct the inaccurate or inconsistent rule. "
                        "Public source quote: adds cash but does not create April revenue Reconcile it with the public "
                        "framework and approved teaching facts; preserve their scope.")]


# glm writing_experienced_missing 7ae02b2b (criteria abridged to the quoted ones).
CRITERIA = [
    "States a clear central claim about keeping the morning reading block",
    "Supports the claim with the supplied observation about students completing more books, linked to student learning",
    "Addresses the schedule concern using the supplied schedule constraint rather than ignoring it",
    "Uses no invented statistics, quotations or new observations beyond the supplied facts",
]
PAYLOAD = {"sections": {"core_framework": "Audience-fit revision means keeping your claim while swapping in support "
                                          "the specific reader uses to decide."},
           "practice_contracts": [{"target": "practice.revise_for_principals", "instructions": "Revise the note.",
                                   "worked_solution": "Keep the claim.", "data": [], "diagram": "", "fields": [{
                                       "target": "practice.revise_for_principals.revision", "label": "Revision",
                                       "kind": "text", "unit": "", "expression": None, "choices": [],
                                       "answer_key": None, "criteria": CRITERIA, "rubric_criterion": ""}]}]}


def alignment(quote):
    return AlignmentOnlyReview.model_validate({"practice_alignment": [{
        "target": "practice.revise_for_principals.revision", "aligned": True, "public_rule_valid": True,
        "public_section_id": "core_framework",
        "public_quote": "Audience-fit revision means keeping your claim while swapping in support the specific reader uses to decide.",
        "assessment_source": "criteria", "assessment_quote": quote, "repair_scope": "none",
        "reason": "Criteria mirror the taught move."}]})


def test_json_list_of_verbatim_criteria_is_an_exact_quote():
    errors, public, private = _practice_alignment_failures(alignment(json.dumps(CRITERIA)), PAYLOAD)
    assert (errors, public, private) == ([], [], [])
    errors, *_ = _practice_alignment_failures(alignment(json.dumps([CRITERIA[1], CRITERIA[3]])), PAYLOAD)
    assert errors == []


@pytest.mark.parametrize("quote", [
    json.dumps([CRITERIA[0], "Uses invented statistics freely"]),   # one element is not in the source
    json.dumps([]),
    json.dumps({"criteria": CRITERIA}),
    "States a clear central claim … beyond the supplied facts",
])
def test_list_quotes_need_every_element_verbatim(quote):
    errors, *_ = _practice_alignment_failures(alignment(quote), PAYLOAD)
    assert errors == ["Practice alignment evidence must quote the supplied public and assessment sources"]
