"""Wire contract of the direct Anthropic and OpenAI clients and their callers.

Ported from the retired gateway suites (test_openlux.py, test_zai.py) on
2026-11-07: the same streaming, accounting, redaction and recovery guarantees,
now for Claude Haiku 5.5 and gpt-6-luna. Routing itself is covered by
test_model_routing.py.
"""
import asyncio
from types import SimpleNamespace as NS

import anthropic
import httpx
import httpx2
import openai
import pytest
from pydantic import BaseModel

from app.core.config import Settings, settings
from app.services.llm.anthropic_direct import AnthropicDirectLLMClient
from app.services.llm.client import FallbackLLMClient
from app.services.llm.openai_direct import OpenAIDirectLLMClient, _stream_error
from app.services.llm.protocol import ProviderStreamError
from tests.direct_wire import PROVIDERS, Reply, client_for, request_text, serve


class Answer(BaseModel):
    ok: bool


@pytest.fixture(autouse=True)
def offline(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})


@pytest.fixture
def routed(monkeypatch):
    FallbackLLMClient.reset_circuits_for_tests()
    monkeypatch.setattr(settings, "llm_provider", "routed")
    monkeypatch.setattr(settings, "anthropic_api_key", "fake-anthropic-key")
    monkeypatch.setattr(settings, "openai_api_key", "fake-openai-key")
    monkeypatch.setattr(settings, "anthropic_model", "claude-haiku-5-5")
    monkeypatch.setattr(settings, "openai_model", "gpt-6-luna")
    monkeypatch.setattr(settings, "llm_route_overrides", {})
    yield
    FallbackLLMClient.reset_circuits_for_tests()


@pytest.fixture
def usage_rows(monkeypatch):
    rows = []

    async def record(items, **_):
        rows.extend(items)
        return True

    monkeypatch.setattr("app.services.llm.telemetry.record_usage_records", record)
    return rows


@pytest.mark.asyncio
async def test_json_usage_only_final_chunk_and_schema():
    client = client_for("openai", max_tokens=300, reasoning_reserve=2048)
    wire = serve(client, Reply(pieces=['{"ok":', "true}"], usage=(40, 90), reasoning_text="hidden reasoning"))
    response = await client.generate_json("System", "User", output_model=Answer)
    assert response.data == {"ok": True}
    assert response.error is None
    assert (response.prompt_tokens, response.completion_tokens, response.total_tokens) == (40, 90, 130)
    assert response.provider == "openai" and "hidden" not in response.raw_response
    assert all(stream.closed for stream in wire.streams)
    request = wire.request
    assert request["max_completion_tokens"] == 2348
    assert request["stream_options"] == {"include_usage": True}
    assert request["reasoning_effort"] == "low" and request["store"] is False
    assert "temperature" not in request and "max_tokens" not in request
    assert '"ok"' in request_text(request)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_hidden_reasoning_never_reaches_the_response(provider):
    client = client_for(provider)
    serve(client, Reply('{"ok":true}', reasoning_text="PRIVATE hidden reasoning"))
    response = await client.generate_json("System", "User", output_model=Answer)
    assert response.error is None and response.data == {"ok": True}
    assert "PRIVATE" not in response.model_dump_json()


@pytest.mark.asyncio
@pytest.mark.parametrize("provider, finish", [
    ("openai", None), ("openai", "length"), ("openai", "content_filter"), ("openai", "tool_calls"),
    ("anthropic", "max_tokens"), ("anthropic", "refusal"), ("anthropic", "pause_turn"), ("anthropic", None),
])
async def test_incomplete_json_is_not_accepted_even_when_parseable(provider, finish):
    client = client_for(provider)
    wire = serve(client, Reply('{"ok":true}', finish))
    result = await client.generate_json("System", "User")
    assert result.error and result.data == {}
    assert all(stream.closed for stream in wire.streams)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_json_array_returns_an_error_instead_of_escaping_validation(provider):
    client = client_for(provider)
    serve(client, Reply("[]", "stop"))
    result = await client.generate_json("System", "User")
    assert result.error and result.data == {}


