"""Helpers for deduplicating reusable books, videos, and lessons."""
from __future__ import annotations

import asyncio
import json
import logging
import re
import unicodedata
from collections.abc import Awaitable, Callable
from difflib import SequenceMatcher
from typing import Any
from urllib.parse import parse_qs, urlparse

from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content_resource import ContentResource, ContentResourceKind, LicenseStatus
from app.models.idol import CatalogStatus
from app.models.plan import PlanItemContentResource
from app.services.content_quality import (
    EXPECTED_BOOK_HEADING_COUNT,
    EXPECTED_BOOK_PRACTICE_COUNT,
    MAX_BOOK_MODULE_WORDS,
    MAX_DUPLICATE_PARAGRAPH_RATIO,
    MAX_NEAR_DUPLICATE_PARAGRAPH_RATIO,
    MAX_REPEATED_SENTENCE_OPENING_RATIO,
    MIN_BOOK_MODULE_WORDS,
    build_book_retry_instruction,
    evaluate_book_module,
)

BookModuleFactory = Callable[..., Awaitable[dict[str, Any]]]
BookSourceLookup = Callable[..., Awaitable[dict[str, Any] | None]]
VideoResolver = Callable[[str], Awaitable[str | None]]


logger = logging.getLogger(__name__)

SHARED_BOOK_GOAL = (
    "Build an accurate, practical understanding of the book's central frameworks "
    "for a general adult reader. Keep the module reusable across users."
)
MAX_BOOK_SOURCE_CONTEXT_CHARS = 60_000

_YOUTUBE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")


class BookModuleSectionOutput(BaseModel):
    title: str
    summary: str
    exercise: str


class BookModuleIdeaOutput(BaseModel):
    title: str
    content: str
    category: str


class BookModuleOutput(BaseModel):
    """Native response schema for long Markdown embedded inside JSON."""

    title: str
    author_or_creator: str
    kind: str = "llm_book_summary"
    license_status: str = "llm_summary"
    duration_minutes: int = 15
    promise: str
    sections: list[BookModuleSectionOutput] = Field(min_length=6, max_length=6)
    ideas: list[BookModuleIdeaOutput] = Field(min_length=7, max_length=9)
    grounding_notes: list[str] = Field(default_factory=list)
    content_markdown: str


class BookModuleMetadataOutput(BaseModel):
    """Small repair schema that avoids regenerating a sound long-form lesson."""

    sections: list[BookModuleSectionOutput] = Field(min_length=6, max_length=6)
    ideas: list[BookModuleIdeaOutput] = Field(min_length=7, max_length=9)


def _book_core_is_sound(report: Any) -> bool:
    metrics = report.metrics
    section_count = int(metrics.get("section_count", 0))
    return (
        MIN_BOOK_MODULE_WORDS
        <= int(metrics.get("word_count", 0))
        <= MAX_BOOK_MODULE_WORDS
        and 5 <= section_count <= 7
        and 6 <= int(metrics.get("idea_count", 0)) <= 10
        and int(metrics.get("heading_count", 0)) == EXPECTED_BOOK_HEADING_COUNT
        and int(metrics.get("practice_block_count", 0))
        == EXPECTED_BOOK_PRACTICE_COUNT
        and int(metrics.get("closing_synthesis_count", 0)) == 1
        and int(metrics.get("filler_phrase_count", 0)) == 0
        and float(metrics.get("duplicate_paragraph_ratio", 0))
        <= MAX_DUPLICATE_PARAGRAPH_RATIO
        and float(metrics.get("near_duplicate_paragraph_ratio", 0))
        <= MAX_NEAR_DUPLICATE_PARAGRAPH_RATIO
        and (
            int(metrics.get("repeated_sentence_opening_count", 0)) < 4
            or float(metrics.get("repeated_sentence_opening_ratio", 0))
            <= MAX_REPEATED_SENTENCE_OPENING_RATIO
        )
    )


def _book_report_is_better(candidate: Any, current: Any) -> bool:
    """Prefer a passing rewrite even when two drafts have the same score.

    Some hard contracts (for example the exact Closing Synthesis heading) are
    intentionally binary and do not each carry a score penalty. Comparing only
    numeric scores could therefore keep a polished-looking but unpublishable
    draft over an equally scored draft that fixed the actual defect.
    """
    if bool(candidate.passed) != bool(current.passed):
        return bool(candidate.passed)
    if len(candidate.issues) != len(current.issues):
        return len(candidate.issues) < len(current.issues)
    return float(candidate.score) > float(current.score)


def _slug(value: str | None, fallback: str = "unknown") -> str:
    text = unicodedata.normalize("NFKD", value or "").encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-zA-Z0-9]+", "_", text.lower()).strip("_")
    return text or fallback


