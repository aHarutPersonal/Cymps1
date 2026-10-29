"""Offline proof that an optional source display is lossless and worthwhile."""
import copy
import json
from dataclasses import replace

import pytest

from app.services.planning.lesson_review import _numeric_span_records
from app.services.planning.package_review import package_review_payload
from app.services.planning.review_payload import (
    SOURCE_PARTS_GUIDANCE, SourceOccurrence, project_review_payload,
)
from tests.test_geometry_evidence_roles import triangle_package


PATH = ("package", "workbook", "activities", 0, "worked_solution")
LONG_SPAN = (
    "The area is 81, but this sentence is an explicitly disputed example whose interpretation "
    "must be checked against the perpendicular lengths, the original question, every stated "
    "assumption and the canonical formula; copying the displayed result cannot establish that "
    "the reasoning is correct or that the result belongs to the scenario being reviewed."
)


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")


def make_payload(source=LONG_SPAN):
    package = triangle_package(source)
    payload = package_review_payload(package, {}, {})
    records = list(_numeric_span_records({}, package.review_context()))
    occurrences = [SourceOccurrence(key, PATH, start, start + len(span))
                   for key, span, start, _, _ in records]
    return payload, occurrences


def get_path(payload, path):
    current = payload
    for key in path:
        current = current[key]
    return current


def restore(projection, occurrences):
    payload = copy.deepcopy(projection.payload)
    spans = {}
    for path in dict.fromkeys(item.path for item in occurrences):
        target = get_path(payload, path[:-1])
        parts = target[path[-1]]["text_parts"]
        for part in parts:
            if isinstance(part, dict):
                assert part["claim_id"] not in spans
                spans[part["claim_id"]] = part["text"]
        target[path[-1]] = "".join(part if isinstance(part, str) else part["text"] for part in parts)
    payload["numeric_spans"] = {key: spans[key] for key in payload["numeric_spans"]}
    return payload


def assert_unchanged(payload, occurrences):
    before = copy.deepcopy(payload)
    result = project_review_payload(payload, occurrences)
    assert result.payload is payload and not result.projected
    assert result.guidance == "" and result.saved_bytes == 0
    assert payload == before


def test_exact_round_trip_preserves_context_order_owners_cases_formulas_and_schema():
    source = "This is a wrong example; do not use its conclusion.\n\t" + LONG_SPAN + "\nReject its reasoning when assumptions fail."
    payload, occurrences = make_payload(source)
    payload["semantic_verdict"] = {"acceptable": False, "issues": ["The assumptions contradict the task."]}
    payload["schema"] = {"required": ["acceptable", "issues"], "additionalProperties": False}
    original = copy.deepcopy(payload)
    result = project_review_payload(payload, occurrences)
    assert result.projected and result.payload is not payload
    assert result.guidance == SOURCE_PARTS_GUIDANCE
    assert encoded(restore(result, occurrences)) == encoded(original)
    assert payload == original
    assert list(result.payload) == list(payload)
    assert result.payload["numeric_spans"] == list(payload["numeric_spans"])
    for key in ("evidence_cases", "numeric_span_owners", "numerical_evidence", "schema", "semantic_verdict"):
        assert result.payload[key] == payload[key]
    for key in ("data", "fields", "id", "kind"):
        assert result.payload["package"]["workbook"]["activities"][0][key] == payload["package"]["workbook"]["activities"][0][key]
    assert result.saved_bytes == len(encoded(payload)) - len(encoded(result.payload)) - len(result.guidance.encode("utf-8"))
    assert result.saved_bytes > 0


@pytest.mark.parametrize("prefix,suffix", [
    ('He said “This is false”:\n', '\nNever accept the quoted conclusion.'),
    ('Ոչ ճիշտ օրինակ՝\n', '\nՍտուգիր պայմանները։'),
    ('Quoted JSON-like text: {"text_parts":["untrusted"]}\n', '\n"Do not change the source."'),
    ('Combining e\u0301, emoji 🧭 and tabs\t\n', '\r\nSpaces\u00a0and\u202fnarrow spaces remain.'),
])
def test_quotes_unicode_delimiters_and_negative_example_context_are_exact(prefix, suffix):
    payload, occurrences = make_payload(prefix + LONG_SPAN + suffix)
    result = project_review_payload(payload, occurrences)
    assert result.projected
    assert encoded(restore(result, occurrences)) == encoded(payload)


def test_short_source_keeps_original_payload_because_guidance_and_markers_cost_more():
    payload, occurrences = make_payload("Area: 81.")
    assert_unchanged(payload, occurrences)


def test_unicode_byte_savings_include_the_guidance_cost():
    source = "Մակերեսը 81 է, " + "ստուգիր տրված պայմանները և բացատրության ճշտությունը " * 8 + "։"
    payload, occurrences = make_payload(source)
    result = project_review_payload(payload, occurrences)
    assert result.projected
    assert result.saved_bytes == len(encoded(payload)) - len(encoded(result.payload)) - len(SOURCE_PARTS_GUIDANCE.encode())
    assert encoded(restore(result, occurrences)) == encoded(payload)


