"""In-memory replay boundaries; no SSH, model, server, or capture access."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import patch


def load_replay():
    here = Path(__file__).parent
    module = ModuleType("v23_replay_test_payload")
    exec(compile((here / "staged_v22_audit_payload.py").read_text(), "baseline_audit", "exec"), module.__dict__)
    exec(compile((here / "staged_v23_replay_payload.py").read_text(), "candidate_replay", "exec"), module.__dict__)
    module.load_runtime()
    return module


def run_tests():
    audit = load_replay()
    from tests.lesson_package_fixtures import package_payload
    from tests.section_client_fixture import activity_draft_fixture
    from tests.test_preflight_checkpoint_task_wiring import quantitative_package
    from scripts.pilot_generation import _request_diagnostics

    canonical = package_payload()
    seed = {"workbook_title": canonical["workbook"]["title"], "teaching_cases": [],
        "activity_briefs": [{"id": item["id"], "kind": item["kind"], "scope": item["instructions"]}
                            for item in canonical["workbook"]["activities"]]}
    drafts = [activity_draft_fixture(item) for item in canonical["workbook"]["activities"]]
    drafts[0]["fields"][0]["criteria"].insert(1, "")
    components = [{"position": 0, "schema": "LessonPackageSeed", "wire_verified": True, "data": seed}] + [
        {"position": index + 1, "schema": "LessonActivityDraft", "wire_verified": True, "data": value}
        for index, value in enumerate(drafts)]
    bundle = {"components": components, "baseline_package_available": False}
    before = copy.deepcopy(bundle)
    result = audit.candidate_component_replay(bundle)
    assert bundle == before and result["candidate_structural_package_valid"]
    assert result["component_attempts"][1]["exact_empty_criteria_removed_count"] == 1
    assert result["validated_activity_count"] == 2 and not result["publication_approval_inferred"]
    assert not any(row["accepted"] for row in result["component_attempts"])
    for invalid in ([""], [" ", ""], [" ", "Valid criterion"], [{"private": "value"}, ""]):
        changed = copy.deepcopy(bundle)
        changed["components"][1]["data"]["fields"][0]["criteria"] = invalid
        assert not audit.candidate_component_replay(changed)["candidate_structural_package_valid"]
    changed = copy.deepcopy(bundle)
    changed["components"][1]["wire_verified"] = False
    assert not audit.candidate_component_replay(changed)["candidate_structural_package_valid"]
    changed = copy.deepcopy(bundle)
    field = changed["components"][1]["data"]["fields"][0]
    field["criteria"] = [item for item in field["criteria"] if item]
    changed["components"][1]["data"]["explanation"] = field.pop("explanation")
    result = audit.candidate_component_replay(changed)
    event = result["component_attempts"][1]
    assert event["ownership_candidate_eligible"] and event["ownership_binding_requires_new_verdict"]
    assert not event["ownership_assigned"] and not result["candidate_structural_package_valid"]

    package = quantitative_package()
    case = {"id": "geometry_novice_missing", "goal": "Synthetic evidence replay", "learner_level": "novice",
            "locale": "hy", "untrusted_note": "Synthetic reference only"}
    phase = audit.PreflightAudit(package, case)
    source = audit.replay_inventory(package)
    snapshots = []
    for index, item in enumerate(package.workbook.activities):
        ids = phase.remaining_groups[item.id]
        snapshots.append({"owner_position": index, "expected_ids": sorted(ids), "requested_ids": sorted(ids),
            "schema_valid": True, "numeric_validation_performed": True, "known_negative": False,
            "fixed_evidence": {"calculations": [{"claim_ids": sorted(ids), "case_id": "practice." + item.id,
                "expression": "receipts - revenue", "claimed_result": 20 if index == 0 else 25}]}})
    exported = {"package": package.model_dump(mode="json"), "inventory": source, "snapshots": snapshots,
                "semantic_positive_verified": True, "known_negative": False, "exact_request_count": 3}
    before = copy.deepcopy(exported)
    result = audit.candidate_phase_replay({"case": case}, exported)
    assert exported == before and result["full_union_schema_valid"] and not result["full_union_error_categories"]
    assert not result["new_semantic_verdict"] and not result["publication_approval_inferred"]
    assert all(not row["candidate_request_reconstruction_claimed"] and not row["new_proofs_added"] for row in result["proof_attempts"])
    changed = copy.deepcopy(exported)
    changed["snapshots"][0]["fixed_evidence"]["calculations"][0]["expression"] = "receipts + revenue"
    assert audit.candidate_phase_replay({"case": case}, changed)["full_union_error_categories"]
    changed = copy.deepcopy(exported)
    changed["known_negative"] = True
    result = audit.candidate_phase_replay({"case": case}, changed)
    assert result["known_negative_preserved"] and all(row["known_negative_preserved"] for row in result["proof_attempts"])
    changed = copy.deepcopy(exported)
    changed["snapshots"][0]["fixed_evidence"] = {}
    result = audit.candidate_phase_replay({"case": case}, changed)
    assert result["proof_attempts"][0]["remaining_uncovered_source_positions"]
    for key, mutation in (("span", "Altered private text"), ("path", ["different"]), ("start", 999), ("source_hash", "0" * 64)):
        changed = copy.deepcopy(exported); changed["inventory"][0][key] = mutation
        try: audit.candidate_phase_replay({"case": case}, changed)
        except AssertionError: pass
        else: raise AssertionError("Candidate accepted a different source occurrence")
    encoded = json.dumps(result)
    for private in (case["goal"], "receipts - revenue", package.workbook.activities[0].worked_solution):
        assert private not in encoded

    from tests.test_compiled_solution_evidence import typed_package
    typed = typed_package(explanation="Write 2–3 sentences explaining why this comparison follows from the supplied inputs.")
    typed_phase = audit.PreflightAudit(typed, case)
    assert len(typed_phase.compiled_ids) == 2 and all(typed_phase.remaining_groups.values())
    typed_export = {"package": typed.model_dump(mode="json"), "inventory": audit.replay_inventory(typed),
        "semantic_positive_verified": True, "known_negative": False, "exact_request_count": 3,
        "snapshots": [{"owner_position": index, "expected_ids": sorted(typed_phase.remaining_groups[item.id]),
            "requested_ids": sorted(typed_phase.remaining_groups[item.id]), "schema_valid": True,
            "numeric_validation_performed": True, "known_negative": False, "fixed_evidence": {}}
            for index, item in enumerate(typed.workbook.activities)]}
    missing = audit.candidate_phase_replay({"case": case}, typed_export)
    assert missing["full_union_error_categories"]
    assert all(row["metadata_candidate_source_positions"] and row["remaining_uncovered_source_positions"]
               for row in missing["proof_attempts"])
    supplied = copy.deepcopy(typed_export)
    for snapshot in supplied["snapshots"]:
        snapshot["fixed_evidence"] = {"literal_fact_ids": snapshot["expected_ids"]}
    valid = audit.candidate_phase_replay({"case": case}, supplied)
    assert valid["full_union_schema_valid"] and not valid["full_union_error_categories"]
    assert all(not row["new_proofs_added"] for row in valid["proof_attempts"])

    # The baseline observer exports only exact request-owned merged evidence.
    class MemoryCaptures:
        def __init__(self, values, name=""): self.values, self.name = values, name
        def __truediv__(self, name): return MemoryCaptures(self.values, name)
        def exists(self): return self.name in self.values
        def read_text(self): return json.dumps(self.values[self.name])
    phase = audit.PreflightAudit(package, case)
    body = {key: value for key, value in phase.payload.items() if key in {
        "outline", "context", "capabilities", "package", "numerical_evidence", "workload_contract"}}
    semantic = {"schema": "PackageSemanticReview", "data": {"acceptable": True, "issues": []}, "finish_reason": "stop",
        **_request_diagnostics(json.dumps(body, ensure_ascii=False, separators=(",", ":")), "PackageSemanticReview")}
    # A tiny audited orchestration fixture avoids changing runtime seams.
    def fake_audit(scenario, report, rows, captures):
        observed = audit.PreflightAudit(package, scenario)
        observed.semantic_capture(semantic)
        owner = package.workbook.activities[0].id
        ids = observed.remaining_groups[owner]
        payload = {**observed.payload, "numeric_spans": {key: value for key, value in observed.spans.items() if key in ids},
                   "numeric_span_owners": {key: value for key, value in observed.owners.items() if key in ids}}
        request, scope = audit._evidence_patch_request(audit.PackageReview(acceptable=True, issues=[]), payload, [])
        capture = {"schema": "ReviewEvidencePatch", "data": snapshots[0]["fixed_evidence"], "finish_reason": "stop",
                   **_request_diagnostics(request["user_prompt"], "ReviewEvidencePatch")}
        if report.get("tampered"): capture["request_sha256"] = "0" * 64
        observed.proof_capture(capture)
        return {"final_reviews": [], "repairs": [], "package_available": True}
    with patch.object(audit, "audit_case", side_effect=fake_audit):
        verified = audit.baseline_case_bundle(case, {}, [], MemoryCaptures({}))
        assert verified["phases"][0]["exact_request_count"] == 2
        assert verified["phases"][0]["snapshots"][0]["fixed_evidence"]["calculations"]
        try: audit.baseline_case_bundle(case, {"tampered": True}, [], MemoryCaptures({}))
        except AssertionError: pass
        else: raise AssertionError("Unverified baseline request exported private evidence")

    wrapper_path = Path(__file__).with_name("staged_v23_replay.py")
    spec = importlib.util.spec_from_file_location("v23_replay_wrapper_test", wrapper_path)
    wrapper = importlib.util.module_from_spec(spec); spec.loader.exec_module(wrapper)
    with patch.object(wrapper, "CANDIDATE_DIGEST", None):
        try: wrapper.programs(["geometry"])
        except ValueError: pass
        else: raise AssertionError("Missing candidate pins allowed execution")
    source = wrapper_path.read_text()
    assert '"--network", "none"' in source and '"--read-only"' in source
    assert 'stdin=first.stdout' in source and 'stderr=subprocess.DEVNULL' in source
    assert 'second.stdout' in source and 'first.communicate' not in source
    assert 'capture_release + "/generation_scenarios.json:/scenarios.json:ro"' in source
    print("Two-phase replay tests passed: exact baseline binding, fixed proofs, strict source inventory, empty-only criteria, negative retention, no inferred ownership, no private output.")


if __name__ == "__main__":
    run_tests()
