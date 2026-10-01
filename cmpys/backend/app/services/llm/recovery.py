"""One explicitly scoped independent-provider retry after a gateway outage.

Callers own the retry count and record both responses separately. Content or
schema failures never authorize switching providers here.
"""

from app.core.config import settings
from app.services.llm.client import FallbackLLMClient, GeminiLLMClient


class CompleteRecoveryClient(GeminiLLMClient):
    async def generate_json(self, *args, **kwargs):
        response = await super().generate_json(*args, **kwargs)
        if not response.error and str(response.finish_reason).upper() != "STOP":
            response.error = "Independent recovery response was incomplete"
            response.data = {}
        return response


def operational_recovery_client(response, *, timeout: float, max_tokens: int):
    if getattr(response, "provider", None) != "openlux":
        return None
    error = str(getattr(response, "error", None) or "")
    # OpenLux sanitizes upstream failures to exception categories. A stream
    # ending without its terminal marker is transport failure, not bad JSON.
    interrupted = (
        error.startswith("OpenLux request failed (")
        and "finish=missing" in error
        and any(category in error for category in (
            "ValueError", "APIConnectionError", "RemoteProtocolError",
            "ReadError", "APIStatusError", "InternalServerError",
        ))
    )
    if not error or not (
        interrupted or FallbackLLMClient._is_operational_failure(error)
    ):
        return None
    if not settings.gemini_api_key:
        return None
    return CompleteRecoveryClient(
        model=settings.gemini_quality_model,
        timeout=timeout,
        max_tokens=max_tokens,
        thinking_level="low",
    )


# An operator-verified outage can be carried through one catalog call without
# changing provider settings for concurrent requests or other learners.
from contextlib import contextmanager
from contextvars import ContextVar

_scoped_failure = ContextVar('scoped_operational_failure', default=None)


@contextmanager
def scoped_operational_recovery(response):
    token = _scoped_failure.set(response)
    try:
        yield
    finally:
        _scoped_failure.reset(token)


def scoped_llm_client(**kwargs):
    from app.services.llm import get_llm_client
    recovery = operational_recovery_client(_scoped_failure.get(),
        timeout=kwargs['timeout'], max_tokens=kwargs['max_tokens'])
    return recovery or get_llm_client(**kwargs)
