from unittest.mock import AsyncMock

import pytest

from app.core.config import settings
from app.services.llm import recovery
from app.services.llm.anthropic_direct import AnthropicDirectLLMClient
from app.services.llm.client import LLMResponse
from app.services.llm.openai_direct import OpenAIDirectLLMClient

OTHER = {"anthropic": ("openai", OpenAIDirectLLMClient, "gpt-6-luna"),
         "openai": ("anthropic", AnthropicDirectLLMClient, "claude-haiku-5-5")}


@pytest.fixture
def both_models(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "routed")
    monkeypatch.setattr(settings, "anthropic_api_key", "fake-anthropic-key")
    monkeypatch.setattr(settings, "openai_api_key", "fake-openai-key")
    monkeypatch.setattr(settings, "anthropic_model", "claude-haiku-5-5")
    monkeypatch.setattr(settings, "openai_model", "gpt-6-luna")


@pytest.mark.parametrize('provider', ['anthropic', 'openai'])
@pytest.mark.parametrize('error,code,finish,allowed', [
    # The provider could not serve the call: the other model may recover it.
    ('{p} request failed (APITimeoutError; connection)', 'generation_failed', None, True),
    ('{p} request failed (IncompleteStreamError; finish=missing)', 'generation_failed', None, True),
    ('{p} request failed (RemoteProtocolError; stream)', 'generation_failed', None, True),
    ('{p} request failed (RateLimitError; 429)', 'generation_rate_limited', None, True),
    ('{p} request failed (MissingCredential; client)', 'generation_unavailable', None, True),
    # The model answered: content and schema failures never switch models.
    ('{p} request failed (JSONDecodeError; Expecting value)', None, 'stop', False),
    ('{p} request failed (JSONProtocolError; Duplicate JSON property)', None, 'stop', False),
    ('{p} request failed (ValueError; finish=length)', None, 'length', False),
    ('Schema validation failed', None, 'stop', False),
    (None, None, 'stop', False),
])
def test_recovery_requires_gateway_operational_failure(both_models, provider, error, code, finish, allowed):
    response = LLMResponse(data={}, provider=provider, error=error and error.format(p=provider),
                           error_code=code, finish_reason=finish)
    client = recovery.operational_recovery_client(response, timeout=25, max_tokens=2000)
    assert (client is not None) == allowed
    if client:
        other, client_class, model = OTHER[provider]
        assert isinstance(client, recovery.CompleteRecoveryClient)
        assert isinstance(client._client, client_class)
        assert client.provider_name == other  # the other direct model, never Gemini
        assert client.model == model
        assert client.timeout == 25
        assert client.max_tokens == 2000


def test_no_cross_provider_chain_or_missing_key(both_models, monkeypatch):
    outage = 'request failed (APITimeoutError; connection)'
    # Only a direct model's own outage is recoverable: no Gemini, dummy or gateway chain.
    for provider in ('openlux', 'zai', 'gemini', 'dummy', None):
        assert recovery.operational_recovery_client(
            LLMResponse(data={}, provider=provider, error=f'{provider} {outage}',
                        error_code='generation_failed'),
            timeout=25, max_tokens=2000) is None

    # No recovery when the other model has no key.
    monkeypatch.setattr(settings, "openai_api_key", None)
    assert recovery.operational_recovery_client(
        LLMResponse(data={}, provider='anthropic', error=f'anthropic {outage}', error_code='generation_failed'),
        timeout=25, max_tokens=2000) is None

    # Dummy mode never builds a provider client.
    monkeypatch.setattr(settings, "openai_api_key", "fake-openai-key")
    monkeypatch.setattr(settings, "llm_provider", "dummy")
    assert recovery.operational_recovery_client(
        LLMResponse(data={}, provider='anthropic', error=f'anthropic {outage}', error_code='generation_failed'),
        timeout=25, max_tokens=2000) is None


@pytest.mark.asyncio
@pytest.mark.parametrize('finish', ['length', 'MAX_TOKENS', None])
async def test_complete_json_still_requires_terminal_stop(finish):
    backup = AsyncMock()
    backup.generate_json = AsyncMock(return_value=LLMResponse(data={'looks': 'valid'}, finish_reason=finish))
    client = recovery.CompleteRecoveryClient(backup)
    response = await client.generate_json('system', 'user')
    assert response.error
    assert response.data == {}


@pytest.mark.asyncio
async def test_complete_json_with_terminal_stop_passes_through():
    backup = AsyncMock()
    backup.generate_json = AsyncMock(return_value=LLMResponse(data={'looks': 'valid'}, finish_reason='stop'))
    response = await recovery.CompleteRecoveryClient(backup).generate_json('system', 'user')
    assert response.error is None
    assert response.data == {'looks': 'valid'}
