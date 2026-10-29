"""Two-phase private offline replay, appended to the frozen v22 audit helper.

The baseline phase's stdout is PRIVATE and must feed only the candidate's stdin
on the backend host. The candidate phase emits bounded aggregate metadata only.
Neither phase constructs a provider or invokes generation.
"""
import sys

REPLAY_FIELDS = ("calculations", "literal_facts", "literal_fact_ids", "math_roles")


def replay_inventory(package):
    return [{"claim_id": item.claim_id, "path": list(item.path), "start": item.start,
             "end": item.end, "span": item.span, "source_hash": hashlib.sha256(item.source.encode()).hexdigest()}
            for item in numeric_span_occurrences({}, package.review_context())]


def verify_replay_sources(config):
    assert config["manifest"] and config["release"] and re.fullmatch(r"sha256:[0-9a-f]{64}", config["digest"])
    for filename, expected in config["manifest"].items():
        assert re.fullmatch(r"[0-9a-f]{64}", expected)
        assert hashlib.sha256(Path(filename).read_bytes()).hexdigest() == expected


def baseline_case_bundle(case, report, rows, captures):
    """Export only after the old runtime has reconstructed every review request."""
    original = PreflightAudit
    phases = []

    class ObservedPreflight(original):
        def __init__(self, package, scenario, timing_changes=()):
            super().__init__(package, scenario, timing_changes)
            self.replay_snapshots = []
            phases.append(self)

        def proof_capture(self, capture):
            super().proof_capture(capture)
            result = self.proofs[-1]
            assert result.get("exact_request_reconstructed") is True
            owner_index = result["owner_activity_position"]
            owner = self.package.workbook.activities[owner_index].id
            prior = self.prior.get(owner)
            self.replay_snapshots.append({
                "owner_position": owner_index, "expected_ids": sorted(self.remaining_groups[owner]),
                "requested_ids": list(capture["request_claim_ids"]),
                "known_negative": self.negative,
                "schema_valid": result.get("schema_valid") is True,
                "numeric_validation_performed": result.get("numeric_validation_performed") is True,
                "fixed_evidence": prior.model_dump(mode="json", include=set(REPLAY_FIELDS)) if prior else None,
                "baseline_error_categories": result.get("proof_error_categories", {}),
            })

    globals()["PreflightAudit"] = ObservedPreflight
    try:
        result = audit_case(case, report, rows, captures)
    finally:
        globals()["PreflightAudit"] = original
    # These scenarios have no later prose/final-review calls. Refuse scope
    # expansion instead of treating an unverified new stage as baseline truth.
    assert not result["final_reviews"] and not result["repairs"]
    components = []
    for position, row in enumerate(row for row in rows if row.get("scenario_id") == case["id"]):
        ident = row["id"]
        assert re.fullmatch(r"[A-Za-z0-9_-]{1,100}", ident)
        capture = json.loads((captures / (ident + "-response.json")).read_text())
        schema = capture.get("schema")
        assert schema in {"LessonPackageSeed", "LessonActivityDraft", "PackageSemanticReview", "ReviewEvidencePatch"}
        if schema not in {"LessonPackageSeed", "LessonActivityDraft"}: continue
        complete = not capture.get("error") and capture.get("finish_reason") in (None, "stop")
        wire, _ = wire_diagnostic(capture, LessonPackageSeed if schema == "LessonPackageSeed" else LessonActivityDraft)
        verified = complete and wire.get("status") == "parsed" and wire.get("wire_matches_saved_data") is True
        components.append({"position": position, "schema": schema, "wire_verified": verified,
                           "data": copy.deepcopy(capture.get("data")) if verified else None})
    exported_phases = []
    for phase in phases:
        status = phase.report()
        assert phase.semantic and all(item["request_hash_matches"] for item in phase.semantic)
        assert all(item.get("exact_request_reconstructed") for item in phase.proofs)
        exported_phases.append({"package": phase.package.model_dump(mode="json"),
            "inventory": replay_inventory(phase.package), "snapshots": phase.replay_snapshots,
            "semantic_positive_verified": status["semantic_positive_verified"],
            "known_negative": status["known_negative_preserved"],
            "exact_request_count": len(phase.semantic) + len(phase.proofs)})
    assert len(exported_phases) <= 1 and len(components) <= 10
    return {"domain": case["id"].removesuffix("_novice_missing"), "case": copy.deepcopy(case),
            "components": components, "phases": exported_phases,
            "baseline_package_available": result["package_available"],
            "baseline_semantic_call_count": sum(len(phase.semantic) for phase in phases)}


