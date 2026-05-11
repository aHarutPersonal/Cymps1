"""Helpers for deduplicating reusable books, videos, and lessons."""
from __future__ import annotations

import re
import unicodedata
from collections.abc import Awaitable, Callable
from typing import Any
from urllib.parse import parse_qs, urlparse

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content_resource import ContentResource, ContentResourceKind, LicenseStatus
from app.models.plan import PlanItemContentResource

BookModuleFactory = Callable[..., Awaitable[dict[str, Any]]]
BookSourceLookup = Callable[..., Awaitable[dict[str, Any] | None]]
VideoResolver = Callable[[str], Awaitable[str | None]]


_YOUTUBE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")


def _slug(value: str | None, fallback: str = "unknown") -> str:
    text = unicodedata.normalize("NFKD", value or "").encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-zA-Z0-9]+", "_", text.lower()).strip("_")
    return text or fallback


def canonical_book_key(title: str, author: str | None = None) -> str:
    """Return a stable shared-resource key for a book title and author."""
    return f"book:{_slug(author)}:{_slug(title)}"


def _youtube_video_id(url: str | None) -> str | None:
    if not url:
        return None

    parsed = urlparse(url)
    host = parsed.netloc.lower().replace("www.", "")
    if host == "youtu.be":
        candidate = parsed.path.strip("/").split("/")[0]
        return candidate if _YOUTUBE_ID_RE.match(candidate) else None

    if host.endswith("youtube.com"):
        if parsed.path == "/watch":
            candidate = parse_qs(parsed.query).get("v", [None])[0]
            return candidate if candidate and _YOUTUBE_ID_RE.match(candidate) else None
        if parsed.path.startswith("/embed/") or parsed.path.startswith("/shorts/"):
            candidate = parsed.path.split("/")[2]
            return candidate if _YOUTUBE_ID_RE.match(candidate) else None

    return None


def canonical_youtube_key(url: str) -> str | None:
    """Return a stable key from a YouTube URL, ignoring tracking parameters."""
    video_id = _youtube_video_id(url)
    return f"youtube:{video_id}" if video_id else None


def canonical_video_query_key(query: str) -> str:
    """Return a stable key for an unresolved video search query."""
    return f"youtube_query:{_slug(query)}"


def _material_author(material: dict[str, Any]) -> str | None:
    for key in ("author", "author_or_creator", "creator", "source"):
        value = material.get(key)
        if value:
            return str(value)
    return None


def material_to_resource_payload(material: dict[str, Any]) -> dict[str, Any] | None:
    """Convert a plan material dict into a shared content resource payload."""
    title = str(material.get("title") or "").strip()
    if not title:
        return None

    raw_type = str(material.get("type") or "").lower()
    author = _material_author(material)
    metadata = {
        "reason": material.get("reason"),
        "search_query": material.get("search_query"),
    }

    if raw_type == "video":
        canonical_key = canonical_youtube_key(str(material.get("url") or ""))
        if not canonical_key:
            return None
        return {
            "kind": ContentResourceKind.VIDEO,
            "canonical_key": canonical_key,
            "title": title,
            "author_or_creator": author,
            "source_url": material.get("url"),
            "thumbnail_url": material.get("thumbnail_url"),
            "license_status": LicenseStatus.EXTERNAL_LINK,
            "duration_minutes": material.get("duration_minutes"),
            "summary_json": {"takeaways": material.get("takeaways", [])},
            "metadata_json": metadata,
        }

    if raw_type in {"book", "in_app_lesson"} and (
        material.get("ideas") or material.get("content_markdown")
    ):
        return {
            "kind": ContentResourceKind.LLM_BOOK_SUMMARY,
            "canonical_key": canonical_book_key(title, author),
            "title": title,
            "author_or_creator": author,
            "source_url": material.get("url"),
            "thumbnail_url": material.get("thumbnail_url"),
            "license_status": LicenseStatus.LLM_SUMMARY,
            "content_markdown": material.get("content_markdown"),
            "duration_minutes": material.get("duration_minutes") or 15,
            "summary_json": {
                "ideas": material.get("ideas", []),
                "promise": material.get("promise"),
                "sections": material.get("sections", []),
            },
            "metadata_json": metadata,
        }

    if raw_type in {"article", "course", "tool", "template", "in_app_lesson"}:
        return {
            "kind": ContentResourceKind.IN_APP_LESSON
            if raw_type == "in_app_lesson"
            else ContentResourceKind.ARTICLE,
            "canonical_key": f"{_slug(raw_type, 'article')}:{_slug(title)}",
            "title": title,
            "author_or_creator": author,
            "source_url": material.get("url"),
            "thumbnail_url": material.get("thumbnail_url"),
            "license_status": LicenseStatus.EXTERNAL_LINK
            if material.get("url")
            else LicenseStatus.UNKNOWN,
            "content_markdown": material.get("content_markdown"),
            "duration_minutes": material.get("duration_minutes"),
            "summary_json": {"ideas": material.get("ideas", [])},
            "metadata_json": metadata,
        }

    return None