def canonical_book_key(title: str, author: str | None = None) -> str:
    """Return a stable shared-resource key for a book title and author."""
    return f"book:{_slug(author)}:{_slug(title)}"


def _book_identity_score(
    requested_title: str,
    requested_author: str | None,
    candidate_title: str,
    candidate_authors: list[str],
) -> float:
    """Score catalog metadata so a fuzzy provider result cannot poison the cache."""
    title_score = SequenceMatcher(
        None,
        _slug(requested_title),
        _slug(candidate_title),
    ).ratio()
    if not requested_author:
        return title_score
    requested_tokens = set(_slug(requested_author).split("_"))
    candidate_tokens = set(
        token
        for author in candidate_authors
        for token in _slug(author).split("_")
    )
    author_score = (
        len(requested_tokens & candidate_tokens) / len(requested_tokens | candidate_tokens)
        if requested_tokens and candidate_tokens
        else 0.0
    )
    return title_score * 0.75 + author_score * 0.25


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

    if raw_type == "book" and (
        material.get("ideas") or material.get("content_markdown")
    ):
        # A short plan-detail snippet is not a canonical book module. Returning
        # None sends it through the dedicated 3,200+ word generation/cache path.
        content_md = material.get("content_markdown", "") or ""
        word_count = len(content_md.split()) if content_md else 0
        if word_count < MIN_BOOK_MODULE_WORDS:
            return None
        calculated_duration = max(5, round(word_count / 200)) if word_count > 0 else (material.get("duration_minutes") or 15)

        return {
            "kind": ContentResourceKind.LLM_BOOK_SUMMARY,
            "canonical_key": canonical_book_key(title, author),
            "title": title,
            "author_or_creator": author,
            "source_url": material.get("url"),
            "thumbnail_url": material.get("thumbnail_url"),
            "license_status": LicenseStatus.LLM_SUMMARY,
            "content_markdown": content_md,
            "duration_minutes": calculated_duration,
            "summary_json": {
                "ideas": material.get("ideas", []),
                "promise": material.get("promise"),
                "sections": material.get("sections", []),
            },
            "metadata_json": metadata,
        }

    if raw_type in {"article", "course", "tool", "template", "in_app_lesson"}:
        # Do not manufacture an in-app resource from title/reason metadata.
        # External recommendations must keep opening their source URL unless
        # the generator supplied an actual lesson body or idea cards.
        if not (str(material.get("content_markdown") or "").strip() or material.get("ideas")):
            return None
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
    """Generate a reusable 16+ minute book module via the configured LLM."""
    from app.services.llm.client import get_llm_client
    from app.services.llm.prompt_loader import load_and_render
    from app.services.llm.routing import choose_llm_tier

    # Long-form guides use a dedicated nonfiction-editor voice. This preserves
    # the planner's source flexibility without inheriting its coaching tone.
    system_prompt = load_and_render("book_writer_system.txt", {}, strict=False)
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
    # This is long-form writing, not a reasoning task. A zero thinking budget
    # keeps latency and billed output tokens down without weakening the source
    # context or the explicit structure in the prompt.
    routing_decision = await choose_llm_tier(
        operation="book_module_generation",
        routing_key=canonical_book_key(title, author),
        default_tier="balanced",
    )
    active_tier = routing_decision.tier
    client = get_llm_client(
        timeout=180.0,
        max_tokens=16000,
        tier=active_tier,
        thinking_budget=0,
        temperature=0.2,
    )
    generation_calls: list[dict[str, Any]] = []

    def _record_call(
        stage: str,
        call_client: Any,
        call_response: Any,
        *,
        selected_tier: str,
        routing_reason: str,
    ) -> None:
        generation_calls.append(
            {
                "stage": stage,
                "selected_tier": selected_tier,
                "routing_reason": routing_reason,
                "model": getattr(call_response, "model", None)
                or getattr(call_client, "model", None),
                "provider": getattr(call_response, "provider", None),
                "prompt_tokens": getattr(call_response, "prompt_tokens", None),
                "completion_tokens": getattr(call_response, "completion_tokens", None),
                "total_tokens": getattr(call_response, "total_tokens", None),
                "duration_ms": getattr(call_response, "duration_ms", None),
                "succeeded": not bool(getattr(call_response, "error", None)),
                "error": getattr(call_response, "error", None),
            }
        )

    async def _persist_usage(result_status: str, quality_score: float | None) -> None:
        from app.services.llm.telemetry import (
            UsageRecord,
            infer_provider,
            record_usage_records,
        )

        records = [
            UsageRecord(
                operation="book_module_generation",
                model=str(call.get("model") or "unknown"),
                provider=str(call.get("provider") or infer_provider(call.get("model"))),
                prompt_tokens=call.get("prompt_tokens"),
                completion_tokens=call.get("completion_tokens"),
                total_tokens=call.get("total_tokens"),
                duration_ms=call.get("duration_ms"),
                success=bool(call.get("succeeded")),
                error_code="llm_error" if call.get("error") else None,
                result_status=call.get("result_status") or result_status,
                quality_score=(
                    call.get("quality_score")
                    if call.get("quality_score") is not None
                    else quality_score
                ),
                metadata={
                    "stage": call.get("stage"),
                    "selected_tier": call.get("selected_tier"),
                    "routing_reason": call.get("routing_reason"),
                    "book_title": title,
                    "author": author,
                },
            )
            for call in generation_calls
        ]
        await record_usage_records(records)

    response = await client.generate_json(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=BookModuleOutput,
    )
    _record_call(
        "draft",
        client,
        response,
        selected_tier=active_tier,
        routing_reason=routing_decision.reason,
    )
    if response.error:
        logger.warning(
            "[BOOK_MODULE] Structured response failed for '%s': %s. Retrying once.",
            title,
            response.error,
        )
        if active_tier == "fast":
            active_tier = "balanced"
            client = get_llm_client(
                timeout=180.0,
                max_tokens=16000,
                tier="balanced",
                thinking_budget=0,
                temperature=0.2,
            )
            recovery_reason = "fast_schema_fallback"
        else:
            recovery_reason = "balanced_schema_retry"
        response = await client.generate_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt
            + "\n\nJSON RECOVERY: Return one complete response matching the required schema. "
            "Do not truncate content_markdown and do not emit literal control characters.",
            output_model=BookModuleOutput,
        )
        _record_call(
            "json_recovery",
            client,
            response,
            selected_tier=active_tier,
            routing_reason=recovery_reason,
        )
        if response.error:
            await _persist_usage("generation_failed", None)
            raise RuntimeError(response.error)

    data = response.data
    report = evaluate_book_module(data, source_context=source_context)
    generation_calls[-1]["quality_score"] = report.score
    generation_calls[-1]["result_status"] = (
        "quality_passed" if report.passed else "quality_failed"
    )

    async def _repair_metadata_if_possible(
        current_data: dict[str, Any], current_report: Any
    ) -> tuple[dict[str, Any], Any]:
        factual_issue = (
            int(current_report.metrics.get("unmatched_attributed_quote_count", 0)) > 0
            or int(current_report.metrics.get("unmatched_year_count", 0)) >= 2
        )
        if (
            current_report.passed
            or factual_issue
            or not _book_core_is_sound(current_report)
        ):
            return current_data, current_report
        metadata_client = get_llm_client(
            timeout=60.0,
            max_tokens=5000,
            tier="fast",
            thinking_budget=0,
            temperature=0.1,
        )
        metadata_prompt = (
            "Repair the following book-module metadata so every section summary is 80-150 "
            "words, every section exercise is 40-80 words, and every idea content is 40-80 "
            "words. Preserve existing claims; add practical explanation and application, "
            "not new quotations, dates, anecdotes, or factual claims. Return JSON only.\n\n"
            "SECTIONS AND IDEAS:\n"
            + json.dumps(
                {
                    "sections": current_data.get("sections", []),
                    "ideas": current_data.get("ideas", []),
                },
                ensure_ascii=False,
            )
        )
        metadata_response = await metadata_client.generate_json(
            system_prompt="You edit learning metadata without changing its factual claims.",
            user_prompt=metadata_prompt,
            output_model=BookModuleMetadataOutput,
        )
        _record_call(
            "metadata_repair",
            metadata_client,
            metadata_response,
            selected_tier="fast",
            routing_reason="fixed_metadata_tier",
        )
        if metadata_response.error:
            return current_data, current_report
        candidate = dict(current_data)
        candidate["sections"] = metadata_response.data.get(
            "sections", current_data.get("sections", [])
        )
        candidate["ideas"] = metadata_response.data.get(
            "ideas", current_data.get("ideas", [])
        )
        candidate_report = evaluate_book_module(candidate, source_context=source_context)
        generation_calls[-1]["quality_score"] = candidate_report.score
        generation_calls[-1]["result_status"] = (
            "quality_passed" if candidate_report.passed else "quality_failed"
        )
        if _book_report_is_better(candidate_report, current_report):
            return candidate, candidate_report
        return current_data, current_report

    # A structurally sound long lesson should never be regenerated merely to
    # lengthen compact cards or summaries.
    data, report = await _repair_metadata_if_possible(data, report)

    # Retry once only when a deterministic, user-visible requirement failed.
    # The retry receives the exact failures, which is both cheaper and more
    # reliable than a generic "make it longer" instruction.
    if not report.passed:
        logger.warning(
            "[BOOK_MODULE] Quality gate failed for '%s' (score=%.3f): %s",
            title,
            report.score,
            "; ".join(report.issues),
        )
        retry_prompt = user_prompt + build_book_retry_instruction(report)
        if active_tier == "fast":
            active_tier = "balanced"
            client = get_llm_client(
                timeout=180.0,
                max_tokens=16000,
                tier="balanced",
                thinking_budget=0,
                temperature=0.2,
            )
            retry_reason = "fast_quality_fallback"
        else:
            retry_reason = "balanced_quality_retry"
        retry_response = await client.generate_json(
            system_prompt=system_prompt,
            user_prompt=retry_prompt,
            output_model=BookModuleOutput,
        )
        _record_call(
            "quality_retry",
            client,
            retry_response,
            selected_tier=active_tier,
            routing_reason=retry_reason,
        )
        if not retry_response.error:
            retry_report = evaluate_book_module(
                retry_response.data, source_context=source_context
            )
            generation_calls[-1]["quality_score"] = retry_report.score
            generation_calls[-1]["result_status"] = (
                "quality_passed" if retry_report.passed else "quality_failed"
            )
            if _book_report_is_better(retry_report, report):
                data = retry_response.data
                report = retry_report

    data, report = await _repair_metadata_if_possible(data, report)

    # Escalate only drafts that still fail after the economical Flash retry.
    # In a healthy pipeline this is a small minority, so Pro improves the tail
    # without becoming the default cost for every catalog item.
    if not report.passed:
        quality_client = get_llm_client(
            timeout=180.0,
            max_tokens=16000,
            tier="quality",
            temperature=0.15,
        )
        quality_response = await quality_client.generate_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt + build_book_retry_instruction(report),
            output_model=BookModuleOutput,
        )
        _record_call(
            "quality_fallback",
            quality_client,
            quality_response,
            selected_tier="quality",
            routing_reason="balanced_quality_fallback",
        )
        if not quality_response.error:
            quality_report = evaluate_book_module(
                quality_response.data, source_context=source_context
            )
            generation_calls[-1]["quality_score"] = quality_report.score
            generation_calls[-1]["result_status"] = (
                "quality_passed" if quality_report.passed else "quality_failed"
            )
            if _book_report_is_better(quality_report, report):
                data = quality_response.data
                report = quality_report

    # Recalculate duration from actual word count (200 wpm reading speed)
    md = data.get("content_markdown", "")
    word_count = len(md.split()) if md else 0
    if word_count > 0:
        data["duration_minutes"] = max(5, round(word_count / 200))
    report_data = report.to_dict()
    report_data["generation"] = {
        "call_count": len(generation_calls),
        "prompt_tokens": sum(int(call.get("prompt_tokens") or 0) for call in generation_calls),
        "completion_tokens": sum(
            int(call.get("completion_tokens") or 0) for call in generation_calls
        ),
        "total_tokens": sum(int(call.get("total_tokens") or 0) for call in generation_calls),
        "duration_ms": round(
            sum(float(call.get("duration_ms") or 0) for call in generation_calls),
            1,
        ),
        "calls": generation_calls,
    }
    data["quality_report"] = report_data
    await _persist_usage(
        "quality_passed" if report.passed else "quality_failed",
        report.score,
    )

    return data


