import pytest

from app.api.v1.debug import get_llm_status
from app.core.config import settings


@pytest.mark.asyncio
async def test_debug_status_reports_yunwu_model_without_exposing_key(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "test-secret")
    monkeypatch.setattr(settings, "gemini_api_key", "gemini-secret")
    monkeypatch.setattr(settings, "yunwu_model", "grok-test")

    status = await get_llm_status()

    assert status.provider == "yunwu"
    assert status.model == "grok-test"
    assert status.configured is True
    assert "secret" not in status.model_dump_json()


@pytest.mark.asyncio
async def test_debug_status_requires_remaining_native_gemini_dependency(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "test-secret")
    monkeypatch.setattr(settings, "gemini_api_key", None)

    status = await get_llm_status()

    assert status.configured is False
