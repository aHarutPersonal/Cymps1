"""
Tests for the blueprint → plan auto-trigger wiring.

Covers the session-context threading into plan generation and the
helpers added for the agentic plan pipeline.
"""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.services.llm.prompt_loader import _UNTRUSTED_OPEN, load_and_render
from app.services.transcripts import build_chat_history_json
from app.tasks.plans import _blueprint_phase_for_week, _load_session_context
from app.api.v1.plans import _detail_job_is_stale, _plan_job_is_stale


class _FakeMessage:
    def __init__(self, role_value: str, content: str):
        class _Role:
            def __init__(self, value):
                self.value = value
        self.role = _Role(role_value)
        self.content = content


class _FakeResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


class _FakeDB:
    """Returns queued scalar results, one per execute() call, in order."""

    def __init__(self, results):
        self._results = list(results)

    async def execute(self, *args, **kwargs):
        return _FakeResult(self._results.pop(0))


class TestBlueprintPhaseMapping:
    def test_week_ranges_map_to_blueprint_phases(self):
        assert _blueprint_phase_for_week(1) == "Weeks 1-3: Foundation"
        assert _blueprint_phase_for_week(3) == "Weeks 1-3: Foundation"
        assert _blueprint_phase_for_week(4) == "Weeks 4-6: Core Skills"
        assert _blueprint_phase_for_week(6) == "Weeks 4-6: Core Skills"
        assert _blueprint_phase_for_week(7) == "Weeks 7-9: Applied Practice"
        assert _blueprint_phase_for_week(9) == "Weeks 7-9: Applied Practice"
        assert _blueprint_phase_for_week(10) == "Weeks 10-12: Integration"
        assert _blueprint_phase_for_week(12) == "Weeks 10-12: Integration"
        assert _blueprint_phase_for_week(None) == "Weeks 1-3: Foundation"


class TestPlanJobRecovery:
    def test_recent_job_is_not_stale(self):
        now = datetime(2026, 7, 11, tzinfo=timezone.utc)
        job = SimpleNamespace(
            updated_at=now - timedelta(minutes=5),
            created_at=now - timedelta(minutes=5),
        )

        assert _plan_job_is_stale(job, now=now) is False

    def test_job_older_than_worker_time_limit_is_stale(self):
        now = datetime(2026, 7, 11, tzinfo=timezone.utc)
        job = SimpleNamespace(
            updated_at=now - timedelta(minutes=16),
            created_at=now - timedelta(minutes=20),
        )

        assert _plan_job_is_stale(job, now=now) is True

    def test_missing_timestamps_are_stale(self):
        job = SimpleNamespace(updated_at=None, created_at=None)

        assert _plan_job_is_stale(job) is True

    def test_old_detail_job_is_stale(self):
        now = datetime(2026, 7, 11, tzinfo=timezone.utc)
        job = SimpleNamespace(created_at=now - timedelta(minutes=16))

        assert _detail_job_is_stale(job, now=now) is True

    def test_recent_detail_job_is_not_stale(self):
        now = datetime(2026, 7, 11, tzinfo=timezone.utc)
        job = SimpleNamespace(created_at=now - timedelta(minutes=2))

        assert _detail_job_is_stale(job, now=now) is False


