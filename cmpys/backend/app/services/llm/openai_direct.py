"""Direct OpenAI client: gpt-6-luna by default (owner decision, 2026-11-07).

Moved from the tested pilot harness (``scripts/pilot_openai_client.py``) so the
app sends GPT reasoning models the same schema-enforced contract the pilots
measured: ``reasoning_effort`` and ``max_completion_tokens``, never
``temperature`` or ``max_tokens``, which these models reject. Every request
streams chat.completions from api.openai.com with usage and returns an
``LLMResponse`` in the pipeline's finish-reason vocabulary (stop/length);
refusals and content filtering are errors.

JSON modes:
- ``native``: ``response_format`` json_schema with ``strict: True`` and the
  strict-compatible schema from ``openai_strict_schema``.
- ``prompt``: the schema is appended to the system prompt (with
  ``response_format=json_object``) and parsed strictly (fenced JSON allowed,
  no brace balancing).
- ``auto`` (default): native when the schema converts cleanly (no free-form
  dict fields, no untyped nodes, inside the strict-mode size limits), else
  prompt; a native 400 retries once in prompt mode (a 400 is not billed).

Strict schema: every property is required, and a property the source schema
made optional becomes nullable (a null for it is dropped before validation so
the Pydantic default applies). Keywords strict mode rejects move into the
node's description as ``{key: value}``, as Anthropic's ``transform_schema``
does, so Pydantic still enforces them after parsing.
"""
import asyncio
import copy
import json
import logging
import time
from contextlib import aclosing
from types import SimpleNamespace
from uuid import uuid4

import openai

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
_RETRYABLE_STATUS = {408, 409, 429, 500, 502, 503, 504}
# Strict-mode limits (documented): nesting depth, total properties, enum values.
_MAX_DEPTH, _MAX_PROPERTIES, _MAX_ENUM_VALUES = 10, 5000, 1000
_STRING_FORMATS = {"date-time", "time", "date", "duration", "email", "hostname", "ipv4", "ipv6", "uuid"}
_KEEP_COMMON = {"description", "title"}
_KEEP_BY_TYPE = {
    "string": {"pattern", "format"},
    "number": {"minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"},
    "integer": {"minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"},
    "array": {"minItems", "maxItems"},
}


def openai_reasoning_effort(thinking_level):
    """Map the pipeline's reasoning levels onto ``reasoning_effort``."""
    level = str(thinking_level or "low").casefold()
    if level in {"xhigh", "max"}:
        return "high"
    return level if level in {"low", "medium", "high"} else "low"  # minimal/none/off -> low


class StrictSchemaError(ValueError):
    """The schema cannot be expressed in strict mode without changing its meaning."""