def _mid_stream_error(provider, kind):
    sdk, http = (openai, httpx) if provider == "openai" else (anthropic, httpx2)
    message = "fake-test-key PRIVATE PROMPT"
    if kind == "sdk_error_event":  # an SSE error event the SDK raises as APIError
        return sdk.APIError(message, http.Request("POST", "https://offline.invalid"), body=None)
    if kind == "transport_drop":  # the SDKs do not wrap transport errors raised while iterating
        return http.RemoteProtocolError(message)
    return RuntimeError(message)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("kind", ["sdk_error_event", "transport_drop", "unexpected"])
async def test_error_is_redacted_and_partial_usage_preserved(provider, kind):
    client = client_for(provider)
    wire = serve(client, Reply(pieces=['{"ok":'], usage=(3, 4), error=_mid_stream_error(provider, kind)))
    result = await client.generate_json("System", "User")
    assert result.error and result.data == {}
    assert "PRIVATE" not in result.error and "fake-test-key" not in result.error
    assert all(stream.closed for stream in wire.streams)
    if provider == "openai":  # OpenAI sent its usage chunk before the failure
        assert result.total_tokens == 7


class _SlowAnthropicStream:
    def __init__(self, **_):
        pass

    async def __aenter__(self):
        await asyncio.sleep(1)

    async def __aexit__(self, *exc):
        return False


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_total_timeout_is_enforced(provider):
    client = client_for(provider, timeout=0.01)

    async def create(**_):
        await asyncio.sleep(1)

    client._client = (NS(chat=NS(completions=NS(create=create))) if provider == "openai"
                      else NS(beta=NS(messages=NS(stream=_SlowAnthropicStream))))
    result = await client.generate_json("System", "User")
    assert "TimeoutError" in result.error
    assert result.error_code == "generation_failed" and result.retryable is True


@pytest.mark.asyncio
@pytest.mark.parametrize("method, operation", [
    ("interview_stream", "interview_stream"),
    ("comparison_stream", "comparison_stream"),
    ("blueprint_stream", "blueprint_stream"),
    ("stream_learnlm", "guided_learning_stream"),
])
async def test_plain_text_stream_routes_through_the_operation_model(monkeypatch, routed, method, operation):
    from app.services import gemini

    expected_operation = operation

    async def text(self, system, user, *, operation):
        assert self.provider_name == "openai" and self.model == "gpt-6-luna"
        assert operation == expected_operation
        yield "One question?"

    async def unexpected(self, *args, **kwargs):
        pytest.fail("Unexpected backup stream")
        yield  # pragma: no cover

    monkeypatch.setattr(OpenAIDirectLLMClient, "stream_text", text)
    monkeypatch.setattr(AnthropicDirectLLMClient, "stream_text", unexpected)
    monkeypatch.setattr(gemini, "_gemini_client", lambda: pytest.fail("Unexpected direct Gemini call"))
    assert [c async for c in getattr(gemini, method)("System", "User")] == ["One question?"]


@pytest.mark.asyncio
async def test_interview_recovers_once_from_temporary_pre_text_failure(monkeypatch, routed):
    from app.services import gemini

    async def unavailable(self, system, user, *, operation):
        assert self.timeout == 20  # onboarding keeps a short primary deadline
        raise _stream_error(TimeoutError("private provider details"), 0)
        yield  # pragma: no cover

    calls = []

    async def backup(self, system, user, *, operation):
        calls.append((system, user, operation))
        assert self.timeout == 35
        yield "What have you already built?"

    monkeypatch.setattr(OpenAIDirectLLMClient, "stream_text", unavailable)
    monkeypatch.setattr(AnthropicDirectLLMClient, "stream_text", backup)
    monkeypatch.setattr(gemini, "_gemini_client", lambda: pytest.fail("Unexpected direct Gemini call"))
    assert [c async for c in gemini.interview_stream("System", "User")] == ["What have you already built?"]
    assert calls == [("System", "User", "interview_stream")]


