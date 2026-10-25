"""Offline regressions for actionable failures without private-content logging."""
import copy
import json
from dataclasses import asdict
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock

import pytest
from pydantic import BaseModel, ValidationError, field_validator
from pydantic_core import PydanticCustomError

from app.services.llm.telemetry import usage_record_from_response
from app.services.planning import package_builder as builder
from app.services.planning.activity_draft import LessonActivityDraft
from tests.test_activity_draft import draft_payload
from tests.test_component_draft_repair import draft
from tests.test_json_generation_errors import client_for
from tests.test_openlux import chunk, transport
from tests.test_staged_package_builder import Factory, components, run


def test_aggregate_solution_limit_is_reported_on_the_actual_authoring_field():
    payload = draft_payload()
    payload['fields'] = payload['fields'][:2]
    for field in payload['fields']:
        field['explanation'] = 'Private model reasoning. ' * 100
    before = copy.deepcopy(payload)
    with pytest.raises(ValidationError) as caught:
        LessonActivityDraft.model_validate(payload)
    failures = caught.value.errors(include_input=False, include_context=False)
    assert [failure['loc'] for failure in failures] == [('fields',)]
    assert '40 to 4000' in failures[0]['msg']
    assert 'worked_solution' not in str(failures)
    assert payload == before


@pytest.mark.parametrize('total, accepted', [(39, False), (40, True), (4000, True), (4001, False)])
def test_wire_aggregate_limits_match_persisted_solution_limits(total, accepted):
    payload = draft_payload()
    if total < 40:
        payload['fields'] = payload['fields'][:1]
        payload['fields'][0]['explanation'] = 'x' * total
    else:
        payload['fields'] = payload['fields'][:2]
        payload['fields'][0]['explanation'] = 'x' * 20
        payload['fields'][1]['explanation'] = 'x' * (total - 20)
    if accepted:
        LessonActivityDraft.model_validate(payload)
    else:
        with pytest.raises(ValidationError):
            LessonActivityDraft.model_validate(payload)


@pytest.mark.asyncio
async def test_bounded_correction_uses_wire_path_and_persists_only_safe_codes(monkeypatch):
    seed, activities = components()
    invalid = draft(activities['guided'])
    invalid['fields'].append({**copy.deepcopy(invalid['fields'][0]), 'id': 'revision_evidence'})
    for field in invalid['fields']:
        field['explanation'] = 'PRIVATE_GENERATED_REASONING ' * 100
    records = []
    async def record(**kwargs):
        records.append(usage_record_from_response(**kwargs))
        return True
    monkeypatch.setattr(builder, 'record_llm_response', record)
    factory = Factory({'seed': [seed], 'guided': [invalid, draft(activities['guided'])],
                       'transfer': [draft(activities['transfer'])]})
    package, response, _ = await run(factory)
    assert package is not None and response.error is None
    corrections = [data['correction'] for key, _, data in factory.requests if key == 'guided' and 'correction' in data]
    assert len(corrections) == 1
    assert corrections[0]['rejected_component'] == invalid
    assert corrections[0]['validation_errors'][0]['loc'] == ['fields']
    assert sum(factory.counts.values()) == 4 and len(records) == 4
    failures = [record.metadata['effective_parameters']['component_validation'] for record in records
                if 'component_validation' in record.metadata.get('effective_parameters', {})]
    assert failures == [{'errors': [{'type': 'value_error', 'loc': ['fields']}], 'total_errors': 1}]
    serialized = json.dumps([asdict(record) for record in records])
    assert 'PRIVATE_GENERATED_REASONING' not in serialized
    assert 'rejected_component' not in serialized
    assert 'validation_errors' not in serialized
    for _, _, data in factory.requests:
        assert data['execution_contract']['mode'] == 'self_contained_in_app'
        assert 'simulated' in data['execution_contract']['missing_feedback']
        assert 'independently' in data['execution_contract']['activity_isolation']


def test_diagnostics_hide_unknown_keys_input_values_messages_and_context():
    payload = draft_payload()
    payload['PRIVATE_PROPERTY_NAME'] = 'PRIVATE_INPUT_VALUE'
    payload['fields'][0]['PRIVATE_NESTED_KEY'] = 'PRIVATE_NESTED_VALUE'
    with pytest.raises(ValidationError) as caught:
        LessonActivityDraft.model_validate(payload)
    metadata = builder._validation_failure_metadata(caught.value, LessonActivityDraft)
    assert metadata['total_errors'] == 2
    assert all(error['loc'][-1] == '<unknown>' for error in metadata['errors'])
    assert 'PRIVATE_' not in json.dumps(metadata)


def test_diagnostics_redact_arbitrary_custom_error_codes_and_messages():
    class TestModel(BaseModel):
        value: str
        @field_validator('value')
        @classmethod
        def fail(cls, value):
            raise PydanticCustomError('PRIVATE_CUSTOM_CODE', 'PRIVATE_MESSAGE {value}', {'value': value})
    with pytest.raises(ValidationError) as caught:
        TestModel.model_validate({'value': 'PRIVATE_INPUT'})
    metadata = builder._validation_failure_metadata(caught.value, TestModel)
    assert metadata == {'errors': [{'type': 'component_contract', 'loc': ['value']}], 'total_errors': 1}
    assert 'PRIVATE_' not in json.dumps(metadata)


def test_diagnostics_are_bounded_for_many_unknown_fields():
    payload = {f'PRIVATE_KEY_{i}': 'PRIVATE_VALUE' for i in range(100)}
    with pytest.raises(ValidationError) as caught:
        LessonActivityDraft.model_validate(payload)
    metadata = builder._validation_failure_metadata(caught.value, LessonActivityDraft)
    assert len(metadata['errors']) == 16
    assert metadata['total_errors'] > 100
    assert 'PRIVATE_' not in json.dumps(metadata)


@pytest.mark.asyncio
@pytest.mark.parametrize('provider', ['zai', 'openlux'])
@pytest.mark.parametrize('raw, code', [
    ('{"PRIVATE_KEY":"PRIVATE_VALUE","PRIVATE_KEY":2}', 'duplicate_property'),
    ('{"value":NaN}', 'non_finite_number'),
    ('[]', 'non_object_document'),
    ('  ', 'empty_document'),
    ('{"value":', 'invalid_json_syntax'),
])
async def test_real_collector_reports_precise_safe_protocol_category(monkeypatch, provider, raw, code):
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    client = client_for(provider)
    usage = NS(prompt_tokens=31, completion_tokens=47, total_tokens=78)
    stream, _ = transport(monkeypatch, client, [chunk(raw, 'stop'), NS(choices=[], usage=usage)])
    response = await client.generate_json('System', 'User')
    assert response.data == {} and response.error and not response.json_valid
    assert response.total_tokens == 78 and stream.closed
    assert response.effective_parameters['json_protocol_error'] == code
    diagnostics = builder._provider_correction_diagnostics(response)
    assert diagnostics[0]['code'] == code
    record = usage_record_from_response(operation='offline', response=response)
    assert 'PRIVATE_' not in json.dumps(asdict(record))
    assert 'PRIVATE_' not in json.dumps(diagnostics)
    assert response.retryable is None


def test_arbitrary_provider_metadata_cannot_inject_correction_instructions():
    from app.services.llm.client import LLMResponse
    response = LLMResponse(data={}, effective_parameters={'json_protocol_error': 'PRIVATE_INSTRUCTION'})
    diagnostics = builder._provider_correction_diagnostics(response)
    assert 'code' not in diagnostics[0]
    assert 'PRIVATE_' not in json.dumps(diagnostics)
