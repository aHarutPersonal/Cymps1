"""Section coverage cannot be replaced by an aggregate approval or a correct quiz."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_review import (
    PackagedLessonReview, REVIEW_VERSION, public_check_inventory, public_section_inventory,
    review_lesson, review_response_quality,
)


def _lesson():
    path = Path(__file__).parent / "fixtures" / "tutorial_teaching_quality.json"
    return json.loads(path.read_text())["factual_claim_section_contradiction"]


def _audits(lesson):
    # Test doubles exercise the gate, not the real model's semantic accuracy.
    return [{"section_id": section, "source_quote": text[:100], "domain_valid": True,
             "consistent_with_core": True,
             "reason": "The quoted teaching passage is evaluated against the assertion-based definition."}
            for section, text in public_section_inventory(lesson).items()]


def _response(lesson, **changes):
    return LLMResponse(data={"acceptable": True, "issues": [], "practice_minutes": 3,
        "contains_calculations": False, "calculations": [], "public_sections": _audits(lesson),
        "public_check_options": [
            {"option_id": option["option_id"], "defensible": option["selected"],
             "reason": "The supplied noun phrase names a subject without asserting something."}
            for check in public_check_inventory(lesson) for option in check["options"]], **changes},
        finish_reason="stop")


@pytest.mark.asyncio
@pytest.mark.parametrize("aggregate_approval", [True, False])
@pytest.mark.parametrize("invalid_property", ["domain_valid", "consistent_with_core"])
async def test_captured_false_failure_mode_requires_only_its_section_repair(aggregate_approval, invalid_property):
    lesson = _lesson()
    assert "Accepted facts, value judgments and normative positions all count as claims" in lesson["lesson_content"]
    assert "'Libraries have books and computers' informs but disputes nothing" in lesson["lesson_content"]
    response = _response(lesson, acceptable=aggregate_approval)
    audit = next(a for a in response.data["public_sections"] if a["section_id"] == "failure_modes")
    audit.update({invalid_property: False,
        "source_quote": "'Libraries have books and computers' informs but disputes nothing",
        "reason": "This asserts a factual property of libraries, so denying its claim status contradicts the Core Framework's accepted-facts rule."})
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    options = []
    def factory(**kwargs):
        options.append(kwargs)
        return client
    failures, returned, _ = await review_lesson(lesson, client_factory=factory, context={"lesson_package": {}})
    assert len(failures) == 1 and failures[0].startswith("Public section failure_modes:")
    assert audit["source_quote"] in failures[0] and audit["reason"] not in failures[0]
    assert returned.data["acceptable"] is False
    assert returned.data["affected_sections"] == ["failure_modes"]
    assert not returned.data["package_issues"]
    assert review_response_quality(returned) == 0
    client.generate_json.assert_awaited_once()
    request = client.generate_json.await_args.kwargs
    body = json.loads(request["user_prompt"])
    assert body["lesson"]["lesson_content"] == lesson["lesson_content"]
    assert body["context"]["public_section_ids"] == list(public_section_inventory(lesson))
    assert len(body["context"]["public_section_ids"]) == 6
    assert "'Libraries have books and computers' is a factual assertion" in request["system_prompt"]
    assert issubclass(request["output_model"], PackagedLessonReview)
    assert options[0]["max_tokens"] == 4000 and options[0]["allow_fallback"] is False


@pytest.mark.asyncio
@pytest.mark.parametrize("defect", ["omitted", "missing", "duplicate", "unknown", "wrong_quote", "blank_reason", "missing_judgment", "coerced_bool"])
async def test_incomplete_positive_section_audit_fails_after_existing_bounded_retry(defect, monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    lesson = _lesson()
    response = _response(lesson)
    audits = response.data["public_sections"]
    if defect == "omitted":
        response.data.pop("public_sections")
    elif defect == "missing":
        audits.pop()
    elif defect == "duplicate":
        audits[-1] = copy.deepcopy(audits[0])
    elif defect == "unknown":
        audits[-1]["section_id"] = "not_a_section"
    elif defect == "wrong_quote":
        audits[-1]["source_quote"] = "Not in this section."
    elif defect == "blank_reason":
        audits[-1]["reason"] = "   "
    elif defect == "missing_judgment":
        audits[-1].pop("domain_valid")
    else:
        audits[-1]["domain_valid"] = "true"
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[response, copy.deepcopy(response)]))
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context={"lesson_package": {}})
    assert failures and returned.error
    assert review_response_quality(returned) == 0
    assert client.generate_json.await_count == 2
    first, retry = client.generate_json.await_args_list
    assert first.kwargs["user_prompt"] == retry.kwargs["user_prompt"]


@pytest.mark.asyncio
async def test_only_complete_section_coverage_can_restore_positive_review(monkeypatch):
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    lesson = _lesson()
    lesson["lesson_content"] = lesson["lesson_content"].replace(
        "Common mistake: treating any informative sentence as a claim because it contains facts. Correction: apply the test — ask whether a reasonable person could disagree and whether the sentence commits its author. 'Libraries have books and computers' informs but disputes nothing; 'Sunday opening would help everyone' disputes.",
        "Common mistake: confusing an accepted assertion with a topic. 'Libraries have books and computers' is a factual claim. Acceptance does not erase its assertion; evidence and precision remain separate questions.")
    missing = _response(lesson, public_sections=[])
    complete = _response(lesson)
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[missing, complete]))
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context={"lesson_package": {}})
    assert not failures and returned is complete and not returned.error
    assert len(returned.data["public_sections"]) == 6
    assert client.generate_json.await_count == 2


@pytest.mark.asyncio
async def test_negative_review_is_final_with_missing_section_coverage():
    lesson = _lesson()
    response = _response(lesson, acceptable=False, issues=["The Failure Modes section denies factual claim status."], public_sections=[])
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context={"lesson_package": {}})
    assert failures == response.data["issues"] and not returned.error
    client.generate_json.assert_awaited_once()


def test_inventory_tracks_actual_legacy_tutorial_sections_without_affecting_long_lessons():
    lesson = _lesson()
    lesson["lesson_content"] += "\n\n## Guided Practice\nApply the assertion test to the supplied sentence."
    assert len(public_section_inventory(lesson)) == 7
    assert public_section_inventory({**lesson, "lesson_format": None}) == {}
    assert REVIEW_VERSION == 34


@pytest.mark.asyncio
async def test_captured_high_reasoning_rejection_survives_363_character_reason():
    path = Path(__file__).parent / "fixtures" / "tutorial_teaching_quality.json"
    captured = json.loads(path.read_text())["factual_claim_high_review"]
    failure_audit = next(a for a in captured["public_sections"] if a["section_id"] == "failure_modes")
    assert len(failure_audit["reason"]) == 363
    response = LLMResponse(data=copy.deepcopy(captured), finish_reason="stop")
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(_lesson(), client_factory=lambda **kw: client,
                                               context={"lesson_package": {}})
    assert returned.error is None and returned.data["acceptable"] is False
    assert all(issue in failures for issue in captured["issues"])
    assert any(issue.startswith("Public section failure_modes:") and failure_audit["source_quote"] in issue
               for issue in failures)
    assert returned.data["affected_sections"] == ["failure_modes"]
    assert returned.data["public_sections"] == captured["public_sections"]
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize("profile,lesson_format,numeric_count,thinking,tokens", [
    ("focused", "tutorial_v1", 0, "low", 4000),
    ("routed", "tutorial_v1", 0, "low", 4000),
    ("dummy", "tutorial_v1", 0, "low", 4000),
    ("focused", None, 0, "low", 8000),
    ("focused", "tutorial_v1", 11, "low", 8000),
])
async def test_full_review_keeps_low_reasoning_and_profile_token_limits(
        monkeypatch, profile, lesson_format, numeric_count, thinking, tokens):
    from app.core.config import settings
    monkeypatch.setattr(settings, "llm_provider", "dummy" if profile == "dummy" else "routed")
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", profile == "focused")
    lesson = {"lesson_format": lesson_format, "lesson_content": "A qualitative explanation."}
    if numeric_count:
        lesson["lesson_content"] = " ".join(f"Observed value: {i}." for i in range(numeric_count))
    # This test verifies routing only; a negative verdict returns before proof repair.
    response = _response(lesson, acceptable=False, issues=["Offline routing fixture."])
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    options = []
    def factory(**kwargs):
        options.append(kwargs)
        return client
    await review_lesson(lesson, client_factory=factory, context={"lesson_package": {}})
    assert options == [{"tier": "balanced", "timeout": 120, "max_tokens": tokens,
                        "thinking_level": thinking, "allow_fallback": False}]
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", ["anthropic", "openai"])
async def test_compact_review_wire_budget_keeps_global_reserve_and_deadline(monkeypatch, provider):
    from app.core.config import settings
    from app.services.llm.client import get_llm_client
    from tests.direct_wire import Reply, serve

    monkeypatch.setattr(settings, "llm_provider", "routed")
    monkeypatch.setattr(settings, f"{provider}_api_key", "offline-fixture-key")
    monkeypatch.setattr(settings, f"{provider}_reasoning_token_reserve", 2048)
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    lesson = _lesson()
    verdict = _response(lesson, acceptable=False, issues=["Offline wire-budget fixture."]).data
    wires, clients = [], []
    def factory(**kwargs):
        client = get_llm_client(**kwargs, provider=provider)
        wires.append(serve(client, [Reply(json.dumps(verdict), "stop")]))
        clients.append(client)
        return client
    failures, returned, _ = await review_lesson(lesson, client_factory=factory,
                                               context={"lesson_package": {}})
    assert failures == verdict["issues"] and not returned.error
    assert len(clients) == 1 and clients[0].timeout == 120
    request = wires[0].request
    if provider == "anthropic":
        assert request["max_tokens"] == 6048 and request["output_config"]["effort"] == "low"
    else:
        assert request["max_completion_tokens"] == 6048 and request["reasoning_effort"] == "low"


@pytest.mark.asyncio
async def test_captured_reasoning_only_length_response_never_approves_or_rewrites():
    path = Path(__file__).parent / "fixtures" / "tutorial_teaching_quality.json"
    captured = json.loads(path.read_text())["reasoning_only_review"]
    assert captured["thoughts_tokens"] == captured["completion_tokens"] == 6048
    assert captured["response_chars"] == 0 and captured["data"] == {}
    response = LLMResponse(**captured)
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(_lesson(), client_factory=lambda **kw: client,
                                               context={"lesson_package": {}})
    assert failures == ["Content review unavailable; lesson must not be published"]
    assert "incomplete" in returned.error and returned.data == {}
    assert review_response_quality(returned) == 0
    client.generate_json.assert_awaited_once()



def _conflict():
    path = Path(__file__).parent / "fixtures" / "tutorial_teaching_quality.json"
    return json.loads(path.read_text())["teaching_grading_conflict"]


def _focused_review(lesson, context):
    from app.services.planning.lesson_review import _public_accuracy_payload
    payload = _public_accuracy_payload(lesson, context)
    result = {"public_sections": _audits(lesson), "practice_alignment": [
        {"target": field["target"], "aligned": True, "public_rule_valid": True, "public_section_id": "core_framework",
         "public_quote": payload["sections"]["core_framework"][:100],
         "assessment_source": "criteria", "assessment_quote": field["criteria"][0],
         "repair_scope": "none", "reason": "Offline gate fixture: semantic alignment is supplied by the mock critic."}
        for activity in payload["practice_contracts"] for field in activity["fields"]]}
    if not result["practice_alignment"]:
        result.pop("practice_alignment")
    return result


def _split_critic_client(response):
    from app.services.planning.lesson_review import AlignmentOnlyReview
    public = response.model_copy(deep=True)
    public.data = {"public_sections": response.data["public_sections"]}
    alignment = response.model_copy(deep=True)
    alignment.data = {"practice_alignment": response.data["practice_alignment"]}
    async def generate(**kwargs):
        return alignment if kwargs["output_model"] is AlignmentOnlyReview else public
    return SimpleNamespace(model="critic", generate_json=AsyncMock(side_effect=generate),
                           public_response=public, alignment_response=alignment)


def test_accuracy_projection_retains_grading_semantics_without_full_context():
    from app.services.planning.lesson_review import _public_accuracy_payload
    captured = _conflict()
    context = captured["context"]
    context.update(learner_context="PRIVATE_HISTORY_MARKER", numeric_span_owners="PRIVATE_INVENTORY_MARKER")
    payload = _public_accuracy_payload(captured["lesson"], context)
    assert set(payload) == {"sections", "teaching_cases", "practice_contracts"}
    assert "PRIVATE_HISTORY_MARKER" not in json.dumps(payload)
    assert "PRIVATE_INVENTORY_MARKER" not in json.dumps(payload)
    first = payload["practice_contracts"][0]
    assert set(first) == {"target", "instructions", "worked_solution", "fields", "data", "diagram"}
    assert "treating the actor or action as missing" in first["worked_solution"]
    assert "Labels the named actor as present" in first["fields"][0]["criteria"][0]
    assert set(first["fields"][0]) == {"target", "label", "kind", "unit", "expression", "choices", "answer_key", "criteria", "rubric_criterion"}
    # Preserve choice alternatives as well as their key, for any choice fields.
    raw = context["lesson_package"]["private_workbook"]["activities"][0]["fields"][0]
    raw.update(kind="choice", choices=[{"id": "actor", "label": "Define the actor"},
        {"id": "success", "label": "Define success"}], correct_choice="success")
    field = _public_accuracy_payload(captured["lesson"], context)["practice_contracts"][0]["fields"][0]
    assert field["choices"] == raw["choices"] and field["answer_key"] == "success"


@pytest.mark.asyncio
async def test_real_full_approval_then_focused_rejection_records_extra_usage_once(monkeypatch):
    from app.core.config import settings
    from app.services.planning.lesson_review import PublicAccuracyReview, _PUBLIC_ACCURACY_SYSTEM
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    lesson = _lesson()
    full = _response(lesson)
    focused = LLMResponse(data=_focused_review(lesson, {}), finish_reason="stop")
    bad = next(a for a in focused.data["public_sections"] if a["section_id"] == "failure_modes")
    bad.update(domain_valid=False, consistent_with_core=False,
        reason="Accepted factual assertions remain claims; the failure-mode example falsely denies that status.")
    client = SimpleNamespace(model="offline", generate_json=AsyncMock(side_effect=[full, focused]))
    options = []
    def factory(**kwargs):
        options.append(kwargs)
        return client
    failures, returned, _ = await review_lesson(lesson, client_factory=factory, context={"lesson_package": {}})
    assert failures and returned is full and not returned.error
    assert returned.data["affected_sections"] == ["failure_modes"]
    assert returned.data["acceptable"] is False
    assert options == [
        {"tier": "balanced", "timeout": 120, "max_tokens": 4000, "thinking_level": "low", "allow_fallback": False},
        {"tier": "balanced", "timeout": 120, "max_tokens": 6000, "thinking_level": "high", "allow_fallback": False}]
    critic_request = client.generate_json.await_args_list[1].kwargs
    assert critic_request["output_model"] is PublicAccuracyReview
    assert critic_request["system_prompt"] == _PUBLIC_ACCURACY_SYSTEM
    record.assert_awaited_once()
    assert record.await_args.kwargs["response"] is focused
    assert record.await_args.kwargs["operation"] == "lesson_review_public_accuracy"
    assert record.await_args.kwargs["result_status"] == "rejected"


@pytest.mark.asyncio
@pytest.mark.parametrize("scope", ["field", "activity", "public"])
async def test_captured_teaching_grading_conflict_routes_to_actual_owner(monkeypatch, scope):
    from app.core.config import settings
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    captured = _conflict()
    lesson, context = captured["lesson"], captured["context"]
    full = _response(lesson)
    full.data["advisories"] = ["Retain the prior full review's evidence and workload."]
    original_minutes = full.data["practice_minutes"]
    full_client = SimpleNamespace(model="full-review")
    monkeypatch.setattr("app.services.planning.lesson_review._review_lesson_full",
                        AsyncMock(return_value=([], full, full_client)))
    data = _focused_review(lesson, context)
    item = data["practice_alignment"][0]
    item.update(aligned=False, repair_scope=scope,
        public_quote='"The town" hides the decision-maker; "the council" names it',
        reason="The public test requires an exact decision-maker, so the rubric cannot reject an actor-first answer for this wording.")
    if scope == "activity":
        item.update(assessment_source="worked_solution",
            assessment_quote="treating the actor or action as missing mistakes vagueness of intent for absence in the wording")
    if scope == "public":
        item["public_rule_valid"] = False
        public = next(a for a in data["public_sections"] if a["section_id"] == "core_framework")
        public.update(domain_valid=False, reason="Mock alternative diagnosis: this public rule is wrong, while grading is valid.")
    focused = LLMResponse(data=data, finish_reason="stop")
    client = _split_critic_client(focused)
    failures, returned, reviewer = await review_lesson(lesson, client_factory=lambda **kw: client, context=context)
    assert failures and returned is full and reviewer is full_client and not returned.error
    assert returned.data["practice_minutes"] == original_minutes
    assert returned.data["advisories"] == ["Retain the prior full review's evidence and workload."]
    if scope == "public":
        assert returned.data["affected_sections"] == ["core_framework"]
        assert returned.data["package_issues"] == []
        assert not (returned.effective_parameters or {}).get("validated_repair_targets")
    else:
        target = "practice.guided_pilot_check" + (".claim_check" if scope == "field" else "")
        assert returned.data["affected_sections"] == []
        assert returned.data["package_issue_targets"] == [target]
        assert returned.effective_parameters["validated_repair_targets"] == [target]
    assert client.generate_json.await_count == record.await_count == 2
    assert {call.kwargs["operation"] for call in record.await_args_list} == {
        "lesson_review_public_accuracy", "lesson_review_practice_alignment"}


@pytest.mark.asyncio
@pytest.mark.parametrize("defect", ["missing_field", "duplicate_field", "unknown_field", "bad_public_quote", "bad_assessment_quote", "bad_section_quote", "wrong_scope", "missing_section", "malformed", "length", "transport"])
async def test_focused_review_missing_or_unanchored_evidence_never_approves_or_retries(monkeypatch, defect):
    from app.core.config import settings
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    captured = _conflict()
    lesson, context = captured["lesson"], captured["context"]
    full = _response(lesson)
    monkeypatch.setattr("app.services.planning.lesson_review._review_lesson_full",
                        AsyncMock(return_value=([], full, SimpleNamespace(model="full"))))
    data = _focused_review(lesson, context)
    item = data["practice_alignment"][0]
    if defect == "missing_field": data["practice_alignment"].pop()
    elif defect == "duplicate_field": data["practice_alignment"][-1] = copy.deepcopy(item)
    elif defect == "unknown_field": item["target"] = "practice.unowned.field"
    elif defect == "bad_public_quote":
        item.update(aligned=False, repair_scope="field", public_quote="Not in the public section")
    elif defect == "bad_assessment_quote":
        item.update(aligned=False, repair_scope="field", assessment_quote="Not in the assessment source")
    elif defect == "bad_section_quote":
        data["public_sections"][0].update(domain_valid=False, source_quote="Not in this section")
    elif defect == "wrong_scope":
        item.update(aligned=False, repair_scope="field", assessment_source="instructions",
            assessment_quote=context["lesson_package"]["private_workbook"]["activities"][0]["instructions"][:100])
    elif defect == "missing_section": data["public_sections"].pop()
    elif defect == "malformed": item["aligned"] = "true"
    focused = LLMResponse(data=data, finish_reason="length" if defect == "length" else "stop",
        error="anthropic request failed (TimeoutError; finish=missing)" if defect == "transport" else None)
    client = _split_critic_client(focused)
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context=context)
    assert failures and returned.error and review_response_quality(returned) == 0
    assert not (returned.effective_parameters or {}).get("validated_repair_targets")
    assert client.generate_json.await_count == record.await_count == 2
    assert any(call.kwargs["result_status"] == "review_unavailable" for call in record.await_args_list)


@pytest.mark.asyncio
async def test_positive_focused_alignment_preserves_full_review_calculations(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    lesson = _lesson()
    full = _response(lesson)
    # The wrapper receives the same canonical return contract from direct
    # approval and from a successful bounded numerical-evidence repair.
    full.data["contains_calculations"] = True
    full.data["calculations"] = [{"location": "Retained evidence", "expression": "2+2", "claimed_result": 4}]
    monkeypatch.setattr("app.services.planning.lesson_review._review_lesson_full",
                        AsyncMock(return_value=([], full, SimpleNamespace(model="full"))))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(
        data=_focused_review(lesson, {}), finish_reason="stop")))
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context={})
    assert not failures and not returned.error
    assert returned.data["calculations"][0]["expression"] == "2+2"
    assert returned.data["practice_minutes"] == 3
    assert len(returned.data["public_sections"]) == 6
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
async def test_successful_bounded_evidence_repair_still_runs_focused_critic(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    lesson = _lesson()
    # Outside References, whose citation digits are not numeric claims.
    lesson["lesson_content"] = lesson["lesson_content"].replace("\n## References", "\nSource label: 2026.\n\n## References")
    assert "Source label: 2026." in lesson["lesson_content"]
    initial = _response(lesson)
    repaired = _response(lesson, literal_fact_ids=["n1"])
    repair_client = SimpleNamespace(model="evidence-repair")
    repair = AsyncMock(return_value=([], repaired, repair_client))
    monkeypatch.setattr("app.services.planning.lesson_review._repair_packaged_evidence", repair)
    focused = LLMResponse(data=_focused_review(lesson, {}), finish_reason="stop")
    client = SimpleNamespace(model="full-and-critic", generate_json=AsyncMock(side_effect=[initial, focused]))
    failures, returned, reviewer = await review_lesson(lesson, client_factory=lambda **kw: client,
                                                      context={"lesson_package": {}})
    assert not failures and not returned.error and returned is repaired and reviewer is repair_client
    assert returned.data["literal_fact_ids"] == ["n1"]
    repair.assert_awaited_once()
    assert client.generate_json.await_count == 2
    assert [call.kwargs["operation"] for call in record.await_args_list] == [
        "lesson_review_evidence_repair", "lesson_review_public_accuracy"]
    assert record.await_args_list[-1].kwargs["response"] is focused


@pytest.mark.asyncio
@pytest.mark.parametrize("origin", ["section", "alignment"])
async def test_private_critic_reason_never_becomes_public_writer_feedback(monkeypatch, origin):
    from app.core.config import settings
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    captured = _conflict()
    lesson, context = captured["lesson"], captured["context"]
    full = _response(lesson)
    monkeypatch.setattr("app.services.planning.lesson_review._review_lesson_full",
                        AsyncMock(return_value=([], full, SimpleNamespace(model="full"))))
    data = _focused_review(lesson, context)
    public = next(a for a in data["public_sections"] if a["section_id"] == "core_framework")
    public.update(domain_valid=False, reason="PRIVATE_ASSESSMENT_KEY_MUST_NOT_REACH_WRITER")
    if origin == "alignment":
        data["practice_alignment"][0].update(aligned=False, public_rule_valid=False, repair_scope="public",
            reason="PRIVATE_MODEL_ANSWER_MUST_NOT_REACH_WRITER")
    focused = LLMResponse(data=data, finish_reason="stop")
    client = _split_critic_client(focused)
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client, context=context)
    assert failures and not returned.error and returned.data["affected_sections"] == ["core_framework"]
    assert "PRIVATE_" not in json.dumps(failures)
    assert "PRIVATE_" not in json.dumps(returned.data["issues"])
    assert "PRIVATE_ASSESSMENT_KEY" in json.dumps(returned.data["public_sections"])
    assert public["source_quote"] in " ".join(failures)



def test_alignment_projection_preserves_raw_case_facts_diagram_units_and_expression():
    from app.services.planning.lesson_review import _practice_alignment_payload, _public_teaching_payload
    context = {"lesson_package": {"private_workbook": {"activities": [{
        "id": "attendance", "instructions": "Choose the room with greater attendance.",
        "data": [{"id": "room_a", "label": "Room A", "value": 30},
                 {"id": "room_b", "label": "Room B", "value": 20}],
        "diagram": "Room A is west; Room B is east.", "worked_solution": "Choose Room A.",
        "fields": [{"id": "room", "label": "Which room?", "kind": "choice", "unit": "people",
                    "expression": None, "choices": [{"id": "a", "label": "Room A"},
                    {"id": "b", "label": "Room B"}], "correct_choice": "a", "criteria": []}]}]}}}
    first = _practice_alignment_payload(_lesson(), context)
    context["lesson_package"]["private_workbook"]["activities"][0]["data"][0]["value"] = 10
    second = _practice_alignment_payload(_lesson(), context)
    assert first != second
    assert first["practice_contracts"][0]["data"][0]["value"] == 30
    assert second["practice_contracts"][0]["data"][0]["value"] == 10
    assert second["practice_contracts"][0]["diagram"] == "Room A is west; Room B is east."
    assert second["practice_contracts"][0]["fields"][0]["unit"] == "people"
    assert "expression" in second["practice_contracts"][0]["fields"][0]
    assert set(_public_teaching_payload(_lesson(), context)) == {"sections", "teaching_cases"}
    assert "Choose Room A" not in json.dumps(_public_teaching_payload(_lesson(), context))


@pytest.mark.asyncio
async def test_public_and_alignment_critics_start_in_parallel_and_record_each_once(monkeypatch):
    import asyncio
    from app.core.config import settings
    from app.services.planning.lesson_review import AlignmentOnlyReview
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    captured = _conflict()
    lesson, context = captured["lesson"], captured["context"]
    full = _response(lesson)
    monkeypatch.setattr("app.services.planning.lesson_review._review_lesson_full",
                        AsyncMock(return_value=([], full, SimpleNamespace(model="full"))))
    data = _focused_review(lesson, context)
    started, gate, requests = [], asyncio.Event(), []
    async def generate(**kwargs):
        is_alignment = kwargs["output_model"] is AlignmentOnlyReview
        started.append(is_alignment)
        requests.append(json.loads(kwargs["user_prompt"]))
        if len(started) == 2:
            gate.set()
        await asyncio.wait_for(gate.wait(), timeout=1)
        key = "practice_alignment" if is_alignment else "public_sections"
        return LLMResponse(data={key: data[key]}, finish_reason="stop")
    options = []
    def factory(**kwargs):
        options.append(kwargs)
        return SimpleNamespace(generate_json=AsyncMock(side_effect=generate))
    failures, returned, _ = await review_lesson(lesson, client_factory=factory, context=context)
    assert not failures and not returned.error and sorted(started) == [False, True]
    assert options == [
        {"tier": "balanced", "timeout": 120, "max_tokens": 6000,
         "thinking_level": "high", "allow_fallback": False},
        {"tier": "balanced", "timeout": 90, "max_tokens": 4000,
         "thinking_level": "high", "allow_fallback": False},
    ]
    assert record.await_count == 2
    assert any(set(p) == {"sections", "teaching_cases"} for p in requests)
    assert any(set(p) == {"sections", "practice_contracts"} for p in requests)



def test_saved_live_alignment_rejection_validates_under_production_contract():
    from app.services.planning.lesson_review import AlignmentOnlyReview, _practice_alignment_payload, _practice_alignment_failures
    path = Path(__file__).parent / "fixtures" / "tutorial_teaching_quality.json"
    fixtures = json.loads(path.read_text())
    captured = fixtures["teaching_grading_conflict"]
    review = AlignmentOnlyReview.model_validate(fixtures["teaching_grading_alignment_review"])
    errors, public, private = _practice_alignment_failures(review,
        _practice_alignment_payload(captured["lesson"], captured["context"]))
    assert not errors and not public
    assert len(private) == 1 and private[0][0] == "practice.guided_pilot_check"
    assert "town" in private[0][1].lower() and "success" in private[0][1].lower()
    assert len(review.practice_alignment) == 2
    assert review.practice_alignment[1].aligned and review.practice_alignment[1].repair_scope == "none"


@pytest.mark.asyncio
async def test_captured_uncontested_fact_support_errors_repair_every_affected_section(monkeypatch):
    from app.core.config import settings
    from app.services.planning.lesson_review import _PUBLIC_ACCURACY_SYSTEM
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    lesson = _lesson()
    # Exact public excerpts from synthetic v35 capture 287f8ff4; no private data.
    captured_sections = {'core_framework': 'A topic is a noun phrase: it labels what the writing is about. "The library\'s Sunday hours" names a subject but asserts nothing. A claim takes a position someone could reasonably deny: "The library should stay open on Sundays." The test is denial, not truth or controversy. A fact nobody disputes, like "Libraries have books and computers," is still a claim, because someone could in principle reject it — it is just weakly supported. Controversy is not required; assertion is. Nor does a claim need the word "should." "Sunday opening helped weekday workers" asserts something and can be denied, so it counts. Evaluative and normative statements — "Equal access is fair" — are claims too, though they call for reasons rather than measurement. Why does the difference matter? Because your reader-summary goal fails without it: a reader can restate a claim, but a topic gives them nothing to restate except a subject area. When you draft, scan each sentence and ask: could a reasonable person say "I disagree" to this exact sentence? If the sentence only answers "what is this about," it belongs in your title or your background, not your thesis.\n```comparison\nTopic\n- Names a subject\n- Answers "what is this about"\n- No one can deny it\nvs\nClaim\n- Asserts a position\n- Answers "what do I contend"\n- A reasonable reader could reject it\n```', 'worked_example': 'Walk the notice-board statements with the denial test. The deciding phrase is underlined in each label.\n```steps\ntitle: Notice board, sorted by the denial test\nA: The library\'s Sunday hours | | A noun phrase. No verb asserting anything. No one can deny it.\nB: Should stay open on Sundays | | Full sentence: the library should stay open on Sundays because many residents work on weekdays. Someone could argue for closing. The position can be rejected, so this is a claim.\nC: Fines for overdue books | | Subject label only. Topic.\nD: Waive fines for under-twelves | | Full sentence: overdue fines should be waived for children under twelve. One could oppose the waiver. Claim.\n```\nNotice the pattern. B and D each contain a disputable position, marked by "should," and B adds a reason with "because." A and C never move past naming. Apply the same test to your own draft opening. "Sunday opening would help everyone" asserts something — someone could deny it — so it is already a claim, though an overbroad one. "Libraries have books and computers" is also a claim, yet it does nothing for your essay because no one would dispute it; it supports no position anyone contests. And "Many people work on weekdays" is a claim about the world, usable as evidence only if you connect it to Sunday demand.', 'failure_modes': 'Common mistake: calling a statement a topic because it is uncontroversial or merely factual. "Libraries have books and computers" is a factual claim — weak support, not a missing position. Correction: ask only whether the words assert something.'}
    for section, original in public_section_inventory(lesson).items():
        if section in captured_sections:
            lesson["lesson_content"] = lesson["lesson_content"].replace(original, captured_sections[section])
    quotes = {
        "core_framework": "it is just weakly supported",
        "worked_example": "it supports no position anyone contests",
        "failure_modes": "weak support, not a missing position",
    }
    full = _response(lesson)
    monkeypatch.setattr("app.services.planning.lesson_review._review_lesson_full",
        AsyncMock(return_value=([], full, SimpleNamespace(model="full"))))
    audits = _audits(lesson)
    # A canned semantic verdict verifies orchestration; live replay separately
    # checks whether the critic diagnoses the captured misconception itself.
    for audit in audits:
        if audit["section_id"] in quotes:
            audit.update(domain_valid=False, source_quote=quotes[audit["section_id"]],
                reason="An uncontested fact may be well supported and relevant to a disputed conclusion; lack of controversy establishes neither weak evidence nor uselessness.")
    focused = LLMResponse(data={"public_sections": audits}, finish_reason="stop")
    client = SimpleNamespace(model="critic", generate_json=AsyncMock(return_value=focused))
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client,
                                               context={"lesson_package": {}})
    assert not returned.error and returned.data["acceptable"] is False
    assert set(returned.data["affected_sections"]) == set(quotes)
    assert len(failures) == 3 and not returned.data["package_issues"]
    assert all(any(quote in failure for failure in failures) for quote in quotes.values())
    assert returned.data["public_sections"] == audits
    request = client.generate_json.await_args.kwargs
    assert request["system_prompt"] == _PUBLIC_ACCURACY_SYSTEM
    projected = json.loads(request["user_prompt"])
    assert set(projected) == {"sections", "teaching_cases"}
    assert all(projected["sections"][section] == text for section, text in captured_sections.items())
    assert "Classification, contestability, truth, evidential support and argumentative usefulness are distinct" in request["system_prompt"]
    assert "it can support a disputed conclusion through a relevant connection" in request["system_prompt"]
    assert "Judge support from supplied evidence and usefulness from that connection" in request["system_prompt"]
    assert "Being inadequate as a stand-alone thesis does not make a fact unusable as a supporting premise" in request["system_prompt"]
    assert "Reject blanket claims that a fact does nothing for an argument or supports no contested position solely because it is undisputed" in request["system_prompt"]
    client.generate_json.assert_awaited_once()
    record.assert_awaited_once()
    assert record.await_args.kwargs["result_status"] == "rejected"


@pytest.mark.asyncio
async def test_captured_correct_key_with_false_distractor_explanation_requires_check_repair(monkeypatch):
    from app.core.config import settings
    from app.services.planning.lesson_review import _PUBLIC_ACCURACY_SYSTEM
    monkeypatch.setattr(settings, "tutorial_focused_accuracy_review", True)
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    lesson = _lesson()
    # Exact public check from synthetic v36 capture 395131be. The selected
    # answer is sound; the Why sentence nevertheless teaches a false rule.
    captured_check = 'Apply the cue to one more board notice.\n\n```check\nQ: A fifth notice reads: "The library should add a second story-time session on Sunday mornings." Is this a topic or a claim?\n- [ ] Topic, because it mentions a library service\n- [x] Claim, because a reader could argue against adding the session\n- [ ] Topic, because it does not cite evidence\n- [ ] Claim, because every notice is a claim\nWhy: The deciding cue is a disputable position someone could reject, marked here by "should add". Mentioning a service would make it a topic, lacking evidence weakens support but does not remove the assertion, and not every notice asserts.\n```'
    original = public_section_inventory(lesson)["check_your_understanding"]
    lesson["lesson_content"] = lesson["lesson_content"].replace(original, captured_check)
    options = public_check_inventory(lesson)[0]["options"]
    assert len(options) == 4
    assert options[1]["selected"] and "Claim, because a reader could argue" in options[1]["text"]
    assert not options[0]["selected"] and "mentions a library service" in options[0]["text"]
    full = _response(lesson)
    expected_option_audits = copy.deepcopy(full.data["public_check_options"])
    monkeypatch.setattr("app.services.planning.lesson_review._review_lesson_full",
        AsyncMock(return_value=([], full, SimpleNamespace(model="full"))))
    audits = _audits(lesson)
    bad = next(a for a in audits if a["section_id"] == "check_your_understanding")
    bad.update(domain_valid=False, consistent_with_core=False,
        source_quote="Mentioning a service would make it a topic",
        reason="The keyed statement itself mentions a service while asserting a proposed action. A topic only names a subject; mention alone cannot erase this assertion.")
    focused = LLMResponse(data={"public_sections": audits}, finish_reason="stop")
    client = SimpleNamespace(model="critic", generate_json=AsyncMock(return_value=focused))
    # This canned rejection checks routing, not the real critic's semantics;
    # the live probe separately evaluates the exact captured explanation.
    failures, returned, _ = await review_lesson(lesson, client_factory=lambda **kw: client,
                                               context={"lesson_package": {}})
    assert not returned.error and returned.data["acceptable"] is False
    assert returned.data["affected_sections"] == ["check_your_understanding"]
    assert len(failures) == 1 and bad["source_quote"] in failures[0]
    assert not returned.data["package_issues"]
    assert returned.data["public_check_options"] == expected_option_audits
    request = client.generate_json.await_args.kwargs
    assert json.loads(request["user_prompt"])["sections"]["check_your_understanding"] == captured_check
    assert request["system_prompt"] == _PUBLIC_ACCURACY_SYSTEM
    assert "Mentioning a subject does not make an assertion a topic" in request["system_prompt"]
    assert "a topic only names a subject without asserting anything" in request["system_prompt"]
    assert "Audit every quick-check explanation of rejected options as well as the correct key" in request["system_prompt"]
    assert "An explanation endorsing a false distractor rule is a defect even when the key is correct" in request["system_prompt"]
    assert "never silently supply a missing qualifier or condition to make a false statement true" in request["system_prompt"]
    assert "must be explicit in the explanation, not added by your paraphrase" in request["system_prompt"]
    assert "quote and judge the flawed wording itself" in request["system_prompt"]
    client.generate_json.assert_awaited_once()
    record.assert_awaited_once()
    assert record.await_args.kwargs["result_status"] == "rejected"


@pytest.mark.asyncio
@pytest.mark.parametrize("alignment", [False, True])
async def test_focused_critic_truncation_is_unavailable_and_accounted_once(alignment, monkeypatch):
    from app.services.planning.lesson_review import _focused_accuracy_call

    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    # Even otherwise-valid JSON must not be approved after a truncated response.
    response = LLMResponse(data={}, finish_reason="length")
    client = SimpleNamespace(model="offline", generate_json=AsyncMock(return_value=response))
    options = []
    def factory(**kwargs):
        options.append(kwargs)
        return client

    returned, audit, defects, package_defects = await _focused_accuracy_call(
        client_factory=factory, payload={"sections": {}}, alignment=alignment)
    assert returned.error and audit is None and not defects and not package_defects
    client.generate_json.assert_awaited_once()
    record.assert_awaited_once()
    assert record.await_args.kwargs["result_status"] == "review_unavailable"
    assert record.await_args.kwargs["quality_score"] == 0.0
    assert options == [{"tier": "balanced", "timeout": 90 if alignment else 120,
                        "max_tokens": 4000 if alignment else 6000,
                        "thinking_level": "high", "allow_fallback": False}]


@pytest.mark.asyncio
async def test_focused_transient_transport_retries_once_and_accounts_each_call(monkeypatch):
    from app.services.planning.lesson_review import _focused_accuracy_call
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    lesson = _lesson()
    first = LLMResponse(data={}, error="timeout", error_code="generation_failed",
                        retryable=True, transport_success=False)
    second = LLMResponse(data={"public_sections": _audits(lesson)}, finish_reason="stop")
    client = SimpleNamespace(model="critic", generate_json=AsyncMock(side_effect=[first, second]))
    response, audit, defects, package_defects = await _focused_accuracy_call(
        client_factory=lambda **kwargs: client,
        payload={"sections": public_section_inventory(lesson), "teaching_cases": []},
        alignment=False)
    assert response is second and audit and not defects and not package_defects
    assert client.generate_json.await_count == record.await_count == 2
    assert [c.kwargs["response"] for c in record.await_args_list] == [first, second]
    assert [c.kwargs["result_status"] for c in record.await_args_list] == ["review_unavailable", "approved"]


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [
    LLMResponse(data={}, error="timeout", error_code="generation_failed", retryable=True, transport_success=False),
    LLMResponse(data={}, error="rate limit", error_code="generation_rate_limited", retryable=True, transport_success=False),
    LLMResponse(data={}, error="truncated", error_code="generation_failed", retryable=True, transport_success=False, finish_reason="length"),
    LLMResponse(data={}, error="bad json", error_code="generation_failed", retryable=None, transport_success=False),
])
async def test_focused_retries_are_bounded_and_other_errors_never_retry(failure, monkeypatch):
    from app.services.planning.lesson_review import _focused_accuracy_call
    record = AsyncMock()
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", record)
    client = SimpleNamespace(model="critic", generate_json=AsyncMock(return_value=failure.model_copy(deep=True)))
    response, audit, defects, package_defects = await _focused_accuracy_call(
        client_factory=lambda **kwargs: client, payload={"sections": {}}, alignment=False)
    count = 2 if failure.error == "timeout" else 1
    assert response.error and audit is None and not defects and not package_defects
    assert client.generate_json.await_count == record.await_count == count
    assert all(c.kwargs["result_status"] == "review_unavailable" for c in record.await_args_list)
