import copy
from unittest.mock import AsyncMock
import pytest
from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import PackageSemanticReview
from tests.test_lesson_pipeline_reliability import Scenario,ScenarioClient,run_scenario,package_payload

@pytest.mark.asyncio
@pytest.mark.parametrize('reject_again',[False,True])
@pytest.mark.parametrize('repair_target',['package','teaching.repair_case'])
async def test_global_package_rejection_rebuilds_once_then_requires_independent_approval(monkeypatch,reject_again,repair_target):
 payload=package_payload()
 payload['teaching_cases']=[{'id':'repair_case','assumptions':'Original fictional notice: Club meeting today. The notice names an event but supplies no place.','data':[],'results':[]}]
 original=LessonPackage.model_validate(payload);changed=copy.deepcopy(payload)
 changed['workbook']['activities'][0]['hint']='Check the limiting assumption against the supplied evidence before choosing a revision.'
 rebuilt=LessonPackage.model_validate(changed)
 response=LLMResponse(data={},effective_parameters={'synthetic_local_validation':True})
 build=AsyncMock(side_effect=[(original,response,None),(rebuilt,response,None)])
 monkeypatch.setattr('app.services.planning.package_builder.generate_initial_package',build)
 monkeypatch.setattr('app.tasks.plans.generate_package',AsyncMock(side_effect=AssertionError('Global rejection routed to private field repair')))
 reviews=[];patches=[]
 class Case(Scenario):
  def factory(self,**kwargs):
   case=self
   class Client(ScenarioClient):
    async def generate_json(self,*,output_model,user_prompt,**options):
     if output_model.__name__=='TeachingCaseRepair':
      # A teaching-case target first gets its text patch; a defect the text
      # cannot fix falls back to the same bounded rebuild (repair path R2).
      patches.append(user_prompt)
      return LLMResponse(data={'requires_data_change':['The whole package lacks the required reasoning support.']})
     if issubclass(output_model,PackageSemanticReview):
      reviews.append(user_prompt)
      if len(reviews)==1 or reject_again:
       return LLMResponse(data={'acceptable':False,'issues':[{'target':repair_target,'description':'Required reasoning support is absent across the whole package; correct its tasks.'}]})
     return await super().generate_json(output_model=output_model,user_prompt=user_prompt,**options)
   return Client(case)
 result,calls,error=await run_scenario(Case('accepted'))
 assert len(patches)==(repair_target.startswith('teaching.'))
 assert build.await_count==2 and len(reviews)==2
 assert build.await_args.args[1]['independent_package_defects']
 assert bool(error)==reject_again
 assert bool(result['steps'][0].get('lesson_content')) is not reject_again


def test_public_rebuild_requires_a_known_public_owner():
 from app.tasks.plans import _requires_public_package_rebuild,_teaching_patch_cases
 payload=package_payload()
 payload['teaching_cases']=[{'id':'repair_case','assumptions':'Original fictional notice: Club meeting today. The notice names an event but supplies no place.','data':[],'results':[]}]
 package=LessonPackage.model_validate(payload)
 # Package-wide and learner-context defects rebuild; a teaching case is patched first.
 assert _requires_public_package_rebuild(['package'],package)
 assert _requires_public_package_rebuild(['package','practice.guided'],package)
 assert _requires_public_package_rebuild(['teaching.repair_case','context'],package)
 assert not _requires_public_package_rebuild(['teaching.repair_case'],package)
 assert not _requires_public_package_rebuild(['teaching.unknown','package'],package)
 assert not _requires_public_package_rebuild(['practice.guided'],package)
 assert _teaching_patch_cases(['teaching.repair_case'],package)=={'repair_case'}
 assert _teaching_patch_cases(['teaching.repair_case','practice.guided'],package)=={'repair_case'}
 assert _teaching_patch_cases(['teaching.unknown'],package)==set()
 assert _teaching_patch_cases(['teaching.repair_case','package'],package)==set()
 assert _teaching_patch_cases(['practice.guided'],package)==set()
