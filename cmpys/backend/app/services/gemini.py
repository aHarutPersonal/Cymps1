"""
Google Gemini service for the CMPYS chat advisor.

Provides two capabilities:
1. `generate_with_grounding()` — Gemini 2.5 Flash with Google Search grounding.
   Used for resource/link queries: the model searches Google in real-time and
   cites real URLs in its response. Single call, full response.

2. `stream_learnlm()` — Gemini 2.5 Flash for Socratic tutoring.
   Used for study/learning questions: the model asks guiding questions and
   checks understanding rather than just giving answers. The caller provides
   the full rendered system prompt (guided_learning_system.txt).

Both return async generators that yield text chunks for SSE streaming.
"""

import asyncio
import inspect
import logging
import time
from typing import AsyncGenerator

from google import genai
from google.genai import types

from app.core.config import settings

logger = logging.getLogger("cmpys.services.gemini")

# Bound user-facing provider requests. Historical successful generations are
# below this ceiling; the limit prevents a stalled socket from holding an SSE
# request or worker slot indefinitely.
GEMINI_REQUEST_TIMEOUT_MS = 60_000

# Keywords that suggest user is asking for learning resources
RESOURCE_KEYWORDS = {
    "book", "video", "course", "recommend", "resource", "reading",
    "watch", "study", "tutorial", "guide", "article", "material",
    "podcast", "tool", "practice", "learn", "teach", "explain",
    "where can i", "what should i", "how do i find",
}

# Keywords that suggest user wants Socratic tutoring
TUTOR_KEYWORDS = {
    "help me understand", "how does", "why is", "what is", "explain",
    "i don't understand", "i'm confused", "can you teach", "quiz me",
    "test me", "check my", "am i right", "is this correct",
}


# Module-level singleton: each genai.Client owns its own connection pool, so a
# per-call client pays a fresh TCP+TLS handshake (~100-300ms) on every LLM
# call. The SDK's aiohttp session is bound to the event loop that first uses
# it, though, so a worker must never reuse the client after switching loops.
_client_singleton: genai.Client | None = None
_client_api_key: str | None = None
_client_event_loop: asyncio.AbstractEventLoop | None = None


def _client_session_matches_loop(
    client: genai.Client,
    loop: asyncio.AbstractEventLoop,
) -> bool:
    """Return whether the SDK's live aiohttp session belongs to ``loop``.

    google-genai lazily creates and caches an aiohttp session. Its own reuse
    guard replaces sessions whose loop is closed, but not sessions attached to
    a different loop that is still open. That produces aiohttp's misleading
    ``Timeout context manager should be used inside a task`` error even though
    the caller is inside a task. Inspecting the private transport is deliberate
    containment for that upstream lifecycle gap; absent/lazy sessions are safe.
    """
    api_client = getattr(client, "_api_client", None)
    session = getattr(api_client, "_aiohttp_session", None)
    if session is None or getattr(session, "closed", False):
        return True
    return getattr(session, "_loop", loop) is loop


def _gemini_client() -> genai.Client:
    global _client_singleton, _client_api_key, _client_event_loop
    loop = asyncio.get_running_loop()
    if (
        _client_singleton is None
        or _client_api_key != settings.gemini_api_key
        or _client_event_loop is not loop
        or not _client_session_matches_loop(_client_singleton, loop)
    ):
        _client_singleton = genai.Client(api_key=settings.gemini_api_key)
        _client_api_key = settings.gemini_api_key
        _client_event_loop = loop
    return _client_singleton


def detect_intent(message: str) -> str:
    """
    Classify user message intent for routing.
    Returns: 'tutor' | 'resource' | 'general'
    """
    msg_lower = message.lower()
    if any(kw in msg_lower for kw in TUTOR_KEYWORDS):
        return "tutor"
    if any(kw in msg_lower for kw in RESOURCE_KEYWORDS):
        return "resource"
    return "general"


