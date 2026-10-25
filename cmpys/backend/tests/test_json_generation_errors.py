"""JSON transport must distinguish exhausted credit from temporary throttling."""
import httpx
import pytest
from openai import AuthenticationError, PermissionDeniedError, RateLimitError

from app.core.config import settings
from app.services.llm.openlux import OpenLuxLLMClient
from app.services.llm.zai import ZaiLLMClient
from app.services.planning.lesson_writer import _may_retry
from app.services.planning.package_review import _retryable_error
from tests.test_openlux import chunk, transport


def client_for(provider):
    if provider == "zai":
        return ZaiLLMClient(model="glm-5.3", api_key="fake-test-key",
                            base_url="https://api.z.ai/api/paas/v4")
    return OpenLuxLLMClient(model="gpt-5.6-terra", api_key="fake-test-key",
                            base_url="https://api.openlux.ai/v1")


def api_error(error_type, status, body, retry_after="120"):
    return error_type(
        "PRIVATE provider message and credential",
        body=body,
        response=httpx.Response(status, headers={"retry-after": retry_after},
                                request=httpx.Request("POST", "https://example.test")),
    )


@pytest.fixture(autouse=True)
def no_admission_network(monkeypatch):
    monkeypatch.setattr(settings, "llm_admission_limits", {})


@pytest.mark.asyncio
@pytest.mark.parametrize("streaming", [False, True])
@pytest.mark.parametrize("nested", [False, True])
@pytest.mark.parametrize("provider,code", [
    ("zai", "1113"), ("zai", 1113),
    ("zai", "insufficient_quota"), ("openlux", "credit_balance_exhausted"),
])
async def test_exhausted_credit_never_becomes_a_json_throttling_retry(
    monkeypatch, provider, code, nested, streaming, caplog,
):
    client = client_for(provider)
    details = {"code": code, "message": "PRIVATE credit details"}
    stream, _ = transport(monkeypatch, client, [api_error(
        RateLimitError, 429, {"error": details} if nested else details,
    )])
    generate = client.generate_json_streaming if streaming else client.generate_json
    response = await generate("System", "User")
    assert response.data == {}
    assert response.error_code == "generation_unavailable"
    assert response.retryable is False
    assert response.retry_after_seconds is None
    assert "GenerationUnavailable" in response.error
    assert "RateLimitError" not in response.error
    assert not _may_retry(response, [])
    assert not _retryable_error(response)
    assert "PRIVATE" not in response.model_dump_json() + caplog.text
    assert response.total_tokens is None
    assert client.last_attempt is response and stream.closed


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", ["zai", "openlux"])
@pytest.mark.parametrize("error_type,status", [
    (AuthenticationError, 401), (PermissionDeniedError, 403),
])
async def test_json_auth_failures_are_explicitly_permanent(monkeypatch, provider, error_type, status):
    client = client_for(provider)
    transport(monkeypatch, client, [api_error(error_type, status, {"message": "PRIVATE"})])
    response = await client.generate_json("System", "User")
    assert response.error_code == "generation_unavailable"
    assert response.retryable is False and response.retry_after_seconds is None
    assert not _may_retry(response, [])
    assert not _retryable_error(response)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", ["zai", "openlux"])
@pytest.mark.parametrize("header,expected", [("2", 2), ("120", 120), ("invalid", 60), ("-1", 1), ("99999", 3600)])
async def test_genuine_json_throttling_preserves_sanitized_retry_metadata(monkeypatch, provider, header, expected):
    client = client_for(provider)
    transport(monkeypatch, client, [api_error(
        RateLimitError, 429, {"code": "1302", "message": "PRIVATE request"}, header,
    )])
    response = await client.generate_json("System", "User")
    assert response.error_code == "generation_rate_limited"
    assert response.retryable is True
    assert response.retry_after_seconds == expected
    assert "RateLimitError" in response.error and "PRIVATE" not in response.model_dump_json()
    assert response.total_tokens is None


@pytest.mark.asyncio
async def test_json_timeout_retains_transient_policy_but_invalid_output_leaves_repair_to_caller(monkeypatch):
    client = client_for("zai")
    transport(monkeypatch, client, [TimeoutError("PRIVATE timeout")])
    response = await client.generate_json("System", "User")
    assert response.retryable is True and response.retry_after_seconds is None
    assert response.error_code == "generation_failed"

    transport(monkeypatch, client, [chunk('{"unfinished":', "length")])
    response = await client.generate_json("System", "User")
    assert response.retryable is None and response.retry_after_seconds is None
    assert response.finish_reason == "length"

    transport(monkeypatch, client, [chunk('{"invalid":}', "stop")])
    response = await client.generate_json("System", "User")
    assert response.retryable is None and "JSONDecodeError" in response.error


@pytest.mark.asyncio
async def test_success_does_not_retain_a_prior_request_error_policy(monkeypatch):
    client = client_for("zai")
    transport(monkeypatch, client, [api_error(RateLimitError, 429, {"code": "1113"})])
    assert (await client.generate_json("System", "User")).retryable is False
    transport(monkeypatch, client, [chunk('{"ok":true}', "stop")])
    response = await client.generate_json("System", "User")
    assert response.data == {"ok": True}
    assert response.error is response.error_code is response.retryable is response.retry_after_seconds is None
