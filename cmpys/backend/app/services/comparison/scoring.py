"""Structured comparison scores: a separate JSON scorer with a seed fallback."""
import asyncio
import logging

from app.services.llm.prompt_loader import load_and_render

logger = logging.getLogger(__name__)

# Fixed dimensions — ids MUST match the FE radar (capital/knowledge/habits/
# network/clarity). Seed values fill any dimension the model omits so the radar
# always has 5 axes.
FIXED_DIMENSIONS: list[dict] = [
    {"id": "capital", "label": "Capital at work", "you": 35, "idol": 70,
     "you_note": "", "idol_note": ""},
    {"id": "knowledge", "label": "Knowledge base", "you": 45, "idol": 85,
     "you_note": "", "idol_note": ""},
    {"id": "habits", "label": "Daily discipline", "you": 40, "idol": 80,
     "you_note": "", "idol_note": ""},
    {"id": "network", "label": "Trusted network", "you": 35, "idol": 65,
     "you_note": "", "idol_note": ""},
    {"id": "clarity", "label": "Strategic clarity", "you": 45, "idol": 78,
     "you_note": "", "idol_note": ""},
]

_SCORES_SCHEMA = {
    "type": "object",
    "properties": {
        "dimensions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "label": {"type": "string"},
                    "you": {"type": "integer"},
                    "idol": {"type": "integer"},
                    "you_note": {"type": "string"},
                    "idol_note": {"type": "string"},
                },
                "required": ["id", "you", "idol"],
            },
        },
        "milestones": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "hit_by_age": {"type": "integer"},
                },
                "required": ["text"],
            },
        },
    },
    "required": ["dimensions", "milestones"],
}


def _clamp(v, lo=0, hi=100) -> int:
    try:
        return max(lo, min(hi, int(v)))
    except (TypeError, ValueError):
        return lo


def normalize_comparison_scores(raw: dict | None) -> dict:
    """Always return {dimensions:[5 fixed, in order], milestones:[<=5]}.

    Fills any missing dimension from FIXED_DIMENSIONS, clamps you/idol to
    0-100, and assigns positional milestone ids (m1..m5) so the FE claim map
    stays stable.
    """
    raw = raw or {}
    by_id = {}
    for d in raw.get("dimensions") or []:
        if isinstance(d, dict) and d.get("id") in {x["id"] for x in FIXED_DIMENSIONS}:
            by_id[d["id"]] = d

    dimensions = []
    for seed in FIXED_DIMENSIONS:
        d = by_id.get(seed["id"])
        if d:
            dimensions.append({
                "id": seed["id"],
                "label": (d.get("label") or seed["label"]),
                "you": _clamp(d.get("you", seed["you"])),
                "idol": _clamp(d.get("idol", seed["idol"])),
                "you_note": (d.get("you_note") or "").strip(),
                "idol_note": (d.get("idol_note") or "").strip(),
            })
        else:
            dimensions.append(dict(seed))

    milestones = []
    for i, m in enumerate((raw.get("milestones") or [])[:5]):
        if not isinstance(m, dict):
            continue
        text = (m.get("text") or "").strip()
        if not text:
            continue
        milestones.append({
            "id": f"m{i + 1}",
            "label": text,
            "hit_by_age": _clamp(m.get("hit_by_age", 0), 0, 200),
        })

    return {"dimensions": dimensions, "milestones": milestones}


async def generate_comparison_scores(
    client,
    *,
    idol_name: str,
    user_age,
    user_profile_json: str,
    interview_transcript_json: str,
    idol_facts_json: str,
    comparison_summary: str,
    timeout_s: float = 25.0,
) -> dict | None:
    """Generate structured scores. Returns normalized dict, or None on failure
    (caller falls back to the FE seed). Never raises."""
    try:
        prompt = load_and_render(
            "comparison_scores.txt",
            {
                "idol_name": idol_name,
                "user_age": str(user_age),
                "user_profile_json": user_profile_json,
                "interview_transcript_json": interview_transcript_json,
                "idol_facts_json": idol_facts_json,
                "comparison_summary": comparison_summary[:2000],
            },
            strict=True,
        )
        resp = await asyncio.wait_for(
            client.generate_json(
                system_prompt="You output ONLY valid JSON comparison scores.",
                user_prompt=prompt,
                json_schema=_SCORES_SCHEMA,
            ),
            timeout=timeout_s,
        )
        if resp.error:
            # one fresh retry — Gemini JSON is non-deterministic
            resp = await asyncio.wait_for(
                client.generate_json(
                    system_prompt="You output ONLY valid, minified JSON.",
                    user_prompt=prompt,
                    json_schema=_SCORES_SCHEMA,
                ),
                timeout=timeout_s,
            )
        if resp.error or not resp.data:
            logger.warning(f"[CMP_SCORES] scorer failed: {resp.error}")
            return None
        return normalize_comparison_scores(resp.data)
    except Exception as e:  # noqa: BLE001 — fallback is the contract
        logger.warning(f"[CMP_SCORES] scorer exception: {e}")
        return None
