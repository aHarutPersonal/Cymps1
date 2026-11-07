"""
LLM client abstraction for structured JSON generation.

Provides the abstract interface, a DummyLLMClient for development that returns
deterministic fixtures, the backup wrapper, and the routed client factory. The
direct provider clients live in ``anthropic_direct.py`` and ``openai_direct.py``.
"""

import asyncio
import json
import logging
import time
from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from contextlib import aclosing
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field, ValidationError

logger = logging.getLogger(__name__)

# Path to fixtures directory (relative to backend root)
FIXTURES_DIR = Path(__file__).parent.parent.parent.parent / "fixtures"


async def _retry_async(fn, attempts=3, base_delay=0.5):
    """Retry an async callable with exponential backoff. Re-raises the last
    exception after `attempts` tries."""
    last_exc = None
    for attempt in range(attempts):
        try:
            return await fn()
        except Exception as exc:
            last_exc = exc
            if attempt == attempts - 1:
                break
            delay = base_delay * (2**attempt)
            if delay > 0:
                await asyncio.sleep(delay)
    raise last_exc


def _repair_json(raw: str) -> dict | None:
    """
    Attempt to repair malformed JSON from LLM output.

    Handles common model failure modes:
    - Markdown code fences (```json ... ```)
    - Trailing commas before } or ]
    - Invalid backslash escape sequences
    - Unterminated strings at EOF
    - Missing closing braces/brackets
    """
    import re

    text = raw.strip()

    # 1. Strip markdown code fences
    if text.startswith("```"):
        lines = text.split("\n")
        # Remove first line (```json) and last line (```)
        if lines[-1].strip() == "```":
            lines = lines[1:-1]
        else:
            lines = lines[1:]
        text = "\n".join(lines).strip()

    # 2. Fix invalid backslash escapes (e.g. \n in a string that should be \\n,
    #    or bare backslashes before non-escape characters)
    #    Valid JSON escapes: \", \\, \/, \b, \f, \n, \r, \t, \uXXXX
    text = re.sub(
        r'\\(?!["\\bfnrtu/])',
        r"\\\\",
        text,
    )

    # 3. Remove trailing commas before } or ]
    text = re.sub(r",\s*([}\]])", r"\1", text)

    # 3b. Insert missing commas between adjacent values
    #     Handles: } { → }, {   and  } "key" → }, "key"
    #     and: "value" "key" → "value", "key"  (number/bool/null before ")
    text = re.sub(r"(\})\s*(\{)", r"\1, \2", text)
    text = re.sub(r'(\})\s*(")', r"\1, \2", text)
    text = re.sub(r'("])\s*(")', r"\1, \2", text)
    text = re.sub(r'(true|false|null|\d+)\s*\n\s*(")', r"\1,\n\2", text)

    # 4. Try parsing
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # 5. Fix unterminated strings: find last valid content, close open strings
    #    and add missing closing braces
    try:
        # Count open/close braces and brackets
        open_braces = text.count("{")
        close_braces = text.count("}")
        open_brackets = text.count("[")
        close_brackets = text.count("]")

        # If we're inside an unclosed string, close it
        # Simple heuristic: count unescaped quotes
        in_string = False
        i = 0
        while i < len(text):
            c = text[i]
            if c == "\\" and in_string:
                i += 2
                continue
            if c == '"':
                in_string = not in_string
            i += 1

        repair = text
        if in_string:
            repair += '"'

        # Add missing closing brackets/braces
        repair += "]" * max(0, open_brackets - close_brackets)
        repair += "}" * max(0, open_braces - close_braces)

        return json.loads(repair)
    except json.JSONDecodeError:
        pass

    # 6. Last resort: truncate to last valid closing brace and try
    try:
        last_brace = text.rfind("}")
        if last_brace > 0:
            truncated = text[: last_brace + 1]
            return json.loads(truncated)
    except json.JSONDecodeError:
        pass

    return None


