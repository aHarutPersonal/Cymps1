import copy
from unittest.mock import AsyncMock
import pytest
from app.services.llm.client import LLMResponse
from app.services.planning.lesson_package import LessonPackage
from app.services.planning.package_preflight import PackageSemanticReview
from tests.test_lesson_pipeline_reliability import Scenario,ScenarioClient,run_scenario,package_payload

@pytest.mark.asyncio
@pytest.mark.parametrize('reject_again',[False,True])
async def test_global_package_rejection_rebuilds_once_then_requires_independent_approval(monkeypatch,reject_again):
 original=LessonPackage.model_validate(package_payload());changed=copy.deepcopy(package_payload())
 changed['workbook']['activities'][0]['hint']='Check the limiting assumption against the supplied evidence before choosing a revision.'
 rebuilt=LessonPackage.model_validate(changed)
 response=LLMResponse(data={},effective_parameters={'synthetic_local_validation':True})
 build=AsyncMock(side_effect=[(original,response,None),(rebuilt,response,None)])
 monkeypatch.setattr('app.services.planning.package_builder.generate_initial_package',build)
 monkeypatch.setattr('app.tasks.plans.generate_package',AsyncMock(side_effect=AssertionError('Global rejection routed to private field repair')))
 reviews=[]
 class Case(Scenario):
  def factory(self,**kwargs):
   case=self
   class Client(ScenarioClient):
    async def generate_json(self,*,output_model,user_prompt,**options):
     if issubclass(output_model,PackageSemanticReview):
      reviews.append(user_prompt)
      if len(reviews)==1 or reject_again:
       return LLMResponse(data={'acceptable':False,'issues':[{'target':'package','description':'Required reasoning support is absent across the whole package; correct its tasks.'}]})
     return await super().generate_json(output_model=output_model,user_prompt=user_prompt,**options)
   return Client(case)
 result,calls,error=await run_scenario(Case('accepted'))
 assert build.await_count==2 and len(reviews)==2
 assert build.await_args.args[1]['independent_package_defects']
 assert bool(error)==reject_again
 assert bool(result['steps'][0].get('lesson_content')) is not reject_again
