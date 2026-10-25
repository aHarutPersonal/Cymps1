import asyncio
from types import SimpleNamespace as NS

import pytest
from pydantic import BaseModel

from app.core.config import Settings, settings
from app.services.llm.client import get_llm_client
from app.services.llm.openlux import OpenLuxLLMClient, OpenLuxStreamError


@pytest.fixture(autouse=True)
def configure(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "openlux")
    monkeypatch.setattr(settings, "openlux_api_key", "fake-openlux-secret")
    monkeypatch.setattr(settings, "openlux_base_url", "https://api.openlux.ai/v1")
    monkeypatch.setattr(settings, "openlux_fast_model", "gpt-5.6-terra")
    monkeypatch.setattr(settings, "openlux_model", "gpt-5.6-terra")
    monkeypatch.setattr(settings, "openlux_quality_model", "gpt-5.6-sol")
    monkeypatch.setattr(settings, "openlux_reasoning_token_reserve", 2048)


def chunk(text="", finish=None):
    return NS(
        choices=[NS(index=0, delta=NS(content=text), finish_reason=finish)], usage=None
    )


class Stream:
    def __init__(self, chunks):
        self.chunks = chunks
        self.closed = False

    async def __aiter__(self):
        for item in self.chunks:
            if isinstance(item, Exception):
                raise item
            yield item

    async def close(self):
        self.closed = True


def transport(monkeypatch, client, chunks):
    stream = Stream(chunks)
    kwargs = {}

    async def create(**kw):
        kwargs.update(kw)
        return stream

    monkeypatch.setattr(
        client, "_get_client", lambda key: NS(chat=NS(completions=NS(create=create)))
    )
    return stream, kwargs


def test_factory_routes_models_and_reasoning():
    fast, balanced, quality = [
        get_llm_client(tier=t) for t in ("fast", "balanced", "quality")
    ]
    assert all(isinstance(c, OpenLuxLLMClient) for c in (fast, balanced, quality))
    assert [c.model for c in (fast, balanced, quality)] == [
        "gpt-5.6-terra",
        "gpt-5.6-terra",
        "gpt-5.6-sol",
    ]
    assert [c.thinking_level for c in (fast, balanced, quality)] == [
        "low",
        "low",
        "high",
    ]
    assert balanced.provider_name == "openlux"
    assert balanced.base_url == "https://api.openlux.ai/v1"
    assert get_llm_client(thinking_level="minimal").thinking_level == "low"


@pytest.mark.asyncio
async def test_native_pool_disables_hidden_retries():
    client = get_llm_client()
    sdk = client._get_client("fake-openlux-secret")
    assert sdk.max_retries == 0
    await sdk.close()


@pytest.mark.asyncio
async def test_json_usage_only_final_chunk_and_schema(monkeypatch):
    class Answer(BaseModel):
        ok: bool

    client = get_llm_client(max_tokens=300)
    usage = NS(prompt_tokens=40, completion_tokens=90, total_tokens=130)
    stream, kwargs = transport(
        monkeypatch,
        client,
        [
            chunk('{"ok":'),
            chunk("true}", "stop"),
            NS(choices=[], usage=usage),
        ],
    )
    response = await client.generate_json("System", "User", output_model=Answer)
    assert response.data == {"ok": True}
    assert response.error is None
    assert (
        response.prompt_tokens,
        response.completion_tokens,
        response.total_tokens,
    ) == (40, 90, 130)
    assert response.provider == "openlux"
    assert stream.closed
    assert kwargs["max_completion_tokens"] == 2348
    assert kwargs["stream_options"] == {"include_usage": True}
    assert kwargs["reasoning_effort"] == "low"
    assert "temperature" not in kwargs and "max_tokens" not in kwargs
    assert '"ok"' in kwargs["messages"][0]["content"]


@pytest.mark.asyncio
@pytest.mark.parametrize("finish", [None, "length", "content_filter", "tool_calls"])
async def test_incomplete_json_is_not_accepted_even_when_parseable(monkeypatch, finish):
    client = get_llm_client()
    stream, _ = transport(monkeypatch, client, [chunk('{"ok":true}', finish)])
    result = await client.generate_json("System", "User")
    assert result.error and result.data == {}
    assert stream.closed


@pytest.mark.asyncio
async def test_json_array_returns_an_error_instead_of_escaping_validation(monkeypatch):
    client = get_llm_client()
    transport(monkeypatch, client, [chunk("[]", "stop")])
    result = await client.generate_json("System", "User")
    assert result.error and result.data == {}


@pytest.mark.asyncio
async def test_error_is_redacted_and_partial_usage_preserved(monkeypatch):
    client = get_llm_client()
    usage = NS(prompt_tokens=3, completion_tokens=4, total_tokens=7)
    stream, _ = transport(
        monkeypatch,
        client,
        [
            NS(choices=[], usage=usage),
            RuntimeError("fake-openlux-secret PRIVATE PROMPT"),
        ],
    )
    result = await client.generate_json("System", "User")
    assert "PRIVATE" not in result.error and "secret" not in result.error
    assert result.total_tokens == 7 and stream.closed