def _strip_gutenberg_boilerplate(text: str) -> str:
    """Remove the common Project Gutenberg header/footer when markers exist."""
    upper = text.upper()
    start_marker = "*** START OF THE PROJECT GUTENBERG EBOOK"
    end_marker = "*** END OF THE PROJECT GUTENBERG EBOOK"
    start = upper.find(start_marker)
    if start >= 0:
        line_end = text.find("\n", start)
        text = text[line_end + 1 :] if line_end >= 0 else text[start:]
        upper = text.upper()
    end = upper.find(end_marker)
    if end >= 0:
        text = text[:end]
    return text.strip()


def _sample_book_text(text: str, max_chars: int = MAX_BOOK_SOURCE_CONTEXT_CHARS) -> str:
    """Sample the whole book evenly so one prompt does not contain only chapter one."""
    cleaned = _strip_gutenberg_boilerplate(text)
    if len(cleaned) <= max_chars:
        return cleaned

    sample_count = 6
    chunk_size = max_chars // sample_count
    max_start = max(len(cleaned) - chunk_size, 0)
    starts = [round(i * max_start / (sample_count - 1)) for i in range(sample_count)]
    chunks = [cleaned[start : start + chunk_size] for start in starts]
    return "\n\n[... SOURCE SAMPLE ...]\n\n".join(chunks)


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

    candidates = []
    for item in data.get("results", [])[:8]:
        item_title = str(item.get("title") or "")
        authors = item.get("authors") or []
        author_names = [str(a.get("name")) for a in authors if a.get("name")]
        identity_score = _book_identity_score(title, author, item_title, author_names)
        if identity_score < 0.72:
            continue
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
        candidates.append((identity_score, item, item_title, author_names, text_url))

    for _, item, item_title, author_names, text_url in sorted(
        candidates, key=lambda candidate: candidate[0], reverse=True
    ):
        source_url = f"https://www.gutenberg.org/ebooks/{item.get('id')}"
        try:
            async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
                text_response = await client.get(text_url)
                text_response.raise_for_status()
                source_context = _sample_book_text(text_response.text)
        except Exception:
            # Metadata is still useful, but an ungrounded public-domain stub is
            # not a finished learning module and must never be published as one.
            source_context = ""
        return {
            "title": item_title or title,
            "author_or_creator": ", ".join(author_names) or author,
            "source_url": source_url,
            "license_status": "public_domain",
            "content_markdown": None,
            "source_context": source_context,
            "summary_json": {
                "source": "project_gutenberg",
                "text_url": text_url,
                "subjects": item.get("subjects", []),
            },
            "metadata_json": {
                "provider": "gutendex",
                "gutenberg_id": item.get("id"),
                "download_count": item.get("download_count"),
            },
        }

    return None


