"""Captured namespace drift must be prevented, never normalized into approval."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.core.config import settings
from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import (
    LessonReview, PackagedLessonReview, ReviewEvidencePatch, _canonical_review_data,
    evidence_case_index, grounded_failures, numeric_span_owners, numeric_spans,
    scoped_review_model, scope_evidence_package, review_lesson,
)
from app.services.planning.package_review import (
    PackageReview, _evidence_patch_request, package_review_payload, review_package,
)
from tests.lesson_package_fixtures import package_payload
from tests.test_package_preflight_patch import package_with_spans, approved, check
from tests.test_json_generation_errors import client_for
from tests.test_openlux import chunk, transport


@pytest.fixture(autouse=True)
def no_telemetry(monkeypatch):
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())


def transfer_package():
    payload = package_payload()
    item = payload['workbook']['activities'][1]
    item['data'] = [{'id': 'receipts', 'label': 'Receipts', 'value': 230},
                    {'id': 'revenue', 'label': 'Revenue', 'value': 200}]
    item['worked_solution'] = 'Receipts exceed revenue by 30. Explain the difference using the supplied facts.'
    return LessonPackage.model_validate(payload)


def transfer_check(case_id='practice.transfer'):
    return dict(check(expression='receipts - revenue', result=30), case_id=case_id)


def test_case_index_uses_practice_namespace_for_transfer_and_keeps_raw_ids_distinct():
    package = transfer_package()
    index = evidence_case_index(package.review_context())
    assert set(index) == {'practice.guided', 'practice.transfer'}
    assert index['practice.transfer'] == {'raw_datum_ids': ['receipts', 'revenue'], 'derived_target_ids': []}
    assert numeric_span_owners({}, package.review_context()) == {'n1': 'practice.transfer'}
    context = {'teaching_cases': [{'id': 'example', 'data': [{'id': 'raw', 'value': 9}],
        'results': [{'id': 'derived', 'expression': 'raw*2'}]}]}
    assert evidence_case_index(context)['teaching.example'] == {
        'raw_datum_ids': ['raw'], 'derived_target_ids': ['derived']}


@pytest.mark.parametrize('base', [PackageReview, PackagedLessonReview, ReviewEvidencePatch])
def test_shared_case_enum_and_role_free_schema_are_request_local(base):
    original = copy.deepcopy(base.model_json_schema())
    compact = scoped_review_model(base, {'n1': 'A source'}, case_ids={'practice.transfer'},
        include_math_roles=False, excluded_fields=('practice_minutes', 'affected_sections'))
    schema = compact.model_json_schema()
    assert issubclass(compact, base) and compact.__name__ == base.__name__
    assert schema['$defs']['EvidenceCaseId']['enum'] == ['practice.transfer']
    for name in ('PackagedCalculationCheck', 'LiteralFactCheck'):
        assert schema['$defs'][name]['properties']['case_id'] == {'$ref': '#/$defs/EvidenceCaseId'}
    assert not {'math_roles', 'practice_minutes', 'affected_sections'} & schema['properties'].keys()
    assert 'MathRoleCheck' not in schema['$defs']
    assert not {'math_roles', 'practice_minutes', 'affected_sections'} & set(schema.get('required', []))
    another = scoped_review_model(base, {'n2': 'Other'}, case_ids={'teaching.other'}).model_json_schema()
    assert 'MathRoleCheck' in another['$defs']
    assert another['$defs']['EvidenceCaseId']['enum'] == ['teaching.other']
    assert compact.model_json_schema() == schema and base.model_json_schema() == original


@pytest.mark.parametrize('provider', ['zai', 'openlux'])
@pytest.mark.asyncio
async def test_real_offline_transport_receives_case_enum_without_impossible_or_forbidden_fields(provider, monkeypatch):
    monkeypatch.setattr(settings, 'llm_admission_limits', {})
    client = client_for(provider)
    stream, request = transport(monkeypatch, client, [chunk('{"issues":["The source contradicts its data."]}', 'stop')])
    model = scoped_review_model(ReviewEvidencePatch, {'n1': 'A source'}, case_ids={'practice.transfer'},
        include_math_roles=False, excluded_fields=('practice_minutes', 'affected_sections'))
    response = await client.generate_json('Review independently', 'Reference package', output_model=model)
    assert not response.error and response.data['issues']
    system = request['messages'][0]['content']
    schema = json.loads(system[system.index('{'):])
    assert schema['$defs']['EvidenceCaseId']['enum'] == ['practice.transfer']
    assert 'MathRoleCheck' not in system and 'affected_sections' not in system and 'practice_minutes' not in system
    assert stream.closed


@pytest.mark.asyncio
async def test_wrong_case_transfer_namespace_is_not_normalized_even_when_suffix_and_operands_match():
    package = transfer_package()
    bad = transfer_check('Transfer.transfer')
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[
        LLMResponse(data=approved(bad)), LLMResponse(data={'calculations': [bad]})]))
    failures, response, _ = await review_package(package, {}, {}, client_factory=lambda **kw: client)
    assert failures and response.error and client.generate_json.await_count == 2
    for call in client.generate_json.await_args_list:
        body = json.loads(call.kwargs['user_prompt'])
        assert set(body['evidence_cases']) == {'practice.guided', 'practice.transfer'}
        assert 'transfer.<id> is never' in call.kwargs['system_prompt']
        assert 'MathRoleCheck' not in json.dumps(call.kwargs['output_model'].model_json_schema())
    assert response.data['calculations'][0]['case_id'] == 'Transfer.transfer'


@pytest.mark.asyncio
async def test_correct_transfer_binding_succeeds_without_role_schema_or_extra_request():
    package = transfer_package()
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=approved(transfer_check()))))
    failures, response, _ = await review_package(package, {}, {}, client_factory=lambda **kw: client)
    assert not failures and not response.error and client.generate_json.await_count == 1
    call = client.generate_json.call_args.kwargs
    assert 'symbolic_formula' not in call['system_prompt']
    assert 'practice.transfer' in json.loads(call['user_prompt'])['evidence_cases']


def test_owned_patch_trims_only_unrelated_private_prose_and_keeps_all_reference_data():
    package = package_with_spans('Receipts exceed revenue by 20.')
    context = package.review_context()
    context['teaching_cases'] = [{'id': 'reference', 'data': [{'id': 'other', 'value': 7}], 'results': []}]
    original = copy.deepcopy(context)
    review = PackageReview.model_validate(approved(check()))
    owners = numeric_span_owners({}, context)
    scoped = scope_evidence_package(context, owners, {'n1'}, review)
    assert scoped['private_workbook']['activities'][0] == context['private_workbook']['activities'][0]
    assert scoped['private_workbook']['activities'][1] == {
        key: value for key, value in context['private_workbook']['activities'][1].items()
        if key not in {'hint', 'worked_solution'}}
    assert scoped['teaching_cases'] == context['teaching_cases']
    assert context == original
    payload = package_review_payload(package, {}, {})
    request, _ = _evidence_patch_request(review, payload, ['n1: a missing proof'])
    body = json.loads(request['user_prompt'])
    assert body['package']['workbook']['activities'][0] == payload['package']['workbook']['activities'][0]
    assert body['package']['workbook']['activities'][1] == {
        key: value for key, value in payload['package']['workbook']['activities'][1].items()
        if key not in {'hint', 'worked_solution'}}
    assert set(body['evidence_cases']) == {'practice.guided', 'practice.transfer'}
    props = request['output_model'].model_json_schema()['properties']
    assert not {'math_roles', 'practice_minutes', 'affected_sections'} & props.keys()
    assert 'symbolic_formula' not in request['system_prompt']


@pytest.mark.parametrize('mode', ['ownerless', 'unknown_case', 'other_known_case'])
def test_patch_scope_conservatively_retains_required_or_ambiguous_context(mode):
    package = package_with_spans('Receipts exceed revenue by 20.')
    context = package.review_context()
    owners = numeric_span_owners({}, context)
    review = PackageReview.model_validate(approved(check()))
    if mode == 'ownerless': owners = {}
    if mode == 'unknown_case': review.calculations[0].case_id = 'transfer.guided'
    if mode == 'other_known_case': review.calculations[0].case_id = 'practice.transfer'
    scoped = scope_evidence_package(context, owners, {'n1'}, review)
    assert scoped == context


@pytest.mark.asyncio
async def test_omitted_role_wire_definition_does_not_discard_unsolicited_invalid_evidence():
    package = transfer_package()
    role = {'claim_id':'n1', 'case_id':'practice.transfer', 'field_id':'invented', 'role':'divisor',
            'coefficient':2, 'source_quote':'divide by 2', 'symbol_bindings':{}}
    bad = approved(transfer_check(), math_roles=[role])
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[LLMResponse(data=bad),
        LLMResponse(data={'calculations': [transfer_check()], 'math_roles': [role]})]))
    failures, response, _ = await review_package(package, {}, {}, client_factory=lambda **kw: client)
    assert failures and response.error and client.generate_json.await_count == 2


@pytest.mark.asyncio
async def test_negative_verdict_survives_unknown_case_and_unused_role_fields():
    package = transfer_package()
    rejected = approved(transfer_check('transfer.transfer'), acceptable=False, issues=['Transfer reveals its answer.'])
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=rejected)))
    failures, response, _ = await review_package(package, {}, {}, client_factory=lambda **kw: client)
    assert failures == rejected['issues'] and not response.data['acceptable']
    assert client.generate_json.await_count == 1


@pytest.mark.asyncio
async def test_final_lesson_initial_and_patch_share_explicit_case_index_and_compact_modes():
    from tests.test_lesson_review_evidence_patch import PACKAGE, LESSON, verdict, calculation
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[LLMResponse(data=verdict()),
        LLMResponse(data={'calculations':[calculation(['n2'], 'second-first', 10)]})]))
    failures, response, _ = await review_lesson(LESSON, client_factory=lambda **kw: client,
        context={'lesson_package': copy.deepcopy(PACKAGE)})
    assert not failures and not response.error
    initial, patch = [call.kwargs for call in client.generate_json.await_args_list]
    assert json.loads(initial['user_prompt'])['context']['evidence_cases']['teaching.case']['raw_datum_ids'] == ['first', 'second']
    body = json.loads(patch['user_prompt'])
    assert body['lesson_package'] == PACKAGE  # Ownerless prose retains full context.
    for request in (initial, patch):
        schema = request['output_model'].model_json_schema()
        assert schema['$defs']['EvidenceCaseId']['enum'] == ['teaching.case']
        assert 'MathRoleCheck' not in schema['$defs']
    assert 'affected_sections' in patch['output_model'].model_json_schema()['properties']
    assert 'practice_minutes' not in patch['output_model'].model_json_schema()['properties']


@pytest.mark.asyncio
async def test_replacement_timing_comparison_remains_semantic_evidence_not_automatic_approval():
    changes = [{'activity_id': 'transfer', 'previous_minutes': [14, 22],
                'revised_minutes': [16, 24], 'unchanged_task': True}]
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data={
        'acceptable': False, 'issues': ['Unchanged work does not support the increased estimate.']})))
    failures, response, _ = await review_package(transfer_package(), {}, {'activity_timing_changes': changes},
        client_factory=lambda **kw: client)
    request = client.generate_json.call_args.kwargs
    assert json.loads(request['user_prompt'])['context']['activity_timing_changes'] == changes
    assert 'Increasing time labels alone cannot fix a workload shortfall' in request['system_prompt']
    assert failures and not response.data['acceptable'] and client.generate_json.await_count == 1


@pytest.mark.parametrize('stage', ['package', 'lesson'])
@pytest.mark.asyncio
async def test_missing_cross_activity_fact_can_bind_to_previous_task_without_naming_it(stage):
    payload = package_payload()
    guided, transfer = payload['workbook']['activities']
    guided['data'] = [{'id': 'funding', 'label': 'Original funding', 'value': 100, 'unit': 'USD'}]
    transfer['data'] = [{'id': 'ending', 'label': 'Ending balance', 'value': 200, 'unit': 'USD'}]
    transfer['worked_solution'] = ('The previous task supplied original funding of 100. '
        'Explain the comparison using the new scenario and its changed assumptions.')
    package = LessonPackage.model_validate(payload)
    fact = {'claim_id': 'n1', 'case_id': 'practice.guided', 'datum_ids': ['funding']}
    initial = {'acceptable': True, 'issues': []}
    if stage == 'lesson':
        initial.update(package_issues=[], advisories=[], practice_minutes=45, contains_calculations=False, calculations=[])
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=[LLMResponse(data=initial),
        LLMResponse(data={'literal_facts': [fact]})]))
    if stage == 'package':
        failures, response, _ = await review_package(package, {}, {}, client_factory=lambda **kw: client)
    else:
        failures, response, _ = await review_lesson({'lesson_content': 'Apply the cases and compare their assumptions.'},
            client_factory=lambda **kw: client, context={'lesson_package': package.review_context()})
    assert not failures and not response.error and response.data['acceptable'] is True
    assert response.data['literal_facts'] == [fact] and client.generate_json.await_count == 2
    request = client.generate_json.call_args.kwargs
    body = json.loads(request['user_prompt'])
    assert set(body['evidence_cases']) == {'practice.guided', 'practice.transfer'}
    assert request['output_model'].model_json_schema()['$defs']['EvidenceCaseId']['enum'] == [
        'practice.guided', 'practice.transfer']
    if stage == 'package':
        first = json.loads(client.generate_json.await_args_list[0].kwargs['user_prompt'])['package']['workbook']['activities']
        corrected = body['package']['workbook']['activities']
    else:
        first = package.review_context()['private_workbook']['activities']
        corrected = body['lesson_package']['private_workbook']['activities']
    assert corrected[0] == {key: value for key, value in first[0].items() if key not in {'hint', 'worked_solution'}}
    assert corrected[1] == first[1]
    assert body['numeric_span_owners'] == {'n1': 'practice.transfer'}
