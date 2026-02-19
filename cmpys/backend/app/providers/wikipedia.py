"""
Wikipedia provider for fetching article content.

Uses the Wikipedia REST API and MediaWiki Action API.
"""
import re
from dataclasses import dataclass
from urllib.parse import quote, unquote

import httpx

# API endpoints
WIKIPEDIA_REST_API = "https://en.wikipedia.org/api/rest_v1"
WIKIPEDIA_ACTION_API = "https://en.wikipedia.org/w/api.php"

# Feature flags
ENABLE_HTML_SECTIONS = False


@dataclass
class WikipediaSummary:
    """Summary data from Wikipedia REST API."""

    title: str
    display_title: str
    extract: str
    url: str
    thumbnail_url: str | None = None


@dataclass
class WikipediaContent:
    """Full Wikipedia page content."""

    title: str
    url: str
    summary: str
    full_text: str
    thumbnail_url: str | None = None


# =============================================================================
# Public API Functions
# =============================================================================


def resolve_title_from_url(url: str) -> str | None:
    """
    Extract Wikipedia article title from URL.

    Handles URLs like:
    - https://en.wikipedia.org/wiki/Warren_Buffett
    - https://en.wikipedia.org/wiki/Elon_Musk#Early_life
    - https://en.wikipedia.org/w/index.php?title=Warren_Buffett

    Returns the title with underscores (e.g., "Warren_Buffett").
    """
    if not url:
        return None

    patterns = [
        r"wikipedia\.org/wiki/([^#?]+)",
        r"wikipedia\.org/w/index\.php\?title=([^&#]+)",
    ]

    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            title = match.group(1)
            # URL decode (handles %20, etc.) but keep underscores
            title = unquote(title)
            # Normalize spaces to underscores
            title = title.replace(" ", "_")
            return title

    return None


async def fetch_page_summary(title: str) -> WikipediaSummary | None:
    """
    Fetch page summary from Wikipedia REST API.

    GET https://en.wikipedia.org/api/rest_v1/page/summary/{title}

    Returns WikipediaSummary with:
    - title, display_title
    - extract (short summary)
    - url (canonical page URL)
    - thumbnail_url (optional)
    """
    encoded_title = _encode_title(title)

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(
                f"{WIKIPEDIA_REST_API}/page/summary/{encoded_title}",
                headers={
                    "Accept": "application/json",
                    "User-Agent": "cmpys/1.0 (https://github.com/cmpys)",
                },
            )
            response.raise_for_status()
            data = response.json()

            return WikipediaSummary(
                title=data.get("title", title),
                display_title=data.get("displaytitle", data.get("title", title)),
                extract=data.get("extract", ""),
                url=data.get("content_urls", {}).get("desktop", {}).get(
                    "page", f"https://en.wikipedia.org/wiki/{encoded_title}"
                ),
                thumbnail_url=data.get("thumbnail", {}).get("source"),
            )
        except httpx.HTTPStatusError:
            return None
        except Exception:
            return None


