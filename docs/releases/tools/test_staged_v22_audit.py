"""Synthetic in-memory regressions; no provider, SSH, database, or capture access."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path


def run_tests():
    path = Path(__file__).with_name("staged_v22_audit_payload.py")
    spec = importlib.util.spec_from_file_location("staged_v22_payload_tests", path)
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    audit.load_runtime()
    from scripts.pilot_generation import _request_diagnostics
    from tests.test_preflight_checkpoint_task_wiring import quantitative_package

    body = {"private_source": "Exact synthetic source stays private", "verification_defects": [
        "n1: numeric span contains additional unverified values", "n2: numeric span contains additional unverified values"],
        "private_evidence": {"unchanged": True}}
    request = {"user_prompt": json.dumps(body, ensure_ascii=False, separators=(",", ":"))}
    reversed_body = copy.deepcopy(body); reversed_body["verification_defects"].reverse()
    expected = hashlib.sha256(json.dumps(reversed_body, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
    assert audit.match_request_hash(request, expected)[:2] == (True, True)
    changed = copy.deepcopy(reversed_body); changed["private_evidence"]["unchanged"] = False
    different = hashlib.sha256(json.dumps(changed, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
    assert audit.match_request_hash(request, different)[0] is False
    assert json.loads(request["user_prompt"]) == body

    package = quantitative_package()
    case = {"id": "writing_novice_missing", "goal": "Synthetic exact arithmetic review",
            "learner_level": "novice", "locale": "hy", "untrusted_note": "Synthetic untrusted reference"}
    phase = audit.PreflightAudit(package, case)
    body = {key: value for key, value in phase.payload.items() if key in {
        "outline", "context", "capabilities", "package", "numerical_evidence", "workload_contract"}}
    semantic = {"schema": "PackageSemanticReview", "data": {"acceptable": True, "issues": []},
                "finish_reason": "stop", **_request_diagnostics(json.dumps(body, ensure_ascii=False,
                    separators=(",", ":")), "PackageSemanticReview")}

    def proof_capture(target, owner, *, bad=False, empty=False):
        ids = target.groups[owner]
        payload = {**target.payload,
                   "numeric_spans": {key: value for key, value in target.spans.items() if key in ids},
                   "numeric_span_owners": {key: value for key, value in target.owners.items() if key in ids}}
        prior = target.prior.get(owner, audit.PackageReview(acceptable=True, issues=[]))
        request, scope = audit._evidence_patch_request(prior, payload, target.errors.get(owner, []))
        data = {} if empty else {"calculations": [{"claim_ids": sorted(scope), "case_id": "practice." + owner,
                "expression": "receipts + revenue" if bad else "receipts - revenue",
                "claimed_result": 20 if owner == "guided" else 25}]}
        return {"schema": "ReviewEvidencePatch", "data": data, "finish_reason": "stop",
                **_request_diagnostics(request["user_prompt"], "ReviewEvidencePatch")}

    originals = [semantic, proof_capture(phase, "guided"), proof_capture(phase, "transfer")]
    before = copy.deepcopy(originals)
    phase.semantic_capture(semantic)
    # Completion order need not match source order. Exact recorded claims bind
    # transfer to original activity one, even when scoped owner position is zero.
    phase.proof_capture(originals[2])
    phase.proof_capture(originals[1])
    result = phase.report()
    assert result["semantic_positive_verified"] and result["verified_owner_scope_count"] == 2
    assert not result["union_error_categories"] and not result["publication_approval_inferred"]
    assert [row["owner_activity_position"] for row in result["proof_attempts"]] == [1, 0]
    assert all(row["exact_request_reconstructed"] for row in result["proof_attempts"])
    assert originals == before

    oversized_union = audit.PreflightAudit(package, case)
    oversized_union.semantic_capture(semantic)
    for owner, capture in zip(("guided", "transfer"), originals[1:]):
        oversized_union.prior[owner] = audit.PackageReview(acceptable=True, issues=[], contains_calculations=True,
            calculations=[copy.deepcopy(capture["data"]["calculations"][0]) for _ in range(40)])
        oversized_union.errors[owner] = []
    union = oversized_union.report()
    assert union["union_schema_valid"] is False and union["union_schema_errors"]
    assert union["verified_owner_scope_count"] == 2 and not union["publication_approval_inferred"]

    correcting = audit.PreflightAudit(package, case)
    correcting.semantic_capture(semantic)
    failed = proof_capture(correcting, "guided", bad=True)
    correcting.proof_capture(failed)
    assert correcting.proofs[-1]["proof_error_count"] > 0
    correcting.proof_capture(proof_capture(correcting, "transfer"))
    correcting.proof_capture(proof_capture(correcting, "guided"))
    assert correcting.report()["verified_owner_scope_count"] == 2
    assert correcting.proofs[-1]["exact_request_reconstructed"]

    wrong_owner = audit.PreflightAudit(package, case)
    cross = copy.deepcopy(originals[1]); cross["data"] = copy.deepcopy(originals[2]["data"])
    wrong_owner.proof_capture(cross)
    assert wrong_owner.proofs[0]["outside_requested_scope_count"] > 0
    assert wrong_owner.proofs[0]["scope_or_schema_rejected"]

    unknown_request = audit.PreflightAudit(package, case)
    mismatched = copy.deepcopy(originals[1]); mismatched["request_sha256"] = "0" * 64
    unknown_request.proof_capture(mismatched)
    assert not unknown_request.proofs[0]["exact_request_reconstructed"]
    assert not unknown_request.proofs[0]["numeric_validation_performed"]
    assert "evidence_diagnostics" not in unknown_request.proofs[0]
    missing_scope = copy.deepcopy(originals[1]); missing_scope.pop("request_claim_ids")
    unknown_request.proof_capture(missing_scope)
    assert not unknown_request.proofs[-1]["recorded_scope_valid"]

    empty = audit.PreflightAudit(package, case)
    empty.proof_capture(proof_capture(empty, "guided", empty=True))
    assert empty.proofs[0]["owner_activity_position"] == 0 and empty.proofs[0]["proof_error_count"] > 0
    truncated = audit.PreflightAudit(package, case)
    incomplete = copy.deepcopy(originals[1]); incomplete.update(error="Synthetic output ceiling", finish_reason="length")
    truncated.proof_capture(incomplete)
    assert truncated.proofs[0]["exact_request_reconstructed"] and not truncated.proofs[0]["numeric_validation_performed"]

    for data in ({"acceptable": False, "issues": [{"target": "practice.unowned", "description": "Private synthetic diagnostic must stay private."}]},
                 {"acceptable": False, "issues": [{"field": True, "message": "placeholder"}]}):
        negative = audit.PreflightAudit(package, case)
        negative.semantic_capture({**semantic, "data": data})
        negative.semantic_capture(semantic)
        assert negative.report()["known_negative_preserved"]
        assert not negative.report()["semantic_positive_verified"]
        assert "Private synthetic diagnostic" not in json.dumps(negative.report())
        assert "unowned" not in json.dumps(negative.report())

    issue = audit.PackageSemanticReview.model_validate({"acceptable": False, "issues": [{
        "target": "practice.guided", "description": "The workload duration and answer criteria need revision."}]}).issues[0]
    metadata = audit.semantic_issue_metadata(issue, package)
    assert metadata["target_kind"] == "activity" and metadata["owner_position"] == 0
    assert metadata["lexical_flags"]["workload"] and metadata["lexical_flags"]["answer_or_solution"]
    assert issue.description not in json.dumps(metadata) and issue.target not in json.dumps(metadata)
    critique = "The task is underdetermined because of a missing constraint; multiple valid answers conflict with the answer key."
    assert set(audit.critique_phrase_matches(critique)) == {"underdetermined", "missing_constraint", "ambiguity_or_multiple_answers", "choice_answer_key"}
    assert audit.critique_phrase_matches("A private sentence about a unique example.") == []
    assert audit.critique_phrase_matches("The task is not ambiguous.") == ["ambiguity_or_multiple_answers"]
    # A match remains explicitly lexical: even negated phrases are not adjudicated.
    assert metadata["flag_basis"] == "literal keyword matches only; not a semantic adjudication"
    altered = package.model_copy(deep=True)
    altered.workbook.activities[0].worked_solution = "Private replacement source never printed."
    changes = audit.package_change_metadata(package, altered)
    assert changes["changed_leaf_count"] == 1 and changes["omitted_path_count"] == 0
    assert changes["changed_paths"] == [{"path": ["workbook", "activities", 0, "worked_solution"], "change_kind": "modified", "before_type": "str", "after_type": "str"}]
    assert changes["teaching_cases_unchanged"] and changes["activity_order_unchanged"]
    assert "Private replacement source" not in json.dumps(changes)
    assert audit.category("n12: calculation cannot be verified") == "calculation cannot be verified"

    seed_data = {"workbook_title": package.workbook.title, "teaching_cases": [],
                 "activity_briefs": [{"id": item.id, "kind": item.kind, "scope": item.instructions}
                                     for item in package.workbook.activities]}
    fresh = copy.deepcopy(seed_data)
    fresh["teaching_cases"] = [{"assumptions": "The fictional input is doubled with the same unit.",
        "data": [{"id": "base", "label": "Base input", "value": 10, "unit": "m"}],
        "results": [{"id": "double", "label": "Doubled input", "expression": "base * 2", "unit": "m", "decimal_places": 1}]}]
    fresh["activity_briefs"][1]["kind_note"] = " Preserve this note exactly. "
    raw = copy.deepcopy(fresh)
    parsed, identities, notes = audit._parse_initial_seed_response_details(copy.deepcopy(fresh))
    assert identities == notes == 1 and fresh == raw
    assert parsed.activity_briefs[1].scope == raw["activity_briefs"][1]["scope"] + "\n" + raw["activity_briefs"][1]["kind_note"]
    try: audit.LessonPackageSeed.model_validate(fresh)
    except audit.ValidationError: pass
    else: raise AssertionError("Saved canonical models must remain strict")
    duplicate, value = audit.wire_diagnostic({"visible_response": '{"kind":"a","kind":"a"}'}, audit.LessonPackageSeed)
    assert duplicate["category"] == "duplicate_property" and value is None
    malformed, value = audit.wire_diagnostic({"visible_response": '{1:"Private source"}'}, audit.LessonPackageSeed)
    assert malformed["status"] == "malformed_json" and value is None
    assert "Private source" not in json.dumps(malformed)

    class MemoryFile:
        def __init__(self, files, name): self.files, self.name = files, name
        def exists(self): return self.name in self.files
        def read_text(self): return json.dumps(self.files[self.name])
    class MemoryCaptures:
        def __init__(self, files): self.files = files
        def __truediv__(self, name): return MemoryFile(self.files, name)

    sequence = [("LessonPackageSeed", seed_data), *[("LessonActivityDraft", activity.model_dump(mode="json")) for activity in package.workbook.activities]]
    captures = {str(index) + "-response.json": {"schema": schema, "data": data, "visible_response": json.dumps(data), "finish_reason": "stop"}
                for index, (schema, data) in enumerate(sequence)}
    for index, capture in enumerate(originals, len(sequence)): captures[str(index) + "-response.json"] = capture
    rows = [{"id": key.removesuffix("-response.json"), "scenario_id": case["id"], "tier": "balanced",
             "status": "finished", "usage_unknown": False, "charged_usd": 0.01} for key in captures]
    ordered = boundary_tests(audit, rows)
    report = {"scenario_id": case["id"], "tier": "balanced", "full_pipeline": True,
              "validation_identity": audit.validation_identity(), "accepted": False, "failures": []}
    before = copy.deepcopy(captures)
    complete = audit.audit_case(case, report, ordered, MemoryCaptures(captures))
    # Canonical/legacy shape is not the provider DTO. Saved packages still use
    # their ordinary proof path, but fresh wire captures must not be inferred.
    assert not complete["package_available"] and complete["component_failures"]
    assert not complete["preflights"]
    assert complete["output_limit_count"] == complete["transport_timeout_count"] == 0
    assert captures == before
    encoded = json.dumps(complete)
    for private_text in (package.workbook.activities[0].worked_solution, package.workbook.activities[1].instructions,
                         "receipts - revenue", "practice.guided", "practice.transfer"):
        assert private_text not in encoded
    budget = audit.budget_aggregates([{"status": "finished", "usage_unknown": False, "charged_usd": 0.1},
        {"status": "finished", "usage_unknown": True, "charged_usd": 0.2}, {"status": "reserved", "reserved_usd": 0.3}])
    assert budget["known_reported_usd"] == 0.1 and budget["unknown_reserved_usd"] == 0.2 and budget["pending_reserved_usd"] == 0.3
    structured_tests(audit)
    choice_repair_tests(audit)
    component_shape_tests(audit)
    draft_component_tests(audit)
    diagnostic_phase_tests(audit)
    wrapper_mount_tests()
    evidence_shape_tests(audit)
    print("Offline in-memory audit tests passed: exact scope/hash attribution, interleaved completions, negative retention, correction merging, strict seeds, unchanged captures, ledger boundary, cost separation, and output privacy.")


def boundary_tests(audit, current):
    baseline, reports = [], {}
    for domain, (count, cost) in audit.BASELINE_COSTS.items():
        for index in range(count):
            baseline.append({"id": "prior_" + domain + "_" + str(index), "status": "finished",
                "scenario_id": domain + "_novice_missing", "tier": "balanced",
                "usage_unknown": False, "charged_usd": float(cost) / count})
        reports[domain] = {"scenario_id": domain + "_novice_missing", "tier": "balanced",
            "full_pipeline": True, "accepted": False, "estimated_cost_usd": float(cost)}
    auth = {"max_tests": 6, "tests_reserved": 6, "owner_approved": True, "shared_cap_usd": 1.97,
        "scope": "synthetic accounting, geometry, writing across v21 and follow-up fixes",
        "ledger": "/opt/cmpys/releases/" + audit.BASELINE_RELEASE + "/live-batch/usage.jsonl", "batches": [
            {"label": "", "tests_reserved": 3, "release": audit.BASELINE_RELEASE,
             "image_digest": audit.BASELINE_DIGEST, "prior_request_ids": [],
             "container": "cmpys-staged-v21-batch-20261017", "domains": ["accounting", "geometry", "writing"]},
            {"label": "corrected", "tests_reserved": 3, "release": "test", "image_digest": "sha256:test",
             "manifest_sha256": "manifest", "prior_request_ids": [row["id"] for row in baseline],
             "prior_accounted_usd": 0.2193908, "remaining_usd": 1.7506092,
             "container": "cmpys-staged-v22-batch-20261017", "domains": ["accounting", "geometry", "writing"]}]}
    rows = baseline + copy.deepcopy(current)
    before = copy.deepcopy((rows, auth, reports))
    def check(candidate_rows=rows, authorization=auth, baseline_reports=reports):
        return audit.boundary_rows(candidate_rows, authorization, "test", "sha256:test",
            baseline_reports=baseline_reports, manifest_sha256="manifest")
    ordered, selected, shared, excluded = check()
    assert excluded == 10 and len(shared) == len(selected) + 10
    assert ordered == selected == current
    assert audit.budget_aggregates(shared)["known_reported_usd"] == round(
        audit.budget_aggregates(selected)["known_reported_usd"] + 0.2193908, 10)
    for mutation in ("reserved_count", "cap", "approval", "duplicate_id", "unknown_id", "prior_cost",
                     "prior_release", "label", "container", "manifest", "prior_pending", "prior_unknown",
                     "cost_changed", "report_cost", "report_accepted", "report_missing"):
        changed_rows, changed_auth, changed_reports = copy.deepcopy(before)
        batch = changed_auth["batches"][1]
        if mutation == "reserved_count": changed_auth["tests_reserved"] = 3
        elif mutation == "cap": changed_auth["shared_cap_usd"] = 3
        elif mutation == "approval": changed_auth["owner_approved"] = False
        elif mutation == "duplicate_id": batch["prior_request_ids"][-1] = batch["prior_request_ids"][0]
        elif mutation == "unknown_id": batch["prior_request_ids"][-1] = "unseen"
        elif mutation == "prior_cost": batch["prior_accounted_usd"] = 0.2
        elif mutation == "prior_release": changed_auth["batches"][0]["release"] = "different"
        elif mutation == "label": batch["label"] = "v22"
        elif mutation == "container": batch["container"] = "unreviewed-container"
        elif mutation == "manifest": batch["manifest_sha256"] = "different"
        elif mutation == "prior_pending": changed_rows[0]["status"] = "reserved"
        elif mutation == "prior_unknown": changed_rows[0]["usage_unknown"] = True
        elif mutation == "cost_changed": changed_rows[0]["charged_usd"] += 0.01
        elif mutation == "report_cost": changed_reports["writing"]["estimated_cost_usd"] += 0.01
        elif mutation == "report_accepted": changed_reports["writing"]["accepted"] = True
        elif mutation == "report_missing": changed_reports.pop("writing")
        try: check(changed_rows, changed_auth, changed_reports)
        except AssertionError: pass
        else: raise AssertionError("Unreviewed second-batch boundary accepted: " + mutation)
    pending = {"id": "pending", "status": "reserved", "reserved_usd": 0.04}
    _, selected_pending, all_pending, _ = check(rows + [pending])
    assert audit.budget_aggregates(selected_pending)["pending_reserved_usd"] == 0.04
    assert audit.budget_aggregates(all_pending)["known_reported_usd"] == audit.budget_aggregates(shared)["known_reported_usd"]
    assert (rows, auth, reports) == before
    return ordered


def component_shape_tests(audit):
    secret = "Private synthetic hint and criterion must never appear"
    arbitrary_key = "private_unrecognized_metadata_name"
    activity = {
        "id": "private_activity_identifier", "hint": secret,
        "worked_solution": {"version": 1, "steps": [], "hint": secret,
                            "minutes_min": 13, "minutes_max": 17, arbitrary_key: secret},
        "fields": [{"id": "private_field_identifier", "kind": "text", "criteria": [secret]},
                   {"kind": "text"}, {"kind": "text", "criteria": secret},
                   {"kind": "text", "criteria": {arbitrary_key: secret}},
                   {"kind": "text", "criteria": []}, {"kind": "number", "expression": "private_formula"}],
    }
    original = copy.deepcopy(activity)
    shape = audit.component_shape_diagnostics(activity)
    assert shape["hint_shape"]["strings_comparable"] and shape["hint_shape"]["root_nested_equal"]
    assert shape["nested_minutes"]["minimum_valid"] and shape["nested_minutes"]["maximum_valid"]
    assert shape["nested_minutes"]["interval_valid"]
    assert shape["solution_extra_keys"] == {
        "count": 4, "recognized_names": ["hint", "minutes_max", "minutes_min"],
        "recognized_names_omitted": 0, "unrecognized_count": 1,
    }
    assert shape["text_field_count"] == 5
    assert [row["criteria_type"] for row in shape["text_fields"]] == ["list", "NoneType", "str", "dict", "list"]
    assert [row["criteria_count"] for row in shape["text_fields"]] == [1, None, None, None, 0]
    assert not shape["text_fields"][1]["criteria_present"]
    assert activity == original
    output = json.dumps(shape)
    for private in (secret, arbitrary_key, activity["id"], activity["fields"][0]["id"], "private_formula", "13", "17"):
        assert private not in output

    for lower, upper, expected in ((1, 60, True), (45.0, 60.0, True), (18, 17, False),
                                   (0, 1, False), (46, 60, False), (1, 61, False),
                                   (True, 2, False), (1, False, False), ("1", 2, False),
                                   (1.5, 2, False), (float("nan"), 2, False),
                                   (1, float("inf"), False), (10 ** 400, 2, False)):
        candidate = {"worked_solution": {"minutes_min": lower, "minutes_max": upper}}
        assert audit.component_shape_diagnostics(candidate)["nested_minutes"]["interval_valid"] is expected
    for root, nested in ((None, None), ([], []), ({}, {}), (secret, "different private hint")):
        candidate = {"hint": root, "worked_solution": {"hint": nested}}
        assert not audit.component_shape_diagnostics(candidate)["hint_shape"]["root_nested_equal"]
    assert audit.component_shape_diagnostics([]) == {"root_type": "list"}
    assert "hint_shape" not in audit.component_shape_diagnostics({"worked_solution": secret})

    oversized = {"worked_solution": {key: secret for key in audit.FIELDS},
                 "fields": [{"kind": "text", "criteria": [secret]} for _ in range(1000)]}
    bounded = audit.component_shape_diagnostics(oversized)
    assert len(bounded["text_fields"]) == 10 and bounded["text_fields_omitted"] == 990
    assert len(bounded["solution_extra_keys"]["recognized_names"]) <= 16
    assert bounded["solution_extra_keys"]["recognized_names_omitted"] > 0
    assert len(bounded["field_explanations"]) == 10
    assert bounded["field_explanations_omitted"] == 990
    assert len(json.dumps(bounded)) < 5000 and secret not in json.dumps(bounded)



def structured_tests(audit):
    import asyncio
    from types import SimpleNamespace
    from app.services.planning.package_preflight import review_package
    from app.services.planning.lesson_review import review_lesson
    from app.services.planning.lesson_package import LessonPackage
    from app.services.llm.client import LLMResponse
    from scripts.pilot_generation import _request_diagnostics
    from tests.test_preflight_checkpoint_task_wiring import quantitative_package
    from tests.test_plan_detail_output_schema import _lesson_sections_payload

    raw = quantitative_package().model_dump(mode="json")
    for activity in raw["workbook"]["activities"]:
        activity["fields"] = [{"id": "argument", "label": "Difference", "kind": "number", "expression": "receipts - revenue"}]
        activity["worked_solution"] = {"version": 1, "steps": [{"field_id": field["id"],
            "explanation": "Private authored rationale stays inside the offline process and explains the period comparison."}
            for field in activity["fields"]]}
    raw["workbook"]["activities"][0]["worked_solution"]["steps"][0]["explanation"] += " Receipts are 120."
    package = LessonPackage.model_validate(raw)
    case = {"id": "accounting_novice_missing", "goal": "Synthetic exact arithmetic review",
            "learner_level": "novice", "locale": "hy", "untrusted_note": "Synthetic untrusted reference"}
    captures = []
    evidence_count = 0
    async def generate(**request):
        nonlocal evidence_count
        name = request["output_model"].__name__
        body = json.loads(request["user_prompt"])
        if name == "PackageSemanticReview":
            data = {"acceptable": True, "issues": []}
        else:
            evidence_count += 1
            data = {} if evidence_count == 1 else {"literal_facts": [{"claim_id": key,
                "case_id": body["numeric_span_owners"][key], "datum_ids": ["receipts"]} for key in body["numeric_spans"]]}
        capture = {"schema": name, "data": copy.deepcopy(data), "finish_reason": "stop",
            **_request_diagnostics(request["user_prompt"], name)}
        captures.append(capture)
        return LLMResponse(data=data, finish_reason="stop")
    async def execute():
        return await review_package(package, audit.outline_for(case), audit.context_for(case),
            client_factory=lambda **_: SimpleNamespace(generate_json=generate))
    errors, response, _ = asyncio.run(execute())
    assert not errors and len(captures) == 3
    original = copy.deepcopy(captures)
    phase = audit.PreflightAudit(package, case)
    phase.semantic_capture(captures[0])
    phase.proof_capture(captures[1])
    phase.proof_capture(captures[2])
    report = phase.report()
    assert report["compiled_claim_count"] == 2 and report["residual_claim_count"] == 1
    assert report["verified_owner_scope_count"] == 2 and report["union_schema_valid"]
    assert not report["union_error_categories"]
    assert all(row["exact_request_reconstructed"] for row in report["proof_attempts"])
    assert captures == original
    assert report["proof_attempts"][0]["proof_error_count"] > 0
    # Compiled IDs are not valid substitutes for a captured residual scope.
    changed = copy.deepcopy(captures[1]); changed["request_claim_ids"] = sorted(phase.compiled_ids)
    wrong = audit.PreflightAudit(package, case); wrong.proof_capture(changed)
    assert not wrong.proofs[0].get("numeric_validation_performed")
    altered = copy.deepcopy(captures[0]); altered["request_sha256"] = "0" * 64
    mismatch = audit.PreflightAudit(package, case); mismatch.semantic_capture(altered)
    assert not mismatch.report()["semantic_positive_verified"]
    negative = copy.deepcopy(captures[0]); negative["data"] = {"acceptable": False, "issues": [{
        "target": "practice.guided", "description": "Private diagnostic says the scenario needs a substantive task revision."}]}
    rejected = audit.PreflightAudit(package, case); rejected.semantic_capture(negative); rejected.semantic_capture(captures[0])
    assert rejected.validated_targets == {"practice.guided"}
    assert rejected.report()["known_negative_preserved"] and not rejected.report()["semantic_positive_verified"]

    # Exercise real final request construction and correction. Only fixture
    # responses are supplied; no provider, database or application is used.
    sections = _lesson_sections_payload()
    sections["guided_practice"] = " ".join("[[practice:" + activity.id + "." + field.id + "]]"
        for activity in package.workbook.activities for field in activity.fields) + " substance" * 500
    final = audit.FinalReviewAudit(package, case, sections)
    assembled = LLMResponse(data=audit.render_package_results(copy.deepcopy(sections), package))
    audit._assemble_parallel_lesson_response(assembled, step=audit.outline_for(case),
        material_titles={"Optional background reference"}, target_minutes=60)
    assert not assembled.error
    finals = []
    async def final_generate(**request):
        name = request["output_model"].__name__
        body = json.loads(request["user_prompt"])
        data = {"calculations": [], "literal_facts": []}
        if name == "PackagedLessonReview":
            data.update(acceptable=True, issues=[], practice_minutes=40, contains_calculations=False)
        else:
            data["literal_facts"] = [{"claim_id": key, "case_id": "practice.guided", "datum_ids": ["receipts"]}
                for key in body["numeric_spans"]]
        finals.append({"schema": name, "data": copy.deepcopy(data), "finish_reason": "stop",
            **_request_diagnostics(request["user_prompt"], name)})
        return LLMResponse(data=data, finish_reason="stop")
    async def execute_final():
        return await review_lesson(copy.deepcopy(assembled.data),
            client_factory=lambda **_: SimpleNamespace(generate_json=final_generate),
            context={"goal": case["goal"], "mentor_evidence": {}, "lesson_package": package.review_context(),
                     "activity_timing_changes": []})
    failures, response, _ = asyncio.run(execute_final())
    assert not failures and len(finals) == 2
    original_finals = copy.deepcopy(finals)
    final.append(finals[0]); first = final.report()
    assert first["replay_requires_more_captures"] and not first["validation_performed"]
    final.append(finals[1]); complete = final.report()
    assert complete["validation_performed"] and complete["replay_finished"]
    assert complete["compiled_claim_count"] == 2 and complete["acceptable"]
    assert not complete["error_categories"]
    assert all(row["exact_request_reconstructed"] for row in complete["request_attempts"])
    assert complete["final_entry_counts"]["calculations"] == 2
    bad_final = audit.FinalReviewAudit(package, case, sections)
    changed = copy.deepcopy(finals[0]); changed["request_sha256"] = "0" * 64
    bad_final.append(changed)
    assert bad_final.report()["request_mismatch"] and not bad_final.report()["validation_performed"]
    rejected_final = audit.FinalReviewAudit(package, case, sections)
    negative = copy.deepcopy(finals[0]); negative["data"]["acceptable"] = False
    negative["data"]["issues"] = ["Private negative content remains blocking and stays inside the audit process."]
    rejected_final.append(negative)
    assert rejected_final.report()["known_negative_preserved"]
    assert not rejected_final.report()["acceptable"]
    assert finals == original_finals
    all_reports = json.dumps([report, complete, rejected_final.report(), rejected.report()])
    for secret in ("Private authored rationale", "Private diagnostic", "Private negative content",
                   "receipts - revenue", "practice.guided", "Receipts are 120"):
        assert secret not in all_reports


def choice_repair_tests(audit):
    from tests.test_choice_definition_repair import original_package, corrected_activity, deletion
    from scripts.pilot_generation import _request_diagnostics
    from tests.section_client_fixture import activity_draft_fixture
    package = original_package()
    case = {"id": "writing_novice_missing", "goal": "Synthetic choice correction review",
            "learner_level": "novice", "locale": "hy", "untrusted_note": "Synthetic untrusted reference"}
    phase = audit.PreflightAudit(package, case)
    body = {key: value for key, value in phase.payload.items() if key in {
        "outline", "context", "capabilities", "package", "numerical_evidence", "workload_contract"}}
    semantic = {"schema": "PackageSemanticReview", "data": {"acceptable": False, "issues": [{
        "target": "practice.transfer.audience", "description": "Freely chosen audience cannot have a fixed correct answer."}]},
        "finish_reason": "stop", **_request_diagnostics(json.dumps(body, ensure_ascii=False, separators=(",", ":")), "PackageSemanticReview")}
    seed = {"workbook_title": package.workbook.title, "teaching_cases": [], "activity_briefs": [
        {"id": item.id, "kind": item.kind, "scope": item.instructions} for item in package.workbook.activities]}

    class MemoryFile:
        def __init__(self, files, name): self.files, self.name = files, name
        def exists(self): return self.name in self.files
        def read_text(self): return json.dumps(self.files[self.name])
    class MemoryCaptures:
        def __init__(self, files): self.files = files
        def __truediv__(self, name): return MemoryFile(self.files, name)

    for invalid in (False, True):
        revised = corrected_activity()
        if invalid: revised["fields"][1]["label"] = "A changed target label that runtime must reject"
        sequence = [("LessonPackageSeed", seed), *[("LessonActivityDraft", activity_draft_fixture(item.model_dump(mode="json")))
            for item in package.workbook.activities], ("PackageSemanticReview", semantic["data"]),
            ("PrivatePackageRepair", deletion()), ("LessonActivityDraft", activity_draft_fixture(revised))]
        files = {str(index) + "-response.json": {"schema": name, "data": data,
            "visible_response": json.dumps(data), "finish_reason": "stop"} for index, (name, data) in enumerate(sequence)}
        files["3-response.json"] = semantic
        rows = [{"id": str(index), "scenario_id": case["id"], "tier": "balanced", "status": "finished",
                 "usage_unknown": False, "charged_usd": 0.01} for index in range(len(sequence))]
        original = copy.deepcopy(files)
        report = audit.audit_case(case, {"scenario_id": case["id"], "tier": "balanced", "full_pipeline": True,
            "validation_identity": audit.validation_identity(), "accepted": False, "failures": []}, rows, MemoryCaptures(files))
        assert report["package_available"]
        assert bool(report["component_failures"]) is invalid
        assert bool(report["repairs"]) is not invalid
        assert report["package_metrics"]["field_kind_counts"].get("choice", 0) == int(invalid)
        assert files == original


def evidence_shape_tests(audit):
    from tests.test_math_role_evidence import package_for, role

    def inspect(package, data, *, quote_candidates=None):
        records = audit.numeric_span_occurrences({}, package.review_context())
        patch = audit.ReviewEvidencePatch.model_validate(data)
        before_package, before_patch = package.model_dump(mode="json"), patch.model_dump(mode="json")
        result = audit.evidence_shape_diagnostics(package, patch, {record.claim_id for record in records},
            quote_candidates=quote_candidates)
        assert package.model_dump(mode="json") == before_package and patch.model_dump(mode="json") == before_patch
        return result, records

    package = package_for("Օգտագործիր (b × h) / 2 սմ։")
    value = package.model_dump(mode="json"); value["workbook"]["activities"][0]["fields"][0]["unit"] = "սմ"
    package = audit.LessonPackage.model_validate(value)
    result, records = inspect(package, {"math_roles": [role()]})
    diagnostic = result["role_diagnostics"][0]
    assert diagnostic["quote_unique"] and not diagnostic["quote_is_full_span"]
    assert diagnostic["quote_numeric_occurrence_count"] == 1 and diagnostic["coefficient_match"]
    assert diagnostic["following_category"] == "declared_unit"
    assert not diagnostic["quote_contains_following_token"] and not diagnostic["current_validator_accepts"]
    assert diagnostic["selected_role_canonical_operator_licensed"] and diagnostic["owner_valid"] and diagnostic["field_valid"]
    assert diagnostic["source_slice_exact"] and diagnostic["source_path"][-1] == "worked_solution"
    for private in ("Օգտագործիր", "(b × h) / 2", "practice.guided", "area", "սմ"):
        assert private not in json.dumps(result, ensure_ascii=False)
    repeated, _ = inspect(package, {"math_roles": [role(), role()]})
    assert repeated["duplicate_quoted_coefficient_occurrence_count"] == 1
    assert repeated["duplicate_valid_role_occurrence_count"] == 0

    source = "Արտադրյալը բաժանած 2-ի ստանում ենք մակերեսը։"
    package = package_for(source)
    result, records = inspect(package, {"math_roles": [role(kind="divisor", quote=source)]})
    diagnostic = result["role_diagnostics"][0]
    assert diagnostic["quote_has_known_Armenian_participle"]
    assert not diagnostic["quote_has_existing_Armenian_division_form"]
    assert diagnostic["following_category"] == "unclassified_word" and diagnostic["quote_contains_following_token"]
    assert not diagnostic["current_validator_accepts"]
    assert diagnostic["grammar_shape"]["following_word_classes"][:2] == ["Armenian_result_verb", "Armenian_copula"]
    assert diagnostic["grammar_shape"]["following_prefix_has_result_verb"]
    assert diagnostic["grammar_shape"]["operation_shapes"][0]["known_Armenian_participle"]
    assert source not in json.dumps(result, ensure_ascii=False)

    for source, expected in (
        ("Արտադրյալը բաժանե՛լով 2-ի ստանում ենք մակերեսը։", {"Armenian_stress_or_question_mark": True,
            "supported_after_removing_only_stress_or_question_marks": True, "current_supported_Armenian_form": False}),
        ("Արտադրյալը բաժանելով՝ 2-ի ստանում ենք մակերեսը։", {"gap_contains_Armenian_punctuation": True}),
        ("Արտադրյալը բաժանելով սկզբնարժեքը և հիմքը 2-ի ստանում ենք մակերեսը։",
            {"gap_contains_Armenian_ligature": True, "gap_contains_connective": True,
             "gap_current_Armenian_word_grammar": False}),
        ("Արտադրյալը 2-ի բաժանելով ստանում ենք մակերեսը։", {"relative_position": "after_coefficient"}),
        ("Արտադրյալը բաժանելով ոչ արժեքը 2-ի ստանում ենք մակերեսը։", {"gap_contains_known_negation": True}),
    ):
        result, _ = inspect(package_for(source), {"math_roles": [role(kind="divisor", quote=source)]})
        grammar = result["role_diagnostics"][0]["grammar_shape"]
        assert grammar["coefficient_Armenian_inflection"] == "genitive"
        operation = grammar["operation_shapes"][0]
        assert all(operation[key] == value for key, value in expected.items())
        assert source not in json.dumps(result, ensure_ascii=False)

    for suffix, word_class in (("we get the result", "English_subject_pronoun"),
            ("ապա ստանում ենք", "Armenian_connective"), ("never proceed", "negation"),
            ("հարկավոր է ստանալ", "Armenian_modal_or_evaluative"),
            ("օգնում է հասկանալ", "Armenian_known_predicate"),
            ("million units", "scale"), ("unrecognized_private_word remains", "unclassified_word")):
        source = "Divide the product by 2 " + suffix + "."
        result, _ = inspect(package_for(source), {"math_roles": [role(kind="divisor", quote=source)]})
        assert result["role_diagnostics"][0]["grammar_shape"]["following_word_classes"][0] == word_class
        assert suffix not in json.dumps(result, ensure_ascii=False)

    for token, kind in (("բաժանելն", "definite_infinitive_n"), ("բաժանելը", "definite_infinitive_y"),
            ("բաժանելիս", "while_participle"), ("բաժանելուց", "after_participle"), ("բաժանումն", "definite_nominal_n")):
        source = "Արտադրյալը 2-ի " + token + " ավարտում է քայլը։"
        result, _ = inspect(package_for(source), {"math_roles": [role(kind="divisor", quote=source)]})
        shape = result["role_diagnostics"][0]["grammar_shape"]["operation_shapes"][0]
        assert shape["operation_family"] == "division" and shape["Armenian_form"] == kind
        assert token not in json.dumps(result, ensure_ascii=False)
    source = "Արտադրյալը բաժանելով արժեքը 2-ի։"
    result, _ = inspect(package_for(source), {"math_roles": [role(kind="inverse_multiplier", quote=source)]})
    shape = result["role_diagnostics"][0]
    assert shape["selected_role"] == "inverse_multiplier" and shape["expected_operation_family"] == "multiplication"
    assert not shape["selected_operation_family_matches_observed"]
    assert shape["alternative_licensed_role_acceptance"]["divisor"]
    assert not shape["alternative_licensed_role_acceptance"]["inverse_multiplier"]
    assert not shape["current_validator_accepts"]  # Counterfactual probes never replace the captured evidence.

    for source, key, count in (("Write 20–30 words.", "word_quota", 2),
            ("Գրիր 2–3 նախադասություն։", "sentence_quota", 2),
            ("Allocate 10 minutes.", "duration", 1), ("A pump takes 10 minutes.", "duration", 0)):
        result, _ = inspect(package_for(source), {})
        shape = result["omitted_scope_positions"][0]["metadata_shape"]
        assert shape[key + "_recognized_numeral_count"] == count
        assert shape[key + "_numeral_count"] >= 1
        assert source not in json.dumps(result, ensure_ascii=False)
    result, _ = inspect(package_for("Write 20 words + 30 words = 50 words."), {})
    assert result["omitted_scope_positions"][0]["metadata_shape"]["workload_arithmetic_present"]

    source = "Do not divide the product by 2."
    result, _ = inspect(package_for(source), {"math_roles": [role(kind="divisor", quote=source)]})
    assert result["role_diagnostics"][0]["english_negation_present"]
    assert "not semantic proof" in result["basis"]  # No acceptance assertion from grammar alone.
    source = "Use (b × h) / 2 and (b × h) / 2 for comparison."
    result, _ = inspect(package_for(source), {"math_roles": [role()]})
    assert not result["role_diagnostics"][0]["quote_unique"]
    assert result["role_diagnostics"][0]["quote_occurrence_count"] == 2

    package = package_for("Area is 81.\nA separate displayed amount is 90.")
    calculations = [{"claim_ids": ["n1"], "case_id": "practice.guided", "expression": "base * height / 2",
                     "claimed_result": 90}]
    result, _ = inspect(package, {"calculations": calculations})
    calculation = result["unbound_calculations"][0]
    assert not calculation["result_present_original"] and not calculation["result_present_normalized"]
    assert calculation["result_present_other_span"] and calculation["result_present_other_same_owner_span"]
    assert calculation["named_inputs_bound"] and calculation["owner_valid"]
    assert result["omitted_scope_positions"][0]["source_position"] == 1
    assert "90" not in json.dumps(result) and "base * height" not in json.dumps(result)

    value = package_for("Area is 81սմ.").model_dump(mode="json")
    value["workbook"]["activities"][0]["fields"][0]["unit"] = "սմ"
    calculations[0]["claimed_result"] = 81
    result, _ = inspect(audit.LessonPackage.model_validate(value), {"calculations": calculations})
    assert not result["unbound_calculations"][0]["result_present_original"]
    assert result["unbound_calculations"][0]["result_present_normalized"]

    result, _ = inspect(package_for("Explain why we divide the product by 2."), {})
    omitted = result["omitted_scope_positions"][0]
    assert omitted["coefficient_candidate_count"] == 1 and omitted["canonical_role_candidate_count"] == 2
    assert omitted["exactly_one_full_span_licensed_field"]
    assert omitted["raw_value_coincidence_count"] == omitted["derived_value_coincidence_count"] == 0
    result, _ = inspect(package_for("2"), {})  # Too short for role schema; diagnostic must not crash.
    assert result["omitted_scope_positions"][0]["exact_full_span_licensed_field_count"] == 0
    result, _ = inspect(package_for("Use (b × h) / 2 for this shape."), {},
        quote_candidates={"n1": [{"source_quote": "(b × h) / 2"}]})
    assert result["omitted_scope_positions"][0]["existing_quote_candidate_count"] == 1
    assert result["omitted_scope_positions"][0]["existing_quote_candidate_exact_count"] == 1


def diagnostic_phase_tests(audit):
    import contextlib
    import io
    from unittest.mock import patch

    def output(config):
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            audit.run_audit(config)
        return [json.loads(line) for line in stream.getvalue().splitlines()]

    secret = "Private source, path, and exception text must stay hidden"
    missing = output({"manifest": {"/not-a-real-audit-path/private-capture": "private-hash"}})
    assert missing == [{"audit_error_phase": "manifest_verification", "audit_error_type": "FileNotFoundError",
                        "validation_performed": False, "publication": "none"}]
    class UntrustedPrivateException(Exception): pass
    with patch.object(audit, "load_runtime", side_effect=UntrustedPrivateException(secret)):
        failure = output({"manifest": {}})
    assert failure == [{"audit_error_phase": "runtime_import", "audit_error_type": "other_error",
                        "validation_performed": False, "publication": "none"}]
    assert secret not in json.dumps(failure) and "UntrustedPrivateException" not in json.dumps(failure)

    # Auditing one completed case must not depend on another current case
    # finishing. The boundary itself is exercised separately against real rows.
    selected = {"id": "current", "scenario_id": "accounting_novice_missing", "status": "finished",
                "charged_usd": 0.1, "usage_unknown": False}
    pending = {"id": "next", "scenario_id": "geometry_novice_missing", "status": "reserved", "reserved_usd": 0.2}
    files = {"/captures/authorization.json": {}, "/captures/usage.jsonl": "",
             "/scenarios.json": [{"id": "accounting_novice_missing"}],
             "/captures/accounting_novice_missing-corrected-balanced.json": {}}
    files.update({"/captures/" + domain + "_novice_missing-balanced.json": {} for domain in audit.BASELINE_COSTS})
    class MemoryPath:
        def __init__(self, value): self.value = str(value)
        def __truediv__(self, value): return MemoryPath(self.value + "/" + value)
        def exists(self): return self.value in files
        def read_text(self):
            value = files[self.value]
            return value if isinstance(value, str) else json.dumps(value)
        def read_bytes(self): return self.read_text().encode()
    report = {"scenario_id": "accounting_novice_missing", "components": [], "component_failures": [],
              "transport": [], "budget": audit.budget_aggregates([selected])}
    config = {"manifest": {}, "capture_release": audit.BASELINE_RELEASE, "release": "test", "digest": "test",
              "manifest_sha256": "test", "cases": ["accounting"], "mode": "components",
              "fixture_sha256": hashlib.sha256(json.dumps(files["/scenarios.json"]).encode()).hexdigest()}
    with patch.object(audit, "load_runtime"), patch.object(audit, "Path", MemoryPath), \
         patch.object(audit, "boundary_rows", return_value=([selected], [selected, pending], [selected, pending], 10)), \
         patch.object(audit, "audit_case", return_value=report) as replay:
        partial = output(config)
        mismatch = output({**config, "fixture_sha256": "0" * 64})
    assert replay.call_count == 1 and partial[0] == report
    assert partial[1]["completed_reports_audited"] == 1
    assert partial[1]["current_batch_budget"]["pending_count"] == 1
    assert not any("audit_error_phase" in item for item in partial)
    assert mismatch == [{"audit_error_phase": "scenario_fixture_hash", "audit_error_type": "AssertionError",
                         "validation_performed": False, "publication": "none"}]


def wrapper_mount_tests():
    import ast
    import contextlib
    import io
    from types import SimpleNamespace
    from unittest.mock import patch

    spec = importlib.util.spec_from_file_location("v22_wrapper_mount_test", Path(__file__).with_name("staged_v22_audit.py"))
    wrapper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(wrapper)
    with patch.object(wrapper.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout="{}", stderr="")) as runner, \
         patch("sys.argv", ["audit", "--run", "--components", "--case", "accounting"]), \
         contextlib.redirect_stdout(io.StringIO()):
        wrapper.main()
    assert runner.call_count == 1
    remote = runner.call_args.args[0][-1]
    expected = "/opt/cmpys/releases/" + wrapper.CAPTURE_RELEASE + "/generation_scenarios.json:/scenarios.json:ro"
    assert expected in remote
    assert "/opt/cmpys/releases/" + wrapper.RELEASE + "/generation_scenarios.json" not in remote
    assert "--network none" in remote and "--read-only" in remote and "--pull never" in remote
    assert "cmpys-backend@" + wrapper.DIGEST in remote
    generated = ast.parse(runner.call_args.kwargs["input"])
    config = ast.literal_eval(generated.body[-1].value.args[0])
    assert config["fixture_sha256"] == "5999f5942018c8cc817c3a7bfa85544c4d7cd1dccac4f46b275ccb24662342cc"
    assert config["capture_release"] == wrapper.CAPTURE_RELEASE and config["cases"] == ["accounting"]
    assert runner.call_args.kwargs["timeout"] == 60


def draft_component_tests(audit):
    from tests.test_preflight_checkpoint_task_wiring import quantitative_package
    from tests.section_client_fixture import activity_draft_fixture
    from scripts.pilot_generation import _request_diagnostics

    original_data = quantitative_package().model_dump(mode="json")
    for activity in original_data["workbook"]["activities"]:
        activity["fields"] = [{"id": "argument", "label": "Difference", "kind": "number",
                               "expression": "receipts - revenue"}]
        activity["worked_solution"] = {"version": 1, "steps": [{"field_id": "argument",
            "explanation": "Compare the supplied receipts with revenue and explain the period difference."}]}
    original = audit.LessonPackage.model_validate(original_data)
    drafts = [activity_draft_fixture(activity.model_dump(mode="json")) for activity in original.workbook.activities]
    canonical = [audit.parse_activity_draft(copy.deepcopy(draft)) for draft in drafts]
    package = audit.LessonPackage.model_validate({"teaching_cases": [], "workbook": {
        "title": original.workbook.title, "activities": [activity.model_dump(mode="json") for activity in canonical]}})
    case = {"id": "accounting_novice_missing", "goal": "Synthetic field-local reasoning review",
            "learner_level": "novice", "locale": "hy", "untrusted_note": "Synthetic untrusted reference"}
    seed = {"workbook_title": package.workbook.title, "teaching_cases": [], "activity_briefs": [
        {"id": activity.id, "kind": activity.kind, "scope": activity.instructions} for activity in package.workbook.activities]}
    phase = audit.PreflightAudit(package, case)
    body = {key: value for key, value in phase.payload.items() if key in {
        "outline", "context", "capabilities", "package", "numerical_evidence", "workload_contract"}}
    semantic = {"schema": "PackageSemanticReview", "data": {"acceptable": True, "issues": []},
        "finish_reason": "stop", **_request_diagnostics(json.dumps(body, ensure_ascii=False,
            separators=(",", ":")), "PackageSemanticReview")}
    class MemoryFile:
        def __init__(self, files, name): self.files, self.name = files, name
        def exists(self): return self.name in self.files
        def read_text(self): return json.dumps(self.files[self.name])
    class MemoryCaptures:
        def __init__(self, files): self.files = files
        def __truediv__(self, name): return MemoryFile(self.files, name)

    def replay(changed, *, schema="LessonActivityDraft", include_review=False):
        sequence = [("LessonPackageSeed", seed), (schema, changed[0]), (schema, changed[1])]
        files = {str(index) + "-response.json": {"schema": name, "data": data,
            "visible_response": json.dumps(data), "finish_reason": "stop"} for index, (name, data) in enumerate(sequence)}
        if include_review: files["3-response.json"] = semantic
        rows = [{"id": str(index), "scenario_id": case["id"], "tier": "balanced", "status": "finished",
            "usage_unknown": False, "charged_usd": 0.01} for index in range(len(files))]
        before = copy.deepcopy(files)
        report = audit.audit_case(case, {"scenario_id": case["id"], "tier": "balanced", "full_pipeline": True,
            "validation_identity": audit.validation_identity(), "accepted": False, "failures": []}, rows, MemoryCaptures(files))
        assert files == before
        return report

    result = replay(drafts, include_review=True)
    assert result["package_available"] and result["validated_activity_count"] == 2
    assert not result["component_failures"]
    assert result["preflights"][0]["semantic_positive_verified"]
    assert result["preflights"][0]["compiled_claim_count"] == 2
    assert not result["publication_approval_inferred"]
    assert all(component.get("contract_valid") for component in result["components"])
    assert all(component["wire"]["wire_matches_saved_data"] for component in result["components"])
    for mutation in ("missing_explanation", "misnested_document", "foreign_choice_key", "malformed_criteria", "wrong_identity"):
        changed = copy.deepcopy(drafts)
        field = changed[0]["fields"][0]
        if mutation == "missing_explanation": field.pop("explanation")
        elif mutation == "misnested_document":
            changed[0]["worked_solution"] = canonical[0].worked_solution.model_dump(mode="json")
        elif mutation == "foreign_choice_key": field["correct_choice"] = "private_answer"
        elif mutation == "malformed_criteria":
            field.update(kind="text", criteria=[{"private_key": "Private criterion"}]); field.pop("expression")
        elif mutation == "wrong_identity": changed[0]["id"] = "unknown_activity"
        failed = replay(changed)
        assert not failed["package_available"] and failed["component_failures"]
        assert not failed["preflights"]
        assert "private_key" not in json.dumps(failed) and "Private criterion" not in json.dumps(failed)
    obsolete = replay([activity.model_dump(mode="json") for activity in canonical], schema="LessonPackageActivity")
    assert not obsolete["package_available"]
    assert all(row["errors"] == [{"type": "obsolete_activity_wire_schema"}] for row in obsolete["component_failures"])
    encoded = json.dumps(result)
    for draft in drafts:
        for field in draft["fields"]:
            assert field["explanation"] not in encoded and field["expression"] not in encoded


if __name__ == "__main__":
    run_tests()