def openai_strict_schema(schema):
    """Return ``(strict_schema, optional_keys)`` or raise ``StrictSchemaError``.

    ``optional_keys`` maps ``id(object node)`` in the returned schema to the
    property names made nullable here; ``drop_added_nulls`` uses it.
    """
    if not isinstance(schema, dict):
        raise StrictSchemaError("schema is not an object")
    root = copy.deepcopy(schema)
    raw_defs = root.pop("$defs", None) or {}
    optional_keys = {}
    counts = {"properties": 0}

    def resolve(ref):
        if not isinstance(ref, str) or not ref.startswith("#/$defs/") or ref[8:] not in raw_defs:
            raise StrictSchemaError(f"unsupported $ref {ref!r}")
        return raw_defs[ref[8:]]

    def nullable(node, seen=frozenset()):
        type_ = node.get("type")
        if type_ == "null" or (isinstance(type_, list) and "null" in type_):
            return True
        if "$ref" in node and len(node) == 1:
            return node["$ref"] not in seen and nullable(resolve(node["$ref"]), seen | {node["$ref"]})
        return any(isinstance(v, dict) and nullable(v, seen) for v in node.get("anyOf", []))

    def walk(node):
        if not isinstance(node, dict):
            raise StrictSchemaError("non-object schema node")
        node = dict(node)
        if "$ref" in node:
            if len(node) == 1:
                return node
            # Strict mode rejects $ref siblings: inline the definition (siblings win).
            node = {**resolve(node.pop("$ref")), **node}
        all_of = node.pop("allOf", None)
        if all_of is not None:
            if not isinstance(all_of, list) or len(all_of) != 1 or not isinstance(all_of[0], dict):
                raise StrictSchemaError("allOf with several entries")
            only = all_of[0]
            if "$ref" in only and len(only) == 1:
                only = resolve(only["$ref"])
            return walk({**only, **node})
        out, leftover = {}, {}
        variants = node.pop("anyOf", None)
        one_of = node.pop("oneOf", None)
        if variants is None and one_of is not None:
            variants = one_of
            node.pop("discriminator", None)  # each variant's const kind carries it
        if variants is not None:
            out["anyOf"] = [walk(variant) for variant in variants]
        type_ = node.pop("type", None)
        types = type_ if isinstance(type_, list) else [type_] if type_ is not None else []
        if variants is None:
            if not types and "const" not in node and "enum" not in node:
                raise StrictSchemaError("untyped node")  # e.g. Any
            if type_ is not None:
                out["type"] = type_
        elif type_ is not None:
            leftover["type"] = type_
        if "const" in node:
            out["enum"] = [node.pop("const")]
        if "enum" in node:
            values = node.pop("enum")
            if len(values) > _MAX_ENUM_VALUES:
                raise StrictSchemaError("enum too large")
            out["enum"] = [v for v in values if v in out["enum"]] if "enum" in out else values
        if "object" in types:
            extra = node.pop("additionalProperties", None)
            if extra not in (None, False):
                raise StrictSchemaError("free-form dict field")  # strict mode would force {}
            properties = node.pop("properties", {})
            counts["properties"] += len(properties)
            required = set(node.pop("required", []))
            out["properties"], added = {}, set()
            for key, prop in properties.items():
                strict = walk(prop)
                if key not in required and not nullable(prop if isinstance(prop, dict) else {}):
                    strict = {"anyOf": [strict, {"type": "null"}]}
                    added.add(key)
                out["properties"][key] = strict
            out["required"] = list(properties)
            out["additionalProperties"] = False
            if added:
                optional_keys[id(out)] = added
        if "array" in types:
            if not isinstance(node.get("items"), dict):
                raise StrictSchemaError("array without an item schema")
            out["items"] = walk(node.pop("items"))
        if node.get("format") is not None and node["format"] not in _STRING_FORMATS:
            leftover["format"] = node.pop("format")
        keep = set(_KEEP_COMMON).union(*(_KEEP_BY_TYPE.get(t, set()) for t in types))
        for key, value in node.items():
            (out if key in keep else leftover)[key] = value
        if leftover:
            # As Anthropic's transform_schema does: keep the hint, Pydantic enforces it.
            text = "{" + ", ".join(f"{key}: {value}" for key, value in leftover.items()) + "}"
            out["description"] = (out["description"] + "\n\n" if out.get("description") else "") + text
        return out

    strict_defs = {name: walk(definition) for name, definition in raw_defs.items()}
    top = walk(root)
    if top.get("type") != "object":
        raise StrictSchemaError("root is not an object")
    if counts["properties"] > _MAX_PROPERTIES:
        raise StrictSchemaError("too many properties")

    def depth(node, seen):
        if not isinstance(node, dict):
            return 0
        if "$ref" in node:
            name = node["$ref"][8:]
            return 0 if name in seen else depth(strict_defs[name], seen | {name})
        here = 1 if node.get("type") == "object" else 0
        children = list((node.get("properties") or {}).values()) + list(node.get("anyOf") or [])
        if isinstance(node.get("items"), dict):
            children.append(node["items"])
        return here + max((depth(child, seen) for child in children), default=0)

    if depth(top, frozenset()) > _MAX_DEPTH:
        raise StrictSchemaError("nesting too deep")
    if strict_defs:
        top["$defs"] = strict_defs
    return top, optional_keys


def native_schema_compatible(schema):
    """False when strict structured outputs would reject or silently narrow the schema."""
    try:
        openai_strict_schema(schema)
    except (StrictSchemaError, RecursionError, TypeError):
        return False
    return True


def drop_added_nulls(data, strict_schema, optional_keys):
    """Remove nulls strict mode forced onto properties the source left optional."""
    defs = strict_schema.get("$defs", {})

    def resolve(node):
        while isinstance(node, dict) and "$ref" in node:
            node = defs[node["$ref"][8:]]
        return node

    def matches(node, value):
        node = resolve(node)
        if isinstance(value, dict):
            props = node.get("properties")
            if props is None or not set(value) <= set(props):
                return False
            return all(len(resolve(props[key]).get("enum", [None, None])) != 1
                       or value.get(key) == resolve(props[key])["enum"][0] for key in value)
        if isinstance(value, list):
            return node.get("type") == "array"
        return True

    def walk(node, value):
        node = resolve(node)
        if "anyOf" in node:
            for variant in node["anyOf"]:
                if (isinstance(value, (dict, list)) and resolve(variant).get("type") != "null"
                        and matches(variant, value)):
                    return walk(variant, value)
            return value
        if isinstance(value, dict) and "properties" in node:
            added = optional_keys.get(id(node), set())
            # A key outside the schema passes through unchanged; Pydantic decides.
            return {key: walk(node["properties"][key], item) if key in node["properties"] else item
                    for key, item in value.items() if not (item is None and key in added)}
        if isinstance(value, list) and isinstance(node.get("items"), dict):
            return [walk(node["items"], item) for item in value]
        return value

    return walk(strict_schema, data)


