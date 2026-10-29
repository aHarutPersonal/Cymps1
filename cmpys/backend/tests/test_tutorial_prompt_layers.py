"""Layered tutorial_v1 prompts: one shared contract, domain notes and valid exemplars."""
import json
import re
import shutil

import pytest

from app.services.llm import prompt_loader
from app.services.llm.prompt_loader import load_and_render, resolve_prompt_text
from app.services.planning import lesson_package
from app.services.planning.activity_draft import TutorialActivityDraft, parse_activity_draft
from app.services.planning.package_builder import LessonPackageSeed

SEED, ACTIVITY = "tutorial_package_seed.txt", "tutorial_activity_generate.txt"
RULE_IDS = ("[R-SCOPE]", "[R-TRANSFER]", "[R-FIELDS]", "[R-DATA]", "[R-TIME]",
            "[R-SELF-CONTAINED]", "[R-SOURCES]", "[R-LANGUAGE]", "[R-JSON]")
NEGATIONS = r"\b(never|not|no|don't|do not)\b"


def test_includes_resolve_and_render():
    for name in (SEED, ACTIVITY):
        rendered = load_and_render(name, {})
        assert "{{include:" not in rendered
        assert "TUTORIAL_V1 CONTRACT" in rendered


def test_contract_appears_once_per_rendered_prompt():
    contract = (prompt_loader.PROMPTS_DIR / "tutorial_contract.txt").read_text().rstrip("\n")
    for name in (SEED, ACTIVITY):
        rendered = load_and_render(name, {})
        assert rendered.count(contract) == 1
        for rule_id in RULE_IDS:
            assert rendered.count(rule_id) == 1, (name, rule_id)


def test_numeric_answer_rules_reach_activities_only():
    assert "NUMERIC ANSWERS AND EXPLANATIONS" in load_and_render(ACTIVITY, {})
    assert "NUMERIC ANSWERS AND EXPLANATIONS" not in load_and_render(SEED, {})
    for name in (SEED, ACTIVITY):
        rendered = load_and_render(name, {})
        assert "DOMAIN NOTES — numbers" in rendered and "DOMAIN NOTES — writing" in rendered


def test_domain_incident_rules_are_preserved_in_their_notes():
    activity = " ".join(load_and_render(ACTIVITY, {}).split())
    for marker in ("prior-period collections and payments", "overdue rent", "tolerance of 0.01",
                   "symbolic formula", "quoting its opening words", "untrusted reference data"):
        assert marker in activity, marker


def test_numbers_in_quoted_material_are_declared_data():
    # A memo-shape tutorial quoted "$82,000" in a sample memo with data: [];
    # the evidence gate rejected every attempt, so the rule names quoted text.
    for name in (SEED, ACTIVITY):
        rendered = " ".join(load_and_render(name, {}).split())
        assert "Every raw number shown in a task, hint or explanation, quoted material included" in rendered
    activity = " ".join(load_and_render(ACTIVITY, {}).split())
    assert "lists every raw number in the instructions, hint or explanations" in activity


def test_rubric_rows_never_state_the_answer():
    # A multi_choice row read "Labels the sentence as numbers, sources and
    # checks": the exact answer set, shown before the learner answered.
    from app.services.practice.contracts import GeneratedWorkbook

    answer = GeneratedWorkbook.model_json_schema()["$defs"]["AnswerField"]
    for text in (load_and_render(ACTIVITY, {}), resolve_prompt_text("lesson_practice_generate.txt"),
                 answer["properties"]["rubric_criterion"]["description"]):
        text = " ".join(text.split())
        assert "naming what a correct answer shows" not in text
        assert "never the answer itself" in text


def test_multi_choice_keys_are_the_only_defensible_set():
    # A guided key {sources, checks} was rejected: a vague "Sources" line made
    # {checks} alone defensible. Single-choice uniqueness now covers sets too.
    for name in (SEED, ACTIVITY):
        rendered = " ".join(load_and_render(name, {}).split())
        assert ("Choice and multi_choice keys are the only defensible option or set "
                "from supplied facts, with no borderline options") in rendered


def _exemplar(name: str) -> dict:
    return json.loads(resolve_prompt_text(name).split("\n", 1)[1])


@pytest.mark.parametrize("name", ["tutorial_exemplar_qualitative.txt", "tutorial_exemplar_quantitative.txt"])
def test_activity_exemplars_satisfy_the_real_contract(name):
    data = _exemplar(name)
    TutorialActivityDraft.model_validate(data)
    parse_activity_draft(data)
    assert len(data["instructions"]) <= 1500
    assert sum(len(field["explanation"]) for field in data["fields"]) <= 1500


def test_seed_exemplar_satisfies_the_real_contract():
    seed = load_and_render(SEED, {})
    example = seed[seed.index("ILLUSTRATIVE SEED"):].split("\n", 1)[1]
    LessonPackageSeed.model_validate(json.loads(example))


def test_rendered_prompt_budget():
    """Guard against re-accreting incident patches into the universal prompts."""
    for name, max_chars, max_negations in ((SEED, 11000, 42), (ACTIVITY, 16500, 55)):
        rendered = load_and_render(name, {})
        assert len(rendered) <= max_chars, (name, len(rendered))
        assert len(re.findall(NEGATIONS, rendered, re.I)) <= max_negations, name
    assert len((prompt_loader.PROMPTS_DIR / "tutorial_contract.txt").read_text()) <= 4500


def test_validation_identity_changes_when_included_file_changes(tmp_path, monkeypatch):
    copy = tmp_path / "prompts"
    shutil.copytree(prompt_loader.PROMPTS_DIR, copy, ignore=shutil.ignore_patterns("*.db", ".claude"))
    monkeypatch.setattr(prompt_loader, "PROMPTS_DIR", copy)
    before = lesson_package.validation_identity()["prompt_hash"]
    contract = copy / "tutorial_contract.txt"
    contract.write_text(contract.read_text() + "[R-EXTRA] A changed shared rule.\n")
    assert lesson_package.validation_identity()["prompt_hash"] != before


def test_nested_includes_are_rejected(tmp_path):
    (tmp_path / "outer.txt").write_text("A\n{{include:middle.txt}}\n")
    (tmp_path / "middle.txt").write_text("{{include:inner.txt}}\n")
    (tmp_path / "inner.txt").write_text("C\n")
    with pytest.raises(ValueError):
        resolve_prompt_text("outer.txt", tmp_path)


def test_tutorial_pilot_outline_is_a_valid_tutorial_scaffold():
    import importlib.util
    from pathlib import Path
    spec = importlib.util.spec_from_file_location(
        "pilot_generation", Path(__file__).resolve().parents[1] / "scripts" / "pilot_generation.py")
    pilot = importlib.util.module_from_spec(spec); spec.loader.exec_module(pilot)
    scenarios = json.loads((Path(__file__).parent / "fixtures" / "generation_scenarios.json").read_text())
    for case in scenarios:
        outline = pilot.tutorial_outline(case)
        assert outline["lesson_format"] == "tutorial_v1"
        assert [step["lesson_format"] for step in outline["steps"]] == ["tutorial_v1"]
        assert len(outline["steps"][0]["title"]) <= 60
