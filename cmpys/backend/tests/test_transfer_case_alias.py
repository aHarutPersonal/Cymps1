"""Only an exact, canonical transfer activity can supply the namespace alias."""
import copy
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.lesson_review import normalize_evidence_case_aliases, review_lesson
from app.services.planning.package_review import review_package
from tests.lesson_package_fixtures import package_payload


def fixture(mode='calculations'):
    payload = package_payload()
    activity = payload['workbook']['activities'][1]
    activity['data'] = [{'id': 'receipts', 'label': 'Receipts', 'value': 230},
                        {'id': 'revenue', 'label': 'Revenue', 'value': 200}]
    if mode == 'calculations':
        activity['worked_solution'] = 'Receipts exceed revenue by 30. Explain the accounting distinction using the supplied case.'
        entry = {'claim_ids': ['n1'], 'case_id': 'transfer.transfer',
                 'expression': 'receipts-revenue', 'claimed_result': 30}
    elif mode == 'literal_facts':
        activity['worked_solution'] = 'Revenue is 200. Explain the accounting distinction using the supplied case and its assumptions.'
        entry = {'claim_id': 'n1', 'case_id': 'transfer.transfer', 'datum_ids': ['revenue']}
    else:
        activity['data'] = [{'id': 'base', 'label': 'Base', 'value': 18},
                            {'id': 'height', 'label': 'Height', 'value': 9}]
        activity['fields'].append({'id': 'area', 'label': 'Area', 'kind': 'number', 'expression': 'base*height/2'})
        activity['worked_solution'] = 'Explain why we divide by 2 for this operation. Describe the geometric relationship without introducing another task.'
        entry = {'claim_id': 'n1', 'case_id': 'transfer.transfer', 'field_id': 'area',
                 'role': 'divisor', 'coefficient': 2, 'source_quote': 'divide by 2', 'symbol_bindings': {}}
    return LessonPackage.model_validate(payload), entry


@pytest.fixture(autouse=True)
def no_telemetry(monkeypatch):
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())


def base_verdict(stage, mode, entries=None):
    data = {'acceptable': True, 'issues': [], 'contains_calculations': mode == 'calculations' and bool(entries)}
    if stage == 'lesson':
        data.update(package_issues=[], advisories=[], practice_minutes=45, calculations=[])
    if entries is not None:
        data[mode] = entries
    return data


async def execute(stage, package, replies):
    responses = [LLMResponse(data=copy.deepcopy(data), effective_parameters={'provider_parameter': 'preserved'}) for data in replies]
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=responses))
    if stage == 'package':
        result = await review_package(package, {}, {}, client_factory=lambda **kw: client)
    else:
        result = await review_lesson({'lesson_content': 'Apply the method to the provided independent scenario.'},
            client_factory=lambda **kw: client, context={'lesson_package': package.review_context()})
    return result, client


@pytest.mark.parametrize('mode', ['calculations', 'literal_facts', 'math_roles'])
def test_normalization_changes_only_exact_case_ids_without_mutating_input(mode):
    package, entry = fixture(mode)
    data = {'acceptable': False, 'issues': ['A negative verdict stays negative.'], mode: [entry],
            'extra_field': {'case_id': 'transfer.transfer'}, 'literal_fact_ids': ['transfer.transfer']}
    original = copy.deepcopy(data)
    normalized, count = normalize_evidence_case_aliases(data, package.review_context())
    assert count == 1 and data == original
    expected = copy.deepcopy(data); expected[mode][0]['case_id'] = 'practice.transfer'
    assert normalized == expected
    assert normalize_evidence_case_aliases(normalized, package.review_context()) == (normalized, 0)


@pytest.mark.parametrize('alias', ['transfer.guided', 'transfer.missing', 'Transfer.transfer',
    'transfer.Transfer', ' transfer.transfer', 'transfer.transfer ', 'transfer.transfer.extra',
    'teaching.transfer', 'guided.transfer', 'practice.transfer', '', None, ['transfer.transfer']])
def test_no_fuzzy_guided_teaching_whitespace_or_case_alias(alias):
    package, entry = fixture()
    data = {'calculations': [{**entry, 'case_id': alias}]}
    normalized, count = normalize_evidence_case_aliases(data, package.review_context())
    assert normalized == data and count == 0


@pytest.mark.parametrize('broken', ['missing', 'wrong_container', 'duplicate', 'guided_kind',
    'incomplete', 'malformed_datum', 'malformed_field'])
def test_malformed_or_ambiguous_workbook_cannot_establish_alias(broken):
    package, entry = fixture()
    context = package.review_context()
    if broken == 'missing': context = {}
    elif broken == 'wrong_container': context['private_workbook'] = []
    elif broken == 'duplicate':
        context['private_workbook']['activities'].append(copy.deepcopy(context['private_workbook']['activities'][1]))
    elif broken == 'guided_kind': context['private_workbook']['activities'][1]['kind'] = 'practice'
    elif broken == 'incomplete': del context['private_workbook']['activities'][1]['instructions']
    elif broken == 'malformed_datum': context['private_workbook']['activities'][1]['data'][0]['value'] = 'unknown'
    elif broken == 'malformed_field': context['private_workbook']['activities'][1]['fields'] = [None]
    data = {'calculations': [entry]}
    normalized, count = normalize_evidence_case_aliases(data, context)
    assert normalized == data and count == 0