class LLMResponse(BaseModel):
    """Response from an LLM call."""

    data: dict[str, Any]
    raw_response: str | None = None
    retried: bool = False
    error: str | None = None
    error_code: str | None = None
    # Sanitized transport policy only. None leaves malformed/unfinished output
    # recovery to the operation's schema and content contract.
    retryable: bool | None = None
    retry_after_seconds: int | None = Field(default=None, ge=1, le=3600)
    model: str | None = None
    prompt_tokens: int | None = None
    completion_tokens: int | None = None
    total_tokens: int | None = None
    thoughts_tokens: int | None = None
    duration_ms: float | None = None
    first_event_ms: float | None = None
    first_content_ms: float | None = None
    response_chars: int | None = None
    admission_wait_ms: float | None = None
    cached_prompt_tokens: int | None = None
    effective_parameters: dict[str, Any] = Field(default_factory=dict)
    transport_success: bool | None = None
    json_valid: bool | None = None
    semantic_accepted: bool | None = None
    critical_defect: bool = False
    trace_id: str | None = None
    attempt_id: str | None = None
    trace_recorded: bool = False
    finish_reason: str | None = None
    provider: str | None = None
    fallback_from_model: str | None = None
    fallback_from_provider: str | None = None
    fallback_error: str | None = None


class BaseLLMClient(ABC):
    """Abstract base class for LLM clients."""

    @abstractmethod
    async def generate_json(
        self,
        system_prompt: str,
        user_prompt: str,
        json_schema: dict[str, Any] | None = None,
        output_model: type[BaseModel] | None = None,
    ) -> LLMResponse:
        """
        Generate structured JSON from prompts.

        Args:
            system_prompt: System message setting up the LLM behavior
            user_prompt: User message with the actual request
            json_schema: Optional JSON schema for validation
            output_model: Optional Pydantic model for validation

        Returns:
            LLMResponse with parsed data or error
        """
        pass

    async def generate_and_validate(
        self,
        system_prompt: str,
        user_prompt: str,
        output_model: type[BaseModel],
        repair_on_failure: bool = True,
    ) -> tuple[BaseModel | None, LLMResponse]:
        """
        Generate JSON and validate against a Pydantic model.

        If validation fails and repair_on_failure is True, retries once
        with a repair prompt.

        Args:
            system_prompt: System message
            user_prompt: User message
            output_model: Pydantic model to validate against
            repair_on_failure: Whether to retry with repair prompt on validation failure

        Returns:
            Tuple of (validated model or None, LLMResponse)
        """
        response = await self.generate_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            output_model=output_model,
        )

        if response.error:
            return None, response

        # Try to validate
        try:
            validated = output_model.model_validate(response.data)
            return validated, response
        except ValidationError as e:
            if not repair_on_failure:
                response.error = f"Validation failed: {e}"
                return None, response

            # Retry with repair prompt
            repair_prompt = self._build_repair_prompt(
                original_prompt=user_prompt,
                invalid_json=json.dumps(response.data, indent=2),
                validation_error=str(e),
                schema=output_model.model_json_schema(),
            )

            repair_response = await self.generate_json(
                system_prompt=system_prompt,
                user_prompt=repair_prompt,
                output_model=output_model,
            )
            repair_response.retried = True
            repair_response.prompt_tokens = int(response.prompt_tokens or 0) + int(
                repair_response.prompt_tokens or 0
            )
            repair_response.completion_tokens = int(
                response.completion_tokens or 0
            ) + int(repair_response.completion_tokens or 0)
            repair_response.total_tokens = int(response.total_tokens or 0) + int(
                repair_response.total_tokens or 0
            )
            repair_response.duration_ms = float(response.duration_ms or 0.0) + float(
                repair_response.duration_ms or 0.0
            )
            repair_response.model = repair_response.model or response.model

            if repair_response.error:
                return None, repair_response

            try:
                validated = output_model.model_validate(repair_response.data)
                return validated, repair_response
            except ValidationError as e2:
                repair_response.error = f"Validation failed after repair: {e2}"
                return None, repair_response

    def _build_repair_prompt(
        self,
        original_prompt: str,
        invalid_json: str,
        validation_error: str,
        schema: dict[str, Any],
    ) -> str:
        """Build a prompt to repair invalid JSON."""
        return f"""The previous response had validation errors. Please fix the JSON to match the schema.

ORIGINAL REQUEST:
{original_prompt}

INVALID JSON:
{invalid_json}

VALIDATION ERROR:
{validation_error}

REQUIRED SCHEMA:
{json.dumps(schema, indent=2)}

Please output ONLY the corrected JSON that matches the schema exactly."""


