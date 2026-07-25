from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.tasks import comparison as comparison_tasks


def _current_scores() -> dict:
    return {
        "version": 2,
        "methodology": "like_for_like_evidence",
        "overall": {},
        "dimensions": [],
        "milestones": [],
    }


class ScalarResult:
    def __init__(self, value=None):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


class FakeSessionMaker:
    def __init__(self, db):
        self._db = db

    def __call__(self):
        return self

    async def __aenter__(self):
        return self._db

    async def __aexit__(self, *args):
        return False


def _session(**overrides):
    session = MagicMock()
    session.id = "sess-1"
    session.comparison_scores_json = None
    session.comparison_scores_status = "not_started"
    session.comparison_scores_attempts = 0
    session.comparison_scores_error = None
    session.comparison_scores_last_attempt_at = None
    session.comparison_scores_next_retry_at = None
    session.comparison_output = "You are behind, but the path is clear."
    session.interview_thread_id = None
    session.idol = MagicMock()
    session.idol.name = "Benjamin Graham"
    session.user_age = 28
    session.user_financial_status = "modest"
    session.user_interests = ["investing"]
    session.user_goal = None
    session.idol_facts_json = {}
    for key, value in overrides.items():
        setattr(session, key, value)
    return session


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "existing_scores",
    [None, {"dimensions": [{"id": "capital", "you": 45, "idol": 90}]}],
)
async def test_backfill_generates_and_replaces_missing_or_stale_scores(
    monkeypatch,
    existing_scores,
):
    session = _session(comparison_scores_json=existing_scores)
    db = AsyncMock()
    db.execute.return_value = ScalarResult(session)
    monkeypatch.setattr(comparison_tasks, "async_session_maker", FakeSessionMaker(db))
    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client", lambda **kwargs: object()
    )

    generated = {
        "dimensions": [{"id": "capital", "you": 20, "idol": 75}],
        "milestones": [],
    }
    calls = []

    async def fake_generate(client, **kwargs):
        calls.append(kwargs)
        return generated

    monkeypatch.setattr(
        "app.services.comparison.scoring.generate_comparison_scores", fake_generate
    )

    result = await comparison_tasks._backfill_comparison_scores_async("sess-1")

    assert result["status"] == "completed"
    assert session.comparison_scores_json == generated
    assert db.commit.await_count == 2
    assert session.comparison_scores_status == "ready"
    assert session.comparison_scores_attempts == 1
    assert calls[0]["idol_name"] == "Benjamin Graham"
    assert calls[0]["comparison_summary"] == session.comparison_output


@pytest.mark.asyncio
async def test_backfill_skips_when_scores_already_present(monkeypatch):
    session = _session(comparison_scores_json=_current_scores())
    db = AsyncMock()
    db.execute.return_value = ScalarResult(session)
    monkeypatch.setattr(comparison_tasks, "async_session_maker", FakeSessionMaker(db))

    async def fail_generate(client, **kwargs):
        raise AssertionError("scorer must not run when scores exist")

    monkeypatch.setattr(
        "app.services.comparison.scoring.generate_comparison_scores", fail_generate
    )

    result = await comparison_tasks._backfill_comparison_scores_async("sess-1")

    assert result == {"status": "skipped", "reason": "scores_already_present"}
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_backfill_skips_without_comparison_output(monkeypatch):
    session = _session(comparison_output=None)
    db = AsyncMock()
    db.execute.return_value = ScalarResult(session)
    monkeypatch.setattr(comparison_tasks, "async_session_maker", FakeSessionMaker(db))

    result = await comparison_tasks._backfill_comparison_scores_async("sess-1")

    assert result == {"status": "skipped", "reason": "no_comparison_output"}
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_backfill_persists_retryable_state_when_scorer_fails(monkeypatch):
    session = _session()
    db = AsyncMock()
    db.execute.return_value = ScalarResult(session)
    monkeypatch.setattr(comparison_tasks, "async_session_maker", FakeSessionMaker(db))
    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client", lambda **kwargs: object()
    )

    async def fake_generate(client, **kwargs):
        return None

    monkeypatch.setattr(
        "app.services.comparison.scoring.generate_comparison_scores", fake_generate
    )

    result = await comparison_tasks._backfill_comparison_scores_async("sess-1")

    assert result["status"] == "retry_wait"
    assert session.comparison_scores_json is None
    assert session.comparison_scores_status == "retry_wait"
    assert session.comparison_scores_attempts == 1
    assert session.comparison_scores_error
    assert session.comparison_scores_next_retry_at is not None
    assert db.commit.await_count == 2


@pytest.mark.asyncio
async def test_maybe_enqueue_scores_backfill_dedupes_and_guards(monkeypatch):
    from app.api.v1 import sessions as sessions_api

    enqueued = []
    monkeypatch.setattr(
        comparison_tasks.backfill_comparison_scores,
        "apply_async",
        lambda **kwargs: enqueued.append(kwargs),
    )
    db = AsyncMock()
    db.execute.return_value = SimpleNamespace(rowcount=1)

    needs_backfill = _session(id="sess-needs")
    await sessions_api._maybe_enqueue_scores_backfill(needs_backfill, db)
    await sessions_api._maybe_enqueue_scores_backfill(needs_backfill, db)
    assert len(enqueued) == 1
    assert enqueued[0]["args"] == ["sess-needs"]
    assert enqueued[0]["queue"] == "low_priority"
    assert db.execute.await_count == 1
    claim_statement = db.execute.await_args.args[0]
    assert claim_statement.get_execution_options()["synchronize_session"] is False

    has_scores = _session(id="sess-done", comparison_scores_json=_current_scores())
    await sessions_api._maybe_enqueue_scores_backfill(has_scores, db)
    no_verdict = _session(id="sess-early", comparison_output=None)
    await sessions_api._maybe_enqueue_scores_backfill(no_verdict, db)
    assert len(enqueued) == 1
