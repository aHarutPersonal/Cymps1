"""_build_session_response surfaces comparison_scores_json as comparisonScores."""
from types import SimpleNamespace
from datetime import datetime, timezone

from app.api.v1.sessions import _build_session_response
from app.schemas.session import SessionResponse


def _session(scores):
    return SimpleNamespace(
        id="s1", phase=None, user_age=24, user_financial_status="",
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


def test_response_model_preserves_scores_under_client_contract_key():
    """Catch FastAPI/Pydantic filtering after the response dict is built."""
    scores = {
        "dimensions": [{"id": "capital", "you": 35, "idol": 70}],
        "milestones": [{"id": "m1", "label": "First milestone"}],
    }

    response = SessionResponse.model_validate(
        _build_session_response(_session(scores))
    ).model_dump(mode="json", by_alias=True)

    assert response["comparisonScores"] == scores


def test_null_when_absent():
    out = _build_session_response(_session(None))
    assert out["comparisonScores"] is None