async def lookup_book_reference_context(
    *,
    title: str,
    author: str | None,
) -> dict[str, Any] | None:
    """Fetch free canonical metadata for a modern book from Google Books.

    The description verifies identity and themes; it is not treated as the full
    book. This small lookup improves title/author accuracy before the LLM call
    without paying for search grounding.
    """
    import httpx

    query = f'intitle:"{title}"' + (f' inauthor:"{author}"' if author else "")
    try:
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
            response = await client.get(
                "https://www.googleapis.com/books/v1/volumes",
                params={"q": query, "maxResults": 8, "printType": "books"},
            )
            response.raise_for_status()
            items = response.json().get("items", [])
    except Exception:
        return None

    ranked: list[tuple[float, dict[str, Any], dict[str, Any]]] = []
    for item in items:
        volume = item.get("volumeInfo") or {}
        candidate_title = str(volume.get("title") or "")
        candidate_authors = [str(value) for value in (volume.get("authors") or [])]
        score = _book_identity_score(title, author, candidate_title, candidate_authors)
        if score >= 0.72:
            ranked.append((score, item, volume))
    if not ranked:
        return None

    _, item, volume = max(ranked, key=lambda candidate: candidate[0])
    identifiers = {
        value.get("type"): value.get("identifier")
        for value in volume.get("industryIdentifiers") or []
        if value.get("type") and value.get("identifier")
    }
    description = re.sub(r"<[^>]+>", " ", str(volume.get("description") or ""))
    description = re.sub(r"\s+", " ", description).strip()
    source_context = (
        "GOOGLE BOOKS CATALOG METADATA (identity and overview only; not full source text):\n"
        f"Title: {volume.get('title') or title}\n"
        f"Authors: {', '.join(volume.get('authors') or ([author] if author else []))}\n"
        f"Publisher: {volume.get('publisher') or 'unknown'}\n"
        f"Published date: {volume.get('publishedDate') or 'unknown'}\n"
        f"Categories: {', '.join(volume.get('categories') or [])}\n"
        f"Catalog description: {description or 'not available'}"
    )
    return {
        "title": volume.get("title") or title,
        "author_or_creator": ", ".join(volume.get("authors") or []) or author,
        "source_url": volume.get("infoLink") or volume.get("canonicalVolumeLink"),
        "thumbnail_url": (volume.get("imageLinks") or {}).get("thumbnail"),
        "license_status": "llm_summary",
        "content_markdown": None,
        "source_context": source_context,
        "summary_json": {
            "source": "google_books",
            "categories": volume.get("categories") or [],
            "published_date": volume.get("publishedDate"),
        },
        "metadata_json": {
            "provider": "google_books",
            "google_books_id": item.get("id"),
            "isbn_10": identifiers.get("ISBN_10"),
            "isbn_13": identifiers.get("ISBN_13"),
        },
    }


