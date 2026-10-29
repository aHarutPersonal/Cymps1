"""Session context from onboarding: situation chips and note (Task A3).

The v3 onboarding "Your situation" step sends chips and an optional note with
``POST /sessions``. They are stored on the session and reach the comparison,
blueprint, backbone and week prompts; for v3 (V2 key set) sessions they also
replace the retired constraints/capability interview answers.
"""

import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import ValidationError

from app.api.v1 import sessions as sessions_api
from app.models.chat import ChatThread
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.user_profile import UserProfile
from app.schemas.session import SessionCreate
from app.services import session_context

CHIPS = [
    "I work full-time",
    "I’m a student",
    "Mornings are best",
    "Evenings are best",
    "I commute",
    "Limited budget for books",
]
SITUATION = {
    "situation": ["I work full-time", "I commute", "Evenings are best"],
    "note": "Two kids under five, so weekends are out.",
}


def _create_db() -> AsyncMock:
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = SimpleNamespace(scalar_one_or_none=lambda: None)
    return db


def _payload(**extra) -> dict:
    return {
        "age": 31,
        "financial_status": "not_specified",
        "interests": ["Investing"],
        "goal": "Build wealth",
        **extra,
    }


# ---------------------------------------------------------------------------
# Request schema
# ---------------------------------------------------------------------------


def test_schema_accepts_every_design_chip_and_any_other_string():
    chips = [*CHIPS, "Night shifts"]
    data = SessionCreate(**_payload(situation=chips))
    assert data.situation == chips


@pytest.mark.parametrize(
    "extra",
    [
        {"situation": [f"chip {index}" for index in range(9)]},  # more than 8
        {"situation": [""]},  # empty chip
        {"situation": ["   "]},  # blank chip
        {"situation": ["x" * 61]},  # chip over 60 characters
        {"situation_note": "n" * 501},  # note over 500 characters
    ],
)
def test_schema_rejects_out_of_range_situation(extra):
    with pytest.raises(ValidationError):
        SessionCreate(**_payload(**extra))


def test_schema_limits_are_inclusive_and_text_is_trimmed():
    data = SessionCreate(
        **_payload(
            situation=["x" * 60, "  I   commute  "] + ["y"] * 6,
            situation_note=("n" * 500),
        )
    )
    assert len(data.situation) == 8
    assert data.situation[1] == "I commute"
    assert len(data.situation_note) == 500


@pytest.mark.parametrize("blank", ["", "   ", None])
def test_blank_note_and_null_situation_mean_nothing_was_said(blank):
    data = SessionCreate(**_payload(situation=None, situation_note=blank))
    assert data.situation == []
    assert data.situation_note is None


# ---------------------------------------------------------------------------
# POST /sessions
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_session_persists_situation():
    db = _create_db()
    data = SessionCreate(
        **_payload(situation=SITUATION["situation"], situation_note=SITUATION["note"])
    )

    response = await sessions_api.create_session(
        data, db, SimpleNamespace(id="user-1")
    )

    created = db.add.call_args.args[0]
    assert created.situation_json == SITUATION
    assert created.user_goal == "Build wealth"
    assert created.user_financial_status == "not_specified"
    assert created.phase == SessionPhase.IDOL_SELECTION
    assert response["phase"] == "idol_selection"
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_create_session_stores_chips_without_a_note_and_a_note_without_chips():
    chips_only = _create_db()
    await sessions_api.create_session(
        SessionCreate(**_payload(situation=["I commute"])),
        chips_only,
        SimpleNamespace(id="user-1"),
    )
    assert chips_only.add.call_args.args[0].situation_json == {
        "situation": ["I commute"],
        "note": None,
    }

    note_only = _create_db()
    await sessions_api.create_session(
        SessionCreate(**_payload(situation_note="Night shifts")),
        note_only,
        SimpleNamespace(id="user-1"),
    )
    assert note_only.add.call_args.args[0].situation_json == {
        "situation": [],
        "note": "Night shifts",
    }


