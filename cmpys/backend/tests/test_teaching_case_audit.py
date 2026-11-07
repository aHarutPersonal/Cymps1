"""An accepted public worked example compared attendance directly with money."""
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
    TeachingCaseAudit, _teaching_case_audit_issues, review_package, validate_preflight_state,
)


RECORDED = json.loads((Path(__file__).parent / 'fixtures' / 'teaching_case_unit_mismatch.json').read_text())
TARGET = 'teaching.sunday_pilot_check'
CORRECTED_ASSUMPTIONS = (
    'Original fictional example. The town council proposes a Sunday-opening pilot at the main library. '
    'Its policy defines two independent continuation conditions before the trial: average Sunday '
    'attendance must meet a stated attendance threshold, and added staffing spending must stay '
    'within a stated budget ceiling. Visits are counted as visits; spending is recorded in currency. '
    'Worked analysis: the council is the deciding actor and the pilot is its action. The success '
    'rule is checkable because each observable is compared with a threshold in the same unit. '
    'Both conditions must hold to continue. Attendance alone does not cover or recover spending; '
    'no admission revenue or monetary value per visit has been supplied.'
)


def package(corrected=False, *, isolate_teaching=False):
    raw = copy.deepcopy(RECORDED['package'])
    if isolate_teaching:
        # The historical capture predates the tutorial pairing rule. Keep its public
        # case exact while using one response to isolate the separate inference audit.
        guided = raw['workbook']['activities'][0]
        guided['fields'] = guided['fields'][1:]
        guided['instructions'] = guided['instructions'].replace(
            'First, pick the criterion this clinic draft meets least. Then, for the criterion you picked, name the specific missing element in the draft and write one sentence that would supply it.',
            'In one response, name the weakest criterion, identify its specific missing element, and write one sentence that would supply it.'
        )
        guided['fields'][0]['label'] = 'Name the weakest criterion, its missing element, and a concrete correction'
        guided['worked_solution'] = (
            'The weakest criterion is what exactly to do: take action provides no concrete step. '
            'A valid correction is for the county health office to open another morning intake window. '
            'The actor and success measure already pass, so the response should justify the action diagnosis.'
        )
    if corrected:
        raw['teaching_cases'][0]['assumptions'] = CORRECTED_ASSUMPTIONS
    return LessonPackage.model_validate(raw)


def teaching_audit(corrected=False):
    return {
        'target': TARGET,
        'core_inference': ('Continue only when attendance and spending each meet their own policy limits.'
                           if corrected else 'Average visit counts supposedly cover added staffing spending.'),
        'quantities_and_units': 'Attendance: visits per Sunday; added staffing cost: currency over the pilot.',
        'decision_rule': ('Compare attendance with an attendance threshold and cost with a budget ceiling.'
                          if corrected else 'Compare attendance directly with cost without any monetary conversion.'),
        'semantically_valid': corrected,
        'reason': ('Each quantity has a same-unit threshold; both conditions must hold.' if corrected else
                   'Visits cannot cover currency without a supplied value-per-visit or revenue conversion.'),
    }


def verdict(corrected=False):
    result = copy.deepcopy(RECORDED['recorded_verdict'])
    # The review fixture consolidates the old mixed pair into its existing text response.
    result.pop('choice_audits', None)
    result['teaching_case_audits'] = [teaching_audit(corrected)]
    return result


def test_recorded_approval_missed_a_public_case_with_incompatible_units():
    value = package()
    assert RECORDED['recorded_verdict']['acceptable'] is True
    assert 'average Sunday visits cover the added staffing cost' in value.teaching_cases[0].assumptions
    assert value.teaching_cases[0].data == value.teaching_cases[0].results == []
    issues = _teaching_case_audit_issues(value, [TeachingCaseAudit.model_validate(teaching_audit())])
    assert [issue.target for issue in issues] == [TARGET]
    assert 'Visits cannot cover currency' in issues[0].description


@pytest.mark.parametrize('fault', ['missing', 'duplicate', 'unknown'])
def test_teaching_audit_requires_exact_case_coverage(fault):
    audits = [TeachingCaseAudit.model_validate(teaching_audit(True))]
    if fault == 'missing': audits = []
    elif fault == 'duplicate': audits.append(audits[0])
    else: audits[0].target = 'teaching.unrelated'
    with pytest.raises(ValueError):
        _teaching_case_audit_issues(package(True), audits)


