"""The real annotation was rejected for a diagnostic sentence omitted from view."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.prompt_loader import load_and_render
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import TextCriterionAudit, _SEMANTIC_PROMPT, review_package
from tests.lesson_package_fixtures import package_payload


RECORDED = json.loads((Path(__file__).parent / 'fixtures' / 'hidden_diagnostic_criterion.json').read_text())


def test_actual_unfair_grade_and_omitted_public_fact_are_preserved():
    activity = RECORDED['activity']
    assert 'weekday workers' not in activity['instructions']
    assert 'weekday workers' in activity['fields'][0]['criteria'][1]
    assert 'weekday workers' in RECORDED['full_relevant_attempt']
    assert 'learn whether continued opening is justified before committing' in RECORDED['submitted_answer']
    grade = RECORDED['grading_diagnostic']['fields'][0]
    assert grade['criterion_met'] == [True, False, True, True]
    assert 'weekday workers' in grade['feedback'] and grade['uncertain'] is False


def test_public_input_boundary_is_part_of_existing_alignment_audit_and_authoring():
    description = TextCriterionAudit.model_json_schema()['properties']['task_aligned']['description']
    assert "activity's public instructions/data" in description
    assert 'Hidden context or private model answers do not supply missing inputs' in description
    for clause in ('ALL case-specific facts', 'task_aligned=false for a hidden-fact requirement',
                   'including a separately stated reason', 'not a minor self-containment advisory',
                   'surrounding lesson/context cannot make an omitted purpose part of the quote'):
        assert clause in _SEMANTIC_PROMPT
    for name in ('tutorial_package_seed.txt', 'tutorial_activity_generate.txt',
                 'lesson_package_seed.txt', 'lesson_activity_generate.txt', 'lesson_package_generate.txt'):
        prompt = load_and_render(name, {})
        assert 'public' in prompt and 'instructions/data' in prompt
        if name.startswith('tutorial_'):
            assert 'complete relevant diagnostic attempts' in prompt
        else:
            assert ('full relevant diagnostic attempt' in prompt or 'full relevant\noriginal attempt' in prompt)


@pytest.mark.asyncio
@pytest.mark.parametrize('restored_public_attempt', [False, True])
async def test_hidden_session_fact_cannot_rescue_the_criterion_but_public_restoration_can(monkeypatch, restored_public_attempt):
    raw = package_payload()
    raw['teaching_cases'] = [{'id': 'notice', 'assumptions': (
        'Original fictional notice: Garden helpers welcome. A revision names the cleanup '
        'and contact so a reader can identify the proposed action and response path.'
    ), 'data': [], 'results': []}]
    raw['workbook']['activities'][0] = copy.deepcopy(RECORDED['activity'])
    raw['workbook']['activities'][1].update(minutes_min=1, minutes_max=2)
    if restored_public_attempt:
        raw['workbook']['activities'][0]['instructions'] = (
            'Here is your full relevant diagnostic attempt:\n\n' + RECORDED['full_relevant_attempt']
            + '\n\nIdentify the proposal, its stated purpose, and one admitted gap. '
            'Distinguish the proposal sentence from the separately stated reason.'
        )
    package = LessonPackage.model_validate(raw)
    audits = []
    for activity in package.workbook.activities:
        field = activity.fields[0]
        hidden = activity.id == 'label_own_claim' and not restored_public_attempt
        alternative = (RECORDED['submitted_answer'] if hidden else
            'The proposal tests Sunday opening before continuation. Its stated purpose is learning '
            'whether weekday workers benefit without permanent commitment. The attempt admits '
            'uncertainty about sufficient evidence and a fair reply to the strongest objection.'
            if activity.id == 'label_own_claim' else
            'A bounded claim names its conditions; an objection tests its reason, and a revision '
            'narrows those conditions when the objection reveals a weakness.')
        audits.append({
            'target': 'practice.' + activity.id + '.' + field.id,
            'alternative_response': alternative,
            'criteria': [{
                'criterion_index': index, 'task_aligned': not (hidden and index == 1),
                'accepts_alternative': not (hidden and index == 1),
                'reason': ('Weekday-worker purpose appears only in omitted diagnostic context, not public inputs.'
                           if hidden and index == 1 else
                           'The alternative follows the stated task and its publicly supplied facts.'),
            } for index in range(len(field.criteria))],
            'model_answer_valid': not hidden,
            'model_answer_reason': ('Model requires a separately stated purpose omitted from the shown passage.'
                                   if hidden else 'The model uses the task facts supplied to the learner.'),
            'requires_activity_repair': hidden,
        })
    response_data = {'acceptable': True, 'issues': [], 'text_audits': audits,
        'teaching_case_audits': [{'target': 'teaching.notice',
        'core_inference': 'A clearer invitation names action and response path.',
        'quantities_and_units': 'Qualitative action and contact; no quantitative comparison.',
        'decision_rule': 'Can the reader identify cleanup and reply contact?',
        'semantically_valid': True, 'reason': 'The revision supplies both elements missing from the invitation.'}]}
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=response_data)))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'},
        {'session_context': RECORDED['full_relevant_attempt']}, client_factory=lambda **kwargs: client)
    assert client.generate_json.await_count == 1
    assert not response.error
    if restored_public_attempt:
        assert not failures and response.semantic_accepted
    else:
        assert failures and not response.semantic_accepted
        assert response.effective_parameters['validated_repair_targets'] == ['practice.label_own_claim']
        assert 'omitted diagnostic context' in ' '.join(failures)