async def lookup_book_source(
    *,
    title: str,
    author: str | None,
) -> dict[str, Any] | None:
    """Prefer full public-domain text, then fall back to canonical metadata."""
    public_domain, reference = await asyncio.gather(
        lookup_public_domain_book(title=title, author=author),
        lookup_book_reference_context(title=title, author=author),
    )
    if public_domain:
        return public_domain
    return reference


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
    """Lookup or generate one reusable long-form book guide resource."""
    canonical_key = canonical_book_key(title, author)
    result = await db.execute(
        select(ContentResource).where(ContentResource.canonical_key == canonical_key)
    )
    existing = result.scalar_one_or_none()
    if existing:
        existing_words = len((existing.content_markdown or "").split())
        existing_quality = (existing.metadata_json or {}).get("quality_report", {})
        if existing_words >= MIN_BOOK_MODULE_WORDS and (
            existing.status == CatalogStatus.PUBLISHED or existing_quality.get("passed")
        ):
            return existing

    async def _save(resource: ContentResource) -> ContentResource:
        """Replace a thin legacy row in place, preserving all foreign keys."""
        if existing is None:
            db.add(resource)
            await db.flush()
            return resource
        for column in (
            "kind",
            "title",
            "author_or_creator",
            "source_url",
            "thumbnail_url",
            "license_status",
            "content_markdown",
            "summary_json",
            "duration_minutes",
            "metadata_json",
            "status",
            "is_public_domain",
            "source_provider",
            "source_external_id",
            "read_minutes",
        ):
            value = getattr(resource, column)
            if column == "is_public_domain":
                value = bool(value)
            setattr(existing, column, value)
        await db.flush()
        return existing

    lookup = source_lookup or lookup_book_source
    source = await lookup(title=title, author=author)
    if source:
        source_md = source.get("content_markdown", "") or ""
        source_words = len(source_md.split()) if source_md else 0
        source_metadata = source.get("metadata_json") or {}
        source_external_id = (
            source_metadata.get("gutenberg_id")
            or source_metadata.get("google_books_id")
        )
        source_license = source.get("license_status")
        license_status = {
            "public_domain": LicenseStatus.PUBLIC_DOMAIN,
            "licensed": LicenseStatus.LICENSED,
            "external_link": LicenseStatus.EXTERNAL_LINK,
            "llm_summary": LicenseStatus.LLM_SUMMARY,
        }.get(source_license, LicenseStatus.UNKNOWN)

        # A provider result may be a complete licensed module, or merely a raw
        # source. Only complete modules bypass generation. This prevents the old
        # Gutenberg link stub from masquerading as a long-form reading.
        if source_words >= MIN_BOOK_MODULE_WORDS:
            source_duration = max(5, round(source_words / 200))
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
                content_markdown=source_md,
                summary_json=source.get("summary_json"),
                duration_minutes=source_duration,
                metadata_json=source.get("metadata_json"),
                status=CatalogStatus.PUBLISHED,
                is_public_domain=license_status == LicenseStatus.PUBLIC_DOMAIN,
                source_provider=source_metadata.get("provider"),
                source_external_id=str(source_external_id or "") or None,
                read_minutes=source_duration,
            )
            return await _save(resource)

        factory = module_factory or generate_book_module
        module = await factory(
            title=str(source.get("title") or title),
            author=source.get("author_or_creator") or author,
            user_goal=SHARED_BOOK_GOAL,
            source_context=(
                source.get("source_context")
                or source_md
                or source_context
                or (
                    "Only bibliographic metadata was available. Stay conservative and "
                    "do not invent scenes, quotations, chapter names, or author anecdotes."
                )
            ),
        )
        module_md = module.get("content_markdown", "") or ""
        module_words = len(module_md.split())
        module_duration = max(5, round(module_words / 200)) if module_words else 5
        quality_report = module.get("quality_report") or evaluate_book_module(module).to_dict()
        resource = ContentResource(
            kind=ContentResourceKind.PUBLIC_DOMAIN_BOOK
            if license_status == LicenseStatus.PUBLIC_DOMAIN
            else ContentResourceKind.LLM_BOOK_SUMMARY,
            canonical_key=canonical_key,
            title=str(module.get("title") or source.get("title") or title),
            author_or_creator=str(
                module.get("author_or_creator") or source.get("author_or_creator") or author or ""
            ),
            source_url=source.get("source_url"),
            thumbnail_url=source.get("thumbnail_url") or module.get("thumbnail_url"),
            license_status=license_status,
            content_markdown=module_md,
            summary_json={
                "promise": module.get("promise"),
                "sections": module.get("sections", []),
                "ideas": module.get("ideas", []),
                "grounding_notes": module.get("grounding_notes", []),
                **(source.get("summary_json") or {}),
            },
            duration_minutes=module_duration,
            metadata_json={
                **(source.get("metadata_json") or {}),
                "source": "source_grounded_book_module",
                "quality_report": quality_report,
            },
            status=CatalogStatus.PUBLISHED
            if quality_report.get("passed")
            else CatalogStatus.FLAGGED,
            is_public_domain=license_status == LicenseStatus.PUBLIC_DOMAIN,
            source_provider=source_metadata.get("provider"),
            source_external_id=str(source_external_id or "") or None,
            read_minutes=module_duration,
        )
        return await _save(resource)

    factory = module_factory or generate_book_module
    module = await factory(
        title=title,
        author=author,
        # Shared resources must not inherit the first requester's goal. A short
        # personalized wrapper can be generated elsewhere; the expensive core
        # module is neutral and reusable for every user.
        user_goal=SHARED_BOOK_GOAL,
        source_context=(
            source_context
            or (
                "No licensed source text was provided. Use only well-established concepts "
                "you are confident belong to this exact book. Do not invent quotations, "
                "chapter names, studies, scenes, or author anecdotes."
            )
        ),
    )

    # Calculate duration from actual word count (200 wpm reading speed)
    module_md = module.get("content_markdown", "") or ""
    module_words = len(module_md.split()) if module_md else 0
    module_duration = max(5, round(module_words / 200)) if module_words > 0 else (module.get("duration_minutes") or 15)

    quality_report = module.get("quality_report") or evaluate_book_module(module).to_dict()
    resource = ContentResource(
        kind=ContentResourceKind.LLM_BOOK_SUMMARY,
        canonical_key=canonical_key,
        title=str(module.get("title") or title),
        author_or_creator=str(module.get("author_or_creator") or author or ""),
        source_url=None,
        thumbnail_url=module.get("thumbnail_url"),
        license_status=LicenseStatus.LLM_SUMMARY,
        content_markdown=module_md,
        summary_json={
            "promise": module.get("promise"),
            "sections": module.get("sections", []),
            "ideas": module.get("ideas", []),
            "grounding_notes": module.get("grounding_notes", []),
        },
        duration_minutes=module_duration,
        metadata_json={
            "source": "llm_book_module",
            "quality_report": quality_report,
        },
        status=CatalogStatus.PUBLISHED
        if quality_report.get("passed")
        else CatalogStatus.FLAGGED,
        is_public_domain=False,
        read_minutes=module_duration,
    )
    return await _save(resource)


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