class DummyLLMClient(BaseLLMClient):
    """
    Dummy LLM client for development.

    Returns deterministic fixtures from the /fixtures directory.
    Fixture files are named: {extraction_type}.json
    """

    def __init__(self, fixtures_dir: Path | None = None):
        self.fixtures_dir = fixtures_dir or FIXTURES_DIR

    async def generate_json(
        self,
        system_prompt: str,
        user_prompt: str,
        json_schema: dict[str, Any] | None = None,
        output_model: type[BaseModel] | None = None,
    ) -> LLMResponse:
        """
        Return fixture data based on prompt content.

        Determines fixture type by looking for keywords in the user_prompt.
        """
        fixture_type = self._determine_fixture_type(user_prompt)
        fixture_path = self.fixtures_dir / f"{fixture_type}.json"

        if not fixture_path.exists():
            logger.warning(f"Fixture not found: {fixture_path}, using empty response")
            return LLMResponse(
                data={},
                error=f"Fixture not found: {fixture_type}.json",
                provider="dummy",
            )

        try:
            with open(fixture_path) as f:
                data = json.load(f)

            return LLMResponse(
                data=data,
                raw_response=json.dumps(data),
                provider="dummy",
            )
        except json.JSONDecodeError as e:
            return LLMResponse(
                data={},
                error=f"Invalid JSON in fixture {fixture_type}.json: {e}",
                provider="dummy",
            )

    def _determine_fixture_type(self, user_prompt: str) -> str:
        """Determine which fixture to use based on prompt content."""
        prompt_lower = user_prompt.lower()

        if "canonical profile" in prompt_lower or "profile_extract" in prompt_lower:
            return "profile_extract"
        elif "achievements" in prompt_lower or "milestones" in prompt_lower:
            if "normalize" in prompt_lower or "deduplicate" in prompt_lower:
                return "timeline_normalize"
            elif "target_age" in prompt_lower or "age=" in prompt_lower:
                return "milestones_by_age"
            return "achievements_extract"
        elif "timeline" in prompt_lower:
            return "timeline_normalize"
        elif "persona" in prompt_lower or "chat persona" in prompt_lower:
            return "persona_pack"
        elif "plan" in prompt_lower or "12-week" in prompt_lower:
            return "plan_generate"

        # Default to profile
        return "profile_extract"

    async def stream_text(self, system_prompt: str, user_prompt: str, *, operation: str) -> AsyncIterator[str]:
        """A fixed reply, so interactive streams work offline."""
        yield f"[dummy {operation} reply]"


