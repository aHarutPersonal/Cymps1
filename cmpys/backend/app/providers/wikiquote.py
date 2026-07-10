"""Conservative Wikiquote ingestion for the shared quote catalog.

Wikiquote is used as a discovery and provenance index, not as an authority by
itself. Only quote bullets that include a nested source/reference bullet are
returned. Ambiguous sections (Attributed, Disputed, Misattributed, etc.) are
discarded before anything can reach the published catalog.
"""
from __future__ import annotations

import html
import re
from dataclasses import dataclass
from urllib.parse import quote as url_quote

import httpx

from app.models.verified_quote import QuoteType

WIKIQUOTE_API_URL = "https://en.wikiquote.org/w/api.php"
WIKIQUOTE_PAGE_URL = "https://en.wikiquote.org/wiki/"
HEADERS = {
    "User-Agent": "CMPYS/1.0 (quote catalog; contact@cmpys.app) httpx",
}

_UNSAFE_SECTION_WORDS = {
    "apocryphal",
    "attributed",
    "disputed",
    "falsely attributed",
    "misattributed",
    "quotes about",
    "unsourced",
}
_NON_QUOTE_SECTION_WORDS = {
    "external links",
    "references",
    "see also",
}
_META_PREFIXES = (
    "as quoted in",
    "see also",
    "source:",
    "variant:",
    "variants:",
)
_ENGLISH_MARKERS = {
    "a",
    "and",
    "are",
    "as",
    "at",
    "be",
    "but",
    "by",
    "do",
    "for",
    "from",
    "have",
    "i",
    "if",
    "in",
    "is",
    "it",
    "my",
    "not",
    "of",
    "on",
    "one",
    "or",
    "our",
    "so",
    "that",
    "the",
    "their",
    "this",
    "to",
    "we",
    "what",
    "when",
    "with",
    "you",
    "your",
}
_SOURCE_SIGNAL_RE = re.compile(
    r"\b(book|chapter|diary|essay|interview|journal|letter|lecture|page|"
    r"speech|volume|vol\.?|work)\b|\b(?:18|19|20)\d{2}\b|\bp\.?\s*\d+",
    re.IGNORECASE,
)
_HEADING_RE = re.compile(r"^(={2,6})\s*(.*?)\s*\1\s*$")
_HTML_TAG_RE = re.compile(r"<[^>]+>")
_REF_RE = re.compile(r"<ref\b[^>]*>.*?</ref\s*>|<ref\b[^>]*/\s*>", re.I | re.S)
_TEMPLATE_RE = re.compile(r"\{\{[^{}]*\}\}")
_WIKILINK_RE = re.compile(r"\[\[(?:[^\]|]+\|)?([^\]]+)\]\]")
_EXTERNAL_LINK_RE = re.compile(r"\[https?://\S+\s+([^\]]+)\]")


@dataclass(frozen=True)
class WikiquotePage:
    title: str
    url: str
    wikitext: str


@dataclass(frozen=True)
class ParsedQuote:
    text: str
    source_reference: str
    source_title: str
    source_url: str
    section: str | None
    category: str
    quote_type: QuoteType
    confidence: float


def _clean_wikitext(value: str) -> str:
    """Remove common MediaWiki markup without trying to interpret templates."""
    value = _REF_RE.sub(" ", value)
    # Repeated passes handle shallow nested templates conservatively.
    for _ in range(4):
        cleaned = _TEMPLATE_RE.sub(" ", value)
        if cleaned == value:
            break
        value = cleaned
    value = _WIKILINK_RE.sub(r"\1", value)
    value = _EXTERNAL_LINK_RE.sub(r"\1", value)
    value = re.sub(r"\[https?://[^\]]+\]", " ", value)
    value = _HTML_TAG_RE.sub(" ", value)
    value = value.replace("'''", "").replace("''", "")
    value = html.unescape(value)
    value = re.sub(r"\s+", " ", value).strip(" \t\n-–—:")
    return value


def _section_is_unsafe(section_path: list[str]) -> bool:
    normalized = " / ".join(section_path).casefold()
    return any(word in normalized for word in _UNSAFE_SECTION_WORDS)


def _section_is_non_quote(section_path: list[str]) -> bool:
    normalized = " / ".join(section_path).casefold()
    return any(word in normalized for word in _NON_QUOTE_SECTION_WORDS)


def _looks_like_quote(text: str) -> bool:
    words = re.findall(r"\b[\w’'-]+\b", text, re.UNICODE)
    word_count = len(words)
    lowered = text.casefold()
    if not 6 <= word_count <= 45:
        return False
    if not 35 <= len(text) <= 340:
        return False
    if lowered.startswith(_META_PREFIXES):
        return False
    if text.count("http") or text.startswith(("File:", "Image:", "Category:")):
        return False
    # English Wikiquote often shows an original foreign-language line followed
    # by an English translation as a nested bullet. Do not label that original
    # line as English merely because the page itself is English.
    marker_count = len({word.casefold() for word in words} & _ENGLISH_MARKERS)
    if marker_count < 2:
        return False
    return True


