"""
Tests for the blueprint → plan auto-trigger wiring.

Covers the session-context threading into plan generation and the
helpers added for the agentic plan pipeline.
"""
import pytest

from app.services.llm.prompt_loader import load_and_render
from app.services.transcripts import build_chat_history_json
from app.tasks.plans import _blueprint_phase_for_week, _load_session_context


class _FakeMessage:
    def __init__(self, role_value: str, content: str):
        class _Role:
            def __init__(self, value):
                self.value = value
        self.role = _Role(role_value)
        self.content = content


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


class TestLoadSessionContext:
    @pytest.mark.asyncio
    async def test_returns_empty_for_legacy_jobs_without_session(self):
        # Legacy /plans path: no session_id → no context, db never touched.
        assert await _load_session_context(db=None, session_id=None) == {}


class TestTranscriptHelper:
    def test_serializes_roles_and_content(self):
        messages = [
            _FakeMessage("assistant", "What have you built?"),
            _FakeMessage("user", "A small trading model."),
        ]
        result = build_chat_history_json(messages)
        assert "What have you built?" in result
        assert "A small trading model." in result
        assert '"role": "assistant"' in result

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
            "session_context": "Blueprint phase for this mission: Weeks 1-3: Foundation",
        }, strict=True)

        assert "Weeks 1-3: Foundation" in rendered
        assert "Read Security Analysis Ch 1-3" in rendered
