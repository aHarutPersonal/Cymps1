"""Captured rubric required quoting an absent feature and excluded an institution."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import SEMANTIC_TOKENS
from app.services.planning.package_preflight import review_package


RECORDED = json.loads((Path(__file__).parent / 'fixtures' / 'absence_assessment.json').read_text())
GUIDED_ANSWER = (
    "The garden should run a weekly volunteer rota. Actor: yes—'The garden' refers to "
    "the organization managing volunteers. Action: yes—'run a weekly volunteer rota'. "
    "Success measure: missing; the sentence gives no way to judge success."
)
TRANSFER_ANSWER = (
    "'Our town should support the summer market.' Actor: 'Our town' means the addressed "
    "council. Action: 'support' is vague. Success measure: absent; none is stated. "
    "Revision: The Council should permit the summer market in the square and compare "
    "visitor numbers with management costs before renewing permission."
)


def package_and_audits(corrected):
    workbook = copy.deepcopy(RECORDED)
    guided, transfer = workbook['activities']
    if corrected:
        guided['fields'][0]['criteria'][0] = (
            'Names a specific actor, accepting an organization when its agency is justified'
        )
        guided['fields'][0]['criteria'][3] = (
            'Quotes evidence for present features; accurately states absence where no supporting phrase exists'
        )
        guided['worked_solution']['steps'][0]['explanation'] = GUIDED_ANSWER
        transfer['fields'][0]['criteria'][1] = (
            'Judges actor, action and success measure; quotes present features or explains a missing feature'
        )
        transfer['instructions'] = transfer['instructions'].replace(
            'For each criterion give a yes or no and quote the phrase from the sentence that supports your verdict.',
            'For each criterion give a yes or no. Quote present features, or state that the feature is absent '
            'and explain the omission; no quotation of an absent feature is required.'
        )
        transfer['worked_solution']['steps'][0]['explanation'] = TRANSFER_ANSWER
    package = LessonPackage.model_validate({
        'workbook': workbook,
        'teaching_cases': [{'id': 'pantry', 'data': [], 'results': [], 'assumptions': (
            'Original fictional example: The food pantry should offer a pickup rota. The pantry '
            'is the responsible organization and offering a rota is an action; no success measure '
            'is stated, so the correct assessment explicitly identifies its absence.'
        )}],
    })
    audits = []
    for activity in package.workbook.activities:
        field = activity.fields[0]
        is_guided = activity.id == 'guided_practice'
        rejected_indices = ({0, 3} if is_guided else {1}) if not corrected else set()
        audits.append({
            'target': f'practice.{activity.id}.{field.id}',
            'alternative_response': GUIDED_ANSWER if is_guided else TRANSFER_ANSWER,
            'criteria': [{
                'criterion_index': index,
                'task_aligned': index not in rejected_indices,
                'accepts_alternative': index not in rejected_indices,
                'reason': (
                    'A justified organization can act; this exclusion contradicts the task.'
                    if is_guided and index == 0 and not corrected else
                    'An absent success measure has no supporting phrase to quote.'
                    if index in rejected_indices else
                    'The response satisfies the task using supplied facts and justified proposals.'
                ),
            } for index in range(len(field.criteria))],
            'model_answer_valid': corrected,
            'model_answer_reason': (
                'It accepts justified organizational actors and accurate evidence of absence.'
                if corrected else
                'It requires impossible quotations of absence or excludes justified organizational actors.'
            ),
            'requires_activity_repair': not corrected,
        })
    return package, audits


def test_recorded_workbook_preserves_the_public_permission_and_private_contradiction():
    guided, transfer = RECORDED['activities']
    assert 'or state honestly that it is missing' in guided['instructions']
    assert 'rather than "the garden" or "someone"' in guided['fields'][0]['criteria'][0]
    assert 'for each yes or no judgment' in guided['fields'][0]['criteria'][3]
    assert 'still passes if it quotes its own phrases' in guided['worked_solution']['steps'][0]['explanation']
    assert 'each tied to a quoted phrase' in transfer['fields'][0]['criteria'][1]
    assert 'Success measure: missing' in GUIDED_ANSWER
    assert "'The garden' refers to the organization" in GUIDED_ANSWER


@pytest.mark.asyncio
@pytest.mark.parametrize('corrected', [False, True])
async def test_complete_audit_blocks_contradiction_but_accepts_honest_absence_and_organizational_actor(monkeypatch, corrected):
    package, audits = package_and_audits(corrected)
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data={
        'acceptable': True, 'issues': [], 'text_audits': audits,
        'teaching_case_audits': [{'target': 'teaching.pantry',
            'core_inference': 'Pantry is actor; pickup rota is action; measure absent.',
            'quantities_and_units': 'Qualitative roles and absent measure, with no unit conversion.',
            'decision_rule': 'Identify stated elements and honestly report the absent measure.',
            'semantically_valid': True,
            'reason': 'The analysis accepts organizational agency and the stated omission.'}],
    })))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'}, {},
        client_factory=lambda **kwargs: client)
    assert not response.error
    assert client.generate_json.await_count == 1
    assert response.effective_parameters['requested_output_tokens'] == SEMANTIC_TOKENS
    if corrected:
        assert not failures and response.semantic_accepted
    else:
        assert failures and not response.semantic_accepted
        assert set(response.effective_parameters['validated_repair_targets']) == {
            'practice.guided_practice', 'practice.independent_transfer',
        }
        assert 'no supporting phrase to quote' in ' '.join(failures)
        assert 'justified organization can act' in ' '.join(failures)
