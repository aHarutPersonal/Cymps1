"""New columns for achievement provenance and plan cycles exist on the models."""
from app.models.user_achievement import UserAchievement, AchievementSource
from app.models.plan import Plan
from app.models.plan_job import PlanGenerationJob


def test_achievement_source_enum_values():
    assert AchievementSource.MANUAL.value == "manual"
    assert AchievementSource.PLAN_ITEM.value == "plan_item"
    assert AchievementSource.PLAN_CYCLE.value == "plan_cycle"


def test_user_achievement_has_provenance_columns():
    cols = UserAchievement.__table__.columns
    assert "source" in cols
    assert "plan_id" in cols
    assert "plan_item_id" in cols
    assert "cycle_number" in cols


def test_plan_has_cycle_columns():
    cols = Plan.__table__.columns
    assert "cycle_number" in cols
    assert "completed_at" in cols
    assert "previous_plan_id" in cols


def test_plan_generation_job_has_cycle_columns():
    cols = PlanGenerationJob.__table__.columns
    assert "cycle_number" in cols
    assert "previous_plan_id" in cols