@pytest.mark.asyncio
async def test_old_client_without_situation_still_creates():
    # The exact body an app build from before v3 sends: no situation fields.
    old_body = {
        "age": 31,
        "financial_status": "Employed, a little savings",
        "interests": ["Investing"],
        "goal": "Build wealth",
    }
    data = SessionCreate.model_validate(old_body)
    assert data.situation == []
    assert data.situation_note is None

    db = _create_db()
    response = await sessions_api.create_session(
        data, db, SimpleNamespace(id="user-1")
    )

    created = db.add.call_args.args[0]
    assert created.situation_json is None
    assert created.user_financial_status == "Employed, a little savings"
    assert response["phase"] == "idol_selection"
    # financial_status stays required for older clients.
    with pytest.raises(ValidationError):
        SessionCreate.model_validate({k: v for k, v in old_body.items() if k != "financial_status"})


# ---------------------------------------------------------------------------
# Situation helpers
# ---------------------------------------------------------------------------


def test_build_and_read_round_trip():
    stored = session_context.build_situation_json(
        SITUATION["situation"], SITUATION["note"]
    )
    assert stored == SITUATION
    assert session_context.read_situation(stored) == (
        SITUATION["situation"],
        SITUATION["note"],
    )
    assert session_context.build_situation_json([], None) is None
    assert session_context.build_situation_json(None, "  ") is None


@pytest.mark.parametrize(
    "malformed",
    [None, "text", ["a"], 7, {"situation": "text"}, {"situation": [1, None, ""]},
     {"note": 5}, MagicMock()],
)
def test_read_situation_never_raises_on_malformed_json(malformed):
    assert session_context.read_situation(malformed) == ([], None)


def test_profile_fields_are_omitted_when_there_is_no_situation():
    old = SimpleNamespace(situation_json=None)
    assert session_context.situation_profile_fields(old) == {}
    assert session_context.situation_profile_fields(SimpleNamespace()) == {}
    assert session_context.situation_profile_fields(MagicMock()) == {}
    full = SimpleNamespace(situation_json=SITUATION)
    assert session_context.situation_profile_fields(full) == {
        "situation": SITUATION["situation"],
        "situation_note": SITUATION["note"],
    }


def test_sentence_is_readable_and_bounded():
    assert (
        session_context.situation_sentence(SITUATION["situation"], SITUATION["note"])
        == "Situation: I work full-time; I commute; Evenings are best. "
        "Two kids under five, so weekends are out."
    )
    assert session_context.situation_sentence(["I commute"], None) == (
        "Situation: I commute."
    )
    assert session_context.situation_sentence([], "Night shifts") == (
        "Situation: Night shifts."
    )
    assert session_context.situation_sentence([], None) == ""
    long = session_context.situation_sentence(
        ["w" * 60] * 8, "n" * 500, max_length=300
    )
    assert len(long) <= 300 and long.endswith("…")


def test_plan_context_lines():
    assert session_context.situation_context_lines(
        SITUATION["situation"], SITUATION["note"]
    ) == [
        "Situation: I work full-time; I commute; Evenings are best",
        "Situation note: Two kids under five, so weekends are out.",
    ]
    assert session_context.situation_context_lines([], None) == []
    assert session_context.situation_context_lines(["I commute"], None) == [
        "Situation: I commute"
    ]


