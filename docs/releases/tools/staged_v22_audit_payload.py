"""Offline, aggregate-only v22 capture audit; never calls a provider.

Executed inside the pinned image with no network and read-only captures.
No generated prose, issue description, formula, quote, or identifier is output.
"""
import ast
import asyncio
import collections
import copy
import hashlib
import itertools
import json
import logging
import math
import re
from decimal import Decimal, localcontext
from pathlib import Path


def load_runtime():
    """Keep imports separate so the launcher verifies image files first."""
    global ValidationError, LLMResponse, LessonPackage, TransferIndependenceError
    global LessonPackageSeed, LessonPackageActivity, PrivatePackageRepair
    global LessonActivityDraft, parse_activity_draft
    global _parse_initial_seed_response_details, parse_initial_seed_response, _validated_activity
    global parse_package_response, apply_private_package_repair, _cleared_choice_targets, _replace_choice_activity
    global PackageSemanticReview, ReviewEvidencePatch, PackageReview, _targets, _known_negative
    global package_review_payload, _evidence_patch_request, _merge_evidence_patch
    global _scope_failures, _patch_verdict, _evidence_review, _evidence_ids, _numeric_preflight_failures
    global normalize_response_case_aliases, numeric_span_occurrences, source_arithmetic_failures
    global compiled_solution_evidence, _private_solution_source, review_lesson
    global _validated_repair_scope, _check_private_repair_scope, _replace_public_activity
    global validation_identity, activity_timing_changes, build_workload_contract, workload_feasibility_issues
    global _complete_json_object, _unwrap_schema_answer, JSONProtocolError, FIELDS
    global render_package_results, PlanDetailSectionsRepairOutput, _assemble_parallel_lesson_response
    global PackagedLessonReview, _canonical_review_data, grounded_failures, calculate, public_workbook, grade_fixed
    from pydantic import ValidationError
    from app.core.config import settings
    from app.services.llm.client import LLMResponse
    from app.services.llm.openlux import _complete_json_object, _unwrap_schema_answer, JSONProtocolError
    from app.services.llm.schemas import PlanDetailSectionsRepairOutput
    from app.services.planning.lesson_package import (
        LessonPackage, TransferIndependenceError, PrivatePackageRepair, parse_package_response,
        apply_private_package_repair, _cleared_choice_targets, _replace_choice_activity,
        _validated_repair_scope, _check_private_repair_scope, _replace_public_activity,
        validation_identity, render_package_results,
    )
    from app.services.planning.package_builder import (
        LessonPackageSeed, LessonPackageActivity, _parse_initial_seed_response_details,
        parse_initial_seed_response, _validated_activity,
    )
    from app.services.planning.activity_draft import LessonActivityDraft, parse_activity_draft
    from app.services.planning.package_preflight import (
        PackageSemanticReview, _targets, _known_negative, _scope_failures, _patch_verdict,
    )
    from app.services.planning.package_review import (
        PackageReview, package_review_payload, _evidence_patch_request, _merge_evidence_patch,
        _evidence_review, _numeric_preflight_failures,
    )
    from app.services.planning.lesson_review import (
        ReviewEvidencePatch, _evidence_ids, normalize_response_case_aliases,
        numeric_span_occurrences, source_arithmetic_failures, PackagedLessonReview,
        _canonical_review_data, grounded_failures, compiled_solution_evidence, _private_solution_source, review_lesson,
    )
    from app.services.planning.workload_contract import (
        activity_timing_changes, build_workload_contract, workload_feasibility_issues,
    )
    from app.services.practice.contracts import calculate, public_workbook, grade_fixed
    from app.tasks.plans import _assemble_parallel_lesson_response
    assert settings.llm_provider == "dummy", "Offline audit requires dummy provider"
    settings.llm_usage_telemetry_enabled = False
    settings.llm_admission_limits = {}
    logging.disable(logging.CRITICAL)
    FIELDS = {"kind_note", "notes", "rationale", "reason"}
    for model in (LessonPackage, LessonPackageSeed, LessonPackageActivity, LessonActivityDraft, PrivatePackageRepair,
                  PackageSemanticReview, ReviewEvidencePatch, PackagedLessonReview):
        schema = model.model_json_schema()
        FIELDS.update(schema.get("properties", {}))
        for definition in schema.get("$defs", {}).values():
            FIELDS.update(definition.get("properties", {}))


ERROR_MARKERS = (
    "mathematical role invalid:", "mathematical role is not bound to an exact source occurrence and canonical field",
    "mathematical role repeats the same occurrence", "literal facts reference an unknown span, case or datum",
    "literal facts mix different cases", "bound datum values are absent from the source span",
    "calculation and literal facts bind different cases", "numeric span contains additional unverified values",
    "derived result cannot be classified as a literal fact", "explicit derived value has no calculation evidence",
    "literal numeric facts are not bound to supplied data or workload metadata",
    "calculation is not bound to an exact source span", "claimed result is absent from its source quote",
    "formula is not derived from the bound case inputs",
    "Numeric verification coverage is incomplete or contains fabricated span IDs",
    "canonical numeric result requires calculation evidence",
    "calculation cannot be verified", "Numeric examples were not checked",
)
SAFE_MATH_REASONS = (
    "field_id must identify one canonical numeric field in this case",
    "case_id does not own this private source activity", "field_id does not own this source field label",
    "source_quote must occur exactly once, verbatim, in this numeric span",
    "quote must contain exactly one numeral equal to coefficient",
    "coefficient has an attached word or unverified unit suffix",
    "coefficient has an ambiguous following scale, unit or word; do not truncate source_quote",
    "quoted prose coefficient is part of another arithmetic expression",
    "quote is only a subexpression; include the complete symbolic expression",
    "a bare numeral is not an operation; quote its explicit mathematical role",
    "symbolic formula requires canonical coefficient and explicit symbol_bindings",
    "bind every source variable one-to-one to exact raw datum IDs, with no unused bindings",
    "bound symbolic expression AST differs from the canonical field expression",
    "role is not licensed by the canonical field operator; inverse requires a top-level operator",
    "quote must explicitly state the matching multiplication or division operation",
    "quote must be a parseable expression only (omit assignment or result labels), and its canonical formula must validate",
    "roles mix different cases",
)
TRANSPORT_CLASSES = ("JSONDecodeError", "JSONProtocolError", "TimeoutError", "APITimeoutError",
                     "APIConnectionError", "InternalServerError", "RateLimitError")


def category(error):
    value = str(error)
    if "mathematical role invalid:" in value:
        suffix = value.split("mathematical role invalid:", 1)[1].strip()
        return suffix if suffix in SAFE_MATH_REASONS else "math_role_other_static_reason"
    for marker in ERROR_MARKERS:
        if marker in value:
            return marker
    for marker, label in (("explicit source equation is incorrect", "source_equation_contradiction"),
                          ("workload", "workload_contract"), ("total minutes", "workload_contract"),
                          ("budget", "request_budget"), ("deadline", "deadline"), ("timeout", "timeout"),
                          ("seed could not", "seed_unavailable"), ("activity could not", "activity_unavailable"),
                          ("preflight unavailable", "preflight_unavailable"),
                          ("review unavailable", "review_unavailable"), ("schema", "schema")):
        if marker in value.lower():
            return label
    return "reviewer_arithmetic_mismatch" if re.search(r"= .*not ", value) else "other_or_semantic"


def categories(errors):
    return dict(collections.Counter(category(error) for error in errors))


CONTRACT_REASONS = {
    "Solution steps must cover every activity field in its exact order": "solution_field_coverage_or_order",
    "Duplicate solution field IDs": "duplicate_solution_field_ids",
    "Combined solution explanations must contain 40 to 4000 characters": "solution_total_explanation_bounds",
    "Solution explanation needs substantive reasoning": "solution_explanation_substance",
    "Unsupported private solution document version": "solution_document_version",
    "New activities require complete structured solution documents": "new_activity_requires_structured_solution",
    "Activity must preserve its exact assigned ID and kind": "assigned_activity_identity",
    "A numeric answer must derive from named facts in this case": "numeric_answer_named_inputs",
    "Case quantities and thresholds must be named facts, not literal answers": "unnamed_formula_quantity",
    "Formula must use named facts meaningfully, without cancelling them": "formula_unused_or_cancelling_inputs",
    "Numeric field needs a computable expression": "numeric_expression_required",
    "Choice field needs a valid answer": "choice_answer_required",
    "Text field needs substantive criteria": "text_criteria_required",
    "Duplicate choice ids": "duplicate_choice_ids",
    "Duplicate ids": "duplicate_field_or_datum_ids",
    "Invalid time interval": "activity_time_interval",
    "Invalid arithmetic expression": "arithmetic_syntax",
    "Expression is too complex": "arithmetic_complexity",
    "Unsupported arithmetic": "arithmetic_unsupported",
    "Invalid arithmetic result": "arithmetic_result_invalid",
    "Invalid arithmetic": "arithmetic_invalid",
}


def safe_finish_reason(value):
    return value if value in (None, "stop", "length", "content_filter", "tool_calls", "function_call") else "other"