async def run_review(monkeypatch, value, response_data, *, outline=None):
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=copy.deepcopy(response_data)), LLMResponse(data=copy.deepcopy(response_data)),
    ]))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    snapshots = []

    async def save(state): snapshots.append(copy.deepcopy(state))

    result = await review_package(value, {'lesson_format': 'tutorial_v1'} if outline is None else outline, {},
        client_factory=lambda **kwargs: client, on_review=save)
    return result, client, snapshots


@pytest.mark.asyncio
@pytest.mark.parametrize('corrected', [False, True])
async def test_positive_summary_cannot_override_bad_teaching_inference(monkeypatch, corrected):
    value = package(corrected, isolate_teaching=True)
    (failures, response, _), client, snapshots = await run_review(monkeypatch, value, verdict(corrected))
    assert not response.error
    assert client.generate_json.await_count == 1
    assert response.effective_parameters['requested_output_tokens'] == SEMANTIC_TOKENS
    if corrected:
        assert not failures and response.semantic_accepted
        validate_preflight_state(snapshots[-1], package=value, outline={'lesson_format': 'tutorial_v1'}, context={})
    else:
        assert failures and not response.semantic_accepted
        assert response.effective_parameters['validated_repair_targets'] == [TARGET]


@pytest.mark.asyncio
@pytest.mark.parametrize('fault', ['missing', 'duplicate', 'unknown'])
async def test_incomplete_teaching_audit_cannot_approve_after_bounded_retry(monkeypatch, fault):
    result = verdict(True)
    if fault == 'missing': result.pop('teaching_case_audits')
    elif fault == 'duplicate': result['teaching_case_audits'] *= 2
    else: result['teaching_case_audits'][0]['target'] = 'teaching.unrelated'
    (failures, response, _), client, _ = await run_review(monkeypatch, package(True, isolate_teaching=True), result)
    assert failures and response.error and not response.semantic_accepted
    assert client.generate_json.await_count == 2
    assert response.effective_parameters['requested_output_tokens'] == 2 * SEMANTIC_TOKENS


@pytest.mark.asyncio
async def test_cached_tutorial_approval_without_teaching_audit_is_invalid(monkeypatch):
    value = package(True, isolate_teaching=True)
    (_, response, _), _, snapshots = await run_review(monkeypatch, value, verdict(True))
    assert response.semantic_accepted
    saved = snapshots[-1]
    saved['semantic'].pop('teaching_case_audits')
    with pytest.raises(ValueError):
        validate_preflight_state(saved, package=value, outline={'lesson_format': 'tutorial_v1'}, context={})


@pytest.mark.asyncio
async def test_legacy_package_review_does_not_require_teaching_audit(monkeypatch):
    result = {'acceptable': True, 'issues': []}
    value = package(True, isolate_teaching=True)
    # The legacy format has a longer workload contract; keep this test about audit compatibility.
    for activity in value.workbook.activities:
        activity.minutes_min, activity.minutes_max = 20, 40
    (failures, response, _), client, _ = await run_review(monkeypatch, value, result, outline={})
    assert not failures and not response.error and response.semantic_accepted
    assert client.generate_json.await_count == 1


@pytest.mark.asyncio
async def test_actionable_negative_teaching_issue_survives_incomplete_optional_audits(monkeypatch):
    result = {
        'acceptable': False,
        'issues': [{'target': TARGET, 'description':
            'Visits cannot cover currency without a monetary conversion; use separate attendance and budget limits.'}],
        'teaching_case_audits': [{'target': TARGET}],
    }
    (failures, response, _), client, snapshots = await run_review(monkeypatch, package(isolate_teaching=True), result)
    assert failures and not response.error and not response.semantic_accepted
    assert response.effective_parameters['validated_repair_targets'] == [TARGET]
    assert snapshots[-1]['semantic']['issues'] == [dict(issue, severity='blocking') for issue in result['issues']]
    assert client.generate_json.await_count == 1