@pytest.mark.asyncio
@pytest.mark.parametrize("partial,temporary,backup_key", [
    (True, True, True),
    (False, False, True),
    (False, True, False),
])
async def test_interview_recovery_never_splices_or_hides_other_failures(monkeypatch, routed, partial, temporary,
                                                                        backup_key):
    from app.services import gemini

    if not backup_key:
        monkeypatch.setattr(settings, "anthropic_api_key", None)

    async def unavailable(self, system, user, *, operation):
        if partial:
            yield "Partial reply"
        error = TimeoutError("private") if temporary else ValueError("private")
        raise _stream_error(error, len("Partial reply") if partial else 0)

    async def unexpected(self, *args, **kwargs):
        pytest.fail("Unexpected fallback")
        yield  # pragma: no cover

    monkeypatch.setattr(OpenAIDirectLLMClient, "stream_text", unavailable)
    monkeypatch.setattr(AnthropicDirectLLMClient, "stream_text", unexpected)
    with pytest.raises(ProviderStreamError, match="openai stream failed") as error:
        _ = [c async for c in gemini.interview_stream("System", "User")]
    assert "private" not in str(error.value)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_stopping_text_consumer_closes_upstream_stream(provider, usage_rows):
    client = client_for(provider)
    wire = serve(client, Reply(pieces=["First", "Second"]))
    output = client.stream_text("System", "User", operation="test")
    assert await anext(output) == "First"
    await output.aclose()
    assert wire.streams and all(stream.closed for stream in wire.streams)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_text_stream_records_actual_provider_and_usage(provider, usage_rows):
    client = client_for(provider)
    wire = serve(client, Reply("Hello", usage=(10, 20)))
    assert [t async for t in client.stream_text("System", "User", operation="test")] == ["Hello"]
    assert usage_rows[0].provider == provider and usage_rows[0].success
    assert usage_rows[0].total_tokens == 30 and all(stream.closed for stream in wire.streams)
    assert "response_format" not in wire.request
    assert "format" not in wire.request.get("output_config", {})


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_interrupted_stream_without_usage_is_recorded(provider, usage_rows):
    client = client_for(provider)
    serve(client, Reply(usage=None, error=TimeoutError("private upstream detail")))
    with pytest.raises(ProviderStreamError) as raised:
        async for _ in client.stream_text("system", "user", operation="chat"):
            pass
    assert "private" not in str(raised.value)
    [event] = usage_rows
    assert not event.success
    assert event.prompt_tokens is None
    assert event.operation == "chat" and event.provider == provider


def test_settings_exclude_direct_credentials_and_require_one_for_routing():
    safe = Settings(_env_file=None, llm_provider="routed", anthropic_api_key="fake-credential-value",
                    openai_api_key="fake-credential-value")
    assert "fake-credential-value" not in repr(safe) and "fake-credential-value" not in safe.model_dump_json()
    assert not {"anthropic_api_key", "openai_api_key"} & safe.model_dump().keys()
    assert safe.llm_configured
    assert Settings(_env_file=None, llm_provider="routed", anthropic_api_key=None,
                    openai_api_key="fake-credential-value").llm_configured
    assert not Settings(_env_file=None, llm_provider="routed", anthropic_api_key=None,
                        openai_api_key=None).llm_configured
    assert Settings(_env_file=None, llm_provider="dummy", anthropic_api_key=None, openai_api_key=None).llm_configured


