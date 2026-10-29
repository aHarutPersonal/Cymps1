"""Review failures remain strict, diagnosable, and accurately measured."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.telemetry import usage_record_from_response
from app.services.planning.lesson_review import review_lesson, review_response_quality


def _review(**changes):
    return {
        "acceptable": True,
        "issues": [],
        "advisories": ["Optional external clock; no app timer is required."],
        "practice_minutes": 46,
        "contains_calculations": False,
        "calculations": [],
        **changes,
    }


@pytest.mark.asyncio
async def test_final_review_and_scoped_repair_receive_full_lesson_metadata_hints(monkeypatch):
    from app.services.llm.client import LLMResponse
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    lesson = {"lesson_content": (
        'Complete the approved practice phase "Find the Missing Link" (1-2 minutes): read the excerpt. '
        'Then complete the approved transfer phase "Build Your Chain" (2-3 minutes): submit your chain.')}
    before = copy.deepcopy(lesson)
    initial = LLMResponse(data=_review(literal_fact_ids=["n1"]))
    repair = LLMResponse(data={"literal_fact_ids": ["n2"]})
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[initial, repair]))
    failures, result, _ = await review_lesson(lesson, client_factory=lambda **kw: client,
                                             context={"lesson_package": {}})
    assert not failures and not result.error
    first, second = client.generate_json.await_args_list
    body = json.loads(first.kwargs["user_prompt"])
    assert body["context"]["metadata_candidate_ids"] == ["n1", "n2"]
    patch = json.loads(second.kwargs["user_prompt"])
    assert patch["metadata_candidate_ids"] == ["n2"]
    assert set(patch["numeric_spans"]) == {"n2"}
    assert set(result.data["literal_fact_ids"]) == {"n1", "n2"}
    assert lesson == before


@pytest.mark.asyncio
async def test_metadata_hints_do_not_override_negative_semantic_review():
    lesson = {"lesson_content": 'Complete the approved practice phase "Write a novel" (1-2 minutes): write it.'}
    response = SimpleNamespace(error=None, data=_review(acceptable=False,
        issues=["The requested activity cannot realistically fit its time budget."], literal_fact_ids=["n1"]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, _, _ = await review_lesson(lesson, client_factory=lambda **kw: client,
                                        context={"lesson_package": {}})
    assert failures == response.data["issues"]
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize("payload,expected", [
    ({"answer": "PRIVATE_LESSON_TEXT"}, "acceptable: missing"),
    (_review(advisories="PRIVATE_LESSON_TEXT"), "advisories: list_type"),
    (_review(calculations=[{"location": "PRIVATE_LESSON_TEXT"}]), "calculations.0.expression: missing"),
    (_review(PRIVATE_LESSON_TEXT="PRIVATE_LESSON_TEXT"), "<unknown_field>: extra_forbidden"),
    (None, "review: model_type"),
])
async def test_schema_failure_has_safe_persistable_diagnostics(payload, expected, caplog):
    response = SimpleNamespace(error=None, data=payload)
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "PRIVATE_LESSON_TEXT"},
        client_factory=lambda **kwargs: client, context={},
    )
    assert returned is response
    assert failures == [response.error]
    assert expected in response.error
    assert "PRIVATE_LESSON_TEXT" not in response.error + caplog.text
    usage = usage_record_from_response(operation="plan_item_detail_generation", response=response)
    assert not usage.success
    assert usage.metadata["error"] == response.error
    assert review_response_quality(response) == 0.0
    assert client.generate_json.await_count == 2


@pytest.mark.parametrize("payload,score", [
    (_review(), 1.0),
    (_review(acceptable=False), 0.0),
    (_review(issues=["The required answer key is missing."]), 0.0),
    (_review(contains_calculations=True), 0.0),
    (_review(contains_calculations=True, calculations=[{
        "location": "case answer", "expression": "4 + 2", "claimed_result": 7,
    }]), 0.0),
    (_review(calculations=[{
        "location": "case answer", "expression": "4 + 2", "claimed_result": 6,
    }]), 1.0),
    ({"answer": "not a valid review"}, 0.0),
])
def test_review_telemetry_scores_contract_instead_of_lesson_word_count(payload, score):
    assert review_response_quality(SimpleNamespace(data=payload, error=None)) == score


@pytest.mark.asyncio
async def test_valid_review_retains_approval_and_advisories():
    response = SimpleNamespace(error=None, data=_review())
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(
        {"lesson_content": "Useful teaching content"},
        client_factory=lambda **kwargs: client, context={},
    )
    assert not failures
    assert returned.error is None
    assert returned.data["advisories"]
    assert review_response_quality(returned) == 1.0


@pytest.mark.asyncio
async def test_invalid_review_retried_without_rewriting_lesson():
    invalid = SimpleNamespace(error=None, data=_review(calculations=[{
        "location": "example", "source_quote": "Example: 2+2 equals 4.", "expression": "2+2", "claimed_result": 4,
        "absolute_tolerance": 1,
    }]))
    valid = SimpleNamespace(error=None, data=_review(calculations=[{
        "location": "example", "source_quote": "Example: 2+2 equals 4.", "expression": "2+2", "claimed_result": 4,
        "absolute_tolerance": 0.01,
    }]))
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[invalid, valid]))
    failures, response, _ = await review_lesson(
        {"lesson_content": "Example: 2+2 equals 4."}, client_factory=lambda **kw: client, context={})
    assert not failures and response is valid
    first, second = client.generate_json.await_args_list
    assert first.kwargs["user_prompt"] == second.kwargs["user_prompt"]
    assert "less_than_equal" in second.kwargs["system_prompt"]


@pytest.mark.asyncio
async def test_negative_content_review_is_not_retried_for_approval():
    negative = SimpleNamespace(error=None, data=_review(acceptable=False, issues=["Incorrect calculation"]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=negative))
    failures, _, _ = await review_lesson(
        {"lesson_content": "Wrong example"}, client_factory=lambda **kw: client, context={})
    assert failures == ["Incorrect calculation"]
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
async def test_review_timeout_retries_identical_draft_without_content_changes(monkeypatch):
    from app.services.llm.client import LLMResponse
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    timeout = LLMResponse(data={}, error="zai request failed (TimeoutError; finish=missing)")
    valid = LLMResponse(data=_review())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[timeout, valid]))
    failures, response, _ = await review_lesson(
        {"lesson_content": "Useful teaching content"}, client_factory=lambda **kw: client, context={})
    assert not failures and response is valid
    first, second = client.generate_json.await_args_list
    assert first.kwargs == second.kwargs


@pytest.mark.asyncio
async def test_review_rate_limit_does_not_trigger_transport_retries():
    from app.services.llm.client import LLMResponse
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(
        data={}, error="zai request failed (RateLimitError; finish=missing)")))
    failures, _, _ = await review_lesson(
        {"lesson_content": "Useful teaching content"}, client_factory=lambda **kw: client, context={})
    assert failures
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize('expression,claimed,source,approved', [
    ('(60-40)/60*100', 33.3, 'Margin of safety: 33.3%.', True),
    ('(20.5333-15)/20.5333*100', 26.97, 'Discount: 26.97%.', False),
    ('(20.5333-15)/20.5333*100', 26.95, 'Discount: 26.95%.', True),
    ('10*(1540000/750000)', 20.5, 'Value is $20.5.', True),
    ('10*(1540000/750000)', 20.5, 'Value is $20.50.', False),
    ('10*(1540000/750000)', 20.5, 'Value 20.5; table value 20.50.', False),
    ('(24-20.50)/20.50*100', 17, 'Premium: 17%.', True),
    ('100/3', 33.3, 'No numeric result was supplied.', False),
    ('4+2', 7, 'Result: 7.', False),
    ('-100/3', -33.3, 'Result: -33.3.', True),
    ('5.35/2', 2.68, 'Result: 2.68.', True),
    ('10000/3', 3333.3, 'Result: 3,333.3.', True),
])
async def test_review_uses_actual_displayed_precision(expression, claimed, source, approved):
    from app.services.llm.client import LLMResponse
    response = LLMResponse(data=_review(contains_calculations=True, calculations=[{
        'location': 'worked example', 'source_quote': source, 'case_id': 'teaching.rounding', 'expression': expression, 'claimed_result': claimed,
        'absolute_tolerance': 0.01, 'claimed_literal': '0',
    }]))
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    import ast
    inputs = [abs(float(n.value)) for n in ast.walk(ast.parse(expression, mode="eval"))
              if isinstance(n, ast.Constant) and isinstance(n.value, (int, float))]
    failures, returned, _ = await review_lesson(
        {'lesson_content': source}, client_factory=lambda **kw: client,
        context={"lesson_package": {"teaching_cases": [{"id": "rounding", "data": [
            {"value": value} for value in inputs]}]}})
    assert (not failures) == approved
    assert review_response_quality(returned) == float(approved)
    # A reviewer formula/precision mismatch is not independently source-owned
    # arithmetic. It receives one bounded proof correction and remains blocked
    # if that correction is invalid; no paid prose rewrite is triggered.
    assert client.generate_json.await_count == (1 if approved else 2)


@pytest.mark.asyncio
async def test_malformed_review_json_recovers_once_without_changing_lesson(monkeypatch):
    from app.services.llm.client import LLMResponse
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data={}, error="zai request failed (JSONDecodeError; finish=stop)"),
        LLMResponse(data=_review(acceptable=False, issues=["Wrong private answer key"])),
    ]))
    failures, _, _ = await review_lesson(
        {"lesson_content": "Useful teaching content"}, client_factory=lambda **kw: client, context={})
    assert failures == ["Wrong private answer key"]
    first, second = client.generate_json.await_args_list
    assert first.kwargs["user_prompt"] == second.kwargs["user_prompt"]
    assert "previous response was invalid JSON" in second.kwargs["system_prompt"]


@pytest.mark.asyncio
@pytest.mark.parametrize("repair_evidence", [True, False])
async def test_unverifiable_approval_repairs_review_not_lesson(monkeypatch, repair_evidence):
    from app.services.llm.client import LLMResponse
    from app.services.planning.lesson_review import PackagedCalculationCheck
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    source = "Interest coverage is 3.5."
    def reviewed(quote):
        return LLMResponse(data=_review(contains_calculations=True, calculations=[{
            "location": "coverage", "source_quote": quote, "claim_ids": ["n1"],
            "case_id": "teaching.company", "expression": "14/4", "claimed_result": 3.5,
        }]))
    invalid = "Interest coverage was 3.5."
    corrected = {"calculations": [{"claim_ids": ["n1"], "case_id": "teaching.company",
                                   "expression": "14/4", "claimed_result": 3.5 if repair_evidence else 999}]}
    initial_response = reviewed(invalid)
    original_data = copy.deepcopy(initial_response.data)
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        initial_response, LLMResponse(data=corrected),
    ]))
    failures, response, _ = await review_lesson(
        {"lesson_content": source}, client_factory=lambda **kw: client,
        context={"lesson_package": {"teaching_cases": [{"id": "company", "data": [{"value": 14}, {"value": 4}]}]}},
    )
    assert bool(failures) != repair_evidence
    assert bool(response.error) != repair_evidence
    first, second = client.generate_json.await_args_list
    assert "PRIOR REVIEW TO CORRECT" not in second.kwargs["user_prompt"]
    first_payload = json.loads(first.kwargs["user_prompt"])
    patch_payload = json.loads(second.kwargs["user_prompt"])
    assert first_payload["lesson"]["lesson_content"] == source
    assert first_payload["numeric_spans"] == patch_payload["numeric_spans"] == {"n1": source}
    assert patch_payload["verification_defects"] == [
        "coverage: calculation is not bound to an exact source span"]
    expected_copy = {"claim_ids": ["n1"], "case_id": "teaching.company",
                     "expression": "14/4", "claimed_result": 3.5}
    assert patch_payload["prior_evidence"]["calculations"] == [expected_copy]
    assert PackagedCalculationCheck.model_validate(expected_copy)
    assert second.kwargs["output_model"].model_json_schema()["$defs"]["SourceClaimId"]["enum"] == ["n1"]
    # The invalid quote stays on its original review, not in the compact wire
    # template. The exact source and complete binding defect remain available.
    assert invalid not in second.kwargs["user_prompt"]
    assert initial_response.data == original_data
    assert response.data["calculations"][0]["claimed_result"] == (3.5 if repair_evidence else 999)
    if not repair_evidence:
        assert any("not 999" in error for error in failures)
    assert client.generate_json.await_count == 2
    assert "SAME unchanged lesson" in second.kwargs["system_prompt"]


@pytest.mark.asyncio
async def test_incorrect_calculation_does_not_retry_review_for_approval(monkeypatch):
    from app.services.llm.client import LLMResponse
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=_review(
        contains_calculations=True, calculations=[{
            "location": "example", "source_quote": "4 plus 5 equals 999.",
            "expression": "4+5", "claimed_result": 999, "input_quote": "4 plus 5 equals 999.",
        }]))))
    failures, _, _ = await review_lesson(
        {"lesson_content": "4 plus 5 equals 999."}, client_factory=lambda **kw: client, context={})
    assert failures
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize("corrected", [True, False])
async def test_workload_inconsistency_rechecks_same_artifact_once(monkeypatch, corrected):
    from app.services.llm.client import LLMResponse
    monkeypatch.setattr("app.services.llm.telemetry.record_llm_response", AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=_review(practice_minutes=100)),
        LLMResponse(data={"practice_minutes": 40 if corrected else 100}),
    ]))
    failures, response, _ = await review_lesson(
        {"lesson_content":"Useful teaching content"}, client_factory=lambda **kw:client,
        context={"lesson_package":{"private_workbook":{"activities":[{"minutes_min":30,"minutes_max":60}]}}})
    assert bool(failures) != corrected
    assert bool(response.error) != corrected
    first,second = client.generate_json.await_args_list
    assert "lesson_for_workload_audit" in second.kwargs["user_prompt"]
    assert "Do not force a " in second.kwargs["system_prompt"]


@pytest.mark.parametrize("text", [
    "Reflect on your 1000-word draft.",
    "Write a 600‑word scene.",
    "Revise a 250–400-word draft.",
    "She made the desk at 4:58 but missed the recital.",
    "Deliver the package before 5:00.",
    "At 11:40 the only person who could approve was absent.",
    "The time pressure (11:40 against midnight) tightens it.",
    "After each 60-minute writing session, name what changed.",
    "PASS ONE (self-time about 8 minutes): draft roughly 600 words.",
    '\"Question 1 (goal?): I guessed she wants to fix her mistake.',
    "The reader answered no to question 4, so revise the ending.",
    "PASS 1 — Write the opening half of your scene.",
    "A strong Pass 1 establishes goal and obstacle in action.",
    "Pass 1 planned a confession, but Pass 2 makes silence the choice.",
    "Mira wants to hand in her essay before the 5 p.m. deadline.",
    "She arrived at 12:30 PM before sunset.",
])
def test_hyphenated_writing_quotas_are_covered_workload_metadata(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    spans = numeric_spans(lesson, {})
    assert spans
    review = LessonReview.model_validate(_review(literal_fact_ids=list(spans)))
    assert not grounded_failures(review, lesson, {})
    review.literal_fact_ids = []
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "The replacement cost is 600-dollars.",
    "A machine takes 30-minutes to produce output.",
    "Write 600 words and earn 1000 dollars.",
    "A 600-word draft plus a 400-word draft equals 900 words.",
    "Mix at a ratio of 4:58.",
    "The ratio at 4:58 is correct.",
    "At 11:40 the total is 900 dollars.",
    "At 25:70 she arrived.",
    "She arrived at 13 p.m.",
    "She arrived before 5 p.m. and earned 700 dollars.",
    "Question 4 has an unsupported result of 900 dollars.",
    "Pass 2 + 3 = 9.",
    "Use a phase 2.5 ratio.",
    "The section 20% result is correct.",
])
def test_workload_metadata_does_not_exempt_facts_or_bad_arithmetic(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    review = LessonReview.model_validate(_review(literal_fact_ids=list(numeric_spans(lesson, {}))))
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("quote", [("'", "'"), ('"', '"'), ("‘", "’"), ("“", "”")])
def test_quoted_model_response_list_requires_explicit_review_coverage(quote):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    text = "Model response: " + quote[0] + "1) Ending by coincidence removes the choice. 2) Revision restores a costly choice." + quote[1]
    lesson = {"lesson_content": text}
    spans = numeric_spans(lesson, {})
    assert spans
    review = LessonReview.model_validate(_review(literal_fact_ids=list(spans)))
    assert not grounded_failures(review, lesson, {})
    review.literal_fact_ids = []
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "Model response: '1) Ending changes the story.'",
    "Model response: '1) Ending changes the story. 3) Revision restores a choice.'",
    "Model response: '1) Ending changes the story. (2) Revision restores a choice.'",
    "Model response: '1) dollars are required. 2) euros are missing.'",
    "Model response: '1) Ending costs 900 dollars. 2) Revision restores a choice.'",
    "Model response: '1) The total is 2 + 3 = 9. 2) Revision restores a choice.'",
    "A witness said: '1) Ending changes the story. 2) Revision restores a choice.'",
    "Model response: '1) Ending changes the story. 2) Revision restores a choice.",
])
def test_quoted_model_response_does_not_exempt_unproven_numbers(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    review = LessonReview.model_validate(_review(literal_fact_ids=list(numeric_spans(lesson, {}))))
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "Can the reader identify (1) Maya's goal, (2) the obstacle and its cost, (3) the choice, (4) the change?",
    "Name (1) the goal, (2) the obstacle and (3) the consequence.",
    "Explain 1) the goal; 2) the choice; 3) the change.",
])
def test_explicit_inline_lists_require_reviewer_coverage(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    assert ids
    review = LessonReview.model_validate(_review(literal_fact_ids=ids))
    assert not grounded_failures(review, lesson, {})
    review.literal_fact_ids = []
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "Identify (1) dollars, (2) euros.",
    "Identify (1) the charge of 900 dollars, (2) the missing amount.",
    "Identify (1) the result 2 + 3 = 9, (2) the reason.",
    "Identify (1) the goal, (3) the change.",
    "Identify (1) the goal, 2) the change.",
    "Identify (1) the goal.",
    "Identify (1) percent, (2) percentage points.",
])
def test_inline_list_markers_do_not_hide_quantities_or_ambiguity(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    review = LessonReview.model_validate(_review(literal_fact_ids=list(numeric_spans(lesson, {}))))
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "SCENE DRAFT — 'Dev, 3 a.m.' (original prose)",
    "The title reads 11:45 PM.",
    "Checklist to send: '1) What does the character want? 2) What blocks them? 3) What do they choose? 4) What changes?'",
    "Reader questions: '1) What is the goal? 2) What changes?'",
])
def test_unambiguous_clock_labels_and_reader_lists_need_review_coverage(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    assert ids
    review = LessonReview.model_validate(_review(literal_fact_ids=ids))
    assert not grounded_failures(review, lesson, {})
    review.literal_fact_ids = []
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "The time is 13 a.m.", "The time is -3 a.m.", "The time is 1.3 a.m.",
    "The time is 3:75 a.m.", "The ratio is 3 a.m.",
    "The calculation is 3 a.m. + 4 a.m. = 9 a.m.",
    "Checklist to send: '1) The total is 900 dollars. 2) What changes?'",
    "Checklist to send: '1) The goal. 3) The change.'",
])
def test_clock_and_checklist_metadata_keep_quantitative_failures(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    review = LessonReview.model_validate(_review(literal_fact_ids=list(numeric_spans(lesson, {}))))
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "The station screen said 7:42.",
    "The example uses *screen says 7:42* as a specific time clue.",
    "The watch shows 00:05 while the clock reads 23:59.",
    "Submit three parts: (1) your vague sentence, (2) your revised sentence, and (3) a short note.",
    "The details changed are (1) the fogged window - and (2) the scraping chair.",
    "The details were (1) the fogged window, (2) the scraping chair, or (3) the open door.",
])
def test_displayed_clock_and_complete_copular_lists_need_independent_coverage(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    assert ids
    review = LessonReview.model_validate(_review(literal_fact_ids=ids))
    assert not grounded_failures(review, lesson, {})
    review.literal_fact_ids = []
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "The screen said 27:42.",
    "The screen says 7:62.",
    "The screen says -7:42.",
    "The screen says 1.7:42.",
    "The screen says 7:42:15.",
    "The screen says 7:42 as the ratio.",
    "The scores on the screen said 7:42.",
    "The scoreboard display shows 7:42.",
    "The screen said 7:42 and the total is 900 dollars.",
    "The screen says 7:42 + 2 = 9.",
    "The example uses *screen says 7:42* + 2 = 9.",
    "The example uses *screen says 7:42 * 3.",
    "The example uses screen says 7:42* as a calculation.",
    "The quantities are (1) cm and (2) cm.",
    "The quantities are (1) million dollars and (2) million dollars.",
    "The quantities are (1) a cm and (2) a cm.",
    "The quantities are (1) a 20-dollar fee and (2) a 30-dollar fee.",
    "The formulas are (1) x + 2 and (2) y + 3.",
    "The values are (1) the total 2 + 3 = 9 and (2) the explanation.",
    "The parts are (1) the claim and (3) the reason.",
    "The parts are (1) the claim and 2) the reason.",
    "The parts are (1) the claim.",
    "Submit three parts: (1) the total 900 dollars, (2) the claim, and (3) the reason.",
])
def test_displayed_clock_and_copular_lists_do_not_hide_quantities_or_ambiguity(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    assert ids
    review = LessonReview.model_validate(_review(literal_fact_ids=ids))
    assert grounded_failures(review, lesson, {})


def test_copular_list_metadata_never_joins_source_fields_or_masks_equal_quoted_occurrences():
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": "The details are (1) the opening.", "substeps": ["And (2) the ending."]}
    ids = list(numeric_spans(lesson, {}))
    review = LessonReview.model_validate(_review(literal_fact_ids=ids))
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("opening,closing", [
    ("'", "'"), ('"', '"'), ("‘", "’"), ("“", "”"), ("«", "»"),
    ("`", "`"), ("```\n", "\n```"), ("~~~\n", "\n~~~"),
    ("'", ""), ('"', ""), ("‘", ""), ("“", ""), ("`", ""), ("```\n", ""),
])
def test_arbitrary_quoted_or_code_copular_lists_keep_original_source_ownership(opening, closing):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    text = f"A witness said: {opening}The details are (1) the opening and (2) the ending.{closing}"
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    assert ids
    review = LessonReview.model_validate(_review(literal_fact_ids=ids))
    assert grounded_failures(review, lesson, {})


def test_copular_list_after_complete_quote_owns_only_its_unquoted_occurrence():
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    text = "A witness said 'unclear'. The details are (1) the opening and (2) a specific ending."
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    review = LessonReview.model_validate(_review(literal_fact_ids=ids))
    assert not grounded_failures(review, lesson, {})
    lesson = {"lesson_content": "The changes are (1) the opening and (2) the ending.\n"
                                "A witness quoted '(1) the opening and (2) the ending.'"}
    ids = list(numeric_spans(lesson, {}))
    review = LessonReview.model_validate(_review(literal_fact_ids=ids))
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "Rewrite this as a brief exchange or single line of dialogue (2–4 lines of speech, plus minimal beats) that lets the reader infer both motives without stating either directly.",
    "Write 2–4 lines of speech.",
    "Draft a dialogue (2-4 lines of dialogue).",
])
def test_reviewed_dialogue_line_quota_is_workload_not_missing_case_data(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    ids = list(numeric_spans(lesson, {}))
    assert ids
    review = LessonReview.model_validate(_review(literal_fact_ids=ids))
    assert grounded_failures(review, lesson, {}) == []
    review.literal_fact_ids = []
    assert grounded_failures(review, lesson, {})


@pytest.mark.parametrize("text", [
    "The scene contains 2–4 lines of speech.",
    "Explain why the scene has 2–4 lines of speech.",
    "Write why the poem has dialogue (2–4 lines of speech).",
    'The prompt says "Write 2–4 lines of speech."',
    "Write 4–2 lines of speech.",
    "Write 21 lines of speech.",
    "Write 2.4 lines of speech.",
    "Write -2 lines of speech.",
    "Write 2–4 lines of speech plus 3 = 9.",
    "Write 2–4 lines of speech and earn 900 dollars.",
    "Write 2–4 lines of speechwriters' notes.",
])
def test_dialogue_quota_never_hides_reported_counts_or_other_quantities(text):
    from app.services.planning.lesson_review import LessonReview, grounded_failures, numeric_spans
    lesson = {"lesson_content": text}
    review = LessonReview.model_validate(_review(literal_fact_ids=list(numeric_spans(lesson, {}))))
    assert grounded_failures(review, lesson, {})


@pytest.mark.asyncio
@pytest.mark.parametrize('lesson_format,content,expected', [
    ('tutorial_v1', 'Explain a motive through visible action.', 4000),
    (None, 'Explain a motive through visible action.', 8000),
    ('tutorial_v1', ' '.join(f'Observed value: {i}.' for i in range(1, 16)), 8000),
])
async def test_review_budget_scales_without_dropping_checks(lesson_format, content, expected):
    from app.services.llm.client import LLMResponse
    requests = []
    response = LLMResponse(data=_review(practice_minutes=3), finish_reason='stop')
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    def factory(**kwargs):
        requests.append(kwargs)
        return client
    await review_lesson({'lesson_content': content, 'lesson_format': lesson_format}, client_factory=factory, context={})
    assert requests[0]['max_tokens'] == expected
    assert requests[0]['allow_fallback'] is False
    prompt = client.generate_json.await_args_list[0].kwargs['system_prompt']
    assert 'leaked transfer answers' in prompt and 'private solutions' in prompt


@pytest.mark.asyncio
async def test_truncated_review_cannot_approve_even_valid_looking_json():
    from app.services.llm.client import LLMResponse
    response = LLMResponse(data=_review(practice_minutes=3), finish_reason='length')
    client = SimpleNamespace(generate_json=AsyncMock(return_value=response))
    failures, returned, _ = await review_lesson(
        {'lesson_content': 'Explain a motive through action.', 'lesson_format': 'tutorial_v1'},
        client_factory=lambda **kwargs: client, context={})
    assert failures and 'incomplete' in returned.error
    client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
async def test_final_review_prompt_knows_multi_select_answers_are_supported():
    from app.services.llm.client import LLMResponse
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=_review(), finish_reason='stop')))
    await review_lesson({'lesson_content': 'A complete explanation.'}, client_factory=lambda **kw: client, context={})
    prompt = " ".join(client.generate_json.await_args_list[0].kwargs['system_prompt'].split())
    assert "number, single-choice, multi-select and free-text answers" in prompt


def test_lesson_writer_contract_lists_every_supported_field_kind():
    from app.services.planning.lesson_writer import _COMMON_CONTRACT
    assert "numeric/choice/multi_choice/text fields" in " ".join(_COMMON_CONTRACT.split())
