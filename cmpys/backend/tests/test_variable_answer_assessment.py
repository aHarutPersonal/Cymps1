"""Replay the local writing tutorial's invalid key and failed field conversion.

Only synthetic activity data from the local QA capture is retained; no account,
provider, request context or usage metadata is part of the fixture.
"""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.prompt_loader import load_and_render
from app.services.planning.activity_draft import parse_activity_repair_draft
from app.services.planning.lesson_package import (
    ActivityRepairScopeReview, LessonPackage, TeachingCase, generate_package,
)
from app.services.planning.package_builder import LessonPackageSeed
from app.services.planning.package_preflight import _SEMANTIC_PROMPT
from tests.lesson_package_fixtures import package_payload


RECORDING = json.loads((Path(__file__).parent / 'fixtures' / 'variable_answer_assessment.json').read_text())
TARGET = 'practice.transfer_narrowing'
FIELD_TARGET = TARGET + '.first_challenge'


def original_package():
    payload = package_payload()
    payload['workbook']['activities'][1] = parse_activity_repair_draft(
        copy.deepcopy(RECORDING['original']), tutorial=False).model_dump(mode='json')
    return LessonPackage.model_validate(payload)


def merged_response():
    draft = copy.deepcopy(RECORDING['original'])
    draft['instructions'] = (
        'Original fictional case. A community centre notice says: "The centre should offer '
        'more evening programmes because people are busy during the day." Write a narrowed '
        'claim naming a responsible actor, a bounded trial and an observable result. In the '
        'same response, identify a plausible challenge to your own claim and explain whether '
        'it requires a revision or further evidence.'
    )
    draft['fields'] = [{
        'id': 'narrowed_claim', 'kind': 'text', 'label': 'Your narrowed claim and justified self-check',
        'criteria': [
            'Names an actor with authority and a feasible bounded trial',
            'Matches an observable result to the exact claim being made',
            'Justifies a plausible challenge using the submitted wording or identifies what evidence would settle it',
        ],
        'explanation': (
            'A defensible answer asks the programme coordinator to trial an evening art group '
            'and survey its participants about whether that time suited them. That survey can '
            'support a claim about those participants; it does not by itself represent all '
            'residents or prove a causal effect. Another valid answer might use attendance '
            'to assess actual use. Judge the challenge against the learner\'s own wording and '
            'evidence; actor, action or result can each be defensible, and a sound response '
            'need not invent a defect that is absent.'
        ),
    }]
    return draft


def scope_reply(scope='activity', target=TARGET):
    return LLMResponse(data={'target': target, 'scope': scope, 'explanation': (
        'The choice depends on the learner-created sentence. Converting it to text alone '
        'would exceed the one-text-field limit; combine the response and judgment.'
    )})


def factory_for(monkeypatch, replies):
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())
    client = SimpleNamespace(generate_json=AsyncMock(side_effect=replies))
    return client, lambda **kwargs: client


async def repair(factory, **overrides):
    return await generate_package({'lesson_format': 'tutorial_v1'}, {}, client_factory=factory,
        prior_package=original_package(), defects=[
            'The fixed result key cannot grade a challenge whose answer depends on the learner-written sentence.'
        ], repair_targets=overrides.get('repair_targets', [FIELD_TARGET]))


def test_recorded_repair_fails_for_actual_text_field_limit():
    # Historical canonical data remains readable, but fresh tutorial pairing is forbidden.
    original = parse_activity_repair_draft(copy.deepcopy(RECORDING['original']), tutorial=False)
    with pytest.raises(ValueError, match='cannot combine choice/multi_choice with text'):
        parse_activity_repair_draft(copy.deepcopy(RECORDING['original']), tutorial=True)
    assert [field.kind for field in original.fields] == ['text', 'choice']
    assert original.fields[1].correct_choice == 'result'
    assert 'All three are defensible' in original.worked_solution.steps[1].explanation
    with pytest.raises(ValueError, match='has 2 text fields; use at most one text field'):
        parse_activity_repair_draft(copy.deepcopy(RECORDING['two_text_repair']), tutorial=True)