class TestLoadSessionContext:
    @pytest.mark.asyncio
    async def test_returns_empty_for_legacy_jobs_without_user_or_idol(self):
        # Legacy /plans path: no user/idol to resolve a session → no context,
        # db never touched.
        assert await _load_session_context(db=None, user_id=None, idol_id=None) == {}
        assert await _load_session_context(db=object(), user_id="u1", idol_id=None) == {}

    @pytest.mark.asyncio
    async def test_returns_empty_when_no_session_found(self):
        db = _FakeDB([None])  # IntakeSession lookup → None
        assert await _load_session_context(db, user_id="u1", idol_id="i1") == {}

    @pytest.mark.asyncio
    async def test_threads_comparison_blueprint_and_sanitized_transcript(self):
        session = SimpleNamespace(
            interview_thread_id="thread-1",
            comparison_output="By 28 I ran a partnership; you have read three books.",
            blueprint_output="## Weeks 1-3: Foundation\nLearn balance sheets.",
        )
        thread = SimpleNamespace(
            messages=[
                _FakeMessage("assistant", "What have you built?"),
                _FakeMessage("user", "A small trading model."),
            ]
        )
        db = _FakeDB([session, thread])  # session lookup, then thread lookup

        ctx = await _load_session_context(db, user_id="u1", idol_id="i1")

        assert ctx["comparison_summary"] == session.comparison_output
        assert ctx["blueprint_markdown"] == session.blueprint_output
        assert "A small trading model." in ctx["interview_transcript_json"]
        # User turn must be wrapped as untrusted DATA.
        assert _UNTRUSTED_OPEN in ctx["interview_transcript_json"]

    @pytest.mark.asyncio
    async def test_session_id_resolves_without_user_or_idol(self):
        # Exact linkage: a session_id alone is enough (no user/idol needed).
        session = SimpleNamespace(
            interview_thread_id=None,
            comparison_output="by-id verdict",
            blueprint_output=None,
        )
        db = _FakeDB([session])

        ctx = await _load_session_context(db, session_id="s1")

        assert ctx == {"comparison_summary": "by-id verdict"}

    @pytest.mark.asyncio
    async def test_handles_session_without_interview_thread(self):
        session = SimpleNamespace(
            interview_thread_id=None,
            comparison_output="verdict",
            blueprint_output=None,
        )
        db = _FakeDB([session])  # only the session lookup happens

        ctx = await _load_session_context(db, user_id="u1", idol_id="i1")

        assert ctx == {"comparison_summary": "verdict"}


class TestTranscriptHelper:
    def test_serializes_roles_and_content(self):
        messages = [
            _FakeMessage("assistant", "What have you built?"),
            _FakeMessage("user", "A small trading model."),
        ]
        result = build_chat_history_json(messages)
        assert "What have you built?" in result
        assert "A small trading model." in result
        assert '"role":"assistant"' in result

    def test_max_chars_drops_oldest_messages_first(self):
        messages = [
            _FakeMessage("user", "OLDEST " + "x" * 200),
            _FakeMessage("user", "NEWEST " + "y" * 50),
        ]
        result = build_chat_history_json(messages, max_chars=150)
        assert "NEWEST" in result
        assert "OLDEST" not in result


class TestPlanPromptSessionContext:
    def test_plan_generate_renders_session_context(self):
        rendered = load_and_render("plan_generate", {
            "user_goal": "master value investing",
            "idol_name": "Warren Buffett",
            "hours_per_week": "10",
            "target_age": "28",
            "user_context": "beginner",
            "idol_profile_json": {},
            "idol_persona_json": {},
            "idol_milestones_json": [],
            "gaps_json": [],
            "readiness_by_gap_json": {},
            "interview_transcript_json": '[{"role": "user", "content": "I read annual reports weekly"}]',
            "comparison_summary": "By 28 I ran a partnership; you have read three books.",
            "blueprint_markdown": "## Weeks 1-3: Foundation\nLearn balance sheets.",
            "previous_cycle_block": "",
        }, strict=True)

        assert "I read annual reports weekly" in rendered
        assert "you have read three books" in rendered
        assert "Learn balance sheets" in rendered

    def test_plan_item_details_renders_session_context(self):
        rendered = load_and_render("plan_item_details", {
            "task_title": "Read Security Analysis Ch 1-3",
            "user_goal": "master value investing",
            "learning_preferences": "reading",
            "idol_name": "Warren Buffett",
            "idol_domain": "investing",
            "idol_evidence_json": {"timeline": []},
            "session_context": "Blueprint phase for this mission: Weeks 1-3: Foundation",
        }, strict=True)

        assert "Weeks 1-3: Foundation" in rendered
        assert "Read Security Analysis Ch 1-3" in rendered
