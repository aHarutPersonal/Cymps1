import asyncio
from types import SimpleNamespace

import pytest
from pydantic import BaseModel, ConfigDict

from app.core.config import settings
from app.services.llm.client import (
    BaseLLMClient,
    FallbackLLMClient,
    GeminiLLMClient,
    LLMResponse,
    OpenAILLMClient,
    _gemini_compatibility_schema,
    get_llm_client,
)
from app.services.llm.gemini_compat import generation_config_kwargs


@pytest.fixture(autouse=True)
def _reset_provider_circuits():
    FallbackLLMClient.reset_circuits_for_tests()
    yield
    FallbackLLMClient.reset_circuits_for_tests()


def test_gemini_tiers_route_to_cost_quality_models(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(settings, "gemini_fast_model", "flash-lite-test")
    monkeypatch.setattr(settings, "gemini_model", "flash-test")
    monkeypatch.setattr(settings, "gemini_quality_model", "pro-test")

    fast = get_llm_client(tier="fast")
    balanced = get_llm_client(tier="balanced", thinking_budget=0)
    quality = get_llm_client(tier="quality", thinking_budget=2048)

    assert isinstance(fast, GeminiLLMClient)
    assert fast.model == "flash-lite-test"
    assert fast.thinking_budget == 0
    assert balanced.model == "flash-test"
    assert balanced.thinking_budget == 0
    assert quality.model == "pro-test"
    assert quality.thinking_budget == 2048


def test_fast_flag_remains_backward_compatible(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(settings, "gemini_fast_model", "flash-lite-test")

    client = get_llm_client(fast=True)

    assert isinstance(client, GeminiLLMClient)
    assert client.model == "flash-lite-test"


def test_current_gemini_models_use_levels_instead_of_legacy_budgets(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(settings, "gemini_fast_model", "gemini-3.5-flash-lite")
    monkeypatch.setattr(settings, "gemini_model", "gemini-3.6-flash")
    monkeypatch.setattr(settings, "gemini_quality_model", "gemini-3.1-pro-preview")

    fast = get_llm_client(tier="fast")
    balanced = get_llm_client(tier="balanced", thinking_level="medium")
    quality = get_llm_client(tier="quality")

    assert (fast.thinking_level, fast.thinking_budget) == ("minimal", None)
    assert (balanced.thinking_level, balanced.thinking_budget) == ("medium", None)
    assert (quality.thinking_level, quality.thinking_budget) == ("high", None)


def test_current_gemini_config_omits_deprecated_sampling_parameters():
    kwargs = generation_config_kwargs(
        model="gemini-3.6-flash",
        temperature=0.8,
        thinking_level="low",
    )

    assert "temperature" not in kwargs
    assert str(kwargs["thinking_config"].thinking_level).casefold().endswith("low")


def test_yunwu_tiers_route_to_quality_first_models(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "test-key")
    monkeypatch.setattr(settings, "yunwu_base_url", "https://gateway.test/v1/")
    monkeypatch.setattr(settings, "yunwu_fast_model", "fast-test")
    monkeypatch.setattr(settings, "yunwu_model", "balanced-test")
    monkeypatch.setattr(settings, "yunwu_quality_model", "quality-test")
    monkeypatch.setattr(settings, "yunwu_fallback_enabled", False)

    fast = get_llm_client(tier="fast")
    balanced = get_llm_client(tier="balanced", temperature=0.35)
    quality = get_llm_client(tier="quality")

    assert isinstance(fast, OpenAILLMClient)
    assert fast.model == "fast-test"
    assert balanced.model == "balanced-test"
    assert balanced.base_url == "https://gateway.test/v1"
    assert balanced.provider_name == "yunwu"
    assert balanced.temperature == 0.35
    assert quality.model == "quality-test"


def test_yunwu_routes_current_gemini_tiers_through_gateway(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "test-key")
    monkeypatch.setattr(settings, "yunwu_fallback_enabled", False)
    monkeypatch.setattr(settings, "yunwu_fast_model", "gemini-3.5-flash-lite")
    monkeypatch.setattr(settings, "yunwu_model", "gemini-3.6-flash")
    monkeypatch.setattr(
        settings,
        "yunwu_quality_model",
        "gemini-3.1-pro-preview",
    )

    clients = [
        get_llm_client(tier="fast"),
        get_llm_client(tier="balanced"),
        get_llm_client(tier="quality"),
    ]

    assert all(isinstance(client, OpenAILLMClient) for client in clients)
    assert [client.model for client in clients] == [
        "gemini-3.5-flash-lite",
        "gemini-3.6-flash",
        "gemini-3.1-pro-preview",
    ]
    assert all(client.provider_name == "yunwu" for client in clients)


def test_yunwu_without_key_falls_back_to_dummy(monkeypatch):
    from app.services.llm.client import DummyLLMClient

    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", None)
    monkeypatch.setattr(settings, "gemini_api_key", None)
    monkeypatch.setattr(settings, "yunwu_fallback_enabled", True)

    assert isinstance(get_llm_client(), DummyLLMClient)


def test_openai_compatible_pool_is_scoped_to_event_loop():
    wrapper = OpenAILLMClient(
        model="test",
        api_key="loop-test-key",
        base_url="https://loop-isolation.test/v1",
        provider_name="yunwu",
    )

    async def get_client():
        return wrapper._get_client("loop-test-key")

    first = asyncio.run(get_client())
    second = asyncio.run(get_client())

    assert first is not second
    assert first.max_retries == 0


def test_direct_openai_client_retains_transport_retries():
    wrapper = OpenAILLMClient(
        model="test",
        api_key="openai-test-key",
        provider_name="openai",
    )

    async def get_client():
        return wrapper._get_client("openai-test-key")

    client = asyncio.run(get_client())

    assert client.max_retries == 2


def test_yunwu_factory_builds_independent_gemini_fallback(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "yunwu-test")
    monkeypatch.setattr(settings, "gemini_api_key", "gemini-test")
    monkeypatch.setattr(settings, "yunwu_fallback_enabled", True)
    monkeypatch.setattr(settings, "yunwu_model", "grok-test")
    monkeypatch.setattr(settings, "gemini_model", "gemini-test-model")

    client = get_llm_client(tier="balanced")

    assert isinstance(client, FallbackLLMClient)
    assert isinstance(client.primary, OpenAILLMClient)
    assert isinstance(client.fallback, GeminiLLMClient)
    assert client.primary.model == "grok-test"
    assert client.fallback.model == "gemini-test-model"


def test_yunwu_factory_can_disable_fallback_for_latency_sensitive_calls(
    monkeypatch,
):
    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "yunwu-test")
    monkeypatch.setattr(settings, "gemini_api_key", "gemini-test")
    monkeypatch.setattr(settings, "yunwu_fallback_enabled", True)
    monkeypatch.setattr(settings, "yunwu_quality_model", "quality-test")

    client = get_llm_client(tier="quality", allow_fallback=False)

    assert isinstance(client, OpenAILLMClient)
    assert client.model == "quality-test"


class _ResponseClient(BaseLLMClient):
    def __init__(self, response: LLMResponse, model: str):
        self.response = response
        self.model = model
        self.provider_name = response.provider
        self.calls = 0

    async def generate_json(self, *args, **kwargs) -> LLMResponse:
        self.calls += 1
        return self.response.model_copy(deep=True)


class _RaisingClient(BaseLLMClient):
    model = "grok-test"
    provider_name = "yunwu"

    async def generate_json(self, *args, **kwargs) -> LLMResponse:
        raise RuntimeError("transport setup failed")


@pytest.mark.asyncio
async def test_provider_failure_uses_fallback_and_records_provenance():
    primary = _ResponseClient(
        LLMResponse(
            data={},
            model="grok-test",
            provider="yunwu",
            error="gateway unavailable",
            duration_ms=25,
        ),
        "grok-test",
    )
    fallback = _ResponseClient(
        LLMResponse(
            data={"ok": True},
            model="gemini-test",
            provider="gemini",
            duration_ms=10,
        ),
        "gemini-test",
    )

    response = await FallbackLLMClient(primary, fallback).generate_json(
        "system", "user"
    )

    assert response.data == {"ok": True}
    assert response.provider == "gemini"
    assert response.retried is True
    assert response.fallback_from_model == "grok-test"
    assert response.fallback_from_provider == "yunwu"
    assert response.fallback_error == "gateway unavailable"
    assert response.duration_ms == 35
    assert primary.calls == fallback.calls == 1


@pytest.mark.asyncio
async def test_unexpected_primary_exception_still_uses_fallback():
    fallback = _ResponseClient(
        LLMResponse(
            data={"ok": True},
            model="gemini-test",
            provider="gemini",
        ),
        "gemini-test",
    )

    response = await FallbackLLMClient(_RaisingClient(), fallback).generate_json(
        "system", "user"
    )

    assert response.data == {"ok": True}
    assert response.provider == "gemini"
    assert response.fallback_from_model == "grok-test"
    assert response.fallback_from_provider == "yunwu"
    assert response.fallback_error == "Primary provider error: transport setup failed"
    assert fallback.calls == 1


@pytest.mark.asyncio
async def test_operational_failure_opens_provider_circuit_for_next_call():
    failed_primary = _ResponseClient(
        LLMResponse(data={}, provider="yunwu", error="gateway timed out"),
        "balanced-test",
    )
    first_fallback = _ResponseClient(
        LLMResponse(data={"attempt": 1}, provider="gemini"),
        "gemini-test",
    )
    first = await FallbackLLMClient(failed_primary, first_fallback).generate_json(
        "system", "user"
    )

    healthy_but_skipped_primary = _ResponseClient(
        LLMResponse(data={"wrong": True}, provider="yunwu"),
        "quality-test",
    )
    second_fallback = _ResponseClient(
        LLMResponse(data={"attempt": 2}, provider="gemini"),
        "gemini-test",
    )
    second = await FallbackLLMClient(
        healthy_but_skipped_primary, second_fallback
    ).generate_json("system", "user")

    assert first.data == {"attempt": 1}
    assert second.data == {"attempt": 2}
    assert failed_primary.calls == 1
    assert healthy_but_skipped_primary.calls == 0
    assert "circuit open" in str(second.fallback_error).casefold()


@pytest.mark.asyncio
async def test_content_error_does_not_open_provider_circuit():
    invalid_primary = _ResponseClient(
        LLMResponse(data={}, provider="yunwu", error="Invalid JSON in response"),
        "balanced-test",
    )
    fallback = _ResponseClient(
        LLMResponse(data={"fallback": True}, provider="gemini"),
        "gemini-test",
    )
    await FallbackLLMClient(invalid_primary, fallback).generate_json("system", "user")

    next_primary = _ResponseClient(
        LLMResponse(data={"primary": True}, provider="yunwu"),
        "quality-test",
    )
    response = await FallbackLLMClient(next_primary, fallback).generate_json(
        "system", "user"
    )

    assert response.data == {"primary": True}
    assert next_primary.calls == 1


@pytest.mark.asyncio
async def test_exhausted_quota_opens_provider_circuit_for_next_call():
    failed_primary = _ResponseClient(
        LLMResponse(
            data={},
            provider="yunwu",
            error="local:insufficient_quota: user quota is not enough",
        ),
        "balanced-test",
    )
    first_fallback = _ResponseClient(
        LLMResponse(data={"attempt": 1}, provider="gemini"),
        "gemini-test",
    )
    first = await FallbackLLMClient(failed_primary, first_fallback).generate_json(
        "system", "user"
    )

    healthy_but_skipped_primary = _ResponseClient(
        LLMResponse(data={"wrong": True}, provider="yunwu"),
        "quality-test",
    )
    second_fallback = _ResponseClient(
        LLMResponse(data={"attempt": 2}, provider="gemini"),
        "gemini-test",
    )
    second = await FallbackLLMClient(
        healthy_but_skipped_primary, second_fallback
    ).generate_json("system", "user")

    assert first.data == {"attempt": 1}
    assert second.data == {"attempt": 2}
    assert failed_primary.calls == 1
    assert healthy_but_skipped_primary.calls == 0
    assert "circuit open" in str(second.fallback_error).casefold()


class _CompatibilityOutput(BaseModel):
    ok: bool


class _NativeJsonSchemaOutput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    values: dict[str, str]


class _StructuredItem(BaseModel):
    value: str


class _StructuredOutput(BaseModel):
    name: str
    items: list[_StructuredItem]
    note: str | None = None


def test_gemini_compatibility_schema_keeps_required_nested_shape():
    schema = _gemini_compatibility_schema(
        json_schema=None,
        output_model=_StructuredOutput,
    )

    assert schema == {
        "type": "object",
        "properties": {
            "name": {"type": "string"},
            "items": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {"value": {"type": "string"}},
                    "required": ["value"],
                },
            },
            "note": {"type": "string"},
        },
        "required": ["name", "items"],
    }


