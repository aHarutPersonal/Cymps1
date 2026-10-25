from types import SimpleNamespace
from unittest.mock import AsyncMock
import pytest
from app.services.book_fidelity import repair_book_fidelity, BookSpanEvidence
from app.services.planning.lesson_package import digest
from app.services.llm.client import LLMResponse

CONTENT='  Unchanged heading\n\nA fact that the independent reviewer found incorrect.\n\n  Other paragraph stays byte identical.  '
SOURCE='verified source '*400

@pytest.mark.asyncio
@pytest.mark.parametrize('defect',['none','out_of_scope','duplicate','missing','stale_content','stale_source','incomplete','no_targets'])
async def test_factual_repair_is_exactly_bound_and_preserves_other_bytes(monkeypatch,defect):
 monkeypatch.setattr('app.services.llm.telemetry.record_llm_response',AsyncMock())
 report={'passed':False,'review_completed':True,'content_hash':digest(CONTENT),'source_hash':digest(SOURCE),'issues':['b2: contradicts the verified text']}
 patches=[{'guide_span_id':'b2','replacement':'Corrected paragraph supported by the verified source.'}]
 if defect=='out_of_scope':patches[0]['guide_span_id']='b3'
 if defect=='duplicate':patches*=2
 if defect=='missing':patches=[]
 if defect=='stale_content':report['content_hash']='stale'
 if defect=='stale_source':report['source_hash']='stale'
 if defect=='incomplete':report['review_completed']=False
 if defect=='no_targets':report['issues']=['no scoped evidence']
 client=SimpleNamespace(generate_json=AsyncMock(return_value=LLMResponse(data={'patches':patches})))
 result=await repair_book_fidelity({'content_markdown':CONTENT,'title':'Test'},source=SOURCE,review=report,client_factory=lambda **kw:client)
 if defect=='none':
  assert result['title']=='Test'
  assert result['content_markdown']==CONTENT.replace('A fact that the independent reviewer found incorrect.',patches[0]['replacement'])
 else:assert result is None
 if defect in ('stale_content','stale_source','incomplete','no_targets'):client.generate_json.assert_not_called()


def test_comprehensive_paragraph_may_cite_more_than_twelve_valid_passages():
 assert len(BookSpanEvidence(guide_span_id='b1',kind='book_specific',source_span_ids=[f's{i}' for i in range(1,15)]).source_span_ids)==14
