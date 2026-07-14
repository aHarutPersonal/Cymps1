import asyncio

import pytest

from app.core.config import settings
from app.services.llm.client import (
    BaseLLMClient,
    FallbackLLMClient,
    GeminiLLMClient,
    LLMResponse,
    OpenAILLMClient,
    get_llm_client,
)


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


class _ResponseClient(BaseLLMClient):
    def __init__(self, response: LLMResponse, model: str):
        self.response = response
        self.model = model
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

    response = await FallbackLLMClient(primary, fallback).generate_json("system", "user")

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