def enqueue_book_module_generation(
    *,
    title: str,
    author: str | None,
    user_goal: str,
    source_context: str | None,
) -> None:
    """Queue tracked, idempotent background generation of a shared book module."""
    from app.tasks.catalog import enqueue_catalog_book

    enqueue_catalog_book.apply_async(
        kwargs={
            "title": title,
            "author": author,
            "user_goal": user_goal,
            "source_context": source_context,
        },
        queue="catalog_control",
    )


def _material_video_query(item: dict[str, Any]) -> str:
    return str(item.get("search_query") or item.get("title") or "").strip()


def _material_cache_key(item: dict[str, Any], kind: str) -> str | None:
    """Canonical key a material would be cached under, computable without I/O."""
    if kind == "video":
        url_key = canonical_youtube_key(str(item.get("url") or ""))
        if url_key:
            return url_key
        query = _material_video_query(item)
        return canonical_video_query_key(query) if query else None
    if kind == "book":
        return canonical_book_key(str(item.get("title") or ""), _material_author(item))
    return None


def _apply_video_resource(item: dict[str, Any], resource: ContentResource) -> None:
    item["content_resource_id"] = resource.id
    item["canonical_key"] = resource.canonical_key
    item["url"] = resource.source_url
    item["thumbnail_url"] = resource.thumbnail_url
    item["duration_minutes"] = resource.duration_minutes
    if resource.metadata_json:
        item["resource_unavailable"] = bool(resource.metadata_json.get("unavailable"))