class FallbackLLMClient(BaseLLMClient):
    """Retry a call on the backup provider when the primary cannot serve it.

    Only unavailability (provider error, rate limit, out of credit, missing
    credential) switches providers. A content, schema or refusal failure is
    the operation's own answer and returns to its caller unchanged.
    """

    # An outage should cost a worker one timeout, not one timeout per prompt.
    # The breaker is deliberately process-local: it avoids adding a Redis
    # dependency to every LLM call while still protecting each web or worker
    # process from repeatedly waiting on the same unhealthy endpoint.
    _circuit_open_until: dict[tuple[str, str], float] = {}
    _circuit_last_error: dict[tuple[str, str], str] = {}
    _circuit_cooldown_seconds = 300.0
    # A rate limit is not an outage: it usually clears in seconds, so holding
    # the circuit open for the full outage cooldown would turn a momentary
    # limit into minutes of backup traffic.
    _rate_limit_cooldown_seconds = 20.0

    def __init__(self, primary: BaseLLMClient, fallback: BaseLLMClient):
        self.primary = primary
        self.fallback = fallback
        self.model = getattr(primary, "model", None)
        self.provider_name = getattr(primary, "provider_name", None)

    def __getattr__(self, name):
        # Callers read client options (max_tokens, timeout, thinking_level, ...).
        return getattr(self.primary, name)

    def _primary_circuit_key(self) -> tuple[str, str]:
        return (
            str(
                getattr(self.primary, "provider_name", None)
                or self.primary.__class__.__name__
            ),
            str(getattr(self.primary, "model", None) or "default"),
        )

    @staticmethod
    def _is_rate_limit_failure(response: LLMResponse) -> bool:
        """Throttling that the provider itself says will clear shortly."""
        if response.error_code == "generation_rate_limited":
            return True
        normalized = str(response.error or "").casefold()
        return any(marker in normalized for marker in ("rate limit", "ratelimiterror", "http 429"))

    @staticmethod
    def _is_operational_failure(error: str | None) -> bool:
        """Legacy text markers of an unavailable provider (timeouts, 5xx, quota)."""
        if not error:
            return False
        normalized = error.casefold()
        return any(
            marker in normalized
            for marker in (
                "timeout",
                "timed out",
                "gateway",
                "unavailable",
                "connection",
                "connect error",
                "transport",
                "network",
                "rate limit",
                "overloaded",
                "http 429",
                "status 429",
                "http 500",
                "http 502",
                "http 503",
                "http 504",
                "insufficient_quota",
                "quota exceeded",
            )
        )

    @classmethod
    def unavailable(cls, response: LLMResponse) -> bool:
        from app.services.llm.protocol import provider_unavailable

        return provider_unavailable(response) or cls._is_operational_failure(response.error)

    @classmethod
    def reset_circuits_for_tests(cls) -> None:
        """Clear process-local health state between isolated unit tests."""
        cls._circuit_open_until.clear()
        cls._circuit_last_error.clear()

    async def generate_json(
        self,
        system_prompt: str,
        user_prompt: str,
        json_schema: dict[str, Any] | None = None,
        output_model: type[BaseModel] | None = None,
    ) -> LLMResponse:
        circuit_key = self._primary_circuit_key()
        now = time.monotonic()
        open_until = self._circuit_open_until.get(circuit_key, 0.0)
        if open_until > now:
            remaining = max(1, round(open_until - now))
            last_error = self._circuit_last_error.get(
                circuit_key, "operational failure"
            )
            primary_response = LLMResponse(
                data={},
                error=(
                    f"Primary provider circuit open for {remaining}s after: "
                    f"{last_error}"
                ),
                error_code="generation_unavailable",
                model=getattr(self.primary, "model", None),
                provider=getattr(self.primary, "provider_name", None),
            )
            logger.warning(
                "[LLM] Skipping unhealthy primary provider=%s model=%s for %ss",
                circuit_key[0],
                circuit_key[1],
                remaining,
            )
        else:
            try:
                primary_response = await self.primary.generate_json(
                    system_prompt=system_prompt,
                    user_prompt=user_prompt,
                    json_schema=json_schema,
                    output_model=output_model,
                )
            except Exception as exc:
                logger.exception(
                    "[LLM] Primary provider raised before returning a response"
                )
                primary_response = LLMResponse(
                    data={},
                    error=f"Primary provider error: {type(exc).__name__}",
                    error_code="generation_failed",
                    model=getattr(self.primary, "model", None),
                    provider=getattr(self.primary, "provider_name", None),
                )
            if self.unavailable(primary_response):
                cooldown = (
                    self._rate_limit_cooldown_seconds
                    if self._is_rate_limit_failure(primary_response)
                    else self._circuit_cooldown_seconds
                )
                self._circuit_open_until[circuit_key] = time.monotonic() + cooldown
                self._circuit_last_error[circuit_key] = str(primary_response.error)
            elif not primary_response.error:
                self._circuit_open_until.pop(circuit_key, None)
                self._circuit_last_error.pop(circuit_key, None)
        if not primary_response.error or not self.unavailable(primary_response):
            self.last_attempt = primary_response
            return primary_response

        logger.warning(
            "[LLM] Primary provider unavailable for model=%s; using model=%s: %s",
            getattr(self.primary, "model", "unknown"),
            getattr(self.fallback, "model", "unknown"),
            primary_response.error,
        )
        try:
            fallback_response = await self.fallback.generate_json(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                json_schema=json_schema,
                output_model=output_model,
            )
        except Exception as exc:
            logger.exception(
                "[LLM] Fallback provider raised before returning a response"
            )
            fallback_response = LLMResponse(
                data={},
                error=f"Fallback provider error: {type(exc).__name__}",
                error_code="generation_failed",
                model=getattr(self.fallback, "model", None),
                provider=getattr(self.fallback, "provider_name", None),
            )
        fallback_response.provider = fallback_response.provider or getattr(
            self.fallback, "provider_name", None
        )
        fallback_response.retried = True
        fallback_response.fallback_from_model = primary_response.model or getattr(
            self.primary, "model", None
        )
        fallback_response.fallback_from_provider = primary_response.provider or getattr(
            self.primary, "provider_name", None
        )
        fallback_response.fallback_error = primary_response.error
        fallback_response.duration_ms = float(
            primary_response.duration_ms or 0.0
        ) + float(fallback_response.duration_ms or 0.0)
        self.last_attempt = fallback_response
        return fallback_response


def provider_configured(provider: str) -> bool:
    from app.core.config import settings

    return bool(settings.anthropic_api_key if provider == "anthropic" else settings.openai_api_key)


def provider_model(provider: str) -> str:
    """The one model a direct provider serves for every tier."""
    from app.core.config import settings

    return settings.anthropic_model if provider == "anthropic" else settings.openai_model


