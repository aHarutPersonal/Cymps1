"""Metadata copying aids must never replace the reviewer's exact coverage."""
import copy
import json

import pytest

from app.services.planning.lesson_review import ReviewEvidencePatch
from app.services.planning.package_preflight import _scope_failures
from app.services.planning.package_review import (
    PackageReview, _evidence_patch_request, _metadata_candidate_ids, package_review_payload,
)
from tests.test_package_preflight_patch import package_with_spans


def test_metadata_suggestion_is_source_owned_and_does_not_count_as_evidence():
    package = package_with_spans("Allow 3 minutes for a careful check.")
    before = copy.deepcopy(package.model_dump(mode="json"))
    payload = package_review_payload(package, {}, {})
    assert payload["metadata_candidate_ids"] == ["n1"]
    assert _scope_failures(ReviewEvidencePatch(), {"n1"}, package)
    assert not _scope_failures(ReviewEvidencePatch(literal_fact_ids=["n1"]), {"n1"}, package)
    assert package.model_dump(mode="json") == before


@pytest.mark.parametrize("source", [
    "The screen said 7:42.",
    "Use *screen says 7:42* as a concrete time clue.",
    "Submit three parts: (1) your draft, (2) your revision, and (3) a short note.",
    "The details changed are (1) the fogged window - and (2) the scraping chair.",
])
def test_reviewed_display_and_list_hints_still_require_exact_explicit_assignment(source):
    package = package_with_spans(source)
    payload = package_review_payload(package, {}, {})
    ids = set(payload["numeric_spans"])
    assert ids and set(payload["metadata_candidate_ids"]) == ids
    assert _scope_failures(ReviewEvidencePatch(), ids, package)
    assert not _scope_failures(ReviewEvidencePatch(literal_fact_ids=sorted(ids)), ids, package)


@pytest.mark.parametrize("source", [
    "Note: 'The details changed are (1) the fogged window - and (2) the scraping chair.'",
    'A witness said: "The details are (1) the opening and (2) the ending."',
    "The screen says 7:42 as the ratio.",
    "The quantities are (1) a cm and (2) a cm.",
    "The screen said 7:42 and the total is 900 dollars.",
])
def test_quoted_notes_and_real_quantities_do_not_gain_suggestions_or_evidence(source):
    package = package_with_spans(source)
    payload = package_review_payload(package, {}, {})
    ids = set(payload["numeric_spans"])
    assert ids and not payload["metadata_candidate_ids"]
    assert _scope_failures(ReviewEvidencePatch(literal_fact_ids=sorted(ids)), ids, package)


@pytest.mark.parametrize("source", [
    "Receipts exceed revenue by 20.",
    "Divide the product by 2.",
    "The result is 3 minutes.",
    "Budget 2 minutes plus 3 minutes equals 9 minutes.",
    "An unknown measurement is 3 widgets.",
])
def test_metadata_hint_does_not_license_raw_derived_or_operation_quantities(source):
    package = package_with_spans(source)
    assert _metadata_candidate_ids(package.review_context()) == []


def test_one_ambiguous_metadata_candidate_suppresses_the_whole_suggestion_batch():
    package = package_with_spans("Allow 3 minutes for a careful check.", "2 words + 3 words = 9 words.")
    assert _metadata_candidate_ids(package.review_context()) == []


def test_case_duration_cannot_be_reclassified_as_workload_timing():
    package = package_with_spans("The pump takes 3 minutes to drain the tank.")
    context = package.review_context()
    context["private_workbook"]["activities"][0]["data"][0]["unit"] = "minutes"
    assert _metadata_candidate_ids(context) == []


def test_patch_suggestions_remain_in_exact_requested_scope():
    package = package_with_spans("Allow 3 minutes for a careful check.", "Receipts exceed revenue by 20.")
    payload = package_review_payload(package, {}, {})
    assert payload["metadata_candidate_ids"] == ["n1"]
    prior = PackageReview(acceptable=True, issues=[], contains_calculations=False, literal_fact_ids=["n1"])
    request, scope = _evidence_patch_request(prior, payload, ["n2: calculation is not bound to an exact source span"])
    body = json.loads(request["user_prompt"])
    assert scope == {"n2"}
    assert body["metadata_candidate_ids"] == []
    assert set(body["numeric_spans"]) == {"n2"}
    assert prior.literal_fact_ids == ["n1"]
    assert "an explicit evidence assignment" in request["system_prompt"]


