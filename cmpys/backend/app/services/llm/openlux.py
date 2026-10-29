"""OpenLux chat transport with bounded streaming and complete usage accounting.

The verified account serves GPT through chat/completions streaming. Do not
retry an overloaded non-stream route or silently change providers/models.
"""

import asyncio
from contextlib import aclosing
import json
import logging
import math
import re
import time
from typing import Any

from pydantic import BaseModel, ValidationError

from app.services.llm.client import LLMResponse, OpenAILLMClient

logger = logging.getLogger(__name__)


class IncompleteStreamError(ValueError):
    """The stream closed without any finish reason: a transport fault, not a model answer."""


_INCOMPLETE_STREAM = re.compile(r"(?:zai|OpenLux) request failed \(IncompleteStreamError; finish=missing\)")


def incomplete_stream_error(error: str | None) -> bool:
    return bool(error) and _INCOMPLETE_STREAM.fullmatch(error) is not None


class JSONProtocolError(ValueError):
    """A completed document violates the strict JSON response contract.

    This signals caller-owned, bounded output correction. It is deliberately
    distinct from arbitrary ValueError failures and is not a transport retry.
    """


def _complete_json_object(raw: str) -> dict:
    """Decode one complete document, allowing only lossless wire framing.

    Never balance braces, invent values, or select one object from commentary.
    Literal control characters inside strings are preserved, not removed.
    Callers still validate the schema and the operation's content contract.
    """
    document = raw.strip()
    fenced = re.fullmatch(r"```(?:json)?\s*\n(.*?)\n\s*```", document, re.S | re.I)
    if fenced is not None:
        document = fenced.group(1)

    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise JSONProtocolError("Duplicate JSON property")
            result[key] = value
        return result

    def invalid_constant(_value):
        raise JSONProtocolError("Non-finite JSON number")

    def finite_float(value):
        result = float(value)
        if not math.isfinite(result):
            raise JSONProtocolError("Non-finite JSON number")
        return result

    data = json.loads(
        document, strict=False, object_pairs_hook=unique_object,
        parse_constant=invalid_constant, parse_float=finite_float,
    )
    if not isinstance(data, dict):
        raise JSONProtocolError("Expected a JSON object")
    return data


def _unwrap_schema_answer(data: dict, output_model: type[BaseModel] | None) -> dict:
    """Recover one complete provider envelope only when its payload validates.

    Some JSON-mode responses quote the requested object inside ``answer``.
    Never reinterpret a schema's real answer field, repair incomplete JSON,
    or bypass the caller's subsequent semantic/content checks.
    """
    if (
        output_model is None
        or set(data) != {"answer"}
        or "answer" in output_model.model_json_schema().get("properties", {})
    ):
        return data
    try:
        output_model.model_validate(data)
    except ValidationError:
        pass
    else:
        return data
    candidate = data["answer"]
    if isinstance(candidate, str):
        try:
            candidate = _complete_json_object(candidate)
        except (ValueError, RecursionError):
            return data
    if not isinstance(candidate, dict):
        return data
    try:
        output_model.model_validate(candidate)
    except ValidationError:
        return data
    return candidate


def _connect_phase_failure(error: BaseException) -> bool:
    """True only when the connection itself failed, so no request was sent.

    The SDK wraps transport errors as ``APIConnectionError`` /
    ``APITimeoutError`` raised ``from`` the httpx error, so the cause chain
    decides. A read timeout or a dropped stream is never a connect failure.
    """
    import httpx

    seen: set[int] = set()
    current: BaseException | None = error
    while current is not None and id(current) not in seen:
        if isinstance(current, (httpx.ConnectError, httpx.ConnectTimeout)):
            return True
        seen.add(id(current))
        current = current.__cause__
    return False


