"""Provider-neutral JSON parsing and failure vocabulary for the direct clients.

The Anthropic and OpenAI clients label every sanitized failure
``"<provider> request failed (<Category>; <detail>)"`` with one shared category
set (``APIConnectionError``, ``APITimeoutError``, ``RateLimitError``,
``InternalServerError``, ``JSONDecodeError``, ``JSONProtocolError``,
``IncompleteStreamError``, ...), so pipeline retries stay provider-neutral.
Upstream exception text is never kept: it can echo headers or user content.
"""

import json
import math
import re

from pydantic import BaseModel, ValidationError

DIRECT_PROVIDERS = ("anthropic", "openai")

# The prompt-JSON contract: the schema is appended to the system prompt.
PROMPT_SCHEMA_SUFFIX = ("\nReturn one JSON object matching this schema. Use its properties "
                        "as the top-level keys; do not wrap or quote the object in an answer field:\n")


class IncompleteStreamError(ValueError):
    """The stream closed without any finish reason: a transport fault, not a model answer."""


_INCOMPLETE_STREAM = re.compile(r"(?:anthropic|openai) request failed \(IncompleteStreamError; finish=missing\)")


def incomplete_stream_error(error: str | None) -> bool:
    return bool(error) and _INCOMPLETE_STREAM.fullmatch(error) is not None


def provider_request_failed(error: str | None, categories) -> bool:
    """True when a direct client reported one of ``categories``."""
    text = str(error or "")
    return any(text.startswith(f"{provider} request failed ({category};")
               for provider in DIRECT_PROVIDERS for category in categories)


def status_category(status: int | None, fallback: str) -> str:
    """One category per HTTP status family, whatever the SDK names its classes."""
    if status == 429:
        return "RateLimitError"
    if status == 408:
        return "APITimeoutError"
    if isinstance(status, int) and status >= 500:
        return "InternalServerError"
    return fallback


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
            # A repeated key with the identical value is lossless framing (Haiku
            # repeated "minutes_min": 1 in 12 of 12 captured cases); conflicting
            # values stay ambiguous and are rejected.
            if key in result and (result[key] != value or type(result[key]) is not type(value)):
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


def json_protocol_category(exc: Exception) -> str:
    """A content-free category of a rejected document, for bounded corrections.

    Assigned from fixed parser messages only; never the key names or the text.
    """
    if isinstance(exc, JSONProtocolError):
        return {
            "Duplicate JSON property": "duplicate_property",
            "Non-finite JSON number": "non_finite_number",
            "Expected a JSON object": "non_object_document",
            "Empty JSON document": "empty_document",
        }.get(str(exc), "invalid_json_document")
    return "invalid_json_syntax"


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


def connect_phase_failure(error: BaseException) -> bool:
    """True only when the connection itself failed, so no request was sent.

    The SDKs wrap transport errors as ``APIConnectionError`` /
    ``APITimeoutError`` raised ``from`` the httpx (OpenAI) or httpx2 (Anthropic)
    error, so the cause chain decides. A read timeout or a dropped stream is
    never a connect failure.
    """
    seen: set[int] = set()
    current: BaseException | None = error
    while current is not None and id(current) not in seen:
        if (type(current).__name__ in {"ConnectError", "ConnectTimeout"}
                and type(current).__module__.split(".")[0] in {"httpx", "httpx2"}):
            return True
        seen.add(id(current))
        current = current.__cause__
    return False


class ProviderStreamError(RuntimeError):
    """Sanitized text-stream failure for deliberate, operation-specific recovery.

    ``code`` is generation_unavailable (credential or credit), generation_rate_limited
    or generation_failed. ``connect_phase`` marks a connect failure before any
    text: nothing was sent, so one transport retry is safe.
    """

    def __init__(self, provider: str, category: str, *, code: str, retryable: bool,
                 retry_after_seconds: int | None = None, connect_phase: bool = False):
        self.provider = provider
        self.code = code
        self.retryable = retryable
        self.retry_after_seconds = retry_after_seconds
        self.connect_phase = connect_phase
        super().__init__(f"{provider} stream failed ({category}; {code})")


# Codes for a call the provider could not serve at all, so the backup model may
# take over. Content, schema and refusal failures never switch models.
UNAVAILABLE_CODES = frozenset({"generation_unavailable", "generation_rate_limited", "generation_failed"})


def provider_unavailable(response) -> bool:
    """True when a call failed because its provider was unavailable."""
    if not getattr(response, "error", None):
        return False
    if getattr(response, "error_code", None) in UNAVAILABLE_CODES:
        return True
    return incomplete_stream_error(response.error) or provider_request_failed(response.error, (
        "APIConnectionError", "APITimeoutError", "TimeoutError", "RateLimitError", "InternalServerError",
        "MissingCredential"))
