"""Direct Anthropic client: Claude Haiku 5.5 by default (owner decision, 2026-11-07).

Ported from the tested pilot harness (``scripts/pilot_claude_client.py``), so
the app sends the contract the 2026-11-07 eval measured. Every request streams
from api.anthropic.com with usage and returns an ``LLMResponse`` in the
pipeline's finish-reason vocabulary (stop/length); refusals are errors.
Sampling parameters are never sent: current Claude models reject them.

JSON modes:
- ``native``: ``output_config.format`` with the SDK-transformed schema.
- ``prompt``: the schema is appended to the system prompt and the reply is
  parsed strictly (fenced JSON allowed, no brace balancing).
- ``auto`` (default): native when the schema survives the API's limits (no
  free-form dict fields, no untyped nodes), else prompt; a native 400 retries
  once in prompt mode (a 400 is not billed).

Thinking stays adaptive; ``thinking_level`` sets ``output_config.effort``.
Hidden thinking counts toward ``max_tokens``, so a reasoning reserve is sent on
top of the requested visible budget. Claude Haiku has no server-side refusal
fallback; other Claude models opt into it, and a reply served by a fallback
model is an error so one call never mixes models.
"""
import asyncio
import json
import logging
import time
from contextlib import aclosing
from types import SimpleNamespace
from uuid import uuid4

import anthropic
from anthropic.lib._parse._transform import transform_schema

from app.services.llm.client import BaseLLMClient, LLMResponse
from app.services.llm.protocol import (
    PROMPT_SCHEMA_SUFFIX,
    JSONProtocolError,
    ProviderStreamError,
    _complete_json_object,
    _unwrap_schema_answer,
    connect_phase_failure,
    json_protocol_category,
    status_category,
)

logger = logging.getLogger(__name__)

_NO_SERVER_FALLBACK = ("claude-haiku",)
_RETRYABLE_STATUS = {408, 409, 429, 500, 502, 503, 504, 529}


def claude_effort(thinking_level):
    """Map the pipeline's reasoning levels onto Claude effort (thinking stays adaptive)."""
    level = str(thinking_level or "low").casefold()
    if level in {"xhigh", "max"}:
        return "high"
    return level if level in {"low", "medium", "high"} else "low"


def native_schema_compatible(schema):
    """False when structured outputs would reject or silently narrow the schema."""
    def walk(node):
        if isinstance(node, dict):
            if node.get("type") == "object" and node.get("additionalProperties") not in (None, False):
                return False  # dict[str, X]: strict mode would force {}
            return all(walk(value) for value in node.values())
        if isinstance(node, list):
            return all(walk(value) for value in node)
        return True
    if not walk(schema):
        return False
    try:
        transform_schema(schema)
    except (ValueError, TypeError, RecursionError):
        return False  # e.g. untyped nodes (Any)
    return True


def _status_failure(error):
    """(category, error_code, retryable, retry_after) for an HTTP status error."""
    status = error.status_code
    try:
        retry_after = max(1, min(3600, int(float(error.response.headers.get("retry-after")))))
    except (TypeError, ValueError, AttributeError):
        retry_after = 60  # A limit without a usable delay still waits a full minute.
    body = getattr(error, "body", None)
    details = body.get("error", body) if isinstance(body, dict) else {}
    message = str(details.get("message", "")).casefold() if isinstance(details, dict) else ""
    # Exhausted credit arrives as a 400; never keep the upstream text itself.
    if status in {401, 402, 403} or "credit balance" in message:
        return "GenerationUnavailable", "generation_unavailable", False, None
    if status == 429:
        return "RateLimitError", "generation_rate_limited", True, retry_after
    if status == 400:
        return type(error).__name__, "bad_request", False, None
    retryable = status in _RETRYABLE_STATUS
    return (status_category(status, type(error).__name__), "generation_failed" if retryable else None,
            retryable, retry_after if retryable and error.response.headers.get("retry-after") else None)


class _MissingCredential(RuntimeError):
    pass