@pytest.mark.asyncio
async def test_total_timeout_is_enforced(monkeypatch):
    client = get_llm_client(timeout=0.01)

    async def create(**kwargs):
        await asyncio.sleep(1)

    monkeypatch.setattr(
        client, "_get_client", lambda key: NS(chat=NS(completions=NS(create=create)))
    )
    result = await client.generate_json("System", "User")
    assert "TimeoutError" in result.error


@pytest.mark.asyncio
async def test_missing_key_fails_without_dummy_or_other_provider(monkeypatch):
    monkeypatch.setattr(settings, "openlux_api_key", None)
    result = await get_llm_client().generate_json("System", "User")
    assert result.error and result.provider == "openlux"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "method, operation",
    [
        ("interview_stream", "interview_stream"),
        ("comparison_stream", "comparison_stream"),
    ],
)
async def test_plain_text_stream_routes_through_openlux(monkeypatch, method, operation):
    from app.services import gemini

    expected_operation = operation

    async def text(self, system, user, *, operation):
        assert self.provider_name == "openlux"
        assert operation == expected_operation
        yield "One question?"

    monkeypatch.setattr(OpenLuxLLMClient, "stream_text", text)
    monkeypatch.setattr(
        gemini, "_gemini_client", lambda: pytest.fail("Unexpected direct Gemini call")
    )
    assert [c async for c in getattr(gemini, method)("System", "User")] == [
        "One question?"
    ]


@pytest.mark.asyncio
async def test_grounded_stream_keeps_native_google_dependency(monkeypatch):
    from app.services import gemini

    async def generate(**kwargs):
        assert kwargs["config"].tools
        yield NS(text="Verified", candidates=[], usage_metadata=None)

    monkeypatch.setattr(
        gemini,
        "_gemini_client",
        lambda: NS(aio=NS(models=NS(generate_content_stream=generate))),
    )
    result = [
        c
        async for c in gemini._stream_generate(
            "System", "User", "Search", grounded=True
        )
    ]
    assert result == ["Verified"]


@pytest.mark.asyncio
async def test_interview_recovers_once_from_temporary_pre_text_failure(monkeypatch):
    from app.services import gemini

    monkeypatch.setattr(settings, "gemini_api_key", "fake-google")

    async def unavailable(self, system, user, *, operation):
        assert self.timeout == 20
        raise OpenLuxStreamError(TimeoutError("private provider details"))
        yield  # pragma: no cover

    calls = []

    async def generate(**kwargs):
        calls.append(kwargs)
        assert kwargs["config"].http_options.timeout == 35_000
        assert not kwargs["config"].tools
        assert kwargs["contents"] == "User"
        assert kwargs["config"].system_instruction == "System"
        yield NS(text="What have you already built?", candidates=[], usage_metadata=None)

    monkeypatch.setattr(OpenLuxLLMClient, "stream_text", unavailable)
    monkeypatch.setattr(gemini, "_gemini_client", lambda: NS(aio=NS(models=NS(generate_content_stream=generate))))
    assert [c async for c in gemini.interview_stream("System", "User")] == ["What have you already built?"]
    assert len(calls) == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("partial,temporary,google_key,method", [
    (True, True, "fake-google", "interview_stream"),
    (False, False, "fake-google", "interview_stream"),
    (False, True, None, "interview_stream"),
    (False, True, "fake-google", "comparison_stream"),
])
async def test_interview_recovery_never_splices_or_hides_other_failures(monkeypatch, partial, temporary, google_key, method):
    from app.services import gemini

    monkeypatch.setattr(settings, "gemini_api_key", google_key)

    async def unavailable(self, system, user, *, operation):
        if partial:
            yield "Partial reply"
        error = TimeoutError("private") if temporary else ValueError("private")
        raise OpenLuxStreamError(error)

    monkeypatch.setattr(OpenLuxLLMClient, "stream_text", unavailable)
    monkeypatch.setattr(gemini, "_gemini_client", lambda: pytest.fail("Unexpected fallback"))
    with pytest.raises(OpenLuxStreamError, match="OpenLux stream failed") as error:
        _ = [c async for c in getattr(gemini, method)("System", "User")]
    assert "private" not in str(error.value)


@pytest.mark.asyncio
async def test_stopping_text_consumer_closes_upstream_stream(monkeypatch):
    client = get_llm_client()
    stream, _ = transport(
        monkeypatch, client, [chunk("First"), chunk("Second", "stop")]
    )
    output = client.stream_text("System", "User", operation="test")
    assert await anext(output) == "First"
    await output.aclose()
    assert stream.closed