@pytest.mark.parametrize('stage', ['package', 'lesson'])
@pytest.mark.parametrize('path', ['initial', 'patch'])
@pytest.mark.parametrize('mode', ['calculations', 'literal_facts', 'math_roles'])
@pytest.mark.asyncio
async def test_all_four_review_paths_accept_only_the_identity_alias_before_normal_validation(stage, path, mode):
    package, entry = fixture(mode)
    replies = ([base_verdict(stage, mode, [entry])] if path == 'initial' else
               [base_verdict(stage, mode), {mode: [entry]}])
    (failures, response, _), client = await execute(stage, package, replies)
    assert not failures and not response.error and response.data['acceptable'] is True
    assert response.data[mode][0]['case_id'] == 'practice.transfer'
    assert response.effective_parameters == {'provider_parameter': 'preserved', 'evidence_case_alias_count': 1}
    assert client.generate_json.await_count == (1 if path == 'initial' else 2)
    # Provider contract remains canonical even though one exact response alias is recognized.
    for call in client.generate_json.await_args_list:
        allowed = call.kwargs['output_model'].model_json_schema()['$defs']['EvidenceCaseId']['enum']
        assert 'practice.transfer' in allowed and 'transfer.transfer' not in allowed


@pytest.mark.parametrize('stage', ['package', 'lesson'])
@pytest.mark.parametrize('negative', ['initial', 'patch'])
@pytest.mark.asyncio
async def test_alias_never_rewrites_semantic_negative(stage, negative):
    package, entry = fixture()
    if negative == 'initial':
        rejected = {**base_verdict(stage, 'calculations', [entry]), 'acceptable': False,
                    'issues': ['The independent exercise is not meaningful.']}
        replies = [rejected]
    else:
        replies = [base_verdict(stage, 'calculations'), {'calculations': [entry],
                    'issues': ['The independent exercise is not meaningful.']}]
    (failures, response, _), client = await execute(stage, package, replies)
    assert failures == ['The independent exercise is not meaningful.']
    assert response.data['acceptable'] is False and response.error is None
    assert client.generate_json.await_count == len(replies)


@pytest.mark.parametrize('stage', ['package', 'lesson'])
@pytest.mark.parametrize('mode,change', [
    ('calculations', {'expression': 'receipts+revenue'}),
    ('calculations', {'expression': 'missing-revenue'}),
    ('calculations', {'claimed_result': 31}),
    ('calculations', {'claim_ids': ['n999']}),
    ('literal_facts', {'datum_ids': ['missing']}),
    ('math_roles', {'source_quote': 'multiply by 2'}),
    ('math_roles', {'field_id': 'missing'}),
])
@pytest.mark.asyncio
async def test_alias_does_not_repair_wrong_arithmetic_operands_claims_or_occurrences(stage, mode, change):
    package, entry = fixture(mode)
    bad = {**entry, **change}
    (failures, response, _), client = await execute(stage, package,
        [base_verdict(stage, mode, [bad]), {mode: [bad]}])
    assert failures and response.error and client.generate_json.await_count == 2


@pytest.mark.parametrize('stage', ['package', 'lesson'])
@pytest.mark.parametrize('mode', ['calculations', 'literal_facts', 'math_roles'])
@pytest.mark.asyncio
async def test_canonical_plus_alias_conflicts_are_not_deduplicated_or_laundered(stage, mode):
    package, alias = fixture(mode)
    canonical = {**alias, 'case_id': 'practice.transfer'}
    if mode == 'calculations': canonical['expression'] = 'receipts+revenue'
    if mode == 'literal_facts': canonical['case_id'] = 'practice.guided'
    # A duplicate role occurrence is invalid even when both identities name the same case.
    entries = [canonical, alias]
    (failures, response, _), client = await execute(stage, package,
        [base_verdict(stage, mode, entries), {mode: entries}])
    assert failures and response.error and client.generate_json.await_count == 2


@pytest.mark.parametrize('stage', ['package', 'lesson'])
@pytest.mark.asyncio
async def test_explicit_wrong_source_equation_still_rejects_after_alias(stage):
    package, entry = fixture()
    package.workbook.activities[1].worked_solution = ('230 - 200 = 31. Explain the accounting distinction using the supplied case.')
    entry['claimed_result'] = 31
    (failures, response, _), client = await execute(stage, package, [base_verdict(stage, 'calculations', [entry])])
    assert failures and any('explicit source equation is incorrect' in error for error in failures)
    assert response.data['acceptable'] is False and response.error is None
    assert client.generate_json.await_count == 1
