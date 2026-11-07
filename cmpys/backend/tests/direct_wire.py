"""Provider-neutral offline wire fakes for the direct clients (no network, no key).

``serve(client, replies)`` installs one fake SDK on an ``OpenAIDirectLLMClient``
or an ``AnthropicDirectLLMClient``. Each request takes the next ``Reply`` (or
the only one, or ``replies(request)`` when callable) and the returned ``Wire``
captures every request's parameters and stream. Finish reasons use the
pipeline's vocabulary (``stop``/``length``/``None`` for a stream that closed
without one); Anthropic replies map them onto stop reasons.
"""
import asyncio
import json
from types import SimpleNamespace as NS

from app.services.llm.protocol import PROMPT_SCHEMA_SUFFIX
from tests.llm_fakes import Stream, anthropic_client, chunk, openai_client

PROVIDERS = ("openai", "anthropic")
_STOP_REASONS = {"stop": "end_turn", "length": "max_tokens", "content_filter": "refusal"}


def client_for(provider, **options):
    return (openai_client if provider == "openai" else anthropic_client)(**options)


class Reply:
    """One provider reply.

    ``open_error`` is raised when the request opens (an HTTP status or connect
    failure); ``error`` is raised mid-stream after ``text`` and, for OpenAI,
    after the usage chunk. A ``None`` piece is an event without visible text.
    ``reasoning_text`` streams alongside the text (OpenAI ``reasoning_content``,
    Anthropic thinking deltas) and must never reach the response. ``ready``
    (an ``asyncio.Event``) makes the stream hang after its events, for
    cancellation tests.
    """

    def __init__(self, text="", finish="stop", *, usage=(31, 47), error=None, open_error=None, pieces=None,
                 ready=None, reasoning_tokens=None, reasoning_text=None):
        self.pieces = list(pieces) if pieces is not None else ([text] if text else [])
        self.finish, self.usage, self.error, self.open_error = finish, usage, error, open_error
        self.ready, self.reasoning_tokens, self.reasoning_text = ready, reasoning_tokens, reasoning_text

    @property
    def text(self):
        return "".join(piece for piece in self.pieces if piece)


class Wire:
    def __init__(self, replies):
        self.replies = replies
        self.requests = []
        self.streams = []

    def next_reply(self, request):
        self.requests.append(request)
        if callable(self.replies):
            return self.replies(request)
        if isinstance(self.replies, list):
            assert len(self.requests) <= len(self.replies), "Unexpected extra paid request"
            return self.replies[len(self.requests) - 1]
        return self.replies

    @property
    def request(self):
        return self.requests[-1]


class _HangingStream(Stream):
    def __init__(self, chunks, ready):
        super().__init__(chunks)
        self.ready = ready

    async def __aiter__(self):
        async for item in super().__aiter__():
            yield item
        self.ready.set()
        await asyncio.Event().wait()


def _openai_chunks(reply):
    items = [chunk(piece) for piece in reply.pieces]
    for item in items:
        item.choices[0].delta.reasoning_content = reply.reasoning_text
    if reply.error is None and reply.finish is not None:
        if items:
            items[-1].choices[0].finish_reason = reply.finish
        else:
            items.append(chunk("", reply.finish))
    if reply.usage is not None:
        prompt, completion = reply.usage
        details = None if reply.reasoning_tokens is None else NS(reasoning_tokens=reply.reasoning_tokens)
        items.append(NS(model="gpt-6-luna", choices=[], usage=NS(
            prompt_tokens=prompt, completion_tokens=completion, total_tokens=prompt + completion,
            prompt_tokens_details=None, completion_tokens_details=details)))
    if reply.error is not None:
        items.append(reply.error)
    return items


def _serve_openai(client, wire):
    async def create(**request):
        reply = wire.next_reply(request)
        if reply.open_error is not None:
            raise reply.open_error
        items = _openai_chunks(reply)
        stream = _HangingStream(items, reply.ready) if reply.ready is not None else Stream(items)
        wire.streams.append(stream)
        return stream

    client._client = NS(chat=NS(completions=NS(create=create)))


def _serve_anthropic(client, wire):
    class MessageStream:
        def __init__(self, **params):
            self.reply = wire.next_reply(params)
            self.closed = False
            self.received = False

        async def __aenter__(self):
            if self.reply.open_error is not None:
                raise self.reply.open_error
            wire.streams.append(self)  # only opened streams, as for OpenAI
            return self

        async def __aexit__(self, *exc):
            self.closed = True
            return False

        def __aiter__(self):
            async def events():
                # A real stream opens with message_start, which carries usage.
                self.received = True
                for piece in self.reply.pieces:
                    if self.reply.reasoning_text:
                        yield NS(type="content_block_delta",
                                 delta=NS(type="thinking_delta", thinking=self.reply.reasoning_text))
                    if piece is None:
                        yield NS(type="message_start")
                    else:
                        yield NS(type="content_block_delta", delta=NS(type="text_delta", text=piece))
                if self.reply.error is not None:
                    raise self.reply.error
                if self.reply.ready is not None:
                    self.reply.ready.set()
                    await asyncio.Event().wait()
            return events()

        def _usage(self):
            if self.reply.usage is None:
                return None
            prompt, completion = self.reply.usage
            details = (None if self.reply.reasoning_tokens is None
                       else NS(thinking_tokens=self.reply.reasoning_tokens))
            return NS(input_tokens=prompt, output_tokens=completion, cache_creation_input_tokens=None,
                      cache_read_input_tokens=None, iterations=None, output_tokens_details=details)

        async def get_final_message(self):
            stop = _STOP_REASONS.get(self.reply.finish, self.reply.finish)
            return NS(model=client.model, stop_reason=stop, usage=self._usage(),
                      content=[NS(type="text", text=self.reply.text)])

        def _current_snapshot_or_none(self):
            return NS(usage=self._usage()) if self.received else None

    client._client = NS(beta=NS(messages=NS(stream=MessageStream)))


def serve(client, replies):
    """Serve ``replies`` to every request ``client`` makes; returns the ``Wire``."""
    wire = Wire(replies)
    (_serve_openai if client.provider_name == "openai" else _serve_anthropic)(client, wire)
    return wire


def system_text(request):
    if "system" in request:
        return request["system"]
    return request["messages"][0]["content"]


def user_text(request):
    return request["messages"][-1]["content"]


def sent_schema(request):
    """The JSON schema the provider received, whichever JSON mode carried it."""
    response_format = request.get("response_format") or {}
    if response_format.get("type") == "json_schema":
        return response_format["json_schema"]["schema"]
    output_format = (request.get("output_config") or {}).get("format")
    if output_format:
        return output_format["schema"]
    system = system_text(request)
    return json.loads(system[system.index(PROMPT_SCHEMA_SUFFIX) + len(PROMPT_SCHEMA_SUFFIX):])


def request_text(request):
    """The system prompt plus any native schema, for matching what a request asked for."""
    return system_text(request) + json.dumps(
        request.get("response_format") or request.get("output_config") or {})
