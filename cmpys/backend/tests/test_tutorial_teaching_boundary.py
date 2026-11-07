"""Regressions from the synthetic persuasive-writing QA run on 2026-10-31."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_review import public_check_inventory, review_lesson
from app.services.planning.lesson_writer import (
    TUTORIAL_SUPPLIED_FACTS_RULE, _TUTORIAL_GROUP, _prompt, _public_package_context,
    _tutorial_binding_correction, _tutorial_compression, _tutorial_teaching_context,
)


def _capture():
    return json.loads((Path(__file__).parent / "fixtures" / "tutorial_teaching_quality.json").read_text())


def _package():
    package = _capture()["writer_package"]
    # The repaired seed has a distinct qualitative teaching case, with no
    # manufactured numbers; the captured activities remain unchanged here.
    package["teaching_cases"] = [{"id": "public_case", "title": "A fictional staff rota",
        "assumptions": "The manager proposes a trial rota, checked against missed handovers.",
        "data": [], "results": []}]
    return package


def test_tutorial_writer_keeps_public_method_and_case_but_hides_assessed_scenarios():
    package = _package()
    before = copy.deepcopy(package)
    prompt = _prompt(_TUTORIAL_GROUP, "Learner is practising policy proposals.", package, [])
    body = json.loads(prompt.split("APPROVED PUBLIC LESSON PACKAGE (reference data):\n")[1])
    assert body == {key: package[key] for key in ("capabilities", "teaching_cases")}
    assert TUTORIAL_SUPPLIED_FACTS_RULE in prompt
    assert "missed handovers" in prompt
    assert "programme coordinator" not in prompt
    assert "good for the town" not in prompt
    assert "sign-in" not in prompt
    assert "which single checklist item" not in prompt
    assert "feasible_practice_minutes_range" in prompt
    assert package == before


def test_long_lesson_retains_public_field_mapping_without_private_keys():
    package = _package()
    public = _public_package_context(package)
    assert public["practice"]["activities"][0]["instructions"]
    field = public["practice"]["activities"][0]["fields"][0]
    assert field["display_token"].startswith("[[practice:")
    assert "correct_choice" not in field
    assert "practice" not in _tutorial_teaching_context(package)


def test_tutorial_compression_and_binding_repairs_keep_the_same_boundary():
    package = _package()
    fields = ("why_this_matters", "core_framework", "worked_example", "failure_modes",
              "check_your_understanding", "references")
    previous = {field: "Reasoned public teaching. " * 100 for field in fields}
    targets = {field: 100 for field in fields}
    compression = _tutorial_compression(previous, targets,
        ["Rendered reading has excessive words"], package, "A trial rota", 7)
    correction = _tutorial_binding_correction(previous,
        ["worked_example must include [[result:public_case.total]]"], package)
    assert compression is not None and correction is not None
    for _, prompt in (compression, correction):
        assert TUTORIAL_SUPPLIED_FACTS_RULE in prompt
        assert "missed handovers" in prompt
        assert "programme coordinator" not in prompt
        assert "good for the town" not in prompt


def _review(audits=None, **changes):
    return {"acceptable": True, "issues": [], "practice_minutes": 3,
        "contains_calculations": False, "calculations": [],
        "public_check_options": audits or [], **changes}


def _shop_audit(*, actor_missing=True):
    return [{"option_id": f"check1.option{index}", "defensible": valid, "reason": reason}
            for index, (valid, reason) in enumerate([
                (actor_missing, "The broad claim names no decision-maker." if actor_missing else
                 "The revised claim explicitly names the shop owner."),
                (False, "Keeping longer hours is the proposed action."),
                (True, "More customers supplies no observable comparison or check."),
                (False, "Longer wording is not a required element.")], 1)]


@pytest.mark.asyncio
async def test_live_shop_check_is_rejected_when_unselected_actor_is_also_defensible():
    lesson = _capture()["ambiguous_shop_check"]
    response = LLMResponse(data=_review(_shop_audit()))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context={})
    assert failures and "ambiguous or incorrect key" in failures[0]
    assert "check1.option1" in failures[0]
    assert returned.data["acceptable"] is False
    assert returned.data["affected_sections"] == ["check_your_understanding"]
    client.generate_json.assert_awaited_once()
    request = json.loads(client.generate_json.await_args.kwargs["user_prompt"])
    options = request["context"]["public_quick_checks"][0]["options"]
    assert len(options) == 4
    assert options[0] == {"option_id": "check1.option1", "text": "Who must act", "selected": False}


@pytest.mark.asyncio
async def test_disambiguated_shop_check_can_publish():
    lesson = _capture()["ambiguous_shop_check"]
    lesson["lesson_content"] = lesson["lesson_content"].replace(
        "Longer hours would bring in more customers.",
        "The shop owner should keep the shop open later to bring in more customers.")
    response = LLMResponse(data=_review(_shop_audit(actor_missing=False)))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context={})
    assert failures == [] and returned.error is None


@pytest.mark.asyncio
@pytest.mark.parametrize("audits", [[], _shop_audit()[1:], _shop_audit() + [_shop_audit()[0]]])
async def test_missing_or_duplicate_alternative_audit_cannot_publish(audits, monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=_review(audits)), LLMResponse(data=_review(audits))]))
    failures, response, _ = await review_lesson(_capture()["ambiguous_shop_check"],
        client_factory=lambda **kw: client, context={})
    assert failures == ["Lesson review quick-check audit incomplete"]
    assert response.error
    assert client.generate_json.await_count == 2
    first, second = client.generate_json.await_args_list
    assert first.kwargs["user_prompt"] == second.kwargs["user_prompt"]


@pytest.mark.asyncio
async def test_content_rejection_is_final_even_without_a_complete_audit():
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=_review(
        acceptable=False, issues=["Public diagram solves the independent evening-centre case."]))))
    failures, _, _ = await review_lesson(_capture()["ambiguous_shop_check"],
        client_factory=lambda **kw: client, context={})
    assert failures == ["Public diagram solves the independent evening-centre case."]
    client.generate_json.assert_awaited_once()


def test_numeric_checks_do_not_request_irrelevant_choice_audits():
    assert public_check_inventory({"lesson_content": "A prose lesson without choices."}) == []


@pytest.mark.asyncio
async def test_final_review_retains_assessed_case_and_key_for_independent_comparison():
    package = _package()
    activities = package.pop("practice")["activities"]
    activities[-1]["worked_solution"] = "Private evening-centre solution for comparison."
    activities[-1]["fields"][-1]["correct_choice"] = "result"
    package["private_workbook"] = {"title": "Practice", "activities": activities}
    response = LLMResponse(data=_review(acceptable=False,
        issues=["The public diagram already solves the private transfer case."]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    await review_lesson({"lesson_content": "A public diagram."},
        client_factory=lambda **kw: client, context={"lesson_package": package})
    request = json.loads(client.generate_json.await_args.kwargs["user_prompt"])
    private = request["context"]["lesson_package"]["private_workbook"]["activities"][-1]
    assert private["worked_solution"] == "Private evening-centre solution for comparison."
    assert private["fields"][-1]["correct_choice"] == "result"
    assert "programme coordinator" in private["instructions"]


@pytest.mark.asyncio
async def test_captured_universal_claim_definition_rejection_survives_valid_quick_check():
    # This published replay had an unambiguous local quick check yet taught a
    # false general definition. A correct check cannot override domain review.
    lesson = _capture()["universal_policy_checklist"]
    audits = [{"option_id": f"check1.option{index}", "defensible": index == 2,
               "reason": "The question asks what the trial length bounds."}
              for index in range(1, 5)]
    issues = ["Factual assertions remain claims; the definition wrongly excludes them.",
              "Observable-outcome tests apply to this policy proposal, not every draft."]
    response = LLMResponse(data=_review(audits, acceptable=False, issues=issues,
        affected_sections=["core_framework", "failure_modes"]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(lesson,
        client_factory=lambda **kw: client, context={"goal": "Write persuasive essays"})
    assert failures == issues
    assert returned.data["affected_sections"] == ["core_framework", "failure_modes"]
    request = json.loads(client.generate_json.await_args.kwargs["user_prompt"])
    assert request["lesson"]["lesson_content"] == lesson["lesson_content"]
    assert "If nobody sane would disagree" in request["lesson"]["lesson_content"]
    assert "Run the three tests on every draft" in request["lesson"]["lesson_content"]
    assert len(request["context"]["public_quick_checks"][0]["options"]) == 4
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
async def test_captured_worked_case_cannot_add_unstated_requirements_to_a_successful_task():
    captured = _capture()["task_scope_mismatch"]
    package = {"teaching_cases": captured["teaching_cases"]}
    case = package["teaching_cases"][0]["assumptions"]
    assert "Narrow your claim about school start times into something testable" in case
    assert "compare attendance before deciding" in case
    assert "attempt is incomplete on both fronts" in case
    response = LLMResponse(data=_review(acceptable=False,
        package_issues=["The teaching case adds evidence selection and objection response as requirements "
                        "although the stated task asks only for a testable narrowed claim."],
        package_issue_targets=["package"],
        issues=["The worked example omits the learner's uncertainty remark before using it as evidence."],
        affected_sections=["core_framework", "worked_example", "check_your_understanding"]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(captured["lesson"],
        client_factory=lambda **kw: client, context={"lesson_package": package})
    assert len(failures) == 2 and not returned.data["acceptable"]
    assert returned.data["package_issue_targets"] == ["package"]
    # A whole teaching-case rejection blocks publication; it must not grant
    # an activity-only repair permission to alter unrelated source facts.
    assert "validated_repair_targets" not in returned.effective_parameters
    request = json.loads(client.generate_json.await_args.kwargs["user_prompt"])
    assert request["context"]["lesson_package"]["teaching_cases"] == captured["teaching_cases"]
    assert request["lesson"]["lesson_content"] == captured["lesson"]["lesson_content"]
    rubric = client.generate_json.await_args.kwargs["system_prompt"]
    assert "The bounded trial and comparison MEET the stated task" in rubric
    assert "a later skill cannot retroactively become an earlier task's requirement" in rubric
    client.generate_json.assert_awaited_once()


def test_writer_has_all_captured_source_premises_without_private_assessment_inputs():
    package = _package()
    package["teaching_cases"] = _capture()["task_scope_mismatch"]["teaching_cases"]
    prompt = _prompt(_TUTORIAL_GROUP, "Teach an honest criteria-based verdict.", package, [])
    assert "I don't know what evidence would count" in prompt
    assert "later starts cut sports practice time" in prompt
    assert "Show every source premise needed to follow a worked verdict" in prompt
    flat = " ".join(prompt.split())
    assert "Judge an attempt against its stated task, not a future learning need" in flat
    assert "Show the original task and complete relevant attempt before its verdict" in flat
    assert "a requested gap cannot justify inventing a failed requirement" in flat
    assert "programme coordinator" not in prompt


def test_captured_step_notes_render_without_losing_their_meaning():
    from app.services.planning.tutorial_visuals import native_fences, parse_steps

    # Format acceptance is separate from the semantic review of this capture.
    body = next(body for kind, body in native_fences(_capture()["long_step_notes"]) if kind == "steps")
    block = parse_steps(body)
    assert block is not None
    notes = [line.split("|")[2].strip() for line in body.splitlines() if line.count("|") == 2]
    assert [len(note) for note in notes] == [68, 194, 190]
    assert [row.note for row in block.rows] == notes
    at_limit = "title: T\nA | | " + "n" * 320 + "\nB | | Reason."
    assert len(parse_steps(at_limit).rows[0].note) == 320
    assert parse_steps(at_limit.replace("n" * 320, "n" * 321)) is None


@pytest.mark.asyncio
async def test_correct_quick_check_key_does_not_override_false_distractor_explanation():
    lesson = _capture()["false_check_explanation"]
    audits = [{"option_id": f"check1.option{index}", "defensible": index == 3,
               "reason": "Only the keyed proposal supplies the requested testable because-clause."}
              for index in range(1, 5)]
    issue = "The Why calls a factual claim a topic phrase; it instead lacks the requested policy proposal."
    response = LLMResponse(data=_review(audits, acceptable=False, issues=[issue],
        affected_sections=["check_your_understanding"]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context={})
    assert failures == [issue] and not returned.data["acceptable"]
    request = json.loads(client.generate_json.await_args.kwargs["user_prompt"])
    check = request["context"]["public_quick_checks"][0]
    assert check["options"][3]["text"] == "Free buses are popular in many cities"
    assert "first and fourth are topic statements" in check["why"]
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
async def test_acceptance_claim_definition_and_popularity_proxy_are_blocking_teaching_defects():
    lesson = _capture()["assertion_testability_confusion"]
    assert "A claim asserts something about that subject that a finding could disprove" in lesson["lesson_content"]
    assert "ridership survey showing low use would count against it" in lesson["lesson_content"]
    # The selected option is right; the universal definition and its rationale
    # still misteach claim status and substitute use for a popularity predicate.
    audits = [{"option_id": f"check1.option{index}", "defensible": index == 2,
               "reason": "B is a topic phrase, while A asserts popularity."}
              for index in range(1, 5)]
    issues = ["The definition excludes evaluative and normative claims without an empirical test.",
              "The Why substitutes low ridership for low popularity without defining or justifying that proxy."]
    response = LLMResponse(data=_review(audits, acceptable=False, issues=issues,
        affected_sections=["why_this_matters", "core_framework", "worked_example",
                           "failure_modes", "check_your_understanding"]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context={})
    assert failures == issues and not returned.data["acceptable"]
    request = json.loads(client.generate_json.await_args.kwargs["user_prompt"])
    assert request["lesson"]["lesson_content"] == lesson["lesson_content"]
    assert "low use" in request["context"]["public_quick_checks"][0]["why"]
    rubric = client.generate_json.await_args.kwargs["system_prompt"]
    assert "A topic-versus-claim task tests assertion" in rubric
    assert "popularity is explicitly defined as use and the link is justified" in rubric
    client.generate_json.assert_awaited_once()


def test_captured_quoted_question_preserves_all_cases_under_bounded_grammar():
    from app.services.planning.tutorial_visuals import native_fences, parse_check

    # Format acceptance is not semantic approval of the captured answer key.
    body = next(body for kind, body in native_fences(_capture()["quoted_case_question"]) if kind == "check")
    block = parse_check(body)
    assert block is not None and len(block.question) == 251
    assert block.question == body.splitlines()[0].removeprefix("Q: ")
    assert all(case in block.question for case in ('A: "', 'B: "', 'C: "', 'D: "'))
    bounded = "Q: " + "q" * 480 + "\n- [x] A\n- [ ] B\nWhy: The supplied case."
    assert len(parse_check(bounded).question) == 480
    assert parse_check(bounded.replace("q" * 480, "q" * 481)) is None


def test_captured_title_normalization_removes_only_empty_metadata():
    from app.services.planning.tutorial_visuals import native_fences, normalize_native_fences, parse_steps

    source = _capture()["empty_title_metadata"]
    normalized = normalize_native_fences(source)
    assert normalized == normalize_native_fences(source.replace("\tnote: ", ""))
    assert normalize_native_fences(normalized) == normalized
    body = next(body for kind, body in native_fences(normalized) if kind == "steps")
    assert parse_steps(body).title == "Food pantry claim check"
    # Nonempty metadata must not be discarded; leave it for a bounded repair.
    content = source.replace("\tnote: ", "\tnote: Important source fact")
    assert normalize_native_fences(content) == normalized.replace(
        "title: Food pantry claim check", "title: Food pantry claim check\tnote: Important source fact")
    body = next(body for kind, body in native_fences(content) if kind == "steps")
    assert parse_steps(body) is None
    plain = "title: A note: on claims\nA | | First reason.\nB | | Second reason."
    assert parse_steps(plain).title == "A note: on claims"


def test_support_distinctions_reach_initial_and_repair_prompts_without_changing_supplied_time():
    package = _package()
    source = ("The library closes at 17:30 on Tuesdays. Its books and computers support "
              "the argument for evening access only if workers need them after closing.")
    package["teaching_cases"][0]["assumptions"] = source
    before = copy.deepcopy(package)
    fields = ("why_this_matters", "core_framework", "worked_example", "failure_modes",
              "check_your_understanding", "references")
    previous = {field: "Reasoned public teaching. " * 100 for field in fields}
    compression = _tutorial_compression(previous, {field: 100 for field in fields},
        ["Rendered reading has excessive words"], package, "Relevant factual support", 7)
    correction = _tutorial_binding_correction(previous,
        ["worked_example must include [[result:public_case.total]]"], package)
    assert compression is not None and correction is not None
    prompts = [_prompt(_TUTORIAL_GROUP, "Explain claims and relevant evidence.", package, []),
               compression[1], correction[1]]
    for prompt in prompts:
        assert source in prompt and TUTORIAL_SUPPLIED_FACTS_RULE in prompt
        assert "Classification, contestability, truth, evidential support and argumentative usefulness are distinct" in prompt
        assert "being uncontested does not make a factual claim weakly supported or useless" in prompt
        assert "An uncontested fact can support a disputed conclusion when its relevance is explained" in prompt
        assert "assess support from the supplied evidence and usefulness from that connection" in prompt
        assert "Being inadequate as a stand-alone thesis does not make a fact unusable as a supporting premise" in prompt
        assert "Never infer that it supports no contested position solely because it is undisputed" in prompt
        assert "Preserve these distinctions during repairs" in prompt
        assert "Mentioning a subject does not make an assertion a topic" in prompt
        assert "a topic only names a subject without asserting anything" in prompt
        assert "explain why each distractor's inference fails" in prompt
        assert "never endorse its false rule even when the key is correct" in prompt
        assert "State every qualifier essential to an explanation's accuracy in the explanation itself" in prompt
        assert "do not rely on the reader to silently add missing conditions" in prompt
    assert package == before
