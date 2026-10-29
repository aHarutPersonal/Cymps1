import copy,json
from unittest.mock import AsyncMock
import pytest
from app.services.llm.client import LLMResponse
from app.services.planning.package_preflight import PackageSemanticReview
from tests.test_lesson_pipeline_reliability import Scenario, ScenarioClient, run_scenario
from tests.test_private_generation_checkpoint import Database

# F17: an outline-only preflight issue is reconciling guidance for the lesson
# writer. The plan-time outline description is never rewritten, the package
# is not rebuilt, and the lesson still passes its independent review.

@pytest.mark.asyncio
@pytest.mark.parametrize('reject_again',[False,True])
async def test_outline_rejection_becomes_writer_guidance_without_rewriting_the_outline(monkeypatch,reject_again):
 monkeypatch.setattr('app.services.llm.telemetry.record_llm_response',AsyncMock(return_value=True))
 monkeypatch.setattr('app.tasks.plans.generate_package',AsyncMock(side_effect=AssertionError('Wrong repair owner')))
 semantic=[]; writer=[]; checkpoints=[]
 issue='The outline word count contradicts the scoped exercise requirement.'
 class Case(Scenario):
  def factory(self,**kwargs):
   case=self
   class Client(ScenarioClient):
    async def generate_json(self,*,output_model,user_prompt,**options):
     if output_model.__name__=='LessonOutlineDescriptionRepair':
      raise AssertionError('The outline description is never rewritten')
     if issubclass(output_model,PackageSemanticReview):
      semantic.append(copy.deepcopy(json.loads(user_prompt)['outline']))
      if len(semantic)==1 or reject_again:
       return LLMResponse(data={'acceptable':False,'issues':[{'target':'outline','description':issue}]})
     if output_model.__name__.startswith('LessonSectionGroup_'):
      writer.append(user_prompt)
     return await super().generate_json(output_model=output_model,user_prompt=user_prompt,**options)
   return Client(case)
 db=Database();store=db.store(db.new_job());case=Case('accepted')
 async def checkpoint(payload,stage):checkpoints.append((copy.deepcopy(payload),stage))
 result,calls,error=await run_scenario(case,private_checkpoint_store=store,on_checkpoint=checkpoint)
 assert error is None and result['steps'][0].get('lesson_content')
 assert len(semantic)==1  # one semantic decision; no re-review of a rewritten outline
 assert not any(stage=='outline_corrected' for _,stage in checkpoints)
 assert not any('outline_repair' in call[0] for call in calls)
 assert writer and all('OUTLINE RECONCILIATION' in prompt and issue.rstrip('.') in prompt for prompt in writer)
