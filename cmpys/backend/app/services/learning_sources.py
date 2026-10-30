"""Bounded public evidence retrieval. Search snippets are never teaching evidence."""

import json
import re
from urllib.parse import parse_qs, urlparse

import httpx

from app.services.tavily import _youtube_oembed_metadata, is_direct_resource_url


def youtube_id(url: str) -> str | None:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or parsed.username or parsed.password:
        return None
    value = None
    if host in {"youtube.com", "www.youtube.com", "m.youtube.com"}:
        if parsed.path == "/watch":
            value = parse_qs(parsed.query).get("v", [""])[0]
        elif parsed.path.startswith(("/embed/", "/shorts/")):
            value = parsed.path.split("/")[2]
    elif host == "youtu.be":
        value = parsed.path.lstrip("/")
    return value if value and re.fullmatch(r"[A-Za-z0-9_-]{11}", value) else None


async def search_evidence(query: str) -> list[dict]:
    """Only fixed provider endpoints are fetched, never model-supplied URLs."""
    from app.core.config import settings

    if not settings.tavily_api_key:
        return []
    async with httpx.AsyncClient(timeout=20, follow_redirects=False) as client:
        response = await client.post(
            "https://api.tavily.com/search",
            headers={"Authorization": f"Bearer {settings.tavily_api_key}"},
            json={
                "query": query[:500],
                "search_depth": "advanced",
                "max_results": 5,
                "include_answer": False,
                "include_raw_content": True,
            },
        )
        response.raise_for_status()
    sources = []
    seen = set()
    for result in response.json().get("results", []):
        url = str(result.get("url") or "")
        if url in seen or not is_direct_resource_url(url):
            continue
        seen.add(url)
        text = str(result.get("raw_content") or "")[:18000]
        sources.append(
            {
                "id": f"s{len(sources) + 1}",
                "url": url,
                "title": str(result.get("title") or "")[:300],
                "text": text,
            }
        )
    return sources


def player_response(html: str) -> dict:
    """Decode a complete JSON object, not a regex ending at the first brace."""
    for match in re.finditer(r"(?:var\s+)?ytInitialPlayerResponse\s*=\s*", html):
        try:
            value, _ = json.JSONDecoder().raw_decode(html[match.end() :])
            if isinstance(value, dict):
                return value
        except ValueError:
            pass
    return {}


def referenced_video_urls(source: dict) -> list[str]:
    """Exact links only: mentioning YouTube does not establish video identity."""
    urls = [str(source.get("url") or "")]
    urls += re.findall(
        r"https://(?:www\.)?(?:youtube\.com/(?:watch\?v=|embed/)|youtu\.be/)[A-Za-z0-9_-]{11}",
        source.get("text") or "",
    )
    return list(dict.fromkeys(url for url in urls if youtube_id(url)))


async def verify_video_source(url: str, source: dict | None = None) -> dict | None:
    """Match an offered public embed with substantive creator evidence.

    A server-side watch-page challenge does not invalidate public oEmbed and a
    creator's own lesson linking that exact video. Never bypass sign-in, fetch
    arbitrary hosts, download video, or treat search snippets as transcripts.
    """
    video_id = youtube_id(url)
    if not video_id:
        return None
    canonical = f"https://www.youtube.com/watch?v={video_id}"
    async with httpx.AsyncClient(timeout=12, follow_redirects=False) as client:
        metadata = await _youtube_oembed_metadata(client, canonical)
    if not metadata or not metadata.get("title") or not metadata.get("author_name"):
        return None
    offered = re.search(
        r"https://www\.youtube\.com/embed/([A-Za-z0-9_-]{11})",
        str(metadata.get("html") or ""),
    )
    if not offered or offered[1] != video_id:
        return None
    data = {}
    try:
        async with httpx.AsyncClient(timeout=12, follow_redirects=False) as client:
            response = await client.get(canonical)
            if response.status_code == 200 and len(response.content) <= 3_000_000:
                data = player_response(response.text)
    except httpx.HTTPError:
        pass
    details = data.get("videoDetails") or {}
    playback = data.get("playabilityStatus") or {}
    status = playback.get("status")
    server_challenge = (
        status == "LOGIN_REQUIRED"
        and "not a bot" in str(playback.get("reason") or "").lower()
    )
    if (status and status != "OK" and not server_challenge) or playback.get(
        "playableInEmbed"
    ) is False:
        return None
    if details and (
        details.get("videoId") != video_id or details.get("isLiveContent") is True
    ):
        return None
    evidence = str(details.get("shortDescription") or "")[:18000]
    evidence_type, evidence_url = "creator_description", canonical
    if len(evidence.split()) < 100 and source:
        if not any(
            youtube_id(link) == video_id for link in referenced_video_urls(source)
        ):
            return None
        evidence = str(source.get("text") or "")[:18000]
        evidence_url = source["url"]
        evidence_type = (
            "public_video_page" if youtube_id(evidence_url) else "publisher_lesson"
        )
    if len(evidence.split()) < 100:
        return None
    try:
        seconds = (
            int(details["lengthSeconds"]) if details.get("lengthSeconds") else None
        )
    except (ValueError, TypeError):
        return None
    if seconds is not None and not 60 <= seconds <= 1800:
        return None
    return {
        "url": canonical,
        "videoId": video_id,
        "title": str(metadata["title"])[:300],
        "creator": str(metadata["author_name"])[:300],
        "creatorUrl": metadata.get("author_url"),
        "seconds": seconds,
        "evidence": evidence,
        "evidenceType": evidence_type,
        "evidenceUrl": evidence_url,
        "availabilityMethod": "public_oembed",
    }
