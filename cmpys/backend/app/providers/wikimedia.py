"""Verified Wikimedia Commons image metadata.

The catalog never treats a thumbnail URL by itself as a licensed photo.  This
provider resolves the corresponding Commons file page and accepts it only when
the API returns an image with usable dimensions and an explicit free/public-
domain license.
"""
from __future__ import annotations

import html
import re
from dataclasses import dataclass
from typing import Any
from urllib.parse import unquote, urlparse

import httpx


COMMONS_API_URL = "https://commons.wikimedia.org/w/api.php"
HEADERS = {
    "User-Agent": "CMPYS/1.0 (idol photo catalog; contact@cmpys.app) httpx",
}
MIN_PHOTO_EDGE_PX = 256
_SUPPORTED_IMAGE_MIME_TYPES = frozenset(
    {"image/jpeg", "image/png", "image/webp"}
)
_HTML_TAG_RE = re.compile(r"<[^>]+>")


@dataclass(frozen=True)
class VerifiedWikimediaImage:
    """A Commons image whose file, dimensions, and license were verified."""

    file_name: str
    image_url: str
    source_url: str
    license_short_name: str
    license_url: str | None
    artist: str | None
    credit: str | None
    usage_terms: str | None
    attribution_required: bool | None
    mime_type: str
    width: int
    height: int

    def as_photo_payload(self) -> dict[str, Any]:
        return {
            "image_url": self.image_url,
            "source_url": self.source_url,
            "license_status": self.license_short_name,
            "attribution": {
                "provider": "wikimedia_commons",
                "file_name": self.file_name,
                "artist": self.artist,
                "credit": self.credit,
                "license": self.license_short_name,
                "license_url": self.license_url,
                "usage_terms": self.usage_terms,
                "attribution_required": self.attribution_required,
                "source_url": self.source_url,
                "mime_type": self.mime_type,
                "width": self.width,
                "height": self.height,
            },
        }


def _plain_text(value: Any, *, max_length: int = 2000) -> str | None:
    """Convert Commons extmetadata HTML into compact attribution text."""
    if value is None:
        return None
    text = html.unescape(_HTML_TAG_RE.sub(" ", str(value)))
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_length] or None


def _metadata_value(metadata: dict[str, Any], key: str) -> str | None:
    item = metadata.get(key)
    if isinstance(item, dict):
        item = item.get("value")
    return _plain_text(item)


def _safe_int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def is_recognized_free_license(
    license_short_name: str | None,
    license_url: str | None = None,
) -> bool:
    """Accept explicit Commons-compatible CC/CC0/public-domain licenses."""
    short = re.sub(
        r"[^a-z0-9]+",
        " ",
        str(license_short_name or "").casefold(),
    ).strip()
    url = str(license_url or "").casefold()

    # Non-commercial and no-derivatives variants are not suitable for a shared
    # product catalog even if a malformed Commons record happens to expose one.
    forbidden = (" noncommercial", " no derivatives", " nc", " nd")
    if any(token in f" {short}" for token in forbidden):
        return False
    if "/by-nc" in url or "/by-nd" in url or "/by-nc-nd" in url:
        return False

    if (
        "public domain" in short
        or short == "pd"
        or short.startswith("pd ")
        or short == "cc0"
        or short.startswith("cc0 ")
        or short.startswith("cc by ")
        or short.startswith("cc by sa ")
    ):
        return True

    parsed = urlparse(url)
    if parsed.scheme == "https" and parsed.hostname == "creativecommons.org":
        path = parsed.path.rstrip("/") + "/"
        return path.startswith(
            (
                "/licenses/by/",
                "/licenses/by-sa/",
                "/publicdomain/zero/",
                "/publicdomain/mark/",
            )
        )
    return False


def _is_https_host(url: str | None, host: str) -> bool:
    if not url:
        return False
    parsed = urlparse(url)
    return parsed.scheme == "https" and parsed.hostname == host


