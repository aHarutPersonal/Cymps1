"""Offline SDK fakes for the direct Anthropic and OpenAI clients (no network, no key).

``openai_transport`` serves chat.completions stream chunks; ``anthropic_transport``
serves a messages stream. Both install the fake as the client's ``_client`` and
return the stream plus a dict that captures the request parameters.
"""
from types import SimpleNamespace as NS

from app.services.llm.anthropic_direct import AnthropicDirectLLMClient
from app.services.llm.openai_direct import OpenAIDirectLLMClient


def chunk(text="", finish=None, *, model="gpt-6-luna"):
    """One OpenAI chat.completions stream chunk."""
    return NS(model=model, choices=[NS(index=0, delta=NS(content=text, refusal=None), finish_reason=finish)],
              usage=None)


def usage_chunk(prompt_tokens=31, completion_tokens=47):
    return NS(model="gpt-6-luna", choices=[], usage=NS(
        prompt_tokens=prompt_tokens, completion_tokens=completion_tokens,
        total_tokens=prompt_tokens + completion_tokens, prompt_tokens_details=None, completion_tokens_details=None))


class Stream:
    def __init__(self, chunks):
        self.chunks = chunks
        self.closed = False

    async def __aiter__(self):
        for item in self.chunks:
            if isinstance(item, Exception):
                raise item
            yield item

    async def close(self):
        self.closed = True


def openai_transport(client, chunks):
    """Serve ``chunks`` (an exception item is raised mid-stream) to every request."""
    stream = Stream(chunks)
    kwargs = {}

    async def create(**kw):
        kwargs.update(kw)
        return stream

    client._client = NS(chat=NS(completions=NS(create=create)))
    return stream, kwargs


def anthropic_transport(client, text, *, stop="end_turn", model="claude-haiku-5-5", error=None,
                        input_tokens=31, output_tokens=47):
    """Serve one messages stream with ``text``; ``error`` is raised when the stream opens."""
    seen = {}

    class MessageStream:
        def __init__(self, **params):
            seen.update(params)

        async def __aenter__(self):
            if error is not None:
                raise error
            return self

        async def __aexit__(self, *exc):
            return False

        def __aiter__(self):
            async def events():
                yield NS(type="content_block_delta", delta=NS(type="text_delta", text=text))
            return events()

        async def get_final_message(self):
            usage = NS(input_tokens=input_tokens, output_tokens=output_tokens, cache_creation_input_tokens=None,
                       cache_read_input_tokens=None, iterations=None, output_tokens_details=None)
            return NS(model=model, stop_reason=stop, usage=usage, content=[NS(type="text", text=text)])

        def _current_snapshot_or_none(self):
            return None

    client._client = NS(beta=NS(messages=NS(stream=MessageStream)))
    return seen


def openai_client(**options):
    return OpenAIDirectLLMClient(**{"model": "gpt-6-luna", "api_key": "fake-test-key", **options})


def anthropic_client(**options):
    return AnthropicDirectLLMClient(**{"model": "claude-haiku-5-5", "api_key": "fake-test-key", **options})
