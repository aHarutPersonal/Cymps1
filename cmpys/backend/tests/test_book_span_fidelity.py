import copy,json
from types import SimpleNamespace
from unittest.mock import AsyncMock
import pytest
from app.services.book_fidelity import review_book_fidelity,FIDELITY_VERSION
from app.services.llm.client import LLMResponse

SOURCE='Exact source words which support the book specific claim with enough concrete textual evidence. '*25
CONTENT='The guide explains the documented principle.\n\nGeneral educational synthesis: try applying the principle to a fictional shop.'
VERDICT={'identity_matches':True,'sufficient_source':True,'coverage_complete':True,'issues':[], 'claims':[
 {'guide_span_id':'b1','kind':'book_specific','source_span_ids':['s1']},
 {'guide_span_id':'b2','kind':'general_synthesis','source_span_ids':[]}]}

@pytest.mark.asyncio
@pytest.mark.parametrize('defect',['none','missing','duplicate','unknown_guide','unknown_source','missing_source','duplicate_source','negative','identity','sufficiency','coverage','only_synthesis'])
async def test_every_guide_span_requires_complete_independent_bound_evidence(monkeypatch,defect):
 monkeypatch.setattr('app.services.llm.telemetry.record_llm_response',AsyncMock())
 data=copy.deepcopy(VERDICT)
 if defect=='missing':data['claims'].pop()
 elif defect=='duplicate':data['claims'].append(data['claims'][0])
 elif defect=='unknown_guide':data['claims'][0]['guide_span_id']='b99'
 elif defect=='unknown_source':data['claims'][0]['source_span_ids']=['s99']
 elif defect=='missing_source':data['claims'][0]['source_span_ids']=[]
 elif defect=='duplicate_source':data['claims'][0]['source_span_ids']=['s1','s1']
 elif defect=='negative':data['issues']=['The cited source does not support this attributed assertion.']
 elif defect=='identity':data['identity_matches']=False
 elif defect=='sufficiency':data['sufficient_source']=False
 elif defect=='coverage':data['coverage_complete']=False
 elif defect=='only_synthesis':data['claims'][0]['kind']='general_synthesis'
 client=SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data=data)))
 result=await review_book_fidelity({'content_markdown':CONTENT},source=SOURCE,source_id='verified',client_factory=lambda **kw:client)
 assert result['passed'] is (defect=='none')
 assert result['version']==FIDELITY_VERSION and result['review_completed']
 request=json.loads(client.generate_json.await_args.kwargs['user_prompt'])
 assert request['guide_spans']['b1'] in CONTENT and request['verified_source_spans']['s1'] in SOURCE
 if defect=='none':
  assert result['claims'][0]['statement']==request['guide_spans']['b1']
  assert result['claims'][0]['source_spans'][0]['text']==SOURCE.strip()
