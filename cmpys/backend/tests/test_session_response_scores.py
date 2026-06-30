"""_build_session_response surfaces comparison_scores_json as comparisonScores."""
from types import SimpleNamespace
from datetime import datetime, timezone

from app.api.v1.sessions import _build_session_response


def _session(scores):
    return SimpleNamespace(
        id="s1", phase=None, user_age=24, user_financial_status=None,
        user_interests=[], idol=None, interview_turn_count=0,
        comparison_output=None, blueprint_output=None,
        interview_thread_id=None,
        comparison_scores_json=scores,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )


def test_includes_scores_when_present():
    s = _session({"dimensions": [], "milestones": []})
    out = _build_session_response(s)
    assert out["comparisonScores"] == {"dimensions": [], "milestones": []}


def test_null_when_absent():
    out = _build_session_response(_session(None))
    assert out["comparisonScores"] is None