def component_shape_diagnostics(data):
    """Describe activity shape without emitting identifiers, text, or numbers.

    This is diagnostic only: it neither repairs the capture nor changes the
    strict component validation below. Output lists have fixed small bounds.
    """
    def value_type(value):
        return type(value).__name__ if type(value) in (str, list, dict, int, float, bool, type(None)) else "other"

    result = {"root_type": value_type(data)}
    if not isinstance(data, dict):
        return result
    document = data.get("worked_solution")
    result["solution_document_type"] = value_type(document)
    if isinstance(document, dict):
        extra_keys = set(document) - {"version", "steps"}
        # FIELDS is built only from installed, trusted schemas in load_runtime.
        # Additional names are a fixed structural vocabulary, never draft keys.
        safe_names = FIELDS | {"duration", "duration_minutes", "minutes", "summary"}
        recognized = sorted(key for key in extra_keys if isinstance(key, str) and key in safe_names)
        result["solution_extra_keys"] = {
            "count": len(extra_keys), "recognized_names": recognized[:16],
            "recognized_names_omitted": max(0, len(recognized) - 16),
            "unrecognized_count": len(extra_keys) - len(recognized),
        }
        comparable = isinstance(data.get("hint"), str) and isinstance(document.get("hint"), str)
        result["hint_shape"] = {
            "root_present": "hint" in data, "nested_present": "hint" in document,
            "root_type": value_type(data.get("hint")), "nested_type": value_type(document.get("hint")),
            "strings_comparable": comparable,
            "root_nested_equal": comparable and data["hint"] == document["hint"],
        }

        def minutes_valid(value, ceiling):
            return (type(value) in (int, float) and 1 <= value <= ceiling
                    and (type(value) is int or value.is_integer()))

        minimum, maximum = document.get("minutes_min"), document.get("minutes_max")
        min_valid, max_valid = minutes_valid(minimum, 45), minutes_valid(maximum, 60)
        result["nested_minutes"] = {
            "minimum_present": "minutes_min" in document, "maximum_present": "minutes_max" in document,
            "minimum_numeric": type(minimum) in (int, float), "maximum_numeric": type(maximum) in (int, float),
            "minimum_valid": min_valid, "maximum_valid": max_valid,
            "interval_valid": min_valid and max_valid and minimum <= maximum,
        }
    fields = data.get("fields")
    result["fields_type"] = value_type(fields)
    if isinstance(fields, list):
        text_fields = [(index, field) for index, field in enumerate(fields)
                       if isinstance(field, dict) and field.get("kind") == "text"]
        result["field_count"] = len(fields)
        result["text_field_count"] = len(text_fields)
        result["text_fields_omitted"] = max(0, len(text_fields) - 10)
        result["text_fields"] = [{
            "position": index, "criteria_present": "criteria" in field,
            "criteria_type": value_type(field.get("criteria")),
            "criteria_count": len(field["criteria"]) if isinstance(field.get("criteria"), list) else None,
        } for index, field in text_fields[:10]]
        result["field_explanations"] = [{
            "position": index, "field_type": value_type(field),
            "explanation_present": isinstance(field, dict) and "explanation" in field,
            "explanation_type": value_type(field.get("explanation")) if isinstance(field, dict) else "other",
            "explanation_chars": len(field["explanation"]) if isinstance(field, dict) and isinstance(field.get("explanation"), str) else None,
        } for index, field in enumerate(fields[:10])]
        result["field_explanations_omitted"] = max(0, len(fields) - 10)
    return result


def schema_errors(exc, data=None):
    if isinstance(exc, TransferIndependenceError):
        return [{"type": "transfer_independence", "reason": exc.reason,
                 "public_case_ordinal": exc.public_case_ordinal,
                 "overlapping_input_count": exc.overlapping_input_count,
                 "checked_input_count": exc.checked_input_count, "public_input_count": exc.public_input_count}]
    if not isinstance(exc, ValidationError):
        known = {"Exercise repair did not change the rejected package": "unchanged_rejected_package",
                 "Public contract changes require a full package correction": "public_change_required",
                 "Private repair changed the public contract": "public_contract_changed"}
        return [{"type": "component_contract", "category": CONTRACT_REASONS.get(str(exc), known.get(str(exc), "other_contract"))}]
    result = []
    for error in exc.errors(include_input=False, include_context=False, include_url=False):
        item = {"type": error["type"], "path": [part if type(part) is int or part in FIELDS else "<unknown>"
                                               for part in error["loc"]]}
        reason = CONTRACT_REASONS.get(error.get("msg", "").removeprefix("Value error, "))
        if reason:
            item["category"] = reason
        value = data
        try:
            for part in error["loc"]:
                value = value[part]
            item["value_type"] = type(value).__name__ if type(value) in (str, list, dict, int, float, bool, type(None)) else "other"
            if isinstance(value, str):
                item["value_char_count"] = len(value)
            if isinstance(value, list):
                item["item_count"] = len(value)
                item["item_type_counts"] = dict(collections.Counter(type(child).__name__ for child in value))
            if error["type"] == "extra_forbidden":
                key = error["loc"][-1]
                item["extra_key"] = key if key in FIELDS else "<unknown>"
        except (KeyError, TypeError, IndexError):
            pass
        result.append(item)
    return result


def wire_diagnostic(capture, model):
    raw = capture.get("visible_response")
    if not isinstance(raw, str):
        return {"status": "visible_response_absent"}, None
    try:
        data = _unwrap_schema_answer(_complete_json_object(raw), model)
        return {"status": "parsed", "wire_matches_saved_data": data == capture.get("data")}, data
    except json.JSONDecodeError as exc:
        messages = {"Expecting property name enclosed in double quotes": "property_name_expected",
                    "Expecting value": "value_expected", "Expecting ',' delimiter": "comma_expected",
                    "Expecting ':' delimiter": "colon_expected", "Extra data": "extra_data",
                    "Unterminated string starting at": "unterminated_string"}
        return {"status": "malformed_json", "decoder_category": messages.get(exc.msg, "other_decoder_error"),
                "position": exc.pos, "document_chars": len(exc.doc), "remaining_chars": len(exc.doc) - exc.pos,
                "line": exc.lineno, "column": exc.colno}, None
    except JSONProtocolError as exc:
        known = {"Duplicate JSON property": "duplicate_property", "Non-finite JSON number": "nonfinite_number",
                 "Expected a JSON object": "nonobject_document", "Empty JSON document": "empty_document"}
        return {"status": "json_protocol_error", "category": known.get(str(exc), "other_protocol_error")}, None


def outline_for(case):
    title = case["goal"] if len(case["goal"]) <= 60 else case["goal"][:61].rsplit(" ", 1)[0]
    return {"id": "step_1", "title": title,
            "description": "Learn the concept, apply it to the supplied case, then transfer and revise independently.",
            "resources": ["Optional background reference"]}


def context_for(case, timing_changes=()):
    # Preserve the exact nested JSON string emitted by the pinned pilot script.
    original = {"goal": case["goal"], "learner_context": {"level": case["learner_level"],
                "locale": case["locale"], "untrusted_note": case["untrusted_note"]},
                "mentor_evidence": {}, "target_practice_minutes": 40}
    result = {"goal": case["goal"], "mentor_evidence": {}, "learner_context": json.dumps(original)}
    if timing_changes:
        result["activity_timing_changes"] = copy.deepcopy(timing_changes)
    return result


def error_positions(errors, package, lesson=None):
    records = numeric_span_occurrences(lesson or {}, package.review_context())
    positions = {item.claim_id: (index, item.path) for index, item in enumerate(records)}
    result = []
    for error in errors:
        ids = re.findall(r"\bn[1-9][0-9]*\b", str(error).split(":", 1)[0])
        result.append({"category": category(error), "source_positions": [
            {"position": positions[key][0], "path": list(positions[key][1])} for key in ids if key in positions],
            "unrecognized_position_count": sum(key not in positions for key in ids)})
    return result


def evidence_counts(data):
    return {key: len(data[key]) if isinstance(data.get(key), list) else None
            for key in ("calculations", "literal_facts", "math_roles", "literal_fact_ids")}