async def get_or_create_content_resource(
    db: AsyncSession,
    *,
    kind: ContentResourceKind,
    canonical_key: str,
    title: str,
    license_status: LicenseStatus,
    author_or_creator: str | None = None,
    source_url: str | None = None,
    thumbnail_url: str | None = None,
    content_markdown: str | None = None,
    summary_json: dict | None = None,
    duration_minutes: int | None = None,
    metadata_json: dict | None = None,
) -> ContentResource:
    """Find or create a shared resource without duplicating canonical content."""
    result = await db.execute(
        select(ContentResource).where(ContentResource.canonical_key == canonical_key)
    )
    existing = result.scalar_one_or_none()
    if existing:
        return existing

    resource = ContentResource(
        kind=kind,
        canonical_key=canonical_key,
        title=title,
        author_or_creator=author_or_creator,
        source_url=source_url,
        thumbnail_url=thumbnail_url,
        license_status=license_status,
        content_markdown=content_markdown,
        summary_json=summary_json,
        duration_minutes=duration_minutes,
        metadata_json=metadata_json,
    )
    db.add(resource)
    await db.flush()
    return resource


async def generate_book_module(
    *,
    title: str,
    author: str | None,
    user_goal: str,
    source_context: str | None = None,
) -> dict[str, Any]:
    """Generate a reusable 15-minute book module via the configured LLM."""
    from app.services.llm.client import get_llm_client
    from app.services.llm.prompt_loader import load_and_render

    system_prompt = load_and_render("extractor_system.txt", {}, strict=False)
    user_prompt = load_and_render(
        "book_module_generate.txt",
        {
            "book_title": title,
            "author": author or "Unknown",
            "user_goal": user_goal,
            "source_context": source_context or "No source context available.",
        },
        strict=True,
    )
    client = get_llm_client(max_tokens=8000)
    response = await client.generate_json(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
    )
    if response.error:
        raise RuntimeError(response.error)
    return response.data


async def lookup_public_domain_book(
    *,
    title: str,
    author: str | None,
) -> dict[str, Any] | None:
    """Best-effort lookup for reusable public-domain book sources."""
    import httpx

    query = f"{title} {author or ''}".strip()
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.get(
                "https://gutendex.com/books/",
                params={"search": query, "mime_type": "text/plain"},
            )
            response.raise_for_status()
            data = response.json()
    except Exception:
        return None

    for item in data.get("results", [])[:5]:
        item_title = str(item.get("title") or "")
        authors = item.get("authors") or []
        author_names = [str(a.get("name")) for a in authors if a.get("name")]
        formats = item.get("formats") or {}
        text_url = next(
            (
                url
                for mime, url in formats.items()
                if mime.startswith("text/plain") and isinstance(url, str)
            ),
            None,
        )
        if not text_url:
            continue
        source_url = f"https://www.gutenberg.org/ebooks/{item.get('id')}"
        return {
            "title": item_title or title,
            "author_or_creator": ", ".join(author_names) or author,
            "source_url": source_url,
            "license_status": "public_domain",
            "content_markdown": (
                f"# {item_title or title}\n\n"
                f"This public-domain book is available for in-app reading via Project Gutenberg.\n\n"
                f"Source text: {text_url}"
            ),
            "summary_json": {
                "source": "project_gutenberg",
                "text_url": text_url,
                "subjects": item.get("subjects", []),
            },
            "duration_minutes": 15,
            "metadata_json": {
                "provider": "gutendex",
                "gutenberg_id": item.get("id"),
                "download_count": item.get("download_count"),
            },
        }

    return None