def reported_reasoning_tokens(usage):
    """Keep an optional provider count, never estimate it from visible text."""
    details = getattr(usage, "completion_tokens_details", None)
    count = details.get("reasoning_tokens") if isinstance(details, dict) else getattr(details, "reasoning_tokens", None)
    completion = getattr(usage, "completion_tokens", None)
    if type(count) is not int or count < 0:
        return None
    if type(completion) is int and count > completion:
        return None
    return count


def _status_failure(error):
    """(category, error_code, retryable, retry_after) for an HTTP status error."""
    status = error.status_code
    try:
        retry_after = max(1, min(3600, int(float(error.response.headers.get("retry-after")))))
    except (TypeError, ValueError, AttributeError):
        retry_after = 60  # A limit without a usable delay still waits a full minute.
    body = getattr(error, "body", None)
    details = body.get("error", body) if isinstance(body, dict) else {}
    business_code = str(details.get("code", "")) if isinstance(details, dict) else ""
    # HTTP 429 also covers exhausted credit. Never treat that as transient
    # throttling or retain provider response text (which can echo secrets).
    if status in {401, 402, 403} or business_code == "insufficient_quota":
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


class OpenAIDirectLLMClient(BaseLLMClient):
    provider_name = "openai"

    def __init__(self, *, model=None, max_tokens=None, effort=None, thinking_level=None, timeout=150.0,
                 json_mode="auto", reasoning_reserve=None, api_key=None, **_ignored):
        from app.core.config import settings

        if json_mode not in {"native", "prompt", "auto"}:
            raise ValueError(f"Unknown OpenAI JSON mode: {json_mode}")
        if reasoning_reserve is None:
            reasoning_reserve = settings.openai_reasoning_token_reserve
        self.model = model or settings.openai_model
        self.timeout, self.json_mode, self.api_key = timeout, json_mode, api_key
        self.max_tokens = max_tokens or 4096
        # Sent on top of max_tokens: hidden reasoning shares the completion budget.
        self.reasoning_reserve = int(reasoning_reserve)
        self.thinking_level = thinking_level or effort or "low"
        self.effort = openai_reasoning_effort(effort or thinking_level)
        self.last_attempt = None
        self._client = None  # tests inject an SDK fake; requests otherwise share a pooled transport

    def _sdk(self):
        if self._client is not None:
            return self._client
        from app.core.config import settings
        from app.services.llm.transport import pooled_client

        key = self.api_key or settings.openai_api_key
        if not key:
            raise _MissingCredential()
        # The SDK's own retries would multiply a user-facing wait; callers own retries.
        return pooled_client(("openai", key), lambda: openai.AsyncOpenAI(api_key=key, max_retries=0),
                             timeout=self.timeout)

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
        system = system_prompt
        optional_keys, strict = {}, None
        if mode == "native":
            strict, optional_keys = openai_strict_schema(schema)
            name = getattr(output_model, "__name__", None) or "response"
            response_format = {"type": "json_schema",
                               "json_schema": {"name": name[:64], "schema": strict, "strict": True}}
        else:
            system = system_prompt + PROMPT_SCHEMA_SUFFIX + json.dumps(schema or {"type": "object"})
            response_format = {"type": "json_object"}
        params = dict(model=self.model, messages=[{"role": "system", "content": system},
                                                  {"role": "user", "content": user_prompt}],
                      reasoning_effort=self.effort, max_completion_tokens=self.max_tokens + self.reasoning_reserve,
                      response_format=response_format, stream=True, stream_options={"include_usage": True},
                      store=False)
        effective = {"max_completion_tokens": params["max_completion_tokens"], "reasoning_effort": self.effort,
                     "json_mode": mode}
        timing = {"first_event_ms": None, "first_content_ms": None, "admission_wait_ms": None}
        text, refusal, finish, usage, served_model = "", "", None, None, None
        await record_attempt(LLMResponse(data={}, error="pending_provider_attempt", model=self.model,
                                         provider=self.provider_name, attempt_id=attempt_id),
                             schema_name=schema_name, started=True)

        async def failure(error, *, code=None, retryable=None, retry_after=None, usage=None, chars=0,
                          finish=None):
            tokens = _usage_fields(usage)
            response = LLMResponse(data={}, error=error, error_code=code, retryable=retryable,
                                   retry_after_seconds=retry_after, model=served_model or self.model,
                                   provider=self.provider_name, attempt_id=attempt_id, finish_reason=finish,
                                   duration_ms=(time.perf_counter() - started) * 1000, response_chars=chars,
                                   effective_parameters=dict(effective), transport_success=False,
                                   json_valid=False, **timing, **tokens)
            self.last_attempt = response
            await record_attempt(response, schema_name=schema_name)
            return response

        try:
            sdk = self._sdk()
            async with provider_permit(self.provider_name, self.model, timeout=self.timeout) as wait_ms, \
                    asyncio.timeout(self.timeout):
                timing["admission_wait_ms"] = wait_ms
                stream = await sdk.chat.completions.create(**params)
                try:
                    async for chunk in stream:
                        now = (time.perf_counter() - started) * 1000
                        if timing["first_event_ms"] is None:
                            timing["first_event_ms"] = now
                        served_model = getattr(chunk, "model", None) or served_model
                        usage = getattr(chunk, "usage", None) or usage
                        for choice in chunk.choices or []:
                            if choice.index != 0:
                                continue
                            delta = choice.delta
                            content = getattr(delta, "content", None) or ""
                            refusal += getattr(delta, "refusal", None) or ""
                            if content and timing["first_content_ms"] is None:
                                timing["first_content_ms"] = now
                            text += content
                            finish = choice.finish_reason or finish
                finally:
                    await stream.close()
        except asyncio.CancelledError:
            response = LLMResponse(data={}, error="cancelled", model=served_model or self.model,
                                   provider=self.provider_name, attempt_id=attempt_id, finish_reason=finish,
                                   duration_ms=(time.perf_counter() - started) * 1000, response_chars=len(text),
                                   effective_parameters=dict(effective), transport_success=False,
                                   json_valid=False, **timing, **_usage_fields(usage))
            self.last_attempt = response
            await record_attempt(response, schema_name=schema_name, cancelled=True)
            raise
        except _MissingCredential:
            return await failure("openai request failed (MissingCredential; client)",
                                 code="generation_unavailable", retryable=False)
        except TimeoutError:
            return await failure("openai request failed (TimeoutError; deadline)", code="generation_failed",
                                 retryable=True, usage=usage, chars=len(text))
        except openai.APIStatusError as error:
            category, code, retryable, retry_after = _status_failure(error)
            # An HTTP error before any stream event is a rejected request: nothing
            # was generated or billed. A mid-stream error keeps usage unknown.
            rejected = None if timing["first_event_ms"] is not None else SimpleNamespace(
                prompt_tokens=0, completion_tokens=0)
            return await failure(f"openai request failed ({category}; {error.status_code})", code=code,
                                 usage=rejected, retryable=retryable, retry_after=retry_after)
        except openai.APIConnectionError as error:  # includes APITimeoutError
            return await failure(f"openai request failed ({type(error).__name__}; connection)",
                                 code="generation_failed", retryable=True, usage=usage, chars=len(text))
        except openai.APIError as error:  # e.g. an error event mid-stream
            return await failure(f"openai request failed ({type(error).__name__}; stream)",
                                 code="generation_failed", retryable=True, usage=usage, chars=len(text))
        except openai.OpenAIError as error:
            return await failure(f"openai request failed ({type(error).__name__}; client)", retryable=False)
        except Exception as error:
            # The SDK re-raises transport faults (e.g. RemoteProtocolError) from
            # stream iteration unwrapped. Keep only the category: upstream text
            # can echo headers or user content.
            return await failure(f"openai request failed ({type(error).__name__}; stream)",
                                 code="generation_failed", usage=usage, chars=len(text))

        tokens = _usage_fields(usage)
        common = dict(model=served_model or self.model, provider=self.provider_name, finish_reason=finish,
                      response_chars=len(text), raw_response=text, attempt_id=attempt_id,
                      duration_ms=(time.perf_counter() - started) * 1000,
                      effective_parameters={**effective, "openai_finish_reason": finish, "refused": bool(refusal)},
                      **timing, **tokens)
        error, retryable, error_code, data = None, None, None, {}
        if refusal:
            error, retryable = f"openai refusal; served by {common['model']}", False
        elif finish is None:
            error, retryable = "openai request failed (IncompleteStreamError; finish=missing)", True
            error_code = "generation_failed"
        elif finish == "length":
            error = "openai request failed (ValueError; finish=length)"
        elif finish != "stop":
            error, retryable = f"openai request failed (ValueError; finish={finish})", False
        else:
            try:
                if not text.strip():
                    raise JSONProtocolError("Empty JSON document")
                data = _complete_json_object(text)
                if mode == "native":
                    data = drop_added_nulls(data, strict, optional_keys)
                data = _unwrap_schema_answer(data, output_model)
            # A malformed document is the caller's bounded correction, not a transport retry.
            except JSONProtocolError as exc:
                error = f"openai request failed (JSONProtocolError; {exc})"
                common["effective_parameters"]["json_protocol_error"] = json_protocol_category(exc)
            except (json.JSONDecodeError, RecursionError) as exc:
                error = f"openai request failed (JSONDecodeError; {exc})"
                common["effective_parameters"]["json_protocol_error"] = json_protocol_category(exc)
        response = LLMResponse(data=data if error is None else {}, error=error, error_code=error_code,
                               retryable=retryable, transport_success=finish in {"stop", "length"} and not refusal,
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
                logger.warning("openai stream could not connect (%s); retrying once before any text", operation)

    async def _stream_text_attempt(self, system_prompt, user_prompt, *, operation, attempt):
        from app.services.llm.admission import provider_permit
        from app.services.llm.telemetry import record_stream_usage

        started = time.perf_counter()
        usage, finish, served_model = None, None, None
        chars = 0
        success = False
        try:
            sdk = self._sdk()
            params = dict(model=self.model, messages=[{"role": "system", "content": system_prompt},
                                                      {"role": "user", "content": user_prompt}],
                          reasoning_effort=self.effort,
                          max_completion_tokens=self.max_tokens + self.reasoning_reserve,
                          stream=True, stream_options={"include_usage": True}, store=False)
            async with provider_permit(self.provider_name, self.model, timeout=self.timeout), \
                    asyncio.timeout(self.timeout):
                stream = await sdk.chat.completions.create(**params)
                try:
                    async for chunk in stream:
                        served_model = getattr(chunk, "model", None) or served_model
                        usage = getattr(chunk, "usage", None) or usage
                        for choice in chunk.choices or []:
                            if choice.index != 0:
                                continue
                            finish = choice.finish_reason or finish
                            content = getattr(choice.delta, "content", None) or ""
                            if content:
                                chars += len(content)
                                yield content
                finally:
                    await stream.close()
            if finish != "stop" or not chars:
                raise ProviderStreamError(self.provider_name, f"finish={finish}", code="generation_failed",
                                          retryable=finish is None)
            success = True
        except ProviderStreamError:
            raise
        except Exception as exc:
            raise _stream_error(exc, chars) from None
        finally:
            await record_stream_usage(operation=operation, provider=self.provider_name,
                                       model=served_model or self.model, usage=_usage_fields(usage),
                                       started=started, success=success, finish=finish, chars=chars,
                                       attempt=attempt)


def _stream_error(exc, chars):
    if isinstance(exc, _MissingCredential):
        return ProviderStreamError("openai", "MissingCredential", code="generation_unavailable", retryable=False)
    if isinstance(exc, openai.APIStatusError):
        category, code, retryable, retry_after = _status_failure(exc)
        return ProviderStreamError("openai", category, code=code or "generation_failed", retryable=retryable,
                                   retry_after_seconds=retry_after)
    if isinstance(exc, (openai.APIConnectionError, TimeoutError)):
        return ProviderStreamError("openai", type(exc).__name__, code="generation_failed", retryable=True,
                                   connect_phase=chars == 0 and connect_phase_failure(exc))
    return ProviderStreamError("openai", type(exc).__name__, code="generation_failed",
                               retryable=isinstance(exc, openai.APIError))


def _usage_fields(usage):
    if usage is None:
        return {}
    prompt = getattr(usage, "prompt_tokens", None) or 0
    output = getattr(usage, "completion_tokens", None)
    if output is None:
        return {"prompt_tokens": prompt}
    details = getattr(usage, "prompt_tokens_details", None)
    return {"prompt_tokens": prompt, "completion_tokens": output, "total_tokens": prompt + output,
            "cached_prompt_tokens": getattr(details, "cached_tokens", None),
            "thoughts_tokens": reported_reasoning_tokens(usage)}