async def fetch_page_extract_plaintext(title: str) -> str | None:
    """
    Fetch full plaintext extract using MediaWiki TextExtracts API.

    GET https://en.wikipedia.org/w/api.php
    Query params:
    - action=query
    - format=json
    - prop=extracts
    - explaintext=1 (plaintext, not HTML)
    - exintro=0 (full article, not just intro)
    - redirects=1 (follow redirects)
    - titles={title}

    Returns the full article text as plaintext.
    """
    encoded_title = _encode_title(title)

    params = {
        "action": "query",
        "format": "json",
        "prop": "extracts",
        "explaintext": "1",
        "exintro": "0",
        "redirects": "1",
        "titles": encoded_title,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(
                WIKIPEDIA_ACTION_API,
                params=params,
                headers={
                    "User-Agent": "cmpys/1.0 (https://github.com/cmpys)",
                },
            )
            response.raise_for_status()
            data = response.json()

            # Extract the page content from response
            pages = data.get("query", {}).get("pages", {})
            for page_id, page_data in pages.items():
                if page_id != "-1":  # -1 means page not found
                    return page_data.get("extract", "")

            return None
        except httpx.HTTPStatusError:
            return None
        except Exception:
            return None


async def fetch_page_sections_html(title: str) -> str | None:
    """
    Fetch full page HTML using MediaWiki Parse API.

    GET https://en.wikipedia.org/w/api.php
    Query params:
    - action=parse
    - format=json
    - page={title}
    - prop=text

    Returns the full HTML content. Behind feature flag ENABLE_HTML_SECTIONS.
    """
    if not ENABLE_HTML_SECTIONS:
        return None

    encoded_title = _encode_title(title)

    params = {
        "action": "parse",
        "format": "json",
        "page": encoded_title,
        "prop": "text",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(
                WIKIPEDIA_ACTION_API,
                params=params,
                headers={
                    "User-Agent": "cmpys/1.0 (https://github.com/cmpys)",
                },
            )
            response.raise_for_status()
            data = response.json()

            return data.get("parse", {}).get("text", {}).get("*", "")
        except httpx.HTTPStatusError:
            return None
        except Exception:
            return None


async def fetch_wikipedia_content(
    wikipedia_url: str | None = None,
    title: str | None = None,
) -> WikipediaContent | None:
    """
    High-level function to fetch complete Wikipedia content.

    Combines summary and full extract APIs.

    Args:
        wikipedia_url: Full Wikipedia URL (e.g., https://en.wikipedia.org/wiki/Warren_Buffett)
        title: Article title (e.g., "Warren_Buffett" or "Warren Buffett")

    Returns:
        WikipediaContent with title, url, summary, and full_text
    """
    # Resolve title from URL if provided
    if wikipedia_url:
        resolved_title = resolve_title_from_url(wikipedia_url)
        if resolved_title:
            title = resolved_title

    if not title:
        return None

    # Normalize title
    title = title.replace(" ", "_")

    # Fetch summary
    summary = await fetch_page_summary(title)
    if not summary:
        return None

    # Fetch full plaintext extract
    full_text = await fetch_page_extract_plaintext(title)

    # Use summary extract as fallback if full text fails
    if not full_text:
        full_text = summary.extract

    if not full_text:
        return None

    return WikipediaContent(
        title=summary.display_title,
        url=summary.url,
        summary=summary.extract,
        full_text=full_text,
        thumbnail_url=summary.thumbnail_url,
    )


# =============================================================================
# Text Chunking
# =============================================================================


def chunk_text(
    text: str,
    min_size: int = 900,
    max_size: int = 1200,
) -> list[str]:
    """
    Split text into chunks of approximately min_size to max_size characters.

    Strategy:
    1. Split by paragraphs (double newlines)
    2. Accumulate paragraphs until reaching min_size
    3. If adding next paragraph exceeds max_size, start new chunk
    4. For very large paragraphs, fall back to sentence splitting
    """
    if not text or not text.strip():
        return []

    if len(text) <= max_size:
        return [text.strip()]

    chunks: list[str] = []
    current_chunk = ""

    # Split by paragraphs (double newlines or single newlines for section headers)
    paragraphs = re.split(r"\n\n+", text)

    for para in paragraphs:
        para = para.strip()
        if not para:
            continue

        potential_size = len(current_chunk) + len(para) + 2  # +2 for "\n\n"

        if potential_size > max_size:
            # Current chunk is big enough, save it
            if len(current_chunk) >= min_size:
                chunks.append(current_chunk.strip())
                current_chunk = para
            # Paragraph itself is too big, need to split it
            elif len(para) > max_size:
                # Save current chunk if non-empty
                if current_chunk.strip():
                    chunks.append(current_chunk.strip())
                    current_chunk = ""
                # Split large paragraph by sentences
                sentence_chunks = _split_by_sentences(para, min_size, max_size)
                if sentence_chunks:
                    chunks.extend(sentence_chunks[:-1])
                    current_chunk = sentence_chunks[-1]
            else:
                # Add to current chunk even if slightly over min_size
                current_chunk = f"{current_chunk}\n\n{para}" if current_chunk else para
        else:
            current_chunk = f"{current_chunk}\n\n{para}" if current_chunk else para

    # Don't forget the last chunk
    if current_chunk.strip():
        chunks.append(current_chunk.strip())

    return chunks


def _split_by_sentences(
    text: str,
    min_size: int,
    max_size: int,
) -> list[str]:
    """Split text by sentences to fit within size limits."""
    # Split on sentence boundaries (period, exclamation, question followed by space)
    sentences = re.split(r"(?<=[.!?])\s+", text)

    # If no sentence breaks found, fall back to word-based splitting
    if len(sentences) == 1 and len(text) > max_size:
        return _split_by_words(text, min_size, max_size)

    chunks: list[str] = []
    current = ""

    for sentence in sentences:
        potential_size = len(current) + len(sentence) + 1  # +1 for space

        if potential_size > max_size and len(current) >= min_size:
            chunks.append(current.strip())
            current = sentence
        else:
            current = f"{current} {sentence}" if current else sentence

    if current.strip():
        chunks.append(current.strip())

    return chunks


def _split_by_words(
    text: str,
    min_size: int,
    max_size: int,
) -> list[str]:
    """Split text by words as last resort for text without natural breaks."""
    words = text.split()
    chunks: list[str] = []
    current = ""

    for word in words:
        potential_size = len(current) + len(word) + 1

        if potential_size > max_size and len(current) >= min_size:
            chunks.append(current.strip())
            current = word
        else:
            current = f"{current} {word}" if current else word

    if current.strip():
        chunks.append(current.strip())

    return chunks


# =============================================================================
# Helper Functions
# =============================================================================


def _encode_title(title: str) -> str:
    """Encode title for URL, preserving underscores."""
    # Replace spaces with underscores
    title = title.replace(" ", "_")
    # URL encode special characters but preserve underscores
    return quote(title, safe="_")
