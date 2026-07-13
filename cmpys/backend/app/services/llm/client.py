"""
LLM client abstraction for structured JSON generation.

Provides an abstract interface and a DummyLLMClient for development
that returns deterministic fixtures.
"""
import asyncio
import json
import logging
from abc import ABC, abstractmethod
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import TYPE_CHECKING, Any

from pydantic import BaseModel, ValidationError

if TYPE_CHECKING:
    import openai

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
            delay = base_delay * (2 ** attempt)
            if delay > 0:
                await asyncio.sleep(delay)
    raise last_exc


def _repair_json(raw: str) -> dict | None:
    """
    Attempt to repair malformed JSON from LLM output.

    Handles common Gemini failure modes:
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
        r'\\\\',
        text,
    )

    # 3. Remove trailing commas before } or ]
    text = re.sub(r',\s*([}\]])', r'\1', text)

    # 3b. Insert missing commas between adjacent values
    #     Handles: } { → }, {   and  } "key" → }, "key"
    #     and: "value" "key" → "value", "key"  (number/bool/null before ")
    text = re.sub(r'(\})\s*(\{)', r'\1, \2', text)
    text = re.sub(r'(\})\s*(")', r'\1, \2', text)
    text = re.sub(r'("])\s*(")', r'\1, \2', text)
    text = re.sub(r'(true|false|null|\d+)\s*\n\s*(")', r'\1,\n\2', text)

    # 4. Try parsing
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # 5. Fix unterminated strings: find last valid content, close open strings
    #    and add missing closing braces
    try:
        # Count open/close braces and brackets
        open_braces = text.count('{')
        close_braces = text.count('}')
        open_brackets = text.count('[')
        close_brackets = text.count(']')

        # If we're inside an unclosed string, close it
        # Simple heuristic: count unescaped quotes
        in_string = False
        i = 0
        while i < len(text):
            c = text[i]
            if c == '\\' and in_string:
                i += 2
                continue
            if c == '"':
                in_string = not in_string
            i += 1

        repair = text
        if in_string:
            repair += '"'

        # Add missing closing brackets/braces
        repair += ']' * max(0, open_brackets - close_brackets)
        repair += '}' * max(0, open_braces - close_braces)

        return json.loads(repair)
    except json.JSONDecodeError:
        pass

    # 6. Last resort: truncate to last valid closing brace and try
    try:
        last_brace = text.rfind('}')
        if last_brace > 0:
            truncated = text[:last_brace + 1]
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
    model: str | None = None
    prompt_tokens: int | None = None
    completion_tokens: int | None = None
    total_tokens: int | None = None
    duration_ms: float | None = None


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
            )
        
        try:
            with open(fixture_path) as f:
                data = json.load(f)
            
            return LLMResponse(
                data=data,
                raw_response=json.dumps(data),
            )
        except json.JSONDecodeError as e:
            return LLMResponse(
                data={},
                error=f"Invalid JSON in fixture {fixture_type}.json: {e}",
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


class OpenAILLMClient(BaseLLMClient):
    """
    OpenAI LLM client for production use.
    
    Requires OPENAI_API_KEY environment variable.
    Uses connection pooling and optimized timeout settings.
    """
    
    # Singleton client instance for connection reuse
    _client_instance: "openai.AsyncOpenAI | None" = None
    _client_api_key: str | None = None
    
    def __init__(
        self,
        model: str = "gpt-4o",
        api_key: str | None = None,
        timeout: float = 60.0,
        max_tokens: int | None = None,
    ):
        self.model = model
        self.api_key = api_key
        self.timeout = timeout
        self.max_tokens = max_tokens
    
    def _get_client(self, api_key: str) -> "openai.AsyncOpenAI":
        """Get or create a singleton OpenAI client for connection reuse."""
        import openai
        import httpx
        
        # Reuse client if API key matches
        if OpenAILLMClient._client_instance is not None and OpenAILLMClient._client_api_key == api_key:
            return OpenAILLMClient._client_instance
        
        # Create new client with optimized settings
        OpenAILLMClient._client_instance = openai.AsyncOpenAI(
            api_key=api_key,
            timeout=httpx.Timeout(self.timeout, connect=10.0),
            max_retries=2,
        )
        OpenAILLMClient._client_api_key = api_key
        return OpenAILLMClient._client_instance
    
    async def generate_json(
        self,
        system_prompt: str,
        user_prompt: str,
        json_schema: dict[str, Any] | None = None,
        output_model: type[BaseModel] | None = None,
    ) -> LLMResponse:
        """Generate JSON using OpenAI API with optimized settings."""
        import time
        
        try:
            import openai
        except ImportError:
            logger.error("[LLM] OpenAI package not installed")
            return LLMResponse(
                data={},
                error="openai package not installed. Run: pip install openai",
            )
        
        from app.core.config import settings
        
        api_key = self.api_key or settings.openai_api_key
        if not api_key:
            logger.error("[LLM] OPENAI_API_KEY not configured")
            return LLMResponse(
                data={},
                error="OPENAI_API_KEY not configured",
            )
        
        client = self._get_client(api_key)
        
        # Log request details
        model_name = output_model.__name__ if output_model else "generic"
        prompt_preview = user_prompt[:200].replace("\n", " ")
        logger.info(f"[LLM] Request: model={self.model}, output={model_name}, max_tokens={self.max_tokens}")
        logger.debug(f"[LLM] Prompt preview: {prompt_preview}...")
        
        start_time = time.perf_counter()
        
        try:
            # Build request kwargs
            request_kwargs: dict[str, Any] = {
                "model": self.model,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                "response_format": {"type": "json_object"},
                "temperature": 0.1,
            }
            
            # Add max_tokens if specified (helps speed up response)
            if self.max_tokens:
                request_kwargs["max_tokens"] = self.max_tokens
            
            response = await client.chat.completions.create(**request_kwargs)
            
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            raw_content = response.choices[0].message.content
            if not raw_content:
                logger.warning(f"[LLM] Empty response from OpenAI after {duration_ms:.0f}ms")
                return LLMResponse(
                    data={},
                    error="Empty response from OpenAI",
                )
            
            # Log usage stats
            usage = response.usage
            if usage:
                logger.info(
                    f"[LLM] Response received: {duration_ms:.0f}ms, "
                    f"prompt_tokens={usage.prompt_tokens}, "
                    f"completion_tokens={usage.completion_tokens}, "
                    f"total_tokens={usage.total_tokens}"
                )
            else:
                logger.info(f"[LLM] Response received: {duration_ms:.0f}ms")
            
            try:
                data = json.loads(raw_content)
                logger.debug(f"[LLM] JSON parsed successfully, keys: {list(data.keys()) if isinstance(data, dict) else 'array'}")
                return LLMResponse(
                    data=data,
                    raw_response=raw_content,
                    model=self.model,
                    prompt_tokens=usage.prompt_tokens if usage else None,
                    completion_tokens=usage.completion_tokens if usage else None,
                    total_tokens=usage.total_tokens if usage else None,
                    duration_ms=duration_ms,
                )
            except json.JSONDecodeError as e:
                logger.warning(f"[LLM] Invalid JSON in response: {e}, attempting repair...")
                
                # Attempt repair
                repaired = _repair_json(raw_content)
                if repaired is not None:
                    logger.info("[LLM] JSON repair succeeded (OpenAI)")
                    return LLMResponse(
                        data=repaired,
                        raw_response=raw_content,
                        retried=True,
                        model=self.model,
                        prompt_tokens=usage.prompt_tokens if usage else None,
                        completion_tokens=usage.completion_tokens if usage else None,
                        total_tokens=usage.total_tokens if usage else None,
                        duration_ms=duration_ms,
                    )
                
                logger.error("[LLM] JSON repair failed for OpenAI response")
                logger.debug(f"[LLM] Raw content: {raw_content[:500]}...")
                return LLMResponse(
                    data={},
                    raw_response=raw_content,
                    error=f"Invalid JSON in response: {e}",
                    model=self.model,
                    prompt_tokens=usage.prompt_tokens if usage else None,
                    completion_tokens=usage.completion_tokens if usage else None,
                    total_tokens=usage.total_tokens if usage else None,
                    duration_ms=duration_ms,
                )
                
        except openai.APITimeoutError:
            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.error(f"[LLM] API timeout after {duration_ms:.0f}ms (limit: {self.timeout}s)")
            return LLMResponse(
                data={},
                error=f"OpenAI API timeout after {self.timeout}s",
            )
        except openai.RateLimitError as e:
            logger.error(f"[LLM] Rate limit exceeded: {e}")
            return LLMResponse(
                data={},
                error=f"OpenAI rate limit exceeded: {e}",
            )
        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.exception(f"[LLM] API error after {duration_ms:.0f}ms: {e}")
            return LLMResponse(
                data={},
                error=f"OpenAI API error: {e}",
            )
    
    async def generate_json_streaming(
        self,
        system_prompt: str,
        user_prompt: str,
        output_model: type[BaseModel] | None = None,
        on_chunk: "Callable[[str], Awaitable[None]] | None" = None,
    ) -> LLMResponse:
        """
        Generate JSON using OpenAI API with streaming.
        
        Streams tokens in real-time and calls on_chunk callback with accumulated text.
        This provides a better UX by showing "thinking" as it happens.
        
        Args:
            system_prompt: System message
            user_prompt: User message
            output_model: Optional Pydantic model for validation
            on_chunk: Async callback called with accumulated text after each chunk
        """
        import time
        
        try:
            import openai
        except ImportError:
            logger.error("[LLM] OpenAI package not installed")
            return LLMResponse(
                data={},
                error="openai package not installed. Run: pip install openai",
            )
        
        from app.core.config import settings
        
        api_key = self.api_key or settings.openai_api_key
        if not api_key:
            logger.error("[LLM] OPENAI_API_KEY not configured")
            return LLMResponse(
                data={},
                error="OPENAI_API_KEY not configured",
            )
        
        client = self._get_client(api_key)
        
        model_name = output_model.__name__ if output_model else "generic"
        logger.info(f"[LLM] Streaming request: model={self.model}, output={model_name}")
        
        start_time = time.perf_counter()
        accumulated_text = ""
        chunk_count = 0
        last_callback_len = 0
        
        try:
            request_kwargs: dict[str, Any] = {
                "model": self.model,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                "response_format": {"type": "json_object"},
                "temperature": 0.1,
                "stream": True,
            }
            
            if self.max_tokens:
                request_kwargs["max_tokens"] = self.max_tokens
            
            stream = await client.chat.completions.create(**request_kwargs)
            
            async for chunk in stream:
                chunk_count += 1
                delta = chunk.choices[0].delta
                if delta.content:
                    accumulated_text += delta.content
                    
                    # Call callback every ~200 chars to update UI
                    if on_chunk and len(accumulated_text) - last_callback_len >= 200:
                        try:
                            await on_chunk(accumulated_text)
                            last_callback_len = len(accumulated_text)
                        except Exception as e:
                            logger.warning(f"[LLM] on_chunk callback error: {e}")
            
            # Final callback with complete text
            if on_chunk and len(accumulated_text) > last_callback_len:
                try:
                    await on_chunk(accumulated_text)
                except Exception as e:
                    logger.warning(f"[LLM] Final on_chunk callback error: {e}")
            
            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.info(
                f"[LLM] Streaming complete: {duration_ms:.0f}ms, "
                f"chunks={chunk_count}, chars={len(accumulated_text)}"
            )
            
            if not accumulated_text:
                return LLMResponse(
                    data={},
                    error="Empty streaming response from OpenAI",
                )
            
            try:
                data = json.loads(accumulated_text)
                return LLMResponse(
                    data=data,
                    raw_response=accumulated_text,
                )
            except json.JSONDecodeError as e:
                logger.error(f"[LLM] Invalid JSON in streamed response: {e}")
                return LLMResponse(
                    data={},
                    raw_response=accumulated_text,
                    error=f"Invalid JSON in response: {e}",
                )
                
        except openai.APITimeoutError:
            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.error(f"[LLM] Streaming timeout after {duration_ms:.0f}ms")
            return LLMResponse(
                data={},
                error=f"OpenAI API timeout after {self.timeout}s",
            )
        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.exception(f"[LLM] Streaming error after {duration_ms:.0f}ms: {e}")
            return LLMResponse(
                data={},
                error=f"OpenAI API error: {e}",
            )


class GeminiLLMClient(BaseLLMClient):
    """
    Google Gemini LLM client for production use.
    
    Uses google.genai SDK with JSON output mode.
    """
    
    def __init__(
        self,
        model: str = "gemini-2.5-flash",
        api_key: str | None = None,
        timeout: float = 60.0,
        max_tokens: int | None = None,
        thinking_budget: int | None = None,
        temperature: float = 0.1,
    ):
        self.model = model
        self.api_key = api_key
        self.timeout = timeout
        self.max_tokens = max_tokens
        self.thinking_budget = thinking_budget
        self.temperature = temperature
    
    async def generate_json(
        self,
        system_prompt: str,
        user_prompt: str,
        json_schema: dict[str, Any] | None = None,
        output_model: type[BaseModel] | None = None,
    ) -> LLMResponse:
        """Generate JSON using Google Gemini API."""
        import time
        
        try:
            from google import genai
            from google.genai import types
        except ImportError:
            logger.error("[LLM] google-genai package not installed")
            return LLMResponse(
                data={},
                error="google-genai package not installed. Run: pip install google-genai",
            )
        
        from app.core.config import settings
        
        api_key = self.api_key or settings.gemini_api_key
        if not api_key:
            logger.error("[LLM] GEMINI_API_KEY not configured")
            return LLMResponse(
                data={},
                error="GEMINI_API_KEY not configured",
            )
        
        model_name = output_model.__name__ if output_model else "generic"
        logger.info(f"[LLM] Gemini request: model={self.model}, output={model_name}")
        
        start_time = time.perf_counter()
        
        try:
            # Reuse the shared warm client (avoids a TCP+TLS handshake per
            # call) and enforce the configured timeout — previously stored
            # but never applied, so user-facing paths could hang unbounded.
            from app.services.gemini import _gemini_client
            client = _gemini_client() if api_key == settings.gemini_api_key else genai.Client(api_key=api_key)

            # Build config
            config_kwargs: dict[str, Any] = {
                "temperature": self.temperature,
                "response_mime_type": "application/json",
                "http_options": types.HttpOptions(timeout=int(self.timeout * 1000)),
            }
            if self.max_tokens:
                config_kwargs["max_output_tokens"] = self.max_tokens
            if output_model is not None:
                # Native schema-constrained decoding prevents most malformed
                # JSON responses and avoids an otherwise expensive repair call.
                config_kwargs["response_schema"] = output_model
            elif json_schema is not None:
                config_kwargs["response_json_schema"] = json_schema
            if self.thinking_budget is not None:
                config_kwargs["thinking_config"] = types.ThinkingConfig(
                    thinking_budget=self.thinking_budget,
                )
            
            config = types.GenerateContentConfig(
                system_instruction=system_prompt,
                **config_kwargs,
            )
            
            response = await client.aio.models.generate_content(
                model=self.model,
                contents=user_prompt,
                config=config,
            )
            
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            raw_content = response.text
            if not raw_content:
                logger.warning(f"[LLM] Empty response from Gemini after {duration_ms:.0f}ms")
                return LLMResponse(
                    data={},
                    error="Empty response from Gemini",
                )

            finish_reason = "unknown"
            if getattr(response, "candidates", None):
                reason = getattr(response.candidates[0], "finish_reason", None)
                finish_reason = getattr(reason, "name", None) or str(reason)
            
            # Log usage
            if response.usage_metadata:
                logger.info(
                    f"[LLM] Gemini response: {duration_ms:.0f}ms, "
                    f"prompt_tokens={response.usage_metadata.prompt_token_count}, "
                    f"completion_tokens={response.usage_metadata.candidates_token_count}, "
                    f"finish_reason={finish_reason}"
                )
            else:
                logger.info(
                    f"[LLM] Gemini response: {duration_ms:.0f}ms, "
                    f"finish_reason={finish_reason}"
                )
            
            try:
                data = json.loads(raw_content)
                logger.debug(f"[LLM] JSON parsed, keys: {list(data.keys()) if isinstance(data, dict) else 'array'}")
                return LLMResponse(
                    data=data,
                    raw_response=raw_content,
                    model=self.model,
                    prompt_tokens=(
                        response.usage_metadata.prompt_token_count
                        if response.usage_metadata
                        else None
                    ),
                    completion_tokens=(
                        response.usage_metadata.candidates_token_count
                        if response.usage_metadata
                        else None
                    ),
                    total_tokens=(
                        response.usage_metadata.total_token_count
                        if response.usage_metadata
                        else None
                    ),
                    duration_ms=duration_ms,
                )
            except json.JSONDecodeError as e:
                logger.warning(f"[LLM] Invalid JSON in Gemini response: {e}, attempting repair...")
                
                # Attempt repair
                repaired = _repair_json(raw_content)
                if repaired is not None:
                    logger.info("[LLM] JSON repair succeeded")
                    return LLMResponse(
                        data=repaired,
                        raw_response=raw_content,
                        retried=True,
                        model=self.model,
                        prompt_tokens=(
                            response.usage_metadata.prompt_token_count
                            if response.usage_metadata
                            else None
                        ),
                        completion_tokens=(
                            response.usage_metadata.candidates_token_count
                            if response.usage_metadata
                            else None
                        ),
                        total_tokens=(
                            response.usage_metadata.total_token_count
                            if response.usage_metadata
                            else None
                        ),
                        duration_ms=duration_ms,
                    )
                
                logger.error("[LLM] JSON repair failed for Gemini response")
                logger.debug(f"[LLM] Raw content (first 500): {raw_content[:500]}")
                return LLMResponse(
                    data={},
                    raw_response=raw_content,
                    error=f"Invalid JSON in response: {e}",
                    model=self.model,
                    prompt_tokens=(
                        response.usage_metadata.prompt_token_count
                        if response.usage_metadata
                        else None
                    ),
                    completion_tokens=(
                        response.usage_metadata.candidates_token_count
                        if response.usage_metadata
                        else None
                    ),
                    total_tokens=(
                        response.usage_metadata.total_token_count
                        if response.usage_metadata
                        else None
                    ),
                    duration_ms=duration_ms,
                )
        
        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.exception(f"[LLM] Gemini API error after {duration_ms:.0f}ms: {e}")
            return LLMResponse(
                data={},
                error=f"Gemini API error: {e}",
            )


def get_llm_client(
    timeout: float = 60.0,
    max_tokens: int | None = None,
    fast: bool = False,
    tier: str | None = None,
    thinking_budget: int | None = None,
    temperature: float = 0.1,
) -> BaseLLMClient:
    """
    Factory function to get the configured LLM client.
    
    Uses LLM_PROVIDER env var: 'dummy', 'openai', or 'gemini'
    
    Args:
        timeout: Request timeout in seconds (default: 60s)
        max_tokens: Optional max tokens to generate (limits response size)
        fast: Backward-compatible alias for ``tier="fast"``
        tier: ``fast`` (Flash-Lite), ``balanced`` (Flash), or ``quality`` (Pro)
        thinking_budget: Gemini thinking-token budget. Use 0 for extraction or
            long-form writing where the prompt already supplies the structure.
    """
    from app.core.config import settings
    
    provider = settings.llm_provider
    resolved_tier = tier or ("fast" if fast else "balanced")
    if resolved_tier not in {"fast", "balanced", "quality"}:
        raise ValueError(f"Unknown LLM tier: {resolved_tier}")
    
    if provider == "gemini":
        if not settings.gemini_api_key:
            logger.warning(
                "LLM_PROVIDER=gemini but GEMINI_API_KEY not set. "
                "Falling back to dummy client."
            )
            return DummyLLMClient()
        
        model = {
            "fast": settings.gemini_fast_model,
            "balanced": settings.gemini_model,
            "quality": settings.gemini_quality_model,
        }[resolved_tier]
        if thinking_budget is None and resolved_tier == "fast":
            thinking_budget = 0
        return GeminiLLMClient(
            model=model,
            timeout=timeout,
            max_tokens=max_tokens,
            thinking_budget=thinking_budget,
            temperature=temperature,
        )
    elif provider == "openai":
        if not settings.openai_api_key:
            logger.warning(
                "LLM_PROVIDER=openai but OPENAI_API_KEY not set. "
                "Falling back to dummy client."
            )
            return DummyLLMClient()
        
        model = {
            "fast": settings.openai_fast_model,
            "balanced": settings.openai_model,
            "quality": settings.openai_quality_model,
        }[resolved_tier]
        return OpenAILLMClient(
            model=model,
            timeout=timeout,
            max_tokens=max_tokens,
        )
    else:
        return DummyLLMClient()
