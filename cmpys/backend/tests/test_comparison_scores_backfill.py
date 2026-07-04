from unittest.mock import AsyncMock, MagicMock

import pytest

from app.tasks import comparison as comparison_tasks


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
    session.comparison_output = "You are behind, but the path is clear."
    session.interview_thread_id = None
    session.idol = MagicMock()
    session.idol.name = "Benjamin Graham"
    session.user_age = 28
    session.user_financial_status = "modest"
    session.user_interests = ["investing"]
    session.idol_facts_json = {}
    for key, value in overrides.items():
        setattr(session, key, value)
    return session


@pytest.mark.asyncio
async def test_backfill_generates_and_persists_scores(monkeypatch):
    session = _session()
    db = AsyncMock()
    db.execute.return_value = ScalarResult(session)
    monkeypatch.setattr(comparison_tasks, "async_session_maker", FakeSessionMaker(db))
    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client", lambda **kwargs: object()
    )

    generated = {"dimensions": [{"id": "capital", "you": 20, "idol": 75}], "milestones": []}
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
    db.commit.assert_awaited_once()
    assert calls[0]["idol_name"] == "Benjamin Graham"
    assert calls[0]["comparison_summary"] == session.comparison_output


@pytest.mark.asyncio
async def test_backfill_skips_when_scores_already_present(monkeypatch):
    session = _session(comparison_scores_json={"dimensions": []})
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
async def test_backfill_leaves_session_untouched_when_scorer_fails(monkeypatch):
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

    assert result["status"] == "failed"
    assert session.comparison_scores_json is None
    db.commit.assert_not_awaited()


def test_maybe_enqueue_scores_backfill_dedupes_and_guards(monkeypatch):
    from app.api.v1 import sessions as sessions_api

    enqueued = []
    monkeypatch.setattr(
        comparison_tasks.backfill_comparison_scores,
        "apply_async",
        lambda **kwargs: enqueued.append(kwargs),
    )
    monkeypatch.setattr(sessions_api, "_scores_backfill_enqueued", set())

    needs_backfill = _session(id="sess-needs")
    sessions_api._maybe_enqueue_scores_backfill(needs_backfill)
    sessions_api._maybe_enqueue_scores_backfill(needs_backfill)
    assert len(enqueued) == 1
    assert enqueued[0]["args"] == ["sess-needs"]
    assert enqueued[0]["queue"] == "low_priority"

    has_scores = _session(id="sess-done", comparison_scores_json={"dimensions": []})
    sessions_api._maybe_enqueue_scores_backfill(has_scores)
    no_verdict = _session(id="sess-early", comparison_output=None)
    sessions_api._maybe_enqueue_scores_backfill(no_verdict)
    assert len(enqueued) == 1