async def generate_with_grounding(
    system_prompt: str,
    user_message: str,
    conversation_history: str = "",
    operation: str = "grounded_generation",
) -> str:
    """
    Single Gemini 2.5 Flash call with Google Search grounding.

    For callers that need the complete response (JSON contracts, fact
    lookups) — no streaming involved. The model automatically searches
    Google before responding and cites real URLs.
    """
    client = _gemini_client()
    started = time.perf_counter()

    if conversation_history:
        contents = f"Previous conversation:\n{conversation_history}\n\n{user_message}"
    else:
        contents = user_message

    logger.info("[GEMINI] Grounded generate (Google Search enabled)")

    try:
        response = await client.aio.models.generate_content(
            model="gemini-2.5-flash",
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                tools=[types.Tool(google_search=types.GoogleSearch())],
                temperature=0.7,
                http_options=types.HttpOptions(
                    timeout=GEMINI_REQUEST_TIMEOUT_MS,
                ),
            ),
        )
        text = response.text or ""
        duration_ms = (time.perf_counter() - started) * 1000
        usage = getattr(response, "usage_metadata", None)
        queries: set[str] = set()
        grounded_source_count = 0
        for candidate in getattr(response, "candidates", None) or []:
            metadata = getattr(candidate, "grounding_metadata", None)
            grounded_source_count += len(
                getattr(metadata, "grounding_chunks", None) or []
            )
            for query in getattr(metadata, "web_search_queries", None) or []:
                if str(query).strip():
                    queries.add(str(query).strip())

        from app.services.llm.telemetry import UsageRecord, record_usage_records

        await record_usage_records(
            [
                UsageRecord(
                    operation=operation,
                    model="gemini-2.5-flash",
                    provider="gemini",
                    prompt_tokens=getattr(usage, "prompt_token_count", None),
                    completion_tokens=getattr(usage, "candidates_token_count", None),
                    total_tokens=getattr(usage, "total_token_count", None),
                    duration_ms=duration_ms,
                    grounded=True,
                    search_queries=len(queries),
                    success=bool(text),
                    result_status="generated" if text else "empty",
                    metadata={
                        "grounded_source_count": grounded_source_count,
                        "response_chars": len(text),
                    },
                )
            ]
        )
        return text
    except Exception as e:
        logger.error(f"[GEMINI] Grounded generate error: {e}")
        raise


async def _stream_generate(
    system_prompt: str,
    contents: str,
    label: str,
    grounded: bool = True,
    temperature: float = 0.7,
    max_output_tokens: int | None = None,
) -> AsyncGenerator[str, None]:
    """
    True token streaming via generate_content_stream (the pattern proven by
    interview_stream: streaming works WITH the google_search tool). This cuts
    user-perceived time-to-first-byte from full-generation time to first-token
    time, and yields natural token chunks instead of artificial 8-char slices
    (~10x fewer SSE events downstream).
    """
    client = _gemini_client()
    tools = [types.Tool(google_search=types.GoogleSearch())] if grounded else None
    started = time.perf_counter()
    first_text_at: float | None = None
    response_chars = 0
    finish_reason = "unknown"

    try:
        stream = client.aio.models.generate_content_stream(
            model="gemini-2.5-flash",
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                tools=tools,
                temperature=temperature,
                max_output_tokens=max_output_tokens,
                http_options=types.HttpOptions(
                    timeout=GEMINI_REQUEST_TIMEOUT_MS,
                ),
            ),
        )
        # The async SDK may return the iterator directly or a coroutine that
        # resolves to it, depending on version — support both.
        if inspect.iscoroutine(stream):
            stream = await stream
        async for chunk in stream:
            for candidate in getattr(chunk, "candidates", None) or []:
                reason = getattr(candidate, "finish_reason", None)
                if reason is not None:
                    finish_reason = (
                        getattr(reason, "name", None)
                        or str(reason).rsplit(".", maxsplit=1)[-1]
                    )
            text = getattr(chunk, "text", None)
            if text:
                if first_text_at is None:
                    first_text_at = time.perf_counter()
                response_chars += len(text)
                yield text

        if finish_reason not in {"unknown", "STOP", "FINISH_REASON_UNSPECIFIED"}:
            raise RuntimeError(
                f"{label} response ended incompletely ({finish_reason})"
            )

        duration_ms = (time.perf_counter() - started) * 1000
        first_text_ms = (
            (first_text_at - started) * 1000
            if first_text_at is not None
            else 0
        )
        logger.info(
            "[GEMINI] %s stream completed: %.0fms, first_text=%.0fms, "
            "chars=%s, finish_reason=%s",
            label,
            duration_ms,
            first_text_ms,
            response_chars,
            finish_reason,
        )
    except Exception as e:
        logger.error(f"[GEMINI] {label} stream error: {e}")
        raise