async def get_or_create_book_module_resource(
    db: AsyncSession,
    *,
    title: str,
    author: str | None,
    user_goal: str,
    source_context: str | None = None,
    source_lookup: BookSourceLookup | None = None,
    module_factory: BookModuleFactory | None = None,
) -> ContentResource:
    """Lookup or generate one reusable 15-minute book summary resource."""
    canonical_key = canonical_book_key(title, author)
    result = await db.execute(
        select(ContentResource).where(ContentResource.canonical_key == canonical_key)
    )
    existing = result.scalar_one_or_none()
    if existing:
        return existing

    lookup = source_lookup or lookup_public_domain_book
    source = await lookup(title=title, author=author)
    if source:
        license_status = (
            LicenseStatus.PUBLIC_DOMAIN
            if source.get("license_status") == "public_domain"
            else LicenseStatus.LICENSED
        )
        resource = ContentResource(
            kind=ContentResourceKind.PUBLIC_DOMAIN_BOOK
            if license_status == LicenseStatus.PUBLIC_DOMAIN
            else ContentResourceKind.LLM_BOOK_SUMMARY,
            canonical_key=canonical_key,
            title=str(source.get("title") or title),
            author_or_creator=source.get("author_or_creator") or author,
            source_url=source.get("source_url"),
            thumbnail_url=source.get("thumbnail_url"),
            license_status=license_status,
            content_markdown=source.get("content_markdown"),
            summary_json=source.get("summary_json"),
            duration_minutes=source.get("duration_minutes") or 15,
            metadata_json=source.get("metadata_json"),
        )
        db.add(resource)
        await db.flush()
        return resource

    factory = module_factory or generate_book_module
    module = await factory(
        title=title,
        author=author,
        user_goal=user_goal,
        source_context=source_context,
    )

    resource = ContentResource(
        kind=ContentResourceKind.LLM_BOOK_SUMMARY,
        canonical_key=canonical_key,
        title=str(module.get("title") or title),
        author_or_creator=str(module.get("author_or_creator") or author or ""),
        source_url=None,
        thumbnail_url=module.get("thumbnail_url"),
        license_status=LicenseStatus.LLM_SUMMARY,
        content_markdown=module.get("content_markdown"),
        summary_json={
            "promise": module.get("promise"),
            "sections": module.get("sections", []),
            "ideas": module.get("ideas", []),
        },
        duration_minutes=module.get("duration_minutes") or 15,
        metadata_json={
            "source": "llm_book_module",
            "user_goal_seed": user_goal,
        },
    )
    db.add(resource)
    await db.flush()
    return resource


async def resolve_youtube_url(query: str) -> str | None:
    """Resolve a video search query to a validated YouTube URL."""
    from app.services.tavily import _resolve_single_video

    return await _resolve_single_video(query)


async def get_or_create_video_resource(
    db: AsyncSession,
    *,
    title: str,
    search_query: str | None = None,
    url: str | None = None,
    author_or_creator: str | None = None,
    thumbnail_url: str | None = None,
    duration_minutes: int | None = None,
    reason: str | None = None,
    resolver: VideoResolver | None = None,
) -> ContentResource:
    """Lookup, resolve, or cache a reusable video resource."""
    query = (search_query or title).strip()
    resolved_url = url

    canonical_key = canonical_youtube_key(resolved_url or "")
    if not canonical_key and query:
        query_key = canonical_video_query_key(query)
        result = await db.execute(
            select(ContentResource).where(ContentResource.canonical_key == query_key)
        )
        existing_query_resource = result.scalar_one_or_none()
        if existing_query_resource:
            return existing_query_resource

        resolve = resolver or resolve_youtube_url
        resolved_url = await resolve(query)
        canonical_key = canonical_youtube_key(resolved_url or "")

    if canonical_key:
        result = await db.execute(
            select(ContentResource).where(ContentResource.canonical_key == canonical_key)
        )
        existing = result.scalar_one_or_none()
        if existing:
            return existing

        resource = ContentResource(
            kind=ContentResourceKind.VIDEO,
            canonical_key=canonical_key,
            title=title,
            author_or_creator=author_or_creator,
            source_url=resolved_url,
            thumbnail_url=thumbnail_url,
            license_status=LicenseStatus.EXTERNAL_LINK,
            duration_minutes=duration_minutes,
            summary_json={"takeaways": []},
            metadata_json={
                "reason": reason,
                "search_query": search_query,
                "resolved_from_query": bool(search_query and not url),
            },
        )
        db.add(resource)
        await db.flush()
        return resource

    resource = ContentResource(
        kind=ContentResourceKind.VIDEO,
        canonical_key=canonical_video_query_key(query or title),
        title=title,
        author_or_creator=author_or_creator,
        source_url=None,
        thumbnail_url=thumbnail_url,
        license_status=LicenseStatus.UNKNOWN,
        duration_minutes=duration_minutes,
        summary_json={"takeaways": []},
        metadata_json={
            "reason": reason,
            "search_query": search_query,
            "unavailable": True,
        },
    )
    db.add(resource)
    await db.flush()
    return resource


