import copy
import json
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.planning import package_builder as builder
from tests.test_staged_package_builder import Factory, components, run
from tests.section_client_fixture import activity_draft_fixture


def merged_seed(seed):
    raw = json.dumps(seed)
    groups = ','.join(json.dumps(brief)[1:-1] for brief in seed['activity_briefs'])
    return raw[:raw.index('"activity_briefs"')] + '"activity_briefs":[{' + groups + '}]}'


def response(raw):
    return LLMResponse(data={}, raw_response=raw, finish_reason='stop',
        error='zai request failed (JSONProtocolError; finish=stop)',
        effective_parameters={'json_protocol_error': 'duplicate_property'})


@pytest.mark.parametrize('count', [2, 3, 6])
def test_complete_brief_groups_are_split_without_losing_or_rewriting_values(count):
    seed, _ = components(count)
    result = builder._recover_grouped_seed_briefs(response(merged_seed(seed)))
    assert result.model_dump(mode='json') == builder.LessonPackageSeed.model_validate(seed).model_dump(mode='json')


@pytest.mark.parametrize('defect', ['root_duplicate', 'extra', 'reordered', 'missing', 'same_identity', 'invalid_kind', 'too_many', 'truncated', 'ordinary_json', 'nonfinite'])
def test_ambiguous_or_invalid_seed_is_never_salvaged(defect):
    seed, _ = components(7 if defect == 'too_many' else 2)
    if defect == 'same_identity': seed['activity_briefs'][1]['id'] = seed['activity_briefs'][0]['id']
    if defect == 'invalid_kind': seed['activity_briefs'][1]['kind'] = 'practice'
    raw = merged_seed(seed)
    if defect == 'root_duplicate': raw = raw.replace('"workbook_title":', '"workbook_title":"replacement","workbook_title":', 1)
    if defect == 'extra': raw = raw.replace('"kind":', '"extra":true,"kind":', 1)
    if defect == 'reordered': raw = raw.replace('"id": "guided", "kind": "practice"', '"kind": "practice", "id": "guided"', 1)
    if defect == 'missing': raw = raw.replace('"kind": "practice", ', '', 1)
    if defect == 'truncated': raw = raw[:-2]
    if defect == 'ordinary_json': raw = json.dumps(seed)
    if defect == 'nonfinite': raw = raw.replace('"teaching_cases": []', '"teaching_cases": [NaN]')
    assert builder._recover_grouped_seed_briefs(response(raw)) is None


@pytest.mark.asyncio
async def test_lossless_wire_recovery_does_not_spend_another_request_or_skip_package_validation(monkeypatch):
    seed, activities = components()
    recorder = AsyncMock(return_value=True)
    monkeypatch.setattr(builder, 'record_llm_response', recorder)
    factory = Factory({'seed': [response(merged_seed(seed))], **{key: [value] for key, value in activities.items()}})
    package, metadata, _ = await run(factory)
    assert package is not None
    assert factory.counts['seed'] == 1
    assert recorder.await_count == 3
    assert not metadata.effective_parameters['shared_correction_used']
    assert recorder.await_args_list[0].kwargs['response'].effective_parameters['recovered_complete_brief_groups'] == 2


@pytest.mark.asyncio
async def test_single_correction_reports_hidden_aggregate_and_field_errors_together(monkeypatch):
    seed, activities = components()
    bad = activity_draft_fixture(activities['guided'])
    bad['fields'][0]['criteria'] = ['A valid observable criterion.'] * 6
    bad['fields'][0]['explanation'] = 'A complete line of reasoning. ' * 145
    monkeypatch.setattr(builder, 'record_llm_response', AsyncMock(return_value=True))
    factory = Factory({'seed': [seed], 'guided': [bad, activities['guided']], 'transfer': [activities['transfer']]})
    package, _, _ = await run(factory)
    assert package is not None and factory.counts['guided'] == 2
    corrected = next(data for key, _, data in factory.requests if key == 'guided' and 'correction' in data)
    diagnostics = corrected['correction']['validation_errors']
    assert any(error['type'] == 'too_long' and error['loc'][-1] == 'criteria' for error in diagnostics)
    assert any(error['loc'] == ['fields'] and 'TOTAL' in error['message'] for error in diagnostics)
    assert bad['fields'][0]['explanation'] == corrected['correction']['rejected_component']['fields'][0]['explanation']