@pytest.mark.asyncio
async def test_gemini_uses_native_json_schema_for_pydantic_models(monkeypatch):
    from app.services import gemini as gemini_service

    calls = []

    class Models:
        async def generate_content(self, **kwargs):
            calls.append(kwargs)
            return SimpleNamespace(
                text='{"values": {"answer": "yes"}}',
                candidates=[],
                usage_metadata=None,
            )

    fake_client = SimpleNamespace(aio=SimpleNamespace(models=Models()))
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(gemini_service, "_gemini_client", lambda: fake_client)

    response = await GeminiLLMClient(
        model="gemini-3.6-flash",
        api_key="test-key",
        timeout=5,
    ).generate_json(
        system_prompt="system",
        user_prompt="return the result",
        output_model=_NativeJsonSchemaOutput,
    )

    assert response.error is None
    assert response.data == {"values": {"answer": "yes"}}
    assert len(calls) == 1
    config = calls[0]["config"].model_dump(exclude_none=True)
    assert "response_schema" not in config
    assert config["response_json_schema"] == (
        _NativeJsonSchemaOutput.model_json_schema()
    )
    assert config["response_json_schema"]["additionalProperties"] is False


@pytest.mark.asyncio
async def test_gemini_invalid_native_config_retries_without_native_schema(
    monkeypatch,
):
    from app.services import gemini as gemini_service

    calls = []

    class Models:
        async def generate_content(self, **kwargs):
            calls.append(kwargs)
            if len(calls) == 1:
                raise RuntimeError("400 INVALID_ARGUMENT: response schema unsupported")
            return SimpleNamespace(
                text='{"ok": true}',
                candidates=[],
                usage_metadata=None,
            )

    fake_client = SimpleNamespace(aio=SimpleNamespace(models=Models()))
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(gemini_service, "_gemini_client", lambda: fake_client)

    response = await GeminiLLMClient(
        model="gemini-3.6-flash",
        api_key="test-key",
        timeout=5,
    ).generate_json(
        system_prompt="system",
        user_prompt="return the result",
        output_model=_CompatibilityOutput,
    )

    assert response.error is None
    assert response.data == {"ok": True}
    assert response.retried is True
    assert len(calls) == 2
    assert "COMPATIBILITY MODE" in calls[1]["contents"]
    compatibility_config = calls[1]["config"].model_dump(exclude_none=True)
    assert "response_schema" not in compatibility_config
    assert compatibility_config["response_json_schema"] == {
        "type": "object",
        "properties": {"ok": {"type": "boolean"}},
        "required": ["ok"],
    }
    assert "thinking_config" in compatibility_config


