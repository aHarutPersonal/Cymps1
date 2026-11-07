"""A valid captured rejection must survive an incomplete optional text audit."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError

from app.services.llm.client import LLMResponse
from app.services.llm.prompt_loader import load_and_render
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import (
    PackageSemanticReview, _parse_semantic_verdict, _targets, _SEMANTIC_PROMPT, review_package,
)


FIXTURE = json.loads((Path(__file__).parent / 'fixtures' / 'incomplete_negative_text_audit.json').read_text())
TARGET = 'practice.guided_classify.classify_and_cue'


def test_captured_negative_has_complete_actionable_issue_but_partial_optional_audit():
    value = copy.deepcopy(FIXTURE['verdict'])
    with pytest.raises(ValidationError) as error:
        PackageSemanticReview.model_validate(value)
    assert error.value.errors()[0]['loc'] == ('text_audits', 1, 'requires_activity_repair')
    package = LessonPackage.model_validate(FIXTURE['package'])
    parsed = _parse_semantic_verdict(value, _targets(package))
    assert parsed.acceptable is False
    assert [issue.model_dump() for issue in parsed.issues] == [dict(issue, severity='blocking') for issue in value['issues']]
    assert parsed.issues[0].target == TARGET and parsed.text_audits == []
    assert value == FIXTURE['verdict']


@pytest.mark.parametrize('mutation', ['positive', 'outline_only', 'unknown_target', 'missing_description', 'extra_root'])
def test_partial_audit_cannot_approve_or_broaden_an_invalid_diagnostic(mutation):
    value = copy.deepcopy(FIXTURE['verdict'])
    if mutation == 'positive': value.update(acceptable=True, issues=[])
    elif mutation == 'outline_only': value['issues'][0]['target'] = 'outline'
    elif mutation == 'unknown_target': value['issues'][0]['target'] = 'practice.unrelated.field'
    elif mutation == 'missing_description': value['issues'][0].pop('description')
    elif mutation == 'extra_root': value['override'] = 'approve everything'
    with pytest.raises(ValueError):
        _parse_semantic_verdict(value, _targets(LessonPackage.model_validate(FIXTURE['package'])))


@pytest.mark.asyncio
async def test_actual_negative_response_authorizes_only_original_field_without_retry(monkeypatch):
    raw = copy.deepcopy(FIXTURE['package'])
    # Keep the exact rejected field and diagnostic; remove only its unrelated
    # parallel choice so the current format guard does not mask this parser test.
    guided = raw['workbook']['activities'][0]
    guided['fields'] = guided['fields'][1:]
    assert guided['fields'][0] == FIXTURE['package']['workbook']['activities'][0]['fields'][1]
    guided['instructions'] = guided['instructions'].replace(
        'First, select every statement that commits its writer to a position a reader could reject. Then, in the text field, classify',
        'In the text field, classify'
    )
    guided['worked_solution'] = guided['worked_solution'].split(
        'Classify each of the four statements and name the cue that decided the hardest one\n\n', 1
    )[1]
    package = LessonPackage.model_validate(raw)
    client = SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(
        data=copy.deepcopy(FIXTURE['verdict']), finish_reason='stop')))
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock(return_value=True))
    snapshots = []

    async def save(state): snapshots.append(copy.deepcopy(state))

    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'}, {},
        client_factory=lambda **kwargs: client, on_review=save)
    assert failures and not response.error and not response.semantic_accepted
    assert response.effective_parameters['validated_repair_targets'] == [TARGET]
    assert snapshots[-1]['semantic']['issues'] == [dict(issue, severity='blocking') for issue in FIXTURE['verdict']['issues']]
    assert client.generate_json.await_count == 1
    assert 'known negative review lacked' not in ' '.join(failures)


def test_self_check_feedback_uses_actual_failure_criterion_not_an_external_reader_requirement():
    recorded = json.loads((Path(__file__).parent / 'fixtures' / 'self_check_criterion_activity.json').read_text())
    assert 'one check that could expose a mistake' in recorded['instructions']
    explanation = recorded['fields'][0]['explanation']
    assert 'no result of his check could expose a mistake' in explanation
    assert 'outside-reader summary test' in explanation
    for instruction in (
        "task's actual stated requirements", 'If the attempt passes, say that it passes',
        'public teaching case and private model answer',
        'need not detect every error or use an outside reader',
        'Rereading can reveal contradictions', 'missing test criterion or observable failure condition',
    ):
        assert instruction in _SEMANTIC_PROMPT
    for name in ('tutorial_package_seed.txt', 'tutorial_activity_generate.txt',
                 'lesson_package_seed.txt', 'lesson_activity_generate.txt', 'lesson_package_generate.txt'):
        prompt = load_and_render(name, {})
        if name.startswith('tutorial_'):
            assert 'Assess stated requirements, not future learning needs' in prompt
        else:
            assert 'needs no invented gap' in prompt

