from copy import deepcopy
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.api.v1 import jobs
from app.models.plan_job import PlanGenerationJob
from app.services.planning import generator
from app.tasks import plans
from tests.test_plan_generation_performance import _backbone, _expanded_week_one


@pytest.mark.asyncio
async def test_validated_milestones_fire_after_durable_work_and_on_resume(monkeypatch):
    stored = None
    events = []

    async def save(value):
        nonlocal stored
        stored = deepcopy(value)
        events.append(("saved", tuple(value["stages"])))

    async def stage(value):
        events.append(("stage", value))

    async def backbone(**kwargs):
        value = _backbone()
        await kwargs["candidate_callback"](value, SimpleNamespace(provider="test", model="test"), [])
        return value

    make_backbone = AsyncMock(side_effect=backbone)
    make_week = AsyncMock(return_value=_expanded_week_one().weeks[0])
    monkeypatch.setattr(generator, "_generate_plan_backbone", make_backbone)
    monkeypatch.setattr(generator, "generate_plan_week_from_backbone", make_week)
    kwargs = dict(idol_name="Ada", user_goal="Learn computational thinking", hours_per_week=5,
                  save_generation_checkpoint=save, on_generation_stage=stage)
    first = await generator._generate_llm_items(**kwargs)
    assert events == [
        ("saved", ("backbone",)), ("stage", "backbone_ready"),
        ("saved", ("backbone", "week_one")), ("stage", "week_one_ready"),
    ]
    events.clear()
    resumed = await generator._generate_llm_items(**kwargs, generation_checkpoint=stored)
    assert first == resumed
    assert events == [("stage", "backbone_ready"), ("stage", "week_one_ready")]
    make_backbone.assert_awaited_once()
    make_week.assert_awaited_once()


@pytest.mark.asyncio
async def test_saved_invalid_backbone_does_not_claim_roadmap_is_ready(monkeypatch):
    stage = AsyncMock()

    async def invalid(**kwargs):
        value = _backbone()
        value.weeks[0].tasks[0].estimated_hours = 7
        await kwargs["candidate_callback"](
            value, SimpleNamespace(provider="test", model="test"), ["week 1 has incorrect capacity"],
        )
        raise ValueError("week 1 has incorrect capacity")

    client = SimpleNamespace(model="test", generate_and_validate=AsyncMock(
        return_value=(None, SimpleNamespace(error="repair unavailable"))))
    monkeypatch.setattr(generator, "_generate_plan_backbone", invalid)
    monkeypatch.setattr(generator, "_plan_client", lambda **kwargs: client)
    monkeypatch.setattr(generator, "record_llm_response", AsyncMock())
    with pytest.raises(RuntimeError):
        await generator._generate_llm_items(
            idol_name="Ada", user_goal="Learn", hours_per_week=5, on_generation_stage=stage,
        )
    stage.assert_not_awaited()


@pytest.mark.asyncio
@pytest.mark.parametrize("stage,step,progress", [
    ("context_ready", "structuring_curriculum", 15),
    ("backbone_ready", "preparing_first_week", 55),
    ("week_one_ready", "finalizing_plan", 85),
])
async def test_api_exposes_the_actual_worker_stage_without_simulated_copy(stage, step, progress):
    job = PlanGenerationJob(
        id="job-1", user_id="owner", idol_id="idol-1", target_age=24,
        status="running", progress_percent=10, step="analyzing_gaps",
        weekly_hours=5, duration_weeks=12,
    )
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: job)
    await plans._update_plan_generation_stage(db, job, stage)
    response = await jobs.get_job_status("job-1", db, SimpleNamespace(id="owner"), job_type="plan")
    assert response.step == step
    assert response.progressPercent == progress
    assert response.thinkingStream.currentLine == job.thinking_text
    assert response.thinkingStream.insight is None
    assert response.status == "running"


def test_one_off_diagnostic_mislabeled_as_daily_still_fails_mission_count():
    from app.services.llm.schemas import PlanBackboneTask
    backbone = _backbone()
    week = backbone.weeks[0]
    week.tasks = [
        PlanBackboneTask(title="Complete accounting diagnostic", type="practice", estimated_hours=2,
                         success_metric="Submit the diagnostic case analysis."),
        PlanBackboneTask(title="Read the supplied worked cases", type="reading", estimated_hours=2,
                         success_metric="Explain cash versus profit using the supplied cases."),
        PlanBackboneTask(title="Repeat transaction classification drills", type="habit", estimated_hours=2,
                         success_metric="Complete four daily drills of thirty minutes."),
    ]
    assert "week 1 has invalid mission task count" in generator.validate_plan_backbone(
        backbone, duration_weeks=12, hours_per_week=6,
    )
    assert week.tasks[0].type == "practice"


@pytest.mark.asyncio
async def test_context_load_reuses_full_achievement_read_for_recent_wins(monkeypatch):
    job = SimpleNamespace(
        id="job-1", user_id="owner", idol_id="idol-1", session_id=None, plan_id=None,
        idol=SimpleNamespace(name="Ada", domain="computing"), created_at=datetime.now(timezone.utc),
        weekly_hours=5, target_age=24, focus="Learn computational thinking", duration_weeks=12,
        cycle_number=1, previous_plan_id=None, generation_checkpoint_json=None,
    )
    achievements = [SimpleNamespace(title=f"Recent achievement {n}", category=SimpleNamespace(value="career"))
                    for n in range(5)]
    achievements.append(SimpleNamespace(title="Older achievement", category=SimpleNamespace(value="older_skill")))
    achievement_queries = []
    db = AsyncMock()
    db.add = MagicMock()

    async def execute(statement):
        sql = str(statement)
        if sql.startswith("UPDATE plan_generation_jobs"):
            return SimpleNamespace(rowcount=1)
        row = None
        rows = []
        if "FROM plan_generation_jobs" in sql:
            row = job
        elif "FROM user_achievements" in sql:
            achievement_queries.append(sql)
            rows = achievements
        elif "FROM idol_timeline_events" in sql:
            rows = [SimpleNamespace(category="career"), SimpleNamespace(category="older_skill")]
        return SimpleNamespace(scalar_one_or_none=lambda: row,
                               scalars=lambda: SimpleNamespace(all=lambda: rows))

    db.execute.side_effect = execute
    class Context:
        async def __aenter__(self): return db
        async def __aexit__(self, *_args): return None

    context_builder = MagicMock(return_value={})
    generated = AsyncMock(return_value=generator.PlanRoadmap())
    monkeypatch.setattr(plans, "async_session_maker", Context)
    monkeypatch.setattr(plans, "_build_idol_plan_context", context_builder)
    monkeypatch.setattr(plans, "_load_session_context", AsyncMock(return_value={}))
    monkeypatch.setattr(plans, "generate_plan", generated)
    monkeypatch.setattr(plans, "_finalize_generated_plan", AsyncMock(return_value={"status": "completed"}))
    result = await plans._run_plan_generation_async("job-1")
    assert result == {"status": "completed"}
    assert len(achievement_queries) == 1
    assert "ORDER BY user_achievements.created_at DESC" in achievement_queries[0]
    assert "LIMIT" not in achievement_queries[0]
    assert context_builder.call_args.kwargs["gaps"] == ["learning", "career", "mindset"]
    user_context = generated.await_args.kwargs["user_context"]
    assert all(f"Recent achievement {n}" in user_context for n in range(5))
    assert "Older achievement" not in user_context