# ---------------------------------------------------------------------------
# user_profile in the comparison / blueprint prompts
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_situation_reaches_user_profile(monkeypatch):
    from app.tasks import plans as plan_tasks
    from tests.test_automatic_results_pipeline import (
        _Result,
        _current_scores,
        _use_session_lock,
    )

    session = IntakeSession(
        id="session-1",
        user_id="user-1",
        idol_id="idol-1",
        phase=SessionPhase.COMPARISON,
        user_age=28,
        user_financial_status="not_specified",
        user_interests=["investing"],
        user_goal="Build wealth",
        interview_thread_id="thread-1",
        comparison_scores_json=_current_scores(),
        situation_json=SITUATION,
    )
    session.idol = Idol(id="idol-1", name="Ada Lovelace", domain="technology")
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = []
    plan_job = SimpleNamespace(
        id="job-1", status="pending", step="waiting_for_strategy",
        progress_percent=0, error_message=None, weekly_hours=10,
    )
    db = AsyncMock()
    db.execute.side_effect = [_Result(thread), _Result(thread), _Result(plan_job)]
    prompts: dict[str, str] = {}

    async def fake_get_session(*args, **kwargs):
        return session

    async def fake_comparison(*args, **kwargs):
        prompts["comparison"] = kwargs["user_message"]
        yield "Comparison"

    async def fake_blueprint(*args, **kwargs):
        prompts["blueprint"] = kwargs["user_message"]
        yield "Blueprint"

    async def fake_lock(*args, **kwargs):
        return session, thread

    async def noop(*args, **kwargs):
        return None

    monkeypatch.setattr(
        sessions_api, "catalog_mentor_facts",
        AsyncMock(return_value={"origin": "published_catalog", "facts": []}),
    )
    monkeypatch.setattr(sessions_api, "_get_session", fake_get_session)
    _use_session_lock(monkeypatch, session)
    monkeypatch.setattr(sessions_api, "comparison_stream", fake_comparison)
    monkeypatch.setattr(sessions_api, "blueprint_stream", fake_blueprint)
    monkeypatch.setattr(sessions_api, "_lock_interview_completion_state", fake_lock)
    monkeypatch.setattr(sessions_api, "_sync_user_profile_from_interview", noop)
    monkeypatch.setattr(sessions_api, "_release_owned_thread_claim", noop)
    monkeypatch.setattr(plan_tasks.run_plan_generation, "delay", MagicMock())

    response = await sessions_api.generate_results(
        "session-1", db, SimpleNamespace(id="user-1")
    )
    body = "".join([chunk async for chunk in response.body_iterator])

    assert '"type": "done"' in body
    for section in ("comparison", "blueprint"):
        prompt = prompts[section]
        assert '"situation": ["I work full-time", "I commute", "Evenings are best"]' in prompt
        assert '"situation_note": "Two kids under five, so weekends are out."' in prompt


def test_old_sessions_keep_their_prompt_profile_unchanged():
    # No situation fields at all, so a pre-v3 session renders byte-identically.
    profile = {"age": 28, "goal": "Build wealth"}
    profile.update(session_context.situation_profile_fields(SimpleNamespace(situation_json=None)))
    assert profile == {"age": 28, "goal": "Build wealth"}


@pytest.mark.asyncio
async def test_situation_reaches_the_comparison_scorer_profile(monkeypatch):
    from app.tasks import comparison as comparison_tasks
    from tests.test_comparison_scores_backfill import (
        FakeSessionMaker,
        ScalarResult,
        _session,
    )

    session = _session(situation_json=SITUATION, user_goal="Build wealth")
    db = AsyncMock()
    db.execute.return_value = ScalarResult(session)
    monkeypatch.setattr(comparison_tasks, "async_session_maker", FakeSessionMaker(db))
    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client", lambda **kwargs: object()
    )
    calls = []

    async def fake_generate(client, **kwargs):
        calls.append(kwargs)
        return {"dimensions": [], "milestones": []}

    monkeypatch.setattr(
        "app.services.comparison.scoring.generate_comparison_scores", fake_generate
    )

    await comparison_tasks._backfill_comparison_scores_async("sess-1")

    profile = json.loads(calls[0]["user_profile_json"])
    assert profile["situation"] == SITUATION["situation"]
    assert profile["situation_note"] == SITUATION["note"]


# ---------------------------------------------------------------------------
# Backbone and week prompt contexts
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_plan_session_context_carries_the_situation():
    from app.tasks.plans import _load_session_context
    from tests.test_plan_session_trigger import _FakeDB

    session = SimpleNamespace(
        interview_thread_id=None,
        comparison_output="Comparison",
        blueprint_output="Blueprint",
        user_goal="Build wealth",
        situation_json=SITUATION,
    )
    ctx = await _load_session_context(_FakeDB([session]), user_id="u1", idol_id="i1")
    assert ctx["situation"] == SITUATION["situation"]
    assert ctx["situation_note"] == SITUATION["note"]

    # A session from before v3 has neither column value nor attribute.
    for old in (
        SimpleNamespace(interview_thread_id=None, comparison_output="C",
                        blueprint_output="B", user_goal="g", situation_json=None),
        SimpleNamespace(interview_thread_id=None, comparison_output="C",
                        blueprint_output="B", user_goal="g"),
    ):
        ctx = await _load_session_context(_FakeDB([old]), user_id="u1", idol_id="i1")
        assert "situation" not in ctx and "situation_note" not in ctx


