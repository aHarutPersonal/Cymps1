"""
Material URL resolution service.

Searches YouTube directly for real URLs and validates availability via oEmbed.
Gemini grounding is a fallback for direct-search misses. If no valid URL is
found, returns None (not search links).
"""

import asyncio
import logging
import re
from typing import Optional
from urllib.parse import quote_plus

import httpx

logger = logging.getLogger("cmpys.services.video_search")

YOUTUBE_OEMBED_URL = "https://www.youtube.com/oembed"

_RELEVANCE_STOP_WORDS = {
    "about", "and", "best", "explains", "for", "from", "full", "how",
    "interview", "official", "the", "this", "to", "video", "with", "without",
}


async def _youtube_oembed_metadata(
    client: httpx.AsyncClient,
    url: str,
) -> dict | None:
    """Return trusted playability metadata for one YouTube URL."""
    try:
        resp = await client.get(
            YOUTUBE_OEMBED_URL,
            params={"url": url, "format": "json"},
            timeout=5.0,
        )
        if resp.status_code != 200:
            return None
        payload = resp.json()
        return payload if isinstance(payload, dict) else None
    except Exception:
        return None


async def _validate_youtube_url(client: httpx.AsyncClient, url: str) -> bool:
    """Check if a YouTube video is actually available via oEmbed."""
    return await _youtube_oembed_metadata(client, url) is not None


def _oembed_matches_query(metadata: dict, query: str) -> bool:
    """Reject playable-but-irrelevant first results before the fast-path wins."""
    def tokens(value: str) -> set[str]:
        return {
            token
            for token in re.findall(r"[a-z0-9]+", value.casefold())
            if len(token) >= 3 and token not in _RELEVANCE_STOP_WORDS
        }

    wanted = tokens(query)
    candidate = tokens(
        f"{metadata.get('title', '')} {metadata.get('author_name', '')}"
    )
    if not wanted or not candidate:
        return False
    overlap = wanted & candidate
    required = 1 if len(wanted) <= 2 else 2
    coverage = len(overlap) / len(wanted)
    return len(overlap) >= required and (coverage >= 0.25 or len(overlap) >= 3)


def _extract_youtube_urls(text: str) -> list[str]:
    """Extract YouTube watch URLs from text (11-char video IDs only)."""
    pattern = r'https?://(?:www\.)?youtube\.com/watch\?v=[\w-]{11}'
    return list(dict.fromkeys(re.findall(pattern, text)))  # deduplicate


async def _search_video_via_google(query: str) -> Optional[str]:
    """
    Use Gemini with Google Search grounding to find an exact YouTube video URL.
    Validates via oEmbed. Returns None if no valid video found.
    """
    try:
        from google.genai import types

        from app.core.config import settings
        from app.services.gemini import (
            GEMINI_REQUEST_TIMEOUT_MS,
            _gemini_client,
        )
        from app.services.llm.gemini_compat import (
            generation_config_kwargs,
            resolve_thinking_config,
        )

        client = _gemini_client()
        model = settings.gemini_fast_model
        thinking_level, thinking_budget = resolve_thinking_config(
            model=model,
            tier="fast",
            thinking_level="minimal",
            thinking_budget=None,
        )
        response = await client.aio.models.generate_content(
            model=model,
            contents=(
                f"Find the exact YouTube video for: {query}\n\n"
                "IMPORTANT RULES:\n"
                "1. Return ONLY a real YouTube watch URL: https://www.youtube.com/watch?v=XXXXXXXXXXX\n"
                "2. The video MUST actually exist and be playable\n"
                "3. The video MUST be in English\n"
                "4. Pick a popular video from a well-known channel\n"
                "5. Do NOT return search URLs or playlist URLs\n"
                "6. If no exact match exists, return the closest relevant video\n"
                "7. If you truly cannot find any video, return NOT_FOUND"
            ),
            config=types.GenerateContentConfig(
                tools=[types.Tool(google_search=types.GoogleSearch())],
                max_output_tokens=200,
                http_options=types.HttpOptions(
                    timeout=GEMINI_REQUEST_TIMEOUT_MS,
                ),
                **generation_config_kwargs(
                    model=model,
                    temperature=0.0,
                    thinking_level=thinking_level,
                    thinking_budget=thinking_budget,
                ),
            ),
        )

        if not response.text:
            return None

        text = response.text.strip()
        if "NOT_FOUND" in text:
            return None

        urls = _extract_youtube_urls(text)
        if not urls:
            logger.info(f"[VIDEO] No YouTube URL in Gemini response for '{query}'")
            return None

        # Validate up to 3 URLs via oEmbed
        async with httpx.AsyncClient() as http_client:
            for url in urls[:3]:
                if await _validate_youtube_url(http_client, url):
                    logger.info(f"[VIDEO] ✓ Valid: {url} for '{query}'")
                    return url
                else:
                    logger.warning(f"[VIDEO] ✗ Unavailable: {url}")

        return None

    except Exception as exc:
        logger.warning(f"[VIDEO] Search failed for '{query}': {exc}")
        return None


