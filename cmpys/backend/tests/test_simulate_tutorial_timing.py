"""The offline timing harness drives the real tutorial pipeline end to end."""
import json

from scripts import simulate_tutorial_timing as harness


def test_harness_publishes_both_scenarios_with_the_overlapped_critical_path(tmp_path):
    from app.services.llm import client, telemetry
    originals = (client.get_llm_client, telemetry.record_llm_response)
    out = tmp_path / "timing.json"
    assert harness.main(["--scenario", "all", "--runs", "1", "--time-scale", "0.01", "--out", str(out)]) == 0
    assert (client.get_llm_client, telemetry.record_llm_response) == originals  # Isolation is undone.
    result = json.loads(out.read_text())
    clean, rejected = result["runs"]
    for run in (clean, rejected):
        assert run["published"] and run["error"] is None
        assert not run["unclassified"] and not run["rejected_canned_responses"]
    # The writer overlaps the preflight and evidence overlaps the semantic call,
    # so a clean pass waits on seed, the slower activity, evidence and review.
    assert clean["critical_path"] == ["package_seed", "activity_transfer", "preflight_evidence", "final_review"]
    stages = [c["stage"] for c in clean["timeline"]]
    assert stages.count("preflight_evidence") == 2 and stages.count("lesson_writer") == 1
    assert rejected["critical_path"][2:5] == ["preflight_semantic", "package_repair", "preflight_evidence"]
    # The discarded speculative draft is rewritten after the repair.
    assert [c["stage"] for c in rejected["timeline"]].count("lesson_writer") == 2
    assert result["expected_clean_critical_path_s"] == 79.0  # The sequential baseline.
    assert 56 <= clean["total_real_s"] <= 60
    assert 26 <= rejected["total_real_s"] - clean["total_real_s"] <= 31


def test_stage_detection_uses_output_model_and_calling_module():
    class Named:
        def __init__(self, name):
            self.__name__ = name
    def stage(model, modules, prompt="{}"):
        return harness.classify({"output_model": Named(model), "user_prompt": prompt}, modules)
    builder = ["app.services.planning.package_builder", "app.tasks.plans"]
    assert stage("TutorialActivityDraft", builder, json.dumps({"activity_brief": {"kind": "transfer"}})) == "activity_transfer"
    assert stage("TutorialActivityDraft", builder, json.dumps({"activity_brief": {"kind": "practice"}})) == "activity_guided"
    assert stage("TutorialActivityDraft", ["app.services.planning.lesson_package"]) == "activity_repair"
    assert stage("ReviewEvidencePatch", ["app.services.planning.package_preflight"]) == "preflight_evidence"
    assert stage("ReviewEvidencePatch", ["app.services.planning.lesson_review"]) == "review_evidence_repair"
    assert stage("SomethingNew", ["app.tasks.plans"]).startswith("unclassified:")
    assert harness.latency_for("package_repair") == harness.LATENCIES["repair"]
