from app.core.config import settings
from app.services.llm.client import GeminiLLMClient, get_llm_client


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
