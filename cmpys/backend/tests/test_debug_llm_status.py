import pytest

from app.api.v1.debug import get_llm_status
from app.core.config import settings


@pytest.mark.asyncio
async def test_debug_status_reports_routed_models_without_exposing_keys(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "routed")
    monkeypatch.setattr(settings, "anthropic_api_key", "test-secret")
    monkeypatch.setattr(settings, "openai_api_key", "other-secret")
    monkeypatch.setattr(settings, "anthropic_model", "claude-haiku-5-5")
    monkeypatch.setattr(settings, "openai_model", "gpt-6-luna")

    status = await get_llm_status()

    assert status.provider == "routed"
    assert status.model == "claude-haiku-5-5, gpt-6-luna"
    assert status.configured is True
    assert "secret" not in status.model_dump_json()


@pytest.mark.asyncio
async def test_debug_status_requires_a_direct_provider_key(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "routed")
    monkeypatch.setattr(settings, "anthropic_api_key", None)
    monkeypatch.setattr(settings, "openai_api_key", None)
    monkeypatch.setattr(settings, "gemini_api_key", "gemini-secret")  # search alone cannot generate

    status = await get_llm_status()

    assert status.configured is False