class OpenLuxStreamError(RuntimeError):
    """Sanitized failure category for deliberate, operation-specific recovery."""

    # Set by stream_text: the connect failed before any text, so one transport
    # retry is free (nothing was sent) and cannot splice two replies.
    connect_phase = False

    def __init__(self, error: Exception, provider: str = "openlux"):
        # HTTP 429 also covers exhausted credit. Never treat that as transient
        # throttling or retain provider response text (which can echo secrets).
        body = getattr(error, "body", None)
        details = body.get("error", body) if isinstance(body, dict) else {}
        business_code = str(details.get("code", "")) if isinstance(details, dict) else ""
        status = getattr(error, "status_code", None)
        unavailable = (
            (provider == "zai" and business_code == "1113")
            or business_code in {"insufficient_quota", "credit_balance_exhausted"}
            or status in {401, 403}
        )
        limited = status == 429 or type(error).__name__ == "RateLimitError"
        self.code = (
            "generation_unavailable" if unavailable else
            "generation_rate_limited" if limited else "generation_failed"
        )
        self.retryable = isinstance(error, (TimeoutError, ConnectionError)) or type(error).__name__ in {
            "APITimeoutError", "APIConnectionError", "RateLimitError", "InternalServerError",
        }
        if unavailable:
            self.retryable = False
        self.retry_after_seconds = None
        if limited and not unavailable:
            headers = getattr(getattr(error, "response", None), "headers", {})
            try:
                delay = int(headers.get("retry-after", "60"))
            except (TypeError, ValueError):
                delay = 60
            self.retry_after_seconds = max(1, min(delay, 3600))
        label = "OpenLux" if provider == "openlux" else provider
        super().__init__(f"{label} stream failed ({type(error).__name__}; {self.code})")


