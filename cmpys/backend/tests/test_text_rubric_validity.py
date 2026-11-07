"""Recorded tutorial failures: restrictive policy rubric and altered source facts."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import SEMANTIC_TOKENS
from app.services.planning.package_preflight import (
    TextFieldAudit, _text_audit_issues, _semantic_model, _SEMANTIC_PROMPT,
    review_package, validate_preflight_state,
)
from tests.lesson_package_fixtures import package_payload


RECORDED = json.loads((Path(__file__).parent / 'fixtures' / 'text_rubric_validity.json').read_text())
MARKET_TARGET = 'practice.transfer_gap.diagnosis_and_link'
ALTERNATIVE = (
    'The fees can support feasibility: paying for tables and signs reduces a setup-cost '
    'objection to holding the market. Travel for vegetables suggests possible demand; '
    'concert crowds suggest foot traffic. None must be irrelevant. Linking setup fees '
    'to affordability supports the broad proposal without proving weekly demand.'
)


def package(activity_id='transfer_gap'):
    value = package_payload()
    value['teaching_cases'] = [{'id': 'public', 'assumptions': (
        'Original fictional notice: Garden helpers welcome. A revision names the cleanup '
        'and reply contact so the reader knows the action and response path.'
    ), 'data': [], 'results': []}]
    value['workbook']['activities'][0].update(minutes_min=1, minutes_max=2)
    value['workbook']['activities'][1] = copy.deepcopy(RECORDED[activity_id])
    return LessonPackage.model_validate(value)


def audits_for(value, *, restrict_market=False, invalid_model=False):
    """Explicit synthetic reviewer decisions, not a semantic grading shortcut."""
    audits = []
    for activity in value.workbook.activities:
        for field in activity.fields:
            if field.kind != 'text':
                continue
            market = activity.id == 'transfer_gap'
            garden = activity.id == 'transfer_warrant'
            audits.append(TextFieldAudit.model_validate({
                'target': 'practice.' + activity.id + '.' + field.id,
                'alternative_response': ALTERNATIVE if market else (
                    'The proposal addresses missed shifts for the three afternoon workers. '
                    'The group has five volunteers; morning availability of the remaining '
                    'two is unspecified. Their schedules may qualify the proposal without '
                    'inventing facts about plants or evaporation.' if garden else
                    'A bounded claim names its conditions, addresses an objection to the '
                    'supporting reason, and revises those conditions when the objection succeeds.'
                ),
                'criteria': [{
                    'criterion_index': index,
                    'required_by_task': not (market and restrict_market and index == 0),
                    'accepts_alternative': not (market and restrict_market and index == 0),
                    'reason': ('Feasibility evidence supports the actual broad proposal, despite not proving demand.'
                               if market and restrict_market and index == 0 else
                               'The alternative demonstrates the requested skill using the supplied facts.'),
                } for index in range(len(field.criteria))],
                'model_answer_valid': not (garden and invalid_model),
                'model_answer_reason': ('The passage counts five; evaporation claims are absent from supplied facts.'
                                       if garden and invalid_model else
                                       'The model preserves the task constraints and the supplied facts.'),
                'requires_activity_repair': market and restrict_market,
            }))
    return audits


def test_recorded_market_rubric_excludes_a_valid_feasibility_link():
    value = package()
    transfer = value.workbook.activities[1]
    assert 'should hold a weekly farmers market' in transfer.instructions
    assert 'fees could cover the cost' in transfer.instructions
    assert 'Names the irrelevant fact (stall fees)' in transfer.fields[0].criteria[0]
    assert 'one fact in the draft does not genuinely support' in transfer.instructions
    issues = _text_audit_issues(value, audits_for(value, restrict_market=True))
    assert [issue.target for issue in issues] == ['practice.transfer_gap']
    assert ALTERNATIVE in issues[0].description


def test_recorded_private_answer_must_preserve_source_counts_and_limits():
    value = package('transfer_warrant')
    transfer = value.workbook.activities[1]
    assert 'Three of our five' in transfer.instructions
    explanation = transfer.worked_solution.steps[0].explanation
    assert 'it counts only the three volunteers' in explanation and 'evaporation' in explanation
    issues = _text_audit_issues(value, audits_for(value, invalid_model=True))
    assert [issue.target for issue in issues] == ['practice.transfer_warrant.warrant_evaluation']
    assert 'passage counts five' in issues[0].description


@pytest.mark.parametrize('fault', ['missing_field', 'duplicate_field', 'unknown_field', 'missing_criterion', 'duplicate_criterion', 'unknown_criterion'])
def test_text_audit_requires_every_field_and_criterion_exactly_once(fault):
    value = package()
    audits = audits_for(value)
    if fault == 'missing_field': audits.pop()
    elif fault == 'duplicate_field': audits[1] = audits[0]
    elif fault == 'unknown_field': audits[1].target = 'practice.unknown.field'
    elif fault == 'missing_criterion': audits[1].criteria.pop()
    elif fault == 'duplicate_criterion': audits[1].criteria[-1] = audits[1].criteria[0]
    elif fault == 'unknown_criterion': audits[1].criteria[-1].criterion_index = 99
    with pytest.raises(ValueError, match='exactly once'):
        _text_audit_issues(value, audits)


@pytest.mark.asyncio
@pytest.mark.parametrize('mode', ['restricted', 'missing', 'duplicate', 'valid'])
async def test_positive_summary_never_overrides_failed_or_incomplete_text_audit(monkeypatch, mode):
    value = package()
    if mode == 'valid':
        # Supply a real valid rubric/task, rather than approving the known bad fixture.
        activity = value.workbook.activities[1]
        activity.instructions = activity.instructions.split('\n\nThis draft')[0] + (
            '\n\nUsing these facts, explain a defensible connection to the proposal. '
            'Distinguish demand from feasibility and note any remaining evidence gap.')
        activity.fields[0].criteria = [
            'Explains a defensible relevance judgment for the actual market proposal',
            'Distinguishes what the selected fact supports from what remains uncertain',
            'Writes an explicit link from that fact to the proposal',
            'Uses only the supplied facts',
            'Justifies the choice of which fact to connect',
        ]
        activity.worked_solution.steps[0].explanation = ALTERNATIVE
    audits = audits_for(value, restrict_market=mode == 'restricted')
    if mode == 'missing': audits = []
    if mode == 'duplicate': audits[1] = audits[0]
    verdict = {'acceptable': True, 'issues': [], 'text_audits': [audit.model_dump() for audit in audits],
        'teaching_case_audits': [{'target': 'teaching.public',
        'core_inference': 'A clearer invitation names action and response path.',
        'quantities_and_units': 'Qualitative action and contact; no quantitative comparison.',
        'decision_rule': 'Can the reader identify cleanup and reply contact?',
        'semantically_valid': True, 'reason': 'The revision supplies both elements missing from the invitation.'}]}
    expected_calls = 2 if mode in {'missing', 'duplicate'} else 1
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=copy.deepcopy(verdict)) for _ in range(expected_calls)]))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    snapshots = []

    async def save(state): snapshots.append(copy.deepcopy(state))

    outline = {'lesson_format': 'tutorial_v1'}
    failures, response, _ = await review_package(value, outline, {},
        client_factory=lambda **kwargs: client, on_review=save)
    assert client.generate_json.await_count == expected_calls
    assert response.effective_parameters['requested_output_tokens'] == SEMANTIC_TOKENS * expected_calls
    request = client.generate_json.await_args_list[0].kwargs
    assert set(json.loads(request['user_prompt'])['text_audit_inventory']) == {
        'practice.guided.argument', MARKET_TARGET}
    if mode == 'valid':
        assert not failures and not response.error and response.semantic_accepted
        saved = snapshots[-1]
        validate_preflight_state(saved, package=value, outline=outline, context={})
        saved['semantic']['text_audits'] = []
        with pytest.raises(ValueError, match='Text audit'):
            validate_preflight_state(saved, package=value, outline=outline, context={})
    elif mode == 'restricted':
        assert failures and not response.error and not response.semantic_accepted
        assert response.effective_parameters['validated_repair_targets'] == ['practice.transfer_gap']
    else:
        assert failures and response.error and not response.semantic_accepted


def test_text_audit_wire_schema_limits_targets_and_requires_concrete_alternative():
    schema = _semantic_model({'package', MARKET_TARGET}, set(), {MARKET_TARGET}).model_json_schema()
    field = schema['$defs']['TextFieldAudit']
    assert field['properties']['target']['enum'] == [MARKET_TARGET]
    assert field['properties']['alternative_response']['minLength'] == 24
    assert field['properties']['alternative_response']['maxLength'] == 500
    assert schema['$defs']['TextCriterionAudit']['properties']['criterion_index']['maximum'] == 4
    assert 'Criteria are grading keys' in _SEMANTIC_PROMPT
    assert 'different sound justification of the same answer is enough' in _SEMANTIC_PROMPT
    assert 'nondecisive evidence can still be relevant' in _SEMANTIC_PROMPT

