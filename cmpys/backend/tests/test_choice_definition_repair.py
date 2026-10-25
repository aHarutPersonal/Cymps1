"""A rejected null choice key gets one scoped, bounded public correction."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock
import pytest
from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage, PrivatePackageRepair, _cleared_choice_targets, _replace_choice_activity, generate_package
from app.services.planning.package_builder import LessonPackageActivity
from app.services.planning.activity_draft import LessonActivityDraft
from tests.lesson_package_fixtures import package_payload
from tests.section_client_fixture import activity_draft_fixture


def original_package():
    value = package_payload()
    value['workbook']['activities'][1]['fields'].append({
        'id':'audience', 'label':'Select and explain your audience', 'kind':'choice',
        'choices':[{'id':'peers','label':'Peers'},{'id':'parents','label':'Parents'}],
        'correct_choice':'parents'})
    for activity in value['workbook']['activities']:
        activity['worked_solution'] = {'version': 1, 'steps': [
            {'field_id': field['id'], 'explanation': 'Explain how the claim and its reasons address the intended audience and respond to the objection.'}
            for field in activity['fields']]}
    return LessonPackage.model_validate(value)


def deletion():
    return {'field_patches':[{'activity_id':'transfer','field_id':'audience','correct_choice':None}]}


def corrected_activity():
    value = original_package().workbook.activities[1].model_dump(mode='json')
    value['fields'][1] = {'id':'audience','label':'Select and explain your audience','kind':'text',
        'criteria':['Names an audience and explains how the argument addresses that audience.']}
    return value


@pytest.mark.parametrize('mutation',['omitted','irrelevant_null','wrong_kind','unknown_field','unknown_activity','duplicate','multiple_activities','unrelated_solution','public_defect'])
def test_null_routing_requires_one_exact_known_choice_scope(mutation):
    package, payload = original_package(), deletion()
    patch = payload['field_patches'][0]
    if mutation == 'omitted': patch.pop('correct_choice')
    elif mutation == 'irrelevant_null': patch.update(expression=None)
    elif mutation == 'wrong_kind': patch['field_id']='argument'
    elif mutation == 'unknown_field': patch['field_id']='missing'
    elif mutation == 'unknown_activity': patch['activity_id']='missing'
    elif mutation == 'duplicate': payload['field_patches'].append(copy.deepcopy(patch))
    elif mutation == 'multiple_activities': payload['field_patches'].append({**patch,'activity_id':'guided'})
    elif mutation == 'unrelated_solution': payload['solution_patches']=[{'activity_id':'guided','worked_solution':'An unrelated complete solution must not expand the correction scope.'}]
    elif mutation == 'public_defect': payload['public_defects']=['Other public facts need revision.']
    assert _cleared_choice_targets(package,PrivatePackageRepair.model_validate(payload)) is None


def test_valid_replacement_preserves_other_content_and_changes_public_contract():
    package=original_package(); before=package.model_dump(mode='json')
    activity,targets=_cleared_choice_targets(package,PrivatePackageRepair.model_validate(deletion()))
    corrected=_replace_choice_activity(package,activity,targets,LessonPackageActivity.model_validate(corrected_activity()))
    assert package.model_dump(mode='json') == before
    assert corrected.workbook.activities[0] == package.workbook.activities[0]
    assert corrected.teaching_cases == package.teaching_cases
    assert corrected.writer_context() != package.writer_context()
    assert corrected.workbook.activities[1].fields[0] == package.workbook.activities[1].fields[0]
    assert corrected.workbook.activities[1].fields[1].kind == 'text'


@pytest.mark.parametrize('mutation',['id','kind','title','data','diagram','field_order','drop_field','new_field','untargeted_criteria','target_label','still_fixed','empty_criteria'])
def test_replacement_rejects_scope_drift_and_invalid_grading(mutation):
    package,value=original_package(),corrected_activity()
    if mutation == 'id': value['id']='other'
    elif mutation == 'kind': value['kind']='practice'
    elif mutation == 'title': value['title']='Different activity'
    elif mutation == 'data': value['data']=[{'id':'novel','label':'New fact','value':7,'unit':'units'}]
    elif mutation == 'diagram': value['diagram']={'unsupported':True}
    elif mutation == 'field_order': value['fields'].reverse()
    elif mutation == 'drop_field': value['fields'].pop(0)
    elif mutation == 'new_field': value['fields'].append({**value['fields'][0],'id':'new'})
    elif mutation == 'untargeted_criteria': value['fields'][0]['criteria']=['A different assessment.']
    elif mutation == 'target_label': value['fields'][1]['label']='An unrelated question'
    elif mutation == 'still_fixed': value['fields'][1]=package.workbook.activities[1].fields[1].model_dump(mode='json')
    elif mutation == 'empty_criteria': value['fields'][1]['criteria']=[]
    with pytest.raises(ValueError):
        _replace_choice_activity(package,package.workbook.activities[1],{'audience'},LessonPackageActivity.model_validate(value))


@pytest.mark.asyncio
@pytest.mark.parametrize('outcome',['success','schema','transport','public_defects'])
async def test_choice_correction_uses_only_second_call_and_bounded_component(outcome,monkeypatch):
    telemetry=AsyncMock(); monkeypatch.setattr('app.services.llm.telemetry.record_llm_response',telemetry)
    second=LLMResponse(data=activity_draft_fixture(corrected_activity()))
    if outcome == 'schema': second.data={'id':'transfer'}
    elif outcome == 'transport': second.error='zai request failed (TimeoutError; transient)'
    elif outcome == 'public_defects': second.data={'public_defects':['Change the whole task.']}
    client=SimpleNamespace(generate_json=AsyncMock(side_effect=[LLMResponse(data=deletion()),second]))
    factory_args=[]
    def factory(**kwargs):
        factory_args.append(kwargs); return client
    package,response,_=await generate_package({}, {},client_factory=factory,prior_package=original_package(),defects=['Freely chosen audience cannot have one fixed correct answer.'],repair_targets=['practice.transfer.audience'])
    assert client.generate_json.await_count == 2
    calls=client.generate_json.await_args_list
    assert [c.kwargs['output_model'] for c in calls] == [PrivatePackageRepair,LessonActivityDraft]
    prompt=json.loads(calls[1].kwargs['user_prompt'])
    assert 'previous_package' not in prompt and prompt['previous_activity']['id']=='transfer'
    assert prompt['text_field_ids']==['audience']
    assert 'Preserve instructions and both timing endpoints exactly' in calls[1].kwargs['system_prompt']
    assert 'Put explanation alongside each field in its exact order' in calls[1].kwargs['system_prompt']
    assert 'Copy each unaffected explanation exactly' in calls[1].kwargs['system_prompt']
    assert factory_args[-1]['timeout']==90 and factory_args[-1]['max_tokens']==4000
    telemetry.assert_awaited_once()
    assert telemetry.await_args.kwargs['operation']=='lesson_package_choice_definition_repair'
    assert (package is not None and not response.error) == (outcome=='success')


@pytest.mark.asyncio
async def test_corrected_public_activity_cannot_bypass_package_preflight(monkeypatch):
    from collections import Counter
    from app.services.planning.package_builder import LessonPackageSeed
    from app.services.planning.package_preflight import PackageSemanticReview
    from tests.test_lesson_pipeline_reliability import run_scenario
    monkeypatch.setattr('app.services.llm.telemetry.record_llm_response', AsyncMock())
    from app.core.config import settings
    monkeypatch.setattr(settings, 'llm_usage_telemetry_enabled', False)
    counts = Counter()
    class Client:
        model = 'offline-choice-repair'
        async def generate_json(self, *, output_model, user_prompt, **kwargs):
            counts[output_model.__name__] += 1
            request = {} if output_model is PrivatePackageRepair else json.loads(user_prompt)
            original = original_package()
            if output_model is LessonPackageSeed:
                data = {'workbook_title':original.workbook.title,'teaching_cases':[],
                    'activity_briefs':[{'id':a.id,'kind':a.kind,'scope':a.instructions} for a in original.workbook.activities]}
            elif output_model is LessonActivityDraft:
                if 'previous_activity' in request:
                    data = activity_draft_fixture(corrected_activity())
                else:
                    data = activity_draft_fixture(next(a.model_dump(mode='json') for a in original.workbook.activities if a.id == request['activity_brief']['id']))
            elif issubclass(output_model, PackageSemanticReview):
                data = {'acceptable':False,'issues':[{'target':'practice.transfer.audience',
                    'description':'Audience field is inconsistent with the required reasoning.'}]}
            elif output_model is PrivatePackageRepair:
                data = deletion()
            else:
                raise AssertionError('No prose or final review is allowed after a failed preflight')
            return LLMResponse(data=data,finish_reason='stop')
    scenario=SimpleNamespace(factory=lambda **kwargs:Client())
    packages, approvals = {}, {}
    payload, calls, error = await run_scenario(scenario, prepared_packages=packages, validation_records=approvals)
    assert error and not packages and not approvals
    assert counts['PackageSemanticReview'] == 2
    assert counts['PrivatePackageRepair'] == 1 and counts['LessonActivityDraft'] == 3
    assert not any(step.get('lesson_content') for step in payload['steps'])
