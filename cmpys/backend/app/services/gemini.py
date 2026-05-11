"""
Google Gemini service for the CMPYS chat advisor.

Provides two capabilities:
1. `stream_with_grounding()` — Gemini 2.0 Flash with Google Search grounding.
   Used for resource/link queries: the model searches Google in real-time and
   cites real URLs in its response.

2. `stream_learnlm()` — LearnLM 2.0 Flash for Socratic tutoring.
   Used for study/learning questions: the model asks guiding questions and
   checks understanding rather than just giving answers.

Both return async generators that yield text chunks for SSE streaming.
"""

import logging
from typing import AsyncGenerator

from google import genai
from google.genai import types

from app.core.config import settings

logger = logging.getLogger("cmpys.services.gemini")

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


def _gemini_client() -> genai.Client:
    return genai.Client(api_key=settings.gemini_api_key)


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


async def stream_with_grounding(
    system_prompt: str,
    user_message: str,
    conversation_history: str = "",
) -> AsyncGenerator[str, None]:
    """
    Stream a Gemini 2.0 Flash response with Google Search grounding.

    The model automatically searches Google before responding and cites
    real URLs — no manual Tavily injection needed.
    """
    client = _gemini_client()

    full_prompt = f"""{system_prompt}

Previous conversation:
{conversation_history}

User: {user_message}

When recommending resources, use the real URLs from your Google Search results.
Respond as the persona above:"""

    logger.info("[GEMINI] Starting grounded stream (Google Search enabled)")

    try:
        response = await client.aio.models.generate_content(
            model="gemini-2.5-flash",
            contents=full_prompt,
            config=types.GenerateContentConfig(
                tools=[types.Tool(google_search=types.GoogleSearch())],
                temperature=0.7,
            ),
        )
        # Non-streaming with grounding (grounding requires non-streaming)
        if response.text:
            # Yield in chunks to simulate streaming
            text = response.text
            chunk_size = 8
            for i in range(0, len(text), chunk_size):
                yield text[i:i + chunk_size]
    except Exception as e:
        logger.error(f"[GEMINI] Grounded stream error: {e}")
        raise


async def stream_learnlm(
    idol_name: str,
    idol_persona_context: str,
    user_message: str,
    conversation_history: str = "",
) -> AsyncGenerator[str, None]:
    """
    Stream a LearnLM 2.0 Flash response for Socratic educational tutoring.

    LearnLM is fine-tuned to:
    - Ask guiding questions rather than just giving answers
    - Check the user's understanding
    - Adapt to the user's level
    - Break down complex concepts step-by-step

    This is used when users ask study/comprehension questions.
    """
    client = _gemini_client()

    system_instruction = f"""You are {idol_name}, a simulated AI persona acting as a Socratic tutor.

{idol_persona_context}

As a tutor, you must:
- Guide with questions rather than immediately giving the full answer
- Check if the user understands before moving on
- Break complex ideas into small steps
- Celebrate correct thinking
- Gently correct misconceptions
- Stay in character as {idol_name}

Previous conversation:
{conversation_history}"""

    logger.info("[GEMINI] Starting LearnLM tutor stream")

    try:
        response = await client.aio.models.generate_content(
            model="learnlm-2.0-flash-experimental",
            contents=user_message,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                temperature=0.8,
            ),
        )
        if response.text:
            text = response.text
            chunk_size = 8
            for i in range(0, len(text), chunk_size):
                yield text[i:i + chunk_size]
    except Exception as e:
        logger.warning(f"[GEMINI] LearnLM error (falling back): {e}")
        raise


# =============================================================================
# Agentic Workflow Streams
# =============================================================================


async def interview_stream(
    system_prompt: str,
    user_message: str,
    conversation_history: str = "",
) -> AsyncGenerator[str, None]:
    """
    Stream a Gemini response for the interview phase.

    Uses system_instruction for deep persona immersion + Google Search
    for fact-based grounding. The system_prompt should be the rendered
    interview_system.xml content. The user_message is the rendered
    interview_question.txt.

    The model asks exactly ONE question per turn and reacts emotionally.
    """
    client = _gemini_client()

    # Build the user-facing content (history + current message)
    if conversation_history:
        contents = f"{conversation_history}\n\nUser: {user_message}"
    else:
        contents = user_message

    logger.info("[GEMINI] Starting interview stream (persona + Google Search)")

    try:
        response = await client.aio.models.generate_content(
            model="gemini-2.5-flash",
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                tools=[types.Tool(google_search=types.GoogleSearch())],
                temperature=0.8,
            ),
        )
        if response.text:
            text = response.text
            chunk_size = 8
            for i in range(0, len(text), chunk_size):
                yield text[i:i + chunk_size]
    except Exception as e:
        logger.error(f"[GEMINI] Interview stream error: {e}")
        raise


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
    client = _gemini_client()

    logger.info("[GEMINI] Starting comparison stream (Google Search enabled)")

    try:
        response = await client.aio.models.generate_content(
            model="gemini-2.5-flash",
            contents=user_message,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                tools=[types.Tool(google_search=types.GoogleSearch())],
                temperature=0.7,
            ),
        )
        if response.text:
            text = response.text
            chunk_size = 8
            for i in range(0, len(text), chunk_size):
                yield text[i:i + chunk_size]
    except Exception as e:
        logger.error(f"[GEMINI] Comparison stream error: {e}")
        raise


async def blueprint_stream(
    system_prompt: str,
    user_message: str,
) -> AsyncGenerator[str, None]:
    """
    Stream a Gemini response for the Q1–Q4 quarterly blueprint.

    Uses Google Search to find real, currently available study materials
    (books, courses, platforms) with working URLs. The system_prompt
    maintains the idol persona. The user_message is the rendered
    blueprint_generate.txt with full context.
    """
    client = _gemini_client()

    logger.info("[GEMINI] Starting blueprint stream (Google Search for resources)")

    try:
        response = await client.aio.models.generate_content(
            model="gemini-2.5-flash",
            contents=user_message,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                tools=[types.Tool(google_search=types.GoogleSearch())],
                temperature=0.7,
            ),
        )
        if response.text:
            text = response.text
            chunk_size = 8
            for i in range(0, len(text), chunk_size):
                yield text[i:i + chunk_size]
    except Exception as e:
        logger.error(f"[GEMINI] Blueprint stream error: {e}")
        raise
