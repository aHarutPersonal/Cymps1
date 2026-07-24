"""
Material URL resolution service.

Searches YouTube directly for playable videos and Tavily for exact non-video
resource pages. Search-result pages are never returned. If no sufficiently
specific direct result is found, the material remains unresolved.
"""

import asyncio
import ipaddress
import logging
import re
from typing import Optional
from urllib.parse import parse_qsl, quote_plus, urlencode, urlsplit, urlunsplit

import httpx

logger = logging.getLogger("cmpys.services.material_search")

YOUTUBE_OEMBED_URL = "https://www.youtube.com/oembed"
TAVILY_SEARCH_URL = "https://api.tavily.com/search"

_RELEVANCE_STOP_WORDS = {
    "about",
    "and",
    "best",
    "explains",
    "for",
    "from",
    "full",
    "how",
    "interview",
    "official",
    "the",
    "this",
    "to",
    "video",
    "with",
    "without",
}

_TRACKING_QUERY_KEYS = {
    "fbclid",
    "gclid",
    "mc_cid",
    "mc_eid",
    "ref",
    "ref_",
    "tag",
}
_SHORTENER_HOSTS = {
    "bit.ly",
    "buff.ly",
    "goo.gl",
    "ow.ly",
    "t.co",
    "tinyurl.com",
}


def _hostname_is_public(hostname: str) -> bool:
    host = hostname.rstrip(".").casefold()
    if (
        not host
        or host == "localhost"
        or host.endswith((".localhost", ".local", ".internal"))
    ):
        return False
    try:
        return ipaddress.ip_address(host).is_global
    except ValueError:
        return True


def is_direct_resource_url(url: str | None) -> bool:
    """Return whether a URL is a safe-looking destination, not a search page."""
    if not url:
        return False
    try:
        parsed = urlsplit(url.strip())
        host = (parsed.hostname or "").casefold()
        path = parsed.path.rstrip("/").casefold()
        query_keys = {key.casefold() for key, _ in parse_qsl(parsed.query)}
    except ValueError:
        return False
    if (
        parsed.scheme not in {"http", "https"}
        or parsed.username is not None
        or parsed.password is not None
        or not _hostname_is_public(host)
        or host in _SHORTENER_HOSTS
    ):
        return False

    if (
        ("google." in host and path == "/search")
        or (host.endswith("bing.com") and path == "/search")
        or (host.endswith("search.yahoo.com"))
        or (host.endswith("duckduckgo.com") and "q" in query_keys)
        or ((host.startswith("amazon.") or ".amazon." in host) and path == "/s")
        or (host.endswith("coursera.org") and path == "/search")
        or (host.endswith("youtube.com") and path == "/results")
    ):
        return False
    if path in {"/search", "/find", "/results"} and query_keys.intersection(
        {"q", "query", "keyword", "search", "search_query"}
    ):
        return False
    return True


def _canonicalize_direct_url(url: str) -> str | None:
    if not is_direct_resource_url(url):
        return None
    parsed = urlsplit(url.strip())
    clean_query = urlencode(
        [
            (key, value)
            for key, value in parse_qsl(parsed.query, keep_blank_values=True)
            if not key.casefold().startswith("utm_")
            and key.casefold() not in _TRACKING_QUERY_KEYS
        ],
        doseq=True,
    )
    return urlunsplit(
        (parsed.scheme, parsed.netloc, parsed.path or "/", clean_query, "")
    )


def _resource_tokens(value: str) -> set[str]:
    return {
        token
        for token in re.findall(r"\w+", value.casefold(), re.UNICODE)
        if len(token) >= 2 and token not in _RELEVANCE_STOP_WORDS
    }


def _candidate_match_score(material: dict, candidate: dict) -> float | None:
    """Score only candidates that preserve the requested resource identity."""
    title = str(material.get("title") or "").strip()
    material_type = str(material.get("type") or "").casefold()
    candidate_title = str(candidate.get("title") or "").casefold()
    misleading_markers = {
        "book": {" review", " summary", " notes", " quotes"},
        "course": {" review", " reviews", " alternatives"},
        "tool": {" review", " reviews", " alternatives"},
    }.get(material_type, set())
    if any(marker in candidate_title for marker in misleading_markers):
        return None
    wanted = _resource_tokens(title)
    if not wanted:
        return None
    creator = _resource_tokens(str(material.get("author_or_creator") or ""))
    candidate_text = " ".join(
        str(candidate.get(key) or "") for key in ("title", "content", "url")
    )
    found = _resource_tokens(candidate_text)
    title_coverage = len(wanted & found) / len(wanted)
    required_coverage = 1.0 if len(wanted) <= 2 else 0.6
    if title_coverage < required_coverage:
        return None

    creator_coverage = len(creator & found) / len(creator) if creator else 1.0
    if len(wanted) <= 2 and creator and creator_coverage == 0:
        return None
    try:
        provider_score = max(0.0, min(1.0, float(candidate.get("score") or 0)))
    except (TypeError, ValueError):
        provider_score = 0.0
    exact_phrase = " ".join(title.casefold().split()) in " ".join(
        candidate_text.casefold().split()
    )
    return (
        0.55 * title_coverage
        + 0.2 * creator_coverage
        + 0.2 * provider_score
        + (0.05 if exact_phrase else 0.0)
    )


