"""The new short format is visible through the existing artifact/progress API."""
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.api.v1 import plans
from app.services.llm.schemas import plan_detail_step_model
from app.services.planning.artifact_identity import progressive_ready_step_ids
from app.services.planning.lesson_package import (
    LessonPackage, provenance, validation_identity,
)
from tests.lesson_package_fixtures import package_payload


def tutorial_details(*, ready_count=1, total=8):
    package = LessonPackage.model_validate(package_payload())
    steps = []
    approvals = {}
    for index in range(total):
        step = {
            'id': f'step_{index + 1}', 'lesson_format': 'tutorial_v1',
            'title': f'Apply concept {index + 1}',
            'description': 'Learn one concrete idea, then apply it to a new example.',
            'estimate_minutes': 7, 'reading_minutes': 3, 'practice_minutes': 4,
            'resources': ['Source'],
            'substeps': ['Apply the demonstrated method to the new case, then check your reasoning.'],
            'lesson_content': ' '.join(f'word{n}' for n in range(550)) if index < ready_count else '',
        }
        if index < ready_count:
            step = plan_detail_step_model(step).model_validate(step).model_dump(mode='json')
            approvals[step['id']] = provenance(step, package)
        steps.append(step)
    return {
        'lesson_format': 'tutorial_v1', 'steps': steps,
        'materials': [{'title': 'Source', 'type': 'article', 'url': 'https://example.com/source'}],
        '_generation': {
            'lesson_package_version': 1, 'job_id': '11111111-1111-4111-8111-111111111111',
            'status': 'ready' if ready_count == total else 'partial',
            'ready_step_ids': [step['id'] for step in steps[:ready_count]],
            'validation_identity': validation_identity(), 'lesson_validation': approvals,
        },
    }


def test_api_preserves_complete_tutorial_outline_and_short_ready_content():
    details = tutorial_details()
    parsed = plans._parse_item_details(details)
    assert parsed is not None
    assert parsed.lesson_format == 'tutorial_v1'
    assert len(parsed.steps) == 8
    assert all(step.lesson_format == 'tutorial_v1' for step in parsed.steps)
    assert parsed.steps[0].estimate_minutes == 7
    assert parsed.steps[1].lesson_content == ''
    assert progressive_ready_step_ids(details) == ('step_1',)
    assert plans._partial_lesson_details_available(details)
    assert not plans._lesson_details_meet_quality(details)


def test_completed_tutorial_sequence_meets_readiness_without_legacy_word_floor():
    assert plans._lesson_details_meet_quality(tutorial_details(ready_count=8))


@pytest.mark.parametrize('mutation', ['unapproved', 'changed', 'unknown_format'])
def test_tutorial_marker_never_bypasses_review_or_content_identity(mutation):
    details = tutorial_details()
    if mutation == 'unapproved':
        details['_generation'].pop('lesson_package_version')
    elif mutation == 'changed':
        details['steps'][0]['lesson_content'] += ' unreviewed content'
    else:
        details['steps'][0]['lesson_format'] = 'tutorial_v2'
    assert not plans._partial_lesson_details_available(details)
    assert not plans._lesson_details_meet_quality(details)


def test_unknown_format_cannot_be_emitted_as_a_legacy_lesson():
    details = tutorial_details()
    details['steps'][0]['lesson_format'] = 'unsupported'
    assert plans._parse_item_details(details) is None


@pytest.mark.asyncio
async def test_short_tutorial_completion_still_requires_saved_passed_practice(monkeypatch):
    from app.api.v1 import practice
    from app.services.planning import catalog_lessons
    details = tutorial_details()
    check = AsyncMock()
    monkeypatch.setattr(practice, 'require_practice_complete', check)
    monkeypatch.setattr(catalog_lessons, 'catalog_details_are_ready_in_database', AsyncMock(return_value=True))
    item = SimpleNamespace(id='item-1', details_json=details)
    await plans._require_completion_artifact_ready(
        AsyncMock(), item=item, user_id='user-1', catalog_scope=None,
        selected_step=details['steps'][0],
    )
    assert check.await_count == 1
    assert check.await_args.args[3]['id'] == 'step_1'


@pytest.mark.asyncio
async def test_not_yet_prepared_tutorial_cannot_complete(monkeypatch):
    from app.api.v1 import practice
    check = AsyncMock()
    monkeypatch.setattr(practice, 'require_practice_complete', check)
    details = tutorial_details()
    item = SimpleNamespace(id='item-1', details_json=details)
    with pytest.raises(HTTPException) as error:
        await plans._require_completion_artifact_ready(
            AsyncMock(), item=item, user_id='user-1', catalog_scope=None,
            selected_step=details['steps'][1],
        )
    assert getattr(error.value, 'status_code', None) == 409
    check.assert_not_awaited()
