import copy,json
from unittest.mock import AsyncMock
import pytest
from app.services.llm.client import LLMResponse
from app.services.planning.package_preflight import PackageSemanticReview
from app.tasks.plans import _repair_rejected_outline
from tests.test_lesson_pipeline_reliability import Scenario, ScenarioClient, run_scenario, package_payload
from app.services.planning.lesson_package import LessonPackage
from tests.test_private_generation_checkpoint import Database

@pytest.mark.asyncio
@pytest.mark.parametrize('reject_again',[False,True])
async def test_outline_rejection_repairs_only_description_and_requires_new_review(monkeypatch,reject_again):
 monkeypatch.setattr('app.services.llm.telemetry.record_llm_response',AsyncMock(return_value=True))
 monkeypatch.setattr('app.tasks.plans.generate_package',AsyncMock(side_effect=AssertionError('Wrong repair owner')))
 semantic=[]; packages=[]; repairs=[]; checkpoints=[]
 class Case(Scenario):
  def factory(self,**kwargs):
   case=self
   class Client(ScenarioClient):
    async def generate_json(self,*,output_model,user_prompt,**options):
     body=json.loads(user_prompt) if issubclass(output_model,PackageSemanticReview) or output_model.__name__=='LessonOutlineDescriptionRepair' else {}
     if issubclass(output_model,PackageSemanticReview):
      semantic.append(copy.deepcopy(body['outline']));packages.append(body['package'])
      if len(semantic)==1 or reject_again:
       return LLMResponse(data={'acceptable':False,'issues':[{'target':'outline','description':'The outline word count contradicts the scoped exercise requirement.'}]})
     if output_model.__name__=='LessonOutlineDescriptionRepair':
      repairs.append(body)
      return LLMResponse(data={'description':'Study the supplied argument and test its assumptions using the unchanged exercises in this lesson.'})
     return await super().generate_json(output_model=output_model,user_prompt=user_prompt,**options)
   return Client(case)
 db=Database();store=db.store(db.new_job());case=Case('accepted')
 async def checkpoint(payload,stage):checkpoints.append((copy.deepcopy(payload),stage))
 result,calls,error=await run_scenario(case,private_checkpoint_store=store,on_checkpoint=checkpoint)
 assert len(semantic)==2 and len(repairs)==1 and packages[0]==packages[1]
 assert {k:v for k,v in semantic[0].items() if k!='description'}=={k:v for k,v in semantic[1].items() if k!='description'}
 assert semantic[0]['description']!=semantic[1]['description']
 assert any(stage=='outline_corrected' for _,stage in checkpoints)
 assert any('outline_repair' in call[0] for call in calls)
 assert bool(error)==reject_again
 assert bool(result['steps'][0].get('lesson_content')) is not reject_again

@pytest.mark.asyncio
async def test_outline_scope_cannot_expand_and_model_cannot_patch_other_fields():
 package=LessonPackage.model_validate(package_payload());client=AsyncMock()
 factory=lambda **kw:client
 value,response,_=await _repair_rejected_outline({'id':'step_1'},package,{},['error'],targets=['outline','context'],client_factory=factory)
 assert value is None;client.generate_json.assert_not_awaited()
 client.generate_json.return_value=LLMResponse(data={'description':'A complete revised description for this scoped lesson only.','title':'Changed'})
 value,response,_=await _repair_rejected_outline({'id':'step_1'},package,{},['error'],targets=['outline'],client_factory=factory)
 assert value is None and response.error
