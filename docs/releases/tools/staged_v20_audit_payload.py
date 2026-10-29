"""Offline, aggregate-only v20 capture audit; never calls a provider.

Executed inside the pinned image with no network and read-only captures.
No generated prose, issue description, formula, quote, or identifier is output.
"""
import ast
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
    global _parse_initial_seed_response_details, parse_initial_seed_response, _validated_activity
    global parse_package_response, apply_private_package_repair, _cleared_choice_targets, _replace_choice_activity
    global PackageSemanticReview, ReviewEvidencePatch, PackageReview, _targets, _known_negative
    global package_review_payload, _evidence_patch_request, _merge_evidence_patch
    global _scope_failures, _patch_verdict, _evidence_review, _evidence_ids, _numeric_preflight_failures
    global normalize_response_case_aliases, numeric_span_occurrences, source_arithmetic_failures
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
        validation_identity, render_package_results,
    )
    from app.services.planning.package_builder import (
        LessonPackageSeed, LessonPackageActivity, _parse_initial_seed_response_details,
        parse_initial_seed_response, _validated_activity,
    )
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
        _canonical_review_data, grounded_failures,
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
    for model in (LessonPackage, LessonPackageSeed, LessonPackageActivity, PrivatePackageRepair,
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
        return [{"type": "component_contract", "category": known.get(str(exc), "other_contract")}]
    result = []
    for error in exc.errors(include_input=False, include_context=False, include_url=False):
        item = {"type": error["type"], "path": [part if type(part) is int or part in FIELDS else "<unknown>"
                                               for part in error["loc"]]}
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
        candidate = json.dumps(body, ensure_ascii=False, separators=(",", ":"))
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
        self.spans = self.payload["numeric_spans"]
        self.owners = self.payload["numeric_span_owners"]
        self.positions = {activity.id: index for index, activity in enumerate(package.workbook.activities)}
        self.groups = {activity.id: {key for key, owner in self.owners.items() if owner == "practice." + activity.id}
                       for activity in package.workbook.activities}
        self.groups = {owner: ids for owner, ids in self.groups.items() if ids}
        body = {key: value for key, value in self.payload.items() if key in {
            "outline", "context", "capabilities", "package", "numerical_evidence", "workload_contract"}}
        self.semantic_hash = hashlib.sha256(json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
        self.prior, self.errors, self.semantic, self.proofs = {}, {}, [], []
        self.negative = False

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
        except ValidationError as exc:
            result.update(schema_valid=False, schema_errors=schema_errors(exc, data))
        self.semantic.append(result)

    def proof_capture(self, capture):
        before = copy.deepcopy(capture)
        data = capture.get("data") or {}
        self.negative |= _known_negative(data)
        result = {"known_negative": _known_negative(data), "entry_counts": evidence_counts(data),
                  "finish_reason": capture.get("finish_reason"), "has_error": bool(capture.get("error"))}
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
        ids = self.groups[owner]
        result.update(owner_activity_position=self.positions[owner], recorded_scope_count=len(recorded),
                      owner_total_claim_count=len(ids))
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
                return
            merged = _merge_evidence_patch(prior, patch, scope, payload["numeric_spans"])
            complete = ReviewEvidencePatch.model_validate(merged.model_dump(mode="json", include={
                "calculations", "literal_facts", "literal_fact_ids", "math_roles"}))
            errors = _scope_failures(complete, set(ids), self.package)
            self.prior[owner], self.errors[owner] = merged, errors
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
                "numeric_span_count": len(self.spans), "union_error_categories": categories(union_errors),
                "union_schema_valid": union_schema_valid, "union_schema_errors": union_schema_errors,
                "union_error_positions": error_positions(union_errors, self.package), "publication_approval_inferred": False}


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


def boundary_rows(rows, authorization, release, digest):
    assert authorization["tests_reserved"] == 6 and len(authorization["batches"]) == 2
    batch = authorization["batches"][1]
    assert batch["label"] == "corrected" and batch["tests_reserved"] == 3
    assert batch["release"] == release and batch["image_digest"] == digest
    prior = set(batch["prior_request_ids"])
    assert prior and len(prior) == len(batch["prior_request_ids"])
    latest = {row["id"]: row for row in rows}
    assert prior <= latest.keys()
    selected = {key: row for key, row in latest.items() if key not in prior}
    # Completion order matters for repairs, while original inventory IDs bind
    # concurrent evidence scopes independently of their completion order.
    ordered, seen = [], set()
    for row in rows:
        if row["id"] in selected and row.get("status") == "finished" and row["id"] not in seen:
            seen.add(row["id"]); ordered.append(row)
    return ordered, list(selected.values()), list(latest.values()), len(prior)


def audit_case(case, report, rows, captures):
    assert report["scenario_id"] == case["id"] and report["tier"] == "balanced" and report["full_pipeline"]
    assert report["validation_identity"] == validation_identity()
    selected = [row for row in rows if row.get("scenario_id") == case["id"] and row.get("tier") == "balanced"]
    assert selected, "Corrected report has no second-batch requests"
    seed = package = pending_choice = phase = None
    activities, sections, timings = {}, {}, []
    phases, components, failures, final_reviews, transport, repairs = [], [], [], [], [], []
    for index, row in enumerate(selected):
        ident = row["id"]
        assert re.fullmatch(r"[A-Za-z0-9_-]{1,100}", ident)
        path = captures / (ident + "-response.json")
        capture = json.loads(path.read_text()) if path.exists() else {}
        schema = capture.get("schema") or row.get("schema")
        safe_schema = schema if schema in {"LessonPackageSeed", "LessonPackageActivity", "LessonPackage", "PrivatePackageRepair", "PackageSemanticReview", "ReviewEvidencePatch", "LessonReview", "PackagedLessonReview", "PlanDetailSectionsRepairOutput"} or isinstance(schema, str) and re.fullmatch(r"LessonSectionGroup_(framing|mechanism|worked|practice)", schema) else "other"
        error_class = next((name for name in TRANSPORT_CLASSES if name in str(capture.get("error") or row.get("error") or "")), None)
        transport.append({"schema": safe_schema, "response_present": bool(capture), "duration_ms": row.get("duration_ms"),
                          "finish_reason": row.get("finish_reason"), "error_class": error_class,
                          "has_error": bool(capture.get("error") or row.get("error")), "usage_unknown": row.get("usage_unknown"),
                          "output_limit": (capture.get("finish_reason") or row.get("finish_reason")) == "length",
                          "transport_timeout": error_class in ("TimeoutError", "APITimeoutError")})
        if not capture:
            continue
        before = copy.deepcopy(capture)
        data = capture.get("data") or {}
        complete = not capture.get("error") and capture.get("finish_reason") in (None, "stop")
        if schema in ("LessonPackageSeed", "LessonPackageActivity"):
            model = LessonPackageSeed if schema == "LessonPackageSeed" else LessonPackageActivity
            wire, _ = wire_diagnostic(capture, model)
            component = {"position": index, "schema": schema, "wire": wire, "complete": complete}
            components.append(component)
        try:
            if schema == "PackageSemanticReview" and package is not None:
                if phase is None:
                    phase = PreflightAudit(package, case, timings); phases.append(phase)
                phase.semantic_capture(capture)
            elif schema == "ReviewEvidencePatch" and phase is not None:
                phase.proof_capture(capture)
            elif not complete:
                continue
            elif schema == "LessonPackageSeed":
                parsed, identity_count, note_count = _parse_initial_seed_response_details(copy.deepcopy(data))
                repeated, repeated_identity, repeated_note = _parse_initial_seed_response_details(copy.deepcopy(data))
                public, public_identity = parse_initial_seed_response(copy.deepcopy(data))
                assert parsed == repeated == public and identity_count == repeated_identity == public_identity and note_count == repeated_note
                seed, package, activities, sections, phase, timings = parsed, None, {}, {}, None, []
                component.update(contract_valid=True, id_normalization_count=identity_count, note_normalization_count=note_count)
            elif schema == "LessonPackageActivity":
                if pending_choice is not None:
                    prior, original, targets = pending_choice
                    assert package == prior
                    replacement = LessonPackageActivity.model_validate(data)
                    new_package = _replace_choice_activity(package, original, targets, replacement)
                    repairs.append({"position": index, "kind": "cleared_choice_replacement",
                                    **package_change_metadata(package, new_package)})
                    timings = activity_timing_changes(package.writer_context()["practice"], new_package.writer_context()["practice"])
                    package, pending_choice, phase, sections = new_package, None, None, {}
                    activities = {activity.id: activity for activity in package.workbook.activities}
                else:
                    if seed is None or package is not None:
                        raise ValueError("Activity capture has no matching seed")
                    brief = next((brief for brief in seed.activity_briefs if brief.id == data.get("id")), None)
                    if brief is None: raise ValueError("Activity identity differs from seed")
                    activities[brief.id] = _validated_activity(data, seed, brief)
                    if all(brief.id in activities for brief in seed.activity_briefs):
                        package = LessonPackage.model_validate({"teaching_cases": [item.model_dump(mode="json") for item in seed.teaching_cases],
                            "workbook": {"title": seed.workbook_title, "activities": [activities[brief.id].model_dump(mode="json") for brief in seed.activity_briefs]}})
                component["contract_valid"] = True
            elif schema == "LessonPackage":
                revised = parse_package_response(data)
                if package is not None:
                    repairs.append({"position": index, "kind": "full_package_replacement",
                                    **package_change_metadata(package, revised)})
                timings = activity_timing_changes(package.writer_context()["practice"], revised.writer_context()["practice"]) if package else []
                if package and package.writer_context() != revised.writer_context(): sections = {}
                package, phase = revised, None
            elif schema == "PrivatePackageRepair" and package is not None:
                repair = PrivatePackageRepair.model_validate(data)
                target = _cleared_choice_targets(package, repair)
                if target:
                    pending_choice = (package, *target)
                else:
                    revised = apply_private_package_repair(package, repair)
                    repairs.append({"position": index, "kind": "private_package_repair",
                                    **package_change_metadata(package, revised)})
                    timings = activity_timing_changes(package.writer_context()["practice"], revised.writer_context()["practice"])
                    if package.writer_context() != revised.writer_context(): sections = {}
                    package, phase = revised, None
            elif isinstance(schema, str) and schema.startswith("LessonSectionGroup_"):
                sections.update(copy.deepcopy(data)); phase = None
            elif schema == "PlanDetailSectionsRepairOutput":
                parsed = PlanDetailSectionsRepairOutput.model_validate(data)
                sections.update({item.field_name: item.content for item in parsed.sections}); phase = None
            elif schema in ("LessonReview", "PackagedLessonReview") and package is not None:
                phase = None
                response = LLMResponse(data=render_package_results(copy.deepcopy(sections), package))
                _assemble_parallel_lesson_response(response, step=outline_for(case), material_titles={"Optional background reference"}, target_minutes=60)
                metric = {"assembly_succeeded": not response.error, "known_negative": _known_negative(data),
                          "reconstruction_basis": "captured_sections_only; provisional until final request hash is reconstructed",
                          "request_hash_verified": False}
                if not response.error:
                    reviewed = LLMResponse(data=copy.deepcopy(data))
                    normalize_response_case_aliases(reviewed, package.review_context())
                    verdict = PackagedLessonReview.model_validate(_canonical_review_data(reviewed.data, packaged=True))
                    errors = grounded_failures(verdict, response.data, package.review_context()) + verdict.failures()
                    metric.update(word_count=len(response.data["lesson_content"].split()), acceptable=verdict.acceptable,
                                  issue_count=len(verdict.issues), package_issue_count=len(verdict.package_issues),
                                  error_categories=categories(errors), error_positions=error_positions(errors, package, response.data))
                final_reviews.append(metric)
            elif schema == "ReviewEvidencePatch":
                final_reviews.append({"final_patch_present": True, "replay_status": "not_replayed; no alternate acceptance inferred"})
        except (ValidationError, ValueError, SyntaxError, KeyError, TypeError) as exc:
            item = {"position": index, "schema": safe_schema, "errors": schema_errors(exc, data)}
            failures.append(item)
            if schema in ("LessonPackageSeed", "LessonPackageActivity"):
                component.update(contract_valid=False, errors=item["errors"])
        assert capture == before, "Audit mutated raw capture"
    result = {"scenario_id": case["id"], "accepted_report": report.get("accepted"), "elapsed_ms": report.get("elapsed_ms"),
              "failure_categories": categories(report.get("failures", [])), "components": components,
              "component_failures": failures, "repairs": repairs, "preflights": [item.report() for item in phases],
              "final_reviews": final_reviews, "package_available": package is not None,
              "validated_activity_count": len(activities), "transport": transport, "budget": budget_aggregates(selected),
              "output_limit_count": sum(row["output_limit"] for row in transport),
              "transport_timeout_count": sum(row["transport_timeout"] for row in transport),
              "publication_approval_inferred": False, "quality_scope": "structural and arithmetic evidence; no new semantic adjudication"}
    if package is not None: result["package_metrics"] = package_metrics(package)
    return result


def run_audit(config):
    for filename, expected in config["manifest"].items():
        assert hashlib.sha256(Path(filename).read_bytes()).hexdigest() == expected, "Frozen source mismatch"
    load_runtime()
    captures = Path("/captures")
    authorization = json.loads((captures / "authorization.json").read_text())
    rows = []
    lines = (captures / "usage.jsonl").read_text().splitlines()
    for index, line in enumerate(lines):
        try: rows.append(json.loads(line))
        except ValueError:
            assert index == len(lines) - 1, "Malformed ledger row"
    ordered, current, shared, excluded = boundary_rows(rows, authorization, config["release"], config["digest"])
    cases = json.loads(Path("/scenarios.json").read_text())
    completed = 0
    for domain in config["cases"]:
        case = next(case for case in cases if case["id"] == domain + "_novice_missing")
        path = captures / (case["id"] + "-corrected-balanced.json")
        if not path.exists():
            print(json.dumps({"scenario_id": case["id"], "status": "corrected_report_not_complete"}), flush=True)
            continue
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