def baseline_replay(config):
    """Private pipe producer. No private output may reach a user-facing sink."""
    verify_replay_sources(config)
    load_runtime()
    captures = Path("/captures")
    authorization = json.loads((captures / "authorization.json").read_text())
    rows = [json.loads(line) for line in (captures / "usage.jsonl").read_text().splitlines()]
    reports = {domain: json.loads((captures / (domain + "_novice_missing-balanced.json")).read_text())
               for domain in BASELINE_COSTS}
    ordered, current, shared, excluded = boundary_rows(rows, authorization, config["release"], config["digest"],
        baseline_reports=reports, manifest_sha256=config["manifest_sha256"])
    assert excluded == 10 and len(current) == 15 and len(shared) == 25
    assert all(row.get("status") == "finished" and row.get("usage_unknown") is False for row in shared)
    assert Decimal(str(budget_aggregates(shared)["known_reported_usd"])) == Decimal("0.565886")
    fixture = Path("/scenarios.json").read_bytes()
    assert hashlib.sha256(fixture).hexdigest() == config["fixture_sha256"]
    cases = json.loads(fixture)
    bundles = []
    for domain in config["cases"]:
        case = next(case for case in cases if case["id"] == domain + "_novice_missing")
        report = json.loads((captures / (case["id"] + "-corrected-balanced.json")).read_text())
        bundles.append(baseline_case_bundle(case, report, ordered, captures))
    envelope = {"version": 1, "baseline_digest": config["digest"], "baseline_manifest_sha256": config["manifest_sha256"],
                "fixture_sha256": config["fixture_sha256"], "bundles": bundles}
    serialized = json.dumps(envelope, ensure_ascii=False, separators=(",", ":"))
    assert len(serialized.encode()) <= 2_000_000
    print(serialized, flush=True)


def exact_empty_criteria_copy(data):
    """Independent expected delta; never trim whitespace or invent a rubric."""
    expected, removed = copy.deepcopy(data), 0
    if type(expected) is not dict or type(expected.get("fields")) is not list:
        return expected, removed
    for field in expected["fields"]:
        if type(field) is not dict or field.get("kind") != "text": continue
        criteria = field.get("criteria")
        if (type(criteria) is list and 1 <= len(criteria) <= 5
                and any(type(item) is str and item.strip() for item in criteria)):
            removed += sum(type(item) is str and item == "" for item in criteria)
            field["criteria"] = [item for item in criteria if not (type(item) is str and item == "")]
    return expected, removed


def candidate_component_replay(bundle):
    from app.services.planning.activity_draft import explanation_ownership_candidate
    seed = package = None
    activities, events = {}, []
    for component in bundle["components"]:
        event = {"position": component["position"], "schema": component["schema"],
                 "baseline_complete_wire_verified": component["wire_verified"], "accepted": False}
        events.append(event)
        if not component["wire_verified"]: continue
        data = copy.deepcopy(component["data"])
        before = copy.deepcopy(data)
        try:
            if component["schema"] == "LessonPackageSeed":
                seed, _ = parse_initial_seed_response(data)
                activities, package = {}, None
                event["structural_valid"] = True
            else:
                expected, removed = exact_empty_criteria_copy(data)
                event["exact_empty_criteria_removed_count"] = removed
                ownership = explanation_ownership_candidate(data)
                event.update(ownership_candidate_eligible=ownership is not None,
                             ownership_binding_requires_new_verdict=ownership is not None,
                             ownership_assigned=False)
                parsed = parse_activity_draft(data)
                expected_wire = LessonActivityDraft.model_validate(expected)
                assert parsed == parse_activity_draft(expected_wire)
                assert seed is not None
                brief = next(brief for brief in seed.activity_briefs if brief.id == parsed.id)
                activities[brief.id] = _validated_activity(parsed, seed, brief)
                event["structural_valid"] = True
                if all(brief.id in activities for brief in seed.activity_briefs):
                    package = LessonPackage.model_validate({"teaching_cases": [item.model_dump(mode="json") for item in seed.teaching_cases],
                        "workbook": {"title": seed.workbook_title,
                                     "activities": [activities[brief.id].model_dump(mode="json") for brief in seed.activity_briefs]}})
        except (ValidationError, ValueError, KeyError, StopIteration, TypeError):
            event["structural_valid"] = False
        assert data == before
    return {"component_attempts": events, "candidate_structural_package_valid": package is not None,
            "validated_activity_count": len(activities), "baseline_structural_package_valid": bundle["baseline_package_available"],
            "semantic_review_replayed": False, "publication_approval_inferred": False}


