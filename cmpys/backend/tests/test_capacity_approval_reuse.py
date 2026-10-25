import copy
import pytest
from app.services.planning import lesson_package as module
from tests.test_tutorial_capacity import long_tutorial
from tests.test_short_tutorial_pipeline import short_package

PREVIOUS = {'review_version': 23, 'package_version': 1, 'capability_hash': '1815a97ad0c7246f737c493fbec7b9217c6a5dd6a7d96cacd93c0c34b3afe48f', 'prompt_hash': 'fc899f550b96b760a700da1f5bac50b0118b87b2e615c8106a6b0e4d47ef69eb', 'generation_contract_hash': '4c8e291d46f1d4e58fb1ebc4a09bba28bc0de261d41e400d7ce6ef36c662823d', 'schema_hash': '6c9911659a81cbd8598269be5181940c1bd27d828843305fabac7de560b91a01'}

@pytest.mark.parametrize("previous", [PREVIOUS, {'review_version': 23, 'package_version': 1, 'capability_hash': '1815a97ad0c7246f737c493fbec7b9217c6a5dd6a7d96cacd93c0c34b3afe48f', 'prompt_hash': 'fc899f550b96b760a700da1f5bac50b0118b87b2e615c8106a6b0e4d47ef69eb', 'generation_contract_hash': '90612ce1e3b1ea98c5a841b0ac4aa1805fd4ce957e33e938e5ba79b9a1ad159a', 'schema_hash': '6c9911659a81cbd8598269be5181940c1bd27d828843305fabac7de560b91a01'}])
@pytest.mark.parametrize("mutation", [None, "content", "package", "identity", "schema", "dependency", "extra"])
def test_capacity_only_change_reuses_only_exact_approved_content(monkeypatch, mutation, previous):
    step = long_tutorial(); package = short_package()
    approval = {**previous, "content_hash": module.digest(step), "package_hash": module.digest(package.model_dump(mode="json"))}
    if mutation == "content": step["description"] += " changed"
    if mutation == "package": approval["package_hash"] = "0" * 64
    if mutation == "identity": approval["generation_contract_hash"] = "0" * 64
    if mutation == "schema": approval["schema_hash"] = "0" * 64
    if mutation == "dependency": monkeypatch.setattr(module, "_CAPACITY_REVIEW_DEPENDENCIES", {"lesson_review.py": "0" * 64})
    if mutation == "extra": approval["unrecognized"] = True
    assert module.reusable_published_approval(step, package, approval) is (mutation is None)


def test_current_approval_still_requires_both_content_hashes():
    step=long_tutorial();package=short_package();approval=module.provenance(step,package)
    assert module.reusable_published_approval(step,package,approval)
    approval["package_hash"]="0"*64
    assert not module.reusable_published_approval(step,package,approval)

@pytest.mark.asyncio
async def test_retry_carries_forward_known_unchanged_review_without_provider_calls():
    from app.services.llm.client import LLMResponse
    from app.tasks.plans import _assemble_parallel_lesson_response, _generate_plan_item_details_parallel
    from tests.test_short_tutorial_pipeline import outline
    from tests.test_tutorial_reading_budget import sections
    scaffold=outline(1);package=short_package()
    response=LLMResponse(data=module.render_public_package_results(sections(),package.writer_context()))
    _assemble_parallel_lesson_response(response,step=scaffold['steps'][0],material_titles={'Resource 1'},target_minutes=6)
    assert not response.error
    step=response.data;approval={**PREVIOUS,'content_hash':module.digest(step),'package_hash':module.digest(package.model_dump(mode='json'))}
    saved={**scaffold,'steps':[copy.deepcopy(step)],'_generation':{'outline':scaffold,'outline_contract_version':3,'lesson_validation':{step['id']:approval}}}
    validations={}
    result,calls,error=await _generate_plan_item_details_parallel(system_prompt='Teach',task_title='Sequence',mission_hours=0.1,user_goal='Reason',learning_preferences='examples',idol_name='Mentor',idol_domain='writing',idol_evidence={},session_context='',active_tier='balanced',routing_reason='test',client_factory=lambda **kwargs:pytest.fail('Unchanged published tutorial must not call a provider'),prepared_packages={step['id']:package},validation_records=validations,existing_checkpoint=saved)
    assert error is None and calls == [] and result['steps'] == [step]
    assert validations[step['id']] == module.provenance(step,package)
    assert saved['steps'] == [step]


@pytest.mark.asyncio
@pytest.mark.parametrize("mutation", [None,"owner","input","step","envelope_hash","identity"])
async def test_exact_pinned_private_draft_recovery_retains_all_scope_guards(mutation):
    from tests.test_private_generation_checkpoint import Database,STEP_ID,STEP_HASH
    db=Database();old=db.new_job();previous=db.store(old,validation_identity=PREVIOUS)
    package=short_package()
    assert await previous.save_package(STEP_ID,STEP_HASH,package.model_dump(mode="json"),preflight_passed=False)
    old.status="failed";new=db.new_job();current=db.store(new,validation_identity=module.validation_identity())
    if mutation=="owner": old.private_checkpoint_json["user_id"]="00000000-0000-0000-0000-000000000001"
    if mutation=="input": old.private_checkpoint_json["input_hash"]=module.digest("different inputs")
    if mutation=="step": old.private_checkpoint_json["steps"][STEP_ID]["step_hash"]=module.digest("different step")
    if mutation=="envelope_hash": old.private_checkpoint_json["validation_identity_hash"]="0"*64
    if mutation=="identity":
        old.private_checkpoint_json["validation_identity"]["schema_hash"]="0"*64
        old.private_checkpoint_json["validation_identity_hash"]=module.digest(old.private_checkpoint_json["validation_identity"])
    result=await current.load_step(STEP_ID,STEP_HASH)
    assert (result is not None) is (mutation is None)
    if result:
        assert result["package"]==package.model_dump(mode="json")
        assert result["preflight_passed"] is False