def evidence_shape_diagnostics(package, evidence, expected_ids, *, quote_candidates=None):
    """Content-free lexical diagnostics, never a replacement proof or verdict.

    The caller must first reconstruct the exact captured request. Source paths
    and offsets come from its original inventory, not text/value lookups.
    """
    from app.services.planning import lesson_review as verifier

    context = package.review_context()
    records = numeric_span_occurrences({}, context)
    by_id = {record.claim_id: (index, record) for index, record in enumerate(records)}
    cases = {prefix + case["id"]: case for prefix, values in (
        ("teaching.", context.get("teaching_cases", [])),
        ("practice.", context.get("private_workbook", {}).get("activities", []))) for case in values}
    review = _evidence_review(_patch_verdict(evidence))
    covered = _evidence_ids(review)
    all_units = set().union(*(verifier._metadata_units(case) for case in cases.values())) if cases else set()

    def source_metadata(record, position):
        return {"source_position": position, "source_path": list(record.path),
                "source_slice_exact": record.source[record.start:record.end] == record.span,
                "numeral_count": len(list(verifier._NUMBER_LITERAL.finditer(record.span))),
                "source_field_type": record.path[-1] if record.path[-1] in
                    {"instructions", "worked_solution", "hint", "label", "lesson_content"} else "other"}

    def fields_for(record):
        return {field["id"] for field in (record.owner or {}).get("fields", [])
                if field.get("label") == record.source and isinstance(field.get("id"), str)}

    def normalized_view(record):
        units = verifier._metadata_units(record.owner) if record.owner else all_units
        return verifier.mask_structural_ordinals(record.span, source=record.source, start=record.start, units=units)

    def following_category(span, end, case):
        inflection = re.match(r"-(?:ի|ով)(?!\w)", span[end:])
        if inflection: end += inflection.end()
        end += len(span[end:]) - len(span[end:].lstrip(" \u00a0\u202f"))
        tail = span[end:]
        if not tail: return "end", end
        for unit in sorted(verifier._metadata_units(case), key=len, reverse=True):
            if tail.startswith(unit) and (len(tail) == len(unit) or not tail[len(unit)].isalnum()):
                return "declared_unit", end + len(unit)
        token = re.match(r"[^\W\d_]\w*", tail)
        if token:
            value = token.group().casefold()
            if value in {"hundred", "thousand", "million", "billion", "հարյուր", "հազար", "միլիոն", "միլիարդ"}:
                kind = "known_scale"
            elif value in {"and", "then", "when", "to", "for", "because", "if", "while", "since", "here", "formula",
                           "before", "after", "և", "ապա", "երբ", "որպեսզի", "քանի", "բանաձևը"}:
                kind = "known_connector"
            elif re.fullmatch(r"(?:divid(?:e|es|ed|ing)|division|multipl(?:y|ies|ied|ying|ication))", value):
                kind = "known_English_operation"
            elif re.fullmatch(r"(?:բաժան(?:ում(?:ը)?|ելով|ելու|ել|ես|եք|իր|ի|վում|ած|ված)|"
                              r"բազմապատկ(?:ես|ելով|ում(?:ը)?|ելու|ել|եք|իր|ի|ած|ված))", value):
                kind = "known_Armenian_operation_or_participle"
            elif value in {"cm", "mm", "km", "kg", "mg", "m", "g", "s", "սմ", "մմ", "կմ", "կգ", "մգ", "մ", "գ", "դրամ"}:
                kind = "known_unit"
            else: kind = "unclassified_word"
            return kind, end + token.end()
        if tail[0].isdigit(): return "number", end + 1
        if tail[0] in "%‰‱°$€£": return "known_unit_or_scale_symbol", end + 1
        if tail[0] in "+*/×÷−^=-": return "operator", end + 1
        return "punctuation", end + 1

    def grammar_shape(span, quote, number, offset, case):
        """Fixed lexical classes only; these observations confer no evidence."""
        marks = "\u055b\u055c\u055e"
        word = r"[^\W\d_][\w\u055b\u055c\u055e]*"
        division = r"բաժան(?:ում(?:ը)?|ելով|ելու|ել|ես|եք|իր|ի|վում)"
        multiplication = r"բազմապատկ(?:ես|ելով|ում(?:ը)?|ելու|ել|եք|իր|ի)"
        known_participle = r"(?:բաժան|բազմապատկ)(?:ած|ված|ելիս|ման)"
        strip_marks = str.maketrans("", "", marks)

        def word_class(value):
            if value in verifier._metadata_units(case):
                return "declared_unit"
            value = value.lower()
            if value in {"hundred", "thousand", "million", "billion", "հարյուր", "հազար", "միլիոն", "միլիարդ"}:
                return "scale"
            if value in {"cm", "mm", "km", "kg", "mg", "m", "g", "s", "սմ", "մմ", "կմ", "կգ", "մգ", "մ", "գ", "դրամ"}:
                return "unit"
            if value in {"not", "never", "without", "ոչ", "մի", "առանց", "չի", "չեմ", "չես", "չենք", "չեք", "չեն"}:
                return "negation"
            if re.fullmatch(r"(?:get|gets|obtain|obtains|yield|yields|give|gives|result|results)", value):
                return "English_result_verb"
            if re.fullmatch(r"(?:ստանում|ստացվում|ստացիր|ստացեք|կստանաս|կստանաք)", value):
                return "Armenian_result_verb"
            if re.fullmatch(known_participle, value):
                return "Armenian_operation_participle"
            if re.fullmatch(r"(?:divided|multiplied)", value):
                return "English_operation_participle"
            if re.fullmatch(division + "|" + multiplication, value):
                return "Armenian_operation_verb"
            if value in {"we", "you", "it", "they", "i", "he", "she"}:
                return "English_subject_pronoun"
            if value in {"մենք", "դու", "դուք", "այն", "նա", "ես", "նրանք"}:
                return "Armenian_subject_pronoun"
            if value in {"պետք", "անհրաժեշտ", "հարկավոր", "բավարար"}:
                return "Armenian_modal_or_evaluative"
            if value in {"օգնում", "նշանակում", "ցույց", "թույլ", "կապված", "հիմնված", "պահանջում", "պահանջվում",
                         "բացատրվում", "ապահովում", "տալիս", "հուշում", "արտահայտում", "կախված"}:
                return "Armenian_known_predicate"
            if value in {"and", "then", "when", "to", "for", "because", "if", "while", "since", "before", "after"}:
                return "English_connective"
            if value in {"և", "ապա", "երբ", "որպեսզի", "քանի", "որ", "իսկ", "ուստի", "որովհետև", "հետևաբար"}:
                return "Armenian_connective"
            if value in {"եմ", "ես", "է", "ենք", "եք", "են"}:
                return "Armenian_copula"
            return "unclassified_word"

        end = offset + number.end()
        inflection = re.match(r"-(ի|ով)(?!\w)", span[end:])
        tail = span[end + (inflection.end() if inflection else 0):].lstrip(" \u00a0\u202f")
        prefix_words = []
        cursor = 0
        for _ in range(3):
            token = re.match(word, tail[cursor:])
            if not token: break
            prefix_words.append(word_class(token.group()))
            cursor += token.end()
            space = re.match(r"[ \u00a0\u202f]+", tail[cursor:])
            if not space: break
            cursor += space.end()

        operations = []
        for token in re.finditer(word, quote):
            bare = token.group().translate(strip_marks).casefold()
            if not re.match(r"(?:բաժան|բազմապատկ|divid|division|multipl)", bare): continue
            family = "division" if bare.startswith(("բաժան", "divid", "division")) else "multiplication"
            stem = "բաժան" if family == "division" else "բազմապատկ"
            form = next((name for suffix, name in (
                ("ած", "past_participle"), ("ված", "passive_participle"), ("ելիս", "while_participle"),
                ("ելուց", "after_participle"), ("ման", "nominal"), ("ելն", "definite_infinitive_n"),
                ("ելը", "definite_infinitive_y"), ("ումն", "definite_nominal_n"),
                ("ումը", "definite_nominal_y"), ("ելու", "infinitive_genitive"), ("ելով", "instrumental_participle"),
            ) if bare == stem + suffix), "other_form")
            before = token.end() <= number.start()
            after = token.start() >= number.end()
            gap = (quote[token.end():number.start()] if before else
                   quote[number.end():token.start()] if after else "")
            if after:
                gap = re.sub(r"^-(?:ի|ով)(?!\w)", "", gap)
            tokens = re.findall(word, gap)
            operations.append({
                "operation_family": family,
                "Armenian_form": form,
                "relative_position": "before_coefficient" if before else "after_coefficient" if after else "overlap",
                "Armenian_stress_or_question_mark": any(mark in token.group() for mark in marks),
                "current_supported_Armenian_form": bool(re.fullmatch(division + "|" + multiplication, token.group(), re.I)),
                "supported_after_removing_only_stress_or_question_marks": bool(re.fullmatch(division + "|" + multiplication, bare)),
                "known_Armenian_participle": bool(re.fullmatch(known_participle, bare)),
                "gap_word_count": len(tokens),
                "gap_current_Armenian_word_grammar": bool(re.fullmatch(r"[ \u00a0\u202f]+(?:[\u0531-\u0556\u0561-\u0586]+[ \u00a0\u202f]+){0,6}", gap)),
                "gap_contains_Armenian_punctuation": any(char in gap for char in "\u055a\u055b\u055c\u055d\u055e\u055f\u0589\u058a"),
                "gap_contains_Armenian_ligature": "\u0587" in gap,
                "gap_contains_number": bool(verifier._NUMBER_LITERAL.search(gap)),
                "gap_contains_operator": bool(re.search(r"[+*/×÷−^=<>]", gap)),
                "gap_contains_declared_unit": any(unit and re.search(r"(?<!\w)" + re.escape(unit) + r"(?!\w)", gap)
                    for unit in verifier._metadata_units(case)),
                "gap_contains_known_negation": any(word_class(token) == "negation" for token in tokens),
                "gap_contains_known_unit_or_scale": any(word_class(token) in {"unit", "scale"} for token in tokens),
                "gap_contains_connective": any(word_class(token) in {"English_connective", "Armenian_connective"} for token in tokens),
            })
        return {"coefficient_Armenian_inflection": "genitive" if inflection and inflection[1] == "ի" else
                    "instrumental" if inflection else "none",
                "following_word_classes": prefix_words,
                "following_prefix_has_result_verb": any(value in {"English_result_verb", "Armenian_result_verb"} for value in prefix_words),
                "operation_shapes": operations[:8], "operation_shapes_omitted": max(0, len(operations) - 8)}

    def metadata_shape(record, view, case):
        units = verifier._metadata_units(case)
        content = verifier._numeric_content(view, units=units)
        counts = {}
        # Replay the existing finite workload matcher only to attribute its
        # removals. No class below skips a proof or changes source inventory.
        for name, forms, maximum in (
            ("word_quota", r"words?|բառ(?:անոց|ով|ի)?", 5000),
            ("sentence_quota", r"sentences?|նախադասությամբ|նախադասություն(?:ներ(?:ով|ը)?|ով)?", 20),
            ("duration", r"minutes?|mins?|hours?|hrs?|seconds?|րոպե(?:ի|ում|ով)?|ժամ(?:վա|ում|ով)?|վայրկյան(?:ի|ում|ով)?", 180),
        ):
            pattern = (r"(?<![-+−\w.])(" + verifier._INTEGER_LITERAL + r")(?:\s*[-–]\s*("
                       + verifier._INTEGER_LITERAL + r"))?\s+(?:" + forms + r")\b")
            matched, consumed = 0, 0
            def consume(match):
                nonlocal matched, consumed
                count = 2 if match[2] else 1
                matched += count
                lower = int(verifier._canonical_numeric_spelling(match[1]))
                upper = int(verifier._canonical_numeric_spelling(match[2] or match[1]))
                context_valid = maximum != 180 or verifier._duration_budget(content, match,
                    structural_heading=bool(verifier._STRUCTURAL_PREFIX.match(view)))
                if 1 <= lower <= upper <= maximum and context_valid:
                    consumed += count
                    return verifier._WORKLOAD_MARKER
                return match[0]
            content = re.sub(pattern, consume, content, flags=re.I)
            counts[name + "_numeral_count"] = matched
            counts[name + "_recognized_numeral_count"] = consumed
        counts.update(
            structural_ordinal_removed_count=max(0, len(list(verifier._NUMBER_LITERAL.finditer(record.span)))
                - len(list(verifier._NUMBER_LITERAL.finditer(verifier._numeric_content(view, units=units))))),
            grade_safe_precision_removed_count=max(0, len(list(verifier._NUMBER_LITERAL.finditer(view)))
                - len(list(verifier._NUMBER_LITERAL.finditer(verifier._precision_role_remainder(view, case))))),
            workload_arithmetic_present=verifier._workload_arithmetic(content),
            workload_has_unclassified_numeric_remainder=bool(verifier._NUMBER_LITERAL.search(content)))
        return counts

    failures, occurrences, quoted_occurrences = [], collections.Counter(), collections.Counter()
    for role_index, role in enumerate(review.math_roles):
        found = by_id.get(role.claim_id)
        if found is None: continue
        position, record = found
        case = cases.get(role.case_id, {})
        interval, reason = verifier._math_role_diagnostic(role, record.span, case, record.owner, fields_for(record))
        if interval is not None: occurrences[(role.claim_id, interval)] += 1
        quote, span = role.source_quote, record.span
        count = span.count(quote)
        offset = span.find(quote) if count == 1 else None
        numbers = list(verifier._NUMBER_LITERAL.finditer(quote))
        field = next((field for field in verifier._canonical_formula_fields(case) if field.get("id") == role.field_id), None)
        licensed = False
        if field:
            roles = verifier._formula_coefficient_roles(ast.parse(field["expression"], mode="eval").body, role.coefficient)
            licensed = bool(roles) if role.role == "symbolic_formula" else role.role in roles
        row = {**source_metadata(record, position), "entry_position": role_index,
               "selected_role": role.role,
               "reason": (reason if reason in SAFE_MATH_REASONS else "other_static_reason") if reason else "accepted_by_existing_syntax",
               "current_validator_accepts": interval is not None,
               "quote_unique": count == 1, "quote_occurrence_count": count,
               "quote_is_full_span": quote == span,
               "quote_numeric_occurrence_count": len(numbers),
               "coefficient_match": len(numbers) == 1 and Decimal(verifier._canonical_numeric_spelling(numbers[0].group())) == role.coefficient,
               "selected_role_canonical_operator_licensed": licensed,
               "owner_valid": record.owner is None or role.case_id == "practice." + record.owner.get("id", ""),
               "field_valid": field is not None and (not fields_for(record) or fields_for(record) == {role.field_id}),
               "symbol_binding_values_in_case": set(role.symbol_bindings.values()) <= {datum["id"] for datum in case.get("data", [])},
               "symbol_binding_values_unique": len(set(role.symbol_bindings.values())) == len(role.symbol_bindings),
               "source_operation_count": len(re.findall(r"\b(?:բաժան\w*|բազմապատկ\w*|divid\w*|division|multipl\w*)\b", span, re.I)),
               "quote_has_existing_Armenian_division_form": bool(re.search(r"\bբաժան(?:ում(?:ը)?|ելով|ելու|ել|ես|եք|իր|ի|վում)\b", quote, re.I)),
               "quote_has_existing_Armenian_multiplication_form": bool(re.search(r"\bբազմապատկ(?:ես|ելով|ում(?:ը)?|ելու|ել|եք|իր|ի)\b", quote, re.I)),
               "quote_has_known_Armenian_participle": bool(re.search(r"\b(?:բաժան(?:ած|ված)|բազմապատկ(?:ած|ված))\b", quote, re.I))}
        if offset is not None:
            prefix = re.split(r"[.;:։!?\n\r]", span[:offset])[-1]
            row.update(preceding_clause_negation=bool(re.search(r"\b(?:ոչ|մի|առանց|չի|չեմ|չես|չենք|չեք|չեն)\b", prefix, re.I)),
                       quote_has_negation=bool(re.search(r"\b(?:ոչ|մի|առանց|չի|չեմ|չես|չենք|չեք|չեն)\b", quote, re.I)),
                       english_negation_present=bool(re.search(r"\b(?:not|never|without)\b", prefix + " " + quote, re.I)),
                       symbolic_boundary_complete=verifier._symbolic_quote_is_complete(span, offset, offset + len(quote)),
                       quote_end_inside_word=bool(offset + len(quote) < len(span) and quote[-1:].isalnum() and span[offset + len(quote)].isalnum()))
            if len(numbers) == 1:
                quoted_occurrences[(role.claim_id, offset + numbers[0].start(), offset + numbers[0].end())] += 1
                suffix, end = following_category(span, offset + numbers[0].end(), case)
                row.update(following_category=suffix, quote_contains_following_token=end <= offset + len(quote),
                           coefficient_suffix_accepted=verifier._coefficient_suffix_error(span, offset + numbers[0].end()) is None)
                row["grammar_shape"] = grammar_shape(span, quote, numbers[0], offset, case)
                observed = {item["operation_family"] for item in row["grammar_shape"]["operation_shapes"]}
                expected = "division" if role.role in {"divisor", "inverse_divisor"} else (
                    "multiplication" if role.role in {"multiplier", "inverse_multiplier"} else "symbolic")
                row.update(expected_operation_family=expected,
                    selected_operation_family_matches_observed=observed == {expected},
                    alternative_licensed_role_acceptance={kind: verifier._math_role_diagnostic(
                        role.model_copy(update={"role": kind}), span, case, record.owner, fields_for(record))[0] is not None
                        for kind in ("divisor", "inverse_divisor", "multiplier", "inverse_multiplier")})
        failures.append(row)

    calculations = []
    for check_index, check in enumerate(review.calculations):
        case = cases.get(check.case_id, {})
        raw_ids = {datum["id"] for datum in case.get("data", [])}
        try:
            tree = ast.parse(check.expression, mode="eval")
            names = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name) and node.id != "sqrt"}
            constants = {abs(node.value) for node in ast.walk(tree) if isinstance(node, ast.Constant) and type(node.value) in (int, float)}
            bound = bool(names) and names <= raw_ids and constants <= {0, 1, 2, 100}
        except (ValueError, SyntaxError, RecursionError): bound = False
        for key in check.claim_ids:
            if key not in by_id: continue
            position, record = by_id[key]
            units = verifier._matching_result_units(check, case, record.owner)
            original = verifier._source_literal(record.span, check.claimed_result) is not None
            normalized = verifier._check_source_literal(normalized_view(record), check, units) is not None
            owner = record.owner is None or check.case_id == "practice." + record.owner.get("id", "")
            quote_present = not check.source_quote or (check.source_quote in record.source and
                (check.source_quote in record.span or record.span in check.source_quote))
            if original and normalized and owner and bound and quote_present: continue
            other = [item for item in records if item.claim_id != key and verifier._source_literal(item.span, check.claimed_result) is not None]
            calculations.append({**source_metadata(record, position), "entry_position": check_index,
                "result_present_original": original, "result_present_normalized": normalized,
                "result_present_other_span": bool(other),
                "result_present_other_same_owner_span": any(item.owner == record.owner for item in other),
                "result_present_other_owner_span": any(item.owner != record.owner for item in other),
                "explicit_quote_supplied": bool(check.source_quote), "explicit_quote_source_bound": quote_present,
                "result_present_explicit_quote": verifier._source_literal(check.source_quote, check.claimed_result) is not None if check.source_quote else None,
                "owner_valid": owner, "named_inputs_bound": bound})

    omitted = []
    for key in sorted(set(expected_ids) - covered, key=lambda value: by_id[value][0] if value in by_id else -1):
        if key not in by_id: continue
        position, record = by_id[key]
        case = record.owner or {}
        numbers = list(verifier._NUMBER_LITERAL.finditer(record.span))
        values = [Decimal(verifier._canonical_numeric_spelling(match.group())) for match in numbers]
        raw = {Decimal(str(datum["value"])) for datum in case.get("data", [])}
        derived, licensed, full_fields = set(), 0, set()
        for field in verifier._canonical_formula_fields(case):
            tree = ast.parse(field["expression"], mode="eval").body
            derived.add(Decimal(str(calculate(field["expression"], {item["id"]: item["value"] for item in case.get("data", [])}))))
            for coefficient in (1, 2, 100):
                if Decimal(coefficient) not in values: continue
                roles = verifier._formula_coefficient_roles(tree, coefficient)
                licensed += len(roles)
                if not 3 <= len(record.span) <= 400: continue
                for role in roles:
                    probe = verifier.MathRoleCheck(claim_id=key, case_id="practice." + case.get("id", ""),
                        field_id=field["id"], role=role, coefficient=coefficient, source_quote=record.span)
                    if verifier._math_role_diagnostic(probe, record.span, case, record.owner, fields_for(record))[0] is not None:
                        full_fields.add(field["id"])
        units = verifier._metadata_units(case)
        view = normalized_view(record)
        metadata_removed = len(list(verifier._NUMBER_LITERAL.finditer(view))) - len(list(verifier._NUMBER_LITERAL.finditer(
            verifier._workload_remainder(verifier._numeric_content(view, units=units), units=units))))
        omitted.append({**source_metadata(record, position),
            "coefficient_candidate_count": sum(value in {Decimal(1), Decimal(2), Decimal(100)} for value in values),
            "canonical_role_candidate_count": licensed,
            "exact_full_span_licensed_field_count": len(full_fields),
            "exactly_one_full_span_licensed_field": len(full_fields) == 1,
            "existing_quote_candidate_count": len((quote_candidates or {}).get(key, [])),
            "existing_quote_candidate_exact_count": sum(isinstance(candidate, dict)
                and isinstance(candidate.get("source_quote"), str) and bool(candidate["source_quote"])
                and record.span.count(candidate["source_quote"]) == 1 for candidate in (quote_candidates or {}).get(key, [])),
            "existing_reviewer_quote_candidate_count": sum(record.span.count(role.source_quote) == 1 for role in review.math_roles),
            "raw_value_coincidence_count": sum(value in raw for value in values),
            "derived_value_coincidence_count": sum(value in derived for value in values),
            "recognized_metadata_numeral_count": max(0, metadata_removed),
            "metadata_shape": metadata_shape(record, view, case)})
    return {"basis": "exact source inventory; lexical diagnostics and value coincidences are not semantic proof",
            "role_diagnostics": failures[:32], "role_diagnostics_omitted": max(0, len(failures) - 32),
            "unbound_calculations": calculations[:32], "unbound_calculations_omitted": max(0, len(calculations) - 32),
            "omitted_scope_positions": omitted[:40], "omitted_scope_positions_omitted": max(0, len(omitted) - 40),
            "duplicate_valid_role_occurrence_count": sum(max(0, count - 1) for count in occurrences.values()),
            "duplicate_quoted_coefficient_occurrence_count": sum(max(0, count - 1) for count in quoted_occurrences.values())}