def test_backbone_and_week_prompts_render_the_situation_lines():
    """The lines join `user_context`, which the backbone prompt renders and the
    plan stores as `user_context_snapshot` for week expansion."""
    from app.services.llm.prompt_loader import load_and_render

    lines = session_context.situation_context_lines(
        SITUATION["situation"], SITUATION["note"]
    )
    user_context = "\n".join(["User Age: 31", *lines])
    from app.services.planning.capacity import capacity_prompt_params

    backbone = load_and_render(
        "plan_backbone_generate.txt",
        {
            "duration_weeks": "12", "user_goal": "Build wealth",
            **capacity_prompt_params(300), "target_age": "31",
            "user_context": user_context, "idol_name": "Ada",
            "idol_profile_json": "{}", "idol_persona_json": "{}",
            "idol_milestones_json": "[]", "gaps_json": "[]",
            "readiness_by_gap_json": "{}", "learner_baseline_json": "",
            "interview_transcript_json": "", "comparison_summary": "",
            "blueprint_markdown": "", "previous_cycle_block": "",
        },
    )
    assert "Situation: I work full-time; I commute; Evenings are best" in backbone
    assert "Situation note: Two kids under five" in backbone


# ---------------------------------------------------------------------------
# Ruling: V2 sessions fill profile constraints from the situation
# ---------------------------------------------------------------------------


def _v2_inputs(**extra) -> dict:
    return {
        "interview_key_set": "v2",
        "weekly_capacity_hours": 6,
        "achievement_baseline_status": "missing",
        **extra,
    }


@pytest.mark.asyncio
async def test_v2_profile_constraints_come_from_the_situation():
    from tests.test_interview_profile_persistence import _Database

    profile = UserProfile(id="p1", user_id="user-1", constraints=None)
    session = IntakeSession(
        id="session-1", user_id="user-1", user_goal="Build wealth",
        situation_json=SITUATION,
    )
    for _ in range(2):  # idempotent on retry
        await sessions_api._sync_user_profile_from_interview(
            _Database(profile), session=session, user_id="user-1",
            plan_inputs=_v2_inputs(),
        )
    assert profile.constraints == [
        "Situation: I work full-time; I commute; Evenings are best. "
        "Two kids under five, so weekends are out."
    ]


@pytest.mark.asyncio
async def test_v2_profile_constraints_keep_the_existing_length_limit():
    from tests.test_interview_profile_persistence import _Database

    profile = UserProfile(id="p1", user_id="user-1", constraints=["Older constraint"])
    session = IntakeSession(
        id="session-1", user_id="user-1",
        situation_json={"situation": ["w" * 60] * 8, "note": "n" * 500},
    )
    await sessions_api._sync_user_profile_from_interview(
        _Database(profile), session=session, user_id="user-1", plan_inputs=_v2_inputs(),
    )
    assert profile.constraints[1] == "Older constraint"
    assert len(profile.constraints[0]) <= 300
    assert profile.constraints[0].startswith("Situation: www")


@pytest.mark.asyncio
async def test_v2_without_a_situation_leaves_constraints_alone():
    from tests.test_interview_profile_persistence import _Database

    profile = UserProfile(id="p1", user_id="user-1", constraints=["Keep me"])
    session = IntakeSession(id="session-1", user_id="user-1", situation_json=None)
    await sessions_api._sync_user_profile_from_interview(
        _Database(profile), session=session, user_id="user-1", plan_inputs=_v2_inputs(),
    )
    assert profile.constraints == ["Keep me"]


@pytest.mark.asyncio
async def test_v1_profile_constraints_still_come_from_the_interview_answer():
    from tests.test_interview_profile_persistence import _Database

    profile = UserProfile(id="p1", user_id="user-1", constraints=None)
    # Even a session that somehow carries a situation keeps the V1 behaviour.
    session = IntakeSession(
        id="session-1", user_id="user-1", situation_json=SITUATION,
    )
    plan_inputs = {
        "weekly_capacity_hours": 8,
        "constraints_resources": {
            "answer": "I have a laptop, but only weekday evenings.",
            "source_message_id": "m1",
        },
    }
    await sessions_api._sync_user_profile_from_interview(
        _Database(profile), session=session, user_id="user-1", plan_inputs=plan_inputs,
    )
    assert profile.constraints == ["I have a laptop, but only weekday evenings."]