@pytest.mark.asyncio
async def test_independent_scope_review_authorizes_one_coherent_response(monkeypatch):
    before = original_package()
    client, factory = factory_for(monkeypatch, [
        LLMResponse(data={'public_defects': ['A learner-authored answer needs rubric assessment.']}),
        scope_reply(), LLMResponse(data=merged_response()),
    ])
    corrected, response, _ = await repair(factory)
    assert corrected is not None and not response.error
    assert corrected.workbook.activities[0] == before.workbook.activities[0]
    assert corrected.teaching_cases == before.teaching_cases
    assert corrected.workbook.title == before.workbook.title
    assert len(corrected.workbook.activities[1].fields) == 1
    assert corrected.workbook.activities[1].fields[0].kind == 'text'
    assert response.semantic_accepted is None  # Fresh package preflight is still mandatory.
    scope_call, draft_call = client.generate_json.await_args_list[1:]
    assert issubclass(scope_call.kwargs['output_model'], ActivityRepairScopeReview)
    assert scope_call.kwargs['output_model'].model_json_schema()['properties']['target']['const'] == TARGET
    assert json.loads(scope_call.kwargs['user_prompt'])['validated_field_targets'] == [FIELD_TARGET]
    body = json.loads(draft_call.kwargs['user_prompt'])
    assert body['validated_repair_targets'] == [TARGET] and body['field_ids'] is None
    assert client.generate_json.await_count == 3


@pytest.mark.asyncio
async def test_scope_review_does_not_relax_one_text_limit_or_mask_error(monkeypatch):
    client, factory = factory_for(monkeypatch, [
        LLMResponse(data={'public_defects': ['Replace the subjective fixed key with a rubric.']}),
        scope_reply('field'), LLMResponse(data=RECORDING['two_text_repair']),
        LLMResponse(data=RECORDING['two_text_repair']),
    ])
    corrected, response, _ = await repair(factory)
    assert corrected is None
    assert 'has 2 text fields; use at most one text field' in response.error
    assert 'unchanged-content contract' not in response.error
    assert 'input' not in json.loads(response.error.split(': ', 1)[1])[0]
    # The scoped correction hears its validation error once (repair path, round 1).
    assert client.generate_json.await_count == 4


@pytest.mark.asyncio
async def test_field_scope_still_rejects_merging_without_independent_authorization(monkeypatch):
    client, factory = factory_for(monkeypatch, [
        LLMResponse(data={'public_defects': ['The task requires a different response format.']}),
        scope_reply('field'), LLMResponse(data=merged_response()), LLMResponse(data=merged_response()),
    ])
    corrected, response, _ = await repair(factory)
    assert corrected is None and 'Field-owned correction' in response.error
    # One correction carrying the rejection; the field scope is never widened.
    assert client.generate_json.await_count == 4


@pytest.mark.asyncio
@pytest.mark.parametrize('decision', [
    {'target': 'practice.guided', 'scope': 'activity'},
    {'target': TARGET, 'scope': 'unrepairable'},
    {'target': TARGET, 'scope': 'package'},
])
async def test_scope_reviewer_cannot_grant_other_activity_or_package_authority(monkeypatch, decision):
    client, factory = factory_for(monkeypatch, [
        LLMResponse(data={'public_defects': ['The task requires a different response format.']}),
        LLMResponse(data={**decision, 'explanation': 'The reviewer must preserve the exact independently rejected activity.'}),
    ])
    corrected, response, _ = await repair(factory)
    assert corrected is None and 'Activity repair scope review failed' in response.error
    assert client.generate_json.await_count == 2


@pytest.mark.asyncio
async def test_cleared_choice_key_uses_same_independent_scope_gate(monkeypatch):
    client, factory = factory_for(monkeypatch, [
        LLMResponse(data={'field_patches': [{
            'activity_id': 'transfer_narrowing', 'field_id': 'first_challenge', 'correct_choice': None,
        }]}), scope_reply(), LLMResponse(data=merged_response()),
    ])
    corrected, response, _ = await repair(factory)
    assert corrected is not None and not response.error and client.generate_json.await_count == 3


