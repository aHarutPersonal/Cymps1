"""Small corrections preserve immutable lesson facts and publication checks."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import (
    LessonPackage, PrivatePackageRepair, apply_private_package_repair, generate_package,
)
from app.services.planning.activity_draft import LessonActivityDraft
from app.services.planning.lesson_review import LessonReview, grounded_failures, review_lesson
from tests.lesson_package_fixtures import package_payload


def numeric_package():
    value = package_payload()
    for a in value['workbook']['activities']:
        a['data'] = [
            {'id': 'profit', 'label': 'Operating profit', 'value': 14, 'unit': 'million'},
            {'id': 'interest', 'label': 'Interest expense', 'value': 4, 'unit': 'million'},
        ]
        a['fields'] = [
            {'id': 'coverage', 'label': 'Interest coverage', 'kind': 'number', 'expression': 'profit / interest'},
            {'id': 'decision', 'label': 'Pass the threshold?', 'kind': 'choice',
             'choices': [{'id': 'pass', 'label': 'Pass'}, {'id': 'fail', 'label': 'Fail'}], 'correct_choice': 'fail'},
        ]
    return LessonPackage.model_validate(value)


def test_private_correction_preserves_every_other_value_and_input_package():
    package = numeric_package()
    original = package.model_dump(mode='json')
    repair = PrivatePackageRepair.model_validate({
        'field_patches': [{'activity_id': 'guided', 'field_id': 'decision', 'correct_choice': 'pass'}],
        'solution_patches': [{'activity_id': 'guided', 'worked_solution':
            'Operating profit divided by interest expense gives coverage of 3.5, so the minimum threshold is passed.'}],
    })
    result = apply_private_package_repair(package, repair)
    expected = copy.deepcopy(original)
    expected['workbook']['activities'][0]['fields'][1]['correct_choice'] = 'pass'
    expected['workbook']['activities'][0]['worked_solution'] = repair.solution_patches[0].worked_solution
    assert result.model_dump(mode='json') == expected
    assert package.model_dump(mode='json') == original
    assert result.writer_context() == package.writer_context()


@pytest.mark.parametrize('patch', [
    {'activity_id': 'unknown', 'field_id': 'decision', 'correct_choice': 'pass'},
    {'activity_id': 'guided', 'field_id': 'unknown', 'correct_choice': 'pass'},
    {'activity_id': 'guided', 'field_id': 'decision', 'correct_choice': 'invented'},
    {'activity_id': 'guided', 'field_id': 'coverage', 'expression': '3.5'},
    {'activity_id': 'guided', 'field_id': 'coverage', 'expression': 'other_case / interest'},
    {'activity_id': 'guided', 'field_id': 'coverage', 'expression': 'profit / 0'},
    {'activity_id': 'guided', 'field_id': 'coverage', 'correct_choice': 'pass'},
    {'activity_id': 'guided', 'field_id': 'decision', 'correct_choice': 'pass', 'label': 'Changed public question'},
])
def test_private_patch_rejects_wrong_targets_invalid_answers_and_public_changes(patch):
    with pytest.raises(ValueError):
        apply_private_package_repair(numeric_package(), PrivatePackageRepair.model_validate({'field_patches': [patch]}))


def test_duplicate_or_empty_private_patch_is_rejected():
    patch = {'activity_id': 'guided', 'field_id': 'decision', 'correct_choice': 'pass'}
    for payload in ({}, {'field_patches': [patch, patch]}):
        with pytest.raises(ValueError):
            apply_private_package_repair(numeric_package(), PrivatePackageRepair.model_validate(payload))


@pytest.mark.asyncio
async def test_invalid_private_patch_retry_is_bounded_and_receives_rejected_patch(monkeypatch):
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())
    invalid = {'field_patches': [{'activity_id': 'guided', 'field_id': 'coverage', 'expression': '3.5'}]}
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[LLMResponse(data=copy.deepcopy(invalid)) for _ in range(2)]))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kw: client,
                                                prior_package=numeric_package(), defects=['Incorrect key'])
    assert package is None and response.error
    assert client.generate_json.await_count == 2
    assert json.dumps(invalid) in client.generate_json.await_args_list[1].kwargs['user_prompt']
    assert all(c.kwargs['output_model'] is PrivatePackageRepair for c in client.generate_json.await_args_list)


@pytest.mark.parametrize('expression,case_id,result,source,passes', [
    ('profit / interest', 'practice.guided', 3.5, 'Coverage is 3.50.', True),
    ('profit / interest', 'practice.guided', 4.5, 'Coverage is 4.50.', False),
    ('profit / missing', 'practice.guided', 3.5, 'Coverage is 3.50.', False),
    ('profit / interest', 'practice.unknown', 3.5, 'Coverage is 3.50.', False),
    ('profit / interest + 99', 'practice.guided', 102.5, 'Coverage is 102.50.', False),
    ('profit / interest', 'practice.guided', 3.5, 'The answer is absent.', False),
    ('profit / interest', 'practice.guided', 3.5, 'Coverage is 3.5001.', False),
    ('sqrt(profit + interest)', 'practice.guided', 4.24, 'Result is 4.24.', True),
])
def test_named_formula_remains_case_bound_source_bound_and_mathematically_verified(expression,case_id,result,source,passes):
    review = LessonReview(acceptable=True, issues=[], practice_minutes=30, contains_calculations=True,
        calculations=[{'location': 'coverage', 'claim_ids': ['n1'], 'case_id': case_id,
                       'expression': expression, 'claimed_result': result}])
    context = numeric_package().review_context()
    context.pop('private_workbook')  # avoid unrelated workbook spans for this focused source check
    context['teaching_cases'] = []
    context['private_workbook'] = {'activities': [{'id': 'guided', 'data': numeric_package().model_dump()['workbook']['activities'][0]['data']}]}
    failures = grounded_failures(review, {'lesson_content': source}, context) + review.failures()
    assert (not failures) == passes


@pytest.mark.asyncio
async def test_private_patch_is_not_itself_a_publication_approval(monkeypatch):
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())
    payload = {'field_patches': [{'activity_id': 'guided', 'field_id': 'decision', 'correct_choice': 'pass'}]}
    patch_client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=payload)))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kw: patch_client,
                                                prior_package=numeric_package(), defects=['Wrong private key'])
    assert package is not None and not response.error
    negative = LLMResponse(data={'acceptable': False, 'issues': [], 'package_issues': ['Worked solution is still contradictory'],
        'practice_minutes': 30, 'contains_calculations': False, 'calculations': [], 'literal_fact_ids': []})
    review_client = SimpleNamespace(generate_json=AsyncMock(return_value=negative))
    failures, _, _ = await review_lesson({'lesson_content': 'Teach the calculation.'}, client_factory=lambda **kw: review_client,
                                      context={'lesson_package': package.review_context()})
    assert 'Worked solution is still contradictory' in failures
    review_client.generate_json.assert_awaited_once()


@pytest.mark.asyncio
async def test_public_correction_shares_retry_limit_and_revalidates_full_contract(monkeypatch):
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())
    prior = numeric_package()
    before = prior.model_dump(mode='json')
    requests = []
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data={'public_defects': ['The case facts do not support the task.']}),
        LLMResponse(data={'workbook': {'activities': []}}),
    ]))
    def factory(**kwargs):
        requests.append(kwargs)
        return client
    package, response, _ = await generate_package({}, {}, client_factory=factory,
        prior_package=prior, defects=['Incorrect exercise'], repair_targets=['practice.guided'])
    assert package is None and response.error
    assert client.generate_json.await_count == 2
    assert [c.kwargs['output_model'] for c in client.generate_json.await_args_list] == [PrivatePackageRepair, LessonActivityDraft]
    assert [(request['timeout'], request['max_tokens']) for request in requests] == [(120, 3500), (90, 4000)]
    second = client.generate_json.await_args_list[1].kwargs
    prompt = json.loads(second['user_prompt'])
    assert prompt['previous_activity'] == before['workbook']['activities'][0]
    assert prompt['validated_repair_targets'] == ['practice.guided']
    assert 'previous_package' not in prompt
    assert 'do not inflate timing or repeat work' in second['system_prompt'].lower()
    assert prior.model_dump(mode='json') == before


@pytest.mark.asyncio
async def test_public_defects_cannot_be_hidden_in_an_otherwise_valid_private_patch(monkeypatch):
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())
    payload = {'public_defects': ['Data are wrong.'], 'field_patches': [
        {'activity_id': 'guided', 'field_id': 'decision', 'correct_choice': 'pass'}]}
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[LLMResponse(data=copy.deepcopy(payload)) for _ in range(2)]))
    package, response, _ = await generate_package({}, {}, client_factory=lambda **kw: client,
        prior_package=numeric_package(), defects=['Incorrect exercise'])
    assert package is None and response.error
    assert client.generate_json.await_count == 2


def test_previously_approved_release_remains_readable_but_not_current_for_regeneration():
    from app.services.planning.lesson_package import current_package_approval, provenance
    from app.services.llm.schemas import PlanDetailStepOutput
    from tests.test_plan_detail_output_schema import _valid_payload
    previous = {
        'review_version': 6, 'package_version': 1,
        'capability_hash': '1815a97ad0c7246f737c493fbec7b9217c6a5dd6a7d96cacd93c0c34b3afe48f',
        'prompt_hash': 'e607841f3059a17ec283d0ca7adb49f32911811aa4cb6ce7da50dbda0c53a47f',
        'schema_hash': '69872a66dd96125909e6196f7257f85ad5242b0eefda87a9e266781858b57dc8',
    }
    payload = _valid_payload(lesson_count=1, material_count=1)
    step = PlanDetailStepOutput.model_validate(payload['steps'][0]).model_dump(mode='json')
    payload['steps'] = [step]
    payload['_generation'] = {'lesson_package_version': 1, 'status': 'partial', 'job_id': 'job',
        'ready_step_ids': ['step_1'], 'validation_identity': previous,
        'lesson_validation': {'step_1': {**provenance(step, numeric_package()), **previous}}}
    assert not current_package_approval(payload)
    assert current_package_approval(payload, allow_compatible_read=True)
    from app.api.v1.plans import _partial_lesson_details_available
    assert _partial_lesson_details_available(payload)
    for mutation in ('content', 'identity', 'approval', 'missing_key'):
        changed = copy.deepcopy(payload)
        if mutation == 'content':
            changed['steps'][0]['lesson_content'] += ' An unapproved change.'
        elif mutation == 'identity':
            changed['_generation']['validation_identity']['prompt_hash'] = 'unrecognized'
        elif mutation == 'approval':
            changed['_generation']['lesson_validation']['step_1']['review_version'] = 5
        else:
            changed['_generation']['lesson_validation']['step_1'].pop('package_hash')
        assert not current_package_approval(changed, allow_compatible_read=True)
        assert not _partial_lesson_details_available(changed)
