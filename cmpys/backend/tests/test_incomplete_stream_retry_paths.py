"""A stream that closes without a finish reason is retried on every bounded path:
seed/activity components, the writer, package repair, preflight and lesson review."""
import pytest

from app.services.llm.client import LLMResponse
from app.services.llm.protocol import incomplete_stream_error
from app.services.planning.lesson_writer import _may_retry as writer_may_retry
from app.services.planning.package_review import _retryable_error


@pytest.mark.parametrize("provider", ["openai", "anthropic"])
def test_only_the_exact_incomplete_stream_text_matches(provider):
    assert incomplete_stream_error(f"{provider} request failed (IncompleteStreamError; finish=missing)")
    for other in (None, "", f"{provider} request failed (ValueError; finish=length)",
                  f"{provider} request failed (ValueError; finish=stop)",
                  f"{provider} request failed (TypeError; finish=missing)",
                  f"{provider} request failed (ValueError; finish=missing)",
                  # Retired gateways no longer produce this contract.
                  "zai request failed (IncompleteStreamError; finish=missing)",
                  "OpenLux request failed (IncompleteStreamError; finish=missing)"):
        assert not incomplete_stream_error(other)


@pytest.mark.parametrize("provider", ["openai", "anthropic"])
def test_writer_and_preflight_retry_an_incomplete_stream_but_respect_refusal(provider):
    missing = f"{provider} request failed (IncompleteStreamError; finish=missing)"
    assert writer_may_retry(LLMResponse(data={}, error=missing), [])
    assert _retryable_error(LLMResponse(data={}, error=missing))
    assert not writer_may_retry(LLMResponse(data={}, error=missing, retryable=False), [])
    assert not _retryable_error(LLMResponse(data={}, error=missing, retryable=False))