@pytest.mark.asyncio
async def test_existing_activity_scope_needs_no_additional_scope_request(monkeypatch):
    client, factory = factory_for(monkeypatch, [
        LLMResponse(data={'public_defects': ['Combine the response and justified judgment.']}),
        LLMResponse(data=merged_response()),
    ])
    corrected, response, _ = await repair(factory, repair_targets=[TARGET])
    assert corrected is not None and not response.error and client.generate_json.await_count == 2


def test_semantic_review_tests_counterexamples_instead_of_rationalizing_key():
    repaired = RECORDING['rationalized_key_repair']
    assert repaired['fields'][1]['correct_choice'] == 'result'
    assert 'your sentence' in repaired['fields'][1]['label']
    for clause in ('For EVERY choice and multi_choice field', 'each alternative',
                   'different valid learner responses', 'demographic survey',
                   'not rationalize the old key', 'target the whole activity'):
        assert clause in _SEMANTIC_PROMPT
    for name in ('tutorial_activity_generate.txt', 'tutorial_package_seed.txt',
                 'lesson_activity_generate.txt', 'lesson_package_seed.txt', 'lesson_package_generate.txt'):
        rendered = load_and_render(name, {})
        assert 'learner-authored' in rendered and 'counterexample' in rendered


def test_qualitative_seed_has_its_own_complete_public_worked_case():
    prompt = load_and_render('tutorial_package_seed.txt', {})
    examples = [json.loads(line) for line in prompt.splitlines() if line.startswith('{"workbook_title"')]
    exemplar = next(example for example in examples if not example["teaching_cases"][0]["data"])
    seed = LessonPackageSeed.model_validate(exemplar)
    case = seed.teaching_cases[0]
    assert case.data == [] and case.results == []
    assert 'Original fictional notice:' in case.assumptions and 'Revision:' in case.assumptions
    assert case.computed()['assumptions'] == case.assumptions
    package = original_package().model_copy(update={'teaching_cases': [case]})
    assert package.writer_context()['teaching_cases'][0] == case.computed()


@pytest.mark.parametrize('payload', [
    {'data': [{'id': 'count', 'label': 'Raw count', 'value': 12}], 'results': []},
    {'data': [], 'results': [{'id': 'total', 'label': 'Total', 'expression': 'count', 'unit': '', 'decimal_places': 0}]},
])
def test_quantitative_teaching_case_still_requires_paired_raw_data_and_results(payload):
    with pytest.raises(ValueError, match='needs both raw data and derived results'):
        TeachingCase.model_validate({'id': 'quantitative', 'assumptions': 'Original fictional quantities for arithmetic.', **payload})



def choice_audit(*, depends=False, actor_defensible=False):
    from app.services.planning.package_preflight import ChoiceFieldAudit
    return ChoiceFieldAudit.model_validate({
        'target': FIELD_TARGET, 'depends_on_learner_response': depends,
        'dependency_reason': ('The diagnosis changes with the submitted claim.' if depends else
                              'This separate question addresses only its fully supplied fixed case.'),
        'options': [
            {'option_id': 'actor', 'defensible': actor_defensible,
             'reason': 'A learner may name an actor without decision authority.'},
            {'option_id': 'action', 'defensible': False,
             'reason': 'The stated fixed case supplies a bounded feasible action.'},
            {'option_id': 'result', 'defensible': True,
             'reason': 'The stated fixed case does not provide an observable result.'},
        ],
    })


def test_variable_answer_audit_rejects_rationalized_key_even_with_positive_summary():
    from app.services.planning.package_preflight import _choice_audit_issues
    issues = _choice_audit_issues(original_package(), [choice_audit(depends=True)])
    assert [issue.target for issue in issues] == [TARGET]
    assert 'learner-authored response' in issues[0].description
    issues = _choice_audit_issues(original_package(), [choice_audit(actor_defensible=True)])
    assert [issue.target for issue in issues] == [FIELD_TARGET]
    assert 'contradicts the fixed answer key' in issues[0].description


