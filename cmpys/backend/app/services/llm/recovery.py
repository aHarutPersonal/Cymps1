"""One explicitly scoped backup-model retry after the primary was unavailable.

Callers own the retry count and record both responses separately. Content or
schema failures never authorize switching providers here.
"""

from contextlib import contextmanager
from contextvars import ContextVar

from app.core.config import settings
from app.services.llm.client import BaseLLMClient, FallbackLLMClient, direct_client, provider_configured
from app.services.llm.protocol import DIRECT_PROVIDERS
from app.services.llm.routes import other_provider


class CompleteRecoveryClient(BaseLLMClient):
    """The backup model for one recovery call; an unfinished reply is an error."""

    def __init__(self, client: BaseLLMClient):
        self._client = client

    def __getattr__(self, name):
        return getattr(self._client, name)

    async def generate_json(self, *args, **kwargs):
        response = await self._client.generate_json(*args, **kwargs)
        if not response.error and str(response.finish_reason).casefold() != "stop":
            response.error = "Independent recovery response was incomplete"
            response.data = {}
        return response


def operational_recovery_client(response, *, timeout: float, max_tokens: int):
    """The other direct provider when ``response`` failed because its provider was unavailable."""
    provider = getattr(response, "provider", None)
    if provider not in DIRECT_PROVIDERS or settings.llm_provider == "dummy":
        return None
    if not getattr(response, "error", None) or not FallbackLLMClient.unavailable(response):
        return None
    backup = other_provider(provider)
    if not provider_configured(backup):
        return None
    return CompleteRecoveryClient(direct_client(backup, timeout=timeout, max_tokens=max_tokens,
                                                thinking_level="low"))


# An operator-verified outage can be carried through one catalog call without
# changing provider settings for concurrent requests or other learners.
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
