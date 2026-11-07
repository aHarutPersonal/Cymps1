"""Shared test fixture for Phase 0.4 (exact-value binding in code, 2026-11-04).

Since Phase 0.4 the server binds, without a model call, every numeric span
whose quantities exactly equal a declared datum or a server-computed result.
Many existing tests exercise the MODEL binder's mechanics (call counts,
corrections, cancellation, merges) with packages whose spans are now
server-computable. ``model_binder_mechanics`` keeps those tests on the
earlier behaviour: preflight binds only literal datum spans in code, and the
final lesson review binds nothing up front. The binding itself is covered
in tests/test_phase0_numerals.py.
"""
import pytest


@pytest.fixture
def model_binder_mechanics(monkeypatch):
    from app.services.planning import evidence_resolver, lesson_review
    from app.services.planning.lesson_review import ReviewEvidencePatch

    real = evidence_resolver._case_index

    def data_only(package):
        return {key: (case, [value for value in values if value.kind == "datum"])
                for key, (case, values) in real(package).items()}

    # Only the binder's index: the activity gate (Phase 0.3) is unchanged.
    monkeypatch.setattr(evidence_resolver, "_case_index", data_only)
    monkeypatch.setattr(lesson_review, "_server_bound_evidence", lambda *args, **kwargs: ReviewEvidencePatch())