@pytest.mark.parametrize('mutation', ['missing_field', 'duplicate_field', 'missing_option', 'duplicate_option', 'unknown_option'])
def test_audit_requires_exact_field_and_option_coverage(mutation):
    from app.services.planning.package_preflight import _choice_audit_issues
    audit = choice_audit()
    audits = [audit]
    if mutation == 'missing_field': audits = []
    elif mutation == 'duplicate_field': audits.append(audit)
    elif mutation == 'missing_option': audit.options.pop()
    elif mutation == 'duplicate_option': audit.options[-1] = audit.options[0]
    elif mutation == 'unknown_option': audit.options[-1].option_id = 'invented'
    with pytest.raises(ValueError, match='exactly once'):
        _choice_audit_issues(original_package(), audits)


def test_legacy_independent_fixed_case_can_follow_a_written_response():
    from app.services.planning.package_preflight import _choice_audit_issues
    assert not _choice_audit_issues(original_package(), [choice_audit()])


def test_multi_choice_audit_checks_exact_set_not_single_answer_rule():
    from app.services.planning.package_preflight import _choice_audit_issues
    package = original_package()
    field = package.workbook.activities[1].fields[1]
    field.kind, field.correct_choice, field.correct_choices = 'multi_choice', None, ['actor', 'result']
    assert not _choice_audit_issues(package, [choice_audit(actor_defensible=True)])
    assert _choice_audit_issues(package, [choice_audit()])


@pytest.mark.asyncio
async def test_missing_public_tutorial_case_blocks_before_provider(monkeypatch):
    from app.services.planning.package_preflight import review_package
    package = original_package()
    # Isolate the missing public-case gate with the corrected allowed response shape.
    package.workbook.activities[1] = parse_activity_repair_draft(merged_response(), tutorial=True)
    for activity in package.workbook.activities:
        activity.minutes_min, activity.minutes_max = 1, 2
    client, factory = factory_for(monkeypatch, [])
    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'}, {}, client_factory=factory)
    assert failures and not response.error
    assert response.effective_parameters['validated_repair_targets'] == ['package']
    assert 'separate public worked teaching case' in ' '.join(failures)
    assert client.generate_json.await_count == 0


@pytest.mark.asyncio
@pytest.mark.parametrize('missing_audit', [False, True])
async def test_positive_summary_cannot_override_variable_or_missing_audit(monkeypatch, missing_audit):
    from app.services.planning.package_preflight import review_package
    package = original_package()
    # A standalone choice can still improperly depend on the learner's own draft.
    # Isolate that semantic failure after the new structural mixed-pair gate.
    transfer = package.workbook.activities[1]
    transfer.fields = [transfer.fields[1]]
    transfer.worked_solution.steps = [transfer.worked_solution.steps[1]]
    for activity in package.workbook.activities:
        activity.minutes_min, activity.minutes_max = 1, 2
    package.teaching_cases = [TeachingCase(id='public_notice', assumptions=(
        'Original fictional notice: "Garden helpers welcome." A clear revision names a '
        'cleanup and asks volunteers to reply to its coordinator; it specifies an action and response path.'
    ), data=[], results=[])]
    verdict = {'acceptable': True, 'issues': []}
    if not missing_audit:
        verdict['choice_audits'] = [choice_audit(depends=True).model_dump()]
    client, factory = factory_for(monkeypatch, [
        LLMResponse(data=copy.deepcopy(verdict)) for _ in range(2 if missing_audit else 1)])
    failures, response, _ = await review_package(package, {'lesson_format': 'tutorial_v1'}, {}, client_factory=factory)
    assert failures and not response.semantic_accepted
    if missing_audit:
        assert response.error and client.generate_json.await_count == 2
        assert not response.effective_parameters.get('validated_repair_targets')
    else:
        assert not response.error and client.generate_json.await_count == 1
        assert response.effective_parameters['validated_repair_targets'] == [TARGET]

