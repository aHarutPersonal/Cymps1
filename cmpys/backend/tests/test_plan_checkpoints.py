from copy import deepcopy
from types import SimpleNamespace
import pytest
from app.services.planning.checkpoints import PlanCheckpointStore
from app.services.planning import generator
from app.services.llm.schemas import PlanBackboneTask
from tests.test_plan_generation_performance import _backbone, _expanded_week_one


@pytest.mark.asyncio
async def test_checkpoint_integrity_and_changed_inputs():
    saved = []
    async def persist(value): saved.append(value)
    store = PlanCheckpointStore(None, 'same', persist)
    await store.put('backbone', {'test': 'original'}, repair_attempts=1)
    assert PlanCheckpointStore(saved[-1], 'same', None).load('backbone')['repair_attempts'] == 1
    assert PlanCheckpointStore(saved[-1], 'changed', None).load('backbone') is None
    corrupt = deepcopy(saved[-1]);corrupt['stages']['backbone']['record']['payload']['test'] = 'altered'
    with pytest.raises(ValueError, match='integrity'):
        PlanCheckpointStore(corrupt, 'same', None).load('backbone')


@pytest.mark.asyncio
async def test_backbone_survives_failed_week_and_next_retry_reuses_both(monkeypatch):
    saved = None
    calls = {'backbone': 0, 'week': 0}
    async def persist(value):
        nonlocal saved
        saved = deepcopy(value)
    async def backbone(**kwargs):
        calls['backbone'] += 1
        value = _backbone()
        await kwargs['candidate_callback'](value, SimpleNamespace(provider='openlux', model='test'), [])
        return value
    async def week(**kwargs):
        calls['week'] += 1
        if calls['week'] == 1: raise ValueError('interrupted first week')
        return _expanded_week_one().weeks[0]
    monkeypatch.setattr(generator, '_generate_plan_backbone', backbone)
    monkeypatch.setattr(generator, 'generate_plan_week_from_backbone', week)
    args = dict(idol_name='Ada', user_goal='Learn computational thinking', hours_per_week=5,
                duration_weeks=12, save_generation_checkpoint=persist)
    with pytest.raises(RuntimeError):
        await generator._generate_llm_items(**args)
    assert saved['stages']['backbone']
    first = await generator._generate_llm_items(**args, generation_checkpoint=saved)
    second = await generator._generate_llm_items(**args, generation_checkpoint=saved)
    assert first == second
    assert calls == {'backbone': 1, 'week': 2}
    assert generator._plan_recovery_response.get() is None


@pytest.mark.asyncio
async def test_targeted_repair_replaces_only_invalid_week_and_runs_once(monkeypatch):
    original = _backbone(); bad = original.model_copy(deep=True)
    bad.weeks[9].tasks.insert(1, PlanBackboneTask(title='Extra mission', type='course', estimated_hours=2,
                                               success_metric='One checked example exists.'))
    store = PlanCheckpointStore(None, 'test', None)
    await store.put('backbone', bad.model_dump(mode='json'), provider='openlux', repair_attempts=0)
    calls = []
    class Client:
        model = 'test'
        async def generate_and_validate(self, **kwargs):
            calls.append(kwargs)
            return generator.BackboneWeekRepair(weeks=[original.weeks[9]]), SimpleNamespace(provider='openlux', error=None)
    monkeypatch.setattr(generator, '_plan_client', lambda **kwargs: Client())
    async def telemetry(**kwargs): pass
    monkeypatch.setattr(generator, 'record_llm_response', telemetry)
    args = dict(store=store, system_prompt='system', user_prompt='goal', duration_weeks=12,
                hours_per_week=5, telemetry_context={})
    result = await generator._checkpointed_backbone(**args)
    assert result == original
    assert 'replace_only_week_numbers' in calls[0]['user_prompt']
    assert len(calls) == 1
    await generator._checkpointed_backbone(**args)
    assert len(calls) == 1
    assert store.load('backbone')['repair_attempts'] == 1
    assert store.load('backbone')['previous_payload'] == bad.model_dump(mode='json')


