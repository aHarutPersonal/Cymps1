import copy
from types import SimpleNamespace
from unittest.mock import AsyncMock
import pytest
from app.services.llm.client import LLMResponse
from app.tasks.plans import _generate_plan_item_details_parallel
from tests.test_plan_detail_output_schema import _outline_payload

@pytest.mark.asyncio
@pytest.mark.parametrize('version,ready,regenerated',[(None,[],True),(3,[],False),(None,['step_1'],False)])
async def test_legacy_empty_outline_rebuilt_but_ready_or_current_outline_retained(monkeypatch,version,ready,regenerated):
 old=_outline_payload(lesson_count=1,material_count=1);fresh=copy.deepcopy(old)
 old['steps'][0]['title']='Legacy scaffold';fresh['steps'][0]['title']='Fresh executable scaffold'
 client=SimpleNamespace(model='offline',generate_json=AsyncMock(return_value=LLMResponse(data=fresh)))
 build=AsyncMock(return_value=(None,LLMResponse(data={},error='Offline stop after checking outline'),None))
 monkeypatch.setattr('app.services.planning.package_builder.generate_initial_package',build)
 await _generate_plan_item_details_parallel(system_prompt='Teach accurately',task_title='Test',mission_hours=1,
   user_goal='Learn',learning_preferences='reading',idol_name='Mentor',idol_domain='writing',idol_evidence={},
   session_context='',active_tier='balanced',routing_reason='test',client_factory=lambda **kw:client,
   mission_description='Current increment with all required inputs supplied inside the lesson.',
   existing_checkpoint={'_generation':{'outline':old,'outline_contract_version':version,'ready_step_ids':ready}})
 assert client.generate_json.await_count==int(regenerated)
 assert build.await_args.args[0]['title']==('Fresh executable scaffold' if regenerated else 'Legacy scaffold')