def _apply_book_resource(item: dict[str, Any], resource: ContentResource) -> None:
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


async def attach_content_resources_to_materials(
    db: AsyncSession,
    materials: list[dict[str, Any]],
    *,
    user_goal: str = "personal growth",
    book_source_lookup: BookSourceLookup | None = None,
    book_module_factory: BookModuleFactory | None = None,
    video_resolver: VideoResolver | None = None,
    defer_book_generation: bool = False,
) -> list[dict[str, Any]]:
    """Annotate plan materials with reusable content_resource_id values.

    Cached resources are resolved with a single IN query over the canonical
    keys, and the network/LLM work for cache misses runs concurrently. All
    AsyncSession access stays sequential (the session is not concurrency-safe).
    With defer_book_generation=True — the interactive request path — uncached
    book modules are enqueued to Celery instead of generated inline, and the
    material is returned without a content_resource_id.
    """
    items = [dict(material) for material in materials]

    payloads: dict[int, dict[str, Any]] = {}
    kinds: list[str] = []
    cache_keys: list[str | None] = []
    for index, item in enumerate(items):
        payload = material_to_resource_payload(item)
        material_type = str(item.get("type") or "").lower()
        if payload:
            payloads[index] = payload
            kinds.append("payload")
            cache_keys.append(payload["canonical_key"])
        elif material_type in {"video", "book"}:
            kinds.append(material_type)
            cache_keys.append(_material_cache_key(item, material_type))
        else:
            kinds.append("other")
            cache_keys.append(None)

    cached: dict[str, ContentResource] = {}
    wanted = sorted({key for key in cache_keys if key})
    if wanted:
        result = await db.execute(
            select(ContentResource).where(ContentResource.canonical_key.in_(wanted))
        )
        cached = {resource.canonical_key: resource for resource in result.scalars().all()}

    async def _prepare_book(
        title: str, author: str | None, source_context: str | None
    ) -> dict[str, Any]:
        lookup = book_source_lookup or lookup_book_source
        source = await lookup(title=title, author=author)
        if source is not None:
            source_md = source.get("content_markdown", "") or ""
            if len(source_md.split()) >= MIN_BOOK_MODULE_WORDS:
                return {"source": source, "module": None}
            factory = book_module_factory or generate_book_module
            module = await factory(
                title=str(source.get("title") or title),
                author=source.get("author_or_creator") or author,
                user_goal=SHARED_BOOK_GOAL,
                source_context=source.get("source_context") or source_md or (
                    "Only bibliographic metadata was available. Stay conservative and do not "
                    "invent scenes, quotations, chapter names, or author anecdotes."
                ),
            )
            return {"source": source, "module": module}
        factory = book_module_factory or generate_book_module
        module = await factory(
            title=title,
            author=author,
            user_goal=user_goal,
            source_context=source_context,
        )
        return {"source": None, "module": module}

    # Fan out the per-material network/LLM work for cache misses, deduplicated
    # by canonical key. These coroutines never touch the DB session.
    prep_coros: dict[str, Awaitable[Any]] = {}
    for index, item in enumerate(items):
        key = cache_keys[index]
        if not key or key in cached or key in prep_coros:
            continue
        kind = kinds[index]
        if kind == "video":
            query = _material_video_query(item)
            if not canonical_youtube_key(str(item.get("url") or "")) and query:
                resolve = video_resolver or resolve_youtube_url
                prep_coros[key] = resolve(query)
        elif kind == "book" and not defer_book_generation:
            prep_coros[key] = _prepare_book(
                str(item.get("title") or ""),
                _material_author(item),
                item.get("source_context") or item.get("reason"),
            )

    prepared: dict[str, Any] = {}
    if prep_coros:
        results = await asyncio.gather(*prep_coros.values())
        prepared = dict(zip(prep_coros.keys(), results))

    # Sequential DB phase: attach cached hits and persist prepared misses.
    for index, item in enumerate(items):
        kind = kinds[index]
        if kind == "other":
            continue
        key = cache_keys[index]
        resource = cached.get(key) if key else None

        if kind == "payload":
            if resource is None:
                resource = await get_or_create_content_resource(db, **payloads[index])
                cached[resource.canonical_key] = resource
            item["content_resource_id"] = resource.id
            item["canonical_key"] = resource.canonical_key
        elif kind == "video":
            if resource is None:

                async def _preresolved(
                    query: str, _url: str | None = prepared.get(key) if key else None
                ) -> str | None:
                    return _url

                resource = await get_or_create_video_resource(
                    db,
                    title=str(item.get("title") or ""),
                    search_query=item.get("search_query"),
                    url=item.get("url"),
                    author_or_creator=_material_author(item),
                    thumbnail_url=item.get("thumbnail_url"),
                    duration_minutes=item.get("duration_minutes"),
                    reason=item.get("reason"),
                    resolver=_preresolved,
                )
                cached[resource.canonical_key] = resource
            _apply_video_resource(item, resource)
        elif kind == "book":
            if resource is None and defer_book_generation:
                item["canonical_key"] = key
                enqueue_book_module_generation(
                    title=str(item.get("title") or ""),
                    author=_material_author(item),
                    user_goal=user_goal,
                    source_context=item.get("source_context") or item.get("reason"),
                )
                continue
            if resource is None:
                prep = prepared[key]

                async def _prepared_lookup(
                    _source: dict[str, Any] | None = prep["source"], **kwargs: Any
                ) -> dict[str, Any] | None:
                    return _source

                async def _prepared_factory(
                    _module: dict[str, Any] | None = prep["module"], **kwargs: Any
                ) -> dict[str, Any]:
                    return _module

                resource = await get_or_create_book_module_resource(
                    db,
                    title=str(item.get("title") or ""),
                    author=_material_author(item),
                    user_goal=user_goal,
                    source_context=item.get("source_context") or item.get("reason"),
                    source_lookup=_prepared_lookup,
                    module_factory=_prepared_factory,
                )
                cached[resource.canonical_key] = resource
            resource_words = len((resource.content_markdown or "").split())
            if (
                resource.status != CatalogStatus.PUBLISHED
                or resource_words < MIN_BOOK_MODULE_WORDS
            ):
                # Keep the recommendation, but never attach/serve a module that
                # still failed quality gates after the selective Pro fallback.
                item["canonical_key"] = resource.canonical_key
                item["resource_unavailable"] = True
                item["quality_status"] = (
                    resource.status.value
                    if hasattr(resource.status, "value")
                    else str(resource.status)
                )
                item["quality_word_count"] = resource_words
                if defer_book_generation:
                    enqueue_book_module_generation(
                        title=str(item.get("title") or ""),
                        author=_material_author(item),
                        user_goal=user_goal,
                        source_context=None,
                    )
                continue
            _apply_book_resource(item, resource)
    return items


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
