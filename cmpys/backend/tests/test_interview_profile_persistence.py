from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.api.v1.sessions import _sync_user_profile_from_interview
from app.models.intake import IntakeSession
from app.models.user_profile import UserProfile


class _Result:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


class _Database:
    def __init__(self, profile=None, *, results=None):
        self.profile = profile
        self.results = list(results or [])
        self.added = []
        self.flushes = 0

    async def execute(self, _statement):
        if self.results:
            return _Result(self.results.pop(0))
        return _Result(self.profile)

    def add(self, value):
        self.added.append(value)
        self.profile = value

    async def flush(self):
        self.flushes += 1


def _record(answer: str, source: str) -> dict:
    return {
        "answer": answer,
        "source_message_id": source,
        "question_id": f"question-{source}",
    }


@pytest.mark.asyncio
async def test_registers_capacity_and_self_reported_achievement_idempotently():
    profile = UserProfile(
        id="profile-1",
        user_id="user-1",
        goals=["Long-term product goal"],
        interests=["Technology"],
        constraints=None,
        learning_preferences=None,
        achievements_raw=None,
    )
    db = _Database(profile)
    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        user_goal="Build a useful product",
        user_interests=["Technology", "Design"],
    )
    plan_inputs = {
        "weekly_capacity_hours": 8,
        "achievement_baseline_status": "self_reported",
        "achievement_inventory": _record(
            "I shipped a prototype used by five people in June 2026.",
            "achievement-answer",
        ),
        "target_outcome": _record(
            "Publish a stable product with ten active users.",
            "outcome-answer",
        ),
        "current_capability": _record(
            "I can build and test a small app independently.",
            "capability-answer",
        ),
        "constraints_resources": _record(
            "I have a laptop and test users, but only weekday evenings.",
            "constraint-answer",
        ),
        "learning_habits_support": _record(
            "Worked examples, deliberate practice, and weekly peer feedback.",
            "learning-answer",
        ),
    }

    await _sync_user_profile_from_interview(
        db,
        session=session,
        user_id="user-1",
        plan_inputs=plan_inputs,
    )
    await _sync_user_profile_from_interview(
        db,
        session=session,
        user_id="user-1",
        plan_inputs=plan_inputs,
    )

    assert profile.weekly_hours == 8
    assert profile.goals[0] == "Publish a stable product with ten active users."
    assert profile.interests == ["Technology", "Design"]
    assert len(profile.constraints) == 1
    assert len(profile.learning_preferences) == 1
    assert profile.achievements_raw == (
        "I shipped a prototype used by five people in June 2026."
    )
    assert profile.skills["self_reported_current_capability"] == {
        "answer": "I can build and test a small app independently.",
        "session_id": "session-1",
        "source_message_id": "capability-answer",
    }
    assert db.added == []
    assert db.flushes == 2


@pytest.mark.asyncio
async def test_creates_profile_when_user_does_not_have_one():
    db = _Database()
    session = SimpleNamespace(user_goal="Learn design", user_interests=["Design"])

    await _sync_user_profile_from_interview(
        db,
        session=session,
        user_id="user-1",
        plan_inputs={"weekly_capacity_hours": 5},
    )

    assert len(db.added) == 1
    assert db.profile.weekly_hours == 5
    assert db.profile.goals == ["Learn design"]


@pytest.mark.asyncio
async def test_explicit_none_does_not_register_as_an_achievement():
    profile = UserProfile(
        id="profile-1",
        user_id="user-1",
        achievements_raw="A stale self-report",
    )
    db = _Database(profile)
    session = IntakeSession(id="session-1", user_id="user-1")

    await _sync_user_profile_from_interview(
        db,
        session=session,
        user_id="user-1",
        plan_inputs={
            "achievement_baseline_status": "none_yet",
            "achievement_inventory": _record("None yet", "achievement-answer"),
        },
    )

    assert profile.achievements_raw is None


@pytest.mark.asyncio
async def test_replaying_an_older_session_does_not_overwrite_newer_profile_data():
    profile = UserProfile(
        id="profile-1",
        user_id="user-1",
        weekly_hours=12,
        achievements_raw="Newer session achievement",
    )
    db = _Database(profile, results=[None, "newer-session-id"])
    session = IntakeSession(
        id="older-session",
        user_id="user-1",
        created_at=datetime.now(timezone.utc) - timedelta(days=1),
    )

    await _sync_user_profile_from_interview(
        db,
        session=session,
        user_id="user-1",
        plan_inputs={
            "weekly_capacity_hours": 4,
            "achievement_baseline_status": "self_reported",
            "achievement_inventory": _record(
                "Older session achievement",
                "old-achievement",
            ),
        },
    )

    assert profile.weekly_hours == 12
    assert profile.achievements_raw == "Newer session achievement"
    assert db.flushes == 0
