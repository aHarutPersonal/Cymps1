"""OpenLux chat transport with bounded streaming and complete usage accounting.

The verified account serves GPT through chat/completions streaming. Do not
retry an overloaded non-stream route or silently change providers/models.
"""

import asyncio
from contextlib import aclosing
import json
import logging
import time
from typing import Any

from pydantic import BaseModel, ValidationError

from app.services.llm.client import LLMResponse, OpenAILLMClient

logger = logging.getLogger(__name__)


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
            candidate = json.loads(candidate)
        except (ValueError, RecursionError):
            return data
    if not isinstance(candidate, dict):
        return data
    try:
        output_model.model_validate(candidate)
    except ValidationError:
        return data
    return candidate


class OpenLuxStreamError(RuntimeError):
    """Sanitized failure category for deliberate, operation-specific recovery."""

    def __init__(self, error: Exception, provider: str = "openlux"):
        self.retryable = isinstance(error, (TimeoutError, ConnectionError)) or type(error).__name__ in {
            "APITimeoutError", "APIConnectionError", "RateLimitError", "InternalServerError",
        }
        label = "OpenLux" if provider == "openlux" else provider
        super().__init__(f"{label} stream failed ({type(error).__name__})")


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
        async with asyncio.timeout(self.timeout):
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

    async def _collect_json(
        self, system_prompt, user_prompt, schema, on_chunk=None, *, output_model=None
    ):
        started = time.perf_counter()
        text, finish, usage = "", None, None
        error = None
        data = {}
        try:
            async with aclosing(
                self._events(system_prompt, user_prompt, schema)
            ) as events:
                async for chunk in events:
                    usage = getattr(chunk, "usage", None) or usage
                    for choice in chunk.choices:
                        if choice.index != 0:
                            continue
                        content = choice.delta.content or ""
                        text += content
                        finish = choice.finish_reason or finish
                        if content and on_chunk:
                            await on_chunk(text)
            if finish != "stop" or not text.strip():
                raise ValueError("Incomplete or empty response")
            data = json.loads(text)
            if not isinstance(data, dict):
                raise ValueError("Expected a JSON object")
            data = _unwrap_schema_answer(data, output_model)
        except Exception as exc:
            # Upstream exceptions can echo headers or user content. Keep both
            # logs and persisted failures limited to a safe error category.
            label = "OpenLux" if self.provider_name == "openlux" else self.provider_name
            error = f"{label} request failed ({type(exc).__name__}; finish={finish or 'missing'})"
            logger.warning("%s", error)
        return LLMResponse(
            data=data if error is None else {},
            raw_response=text,
            error=error,
            model=self.model,
            provider=self.provider_name,
            prompt_tokens=getattr(usage, "prompt_tokens", None),
            completion_tokens=getattr(usage, "completion_tokens", None),
            total_tokens=getattr(usage, "total_tokens", None),
            finish_reason=finish,
            duration_ms=(time.perf_counter() - started) * 1000,
        )

    async def stream_text(self, system_prompt, user_prompt, *, operation):
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
            raise OpenLuxStreamError(exc, self.provider_name) from None
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
                                    },
                                )
                            ]
                        )
                except Exception as exc:
                    logger.warning(
                        "OpenLux usage recording failed (%s)", type(exc).__name__
                    )
