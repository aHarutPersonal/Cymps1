"""The offline timing harness drives the real tutorial pipeline end to end."""
import json

import pytest

from scripts import simulate_tutorial_timing as harness
from tests.phase0_fixtures import model_binder_mechanics  # noqa: F401


# Phase 0.4: exercises the model binder; keep earlier server bindings.
@pytest.mark.usefixtures("model_binder_mechanics")
def test_harness_publishes_both_scenarios_with_the_overlapped_critical_path(tmp_path):
    from app.services.llm import client, telemetry
    originals = (client.get_llm_client, telemetry.record_llm_response)
    out = tmp_path / "timing.json"
    # Preserve a 100 ms writer/preflight gap: at 0.01 it is only 10 ms,
    # which local payload processing can consume and change the inferred path.
    assert harness.main(["--scenario", "all", "--runs", "1", "--time-scale", "0.1", "--out", str(out)]) == 0
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


def test_canned_preflight_checks_full_package_and_only_expected_repair():
    import copy
    import pytest

    data = {
        "choice_audit_inventory": {}, "text_audit_inventory": {},
        "teaching_case_audit_inventory": ["teaching.example"],
        "package": harness._expected_preflight_package(repaired=False),
        "numerical_evidence": [
            {"target": "teaching_cases[example].results[double]", "value": 20},
            {"target": "workbook.activities[guided].fields[double]", "value": 24},
            {"target": "workbook.activities[transfer].fields[double]", "value": 26},
        ],
    }
    harness._validate_preflight_fixture(data, repaired=False)
    changed = copy.deepcopy(data)
    changed["package"]["teaching_cases"][0]["results"][0]["unit"] = "cm"
    with pytest.raises(AssertionError):
        harness._validate_preflight_fixture(changed, repaired=False)
    changed = copy.deepcopy(data)
    changed["package"]["workbook"]["activities"][1]["fields"][0]["expression"] = "amount * 3"
    with pytest.raises(AssertionError):
        harness._validate_preflight_fixture(changed, repaired=False)
    repaired = copy.deepcopy(data)
    repaired["package"] = harness._expected_preflight_package(repaired=True)
    harness._validate_preflight_fixture(repaired, repaired=True)
    with pytest.raises(AssertionError):
        harness._validate_preflight_fixture(data, repaired=True)
    repaired["package"]["workbook"]["activities"][1]["worked_solution"] += " wrong"
    with pytest.raises(AssertionError):
        harness._validate_preflight_fixture(repaired, repaired=True)


def test_canned_public_review_rejects_altered_sections_and_answer_keys():
    import copy
    import pytest

    sections, checks = copy.deepcopy(harness._EXPECTED_SECTIONS), copy.deepcopy(harness._EXPECTED_CHECKS)
    harness._validate_public_fixture(sections, checks)
    changed_sections = copy.deepcopy(sections)
    changed_sections["worked_example"] = changed_sections["worked_example"].replace("20.0", "30.0")
    with pytest.raises(AssertionError):
        harness._validate_public_fixture(changed_sections, checks)
    changed_checks = copy.deepcopy(checks)
    changed_checks[0]["options"][0]["selected"] = True
    changed_checks[0]["options"][1]["selected"] = False
    with pytest.raises(AssertionError):
        harness._validate_public_fixture(sections, changed_checks)
    assert harness._OPTION_TRUTH == {"check1.option1": False, "check1.option2": True}
