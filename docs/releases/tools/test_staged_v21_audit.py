"""Synthetic in-memory regressions; no provider, SSH, database, or capture access."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path


def run_tests():
    path = Path(__file__).with_name("staged_v21_audit_payload.py")
    spec = importlib.util.spec_from_file_location("staged_v21_payload_tests", path)
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
    rows = [{"id": key.removesuffix("-response.json"), "scenario_id": case["id"], "tier": "balanced",
             "status": "finished", "usage_unknown": False, "charged_usd": 0.01} for key in captures]
    auth = {"max_tests": 6, "tests_reserved": 3, "owner_approved": True, "shared_cap_usd": 1.97,
        "scope": "synthetic accounting, geometry, writing across v21 and follow-up fixes",
        "ledger": "/opt/cmpys/releases/test/live-batch/usage.jsonl", "batches": [{"label": "", "tests_reserved": 3,
            "release": "test", "image_digest": "sha256:test", "prior_request_ids": [],
            "container": "cmpys-staged-v21-batch-20261017", "domains": ["accounting", "geometry", "writing"]}]}
    ordered, current, shared, excluded = audit.boundary_rows(rows, auth, "test", "sha256:test")
    assert excluded == 0 and len(current) == len(shared)
    for change in [{"tests_reserved": 6}, {"shared_cap_usd": 3}, {"owner_approved": False}]:
        try: audit.boundary_rows(rows, {**auth, **change}, "test", "sha256:test")
        except AssertionError: pass
        else: raise AssertionError("Unreviewed authorization boundary accepted")
    altered = copy.deepcopy(auth); altered["batches"][0]["prior_request_ids"] = ["old"]
    try: audit.boundary_rows(rows, altered, "test", "sha256:test")
    except AssertionError: pass
    else: raise AssertionError("First batch must not borrow earlier request IDs")
    report = {"scenario_id": case["id"], "tier": "balanced", "full_pipeline": True,
              "validation_identity": audit.validation_identity(), "accepted": False, "failures": []}
    before = copy.deepcopy(captures)
    complete = audit.audit_case(case, report, ordered, MemoryCaptures(captures))
    # New activity generation is strictly structured in v21. Saved legacy
    # packages still use the normal proof path tested above, but new legacy
    # string captures must fail rather than be silently normalized.
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
    print("Offline in-memory audit tests passed: exact scope/hash attribution, interleaved completions, negative retention, correction merging, strict seeds, unchanged captures, ledger boundary, cost separation, and output privacy.")


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
    assert len(json.dumps(bounded)) < 3000 and secret not in json.dumps(bounded)



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
        sequence = [("LessonPackageSeed", seed), *[("LessonPackageActivity", item.model_dump(mode="json"))
            for item in package.workbook.activities], ("PackageSemanticReview", semantic["data"]),
            ("PrivatePackageRepair", deletion()), ("LessonPackageActivity", revised)]
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


if __name__ == "__main__":
    run_tests()