@pytest.mark.asyncio
async def test_gemini_compatibility_can_drop_rejected_thinking_config(monkeypatch):
    from app.services import gemini as gemini_service

    calls = []

    class Models:
        async def generate_content(self, **kwargs):
            calls.append(kwargs)
            if len(calls) < 3:
                raise RuntimeError("400 INVALID_ARGUMENT: config unsupported")
            return SimpleNamespace(
                text='{"ok": true}',
                candidates=[],
                usage_metadata=None,
            )

    fake_client = SimpleNamespace(aio=SimpleNamespace(models=Models()))
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(gemini_service, "_gemini_client", lambda: fake_client)

    response = await GeminiLLMClient(
        model="gemini-3.6-flash",
        api_key="test-key",
        timeout=5,
    ).generate_json(
        system_prompt="system",
        user_prompt="return the result",
        output_model=_CompatibilityOutput,
    )

    assert response.error is None
    assert response.data == {"ok": True}
    assert len(calls) == 3
    second_config = calls[1]["config"].model_dump(exclude_none=True)
    third_config = calls[2]["config"].model_dump(exclude_none=True)
    assert second_config["response_json_schema"] == {
        "type": "object",
        "properties": {"ok": {"type": "boolean"}},
        "required": ["ok"],
    }
    assert "thinking_config" in second_config
    assert third_config["response_json_schema"] == {
        "type": "object",
        "properties": {"ok": {"type": "boolean"}},
        "required": ["ok"],
    }
    assert "thinking_config" not in third_config
