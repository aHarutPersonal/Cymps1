from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.services.llm import recovery
from app.services.llm.client import LLMResponse


@pytest.mark.parametrize('error,finish,allowed', [
    ('OpenLux request failed (APITimeoutError; finish=missing)', None, True),
    ('OpenLux request failed (ValueError; finish=missing)', None, True),
    ('OpenLux request failed (RemoteProtocolError; finish=missing)', None, True),
    ('OpenLux request failed (JSONDecodeError; finish=stop)', 'stop', False),
    ('OpenLux request failed (ValueError; finish=length)', 'length', False),
    ('Schema validation failed', 'stop', False),
    (None, 'stop', False),
])
def test_recovery_requires_gateway_operational_failure(monkeypatch, error, finish, allowed):
    monkeypatch.setattr(recovery, 'settings', SimpleNamespace(
        gemini_api_key='test-only', gemini_quality_model='quality-test'))
    response = LLMResponse(data={}, provider='openlux', error=error, finish_reason=finish)
    client = recovery.operational_recovery_client(response, timeout=25, max_tokens=2000)
    assert (client is not None) == allowed
    if client:
        assert client.model == 'quality-test'
        assert client.timeout == 25


def test_no_cross_provider_chain_or_missing_key(monkeypatch):
    monkeypatch.setattr(recovery, 'settings', SimpleNamespace(gemini_api_key=None))
    for provider in ('openlux', 'gemini', None):
        assert recovery.operational_recovery_client(
            LLMResponse(data={}, provider=provider, error='timeout'),
            timeout=25, max_tokens=2000) is None


@pytest.mark.asyncio
async def test_complete_json_still_requires_terminal_stop(monkeypatch):
    monkeypatch.setattr(recovery.GeminiLLMClient, 'generate_json', AsyncMock(
        return_value=LLMResponse(data={'looks': 'valid'}, finish_reason='MAX_TOKENS')))
    client = recovery.CompleteRecoveryClient()
    response = await client.generate_json('system', 'user')
    assert response.error
    assert response.data == {}