# ---------------------------------------------------------------------------
# Ruling: V2 catalog brief capability line
# ---------------------------------------------------------------------------


async def _brief_for(baseline: dict, *, user_profile=None):
    from tests.test_catalog_personalization import _CapturingFakeDB, _Result, _gap
    from app.services.planning import catalog_lessons as catalog

    return await catalog.build_learner_lesson_brief(
        _CapturingFakeDB([_Result(), _Result()]),
        user_id="user-1",
        plan=SimpleNamespace(id="plan-1", weekly_hours=3, roadmap_json={}),
        item=SimpleNamespace(id="item-1", title="A memo", success_metric="A checked memo"),
        gap=_gap(),
        user_profile=user_profile,
        session_context={"learner_baseline": baseline},
        idol=SimpleNamespace(id="idol-1", name="Warren Buffett"),
        idol_evidence=None,
    )


@pytest.mark.asyncio
async def test_v2_brief_capability_uses_skill_confidence_and_achievements():
    brief = await _brief_for(
        {
            "interview_key_set": "v2",
            "skill_confidence": {"answer": "2 of 5", "source_message_id": "m1"},
            "achievement_inventory": {"answer": "I valued three small caps."},
        }
    )
    assert brief.current_capability == (
        "Self-rated confidence: 2 of 5. Achievements: I valued three small caps."
    )
    assert brief.fact_map()["learner.current_capability"].value == brief.current_capability


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "answer,rendered",
    [("2", "2 of 5"), ("4 of 5", "4 of 5"), (" 5/5", "5 of 5"), ("3.", "3 of 5")],
)
async def test_v2_brief_renders_the_confidence_as_n_of_5(answer, rendered):
    brief = await _brief_for(
        {"interview_key_set": "v2", "skill_confidence": {"answer": answer}}
    )
    assert brief.current_capability == f"Self-rated confidence: {rendered}."


@pytest.mark.asyncio
async def test_v2_brief_handles_partial_and_provider_projected_baselines():
    achievements_only = await _brief_for(
        {"interview_key_set": "v2", "skill_confidence": None,
         "achievement_inventory": {"answer": "Nothing yet"}}
    )
    assert achievements_only.current_capability == "Achievements: Nothing yet"

    unparseable = await _brief_for(
        {"interview_key_set": "v2", "skill_confidence": {"answer": "pretty good"}}
    )
    assert unparseable.current_capability == ""

    nothing = await _brief_for({"interview_key_set": "v2"})
    assert nothing.current_capability == ""
    assert "learner.current_capability" not in nothing.fact_map()


@pytest.mark.asyncio
async def test_v2_brief_keeps_checked_skills_ahead_of_self_report():
    brief = await _brief_for(
        {
            "interview_key_set": "v2",
            "skill_confidence": {"answer": "2 of 5"},
            "skill_diagnostics": [
                {"skill_id": "profit_vs_cash", "status": "needs_practice_on_item",
                 "scope": "One item only"}
            ],
        }
    )
    assert brief.current_capability.startswith("Skill checks (not general mastery):")
    assert "Self-reported capability: Self-rated confidence: 2 of 5." in (
        brief.current_capability
    )


@pytest.mark.asyncio
async def test_v1_brief_capability_is_unchanged():
    brief = await _brief_for(
        {
            "current_capability": {"answer": "I can read a balance sheet."},
            # Even stray V2 keys on an unmarked/V1 baseline are ignored.
            "skill_confidence": {"answer": "2 of 5"},
            "achievement_inventory": {"answer": "Shipped a prototype."},
        }
    )
    assert brief.current_capability == "I can read a balance sheet."

    marked_v1 = await _brief_for(
        {
            "interview_key_set": "v1",
            "current_capability": {"answer": "I can read a balance sheet."},
            "skill_confidence": {"answer": "2 of 5"},
        }
    )
    assert marked_v1.current_capability == "I can read a balance sheet."
