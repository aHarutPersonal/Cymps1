"""Reusable idol photo resolution and cache helpers."""
from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any
from urllib.parse import urlparse

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.idol import Idol
from app.providers.wikimedia import (
    commons_filename_from_url,
    fetch_verified_commons_image,
    is_recognized_free_license,
)

PhotoResolver = Callable[..., Awaitable[dict[str, Any] | None]]


def _is_https_host(url: str | None, host: str) -> bool:
    if not url:
        return False
    parsed = urlparse(str(url))
    return parsed.scheme == "https" and parsed.hostname == host


def _is_verified_photo_metadata(
    *,
    image_url: str | None,
    source_url: str | None,
    license_status: str | None,
    attribution: Any,
) -> bool:
    """Require a real Commons file page, usable license, and attribution."""
    if not _is_https_host(image_url, "upload.wikimedia.org"):
        return False
    if not _is_https_host(source_url, "commons.wikimedia.org"):
        return False
    if "/wiki/file:" not in urlparse(str(source_url)).path.casefold():
        return False
    if not isinstance(attribution, dict) or not attribution:
        return False
    if not attribution.get("artist") and not attribution.get("credit"):
        return False
    license_url = attribution.get("license_url")
    return is_recognized_free_license(license_status, license_url)


def is_verified_idol_photo(idol: Idol) -> bool:
    """Return whether an idol has a source- and license-verified Commons photo."""
    return _is_verified_photo_metadata(
        image_url=getattr(idol, "image_url", None),
        source_url=getattr(idol, "image_source_url", None),
        license_status=getattr(idol, "image_license", None),
        attribution=getattr(idol, "image_attribution_json", None),
    )


def _cached_photo_payload(idol: Idol) -> dict[str, Any] | None:
    # Historical rows often contain only a raw P18/Special:FilePath URL.  That
    # is a useful resolution hint, but not proof of a license or attribution.
    if not is_verified_idol_photo(idol):
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

    Candidate filenames come from an existing P18 URL, Wikidata P18, or the
    Wikipedia lead thumbnail.  A candidate is returned only after Commons
    ``imageinfo/extmetadata`` verifies its file page, dimensions, MIME type,
    license, and attribution metadata.
    """
    from app.providers.wikipedia import fetch_page_summary, resolve_title_from_url

    candidate_names: list[str] = []
    for hint in hints or []:
        file_name = commons_filename_from_url(hint)
        if file_name and file_name not in candidate_names:
            candidate_names.append(file_name)

    resolved_wikipedia_url = wikipedia_url
    if wikidata_qid:
        try:
            from app.providers.wikidata import fetch_entity_by_id

            entity = await fetch_entity_by_id(wikidata_qid)
            if entity:
                file_name = str(entity.get("image_filename") or "").strip()
                if file_name and file_name not in candidate_names:
                    candidate_names.append(file_name)
                resolved_wikipedia_url = (
                    resolved_wikipedia_url or entity.get("wikipedia_url")
                )
        except Exception:
            # Wikipedia remains a provenance-preserving fallback.
            pass

    title = (
        resolve_title_from_url(resolved_wikipedia_url)
        if resolved_wikipedia_url
        else name
    )
    summary = None
    if title:
        summary = await fetch_page_summary(title)
        if summary and summary.thumbnail_url:
            file_name = commons_filename_from_url(summary.thumbnail_url)
            if file_name and file_name not in candidate_names:
                candidate_names.append(file_name)

    for file_name in candidate_names:
        verified = await fetch_verified_commons_image(file_name)
        if verified is None:
            continue
        payload = verified.as_photo_payload()
        payload["attribution"] = {
            **payload["attribution"],
            "wikidata_qid": wikidata_qid,
            "wikipedia_url": (
                summary.url if summary else resolved_wikipedia_url
            ),
        }
        return payload
    return None


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
    if not photo or not _is_verified_photo_metadata(
        image_url=photo.get("image_url"),
        source_url=photo.get("source_url"),
        license_status=photo.get("license_status"),
        attribution=photo.get("attribution"),
    ):
        return None

    idol.image_url = str(photo["image_url"])
    idol.image_source_url = photo.get("source_url")
    idol.image_license = photo.get("license_status") or "unknown"
    idol.image_attribution_json = photo.get("attribution") or {}
    await db.flush()

    return _cached_photo_payload(idol)
