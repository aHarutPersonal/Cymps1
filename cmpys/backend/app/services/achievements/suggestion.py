"""Achievement suggestion: AI-phrased line with a deterministic fallback."""
import asyncio
import logging

from app.models.plan import PlanItemType
from app.services.llm import get_llm_client

logger = logging.getLogger(__name__)

_CATEGORY_BY_TYPE = {
    PlanItemType.READING: "learning",
    PlanItemType.COURSE: "learning",
    PlanItemType.PRACTICE: "learning",
    PlanItemType.HABIT: "mindset",
    PlanItemType.PROJECT: "career",
    PlanItemType.REFLECTION: "mindset",
}


def category_for_item(item) -> str:
    return _CATEGORY_BY_TYPE.get(item.type, "other")


def fallback_suggestion(item) -> dict:
    """Instant, no-LLM suggestion derived from the item's success_metric."""
    title = (getattr(item, "success_metric", "") or "").strip()
    if not title:
        title = f"Completed: {(getattr(item, 'title', '') or '').strip()}"
    return {"title": title[:200], "category": category_for_item(item)}


_SUGGESTION_SCHEMA = {
    "type": "object",
    "properties": {"achievement": {"type": "string"}},
    "required": ["achievement"],
}


async def ai_suggestion(item, idol_name: str, timeout_s: float = 2.5) -> dict:
    """AI-phrased achievement; returns fallback on timeout/error.

    Uses the client's only single-shot method, generate_json (returns
    LLMResponse with a `.data` dict and an optional `.error`).
    """
    fb = fallback_suggestion(item)
    try:
        client = get_llm_client(fast=True)
        prompt = (
            f"The user just completed this task while learning from {idol_name}:\n"
            f"Title: {item.title}\nWhat done looks like: {item.success_metric}\n\n"
            "Return JSON {\"achievement\": \"...\"} where the value is ONE "
            "first-person past-tense sentence (max 20 words) the user could log "
            "as a personal achievement. No quotes inside, no preamble."
        )
        resp = await asyncio.wait_for(
            client.generate_json(
                system_prompt="You phrase achievements as JSON.",
                user_prompt=prompt,
                json_schema=_SUGGESTION_SCHEMA,
            ),
            timeout=timeout_s,
        )
        text = ((resp.data or {}).get("achievement") or "").strip().strip('"')
        if not resp.error and text:
            return {"title": text[:200], "category": fb["category"]}
    except Exception as e:  # noqa: BLE001 — fallback is the contract
        logger.info(f"[ACH] AI suggestion fell back: {e}")
    return fb
