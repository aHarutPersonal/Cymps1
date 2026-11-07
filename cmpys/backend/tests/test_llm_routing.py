"""The backup provider serves a call only when the primary is unavailable."""
import pytest

from app.services.llm.client import BaseLLMClient, FallbackLLMClient, LLMResponse
from app.services.llm.gemini_compat import generation_config_kwargs

OUTAGE = "anthropic request failed (InternalServerError; 529)"
TIMEOUT = "anthropic request failed (APITimeoutError; connection)"
NO_CREDIT = "anthropic request failed (GenerationUnavailable; 400)"


@pytest.fixture(autouse=True)
def _reset_provider_circuits():
    FallbackLLMClient.reset_circuits_for_tests()
    yield
    FallbackLLMClient.reset_circuits_for_tests()


def test_current_gemini_config_omits_deprecated_sampling_parameters():
    # Gemini still serves grounded search and narration through this config.
    kwargs = generation_config_kwargs(
        model="gemini-3.6-flash",
        temperature=0.8,
        thinking_level="low",
    )

    assert "temperature" not in kwargs
    assert str(kwargs["thinking_config"].thinking_level).casefold().endswith("low")


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
    model = "claude-haiku-5-5"
    provider_name = "anthropic"

    async def generate_json(self, *args, **kwargs) -> LLMResponse:
        raise RuntimeError("transport setup failed")


@pytest.mark.asyncio
async def test_provider_failure_uses_fallback_and_records_provenance():
    primary = _ResponseClient(
        LLMResponse(
            data={},
            model="claude-haiku-5-5",
            provider="anthropic",
            error=OUTAGE,
            error_code="generation_failed",
            duration_ms=25,
        ),
        "claude-haiku-5-5",
    )
    fallback = _ResponseClient(
        LLMResponse(
            data={"ok": True},
            model="gpt-6-luna",
            provider="openai",
            duration_ms=10,
        ),
        "gpt-6-luna",
    )

    response = await FallbackLLMClient(primary, fallback).generate_json(
        "system", "user"
    )

    assert response.data == {"ok": True}
    assert response.provider == "openai"
    assert response.retried is True
    assert response.fallback_from_model == "claude-haiku-5-5"
    assert response.fallback_from_provider == "anthropic"
    assert response.fallback_error == OUTAGE
    assert response.duration_ms == 35
    assert primary.calls == fallback.calls == 1


@pytest.mark.asyncio
async def test_unexpected_primary_exception_still_uses_fallback():
    fallback = _ResponseClient(
        LLMResponse(
            data={"ok": True},
            model="gpt-6-luna",
            provider="openai",
        ),
        "gpt-6-luna",
    )

    response = await FallbackLLMClient(_RaisingClient(), fallback).generate_json(
        "system", "user"
    )

    assert response.data == {"ok": True}
    assert response.provider == "openai"
    assert response.fallback_from_model == "claude-haiku-5-5"
    assert response.fallback_from_provider == "anthropic"
    # Only the exception type survives: its message can echo private content.
    assert response.fallback_error == "Primary provider error: RuntimeError"
    assert fallback.calls == 1


@pytest.mark.asyncio
async def test_operational_failure_opens_provider_circuit_for_next_call():
    failed_primary = _ResponseClient(
        LLMResponse(data={}, provider="anthropic", error=TIMEOUT, error_code="generation_failed"),
        "claude-haiku-5-5",
    )
    first_fallback = _ResponseClient(
        LLMResponse(data={"attempt": 1}, provider="openai"),
        "gpt-6-luna",
    )
    first = await FallbackLLMClient(failed_primary, first_fallback).generate_json(
        "system", "user"
    )

    healthy_but_skipped_primary = _ResponseClient(
        LLMResponse(data={"wrong": True}, provider="anthropic"),
        "claude-haiku-5-5",
    )
    second_fallback = _ResponseClient(
        LLMResponse(data={"attempt": 2}, provider="openai"),
        "gpt-6-luna",
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
        LLMResponse(data={}, provider="anthropic", retryable=True,
                    error="anthropic request failed (JSONDecodeError; Expecting value: line 1 column 1 (char 0))"),
        "claude-haiku-5-5",
    )
    fallback = _ResponseClient(
        LLMResponse(data={"fallback": True}, provider="openai"),
        "gpt-6-luna",
    )
    first = await FallbackLLMClient(invalid_primary, fallback).generate_json("system", "user")
    assert first.error.startswith("anthropic request failed (JSONDecodeError;") and fallback.calls == 0

    next_primary = _ResponseClient(
        LLMResponse(data={"primary": True}, provider="anthropic"),
        "claude-haiku-5-5",
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
            provider="anthropic",
            error=NO_CREDIT,
            error_code="generation_unavailable",
            retryable=False,
        ),
        "claude-haiku-5-5",
    )
    first_fallback = _ResponseClient(
        LLMResponse(data={"attempt": 1}, provider="openai"),
        "gpt-6-luna",
    )
    first = await FallbackLLMClient(failed_primary, first_fallback).generate_json(
        "system", "user"
    )

    healthy_but_skipped_primary = _ResponseClient(
        LLMResponse(data={"wrong": True}, provider="anthropic"),
        "claude-haiku-5-5",
    )
    second_fallback = _ResponseClient(
        LLMResponse(data={"attempt": 2}, provider="openai"),
        "gpt-6-luna",
    )
    second = await FallbackLLMClient(
        healthy_but_skipped_primary, second_fallback
    ).generate_json("system", "user")

    assert first.data == {"attempt": 1}
    assert second.data == {"attempt": 2}
    assert failed_primary.calls == 1
    assert healthy_but_skipped_primary.calls == 0
    assert "circuit open" in str(second.fallback_error).casefold()