def infer_quote_category(text: str) -> str:
    """Assign a stable broad category without paying for an LLM call."""
    words = set(re.findall(r"\b[\w'-]+\b", text.casefold(), re.UNICODE))
    categories = (
        (
            "Leadership",
            {"command", "leader", "leaders", "leadership", "serve", "service", "team"},
        ),
        (
            "Resilience",
            {
                "adversity",
                "courage",
                "fail",
                "failed",
                "failure",
                "fear",
                "perseverance",
                "persist",
            },
        ),
        (
            "Learning",
            {"education", "idea", "ideas", "knowledge", "learn", "learning", "think", "wisdom"},
        ),
        (
            "Creativity",
            {"art", "create", "created", "creative", "creativity", "imagination", "invent"},
        ),
        (
            "Work",
            {"discipline", "effort", "practice", "success", "successful", "work", "working"},
        ),
        (
            "Purpose",
            {"dream", "dreams", "future", "goal", "goals", "life", "meaning", "purpose"},
        ),
    )
    for category, keywords in categories:
        if words & keywords:
            return category
    return "Mindset"


def parse_wikiquote_page(page: WikiquotePage) -> list[ParsedQuote]:
    """Extract source-backed quote/reference pairs from Wikiquote wikitext."""
    section_path: list[str] = []
    parsed: list[ParsedQuote] = []
    pending_quote: str | None = None
    pending_reference_parts: list[str] = []
    pending_section: str | None = None

    def flush() -> None:
        nonlocal pending_quote, pending_reference_parts, pending_section
        reference = " ".join(part for part in pending_reference_parts if part).strip()
        if pending_quote and reference and _looks_like_quote(pending_quote):
            # A useful citation is more than a one-word label and contains a
            # recognizable work/date/page signal. Anything weaker stays out.
            reference_words = re.findall(r"\b[\w'-]+\b", reference, re.UNICODE)
            if len(reference_words) >= 3 and _SOURCE_SIGNAL_RE.search(reference):
                has_date = bool(re.search(r"\b(?:18|19|20)\d{2}\b", reference))
                has_locator = bool(
                    re.search(r"\b(?:chapter|page|p\.?\s*\d+|volume|vol\.?)\b", reference, re.I)
                )
                confidence = 0.92 if has_date and has_locator else 0.88 if has_date else 0.84
                parsed.append(
                    ParsedQuote(
                        text=pending_quote,
                        source_reference=reference,
                        source_title=page.title,
                        source_url=page.url,
                        section=pending_section,
                        category=infer_quote_category(pending_quote),
                        quote_type=QuoteType.SOURCED,
                        confidence=confidence,
                    )
                )
        pending_quote = None
        pending_reference_parts = []
        pending_section = None

    for raw_line in page.wikitext.splitlines():
        line = raw_line.strip()
        heading_match = _HEADING_RE.match(line)
        if heading_match:
            flush()
            level = len(heading_match.group(1))
            heading = _clean_wikitext(heading_match.group(2))
            depth = max(level - 2, 0)
            section_path = section_path[:depth]
            section_path.append(heading)
            continue

        if line.startswith("* "):
            flush()
            if _section_is_unsafe(section_path) or _section_is_non_quote(section_path):
                continue
            candidate = _clean_wikitext(line[2:])
            if _looks_like_quote(candidate):
                pending_quote = candidate
                pending_section = " / ".join(section_path) or None
            continue

        if pending_quote and line.startswith("**"):
            reference = _clean_wikitext(line.lstrip("*").strip())
            if reference:
                pending_reference_parts.append(reference)
            continue

        # A new list shape or prose paragraph ends the current quote record.
        if pending_quote and line and not line.startswith(("#", ":")):
            flush()

    flush()

    # A page sometimes repeats the same quote in multiple work sections.
    unique: dict[str, ParsedQuote] = {}
    for item in parsed:
        key = re.sub(r"\W+", "", item.text.casefold())
        previous = unique.get(key)
        if previous is None or item.confidence > previous.confidence:
            unique[key] = item
    return list(unique.values())


async def fetch_wikiquote_page(name: str) -> WikiquotePage | None:
    """Resolve a person name and fetch the current English Wikiquote wikitext."""
    params = {
        "action": "query",
        "prop": "revisions",
        "rvprop": "content",
        "rvslots": "main",
        "titles": name,
        "redirects": "1",
        "format": "json",
        "formatversion": "2",
    }
    async with httpx.AsyncClient(timeout=20.0, headers=HEADERS) as client:
        response = await client.get(WIKIQUOTE_API_URL, params=params)
        response.raise_for_status()
        data = response.json()

    pages = data.get("query", {}).get("pages", [])
    if not pages or pages[0].get("missing") is True:
        return None
    page_data = pages[0]
    revisions = page_data.get("revisions") or []
    if not revisions:
        return None
    wikitext = revisions[0].get("slots", {}).get("main", {}).get("content")
    if not isinstance(wikitext, str) or not wikitext.strip():
        return None
    title = str(page_data.get("title") or name)
    return WikiquotePage(
        title=title,
        url=f"{WIKIQUOTE_PAGE_URL}{url_quote(title.replace(' ', '_'), safe='')}",
        wikitext=wikitext,
    )
