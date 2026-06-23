import pytest

from app.models.intake import (
    IntakeSession,
    SessionPhase,
    validate_phase_transition,
)


class TestSessionPhaseStateTransitions:
    """Tests for SessionPhase workflow transitions."""

    def test_valid_forward_transitions(self):
        """All valid forward transitions should pass."""
        assert validate_phase_transition(SessionPhase.INTAKE, SessionPhase.IDOL_SELECTION) is True
        assert validate_phase_transition(SessionPhase.IDOL_SELECTION, SessionPhase.INTERVIEW) is True
        assert validate_phase_transition(SessionPhase.INTERVIEW, SessionPhase.COMPARISON) is True
        assert validate_phase_transition(SessionPhase.COMPARISON, SessionPhase.BLUEPRINT) is True
        assert validate_phase_transition(SessionPhase.BLUEPRINT, SessionPhase.COMPLETED) is True

    def test_invalid_transitions_are_rejected(self):
        """Invalid transitions or skips should be rejected."""
        with pytest.raises(ValueError):
            validate_phase_transition(SessionPhase.INTAKE, SessionPhase.INTERVIEW)
        with pytest.raises(ValueError):
            validate_phase_transition(SessionPhase.INTAKE, SessionPhase.COMPARISON)
        with pytest.raises(ValueError):
            validate_phase_transition(SessionPhase.INTERVIEW, SessionPhase.IDOL_SELECTION)
        with pytest.raises(ValueError):
            validate_phase_transition(SessionPhase.COMPLETED, SessionPhase.INTAKE)

    def test_model_transition_to_success(self):
        """IntakeSession.transition_to updates phase correctly when valid."""
        session = IntakeSession(phase=SessionPhase.INTAKE)
        
        session.transition_to(SessionPhase.IDOL_SELECTION)
        assert session.phase == SessionPhase.IDOL_SELECTION

        session.transition_to(SessionPhase.INTERVIEW)
        assert session.phase == SessionPhase.INTERVIEW

    def test_model_transition_to_failure(self):
        """IntakeSession.transition_to raises ValueError when invalid."""
        session = IntakeSession(phase=SessionPhase.INTAKE)
        
        with pytest.raises(ValueError, match="Invalid phase transition: intake → comparison"):
            session.transition_to(SessionPhase.COMPARISON)
