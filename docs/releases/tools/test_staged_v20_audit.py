"""Synthetic in-memory regressions; no provider, SSH, database, or capture access."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path


def run_tests():
    path = Path(__file__).with_name("staged_v20_audit_payload.py")
    spec = importlib.util.spec_from_file_location("staged_v20_payload_tests", path)
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

    sequence = [("LessonPackageSeed", seed_data), *[("LessonPackageActivity", activity.model_dump(mode="json")) for activity in package.workbook.activities]]
    captures = {str(index) + "-response.json": {"schema": schema, "data": data, "visible_response": json.dumps(data), "finish_reason": "stop"}
                for index, (schema, data) in enumerate(sequence)}
    for index, capture in enumerate(originals, len(sequence)): captures[str(index) + "-response.json"] = capture
    captures["old-response.json"] = {"schema": "LessonPackageSeed", "data": {"invalid_old_seed": True}}
    rows = [{"id": key.removesuffix("-response.json"), "scenario_id": case["id"], "tier": "balanced",
             "status": "finished", "usage_unknown": False, "charged_usd": 0.01} for key in captures]
    auth = {"tests_reserved": 6, "batches": [{}, {"label": "corrected", "tests_reserved": 3, "release": "test",
            "image_digest": "sha256:test", "prior_request_ids": ["old"]}]}
    ordered, current, shared, excluded = audit.boundary_rows(rows, auth, "test", "sha256:test")
    assert excluded == 1 and len(current) == len(shared) - 1
    assert all(row["id"] != "old" for row in ordered)
    report = {"scenario_id": case["id"], "tier": "balanced", "full_pipeline": True,
              "validation_identity": audit.validation_identity(), "accepted": False, "failures": []}
    before = copy.deepcopy(captures)
    complete = audit.audit_case(case, report, ordered, MemoryCaptures(captures))
    assert complete["package_available"] and not complete["component_failures"]
    assert len(complete["preflights"]) == 1 and complete["preflights"][0]["verified_owner_scope_count"] == 2
    assert complete["output_limit_count"] == complete["transport_timeout_count"] == 0
    assert captures == before
    encoded = json.dumps(complete)
    for private_text in (package.workbook.activities[0].worked_solution, package.workbook.activities[1].instructions,
                         "receipts - revenue", "practice.guided", "practice.transfer"):
        assert private_text not in encoded
    budget = audit.budget_aggregates([{"status": "finished", "usage_unknown": False, "charged_usd": 0.1},
        {"status": "finished", "usage_unknown": True, "charged_usd": 0.2}, {"status": "reserved", "reserved_usd": 0.3}])
    assert budget["known_reported_usd"] == 0.1 and budget["unknown_reserved_usd"] == 0.2 and budget["pending_reserved_usd"] == 0.3
    print("Offline in-memory audit tests passed: exact scope/hash attribution, interleaved completions, negative retention, correction merging, strict seeds, unchanged captures, ledger boundary, cost separation, and output privacy.")


if __name__ == "__main__":
    run_tests()
