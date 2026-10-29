"""A stream that closes without a finish reason is a transport fault: the
component gets its bounded correction instead of ending the package."""
from app.services.llm.client import LLMResponse
from app.services.planning.package_builder import _may_retry


def test_incomplete_stream_without_finish_reason_is_retried():
    for provider in ("zai", "OpenLux"):
        response = LLMResponse(data={}, error=f"{provider} request failed (IncompleteStreamError; finish=missing)")
        assert _may_retry(response, invalid=False)


def test_other_value_errors_and_explicit_refusals_are_not_retried():
    assert not _may_retry(LLMResponse(data={}, error="zai request failed (ValueError; finish=stop)"), invalid=False)
    assert not _may_retry(LLMResponse(data={}, error="zai request failed (ValueError)"), invalid=False)
    assert not _may_retry(LLMResponse(data={}, error="zai request failed (ValueError; finish=missing)"), invalid=False)
    refused = LLMResponse(data={}, error="zai request failed (IncompleteStreamError; finish=missing)", retryable=False)
    assert not _may_retry(refused, invalid=False)