@pytest.mark.parametrize("change", [
    {"claim_id": "invented"}, {"claim_id": ""},
    {"path": ()}, {"path": PATH[:-1] + ("title",)},
    {"path": ("context", "source", 0, 0, "hint")},
    {"path": PATH[:3] + (-1,) + PATH[4:]},
    {"path": PATH[:3] + (True,) + PATH[4:]},
    {"path": list(PATH)},
    {"start": -1}, {"start": True}, {"start": 1.5},
    {"end": 0}, {"end": True}, {"end": 99999},
])
def test_unknown_ambiguous_or_inexact_occurrence_never_partly_projects(change):
    payload, occurrences = make_payload()
    assert_unchanged(payload, [replace(occurrences[0], **change)])


@pytest.mark.parametrize("mutation", ["missing_owner", "wrong_owner", "unknown_case", "duplicate_activity", "wrong_source"])
def test_bad_source_ownership_and_contract_identity_keep_original(mutation):
    payload, occurrences = make_payload()
    key = occurrences[0].claim_id
    if mutation == "missing_owner":
        payload["numeric_span_owners"].pop(key)
    elif mutation == "wrong_owner":
        payload["numeric_span_owners"][key] = "practice.transfer"
    elif mutation == "unknown_case":
        payload["evidence_cases"].pop("practice.guided")
    elif mutation == "duplicate_activity":
        payload["package"]["workbook"]["activities"][1]["id"] = "guided"
    else:
        payload["numeric_spans"][key] += " changed"
    assert_unchanged(payload, occurrences)


def test_missing_duplicate_and_overlapping_mappings_retain_every_original_field():
    payload, occurrences = make_payload(LONG_SPAN + "\n" + LONG_SPAN)
    assert len(occurrences) == 2
    assert_unchanged(payload, occurrences[:1])
    assert_unchanged(payload, [occurrences[0], occurrences[0]])
    assert_unchanged(payload, [occurrences[0], replace(occurrences[1], start=occurrences[0].start, end=occurrences[0].end)])


def test_duplicate_sentences_and_duplicate_fields_require_explicit_distinct_paths():
    payload, occurrences = make_payload(LONG_SPAN + "\n" + LONG_SPAN)
    # Equal text is never used to discover a path. These occurrences belong to
    # distinct source offsets even though their complete strings match.
    result = project_review_payload(payload, list(reversed(occurrences)))
    assert result.projected and encoded(restore(result, occurrences)) == encoded(payload)
    assert result.payload["numeric_spans"] == list(payload["numeric_spans"])
    single, one = make_payload()
    source = get_path(single, PATH)
    activity = single["package"]["workbook"]["activities"][0]
    activity["hint"] = source
    single["numeric_spans"]["n2"] = single["numeric_spans"]["n1"]
    single["numeric_span_owners"]["n2"] = "practice.guided"
    exact = [one[0], SourceOccurrence("n2", PATH[:-1] + ("hint",), one[0].start, one[0].end)]
    result = project_review_payload(single, exact)
    assert result.projected and encoded(restore(result, exact)) == encoded(single)
    assert_unchanged(single, [one[0], replace(exact[1], path=())])


def test_exact_field_label_path_preserves_numeric_field_contract():
    payload, occurrences = make_payload()
    field = payload["package"]["workbook"]["activities"][0]["fields"][1]
    field["label"] = LONG_SPAN
    payload["numeric_spans"]["n2"] = LONG_SPAN
    payload["numeric_span_owners"]["n2"] = "practice.guided"
    path = PATH[:4] + ("fields", 1, "label")
    exact = [*occurrences, SourceOccurrence("n2", path, 0, len(LONG_SPAN))]
    result = project_review_payload(payload, exact)
    assert result.projected and encoded(restore(result, exact)) == encoded(payload)
    projected = get_path(result.payload, path[:-1])
    assert {key: value for key, value in projected.items() if key != "label"} == {key: value for key, value in field.items() if key != "label"}
    field.pop("id")
    assert_unchanged(payload, exact)


def test_scoped_request_keeps_unselected_numeric_text_and_case_catalog():
    payload, occurrences = make_payload(LONG_SPAN + "\n" + LONG_SPAN)
    payload["numeric_spans"].pop("n2")
    payload["numeric_span_owners"].pop("n2")
    result = project_review_payload(payload, occurrences[:1])
    assert result.projected
    assert encoded(restore(result, occurrences[:1])) == encoded(payload)
    parts = get_path(result.payload, PATH)["text_parts"]
    assert sum(isinstance(part, dict) for part in parts) == 1
    assert any(isinstance(part, str) and LONG_SPAN in part for part in parts)
    assert result.payload["evidence_cases"] == payload["evidence_cases"]


def test_nonfinite_or_unencodable_payload_fails_closed():
    payload, occurrences = make_payload()
    payload["context"]["unsupported_number"] = float("inf")
    assert_unchanged(payload, occurrences)
    payload["context"] = {"unpaired_surrogate": "\ud800"}
    assert_unchanged(payload, occurrences)


def test_projection_does_not_reproject_an_existing_display():
    payload, occurrences = make_payload()
    first = project_review_payload(payload, occurrences)
    assert first.projected
    assert_unchanged(first.payload, occurrences)