def match_request_hash(request, expected):
    """Recover only known set-iteration diagnostic order, then require exact SHA.

    The pinned verifier appends remainder failures in set order. Python's hash
    seed can change that order between production and the offline container.
    No content, evidence, scope, or diagnostic is changed or omitted.
    """
    original = request["user_prompt"]
    if hashlib.sha256(original.encode()).hexdigest() == expected:
        return True, False, 1
    body = json.loads(original)
    # The preflight uses compact JSON; final-review repair uses default
    # separators. Recover set-order only within the original serialization.
    compact = json.dumps(body, ensure_ascii=False, separators=(",", ":")) == original
    if not compact and json.dumps(body, ensure_ascii=False) != original:
        return False, False, 1
    defects = body.get("verification_defects")
    if not isinstance(defects, list) or not all(isinstance(item, str) for item in defects):
        return False, False, 1
    positions = [index for index, text in enumerate(defects)
                 if re.fullmatch(r"n[1-9][0-9]*: numeric span contains additional unverified values", text)]
    if (not 2 <= len(positions) <= 8 or positions != list(range(positions[0], positions[-1] + 1))):
        return False, False, 1
    start, end = positions[0], positions[-1] + 1
    attempts = 1
    for order in itertools.islice(itertools.permutations(defects[start:end]), 5000):
        body["verification_defects"] = defects[:start] + list(order) + defects[end:]
        attempts += 1
        candidate = json.dumps(body, ensure_ascii=False, **({"separators": (",", ":")} if compact else {}))
        if hashlib.sha256(candidate.encode()).hexdigest() == expected:
            return True, True, attempts
    return False, False, attempts