async def _tavily_search(query: str) -> list[dict]:
    """Run one bounded Tavily search and return its direct result candidates."""
    from app.core.config import settings

    api_key = settings.tavily_api_key
    if not api_key:
        logger.info("[MATERIAL] Tavily is not configured; leaving resource unresolved")
        return []
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                TAVILY_SEARCH_URL,
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "query": query,
                    "search_depth": "advanced",
                    "max_results": 5,
                    "include_answer": False,
                    "include_raw_content": False,
                },
                timeout=12.0,
            )
        response.raise_for_status()
        payload = response.json()
        results = payload.get("results", []) if isinstance(payload, dict) else []
        return [result for result in results if isinstance(result, dict)]
    except Exception as exc:
        logger.warning("[MATERIAL] Tavily search failed: %s", exc)
        return []


async def _resolve_single_non_video(material: dict) -> Optional[str]:
    title = str(material.get("title") or "").strip()
    creator = str(material.get("author_or_creator") or "").strip()
    material_type = str(material.get("type") or "resource").strip()
    query = f'"{title}"'
    if creator:
        query += f' "{creator}"'
    query += f" {material_type} official"

    ranked: list[tuple[float, str]] = []
    for candidate in await _tavily_search(query):
        canonical_url = _canonicalize_direct_url(str(candidate.get("url") or ""))
        if canonical_url is None:
            continue
        score = _candidate_match_score(material, candidate)
        if score is not None:
            ranked.append((score, canonical_url))
    if not ranked:
        return None
    ranked.sort(key=lambda item: item[0], reverse=True)
    return ranked[0][1]


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
    candidate = tokens(f"{metadata.get('title', '')} {metadata.get('author_name', '')}")
    if not wanted or not candidate:
        return False
    overlap = wanted & candidate
    required = 1 if len(wanted) <= 2 else 2
    coverage = len(overlap) / len(wanted)
    return len(overlap) >= required and (coverage >= 0.25 or len(overlap) >= 3)


def _extract_youtube_urls(text: str) -> list[str]:
    """Extract YouTube watch URLs from text (11-char video IDs only)."""
    pattern = r"https?://(?:www\.)?youtube\.com/watch\?v=[\w-]{11}"
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
                metadata = await _youtube_oembed_metadata(http_client, url)
                if metadata and _oembed_matches_query(metadata, query):
                    logger.info(f"[VIDEO] ✓ Valid: {url} for '{query}'")
                    return url
                logger.warning(f"[VIDEO] ✗ Unavailable or irrelevant: {url}")

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
                    logger.info(
                        f"[VIDEO] ✓ Relevant YouTube result: {url} for '{query}'"
                    )
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
    Resolve materials to direct URLs or None. Existing and discovered search
    pages are rejected; an unresolved identity never becomes a synthetic link.
    """
    if not materials:
        return []

    async def resolve_one(material: dict) -> dict:
        mat = dict(material)
        existing = _canonicalize_direct_url(str(mat.get("url") or ""))
        material_type = str(mat.get("type") or "article")
        if existing is not None:
            url = existing
            provider = "existing"
        elif material_type == "video":
            url = await _resolve_single_video(
                str(mat.get("search_query") or mat.get("title") or "")
            )
            url = _canonicalize_direct_url(url or "")
            provider = "youtube" if url else None
        elif material_type == "in_app_lesson":
            url = None
            provider = None
        else:
            url = await _resolve_single_non_video(mat)
            provider = "tavily" if url else None
        mat["url"] = url
        mat["url_resolution_status"] = (
            "resolved"
            if url
            else "not_applicable"
            if material_type == "in_app_lesson"
            else "unresolved"
        )
        mat["url_provider"] = provider
        return mat

    resolved = await asyncio.gather(*(resolve_one(material) for material in materials))
    valid_count = sum(1 for material in resolved if material.get("url"))
    logger.info("[MATERIAL] Resolved %s/%s direct URLs", valid_count, len(materials))
    return resolved