@pytest.mark.parametrize("payload", ['{"GOOGLE_BOOKS_API_KEY":"test-value"}', "{}", "invalid"])
def test_secret_store_reader_validates_payload_and_closes_client(monkeypatch, payload):
    import boto3
    from app.core.credentials import read_aws_secret

    closed = []
    monkeypatch.setattr(
        boto3,
        "client",
        lambda *args, **kwargs: NS(
            get_secret_value=lambda **kw: {"SecretString": payload},
            close=lambda: closed.append(True),
        ),
    )
    if "test-value" in payload:
        assert read_aws_secret("app/test", "us-east-1", "GOOGLE_BOOKS_API_KEY") == "test-value"
    else:
        with pytest.raises(RuntimeError, match="unavailable in AWS") as exc:
            read_aws_secret("app/test", "us-east-1", "GOOGLE_BOOKS_API_KEY")
        assert payload not in str(exc.value)
    assert closed == [True]


def test_curriculum_provenance_names_the_direct_models_with_native_grounding(routed, monkeypatch):
    from app.tasks.curriculum import _grounded_search_route, _resolved_llm_route

    route = _resolved_llm_route("balanced")
    assert route["primary"] == {"provider": "openai", "model": "gpt-6-luna"}
    assert route["fallback"] == {"provider": "anthropic", "model": "claude-haiku-5-5"}
    assert route["resolution"] == "configured_primary_with_fallback"
    assert "fake-openai-key" not in str(route) and "fake-anthropic-key" not in str(route)
    assert _grounded_search_route("fast")["primary"]["provider"] == "gemini"
    monkeypatch.setattr(settings, "openai_api_key", None)
    route = _resolved_llm_route("balanced")
    assert route["primary"] == {"provider": "anthropic", "model": "claude-haiku-5-5"}
    assert route["resolution"] == "configured_primary_unavailable_using_fallback"


@pytest.mark.asyncio
@pytest.mark.parametrize("provider_error", [False, True])
async def test_daily_feed_uses_cached_evidence_without_search(monkeypatch, provider_error):
    from unittest.mock import AsyncMock
    from fastapi import HTTPException
    from app.api.v1 import sessions
    from app.schemas.session import DailyFeedResponse, DailyInsightResponse
    from app.services.llm.client import LLMResponse
    from app.services.llm import telemetry

    session = NS(
        daily_feed_json=None,
        idol=None,
        user_age=25,
        user_financial_status="not_specified",
        user_interests=["geometry"],
    )
    monkeypatch.setattr(sessions, "_get_session", AsyncMock(return_value=session))
    monkeypatch.setattr(
        sessions,
        "generate_with_grounding",
        AsyncMock(side_effect=AssertionError("Unexpected paid search")),
    )
    monkeypatch.setattr(telemetry, "record_usage_records", AsyncMock())
    feed = DailyFeedResponse(
        insights=[
            DailyInsightResponse(
                title="Example",
                content="Reason through the example.",
                category="Learning",
            )
        ]
    )
    response = LLMResponse(
        data={} if provider_error else feed.model_dump(),
        provider="openai",
        model="gpt-6-luna",
        error="openai request failed (InternalServerError; 503)" if provider_error else None,
    )
    generate = AsyncMock(return_value=(None if provider_error else feed, response))

    def factory(**kwargs):
        assert kwargs["operation"] == "daily_feed_generation"
        return NS(generate_and_validate=generate)

    monkeypatch.setattr(sessions, "get_llm_client", factory)
    db = NS(commit=AsyncMock())
    if provider_error:
        with pytest.raises(HTTPException) as exc:
            await sessions.get_daily_feed("s1", db, NS(id="u1"))
        assert exc.value.status_code == 502
        assert session.daily_feed_json is None
    else:
        result = await sessions.get_daily_feed("s1", db, NS(id="u1"))
        assert result == feed
        assert await sessions.get_daily_feed("s1", db, NS(id="u1")) == feed
        generate.assert_awaited_once()
        assert (
            "Use only the supplied documented evidence"
            in generate.call_args.kwargs["user_prompt"]
        )
