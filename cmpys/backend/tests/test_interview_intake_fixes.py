"""Tests for the intake-interview fixes: weekly-hours extraction from the
transcript and marker-based interview completion."""
from types import SimpleNamespace

from app.api.v1.sessions import (
    INTERVIEW_COMPLETE_MARKER,
    _COMPLETION_FALLBACK_SIGNALS,
    _extract_weekly_hours,
)
from app.models.chat import MessageRole


def _user(text: str) -> SimpleNamespace:
    return SimpleNamespace(role=MessageRole.USER, content=text)


def _mentor(text: str) -> SimpleNamespace:
    return SimpleNamespace(role=MessageRole.ASSISTANT, content=text)


class TestExtractWeeklyHours:
    def test_simple_statement(self):
        msgs = [_user("I can put in about 12 hours a week on this.")]
        assert _extract_weekly_hours(msgs) == 12

    def test_range_uses_midpoint(self):
        msgs = [_user("Realistically 8-12 hrs per week.")]
        assert _extract_weekly_hours(msgs) == 10

    def test_later_answer_wins(self):
        msgs = [
            _user("Maybe 20 hours a week."),
            _mentor("Twenty? We shall see."),
            _user("Honestly, more like 6 hours a week."),
        ]
        assert _extract_weekly_hours(msgs) == 6

    def test_ignores_mentor_numbers(self):
        msgs = [
            _mentor("I worked 90 hours a week at your age."),
            _user("I read books sometimes."),
        ]
        assert _extract_weekly_hours(msgs) is None

    def test_ignores_hours_without_week_context(self):
        msgs = [_user("I slept 8 hours last night.")]
        assert _extract_weekly_hours(msgs) is None

    def test_none_when_nothing_said(self):
        msgs = [_user("I want to build wealth."), _mentor("Do you now.")]
        assert _extract_weekly_hours(msgs) is None

    def test_clamped_to_sane_band(self):
        msgs = [_user("I will grind 95 hours a week.")]
        assert _extract_weekly_hours(msgs) == 60


class TestCompletionSignals:
    def test_marker_is_the_documented_token(self):
        assert INTERVIEW_COMPLETE_MARKER == "[INTERVIEW_COMPLETE]"

    def test_ambiguous_phrases_are_not_fallback_signals(self):
        # "let me show you" appears in ordinary mid-interview turns and used
        # to end the interview early — it must never come back as a signal.
        for risky in ("let me show you", "i have my answer", "i've heard enough"):
            assert risky not in _COMPLETION_FALLBACK_SIGNALS

    def test_marker_strips_cleanly_from_closing_turn(self):
        closing = (
            "Now I know the measure of you. Let me show you what I had done "
            "by your age...\n" + INTERVIEW_COMPLETE_MARKER
        )
        cleaned = closing.replace(INTERVIEW_COMPLETE_MARKER, "").rstrip()
        assert INTERVIEW_COMPLETE_MARKER not in cleaned
        assert cleaned.endswith("by your age...")
