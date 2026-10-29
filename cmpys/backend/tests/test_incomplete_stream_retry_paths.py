"""A stream that closes without a finish reason is retried on every bounded path:
seed/activity components, the writer, package repair, preflight and lesson review."""
from app.services.llm.client import LLMResponse
from app.services.llm.openlux import incomplete_stream_error
from app.services.planning.lesson_writer import _may_retry as writer_may_retry
from app.services.planning.package_review import _retryable_error

MISSING = "zai request failed (IncompleteStreamError; finish=missing)"


def test_only_the_exact_incomplete_stream_text_matches():
    assert incomplete_stream_error(MISSING)
    assert incomplete_stream_error("OpenLux request failed (IncompleteStreamError; finish=missing)")
    for other in (None, "", "zai request failed (ValueError; finish=length)",
                  "zai request failed (ValueError; finish=stop)", "zai request failed (TypeError; finish=missing)",
                  "zai request failed (ValueError; finish=missing)"):
        assert not incomplete_stream_error(other)


def test_writer_and_preflight_retry_an_incomplete_stream_but_respect_refusal():
    assert writer_may_retry(LLMResponse(data={}, error=MISSING), [])
    assert _retryable_error(LLMResponse(data={}, error=MISSING))
    assert not writer_may_retry(LLMResponse(data={}, error=MISSING, retryable=False), [])
    assert not _retryable_error(LLMResponse(data={}, error=MISSING, retryable=False))