def candidate_phase_replay(bundle, phase):
    package = LessonPackage.model_validate(phase["package"])
    original = copy.deepcopy(phase)
    inventory = replay_inventory(package)
    assert inventory == phase["inventory"], "Candidate numeric inventory differs from verified source ownership"
    positions = {item["claim_id"]: index for index, item in enumerate(inventory)}
    payload = package_review_payload(package, outline_for(bundle["case"]), context_for(bundle["case"]))
    metadata_ids = set(payload.get("metadata_candidate_ids", []))
    assert metadata_ids <= positions.keys()
    compiled = compiled_solution_evidence({}, package.review_context())
    owners = payload["numeric_span_owners"]
    compiled_ids = {key for check in compiled.calculations for key in check.claim_ids}
    results, latest = [], {}
    for index, snapshot in enumerate(phase["snapshots"]):
        owner = package.workbook.activities[snapshot["owner_position"]].id
        all_ids = {key for key, value in owners.items() if value == "practice." + owner}
        expected = set(snapshot["expected_ids"])
        assert expected == all_ids - compiled_ids
        assert set(snapshot["requested_ids"]) <= expected
        row = {"attempt_position": index, "owner_activity_position": snapshot["owner_position"],
               "baseline_request_verified": True, "candidate_request_reconstruction_claimed": False,
               "known_negative_preserved": snapshot["known_negative"] or phase["known_negative"],
               "metadata_candidate_source_positions": sorted(positions[key] for key in metadata_ids & expected),
               "metadata_candidates_are_suggestions_only": True, "new_proofs_added": False}
        results.append(row)
        if not snapshot["numeric_validation_performed"] or not snapshot["schema_valid"] or snapshot["fixed_evidence"] is None:
            row["candidate_numeric_validation_performed"] = False
            continue
        patch = ReviewEvidencePatch.model_validate(snapshot["fixed_evidence"])
        residual_errors = _scope_failures(patch.model_copy(deep=True), expected, package)
        combined = ReviewEvidencePatch.model_validate({**patch.model_dump(mode="json"),
            "calculations": [check.model_dump(mode="json") for check in compiled.calculations if set(check.claim_ids) <= all_ids]
                          + [check.model_dump(mode="json") for check in patch.calculations]})
        errors = residual_errors + _scope_failures(combined.model_copy(deep=True), all_ids, package)
        errors = list(dict.fromkeys(errors))
        row.update(candidate_numeric_validation_performed=True, proof_error_count=len(errors),
                   proof_error_categories=categories(errors), proof_error_positions=error_positions(errors, package),
                   remaining_uncovered_source_positions=sorted(positions[key] for key in all_ids - _evidence_ids(_evidence_review(_patch_verdict(combined)))),
                   fixed_evidence_count=evidence_counts(patch.model_dump(mode="json")))
        latest[owner] = combined
    union_errors, union_valid = [], False
    if len(latest) == len(package.workbook.activities):
        try:
            combined = {key: [item for evidence in latest.values() for item in getattr(evidence, key)] for key in REPLAY_FIELDS}
            verdict = PackageReview(acceptable=True, issues=[], contains_calculations=bool(combined["calculations"]), **combined)
            source, proofs = _numeric_preflight_failures(verdict, package)
            union_errors, union_valid = source + proofs, True
        except ValidationError:
            union_errors = ["Numeric verification coverage is incomplete or contains fabricated span IDs"]
    assert phase == original
    return {"original_inventory_unchanged": True, "baseline_semantic_positive_verified": phase["semantic_positive_verified"],
            "known_negative_preserved": phase["known_negative"], "exact_baseline_request_count": phase["exact_request_count"],
            "proof_attempts": results, "full_union_schema_valid": union_valid,
            "full_union_error_categories": categories(union_errors), "full_union_error_positions": error_positions(union_errors, package),
            "new_semantic_verdict": False, "publication_approval_inferred": False}


def candidate_replay(envelope, config):
    verify_replay_sources(config)
    load_runtime()
    assert envelope["version"] == 1
    assert envelope["baseline_digest"] == config["baseline_digest"]
    assert envelope["baseline_manifest_sha256"] == config["baseline_manifest_sha256"]
    assert envelope["fixture_sha256"] == config["fixture_sha256"]
    assert [bundle["domain"] for bundle in envelope["bundles"]] == config["cases"]
    result = []
    for bundle in envelope["bundles"]:
        assert bundle["domain"] in {"accounting", "geometry", "writing"}
        result.append({"domain": bundle["domain"], "mode": "fixed_evidence_offline_candidate_replay",
            "components": candidate_component_replay(bundle),
            "preflights": [candidate_phase_replay(bundle, phase) for phase in bundle["phases"]],
            "provider_calls": 0, "publication_approval_inferred": False})
    return result


def run_candidate_replay(config):
    try:
        raw = sys.stdin.buffer.read(2_000_001)
        assert len(raw) <= 2_000_000
        envelope = json.loads(raw)
        rows = candidate_replay(envelope, config)
    except Exception:
        print(json.dumps({"replay_error": "candidate_validation_failed", "private_details": "suppressed"}), flush=True)
        raise SystemExit(1)
    for row in rows:
        print(json.dumps(row, ensure_ascii=False, sort_keys=True), flush=True)
