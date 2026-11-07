"""A keyed choice must not contradict its paired, permissive text rubric."""
import copy
import json
from pathlib import Path
from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError

from app.services.planning.activity_draft import (
    LessonActivityDraft, TutorialActivityDraft, activity_repair_reference,
    parse_activity_draft, parse_activity_repair_draft,
)
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import review_package


RECORDED = json.loads((Path(__file__).parent / 'fixtures' / 'tutorial_response_pairing.json').read_text())
PUBLIC_CASE = {'id': 'bus_lane', 'data': [], 'results': [], 'assumptions': (
    'Original fictional example: The transport office should trial a bus lane and see if it helps. '
    'The office is a named actor and the trial is an action. No result or continuation rule is '
    'stated, so a revision should define a measurable outcome and a decision threshold.'
)}


def package():
    return LessonPackage.model_validate({'teaching_cases': [PUBLIC_CASE], 'workbook': copy.deepcopy(RECORDED)})


def raw_draft():
    return activity_repair_reference(package().workbook.activities[0])


def merged_draft():
    raw = raw_draft()
    raw['fields'] = [raw['fields'][1]]
    raw['fields'][0]['label'] = 'Name and justify your first revision target in one sentence'
    raw['instructions'] = raw['instructions'].replace(
        'First choose which element is weakest. Then write one sentence naming that element as your first revision target and why it is weak.',
        'Write one sentence naming your first revision target and why it is weak. '
        'Accept either a justified actor gap or the missing success decision rule.'
    )
    return raw


def test_exact_capture_accepts_actor_in_text_but_keys_the_paired_choice_to_success():
    original = package()
    guided = original.workbook.activities[0]
    assert guided.fields[0].id == 'weakest_element'
    assert guided.fields[0].correct_choice == 'success'
    assert "vagueness of 'the town' as an actor" in guided.fields[1].criteria[1]
    assert 'An answer naming the actor is also acceptable' in guided.worked_solution.steps[1].explanation
    assert 'the two measures are in different units' in guided.instructions
    # Stored historical workbooks remain readable; the new tutorial boundary is stricter.
    assert LessonPackage.model_validate(original.model_dump(mode='json')) == original
    LessonActivityDraft.model_validate(raw_draft())


@pytest.mark.parametrize('kind', ['choice', 'multi_choice'])
def test_tutorial_generation_and_repair_reject_both_discrete_choice_pairings(kind):
    raw = raw_draft()
    if kind == 'multi_choice':
        raw['fields'][0]['kind'] = 'multi_choice'
        raw['fields'][0]['correct_choices'] = [raw['fields'][0].pop('correct_choice')]
    LessonActivityDraft.model_validate(raw)
    parse_activity_repair_draft(raw)  # legacy repair retains its original contract
    with pytest.raises(ValidationError):
        TutorialActivityDraft.model_validate(raw)
    with pytest.raises(ValidationError):
        parse_activity_repair_draft(raw, tutorial=True)


def test_truly_independent_choice_and_text_is_also_rejected_by_the_format_boundary():
    raw = raw_draft()
    raw['instructions'] = (
        'First identify the season explicitly stated in this supplied sentence: The library opens in winter. '
        'Independently write a justified revision target for the Sunday claim quoted below. '
        + raw['instructions']
    )
    raw['fields'][0].update(label='Which season is explicitly stated?',
        choices=[{'id': 'winter', 'label': 'Winter'}, {'id': 'summer', 'label': 'Summer'}],
        correct_choice='winter', rubric_criterion='Identifies the explicitly supplied season',
        explanation='The supplied sentence explicitly states winter, so no learner-written answer determines this key.')
    LessonActivityDraft.model_validate(raw)
    with pytest.raises(ValidationError):
        TutorialActivityDraft.model_validate(raw)


@pytest.mark.parametrize('shape', ['choice_only', 'multi_choice_only', 'text_only', 'number_and_text'])
def test_supported_response_shapes_remain_valid(shape):
    raw = raw_draft()
    if shape == 'text_only':
        raw = merged_draft()
    elif shape == 'number_and_text':
        raw['data'] = [{'id': 'quantity', 'label': 'Supplied quantity', 'value': 2, 'unit': 'm'}]
        raw['fields'][0] = {
            'id': 'double', 'kind': 'number', 'label': 'Double the supplied length',
            'expression': 'quantity * 2', 'unit': 'm', 'rubric_criterion': 'Doubles the supplied length',
            'explanation': 'Multiply the supplied length by two, retaining the length unit.',
        }
    else:
        raw['fields'] = raw['fields'][:1]
        if shape == 'multi_choice_only':
            raw['fields'][0]['kind'] = 'multi_choice'
            raw['fields'][0]['correct_choices'] = [raw['fields'][0].pop('correct_choice')]
    valid = TutorialActivityDraft.model_validate(raw)
    assert parse_activity_repair_draft(raw, tutorial=True) == parse_activity_draft(valid)


