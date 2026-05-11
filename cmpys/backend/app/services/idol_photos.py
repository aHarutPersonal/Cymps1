"""Reusable idol photo resolution and cache helpers."""
from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.idol import Idol

PhotoResolver = Callable[..., Awaitable[dict[str, Any] | None]]


def _cached_photo_payload(idol: Idol) -> dict[str, Any] | None:
    if not idol.image_url:
        return None
    return {
        "image_url": idol.image_url,
        "source_url": getattr(idol, "image_source_url", None),
        "license_status": getattr(idol, "image_license", None) or "unknown",
        "attribution": getattr(idol, "image_attribution_json", None) or {},
    }


async def resolve_wikimedia_photo(
    *,
    name: str,
    wikidata_qid: str | None = None,
    wikipedia_url: str | None = None,
    hints: list[str] | None = None,
) -> dict[str, Any] | None:
    """
    Resolve a real public idol image from Wikimedia/Wikipedia.

    Current strategy uses Wikipedia page summaries first because they expose a
    stable thumbnail/source pair. The attribution payload marks the image as a
    Wikimedia/Wikipedia-sourced candidate so the UI can display provenance and
    future passes can enrich license details from Commons.
    """
    from app.providers.wikipedia import fetch_page_summary, resolve_title_from_url

    title = resolve_title_from_url(wikipedia_url) if wikipedia_url else name
    summary = await fetch_page_summary(title)
    if not summary or not summary.thumbnail_url:
        return None

    return {
        "image_url": summary.thumbnail_url,
        "source_url": summary.url or wikipedia_url,
        "license_status": "wikimedia",
        "attribution": {
            "provider": "wikipedia",
            "title": summary.title,
            "wikidata_qid": wikidata_qid,
            "hints": hints or [],
            "license_note": "Image sourced from Wikimedia/Wikipedia page summary; verify Commons page for exact license before commercial use.",
        },
    }


async def get_or_resolve_idol_photo(
    db: AsyncSession,
    idol: Idol,
    *,
    wikidata_qid: str | None = None,
    wikipedia_url: str | None = None,
    hints: list[str] | None = None,
    resolver: PhotoResolver | None = None,
) -> dict[str, Any] | None:
    """Return cached idol photo metadata or resolve, persist, and reuse it."""
    cached = _cached_photo_payload(idol)
    if cached:
        return cached

    resolve = resolver or resolve_wikimedia_photo
    photo = await resolve(
        name=idol.name,
        wikidata_qid=wikidata_qid,
        wikipedia_url=wikipedia_url,
        hints=hints or [],
    )
    if not photo or not photo.get("image_url"):
        return None

    idol.image_url = str(photo["image_url"])
    idol.image_source_url = photo.get("source_url")
    idol.image_license = photo.get("license_status") or "unknown"
    idol.image_attribution_json = photo.get("attribution") or {}
    await db.flush()

    return _cached_photo_payload(idol)