@pytest.mark.asyncio
async def test_text_stream_records_actual_provider_and_usage(monkeypatch):
    from app.services.llm import telemetry

    records = []

    async def record(items):
        records.extend(items)

    monkeypatch.setattr(telemetry, "record_usage_records", record)
    client = get_llm_client()
    usage = NS(prompt_tokens=10, completion_tokens=20, total_tokens=30)
    stream, kwargs = transport(
        monkeypatch, client, [chunk("Hello", "stop"), NS(choices=[], usage=usage)]
    )
    assert [
        t async for t in client.stream_text("System", "User", operation="test")
    ] == ["Hello"]
    assert records[0].provider == "openlux" and records[0].success
    assert records[0].total_tokens == 30 and stream.closed
    assert "response_format" not in kwargs


def test_settings_keychain_load_is_explicit_and_secret_is_excluded(monkeypatch):
    from app.core import credentials

    monkeypatch.setattr(
        credentials, "read_keychain_secret", lambda service: "fake-secret"
    )
    config = Settings(
        _env_file=None,
        llm_provider="openlux",
        openlux_keychain_service="test",
        gemini_api_key="test",
    )
    assert config.openlux_api_key == "fake-secret"
    assert config.llm_configured
    assert (
        "fake-secret" not in repr(config)
        and "fake-secret" not in config.model_dump_json()
    )
    config.gemini_api_key = None
    assert config.llm_configured


def test_provider_price_uses_account_estimate_not_yunwu_multiplier(monkeypatch):
    from app.services.llm.pricing import price_card_for_model

    monkeypatch.setattr(settings, "openlux_input_usd_per_million", 3)
    monkeypatch.setattr(settings, "openlux_output_usd_per_million", 14)
    card = price_card_for_model("gpt-5.6-terra", "openlux")
    assert card.token_rates(100) == (3, 14)


def test_settings_reads_production_secret_without_keychain(monkeypatch):
    from app.core import credentials

    calls = []
    monkeypatch.setattr(
        credentials,
        "read_aws_secret",
        lambda secret, region: calls.append((secret, region)) or "fake-aws-secret",
    )
    monkeypatch.setattr(
        credentials,
        "read_keychain_secret",
        lambda service: pytest.fail("Unexpected local Keychain read"),
    )
    config = Settings(
        _env_file=None,
        llm_provider="openlux",
        openlux_api_key=None,
        openlux_secret_id="app/test",
        openlux_secret_region="us-east-1",
        openlux_keychain_service=None,
    )
    assert calls == [("app/test", "us-east-1")]
    assert config.openlux_api_key == "fake-aws-secret" and config.llm_configured
    assert "fake-aws-secret" not in config.model_dump_json()


@pytest.mark.parametrize(
    "payload", ['{"OPENLUX_API_KEY":"test-value"}', "{}", "invalid"]
)
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
        assert read_aws_secret("app/test", "us-east-1") == "test-value"
    else:
        with pytest.raises(RuntimeError, match="unavailable in AWS") as exc:
            read_aws_secret("app/test", "us-east-1")
        assert payload not in str(exc.value)
    assert closed == [True]


def test_curriculum_provenance_is_openlux_with_native_grounding():
    from app.tasks.curriculum import _resolved_llm_route, _grounded_search_route

    route = _resolved_llm_route("balanced")
    assert route["primary"]["provider"] == "openlux"
    assert route["primary"]["model"] == "gpt-5.6-terra"
    assert route["fallback"] is None
    assert "fake-openlux-secret" not in str(route)
    assert _grounded_search_route("fast")["primary"]["provider"] == "gemini"


@pytest.mark.asyncio
async def test_debug_reports_openlux(monkeypatch):
    from app.api.v1.debug import get_llm_status

    monkeypatch.setattr(settings, "gemini_api_key", "test")
    status = await get_llm_status()
    assert status.provider == "openlux" and status.model == "gpt-5.6-terra"
    assert status.configured
    assert "secret" not in status.model_dump_json()


@pytest.mark.asyncio
@pytest.mark.parametrize("provider_error", [False, True])
async def test_daily_feed_uses_cached_evidence_without_search_or_fallback(
    monkeypatch, provider_error
):
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
        provider="openlux",
        model="gpt-5.6-terra",
        error="Unavailable" if provider_error else None,
    )
    generate = AsyncMock(return_value=(None if provider_error else feed, response))

    def factory(**kwargs):
        assert kwargs["allow_fallback"] is False
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

@pytest.mark.asyncio
async def test_interrupted_stream_without_usage_is_recorded(monkeypatch):
    from unittest.mock import AsyncMock
    record = AsyncMock()
    monkeypatch.setattr('app.services.llm.telemetry.record_usage_records', record)
    client = get_llm_client()
    transport(monkeypatch, client, [TimeoutError('private upstream detail')])
    with pytest.raises(OpenLuxStreamError):
        async for _ in client.stream_text('system', 'user', operation='chat'):
            pass
    event = record.call_args.args[0][0]
    assert not event.success
    assert event.prompt_tokens is None
    assert event.operation == 'chat'