def semantic_issue_metadata(issue, package):
    """Structural targets and literal keyword flags, never issue text or IDs."""
    target = issue.target
    location = {"target_kind": "unknown", "owner_position": None, "field_or_result_position": None}
    if target in {"package", "outline", "context"}:
        location["target_kind"] = target
    for owner_index, case in enumerate(package.teaching_cases):
        prefix = "teaching." + case.id
        if target == prefix:
            location.update(target_kind="teaching_case", owner_position=owner_index)
        for result_index, result in enumerate(case.results):
            if target == prefix + "." + result.id:
                location.update(target_kind="teaching_result", owner_position=owner_index, field_or_result_position=result_index)
    for owner_index, activity in enumerate(package.workbook.activities):
        prefix = "practice." + activity.id
        if target == prefix:
            location.update(target_kind="activity", owner_position=owner_index)
        for field_index, field in enumerate(activity.fields):
            if target == prefix + "." + field.id:
                location.update(target_kind="answer_field", owner_position=owner_index, field_or_result_position=field_index)
    patterns = {
        "workload": r"\b(?:minutes?|duration|workload|timing|time estimate|padding)\b|րոպե|տևող|ժամանակ|ծանրաբեռն",
        "transfer": r"\b(?:transfer|independent|independence|reuse|copied|recall)\b|փոխանց|ինքնուրույն|կրկնօգտագործ",
        "answer_or_solution": r"\b(?:answer|answers|solution|solutions|correct choice|answer key|criteria)\b|պատասխան|լուծում|չափանիշ",
        "arithmetic_or_formula": r"\b(?:arithmetic|calculation|calculate|formula|equation|numeric|numerical)\b|հաշվարկ|բանաձև|թվային",
        "raw_input_or_assumption": r"\b(?:raw|data|datum|input|inputs|facts?|assumptions?)\b|տվյալ|ենթադր|մուտք",
        "unsupported_or_contradiction": r"\b(?:unsupported|fabricated|contradict\w*|inconsistent|misleading)\b|հակաս|անհիմն",
        "language": r"\b(?:language|armenian|locale|translation)\b|լեզու|հայերեն|թարգման",
        "public_private_visibility": r"\b(?:public|private|visible|hidden|leak\w*)\b|հանրային|թաքնված",
    }
    return {**location, "description_char_count": len(issue.description),
            "description_sha256": hashlib.sha256(issue.description.encode()).hexdigest(),
            "lexical_flags": {label: bool(re.search(pattern, issue.description, re.I)) for label, pattern in patterns.items()},
            "critique_phrase_matches": critique_phrase_matches(issue.description),
            "flag_basis": "literal keyword matches only; not a semantic adjudication"}


def critique_phrase_matches(description):
    """Bounded English diagnostic taxonomy; no generated words are returned.

    These labels describe matched phrases, not verified defects. Negation and
    suggested remedies may contain the same phrase, so consumers must not turn
    a match into a claim that the package actually has that defect.
    """
    patterns = {
        "underdetermined": r"\b(?:under[- ]?determined|insufficient information|not enough (?:information|data)|cannot be determined|not uniquely determined|does not determine)\b",
        "missing_constraint": r"\b(?:missing|unstated|unspecified|absent|additional|extra|required)\s+(?:geometric\s+)?(?:constraints?|conditions?|assumptions?)\b|\b(?:constraints?|conditions?|assumptions?)\s+(?:are|is)\s+(?:missing|unstated|unspecified|absent)\b",
        "ambiguity_or_multiple_answers": r"\b(?:ambiguous|ambiguity|multiple (?:valid |correct |possible )?(?:answers|solutions|interpretations)|more than one (?:answer|solution)|non[- ]?unique)\b",
        "choice_answer_key": r"\b(?:answer[- ]?key|correct (?:choice|option)|selected (?:choice|option)|choice (?:key|answer)|multiple[- ]choice)\b",
        "rubric_or_grading": r"\b(?:rubric|grading|assessment criteria|acceptance criteria|success criteria|scor(?:ing|e))\b",
        "signed_value_or_orientation": r"\b(?:signed (?:value|quantity|area|distance)|sign convention|negative (?:value|quantity|area|distance)|positive (?:value|quantity|area|distance)|absolute value|orientation)\b",
        "geometric_configuration": r"\b(?:perpendicular|parallel|collinear|right[- ]angled?|right triangle|altitude|height|base|diagonal|rectangle|parallelogram|triangle)\b",
        "units_or_dimensions": r"\b(?:units?|dimensions?|dimensional|square centimeters?|square metres?|square meters?)\b",
        "invented_or_unjustified_assumption": r"\b(?:invented|fabricated|unsupported|unjustified|unwarranted|unstated|unlicensed)\b|\b(?:assumes?|assuming)\s+(?:without|that)\b",
        "answer_prompt_mismatch": r"\b(?:does not match|doesn't match|do not match|does not follow|doesn't follow|contradicts?|inconsistent with|incompatible with|not supported by|not entailed by)\b",
        "rounding_or_precision": r"\b(?:rounding|precision|decimal places?|tolerance|approximation)\b",
        "transfer_independence": r"\b(?:transfer|independence|independent|copy|copied|copying|reuse|reuses|reused)\b",
        "task_changed_or_missing": r"\b(?:different task|changed task|new task|missing task|omit(?:ted|s)?|missing (?:step|component|requirement))\b",
        "workload_inflation": r"\b(?:inflated|padded|padding|unrealistic|too long|too short|unnecessary repetition|redundant)\b",
    }
    return [label for label, pattern in patterns.items() if re.search(pattern, description, re.I)]


def package_change_metadata(before, after):
    """Compare canonical packages, returning schema-owned paths and types only."""
    changes = []
    allowed_types = (str, list, dict, int, float, bool, type(None))

    def walk(left, right, path):
        if left == right:
            return
        if isinstance(left, dict) and isinstance(right, dict):
            for key in sorted(left.keys() | right.keys()):
                child_path = path + [key if key in FIELDS else "<unknown>"]
                if key not in left or key not in right:
                    changes.append({"path": child_path, "change_kind": "added" if key not in left else "removed"})
                else:
                    walk(left[key], right[key], child_path)
        elif isinstance(left, list) and isinstance(right, list):
            for index in range(max(len(left), len(right))):
                if index >= len(left) or index >= len(right):
                    changes.append({"path": path + [index], "change_kind": "added" if index >= len(left) else "removed"})
                else:
                    walk(left[index], right[index], path + [index])
        else:
            changes.append({"path": path, "change_kind": "modified",
                            "before_type": type(left).__name__ if type(left) in allowed_types else "other",
                            "after_type": type(right).__name__ if type(right) in allowed_types else "other"})

    walk(before.model_dump(mode="json"), after.model_dump(mode="json"), [])
    return {"changed_leaf_count": len(changes), "changed_paths": changes[:256],
            "omitted_path_count": max(0, len(changes) - 256),
            "teaching_cases_unchanged": before.teaching_cases == after.teaching_cases,
            "activity_order_unchanged": [item.id for item in before.workbook.activities] == [item.id for item in after.workbook.activities]}


