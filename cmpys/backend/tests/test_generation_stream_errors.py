"""Provider billing failures must not become reconnect/retry loops."""
import pytest

from app.api.v1.sessions import _results_error_event
from app.core.config import settings
from app.services.llm.protocol import ProviderStreamError
from tests.direct_wire import PROVIDERS, Reply, client_for, serve
from tests.test_json_generation_errors import api_error, credit_error


async def stream_failure(provider, error):
    """The ``ProviderStreamError`` a direct client raises for an SDK error."""
    client = client_for(provider)
    serve(client, Reply(usage=None, open_error=error))
    with pytest.raises(ProviderStreamError) as raised:
        async for _ in client.stream_text("System", "User", operation="comparison_stream"):
            pass
    return raised.value


@pytest.fixture(autouse=True)
def quiet(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})
    monkeypatch.setattr("app.services.llm.telemetry.record_usage_records", _ignore)


async def _ignore(*_, **__):
    return True


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("nested", [False, True])
async def test_exhausted_credit_is_not_transient_or_exposed(provider, nested):
    wrapped = await stream_failure(provider, credit_error(provider, nested=nested))
    event = _results_error_event(wrapped, "comparison")
    assert event["code"] == "generation_unavailable"
    assert event["retryable"] is False
    assert event["section"] == "comparison"
    assert "retry_after_seconds" not in event
    assert "PRIVATE" not in str(wrapped) + str(event)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("header,expected", [("120", 120), ("invalid", 60), ("-1", 1), ("99999", 3600)])
async def test_transient_limit_preserves_bounded_retry_delay(provider, header, expected):
    error = api_error(provider, 429, {"code": "rate_limit_exceeded", "message": "PRIVATE"}, header)
    event = _results_error_event(await stream_failure(provider, error), "blueprint")
    assert event["code"] == "generation_rate_limited"
    assert event["retryable"] is True
    assert "PRIVATE" not in str(event)
    assert event.get("retry_after_seconds") == expected


def test_unknown_failure_stays_generic_and_private():
    event = _results_error_event(RuntimeError("PRIVATE database state"), "comparison")
    assert event["code"] == "generation_failed"
    assert "PRIVATE" not in str(event)


@pytest.mark.asyncio
@pytest.mark.parametrize("section", ["comparison", "blueprint"])
async def test_unavailable_stream_preserves_saved_work_and_never_dispatches(monkeypatch, section):
    import json
    from types import SimpleNamespace
    from unittest.mock import AsyncMock
    from app.api.v1 import sessions as api
    from app.models.chat import ChatThread
    from app.models.idol import Idol
    from app.models.intake import IntakeSession, SessionPhase
    from tests.test_automatic_results_pipeline import _Result, _current_scores, _use_session_lock

    phase = SessionPhase.COMPARISON if section == "comparison" else SessionPhase.BLUEPRINT
    saved = None if section == "comparison" else "Previously completed comparison"
    session = IntakeSession(id="session-1", user_id="user-1", idol_id="idol-1", phase=phase,
                            user_age=28, interview_thread_id="thread-1", comparison_output=saved,
                            comparison_scores_json=_current_scores())
    session.idol = Idol(id="idol-1", name="Ada Lovelace", domain="technology")
    thread = ChatThread(id="thread-1", user_id="user-1", idol_id="idol-1")
    thread.messages = []
    job = SimpleNamespace(id="job-1", status="pending", step="waiting_for_strategy", weekly_hours=10)
    db = AsyncMock()
    db.execute.side_effect = [_Result(thread), _Result(thread), _Result(job)]
    monkeypatch.setattr(api, "_get_session", AsyncMock(return_value=session))
    _use_session_lock(monkeypatch, session)
    monkeypatch.setattr(api, "catalog_mentor_facts", AsyncMock(return_value=None))
    monkeypatch.setattr(api, "_sync_user_profile_from_interview", AsyncMock())
    release, dispatch = AsyncMock(), AsyncMock()
    monkeypatch.setattr(api, "_release_owned_thread_claim", release)
    monkeypatch.setattr(api, "_dispatch_session_plan_job", dispatch)

    async def fail(*args, **kwargs):
        yield "Unfinished output"
        raise ProviderStreamError("openai", "GenerationUnavailable", code="generation_unavailable",
                                  retryable=False)

    monkeypatch.setattr(api, f"{section}_stream", fail)
    response = await api.generate_results("session-1", db, SimpleNamespace(id="user-1"))
    events = [json.loads(chunk.removeprefix("data: ")) async for chunk in response.body_iterator]
    assert events[-1]["code"] == "generation_unavailable"
    assert events[-1]["retryable"] is False
    assert events[0] == {"type": "plan_job", "job_id": "job-1"}
    assert session.phase == phase
    assert session.comparison_output == saved
    assert session.blueprint_output is None
    assert all(event["type"] != "done" for event in events)
    # The plan needs only the saved comparison, so it starts before the blueprint
    # streams; a failed comparison never starts it.
    if section == "comparison":
        dispatch.assert_not_awaited()
    else:
        dispatch.assert_awaited_once()
    release.assert_awaited_once()