def test_provider_schema_exposes_the_pairing_prohibition():
    schema = TutorialActivityDraft.model_json_schema()
    fields = schema['properties']['fields']
    serialized = json.dumps(fields)
    assert '"not"' in serialized and '"allOf"' in serialized
    assert '"choice"' in serialized and '"multi_choice"' in serialized and '"text"' in serialized


def test_provider_json_schema_validates_the_same_allowed_and_disallowed_pairs():
    jsonschema = pytest.importorskip('jsonschema')
    schema = TutorialActivityDraft.model_json_schema()
    jsonschema.validate(merged_draft(), schema)
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(raw_draft(), schema)


@pytest.mark.asyncio
async def test_captured_pair_is_rejected_locally_before_review_with_an_activity_target():
    value = package()
    before = value.model_dump(mode='json')

    def forbidden(**kwargs):
        raise AssertionError('Invalid pairing should not incur a provider review')

    failures, response, _ = await review_package(value, {'lesson_format': 'tutorial_v1'}, {},
        client_factory=forbidden)
    assert failures and not response.semantic_accepted
    assert response.effective_parameters['request_count'] == 0
    assert response.effective_parameters['validated_repair_targets'] == ['practice.guided_practice']
    assert value.model_dump(mode='json') == before


def builder_components():
    value = package()
    seed = {
        'workbook_title': value.workbook.title,
        'teaching_cases': [PUBLIC_CASE],
        'activity_briefs': [{'id': activity.id, 'kind': activity.kind, 'scope': activity.instructions}
                            for activity in value.workbook.activities],
    }
    corrected = parse_activity_draft(TutorialActivityDraft.model_validate(merged_draft())).model_dump(mode='json')
    return seed, value, corrected


@pytest.mark.asyncio
async def test_builder_spends_one_existing_correction_to_merge_the_captured_pair(monkeypatch):
    from app.services.planning import package_builder as builder
    from tests.test_staged_package_builder import Factory

    seed, original, corrected = builder_components()
    factory = Factory({
        'seed': [seed],
        'guided_practice': [original.workbook.activities[0].model_dump(mode='json'), corrected],
        'independent_transfer': [original.workbook.activities[1].model_dump(mode='json')],
    })
    monkeypatch.setattr(builder, 'record_llm_response', AsyncMock(return_value=True))
    result, response, _ = await builder.generate_initial_package(
        {'id': 'step_1', 'title': 'Diagnose a claim', 'lesson_format': 'tutorial_v1'}, {}, client_factory=factory)
    assert result and not response.error
    assert [field.kind for field in result.workbook.activities[0].fields] == ['text']
    assert factory.counts == {'seed': 1, 'guided_practice': 2, 'independent_transfer': 1}
    assert response.effective_parameters['shared_correction_used'] is True
    assert 'actor is also acceptable' in result.workbook.activities[0].worked_solution.steps[0].explanation


def test_cached_semantic_approval_cannot_bypass_the_current_pairing_boundary():
    from app.services.planning.package_preflight import _PreflightState, _identity, validate_preflight_state

    value = package()
    outline = {'lesson_format': 'tutorial_v1'}
    saved = _PreflightState(**_identity(value, outline, {}), semantic={
        'acceptable': True, 'issues': [],
    }).model_dump(mode='json')
    with pytest.raises(ValueError, match='cannot combine choice/multi_choice with text'):
        validate_preflight_state(saved, package=value, outline=outline, context={})


@pytest.mark.asyncio
async def test_saved_builder_components_cannot_publish_the_historical_pair():
    from app.services.planning import package_builder as builder
    from tests.test_staged_package_builder import snapshot

    seed, original, _ = builder_components()
    saved = snapshot(seed, {activity.id: activity.model_dump(mode='json')
                            for activity in original.workbook.activities})

    def forbidden(**kwargs):
        raise AssertionError('Invalid saved components must be rejected before provider work')

    result, response, _ = await builder.generate_initial_package(
        {'id': 'step_1', 'lesson_format': 'tutorial_v1'}, {},
        client_factory=forbidden, existing_parts=saved)
    assert result is None and response.error == 'Saved package components failed validation'
    assert response.effective_parameters['component_requests'] == 0