async def stream_learnlm(
    system_prompt: str,
    user_message: str,
) -> AsyncGenerator[str, None]:
    """
    Stream a Gemini 2.5 Flash response for Socratic educational tutoring.

    The caller passes the fully rendered system prompt — normally
    guided_learning_system.txt with the idol's persona pack (voice style,
    principles, lexicon, worldview adapter) and the conversation history
    already substituted in. Keeping the rendering at the call site means
    the tutoring voice stays in the prompt file, not in code.
    """
    logger.info("[GEMINI] Starting LearnLM tutor stream")
    async for text in _stream_generate(
        system_prompt=system_prompt,
        contents=user_message,
        label="LearnLM",
        grounded=False,
        temperature=0.8,
        max_output_tokens=1200,
    ):
        yield text


# =============================================================================
# Agentic Workflow Streams
# =============================================================================


async def interview_stream(
    system_prompt: str,
    user_message: str,
) -> AsyncGenerator[str, None]:
    """
    Stream a Gemini response for the interview phase.

    Uses ``system_instruction`` for deep persona immersion and the verified
    fact sheet embedded by the caller. The system_prompt should be the rendered
    interview_system.xml content. The user_message is the rendered
    interview_question.txt.

    The model asks exactly ONE question per turn and reacts emotionally.
    """
    # The caller supplies a separately verified idol fact sheet in the rendered
    # per-turn prompt. Searching again here adds several seconds to every turn
    # and can produce facts that conflict with that shared source of truth.
    logger.info("[GEMINI] Starting interview stream (persona + verified fact sheet)")
    async for text in _stream_generate(
        system_prompt=system_prompt,
        contents=user_message,
        label="Interview",
        grounded=False,
        temperature=0.8,
    ):
        yield text


async def comparison_stream(
    system_prompt: str,
    user_message: str,
) -> AsyncGenerator[str, None]:
    """
    Stream a Gemini response for the brutal reality comparison.

    Uses Google Search to verify idol achievements at the user's age.
    The system_prompt maintains the idol persona. The user_message is
    the rendered comparison_generate.txt with full interview context.
    """
    logger.info("[GEMINI] Starting comparison stream (Google Search enabled)")
    async for text in _stream_generate(
        system_prompt=system_prompt,
        contents=user_message,
        label="Comparison",
        grounded=True,
    ):
        yield text


async def blueprint_stream(
    system_prompt: str,
    user_message: str,
) -> AsyncGenerator[str, None]:
    """
    Stream a Gemini response for the Q1–Q4 quarterly blueprint.

    Uses the cached idol facts, interview, and comparison supplied by the
    caller. Resource lookup happens later in the plan-detail pipeline, so this
    phase does not pay for live search. The system_prompt maintains the idol
    persona. The user_message is the rendered blueprint_generate.txt.
    """
    logger.info("[GEMINI] Starting blueprint stream (cached evidence, no live search)")
    async for text in _stream_generate(
        system_prompt=system_prompt,
        contents=user_message,
        label="Blueprint",
        grounded=False,
    ):
        yield text