class AnthropicDirectLLMClient(BaseLLMClient):
    provider_name = "anthropic"

    def __init__(self, *, model=None, max_tokens=None, effort=None, thinking_level=None, timeout=150.0,
                 json_mode="auto", reasoning_reserve=None, api_key=None, **_ignored):
        from app.core.config import settings

        if json_mode not in {"native", "prompt", "auto"}:
            raise ValueError(f"Unknown Claude JSON mode: {json_mode}")
        if reasoning_reserve is None:
            reasoning_reserve = settings.anthropic_reasoning_token_reserve
        self.model = model or settings.anthropic_model
        self.timeout, self.json_mode, self.api_key = timeout, json_mode, api_key
        self.max_tokens = max_tokens or 4096
        # Sent on top of max_tokens: adaptive thinking shares the output budget.
        self.reasoning_reserve = int(reasoning_reserve)
        self.thinking_level = thinking_level or effort or "low"
        self.effort = claude_effort(effort or thinking_level)
        self.last_attempt = None
        self._client = None  # tests inject an SDK fake; requests otherwise share a pooled transport

    def _sdk(self):
        if self._client is not None:
            return self._client
        from app.core.config import settings
        from app.services.llm.transport import pooled_client

        key = self.api_key or settings.anthropic_api_key
        if not key:
            raise _MissingCredential()
        # The SDK's own retries would multiply a user-facing wait; callers own retries.
        return pooled_client(("anthropic", key), lambda: anthropic.AsyncAnthropic(api_key=key, max_retries=0),
                             timeout=self.timeout)

    def _params(self, system, user_prompt, output_config):
        params = dict(model=self.model, max_tokens=self.max_tokens + self.reasoning_reserve, system=system,
                      messages=[{"role": "user", "content": user_prompt}], output_config=output_config)
        if not self.model.startswith(_NO_SERVER_FALLBACK):
            params.update(betas=["server-side-fallback-2026-07-01"], fallbacks="default")
        return params

    def _mode_for(self, schema):
        if self.json_mode == "auto":
            return "native" if schema is not None and native_schema_compatible(schema) else "prompt"
        return self.json_mode if schema is not None else "prompt"

    async def generate_json(self, system_prompt, user_prompt, json_schema=None, output_model=None, **_):
        schema = output_model.model_json_schema() if output_model is not None else json_schema
        mode = self._mode_for(schema)
        response = await self._attempt(system_prompt, user_prompt, schema, output_model, mode)
        if mode == "native" and self.json_mode == "auto" and response.error_code == "bad_request":
            response = await self._attempt(system_prompt, user_prompt, schema, output_model, "prompt")
            response.effective_parameters["native_schema_rejected"] = True
        return response

    async def _attempt(self, system_prompt, user_prompt, schema, output_model, mode):
        from app.services.llm.admission import provider_permit
        from app.services.llm.tracing import record_attempt

        started = time.perf_counter()
        attempt_id = str(uuid4())
        schema_name = getattr(output_model, "__name__", None)
        output_config = {"effort": self.effort}
        system = system_prompt
        if mode == "native":
            output_config["format"] = {"type": "json_schema", "schema": transform_schema(schema)}
        else:
            system = system_prompt + PROMPT_SCHEMA_SUFFIX + json.dumps(schema or {"type": "object"})
        params = self._params(system, user_prompt, output_config)
        effective = {"max_tokens": params["max_tokens"], "effort": self.effort, "json_mode": mode,
                     "fallbacks": params.get("fallbacks")}
        timing = {"first_event_ms": None, "first_content_ms": None, "admission_wait_ms": None}
        await record_attempt(LLMResponse(data={}, error="pending_provider_attempt", model=self.model,
                                         provider=self.provider_name, attempt_id=attempt_id),
                             schema_name=schema_name, started=True)

        async def failure(error, *, code=None, retryable=None, retry_after=None, usage=None, chars=0,
                          finish=None):
            response = LLMResponse(data={}, error=error, error_code=code, retryable=retryable,
                                   retry_after_seconds=retry_after, model=self.model,
                                   provider=self.provider_name, attempt_id=attempt_id, finish_reason=finish,
                                   duration_ms=(time.perf_counter() - started) * 1000, response_chars=chars,
                                   effective_parameters=dict(effective), transport_success=False,
                                   json_valid=False, **timing, **_usage_fields(usage))
            self.last_attempt = response
            await record_attempt(response, schema_name=schema_name)
            return response

        stream = None
        chars = 0

        def partial_usage():
            # Usage seen before the fault; unknown spend stays unknown.
            snapshot = stream._current_snapshot_or_none() if stream is not None else None
            return getattr(snapshot, "usage", None)

        try:
            sdk = self._sdk()
            async with provider_permit(self.provider_name, self.model, timeout=self.timeout) as wait_ms, \
                    asyncio.timeout(self.timeout):
                timing["admission_wait_ms"] = wait_ms
                async with sdk.beta.messages.stream(**params) as stream:
                    async for event in stream:
                        now = (time.perf_counter() - started) * 1000
                        if timing["first_event_ms"] is None:
                            timing["first_event_ms"] = now
                        if event.type == "content_block_delta" and getattr(event.delta, "type", None) == "text_delta":
                            chars += len(event.delta.text or "")
                            if timing["first_content_ms"] is None:
                                timing["first_content_ms"] = now
                    message = await stream.get_final_message()
        except asyncio.CancelledError:
            response = LLMResponse(data={}, error="cancelled", model=self.model, provider=self.provider_name,
                                   attempt_id=attempt_id, duration_ms=(time.perf_counter() - started) * 1000,
                                   response_chars=chars, effective_parameters=dict(effective),
                                   transport_success=False, json_valid=False, **timing,
                                   **_usage_fields(partial_usage()))
            self.last_attempt = response
            await record_attempt(response, schema_name=schema_name, cancelled=True)
            raise
        except _MissingCredential:
            return await failure("anthropic request failed (MissingCredential; client)",
                                 code="generation_unavailable", retryable=False)
        except TimeoutError:
            return await failure("anthropic request failed (TimeoutError; deadline)", code="generation_failed",
                                 retryable=True, chars=chars, usage=partial_usage())
        except anthropic.APIStatusError as error:
            category, code, retryable, retry_after = _status_failure(error)
            # An HTTP error before any stream event is a rejected request: nothing
            # was generated or billed. A mid-stream error keeps usage unknown.
            rejected = None if timing["first_event_ms"] is not None else SimpleNamespace(
                input_tokens=0, output_tokens=0)
            return await failure(f"anthropic request failed ({category}; {error.status_code})", code=code,
                                 usage=rejected, retryable=retryable, retry_after=retry_after)
        except anthropic.APIConnectionError as error:  # includes APITimeoutError
            return await failure(f"anthropic request failed ({type(error).__name__}; connection)",
                                 code="generation_failed", retryable=True, chars=chars, usage=partial_usage())
        except anthropic.APIError as error:  # e.g. an error event mid-stream
            return await failure(f"anthropic request failed ({type(error).__name__}; stream)",
                                 code="generation_failed", retryable=True, chars=chars, usage=partial_usage())
        except anthropic.AnthropicError as error:
            return await failure(f"anthropic request failed ({type(error).__name__}; client)", retryable=False)
        except Exception as error:
            # The SDK re-raises transport faults (e.g. RemoteProtocolError) from
            # stream iteration unwrapped. Keep only the category: upstream text
            # can echo headers or user content.
            return await failure(f"anthropic request failed ({type(error).__name__}; stream)",
                                 code="generation_failed", chars=chars, usage=partial_usage())

        usage = message.usage
        served_by_fallback = any(getattr(entry, "type", None) == "fallback_message"
                                 for entry in (getattr(usage, "iterations", None) or []))
        text = "".join(block.text for block in message.content if block.type == "text")
        finish = {"end_turn": "stop", "max_tokens": "length"}.get(message.stop_reason, message.stop_reason)
        common = dict(model=message.model, provider=self.provider_name, finish_reason=finish,
                      response_chars=len(text), raw_response=text, attempt_id=attempt_id,
                      duration_ms=(time.perf_counter() - started) * 1000,
                      effective_parameters={**effective, "stop_reason": message.stop_reason,
                                            "served_by_fallback": served_by_fallback},
                      **timing, **_usage_fields(usage))
        error, retryable, data = None, None, {}
        if message.stop_reason is None:
            error, retryable = "anthropic request failed (IncompleteStreamError; finish=missing)", True
        elif message.stop_reason == "refusal" or served_by_fallback:
            error, retryable = f"claude {message.stop_reason}; served by {message.model}", False
        elif message.stop_reason == "max_tokens":
            error = "anthropic request failed (ValueError; finish=length)"
        elif message.stop_reason != "end_turn":
            error, retryable = f"anthropic request failed (ValueError; finish={message.stop_reason})", False
        else:
            try:
                if not text.strip():
                    raise JSONProtocolError("Empty JSON document")
                data = _unwrap_schema_answer(_complete_json_object(text), output_model)
            # A malformed document is the caller's bounded correction, not a transport retry.
            except JSONProtocolError as exc:
                error = f"anthropic request failed (JSONProtocolError; {exc})"
                common["effective_parameters"]["json_protocol_error"] = json_protocol_category(exc)
            except (json.JSONDecodeError, RecursionError) as exc:
                error = f"anthropic request failed (JSONDecodeError; {exc})"
                common["effective_parameters"]["json_protocol_error"] = json_protocol_category(exc)
        response = LLMResponse(data=data if error is None else {}, error=error, retryable=retryable,
                               error_code="generation_failed" if message.stop_reason is None else None,
                               transport_success=message.stop_reason in {"end_turn", "max_tokens"},
                               json_valid=error is None, **common)
        self.last_attempt = response
        await record_attempt(response, schema_name=schema_name)
        return response

    async def stream_text(self, system_prompt, user_prompt, *, operation):
        """Stream visible text; retry once only a connect failure before text.

        A connect-phase failure sent nothing and cost nothing, so it is retried
        once. Any other error, or any failure after text arrived, is raised as a
        ``ProviderStreamError``. Each actual request records its own usage row.
        """
        for attempt in (1, 2):
            try:
                async with aclosing(self._stream_text_attempt(
                    system_prompt, user_prompt, operation=operation, attempt=attempt,
                )) as pieces:
                    async for piece in pieces:
                        yield piece
                return
            except ProviderStreamError as exc:
                if attempt == 2 or not exc.connect_phase:
                    raise
                logger.warning("anthropic stream could not connect (%s); retrying once before any text",
                               operation)

    async def _stream_text_attempt(self, system_prompt, user_prompt, *, operation, attempt):
        from app.services.llm.admission import provider_permit
        from app.services.llm.telemetry import record_stream_usage

        started = time.perf_counter()
        usage, stop, served_model = None, None, None
        chars = 0
        success = False
        try:
            sdk = self._sdk()
            params = self._params(system_prompt, user_prompt, {"effort": self.effort})
            async with provider_permit(self.provider_name, self.model, timeout=self.timeout), \
                    asyncio.timeout(self.timeout):
                async with sdk.beta.messages.stream(**params) as stream:
                    async for event in stream:
                        if event.type == "content_block_delta" and getattr(event.delta, "type", None) == "text_delta":
                            if event.delta.text:
                                chars += len(event.delta.text)
                                yield event.delta.text
                    message = await stream.get_final_message()
            usage, stop, served_model = message.usage, message.stop_reason, message.model
            if stop != "end_turn" or not chars:
                raise ProviderStreamError(self.provider_name, f"finish={stop}", code="generation_failed",
                                          retryable=False)
            success = True
        except ProviderStreamError:
            raise
        except Exception as exc:
            raise _stream_error(exc, chars) from None
        finally:
            await record_stream_usage(operation=operation, provider=self.provider_name,
                                       model=served_model or self.model, usage=_usage_fields(usage),
                                       started=started, success=success, finish=stop, chars=chars,
                                       attempt=attempt)


