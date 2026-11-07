"""Recover only redundant wrong-kind audits; distinguish permissions from demands."""
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
    PackageSemanticReview, _choice_fields, _text_fields, _choice_audit_issues, _text_audit_issues,
    _normalize_semantic_audit_kinds, _semantic_model, _SEMANTIC_PROMPT, review_package,
)


RECORDED = json.loads((Path(__file__).parent / 'fixtures' / 'semantic_audit_kind_recovery.json').read_text())


def normalize(name='misplaced_complete', mutate=None):
    fixture = RECORDED[name]
    package = LessonPackage.model_validate(fixture['package'])
    data = copy.deepcopy(fixture['verdict'])
    if mutate:
        mutate(data)
    before = copy.deepcopy(data)
    normalized, count = _normalize_semantic_audit_kinds(data, set(_choice_fields(package)), set(_text_fields(package)))
    assert data == before
    return package, normalized, count


@pytest.mark.parametrize('name', ['misplaced_incomplete', 'misplaced_complete'])
def test_captured_wrong_kind_entry_is_removed_only_with_proper_audit_present(name):
    package, normalized, count = normalize(name)
    assert count == 1
    assert [audit['target'] for audit in normalized['choice_audits']] == ['practice.classify_practice.classifications']
    verdict = PackageSemanticReview.model_validate(normalized)
    assert not _choice_audit_issues(package, verdict.choice_audits)
    assert len(verdict.text_audits) == 2
    if name == 'misplaced_complete':
        assert not _text_audit_issues(package, verdict.text_audits)
    else:
        # Old false judgments are not silently reinterpreted by normalization.
        assert _text_audit_issues(package, verdict.text_audits)


@pytest.mark.parametrize('fault', ['missing_proper', 'unknown', 'same_kind_duplicate', 'invalid_proper'])
def test_kind_cleanup_never_fills_missing_coverage_or_discards_unknowns(fault):
    def mutate(data):
        if fault == 'missing_proper': data['text_audits'].pop(0)
        elif fault == 'unknown': data['choice_audits'][1]['target'] = 'practice.unknown.field'
        elif fault == 'same_kind_duplicate': data['choice_audits'][1] = copy.deepcopy(data['choice_audits'][0])
        else: data['text_audits'][0]['criteria'].pop()
    package, normalized, count = normalize(mutate=mutate)
    assert count == (1 if fault == 'invalid_proper' else 0)
    with pytest.raises(ValueError):
        verdict = PackageSemanticReview.model_validate(normalized)
        _choice_audit_issues(package, verdict.choice_audits)
        _text_audit_issues(package, verdict.text_audits)


def test_permissive_rubric_rule_is_task_aligned_without_being_a_learner_requirement():
    fixture = RECORDED['permissive']
    package = LessonPackage.model_validate(fixture['package'])
    old = PackageSemanticReview.model_validate(fixture['verdict'])
    assert _text_audit_issues(package, old.text_audits)  # Never flip a recorded false judgment.
    explicit = copy.deepcopy(fixture['verdict'])
    permissions = 0
    for audit in explicit['text_audits']:
        for item in audit['criteria']:
            old_required = item.pop('required_by_task')
            if not old_required:
                assert item['accepts_alternative'] and 'Tolerance' in item['reason']
                permissions += 1
            # A fresh reviewer can now affirm alignment of these permissions
            # without falsely claiming every response must exercise them.
            item['task_aligned'] = True
    assert permissions == 2
    reviewed = PackageSemanticReview.model_validate(explicit)
    assert not _text_audit_issues(package, reviewed.text_audits)
    reviewed.text_audits[0].criteria[0].task_aligned = False
    assert _text_audit_issues(package, reviewed.text_audits)  # Extraneous demands still block.


def test_provider_schema_names_alignment_and_bounds_each_audit_inventory():
    schema = _semantic_model({'package'}, {'practice.a.choice'}, {'practice.a.text', 'practice.b.text'}).model_json_schema()
    criterion = schema['$defs']['TextCriterionAudit']
    assert 'task_aligned' in criterion['required'] and 'required_by_task' not in criterion['properties']
    assert schema['properties']['choice_audits']['maxItems'] == 1
    assert schema['properties']['text_audits']['maxItems'] == 2
    assert 'not mandatory in every response' in _SEMANTIC_PROMPT
    assert 'preserving genuinely valid optional paths' in _SEMANTIC_PROMPT


@pytest.mark.asyncio
async def test_recorded_complete_substantive_audits_pass_without_buying_another_request(monkeypatch):
    fixture = RECORDED['misplaced_complete']
    raw = copy.deepcopy(fixture['package'])
    # Isolate wrong-kind audit recovery from the newer tutorial pairing restriction.
    # Preserve the original text target and its redundant wrong-kind audit.
    guided = raw['workbook']['activities'][0]
    guided['fields'] = guided['fields'][1:]
    guided['instructions'] = guided['instructions'].split('Classify each item.')[0] + (
        'For Item B, explain what a reader would have to reject to disagree. '
        'Distinguish what the sentence names from what it asserts, accepting a reasoned interpretation.'
    )
    guided['worked_solution'] = guided['worked_solution'].split(
        'For the item you labeled a claim, what would a reader have to reject to disagree? One or two sentences.\n\n', 1
    )[1]
    package = LessonPackage.model_validate(raw)
    verdict = copy.deepcopy(fixture['verdict'])
    verdict['choice_audits'] = verdict['choice_audits'][1:]
    assert verdict['choice_audits'][0]['target'] == verdict['text_audits'][0]['target']
    verdict['teaching_case_audits'] = [{'target': 'teaching.bus_lane_example',
        'core_inference': 'Subject phrase differs from assertion and assertion plus reason.',
        'quantities_and_units': 'Traffic outcomes are asserted qualitatively; no numerical conversion.',
        'decision_rule': 'Determine whether the sentence asserts a rejectable proposition.',
        'semantically_valid': True,
        'reason': 'Classifies assertions without establishing that the traffic cause is true.'}]
    provider_response = LLMResponse(data=verdict, finish_reason='stop')
    client = SimpleNamespace(generate_json=AsyncMock(return_value=provider_response))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'}, {},
        client_factory=lambda **kwargs: client)
    assert not failures and not response.error and response.semantic_accepted
    assert client.generate_json.await_count == 1
    assert provider_response.effective_parameters['normalized_audit_kind_count'] == 1
    assert response.effective_parameters['requested_output_tokens'] == SEMANTIC_TOKENS

