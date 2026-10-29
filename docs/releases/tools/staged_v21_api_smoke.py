import asyncio,json,hashlib
from datetime import timedelta
import httpx
from sqlalchemy import text
from app.core.db import async_session_maker
from app.core.security import create_access_token
from scripts.restore_approved_lesson_snapshot import SOURCE_ITEM_ID,TARGET_ITEM_ID,load_snapshot,fingerprint

async def snapshot():
    async with async_session_maker() as db:
        await db.execute(text('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY'))
        value=await load_snapshot(db,lock=False)
        count=await db.scalar(text('SELECT count(*) FROM llm_usage_events'))
        await db.rollback()
    return value,count

async def main():
    before,calls=await snapshot()
    assert fingerprint(before)=='9620a6e2d34355178ba2d25cf3e3775269f53b586c6037e1cfc423a5bcc5a42d', 'Saved learner state differs from reviewed baseline'
    report={}
    async with httpx.AsyncClient(base_url='http://127.0.0.1:8000',timeout=20) as client:
        for label,item_id in [('learner',TARGET_ITEM_ID),('existing_qa_copy',SOURCE_ITEM_ID)]:
            jobs=[j for j in before['jobs'] if str(j['plan_item_id'])==item_id]
            assert jobs and jobs[0]['status'] in {'failed','ready'}, 'Only inspected terminal artifacts may be checked'
            if label=='learner':
                assert jobs[0]['status']=='failed'
            else:
                from app.services.planning.lesson_package import current_package_approval
                assert current_package_approval(before['items'][item_id]['details_json'],allow_compatible_read=True)
            owner=before['owners'][item_id]
            async with async_session_maker() as db:
                version=await db.scalar(text('SELECT auth_version FROM users WHERE id=:id'),{'id':owner})
            token=create_access_token(owner,expires_delta=timedelta(minutes=2),auth_version=version)
            headers={'Authorization':'Bearer '+token}
            plan=await client.get('/api/v1/plans/current',headers=headers)
            response=await client.get('/api/v1/plan-items/'+item_id+'/detailed',headers=headers)
            result={'plan_http':plan.status_code,'details_http':response.status_code}
            assert plan.status_code==200 and response.status_code==200
            body=response.json()
            result['details_status']=body.get('details_status',body.get('detailsStatus'))
            details=body.get('details') or {}
            ready=[s for s in details.get('steps',[]) if s.get('lesson_content') or s.get('lessonContent')]
            result['ready_lessons']=len(ready)
            artifact=body.get('artifact_job_id',body.get('artifactJobId'))
            if ready:
                params={'artifactJobId':artifact} if artifact else {}
                practice=await client.get('/api/v1/plan-items/'+item_id+'/steps/'+ready[0]['id']+'/practice',headers=headers,params=params)
                result['practice_http']=practice.status_code
                if practice.status_code==200:
                    data=practice.json()
                    result['practice_state']=data.get('state')
                    serialized=json.dumps(data)
                    result['private_keys_absent']=not any('"'+key+'"' in serialized for key in ('expression','worked_solution','worked_solution_document','correct_choice','criteria'))
            assert result.get('practice_http')==200 and result.get('private_keys_absent') is True
            report[label]=result
    after,after_calls=await snapshot()
    report['saved_state_fingerprint']=fingerprint(after)
    report['saved_state_unchanged']=fingerprint(before)==fingerprint(after)
    report['new_usage_events']=after_calls-calls
    assert report['saved_state_unchanged'] and report['new_usage_events']==0
    print(json.dumps(report,sort_keys=True))
asyncio.run(main())
