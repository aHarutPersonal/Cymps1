"""create payload carries provenance; plan_item achievements upsert."""
from app.schemas.achievement import AchievementCreate
from app.models.user_achievement import AchievementSource


def test_create_schema_accepts_provenance():
    data = AchievementCreate(
        title="Did the thing",
        source="plan_item",
        planId="11111111-1111-1111-1111-111111111111",
        planItemId="22222222-2222-2222-2222-222222222222",
        cycleNumber=1,
    )
    assert data.source == AchievementSource.PLAN_ITEM
    assert data.planItemId.endswith("2222")
    assert data.cycleNumber == 1


def test_create_schema_defaults_to_manual():
    data = AchievementCreate(title="Solo win")
    assert data.source == AchievementSource.MANUAL
    assert data.planItemId is None