def test_metadata_classification_scans_source_per_batch_not_per_span(monkeypatch):
    from app.services.planning import package_review
    inventory, grounding = package_review.numeric_span_occurrences, package_review.grounded_failures
    calls = {"inventory": 0, "grounding": 0}
    def wrapped_inventory(*args, **kwargs):
        calls["inventory"] += 1
        return inventory(*args, **kwargs)
    def wrapped_grounding(*args, **kwargs):
        calls["grounding"] += 1
        return grounding(*args, **kwargs)
    monkeypatch.setattr(package_review, "numeric_span_occurrences", wrapped_inventory)
    monkeypatch.setattr(package_review, "grounded_failures", wrapped_grounding)
    package = package_with_spans(*[f"Allow {index} minutes for a careful check." for index in range(3, 10)])
    assert len(_metadata_candidate_ids(package.review_context())) == 7
    assert calls == {"inventory": 1, "grounding": 1}


@pytest.mark.parametrize("text", [
    'Complete the approved practice phase "Find the Missing Link" (1-2 minutes): read the excerpt.',
    'Then complete the approved transfer phase "Build Your Chain" (2-3 minutes): submit your chain.',
    "Phase one, 'Name the Failure Mode' (about 1 minute), read the passage and choose the failure mode.",
    "Phase two, 'Diagnose and Revise a Weak Beat' (2–3 minutes), write the diagnosis and revision.",
    'Phase one, guided (1-2 minutes): in "Telling or Showing?',
    'Phase two, transfer (1-2 minutes): in "Fix an Over-Told Line", quote the opening words and rewrite it.',
    'Phase one, guided practice (about 1 minute): read the supplied excerpt.',
    'Phase two, independent transfer (1–2 minutes): explain your revision.',
])
def test_full_lesson_phase_time_hints_still_require_independent_evidence(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    assert ids and _metadata_candidate_ids({}, lesson=lesson) == ids
    missing = LessonReview(acceptable=True, issues=[], practice_minutes=3,
                           contains_calculations=False, calculations=[])
    assert grounded_failures(missing, lesson, {})
    assert not grounded_failures(missing.model_copy(update={"literal_fact_ids": ids}), lesson, {})


@pytest.mark.parametrize("text", [
    'The machine completed the approved practice phase "Drain" (1-2 minutes): a measured duration.',
    '\'Complete the approved practice phase "Drain" (1-2 minutes): read the excerpt.\'',
    'Complete the approved practice phase "Drain" (1-2 minutes): pay 200 dollars.',
    'Complete the approved practice phase "Drain" (1-2 minutes + 3 minutes): read the excerpt.',
    'Complete the approved practice phase "Drain" (3-2 minutes): read the excerpt.',
    "The machine's phase one, 'Drain' (1-2 minutes), is a measured duration.",
    "Phase one, 'Drain' (1-2 minutes + 3 minutes), read the excerpt.",
    "Phase one, 'Drain' (1-2 minutes), pay 200 dollars.",
    '"Phase one, \'Drain\' (1-2 minutes), read the excerpt."',
    'The machine reports phase one, guided (1-2 minutes): measured elapsed time.',
    '"Phase one, guided (1-2 minutes): read the excerpt."',
    'Phase one, guided (1-2 minutes): pay 200 dollars.',
    'Phase one, guided (1-2 minutes + 3 minutes): read the excerpt.',
    'Phase one, guided (3-2 minutes): read the excerpt.',
    'Phase one, drainage (1-2 minutes): the pump empties the tank.',
])
def test_phase_time_hints_do_not_license_quotes_reported_durations_or_other_quantities(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    assert ids and not _metadata_candidate_ids({}, lesson=lesson)
    review = LessonReview(acceptable=True, issues=[], practice_minutes=3,
                          contains_calculations=False, calculations=[], literal_fact_ids=ids)
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "When drafting your 80-to-150-word passages, start with the protagonist.",
    "Draft an 80‐to‐150‐word passage.",
    "Revise your 80‑to‑150‑word passage.",
])
def test_hyphenated_to_word_ranges_require_reviewed_workload_coverage(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    review = LessonReview(acceptable=True, issues=[], practice_minutes=3,
                          contains_calculations=False, calculations=[])
    assert ids and _metadata_candidate_ids({}, lesson=lesson) == ids
    assert grounded_failures(review, lesson, {})
    assert not grounded_failures(review.model_copy(update={"literal_fact_ids": ids}), lesson, {})


@pytest.mark.parametrize("text", [
    "Draft a 150-to-80-word passage.",
    "Draft a 0-to-150-word passage.",
    "Draft a 80-to-5001-word passage.",
    "Draft a 80-to-150.5-word passage.",
    "Draft a -80-to-150-word passage.",
    "A 80-to-150-word passage plus 200 words equals 500 words.",
    "Draft a 80-to-150-word passage and pay 200 dollars.",
    "The task consumes 80-to-150-kg of material.",
])
def test_hyphenated_to_word_range_never_licenses_other_quantities(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    review = LessonReview(acceptable=True, issues=[], practice_minutes=3,
                          contains_calculations=False, calculations=[], literal_fact_ids=ids)
    assert ids and grounded_failures(review, lesson, {})