@pytest.mark.asyncio
async def test_repair_cannot_change_other_weeks_or_repeat_after_failure(monkeypatch):
    original = _backbone(); bad = original.model_copy(deep=True)
    bad.weeks[9].tasks[0].estimated_hours = 7
    store = PlanCheckpointStore(None, 'test', None)
    await store.put('backbone', bad.model_dump(mode='json'), provider='openlux', repair_attempts=0)
    calls = []
    class Client:
        model = 'test'
        async def generate_and_validate(self, **kwargs):
            calls.append(kwargs)
            return generator.BackboneWeekRepair(weeks=[original.weeks[8]]), SimpleNamespace(provider='openlux', error=None)
    monkeypatch.setattr(generator, '_plan_client', lambda **kwargs: Client())
    async def telemetry(**kwargs): pass
    monkeypatch.setattr(generator, 'record_llm_response', telemetry)
    args = dict(store=store, system_prompt='system', user_prompt='goal', duration_weeks=12,
                hours_per_week=5, telemetry_context={})
    with pytest.raises(ValueError, match='exactly'):
        await generator._checkpointed_backbone(**args)
    with pytest.raises(ValueError, match='exhausted'):
        await generator._checkpointed_backbone(**args)
    assert len(calls) == 1
    assert store.load('backbone')['payload'] == bad.model_dump(mode='json')


@pytest.mark.asyncio
async def test_operator_recovery_requires_same_learner_and_actual_outage(monkeypatch):
    from datetime import datetime, timezone
    from app.tasks.plans import _validated_plan_recovery
    from app.models.plan_job import PlanGenerationJob
    from app.services.curriculum.hashing import sha256_json
    from app.services.llm import recovery
    proof = {'source_job_id': 'prior', 'source_usage_id': 'usage', 'catalog_only': True}
    job = SimpleNamespace(user_id='owner', session_id='intake', idol_id='mentor',
        generation_checkpoint_json={'operator_recovery': {'proof': proof, 'hash': sha256_json(proof)}})
    prior = SimpleNamespace(id='prior', user_id='owner', session_id='intake', idol_id='mentor')
    event = SimpleNamespace(provider='openlux', success=False, created_at=datetime.now(timezone.utc),
        metadata_json={'plan_job_id': 'prior', 'contract_issues': ['OpenLux request failed (TimeoutError; finish=missing)']})
    class DB:
        async def get(self, model, key): return prior if model is PlanGenerationJob else event
    monkeypatch.setattr(recovery, 'operational_recovery_client',
        lambda response, **kwargs: object() if 'TimeoutError' in response.error else None)
    response = await _validated_plan_recovery(DB(), job)
    assert response.provider == 'openlux'
    prior.user_id = 'someone-else'
    with pytest.raises(ValueError, match='matching outage'):
        await _validated_plan_recovery(DB(), job)
    prior.user_id = 'owner';event.metadata_json['contract_issues'] = ['invalid mission count']
    with pytest.raises(ValueError, match='not an operational outage'):
        await _validated_plan_recovery(DB(), job)


def test_catalog_recovery_context_is_restored_after_failure(monkeypatch):
    from app.services.llm import recovery
    import app.services.llm as llm
    primary, native = object(), object()
    failure = object()
    monkeypatch.setattr(llm, 'get_llm_client', lambda **kwargs: primary)
    monkeypatch.setattr(recovery, 'operational_recovery_client',
        lambda response, **kwargs: native if response is failure else None)
    assert recovery.scoped_llm_client(timeout=1, max_tokens=1) is primary
    with pytest.raises(RuntimeError):
        with recovery.scoped_operational_recovery(failure):
            assert recovery.scoped_llm_client(timeout=1, max_tokens=1) is native
            raise RuntimeError('interrupt')
    assert recovery.scoped_llm_client(timeout=1, max_tokens=1) is primary


