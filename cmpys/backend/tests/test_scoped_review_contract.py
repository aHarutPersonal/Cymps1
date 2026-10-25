"""The reviewer gets precise source IDs and quotes without fabricated evidence."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.core.config import settings
from app.services.llm.client import LLMResponse
from app.services.planning.lesson_review import (
    MathRoleCheck, PackagedLessonReview, ReviewEvidencePatch, _math_role_diagnostic,
    math_quote_candidates, scoped_review_model,
)
from app.services.planning.package_review import (
    PackageReview, _evidence_patch_request, _merge_evidence_patch,
    package_review_payload, review_package,
)
from tests.test_geometry_evidence_roles import triangle_package
from tests.test_json_generation_errors import client_for
from tests.test_openlux import chunk, transport


def assert_ids(schema, expected):
    assert schema['$defs']['SourceClaimId']['enum'] == expected
    reference = {'$ref': '#/$defs/SourceClaimId'}
    assert schema['properties']['literal_fact_ids']['items'] == reference
    assert schema['$defs']['PackagedCalculationCheck']['properties']['claim_ids']['items'] == reference
    for name in ('MathRoleCheck', 'LiteralFactCheck'):
        assert schema['$defs'][name]['properties']['claim_id'] == reference


@pytest.mark.parametrize('base', [PackageReview, PackagedLessonReview, ReviewEvidencePatch])
def test_scoped_schema_constrains_every_source_reference_without_global_mutation(base):
    original = copy.deepcopy(base.model_json_schema())
    one = scoped_review_model(base, {'n1': 'A source with a number.'})
    two = scoped_review_model(base, {'n2': 'A different source.'})
    assert one.__name__ == base.__name__ and issubclass(one, base)
    assert_ids(one.model_json_schema(), ['n1'])
    assert_ids(two.model_json_schema(), ['n2'])
    assert_ids(one.model_json_schema(), ['n1'])
    assert base.model_json_schema() == original


def test_number_free_schema_requires_empty_evidence_without_invalid_empty_enums():
    schema = scoped_review_model(PackageReview, {}).model_json_schema()
    for field in ('calculations', 'literal_facts', 'literal_fact_ids', 'math_roles'):
        assert schema['properties'][field]['maxItems'] == 0
    assert '"enum": []' not in json.dumps(schema)


@pytest.mark.parametrize('provider', ['zai', 'openlux'])
@pytest.mark.asyncio
async def test_actual_offline_transport_receives_scoped_schema(provider, monkeypatch):
    monkeypatch.setattr(settings, 'llm_admission_limits', {})
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())
    client = client_for(provider)
    stream, request = transport(monkeypatch, client, [chunk('{"acceptable":false,"issues":["Transfer merely recalls the public answer."]}', 'stop')])
    model = scoped_review_model(PackageReview, {'n4': 'A numeric source.'})
    response = await client.generate_json('Review independently', 'Reference package', output_model=model)
    assert response.error is None and response.data['acceptable'] is False
    prompt = request['messages'][0]['content']
    schema = json.loads(prompt[prompt.index('{'):])
    assert_ids(schema, ['n4'])
    assert stream.closed and request['stream'] is True


@pytest.mark.parametrize('source,quote', [
    ('Area = (b × h) / 2.', '(b × h) / 2'),
    ('Մակերեսը = (հիմք × բարձրություն) / 2։', '(հիմք × բարձրություն) / 2'),
    ('Area = base * height / 2.', 'base * height / 2'),
])
def test_candidates_copy_only_exact_complete_expression_from_assignment(source, quote):
    candidate = math_quote_candidates({'n1': source})['n1'][0]
    assert candidate['source_quote'] == quote and quote in source
    assert candidate['requires_semantic_binding'] is True
    assert set(candidate) == {'source_quote', 'source_symbols', 'role', 'requires_semantic_binding'}


@pytest.mark.parametrize('source', [
    'Area = height * (b × h) / 2.',
    'Area = (b × h) / 2 * height.',
    'Area = sqrt((b × h) / 2).',
    'Area = (b × h) / 2%.',
    'Area = (b × h) / 2 hundred.',
    'Use (b × h) / 2, then repeat (b × h) / 2.',
    '162 / 2 = 81.',  # Numeric claims are not synthesized into symbolic roles.
])
def test_incomplete_scaled_or_repeated_quotes_are_not_offered(source):
    assert math_quote_candidates({'n1': source}) == {}


def test_candidate_is_not_a_math_approval_or_an_invented_variable_binding():
    source = 'Area = (cost × revenue) / 2.'
    candidate = math_quote_candidates({'n1': source})['n1'][0]
    package = triangle_package(source)
    owner = package.review_context()['private_workbook']['activities'][0]
    role = MathRoleCheck(claim_id='n1', case_id='practice.guided', field_id='area',
        role='symbolic_formula', coefficient=2, source_quote=candidate['source_quote'],
        symbol_bindings={'cost': 'missing', 'revenue': 'height'})
    interval, reason = _math_role_diagnostic(role, source, owner, owner, set())
    assert interval is None and 'raw datum IDs' in reason


@pytest.mark.parametrize('change,reason', [
    ({'source_quote': '(wrong × quote) / 2'}, 'verbatim'),
    ({'source_quote': 'Area = (b × h) / 2'}, 'omit assignment'),
    ({'field_id': 'missing'}, 'canonical numeric field'),
    ({'symbol_bindings': {'b': 'height', 'h': 'base'}}, 'AST differs'),
])
def test_role_errors_explain_the_exact_correction_without_echoing_source(change, reason):
    source = 'Area = (b × h) / 2.'
    package = triangle_package(source)
    owner = package.review_context()['private_workbook']['activities'][0]
    role = MathRoleCheck.model_validate({
        'claim_id': 'n1', 'case_id': 'practice.guided', 'field_id': 'area',
        'role': 'symbolic_formula', 'coefficient': 2, 'source_quote': '(b × h) / 2',
        'symbol_bindings': {'b': 'base', 'h': 'height'}, **change})
    interval, diagnostic = _math_role_diagnostic(role, source, owner, owner, set())
    assert interval is None and reason in diagnostic
    assert source not in diagnostic and role.source_quote not in diagnostic


def test_scoped_patch_candidates_and_schema_exclude_unaffected_claims():
    package = triangle_package('Area = (b × h) / 2.\nArea = (base × height) / 2.')
    payload = package_review_payload(package, {}, {})
    verdict = PackageReview(acceptable=True, issues=[], literal_fact_ids=['n1', 'n2'])
    request, scope = _evidence_patch_request(verdict, payload, ['n2: invalid role'])
    body = json.loads(request['user_prompt'])
    assert scope == {'n2'}
    assert set(body['numeric_spans']) == set(body['math_quote_candidates']) == {'n2'}
    assert_ids(request['output_model'].model_json_schema(), ['n2'])
    with pytest.raises(ValueError, match='Unrequested'):
        _merge_evidence_patch(verdict, ReviewEvidencePatch(literal_fact_ids=['base']), scope, payload['numeric_spans'])


@pytest.mark.asyncio
async def test_transfer_semantic_rejection_is_terminal_with_scoped_schema(monkeypatch):
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())
    package = triangle_package('Area = (b × h) / 2.')
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data={
        'acceptable': False, 'issues': ['Transfer merely recalls the public answer.'],
        'literal_fact_ids': ['base'],  # Invalid proof cannot override a negative semantic verdict.
    })))
    failures, response, _ = await review_package(package, {}, {}, client_factory=lambda **kw: client)
    assert failures == ['Transfer merely recalls the public answer.']
    assert response.data['acceptable'] is False and client.generate_json.await_count == 1
    assert 'genuinely new conditions' in client.generate_json.call_args.kwargs['system_prompt']


def test_quote_candidate_payload_is_bounded_and_never_copies_large_source_blocks():
    spans = {f'n{index}': f'Area = (base_{index} × height_{index}) / 2.' for index in range(100)}
    candidates = math_quote_candidates(spans)
    assert sum(map(len, candidates.values())) <= 12
    assert len(json.dumps(candidates, ensure_ascii=False, separators=(',', ':')).encode('utf-8')) <= 6000
    assert all(len(item['source_quote']) <= 240 for items in candidates.values() for item in items)
    assert all(len(items) <= 2 for items in candidates.values())


@pytest.mark.parametrize('name', ['sqrt', 'cos', 'custom', 'Use'])
@pytest.mark.parametrize('space', ['', ' '])
def test_function_argument_is_never_a_complete_symbolic_candidate_or_proof(name, space):
    source = f'Area = {name}{space}(b * h) / 2.'
    assert math_quote_candidates({'n1': source}) == {}
    owner = triangle_package(source).review_context()['private_workbook']['activities'][0]
    role = MathRoleCheck(claim_id='n1', case_id='practice.guided', field_id='area',
        role='symbolic_formula', coefficient=2, source_quote='(b * h) / 2',
        symbol_bindings={'b': 'base', 'h': 'height'})
    interval, reason = _math_role_diagnostic(role, source, owner, owner, set())
    assert interval is None and 'subexpression' in reason
