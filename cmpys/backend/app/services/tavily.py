"""
Material URL resolution service.

Uses Gemini with Google Search grounding to find real, verified YouTube URLs.
Validates availability via oEmbed. If no valid URL found, returns None (not search links).
"""

import asyncio
import logging
import re
from typing import Optional
from urllib.parse import quote_plus

import httpx

from app.core.config import settings

logger = logging.getLogger("cmpys.services.video_search")

YOUTUBE_OEMBED_URL = "https://www.youtube.com/oembed"


async def _validate_youtube_url(client: httpx.AsyncClient, url: str) -> bool:
    """Check if a YouTube video is actually available via oEmbed."""
    try:
        resp = await client.get(
            YOUTUBE_OEMBED_URL,
            params={"url": url, "format": "json"},
            timeout=5.0,
        )
        return resp.status_code == 200
    except Exception:
        return False


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

        from app.services.gemini import _gemini_client

        client = _gemini_client()
        response = await client.aio.models.generate_content(
            model="gemini-2.5-flash",
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
                temperature=0.0,
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

            # Validate first 3 via oEmbed
            for vid in unique_ids[:3]:
                url = f"https://www.youtube.com/watch?v={vid}"
                is_valid = await _validate_youtube_url(client, url)
                if is_valid:
                    logger.info(f"[VIDEO] ✓ YouTube search fallback: {url} for '{query}'")
                    return url

        return None
    except Exception as exc:
        logger.warning(f"[VIDEO] YouTube search fallback failed: {exc}")
        return None


async def _resolve_single_video(query: str) -> Optional[str]:
    """Try Gemini grounding first, fall back to YouTube search scraping."""
    url = await _search_video_via_google(query)
    if url:
        return url

    # Fallback: direct YouTube search scrape
    url = await _search_video_via_youtube_api(query)
    return url


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