def direct_client(
    provider: str,
    *,
    timeout: float,
    max_tokens: int | None,
    thinking_level: str,
) -> BaseLLMClient:
    """One single-provider client for ``provider`` ("anthropic" or "openai")."""
    if provider == "anthropic":
        from app.services.llm.anthropic_direct import AnthropicDirectLLMClient

        return AnthropicDirectLLMClient(timeout=timeout, max_tokens=max_tokens, thinking_level=thinking_level)
    if provider == "openai":
        from app.services.llm.openai_direct import OpenAIDirectLLMClient

        return OpenAIDirectLLMClient(timeout=timeout, max_tokens=max_tokens, thinking_level=thinking_level)
    raise ValueError(f"Unknown LLM provider: {provider}")


def get_llm_client(
    timeout: float = 60.0,
    max_tokens: int | None = None,
    fast: bool = False,
    tier: str | None = None,
    thinking_level: str | None = None,
    temperature: float = 0.1,
    allow_fallback: bool = True,
    operation: str | None = None,
    provider: str | None = None,
) -> BaseLLMClient:
    """
    The configured client for ``operation`` (see ``app/services/llm/routes.py``).

    LLM_PROVIDER=dummy returns fixtures; ``routed`` sends the operation to its
    primary provider with the other provider as backup.

    Args:
        timeout: Request timeout in seconds (default: 60s)
        max_tokens: Visible output budget; the reasoning reserve is added on top.
        fast: Backward-compatible alias for ``tier="fast"``
        tier: ``fast``/``balanced`` reason at low effort, ``quality`` at high,
            unless ``thinking_level`` says otherwise. One model serves every tier.
        thinking_level: Reasoning effort (low, medium or high).
        temperature: Ignored: the direct reasoning models reject sampling parameters.
        allow_fallback: Whether an unavailable primary may retry on the backup.
            Disable where the caller owns its recovery (see ``recovery.py``).
        operation: The usage-telemetry operation; selects the route.
        provider: Force one provider with no backup (a tutorial attempt).
    """
    from app.core.config import settings
    from app.services.llm.routes import route_for

    resolved_tier = tier or ("fast" if fast else "balanced")
    if resolved_tier not in {"fast", "balanced", "quality"}:
        raise ValueError(f"Unknown LLM tier: {resolved_tier}")
    if settings.llm_provider == "dummy":
        return DummyLLMClient()

    level = thinking_level or ("high" if resolved_tier == "quality" else "low")
    primary, backup = (provider, None) if provider else route_for(operation)
    options = {"timeout": timeout, "max_tokens": max_tokens, "thinking_level": level}
    if not provider_configured(primary) and backup and provider_configured(backup):
        logger.warning("[LLM] %s key not set; %s serves operation=%s", primary, backup, operation)
        return direct_client(backup, **options)
    client = direct_client(primary, **options)
    if allow_fallback and backup and provider_configured(backup):
        return FallbackLLMClient(client, direct_client(backup, **options))
    # A missing credential stays a recorded generation_unavailable failure:
    # never silently serve fixtures in production.
    return client


async def stream_routed_text(
    system_prompt: str,
    user_prompt: str,
    *,
    operation: str,
    max_tokens: int | None,
    thinking_level: str = "low",
    primary_timeout: float = 60.0,
    backup_timeout: float = 60.0,
) -> AsyncIterator[str]:
    """Stream visible text from the operation's primary model.

    The backup takes over only before any text arrived and only when the
    primary was unavailable: switching mid-answer would splice two replies.
    """
    from app.core.config import settings
    from app.services.llm.protocol import ProviderStreamError
    from app.services.llm.routes import route_for

    if settings.llm_provider == "dummy":
        async with aclosing(DummyLLMClient().stream_text(system_prompt, user_prompt, operation=operation)) as pieces:
            async for piece in pieces:
                yield piece
        return
    primary, backup = route_for(operation)
    providers = [name for name in (primary, backup) if provider_configured(name)] or [primary]
    for index, provider in enumerate(providers):
        client = direct_client(provider, timeout=primary_timeout if index == 0 else backup_timeout,
                               max_tokens=max_tokens, thinking_level=thinking_level)
        received_text = False
        try:
            async with aclosing(client.stream_text(system_prompt, user_prompt, operation=operation)) as pieces:
                async for piece in pieces:
                    received_text = received_text or bool(piece)
                    yield piece
            return
        except ProviderStreamError as exc:
            unavailable = exc.retryable or exc.code in {"generation_unavailable", "generation_rate_limited"}
            if index + 1 == len(providers) or received_text or not unavailable:
                raise
            logger.warning("[LLM] %s stream unavailable before text (%s); %s takes over",
                           provider, operation, providers[index + 1])
