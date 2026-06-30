"""The comparison_scores_json column exists on IntakeSession."""
from app.models.intake import IntakeSession


def test_intake_session_has_comparison_scores_column():
    assert "comparison_scores_json" in IntakeSession.__table__.columns
