"""JSON transport must distinguish exhausted credit from temporary throttling."""
import anthropic
import httpx
import httpx2
import openai
import pytest

from app.core.config import settings
from app.services.planning.lesson_writer import _may_retry
from app.services.planning.package_review import _retryable_error
from tests.direct_wire import PROVIDERS, Reply, client_for, serve

__all__ = ["api_error", "client_for", "credit_error"]

_CLASSES = {400: "BadRequestError", 401: "AuthenticationError", 403: "PermissionDeniedError",
            429: "RateLimitError", 500: "InternalServerError", 503: "InternalServerError"}
_URLS = {"openai": "https://api.openai.com/v1/chat/completions", "anthropic": "https://api.anthropic.com/v1/messages"}


def api_error(provider, status, body, retry_after="120"):
    """The SDK's own status error, as raised for an HTTP ``status`` response."""
    sdk, http = (openai, httpx) if provider == "openai" else (anthropic, httpx2)
    response = http.Response(status, headers={"retry-after": retry_after},
                             request=http.Request("POST", _URLS[provider]))
    return getattr(sdk, _CLASSES[status])("PRIVATE provider message and credential", response=response, body=body)


def credit_error(provider, *, nested=True):
    """Exhausted credit: OpenAI answers 429 insufficient_quota, Anthropic a 400 credit-balance error."""
    if provider == "openai":
        details, status = {"code": "insufficient_quota", "message": "PRIVATE credit details"}, 429
    else:
        details, status = {"type": "invalid_request_error",
                           "message": "Your credit balance is too low. PRIVATE credit details"}, 400
    return api_error(provider, status, {"type": "error", "error": details} if nested else details)


@pytest.fixture(autouse=True)
def no_admission_network(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})


@pytest.mark.asyncio
@pytest.mark.parametrize("where", ["open", "stream"])
@pytest.mark.parametrize("nested", [False, True])
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_exhausted_credit_never_becomes_a_json_throttling_retry(provider, nested, where, caplog):
    client = client_for(provider)
    error = credit_error(provider, nested=nested)
    wire = serve(client, Reply(usage=None, **({"open_error": error} if where == "open" else {"error": error})))
    response = await client.generate_json("System", "User")
    assert response.data == {}
    assert response.error_code == "generation_unavailable"
    assert response.retryable is False
    assert response.retry_after_seconds is None
    assert "GenerationUnavailable" in response.error
    assert "RateLimitError" not in response.error
    assert not _may_retry(response, [])
    assert not _retryable_error(response)
    assert "PRIVATE" not in response.model_dump_json() + caplog.text
    # Rejected before any stream event: nothing was generated or billed.
    assert response.total_tokens == 0
    assert client.last_attempt is response
    assert all(stream.closed for stream in wire.streams)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("status", [401, 403])
async def test_json_auth_failures_are_explicitly_permanent(provider, status):
    client = client_for(provider)
    serve(client, Reply(open_error=api_error(provider, status, {"message": "PRIVATE"}), usage=None))
    response = await client.generate_json("System", "User")
    assert response.error_code == "generation_unavailable"
    assert response.retryable is False and response.retry_after_seconds is None
    assert not _may_retry(response, [])
    assert not _retryable_error(response)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("header,expected", [("2", 2), ("120", 120), ("invalid", 60), ("-1", 1), ("99999", 3600)])
async def test_genuine_json_throttling_preserves_sanitized_retry_metadata(provider, header, expected):
    client = client_for(provider)
    serve(client, Reply(usage=None, open_error=api_error(
        provider, 429, {"code": "rate_limit_exceeded", "message": "PRIVATE request"}, header)))
    response = await client.generate_json("System", "User")
    assert response.error_code == "generation_rate_limited"
    assert response.retryable is True
    assert "RateLimitError" in response.error and "PRIVATE" not in response.model_dump_json()
    assert response.total_tokens == 0  # rejected before any stream event
    assert response.retry_after_seconds == expected


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_json_timeout_retains_transient_policy_but_invalid_output_leaves_repair_to_caller(provider):
    client = client_for(provider)
    serve(client, Reply(error=TimeoutError("PRIVATE timeout"), usage=None))
    response = await client.generate_json("System", "User")
    assert response.retryable is True and response.retry_after_seconds is None
    assert response.error_code == "generation_failed"
    assert "PRIVATE" not in response.error

    serve(client, Reply('{"unfinished":', "length"))
    response = await client.generate_json("System", "User")
    assert response.retryable is None and response.retry_after_seconds is None
    assert response.finish_reason == "length"

    serve(client, Reply('{"invalid":}', "stop"))
    response = await client.generate_json("System", "User")
    assert "JSONDecodeError" in response.error and response.retry_after_seconds is None
    assert response.retryable is None


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", PROVIDERS)
async def test_success_does_not_retain_a_prior_request_error_policy(provider):
    client = client_for(provider)
    serve(client, Reply(open_error=credit_error(provider), usage=None))
    assert (await client.generate_json("System", "User")).retryable is False
    serve(client, Reply('{"ok":true}', "stop"))
    response = await client.generate_json("System", "User")
    assert response.data == {"ok": True}
    assert response.error is response.error_code is response.retryable is response.retry_after_seconds is None