def commons_filename_from_url(url: str | None) -> str | None:
    """Recover a Commons filename from Special:FilePath or upload URLs."""
    if not url:
        return None
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in {
        "commons.wikimedia.org",
        "upload.wikimedia.org",
    }:
        return None

    parts = [unquote(part) for part in parsed.path.split("/") if part]
    if not parts:
        return None

    filename: str | None = None
    lowered = [part.casefold() for part in parts]
    if "special:filepath" in lowered:
        index = lowered.index("special:filepath")
        if index + 1 < len(parts):
            filename = parts[index + 1]
    elif "thumb" in lowered and len(parts) >= 2:
        # /wikipedia/commons/thumb/a/ab/File.jpg/800px-File.jpg
        filename = parts[-2]
    elif parsed.hostname == "upload.wikimedia.org":
        filename = parts[-1]

    if not filename:
        return None
    filename = filename.removeprefix("File:").replace("_", " ").strip()
    if not filename or "/" in filename or "\\" in filename:
        return None
    return filename


async def fetch_verified_commons_image(
    file_name: str,
    *,
    thumb_width: int = 1024,
) -> VerifiedWikimediaImage | None:
    """Fetch and validate one Commons file via ``imageinfo/extmetadata``."""
    normalized_name = str(file_name or "").removeprefix("File:").strip()
    if not normalized_name:
        return None

    params = {
        "action": "query",
        "format": "json",
        "formatversion": "2",
        "redirects": "1",
        "prop": "imageinfo",
        "iiprop": "url|mime|size|extmetadata",
        "iiurlwidth": str(max(thumb_width, MIN_PHOTO_EDGE_PX)),
        "titles": f"File:{normalized_name}",
    }
    try:
        async with httpx.AsyncClient(timeout=20.0, headers=HEADERS) as client:
            response = await client.get(COMMONS_API_URL, params=params)
            response.raise_for_status()
            data = response.json()
    except (httpx.HTTPError, ValueError, TypeError):
        return None

    pages = data.get("query", {}).get("pages", [])
    if not isinstance(pages, list) or not pages:
        return None
    page = pages[0]
    if page.get("missing") is not None:
        return None
    image_info_items = page.get("imageinfo") or []
    if not image_info_items:
        return None
    image_info = image_info_items[0]

    mime_type = str(image_info.get("mime") or "").casefold()
    width = _safe_int(image_info.get("width"))
    height = _safe_int(image_info.get("height"))
    if (
        mime_type not in _SUPPORTED_IMAGE_MIME_TYPES
        or width < MIN_PHOTO_EDGE_PX
        or height < MIN_PHOTO_EDGE_PX
    ):
        return None

    image_url = str(image_info.get("thumburl") or image_info.get("url") or "")
    source_url = str(image_info.get("descriptionurl") or "")
    if not _is_https_host(image_url, "upload.wikimedia.org"):
        return None
    if not _is_https_host(source_url, "commons.wikimedia.org"):
        return None

    extmetadata = image_info.get("extmetadata") or {}
    if not isinstance(extmetadata, dict):
        return None
    license_short_name = (
        _metadata_value(extmetadata, "LicenseShortName")
        or _metadata_value(extmetadata, "UsageTerms")
    )
    license_url = _metadata_value(extmetadata, "LicenseUrl")
    if not is_recognized_free_license(license_short_name, license_url):
        return None

    attribution_raw = _metadata_value(extmetadata, "AttributionRequired")
    attribution_required = None
    if attribution_raw is not None:
        attribution_required = attribution_raw.casefold() in {"1", "true", "yes"}

    artist = _metadata_value(extmetadata, "Artist")
    credit = _metadata_value(extmetadata, "Credit")
    if not artist and not credit:
        return None

    canonical_file_name = str(page.get("title") or f"File:{normalized_name}")
    canonical_file_name = canonical_file_name.removeprefix("File:")
    return VerifiedWikimediaImage(
        file_name=canonical_file_name,
        image_url=image_url,
        source_url=source_url,
        license_short_name=license_short_name or "",
        license_url=license_url,
        artist=artist,
        credit=credit,
        usage_terms=_metadata_value(extmetadata, "UsageTerms"),
        attribution_required=attribution_required,
        mime_type=mime_type,
        width=width,
        height=height,
    )