def _stream_error(exc, chars):
    if isinstance(exc, _MissingCredential):
        return ProviderStreamError("anthropic", "MissingCredential", code="generation_unavailable", retryable=False)
    if isinstance(exc, anthropic.APIStatusError):
        category, code, retryable, retry_after = _status_failure(exc)
        return ProviderStreamError("anthropic", category, code=code or "generation_failed", retryable=retryable,
                                   retry_after_seconds=retry_after)
    if isinstance(exc, (anthropic.APIConnectionError, TimeoutError)):
        return ProviderStreamError("anthropic", type(exc).__name__, code="generation_failed", retryable=True,
                                   connect_phase=chars == 0 and connect_phase_failure(exc))
    return ProviderStreamError("anthropic", type(exc).__name__, code="generation_failed",
                               retryable=isinstance(exc, anthropic.APIError))


def _usage_fields(usage):
    if usage is None:
        return {}
    prompt = sum(getattr(usage, key, None) or 0 for key in (
        "input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    output = getattr(usage, "output_tokens", None)
    if output is None:
        return {"prompt_tokens": prompt}
    details = getattr(usage, "output_tokens_details", None)
    return {"prompt_tokens": prompt, "completion_tokens": output, "total_tokens": prompt + output,
            "thoughts_tokens": getattr(details, "thinking_tokens", None),
            "cached_prompt_tokens": getattr(usage, "cache_read_input_tokens", None)}