class OpenLuxLLMClient(OpenAILLMClient):
    def __init__(self, *, thinking_level: str | None = None, **kwargs):
        super().__init__(provider_name="openlux", **kwargs)
        self.thinking_level = (
            "low" if thinking_level in {None, "minimal"} else thinking_level
        )

    async def _events(self, system_prompt: str, user_prompt: str, schema=None):
        from app.core.config import settings

        if not self.api_key:
            raise RuntimeError("OpenLux credential is not configured")
        if schema is not None:
            system_prompt += (
                "\nReturn one JSON object matching this schema. Use its properties "
                "as the top-level keys; do not wrap or quote the object in an answer field:\n"
            ) + json.dumps(
                schema
            )
        kwargs: dict[str, Any] = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "stream": True,
            "stream_options": {"include_usage": True},
        }
        # Reasoning GPT models reject legacy sampling/output parameters.
        reasoning_model = self.model.startswith(("gpt-5", "gpt-6", "o1", "o3", "o4"))
        if reasoning_model:
            kwargs["reasoning_effort"] = self.thinking_level
            kwargs["max_completion_tokens"] = (
                self.max_tokens if self.max_tokens is not None else 4096
            ) + settings.openlux_reasoning_token_reserve
        else:
            kwargs["temperature"] = self.temperature
            kwargs["max_tokens"] = self.max_tokens or 4096
        if schema is not None:
            kwargs["response_format"] = {"type": "json_object"}
        self._effective_parameters = {k: v for k, v in kwargs.items() if k not in {"messages", "stream", "stream_options"}}
        from app.services.llm.admission import provider_permit
        async with provider_permit(self.provider_name, self.model, timeout=self.timeout) as wait_ms, asyncio.timeout(self.timeout):
            self._admission_wait_ms = wait_ms
            stream = await self._get_client(self.api_key).chat.completions.create(
                **kwargs
            )
            try:
                async for chunk in stream:
                    yield chunk
            finally:
                await stream.close()

    async def generate_json(
        self, system_prompt, user_prompt, json_schema=None, output_model=None
    ):
        schema = output_model.model_json_schema() if output_model else json_schema
        return await self._collect_json(
            system_prompt, user_prompt, schema or {"type": "object"},
            output_model=output_model,
        )

    async def generate_json_streaming(
        self, system_prompt, user_prompt, output_model=None, on_chunk=None
    ):
        schema = (
            output_model.model_json_schema() if output_model else {"type": "object"}
        )
        return await self._collect_json(
            system_prompt, user_prompt, schema, on_chunk, output_model=output_model
        )

    @staticmethod
    def _reported_reasoning_tokens(usage):
        """Keep an optional provider count, never estimate it from visible text."""
        details = getattr(usage, "completion_tokens_details", None)
        count = details.get("reasoning_tokens") if isinstance(details, dict) else getattr(details, "reasoning_tokens", None)
        completion = getattr(usage, "completion_tokens", None)
        if type(count) is not int or count < 0:
            return None
        if type(completion) is int and count > completion:
            return None
        return count

    async def _collect_json(
        self, system_prompt, user_prompt, schema, on_chunk=None, *, output_model=None
    ):
        started = time.perf_counter()
        text, finish, usage = "", None, None
        first_event_ms = None
        first_content_ms = None
        error = None
        error_code = None
        retryable = None
        retry_after_seconds = None
        data = {}
        transport_success = False
        self._admission_wait_ms = None
        self._effective_parameters = {}
        from app.services.llm.tracing import record_attempt
        attempt = LLMResponse(data={}, error="pending_provider_attempt", model=self.model, provider=self.provider_name)
        await record_attempt(attempt, schema_name=getattr(output_model, "__name__", None), started=True)
        try:
            async with aclosing(
                self._events(system_prompt, user_prompt, schema)
            ) as events:
                async for chunk in events:
                    if first_event_ms is None:
                        first_event_ms = (time.perf_counter() - started) * 1000
                    usage = getattr(chunk, "usage", None) or usage
                    for choice in chunk.choices:
                        if choice.index != 0:
                            continue
                        content = choice.delta.content or ""
                        if content and first_content_ms is None:
                            first_content_ms = (time.perf_counter() - started) * 1000
                        text += content
                        finish = choice.finish_reason or finish
                        if content and on_chunk:
                            await on_chunk(text)
            if finish is None:
                raise IncompleteStreamError("Incomplete response")
            if finish != "stop":
                raise ValueError("Incomplete response")
            transport_success = True
            if not text.strip():
                raise JSONProtocolError("Empty JSON document")
            data = _complete_json_object(text)
            data = _unwrap_schema_answer(data, output_model)
        except asyncio.CancelledError:
            from app.services.llm.tracing import record_attempt
            cancelled_response = LLMResponse(
                data={}, error="cancelled", provider=self.provider_name, model=self.model,
                prompt_tokens=getattr(usage, "prompt_tokens", None),
                completion_tokens=getattr(usage, "completion_tokens", None),
                total_tokens=getattr(usage, "total_tokens", None),
                thoughts_tokens=self._reported_reasoning_tokens(usage),
                duration_ms=(time.perf_counter() - started) * 1000,
                first_event_ms=first_event_ms,
                first_content_ms=first_content_ms,
                response_chars=len(text),
                finish_reason=finish,
                admission_wait_ms=getattr(self, "_admission_wait_ms", None),
                attempt_id=attempt.attempt_id,
                transport_success=False, json_valid=False,
                effective_parameters=getattr(self, "_effective_parameters", {}),
            )
            self.last_attempt = cancelled_response
            await record_attempt(cancelled_response, schema_name=getattr(output_model, "__name__", None), cancelled=True)
            raise
        except Exception as exc:
            # Upstream exceptions can echo headers or user content. Keep both
            # logs and persisted failures limited to a safe error category.
            classified = OpenLuxStreamError(exc, self.provider_name)
            error_code = classified.code
            if classified.code in {"generation_unavailable", "generation_rate_limited"} or classified.retryable:
                retryable = classified.retryable
                retry_after_seconds = classified.retry_after_seconds
            label = "OpenLux" if self.provider_name == "openlux" else self.provider_name
            # Credit exhaustion is also HTTP 429. Do not present its SDK
            # RateLimitError name as transient throttling to legacy callers.
            category = "GenerationUnavailable" if classified.code == "generation_unavailable" else type(exc).__name__
            error = f"{label} request failed ({category}; finish={finish or 'missing'})"
            if isinstance(exc, JSONProtocolError):
                # These categories are assigned from fixed parser messages only.
                # Never persist duplicate key names or the response document.
                self._effective_parameters["json_protocol_error"] = {
                    "Duplicate JSON property": "duplicate_property",
                    "Non-finite JSON number": "non_finite_number",
                    "Expected a JSON object": "non_object_document",
                    "Empty JSON document": "empty_document",
                }.get(str(exc), "invalid_json_document")
            if isinstance(exc, json.JSONDecodeError):
                self._effective_parameters["json_protocol_error"] = "invalid_json_syntax"
                # Decoder diagnostics contain locations, never response text.
                error += f"; JSON at line {exc.lineno} column {exc.colno}: {exc.msg}"
            logger.warning("%s", error)
        response = LLMResponse(
            data=data if error is None else {},
            raw_response=text,
            error=error,
            error_code=error_code,
            retryable=retryable,
            retry_after_seconds=retry_after_seconds,
            model=self.model,
            provider=self.provider_name,
            attempt_id=attempt.attempt_id,
            prompt_tokens=getattr(usage, "prompt_tokens", None),
            completion_tokens=getattr(usage, "completion_tokens", None),
            total_tokens=getattr(usage, "total_tokens", None),
            thoughts_tokens=self._reported_reasoning_tokens(usage),
            finish_reason=finish,
            duration_ms=(time.perf_counter() - started) * 1000,
            first_event_ms=first_event_ms,
            first_content_ms=first_content_ms,
            response_chars=len(text),
            admission_wait_ms=getattr(self, "_admission_wait_ms", None),
            cached_prompt_tokens=getattr(getattr(usage, "prompt_tokens_details", None), "cached_tokens", None),
            effective_parameters=getattr(self, "_effective_parameters", {}),
            transport_success=transport_success, json_valid=error is None,
        )
        self.last_attempt = response
        from app.services.llm.tracing import record_attempt
        await record_attempt(response, schema_name=getattr(output_model, "__name__", None))
        return response

    async def stream_text(self, system_prompt, user_prompt, *, operation):
        """Stream visible text; retry once only a connect failure before text.

        A connect-phase failure (the TCP/TLS connection never opened) sent
        nothing and cost nothing, so it is retried once. A read timeout, any
        other error, or any failure after text arrived is raised unchanged.
        Each actual request records its own usage row.
        """
        for attempt in (1, 2):
            try:
                async with aclosing(self._stream_text_attempt(
                    system_prompt, user_prompt, operation=operation, attempt=attempt,
                )) as pieces:
                    async for content in pieces:
                        yield content
                return
            except OpenLuxStreamError as exc:
                if attempt == 2 or not exc.connect_phase:
                    raise
                logger.warning(
                    "%s stream could not connect (%s); retrying once before any text",
                    self.provider_name, operation,
                )

    async def _stream_text_attempt(self, system_prompt, user_prompt, *, operation, attempt):
        from app.services.llm.telemetry import UsageRecord, record_usage_records

        started = time.perf_counter()
        usage, finish = None, None
        chars = 0
        success = False
        try:
            async with aclosing(self._events(system_prompt, user_prompt)) as events:
                async for chunk in events:
                    usage = getattr(chunk, "usage", None) or usage
                    for choice in chunk.choices:
                        if choice.index != 0:
                            continue
                        finish = choice.finish_reason or finish
                        content = choice.delta.content or ""
                        if content:
                            chars += len(content)
                            yield content
            if finish != "stop" or not chars:
                raise RuntimeError(f"{self.provider_name} returned an incomplete response")
            success = True
        except Exception as exc:
            error = OpenLuxStreamError(exc, self.provider_name)
            error.connect_phase = chars == 0 and _connect_phase_failure(exc)
            raise error from None
        finally:
            # Missing usage after an interrupted stream is unknown spend,
            # not a free call. Persist the failure even without a usage chunk.
            if usage is not None or not success:
                try:
                    async with asyncio.timeout(3):
                        await record_usage_records(
                            [
                                UsageRecord(
                                    operation=operation,
                                    model=self.model,
                                    provider=self.provider_name,
                                    prompt_tokens=getattr(usage, "prompt_tokens", None),
                                    completion_tokens=getattr(usage, "completion_tokens", None),
                                    total_tokens=getattr(usage, "total_tokens", None),
                                    duration_ms=(time.perf_counter() - started) * 1000,
                                    success=success,
                                    result_status="streamed"
                                    if success
                                    else "incomplete",
                                    metadata={
                                        "finish_reason": finish,
                                        "response_chars": chars,
                                        "attempt": attempt,
                                    },
                                )
                            ]
                        )
                except Exception as exc:
                    logger.warning(
                        "OpenLux usage recording failed (%s)", type(exc).__name__
                    )