@pytest.mark.asyncio
async def test_scoped_quality_candidate_is_saved_without_repeating_full_generation(monkeypatch):
    calls = []
    candidate = _backbone();candidate.weeks[9].tasks[0].estimated_hours = 7
    class Client(generator.CompleteRecoveryClient):
        def __init__(self): self.model = 'native-quality'
        async def generate_and_validate(self, **kwargs):
            calls.append(kwargs)
            return candidate, SimpleNamespace(provider='gemini', model=self.model, error=None, finish_reason='STOP')
    monkeypatch.setattr(generator, '_plan_client', lambda **kwargs: Client())
    async def telemetry(**kwargs): pass
    monkeypatch.setattr(generator, 'record_llm_response', telemetry)
    remembered = []
    async def remember(value, response, issues): remembered.append((value, issues))
    token = generator._plan_recovery_response.set(object())
    try:
        with pytest.raises(ValueError, match='week 10'):
            await generator._generate_plan_backbone(system_prompt='system', user_prompt='goal',
                duration_weeks=12, hours_per_week=5, candidate_callback=remember)
    finally:
        generator._plan_recovery_response.reset(token)
    assert len(calls) == 1 and remembered[0][0] == candidate


def test_catalog_cache_recipe_does_not_change_inside_temporary_recovery(monkeypatch):
    import app.services.llm as llm
    from app.services.llm import recovery
    from app.services.planning.catalog_lessons import _default_composer_route_provenance
    primary = SimpleNamespace(provider_name='openlux', model='primary-model')
    native = SimpleNamespace(provider_name='gemini', model='recovery-model')
    failure = object()
    monkeypatch.setattr(llm, 'get_llm_client', lambda **kwargs: primary)
    monkeypatch.setattr(recovery, 'operational_recovery_client',
        lambda response, **kwargs: native if response is failure else None)
    expected = _default_composer_route_provenance()
    with recovery.scoped_operational_recovery(failure):
        assert recovery.scoped_llm_client(timeout=1, max_tokens=1) is native
        assert _default_composer_route_provenance() == expected
    assert _default_composer_route_provenance() == expected

@pytest.mark.asyncio
async def test_first_week_keeps_checked_placement_ahead_of_narrative(monkeypatch):
    async def backbone(**kwargs):
        return _backbone()
    captured = {}
    async def week(**kwargs):
        captured.update(kwargs)
        return _expanded_week_one().weeks[0]
    monkeypatch.setattr(generator, '_checkpointed_backbone', backbone)
    monkeypatch.setattr(generator, 'generate_plan_week_from_backbone', week)
    await generator._generate_llm_items(idol_name='Ada', user_goal='Learn',
        hours_per_week=5, learner_baseline_json='{"checked_level":"beginner"}',
        comparison_summary='Older comparison', blueprint_markdown='Old blueprint')
    context = captured['session_context']
    assert context.startswith('Current learner placement:')
    assert context.index('beginner') < context.index('Older comparison')

@pytest.mark.asyncio
async def test_live_outage_is_reused_for_later_stages_and_does_not_leak(monkeypatch):
    failure = SimpleNamespace(provider='openlux', error='OpenLux request failed (TimeoutError; finish=missing)')
    sentinel = object()
    def recovery(response, **kwargs):
        return sentinel if response is failure else None
    monkeypatch.setattr(generator, 'operational_recovery_client', recovery)
    async def backbone(**kwargs):
        assert generator._recover_plan_outage(failure, timeout=45, max_tokens=9000) is sentinel
        return _backbone()
    async def week(**kwargs):
        assert generator._plan_client(timeout=45, max_tokens=8000) is sentinel
        return _expanded_week_one().weeks[0]
    monkeypatch.setattr(generator, '_checkpointed_backbone', backbone)
    monkeypatch.setattr(generator, 'generate_plan_week_from_backbone', week)
    await generator._generate_llm_items(idol_name='Ada', user_goal='Learn', hours_per_week=5)
    assert generator._plan_recovery_response.get() is None
    assert generator._plan_run_active.get() is False
    generator._recover_plan_outage(failure, timeout=45, max_tokens=9000)
    assert generator._plan_recovery_response.get() is None


def test_daily_preview_length_does_not_replace_execution_depth_check():
    week = _expanded_week_one().weeks[0]
    backbone = _backbone().weeks[0]
    daily = next(task for task in week.binary_tasks if task.type in {'habit', 'practice'})
    daily.description = ' '.join(['meaningful'] * 44)
    assert not generator.validate_week_against_backbone(week, backbone)
    daily.daily_instructions = 'Read and finish.'
    assert any('daily_instructions' in issue for issue in generator.validate_week_against_backbone(week, backbone))
