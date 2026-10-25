import copy
from unittest.mock import AsyncMock
import pytest
from app.services.planning import package_builder as builder
from tests.test_staged_package_builder import Factory, components

@pytest.mark.asyncio
@pytest.mark.parametrize('second_failure',[False,True])
async def test_each_component_gets_at_most_one_repair_without_repeating_valid_work(monkeypatch,second_failure):
 monkeypatch.setattr(builder,'record_llm_response',AsyncMock(return_value=True))
 seed, activities=components()
 responses={'seed':[{**seed,'unsupported_extra':'invalid'},seed]}
 for key,activity in activities.items():
  bad=copy.deepcopy(activity);bad['title']=''
  responses[key]=[bad,bad if second_failure else activity]
 factory=Factory(responses)
 package,response,_=await builder.generate_initial_package({'id':'step_1','title':'Learn'},
   {'component_recovery':'bounded_per_component','target_practice_minutes':35},client_factory=factory)
 assert (package is not None) is not second_failure
 assert factory.counts['seed']==2
 assert all(count<=2 for count in factory.counts.values())
 assert len(factory.requests)<=2*(1+len(activities))
 if not second_failure:assert all(count==2 for count in factory.counts.values())
 assert response.effective_parameters['max_component_requests']==6