async def attach_content_resources_to_materials(
    db: AsyncSession,
    materials: list[dict[str, Any]],
    *,
    user_goal: str = "personal growth",
    book_source_lookup: BookSourceLookup | None = None,
    book_module_factory: BookModuleFactory | None = None,
    video_resolver: VideoResolver | None = None,
) -> list[dict[str, Any]]:
    """Annotate plan materials with reusable content_resource_id values."""
    enriched: list[dict[str, Any]] = []
    for material in materials:
        item = dict(material)
        payload = material_to_resource_payload(item)
        if payload:
            resource = await get_or_create_content_resource(db, **payload)
            item["content_resource_id"] = resource.id
            item["canonical_key"] = resource.canonical_key
        elif str(item.get("type") or "").lower() == "video":
            resource = await get_or_create_video_resource(
                db,
                title=str(item.get("title") or ""),
                search_query=item.get("search_query"),
                url=item.get("url"),
                author_or_creator=_material_author(item),
                thumbnail_url=item.get("thumbnail_url"),
                duration_minutes=item.get("duration_minutes"),
                reason=item.get("reason"),
                resolver=video_resolver,
            )
            item["content_resource_id"] = resource.id
            item["canonical_key"] = resource.canonical_key
            item["url"] = resource.source_url
            item["thumbnail_url"] = resource.thumbnail_url
            item["duration_minutes"] = resource.duration_minutes
            if resource.metadata_json:
                item["resource_unavailable"] = bool(resource.metadata_json.get("unavailable"))
        elif str(item.get("type") or "").lower() == "book":
            resource = await get_or_create_book_module_resource(
                db,
                title=str(item.get("title") or ""),
                author=_material_author(item),
                user_goal=user_goal,
                source_context=item.get("source_context") or item.get("reason"),
                source_lookup=book_source_lookup,
                module_factory=book_module_factory,
            )
            item["content_resource_id"] = resource.id
            item["canonical_key"] = resource.canonical_key
            item["url"] = resource.source_url
            item["thumbnail_url"] = resource.thumbnail_url
            item["license_status"] = (
                resource.license_status.value
                if hasattr(resource.license_status, "value")
                else str(resource.license_status)
            )
            item["content_markdown"] = resource.content_markdown
            item["duration_minutes"] = resource.duration_minutes
            if resource.summary_json:
                item["ideas"] = resource.summary_json.get("ideas", [])
                item["promise"] = resource.summary_json.get("promise")
                item["sections"] = resource.summary_json.get("sections", [])
        enriched.append(item)
    return enriched


async def sync_plan_item_content_resource_links(
    db: AsyncSession,
    *,
    plan_item_id: str,
    materials: list[dict[str, Any]],
) -> None:
    """Persist plan-material to shared-resource links for reuse/auditing."""
    await db.execute(
        delete(PlanItemContentResource).where(
            PlanItemContentResource.plan_item_id == plan_item_id
        )
    )

    for index, material in enumerate(materials):
        resource_id = material.get("content_resource_id")
        if not resource_id:
            continue

        db.add(
            PlanItemContentResource(
                plan_item_id=plan_item_id,
                content_resource_id=str(resource_id),
                material_index=index,
                material_type=str(material.get("type") or "")
                if material.get("type") is not None
                else None,
                title=str(material.get("title") or "")
                if material.get("title") is not None
                else None,
                canonical_key=str(material.get("canonical_key") or "")
                if material.get("canonical_key") is not None
                else None,
                metadata_json={
                    "reason": material.get("reason"),
                    "search_query": material.get("search_query"),
                    "resource_unavailable": material.get("resource_unavailable"),
                    "license_status": material.get("license_status"),
                },
            )
        )

    await db.flush()