async def _search_video_via_youtube_api(query: str) -> Optional[str]:
    """
    Fallback: use YouTube's public search endpoint to find a video.
    No API key needed — uses the public search suggestions + page scraping.
    """
    try:
        search_url = f"https://www.youtube.com/results?search_query={quote_plus(query)}"
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                search_url,
                headers={"User-Agent": "Mozilla/5.0"},
                timeout=8.0,
                follow_redirects=True,
            )
            if resp.status_code != 200:
                return None

            # Extract video IDs from YouTube search results page
            video_ids = re.findall(r'"videoId":"([\w-]{11})"', resp.text)
            # Deduplicate preserving order
            seen = set()
            unique_ids = []
            for vid in video_ids:
                if vid not in seen:
                    seen.add(vid)
                    unique_ids.append(vid)

            if not unique_ids:
                return None

            # Validate playability AND title/creator relevance for the first
            # three. A merely playable result is not a quality-preserving hit.
            for vid in unique_ids[:3]:
                url = f"https://www.youtube.com/watch?v={vid}"
                metadata = await _youtube_oembed_metadata(client, url)
                if metadata and _oembed_matches_query(metadata, query):
                    logger.info(f"[VIDEO] ✓ Relevant YouTube result: {url} for '{query}'")
                    return url
                if metadata:
                    logger.info(
                        "[VIDEO] Playable result was not relevant enough: %s for '%s'",
                        url,
                        query,
                    )

        return None
    except Exception as exc:
        logger.warning(f"[VIDEO] YouTube search fallback failed: {exc}")
        return None


async def _resolve_single_video(query: str) -> Optional[str]:
    """Use validated direct YouTube search, then ground only as a fallback."""
    url = await _search_video_via_youtube_api(query)
    if url:
        return url

    return await _search_video_via_google(query)


async def resolve_material_urls(materials: list[dict]) -> list[dict]:
    """
    Resolve materials to real URLs. For videos, finds exact YouTube watch URLs.
    NEVER returns search page URLs — only real embeddable video URLs or None.
    """
    if not materials:
        return []

    video_indices: list[int] = []
    for i, m in enumerate(materials):
        if m.get("type") == "video":
            video_indices.append(i)

    # Resolve videos in parallel
    if video_indices:
        video_tasks = [
            _resolve_single_video(
                materials[i].get("search_query", materials[i].get("title", ""))
            )
            for i in video_indices
        ]
        video_urls = await asyncio.gather(*video_tasks)
    else:
        video_urls = []

    # Build result
    resolved = []
    video_url_map = dict(zip(video_indices, video_urls))

    for i, material in enumerate(materials):
        mat = dict(material)

        if i in video_url_map:
            # Only set URL if we got a real video URL, otherwise None
            mat["url"] = video_url_map[i]  # None is fine — feed filters nulls
        elif mat.get("url") is None and mat.get("type") != "video":
            # Non-video: use search fallback
            mat["url"] = _fallback_url(material)["url"]

        resolved.append(mat)

    valid_count = sum(1 for u in video_urls if u)
    logger.info(f"[VIDEO] Resolved {valid_count}/{len(video_indices)} videos")
    return resolved


def _fallback_url(material: dict) -> dict:
    """Generate a search URL fallback for non-video materials only."""
    mat = dict(material)
    query = quote_plus(mat.get("search_query", mat.get("title", "")))
    mat_type = mat.get("type", "article")

    if mat_type in ("book",):
        mat["url"] = f"https://www.amazon.com/s?k={query}"
    elif mat_type in ("course",):
        mat["url"] = f"https://www.coursera.org/search?query={query}"
    else:
        mat["url"] = f"https://www.google.com/search?q={query}"

    mat.pop("search_query", None)
    return mat