class PreflightAudit:
    """Replay exact captured scopes, without generating replacement evidence."""
    def __init__(self, package, case, timing_changes=()):
        self.package = package
        self.payload = package_review_payload(package, outline_for(case), context_for(case, timing_changes))
        self.compiled = compiled_solution_evidence({}, package.review_context())
        self.compiled_ids = {key for check in self.compiled.calculations for key in check.claim_ids}
        for activity in self.payload["package"]["workbook"]["activities"]:
            if isinstance(activity.get("worked_solution"), dict):
                activity["worked_solution"] = _private_solution_source(activity)
        self.spans = self.payload["numeric_spans"]
        self.owners = self.payload["numeric_span_owners"]
        self.positions = {activity.id: index for index, activity in enumerate(package.workbook.activities)}
        self.groups = {activity.id: {key for key, owner in self.owners.items() if owner == "practice." + activity.id}
                       for activity in package.workbook.activities}
        self.groups = {owner: ids for owner, ids in self.groups.items() if ids}
        self.remaining_groups = {owner: ids - self.compiled_ids for owner, ids in self.groups.items()}
        body = {key: value for key, value in self.payload.items() if key in {
            "outline", "context", "capabilities", "package", "numerical_evidence", "workload_contract"}}
        self.semantic_hash = hashlib.sha256(json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
        self.prior, self.errors, self.semantic, self.proofs = {}, {}, [], []
        self.negative = False
        self.validated_targets = set()
        for owner, ids in self.groups.items():
            if not self.remaining_groups[owner]:
                seed = ReviewEvidencePatch(calculations=[check for check in self.compiled.calculations
                    if set(check.claim_ids) <= ids])
                self.prior[owner] = PackageReview(acceptable=True, issues=[], contains_calculations=True,
                    calculations=seed.calculations)
                self.errors[owner] = _scope_failures(seed, ids, package)

    def semantic_capture(self, capture):
        data = capture.get("data")
        negative = _known_negative(data)
        self.negative |= negative
        result = {"known_negative": negative, "negative_preserved_as_blocking": negative,
                  "request_hash_matches": capture.get("request_sha256") == self.semantic_hash,
                  "complete": not capture.get("error") and capture.get("finish_reason") in (None, "stop")}
        try:
            verdict = PackageSemanticReview.model_validate(data)
            result.update(schema_valid=True, acceptable=verdict.acceptable, issue_count=len(verdict.issues),
                          invalid_target_count=sum(issue.target not in _targets(self.package) for issue in verdict.issues),
                          issue_metadata=[semantic_issue_metadata(issue, self.package) for issue in verdict.issues])
            if (negative and result["complete"] and result["request_hash_matches"]
                    and result["invalid_target_count"] == 0):
                self.validated_targets.update(issue.target for issue in verdict.issues)
        except ValidationError as exc:
            result.update(schema_valid=False, schema_errors=schema_errors(exc, data))
        self.semantic.append(result)

    def proof_capture(self, capture):
        before = copy.deepcopy(capture)
        data = capture.get("data") or {}
        self.negative |= _known_negative(data)
        result = {"known_negative": _known_negative(data), "entry_counts": evidence_counts(data),
                  "finish_reason": safe_finish_reason(capture.get("finish_reason")), "has_error": bool(capture.get("error"))}
        self.proofs.append(result)
        recorded = capture.get("request_claim_ids")
        scope_valid = (capture.get("request_scope_kind") == "package_evidence"
                       and isinstance(recorded, list) and bool(recorded)
                       and all(type(key) is str and re.fullmatch(r"n[1-9][0-9]*", key) for key in recorded)
                       and len(recorded) == len(set(recorded)) and set(recorded) <= self.spans.keys())
        result["recorded_scope_valid"] = scope_valid
        if not scope_valid:
            result["numeric_validation_performed"] = False
            return
        owners = {self.owners[key].removeprefix("practice.") for key in recorded}
        result["recorded_owner_count"] = len(owners)
        if len(owners) != 1:
            result["numeric_validation_performed"] = False
            return
        owner = next(iter(owners))
        ids = self.remaining_groups[owner]
        result.update(owner_activity_position=self.positions[owner], recorded_scope_count=len(recorded),
                      owner_total_claim_count=len(self.groups[owner]), owner_residual_claim_count=len(ids),
                      owner_compiled_claim_count=len(self.groups[owner] & self.compiled_ids))
        prior = self.prior.get(owner, PackageReview(acceptable=True, issues=[]))
        payload = {**self.payload, "numeric_spans": {key: value for key, value in self.spans.items() if key in ids},
                   "numeric_span_owners": {key: value for key, value in self.owners.items() if key in ids}}
        built = _evidence_patch_request(prior, payload, self.errors.get(owner, []))
        if built is None:
            result.update(numeric_validation_performed=False, request_reconstruction_unavailable=True)
            return
        request, scope = built
        hash_matches, order_recovered, attempts = match_request_hash(request, capture.get("request_sha256"))
        exact = (set(recorded) == scope & self.spans.keys()
                 and hash_matches)
        result["exact_request_reconstructed"] = exact
        result.update(diagnostic_order_recovered=order_recovered, request_hash_candidates_checked=attempts)
        if not exact or capture.get("error") or capture.get("finish_reason") not in (None, "stop"):
            result["numeric_validation_performed"] = False
            return
        response = LLMResponse(data=copy.deepcopy(data))
        normalize_response_case_aliases(response, self.package.review_context())
        result["alias_normalization_count"] = (response.effective_parameters or {}).get("evidence_case_alias_count", 0)
        try:
            patch = ReviewEvidencePatch.model_validate(response.data)
            claims = _evidence_ids(_evidence_review(_patch_verdict(patch)))
            result.update(schema_valid=True, referenced_claim_count=len(claims),
                          unknown_claim_count=len(claims - self.spans.keys()), outside_requested_scope_count=len(claims - scope),
                          semantic_issue_count=len(patch.issues), package_issue_count=len(patch.package_issues))
            if patch.issues or patch.package_issues:
                result.update(numeric_validation_performed=False, negative_preserved_as_blocking=True)
                if (not (claims - scope) and patch.practice_minutes is None and not patch.affected_sections
                        and all(24 <= len(text) <= 1200 for text in patch.issues + patch.package_issues)):
                    self.validated_targets.add("practice." + owner)
                return
            merged = _merge_evidence_patch(prior, patch, scope, payload["numeric_spans"])
            complete = ReviewEvidencePatch.model_validate(merged.model_dump(mode="json", include={
                "calculations", "literal_facts", "literal_fact_ids", "math_roles"}))
            errors = _scope_failures(complete, set(ids), self.package)
            if not errors:
                full = ReviewEvidencePatch.model_validate({**complete.model_dump(mode="json"),
                    "calculations": [check.model_dump(mode="json") for check in self.compiled.calculations
                        if set(check.claim_ids) <= self.groups[owner]] + [check.model_dump(mode="json") for check in complete.calculations]})
                errors = _scope_failures(full, self.groups[owner], self.package)
            self.prior[owner], self.errors[owner] = merged, errors
            if errors:
                result["evidence_diagnostics"] = evidence_shape_diagnostics(self.package, complete, set(ids),
                    quote_candidates=json.loads(request["user_prompt"]).get("math_quote_candidates", {}))
            result.update(numeric_validation_performed=True, proof_error_count=len(errors),
                          proof_error_categories=categories(errors), proof_error_positions=error_positions(errors, self.package),
                          cumulative_entry_counts=evidence_counts(complete.model_dump(mode="json")), complete_owner_evidence=not errors)
        except (ValidationError, ValueError) as exc:
            self.errors[owner] = ["Evidence response must match the schema and this exact source scope"]
            result.update(numeric_validation_performed=False, scope_or_schema_rejected=True,
                          schema_errors=schema_errors(exc, response.data))
        finally:
            assert capture == before, "Audit mutated a raw capture"

    def report(self):
        semantic_ok = not self.negative and any(
            row.get("schema_valid") and row.get("complete") and row.get("acceptable") is True
            and row.get("issue_count") == 0 and row.get("invalid_target_count") == 0 and row.get("request_hash_matches")
            for row in self.semantic)
        verified = {owner for owner in self.groups if owner in self.prior and not self.errors[owner]}
        union_errors = []
        union_schema_valid, union_schema_errors = None, []
        if semantic_ok and len(verified) == len(self.groups):
            combined = {field: [] for field in ("calculations", "literal_facts", "literal_fact_ids", "math_roles")}
            for owner in self.groups:
                for field in combined:
                    combined[field].extend(copy.deepcopy(getattr(self.prior[owner], field)))
                if self.remaining_groups[owner]:
                    combined["calculations"].extend(check.model_copy(deep=True) for check in self.compiled.calculations
                        if set(check.claim_ids) <= self.groups[owner])
            try:
                verdict = PackageReview(acceptable=True, issues=[], contains_calculations=bool(combined["calculations"]), **combined)
                union_schema_valid = True
                source, proofs = _numeric_preflight_failures(verdict.model_copy(deep=True), self.package)
                union_errors = source + proofs
            except ValidationError as exc:
                union_schema_valid, union_schema_errors = False, schema_errors(exc)
        return {"semantic_attempts": self.semantic, "proof_attempts": self.proofs,
                "known_negative_preserved": self.negative, "semantic_positive_verified": semantic_ok,
                "expected_owner_scope_count": len(self.groups), "verified_owner_scope_count": len(verified),
                "numeric_span_count": len(self.spans), "compiled_claim_count": len(self.compiled_ids),
                "residual_claim_count": len(self.spans) - len(self.compiled_ids),
                "validated_repair_target_count": len(self.validated_targets), "union_error_categories": categories(union_errors),
                "union_schema_valid": union_schema_valid, "union_schema_errors": union_schema_errors,
                "union_error_positions": error_positions(union_errors, self.package), "publication_approval_inferred": False}


class _CaptureMissing(Exception):
    pass


class _RequestMismatch(Exception):
    pass


class FinalReviewAudit:
    """Execute only frozen validation code with exact captured-response clients.

    No provider is constructed. The next capture is usable only when its schema
    and exact request SHA agree; otherwise replay stops without adjudication.
    """
    def __init__(self, package, case, sections, timing_changes=()):
        self.package, self.case = package, case
        self.sections = copy.deepcopy(sections)
        self.timings = copy.deepcopy(timing_changes)
        self.captures = []

    def append(self, capture):
        self.captures.append(copy.deepcopy(capture))

    def report(self):
        response = LLMResponse(data=render_package_results(copy.deepcopy(self.sections), self.package))
        _assemble_parallel_lesson_response(response, step=outline_for(self.case),
            material_titles={"Optional background reference"}, target_minutes=60)
        result = {"assembly_succeeded": not response.error, "known_negative_preserved":
            any(_known_negative(capture.get("data")) for capture in self.captures),
            "captured_attempt_count": len(self.captures), "request_attempts": [],
            "publication_approval_inferred": False, "validation_performed": False}
        if response.error:
            return result
        lesson = response.data
        context = self.package.review_context()
        seed = compiled_solution_evidence(lesson, context)
        result.update(word_count=len(lesson["lesson_content"].split()),
            compiled_claim_count=len({key for check in seed.calculations for key in check.claim_ids}),
            numeric_span_count=len(numeric_span_occurrences(lesson, context)))
        position = 0

        class CapturedClient:
            model = "offline-capture"
            provider_name = "dummy"
            async def generate_json(client, **request):
                nonlocal position
                if position == len(self.captures):
                    raise _CaptureMissing
                capture = self.captures[position]
                position += 1
                exact, recovered, attempts = match_request_hash(request, capture.get("request_sha256"))
                exact &= capture.get("schema") == request["output_model"].__name__
                body = json.loads(request["user_prompt"])
                result["request_attempts"].append({"exact_request_reconstructed": exact,
                    "schema_kind": "evidence_patch" if request["output_model"].__name__ == "ReviewEvidencePatch" else "whole_lesson_review",
                    "requested_claim_count": len(body.get("numeric_spans", {})),
                    "diagnostic_order_recovered": recovered, "request_hash_candidates_checked": attempts,
                    "known_negative": _known_negative(capture.get("data"))})
                if not exact:
                    raise _RequestMismatch
                return LLMResponse(**{key: copy.deepcopy(capture[key]) for key in (
                    "data", "error", "finish_reason", "retryable", "error_code", "retry_after_seconds") if key in capture})

        async def replay():
            return await review_lesson(copy.deepcopy(lesson), client_factory=lambda **_: CapturedClient(),
                context={"goal": self.case["goal"], "mentor_evidence": {}, "lesson_package": context,
                         "activity_timing_changes": self.timings})
        try:
            failures, reviewed, _ = asyncio.run(replay())
            result.update(validation_performed=True, replay_requires_more_captures=False,
                replay_finished=True, error_categories=categories(failures),
                error_positions=error_positions(failures, self.package, lesson),
                review_has_error=bool(reviewed.error), acceptable=reviewed.data.get("acceptable") is True,
                issue_count=len(reviewed.data.get("issues", [])), package_issue_count=len(reviewed.data.get("package_issues", [])),
                final_entry_counts=evidence_counts(reviewed.data))
        except _CaptureMissing:
            result.update(replay_requires_more_captures=True, replay_finished=False)
        except _RequestMismatch:
            result.update(replay_requires_more_captures=False, replay_finished=False, request_mismatch=True)
        except (ValidationError, ValueError, KeyError, TypeError) as exc:
            result.update(replay_requires_more_captures=False, replay_finished=False,
                          replay_error_type=type(exc).__name__)
        result["consumed_capture_count"] = position
        result["unused_capture_count"] = len(self.captures) - position
        if result["unused_capture_count"]:
            result.update(validation_performed=False, replay_finished=False, acceptable=False)
        if result["known_negative_preserved"]:
            result["acceptable"] = False
        return result


def independent_decimal(expression, data):
    tree = ast.parse(expression, mode="eval")
    if len(list(ast.walk(tree))) > 64:
        raise ValueError("Unsupported complexity")
    def visit(node):
        if isinstance(node, ast.Expression): return visit(node.body)
        if isinstance(node, ast.Constant) and type(node.value) in (int, float): return Decimal(str(node.value))
        if isinstance(node, ast.Name) and node.id in data: return Decimal(str(data[node.id]))
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            return visit(node.operand) * (-1 if isinstance(node.op, ast.USub) else 1)
        if isinstance(node, ast.BinOp):
            left, right = visit(node.left), visit(node.right)
            if isinstance(node.op, ast.Add): return left + right
            if isinstance(node.op, ast.Sub): return left - right
            if isinstance(node.op, ast.Mult): return left * right
            if isinstance(node.op, ast.Div): return left / right
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "sqrt" and len(node.args) == 1 and not node.keywords:
            return visit(node.args[0]).sqrt()
        raise ValueError("Unsupported expression")
    with localcontext() as context:
        context.prec = 40
        return float(visit(tree))


def package_metrics(package):
    formulas = matches = unchecked = fixed = correct = wrong = 0
    kinds = collections.Counter()
    for item in [*package.teaching_cases, *package.workbook.activities]:
        values = {datum.id: datum.value for datum in item.data}
        expressions = ([result.expression for result in item.results] if hasattr(item, "results")
                       else [field.expression for field in item.fields if field.kind == "number"])
        for expression in expressions:
            formulas += 1
            try: matches += math.isclose(calculate(expression, values), independent_decimal(expression, values), rel_tol=1e-10, abs_tol=1e-9)
            except (ValueError, ArithmeticError): unchecked += 1
    for activity in package.workbook.activities:
        values = {datum.id: datum.value for datum in activity.data}
        answers, incorrect = {}, {}
        for field in activity.fields:
            kinds[field.kind] += 1
            key = activity.id + "." + field.id
            if field.kind == "number":
                expected = independent_decimal(field.expression, values)
                answers[key], incorrect[key] = str(expected), str(expected + max(2, field.tolerance * 4))
            elif field.kind == "choice":
                answers[key] = field.correct_choice
                incorrect[key] = next(choice.id for choice in field.choices if choice.id != field.correct_choice)
            else: answers[key] = incorrect[key] = "Offline synthetic structural check"
        grades, bad = grade_fixed(activity, answers), grade_fixed(activity, incorrect)
        fixed += len(grades); correct += sum(row["passed"] for row in grades); wrong += sum(not row["passed"] for row in bad)
    ledger = build_workload_contract([activity.model_dump() for activity in package.workbook.activities])
    for index, activity in enumerate(ledger.get("activities", [])):
        activity.pop("activity_id", None); activity["activity_position"] = index
    source = source_arithmetic_failures({}, package.review_context())
    return {"activity_count": len(package.workbook.activities), "teaching_case_count": len(package.teaching_cases),
            "field_kind_counts": dict(kinds), "formula_count": formulas, "independent_decimal_matches": matches,
            "independent_decimal_unchecked": unchecked, "fixed_answer_checks": fixed, "fixed_answers_passed": correct,
            "deliberately_wrong_fixed_answers_rejected": wrong, "workload_ledger": ledger,
            "source_error_categories": categories(source), "source_error_positions": error_positions(source, package)}


def budget_aggregates(rows):
    return {"finished_count": sum(row.get("status") == "finished" for row in rows),
            "known_reported_usd": round(sum(row.get("charged_usd") or 0 for row in rows if row.get("status") == "finished" and row.get("usage_unknown") is False), 10),
            "unknown_reserved_usd": round(sum(row.get("charged_usd") or 0 for row in rows if row.get("status") == "finished" and row.get("usage_unknown") is True), 10),
            "pending_reserved_usd": round(sum(row.get("reserved_usd") or 0 for row in rows if row.get("status") == "reserved"), 10),
            "unknown_finished_count": sum(row.get("status") == "finished" and row.get("usage_unknown") is True for row in rows),
            "pending_count": sum(row.get("status") == "reserved" for row in rows),
            "missing_usage_classification_count": sum(row.get("status") == "finished" and type(row.get("usage_unknown")) is not bool for row in rows)}


BASELINE_RELEASE = "20261017-001200-structured-solutions"
BASELINE_DIGEST = "sha256:97e972c16a39963bc544ee3860ebc6ce51605dba20192df5cfae95ae55a86d73"
BASELINE_COSTS = {"accounting": (4, "0.1151932"), "geometry": (4, "0.0819282"),
                  "writing": (2, "0.0222694")}


def boundary_rows(rows, authorization, release, digest, *, baseline_reports, manifest_sha256=None, diagnostic=None):
    """Keep the second batch separate while preserving its shared budget."""
    def phase(name):
        if diagnostic is not None:
            diagnostic["phase"] = name
    phase("authorization_capacity")
    assert authorization["max_tests"] == 6 and authorization["tests_reserved"] == 6
    assert authorization["owner_approved"] is True and Decimal(str(authorization["shared_cap_usd"])) == Decimal("1.97")
    phase("authorization_scope")
    assert authorization["scope"] == "synthetic accounting, geometry, writing across v21 and follow-up fixes"
    assert authorization["ledger"] == "/opt/cmpys/releases/" + BASELINE_RELEASE + "/live-batch/usage.jsonl"
    assert len(authorization["batches"]) == 2
    first, batch = authorization["batches"]
    phase("first_batch_identity")
    assert first["label"] == "" and first["tests_reserved"] == 3
    assert first["release"] == BASELINE_RELEASE and first["image_digest"] == BASELINE_DIGEST
    assert first.get("prior_request_ids", []) == []
    assert first["container"] == "cmpys-staged-v21-batch-20261017"
    assert first["domains"] == ["accounting", "geometry", "writing"]
    phase("current_batch_identity")
    assert batch["label"] == "corrected" and batch["tests_reserved"] == 3
    assert batch["release"] == release and batch["image_digest"] == digest
    if manifest_sha256 is not None:
        assert batch["manifest_sha256"] == manifest_sha256
    phase("baseline_id_inventory")
    ids = batch["prior_request_ids"]
    assert isinstance(ids, list) and len(ids) == 10
    assert all(isinstance(key, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,100}", key) for key in ids)
    prior = set(ids)
    assert len(prior) == 10
    assert batch["container"] == "cmpys-staged-v22-batch-20261017"
    assert batch["domains"] == ["accounting", "geometry", "writing"]
    phase("baseline_accounted_metadata")
    assert Decimal(str(batch["prior_accounted_usd"])) == Decimal("0.2193908")
    phase("baseline_remaining_metadata")
    assert Decimal(str(batch["remaining_usd"])) == Decimal("1.7506092")
    phase("baseline_ledger_inventory")
    latest = {row["id"]: row for row in rows}
    assert prior <= latest.keys()
    baseline = [latest[key] for key in ids]
    assert all(row.get("status") == "finished" and row.get("usage_unknown") is False
               and row.get("tier") == "balanced" for row in baseline)
    phase("baseline_ledger_total")
    assert Decimal(str(budget_aggregates(baseline)["known_reported_usd"])) == Decimal("0.2193908")
    assert set(baseline_reports) == set(BASELINE_COSTS)
    for domain, (count, cost) in BASELINE_COSTS.items():
        phase("baseline_" + domain + "_ledger")
        scenario = domain + "_novice_missing"
        selected = [row for row in baseline if row.get("scenario_id") == scenario]
        assert len(selected) == count
        assert Decimal(str(budget_aggregates(selected)["known_reported_usd"])) == Decimal(cost)
        phase("baseline_" + domain + "_report")
        report = baseline_reports[domain]
        assert report["scenario_id"] == scenario and report["tier"] == "balanced"
        assert report["full_pipeline"] is True and report["accepted"] is False
        assert Decimal(str(round(report["estimated_cost_usd"], 10))) == Decimal(cost)
    selected = {key: row for key, row in latest.items() if key not in prior}
    ordered, seen = [], set()
    for row in rows:
        if row["id"] in selected and row.get("status") == "finished" and row["id"] not in seen:
            seen.add(row["id"]); ordered.append(row)
    return ordered, list(selected.values()), list(latest.values()), len(prior)


def audit_case(case, report, rows, captures):
    assert report["scenario_id"] == case["id"] and report["tier"] == "balanced" and report["full_pipeline"]
    assert report["validation_identity"] == validation_identity()
    selected = [row for row in rows if row.get("scenario_id") == case["id"] and row.get("tier") == "balanced"]
    assert selected, "Completed report has no current-batch requests"
    seed = package = pending_choice = pending_public = phase = final_phase = None
    activities, sections, timings = {}, {}, []
    phases, components, failures, final_reviews, transport, repairs = [], [], [], [], [], []
    repair_targets = None
    for index, row in enumerate(selected):
        ident = row["id"]
        assert re.fullmatch(r"[A-Za-z0-9_-]{1,100}", ident)
        path = captures / (ident + "-response.json")
        capture = json.loads(path.read_text()) if path.exists() else {}
        schema = capture.get("schema") or row.get("schema")
        safe_schema = schema if schema in {"LessonPackageSeed", "LessonActivityDraft", "LessonPackageActivity", "LessonPackage", "PrivatePackageRepair", "PackageSemanticReview", "ReviewEvidencePatch", "LessonReview", "PackagedLessonReview", "PlanDetailSectionsRepairOutput"} or isinstance(schema, str) and re.fullmatch(r"LessonSectionGroup_(framing|mechanism|worked|practice)", schema) else "other"
        error_class = next((name for name in TRANSPORT_CLASSES if name in str(capture.get("error") or row.get("error") or "")), None)
        transport.append({"schema": safe_schema, "response_present": bool(capture), "duration_ms": row.get("duration_ms"),
                          "finish_reason": safe_finish_reason(row.get("finish_reason")), "error_class": error_class,
                          "has_error": bool(capture.get("error") or row.get("error")), "usage_unknown": row.get("usage_unknown"),
                          "output_limit": (capture.get("finish_reason") or row.get("finish_reason")) == "length",
                          "transport_timeout": error_class in ("TimeoutError", "APITimeoutError")})
        if not capture:
            continue
        before = copy.deepcopy(capture)
        data = capture.get("data") or {}
        complete = not capture.get("error") and capture.get("finish_reason") in (None, "stop")
        if schema in ("LessonPackageSeed", "LessonActivityDraft"):
            model = LessonPackageSeed if schema == "LessonPackageSeed" else LessonActivityDraft
            wire, _ = wire_diagnostic(capture, model)
            component = {"position": index, "schema": schema, "wire": wire, "complete": complete}
            if schema == "LessonActivityDraft":
                component["shape"] = component_shape_diagnostics(data)
            components.append(component)
        try:
            if schema == "PackageSemanticReview" and package is not None:
                if phase is None:
                    phase = PreflightAudit(package, case, timings); phases.append(phase)
                phase.semantic_capture(capture)
                repair_targets = sorted(phase.validated_targets) or None
            elif schema == "ReviewEvidencePatch" and phase is not None:
                phase.proof_capture(capture)
                repair_targets = sorted(phase.validated_targets) or None
            elif schema == "ReviewEvidencePatch" and final_phase is not None:
                final_phase.append(capture)
            elif not complete and schema not in ("LessonReview", "PackagedLessonReview"):
                continue
            elif schema == "LessonPackageSeed":
                parsed, identity_count, note_count = _parse_initial_seed_response_details(copy.deepcopy(data))
                repeated, repeated_identity, repeated_note = _parse_initial_seed_response_details(copy.deepcopy(data))
                public, public_identity = parse_initial_seed_response(copy.deepcopy(data))
                assert parsed == repeated == public and identity_count == repeated_identity == public_identity and note_count == repeated_note
                seed, package, activities, sections, phase, timings = parsed, None, {}, {}, None, []
                final_phase, pending_choice, pending_public, repair_targets = None, None, None, None
                component.update(contract_valid=True, id_normalization_count=identity_count, note_normalization_count=note_count)
            elif schema == "LessonActivityDraft":
                if pending_choice is not None or pending_public is not None:
                    repair_kind = "cleared_choice_replacement" if pending_choice is not None else "scoped_public_activity_replacement"
                    replacement = parse_activity_draft(data)
                    if pending_choice is not None:
                        original, targets, scope = pending_choice
                        _replace_choice_activity(package, original, targets, replacement)
                    else:
                        scope = pending_public
                    new_package = _replace_public_activity(package, scope, replacement)
                    repairs.append({"position": index, "kind": repair_kind, "request_hash_verified": False,
                                    **package_change_metadata(package, new_package)})
                    timings = activity_timing_changes(package.writer_context()["practice"], new_package.writer_context()["practice"])
                    package, pending_choice, pending_public, phase, sections = new_package, None, None, None, {}
                    final_phase, repair_targets = None, None
                    activities = {activity.id: activity for activity in package.workbook.activities}
                else:
                    if seed is None or package is not None:
                        raise ValueError("Activity capture has no matching seed")
                    brief = next((brief for brief in seed.activity_briefs if brief.id == data.get("id")), None)
                    if brief is None: raise ValueError("Activity identity differs from seed")
                    activities[brief.id] = _validated_activity(parse_activity_draft(data), seed, brief)
                    if all(brief.id in activities for brief in seed.activity_briefs):
                        package = LessonPackage.model_validate({"teaching_cases": [item.model_dump(mode="json") for item in seed.teaching_cases],
                            "workbook": {"title": seed.workbook_title, "activities": [activities[brief.id].model_dump(mode="json") for brief in seed.activity_briefs]}})
                component["contract_valid"] = True
            elif schema == "LessonPackageActivity":
                # This release requests only the field-local draft DTO. Do not
                # reinterpret an old wire schema as a new provider response.
                failures.append({"position": index, "schema": safe_schema,
                                 "errors": [{"type": "obsolete_activity_wire_schema"}]})
            elif schema == "LessonPackage":
                revised = parse_package_response(data)
                if package is not None:
                    repairs.append({"position": index, "kind": "full_package_replacement",
                                    **package_change_metadata(package, revised)})
                timings = activity_timing_changes(package.writer_context()["practice"], revised.writer_context()["practice"]) if package else []
                if package and package.writer_context() != revised.writer_context(): sections = {}
                package, phase, final_phase, repair_targets = revised, None, None, None
            elif schema == "PrivatePackageRepair" and package is not None:
                repair = PrivatePackageRepair.model_validate(data)
                scope = _validated_repair_scope(package, repair_targets)
                _check_private_repair_scope(repair, scope)
                target = _cleared_choice_targets(package, repair)
                if target:
                    if scope is None or len(scope) != 1 or target[0].id not in scope or (
                            scope[target[0].id] is not None and not target[1] <= scope[target[0].id]):
                        raise ValueError("Unverified public correction scope")
                    pending_choice = (*target, scope)
                elif repair.public_defects:
                    if repair.field_patches or repair.solution_patches or scope is None or len(scope) != 1:
                        raise ValueError("Unverified public correction scope")
                    pending_public = scope
                else:
                    revised = apply_private_package_repair(package, repair, repair_targets=repair_targets)
                    repairs.append({"position": index, "kind": "private_package_repair", "request_hash_verified": False,
                                    **package_change_metadata(package, revised)})
                    timings = activity_timing_changes(package.writer_context()["practice"], revised.writer_context()["practice"])
                    if package.writer_context() != revised.writer_context(): sections = {}
                    package, phase, final_phase, repair_targets = revised, None, None, None
            elif isinstance(schema, str) and schema.startswith("LessonSectionGroup_"):
                sections.update(copy.deepcopy(data)); phase = final_phase = None
                repair_targets = None
            elif schema == "PlanDetailSectionsRepairOutput":
                parsed = PlanDetailSectionsRepairOutput.model_validate(data)
                sections.update({item.field_name: item.content for item in parsed.sections}); phase = final_phase = None
                repair_targets = None
            elif schema in ("LessonReview", "PackagedLessonReview") and package is not None:
                phase = None
                if final_phase is None:
                    final_phase = FinalReviewAudit(package, case, sections, timings)
                    final_reviews.append(final_phase)
                final_phase.append(capture)
            elif schema == "ReviewEvidencePatch":
                failures.append({"position": index, "schema": safe_schema,
                    "errors": [{"type": "unowned_final_evidence_capture"}]})
        except (ValidationError, ValueError, SyntaxError, KeyError, TypeError) as exc:
            item = {"position": index, "schema": safe_schema, "errors": schema_errors(exc, data)}
            failures.append(item)
            if schema in ("LessonPackageSeed", "LessonActivityDraft"):
                component.update(contract_valid=False, errors=item["errors"])
        assert capture == before, "Audit mutated raw capture"
    result = {"scenario_id": case["id"], "accepted_report": report.get("accepted"), "elapsed_ms": report.get("elapsed_ms"),
              "failure_categories": categories(report.get("failures", [])), "components": components,
              "component_failures": failures, "repairs": repairs, "preflights": [item.report() for item in phases],
              "final_reviews": [item.report() for item in final_reviews], "package_available": package is not None,
              "validated_activity_count": len(activities), "transport": transport, "budget": budget_aggregates(selected),
              "output_limit_count": sum(row["output_limit"] for row in transport),
              "transport_timeout_count": sum(row["transport_timeout"] for row in transport),
              "publication_approval_inferred": False, "quality_scope": "structural and arithmetic evidence; no new semantic adjudication"}
    if package is not None: result["package_metrics"] = package_metrics(package)
    return result


def _run_audit(config, diagnostic):
    diagnostic["phase"] = "manifest_verification"
    for filename, expected in config["manifest"].items():
        assert hashlib.sha256(Path(filename).read_bytes()).hexdigest() == expected, "Frozen source mismatch"
    diagnostic["phase"] = "runtime_import"
    load_runtime()
    captures = Path("/captures")
    diagnostic["phase"] = "authorization_read"
    authorization = json.loads((captures / "authorization.json").read_text())
    rows = []
    diagnostic["phase"] = "ledger_read"
    lines = (captures / "usage.jsonl").read_text().splitlines()
    for index, line in enumerate(lines):
        try: rows.append(json.loads(line))
        except ValueError:
            assert index == len(lines) - 1, "Malformed ledger row"
    diagnostic["phase"] = "capture_release"
    assert config["capture_release"] == BASELINE_RELEASE
    diagnostic["phase"] = "baseline_reports_read"
    baseline_reports = {domain: json.loads((captures / (domain + "_novice_missing-balanced.json")).read_text())
                        for domain in BASELINE_COSTS}
    ordered, current, shared, excluded = boundary_rows(rows, authorization, config["release"], config["digest"],
        baseline_reports=baseline_reports, manifest_sha256=config["manifest_sha256"], diagnostic=diagnostic)
    diagnostic["phase"] = "scenario_fixture_read"
    fixture = Path("/scenarios.json").read_bytes()
    diagnostic["phase"] = "scenario_fixture_hash"
    assert hashlib.sha256(fixture).hexdigest() == config["fixture_sha256"]
    cases = json.loads(fixture)
    completed = 0
    for domain in config["cases"]:
        diagnostic["phase"] = "selected_case_lookup"
        case = next(case for case in cases if case["id"] == domain + "_novice_missing")
        path = captures / (case["id"] + "-corrected-balanced.json")
        if not path.exists():
            print(json.dumps({"scenario_id": case["id"], "status": "report_not_complete"}), flush=True)
            continue
        diagnostic["phase"] = "selected_case_pending_check"
        assert not any(row.get("scenario_id") == case["id"] and row.get("status") == "reserved" for row in current), "Case still pending"
        try:
            result = audit_case(case, json.loads(path.read_text()), ordered, captures)
            if config["mode"] == "components":
                result = {key: result[key] for key in ("scenario_id", "components", "component_failures", "transport", "budget")}
        except Exception as exc:
            result = {"scenario_id": case["id"], "audit_error_type": type(exc).__name__}
        print(json.dumps(result, ensure_ascii=False, sort_keys=True), flush=True)
        completed += 1
    print(json.dumps({"completed_reports_audited": completed, "boundary_excluded_request_count": excluded,
                      "current_batch_budget": budget_aggregates(current), "shared_ledger_budget": budget_aggregates(shared),
                      "provider": "dummy", "network": "disabled", "captures": "read_only", "publication": "none"}), flush=True)


def run_audit(config):
    """Expose only a fixed phase and exception class if setup fails.

    Messages/tracebacks can include source content; they are never printed.
    This does not convert a setup failure into a completed validation report.
    """
    diagnostic = {"phase": "setup"}
    try:
        _run_audit(config, diagnostic)
    except Exception as exc:
        safe_types = {"AssertionError", "KeyError", "TypeError", "ValueError", "FileNotFoundError",
                      "PermissionError", "IsADirectoryError", "JSONDecodeError", "ImportError", "ModuleNotFoundError", "OSError"}
        error_type = type(exc).__name__
        print(json.dumps({"audit_error_phase": diagnostic["phase"],
            "audit_error_type": error_type if error_type in safe_types else "other_error",
            "validation_performed": False, "publication": "none"}), flush=True)
