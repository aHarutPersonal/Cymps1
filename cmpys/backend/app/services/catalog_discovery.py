"""Bounded, reproducible candidate discovery for idle catalog work.

Discovery only identifies trustworthy external catalog candidates. Persistence,
deduplication, idle admission, and LLM-budget checks stay in the catalog task so
the same tracked BOOK/IDOL jobs and publication quality gates remain authoritative.
"""
from __future__ import annotations

import hashlib
import logging
import random
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Awaitable, Callable
from urllib.parse import quote_plus, unquote, urlparse

import httpx

from app.models.ingest_job import IngestKind

logger = logging.getLogger(__name__)

GOOGLE_BOOKS_URL = "https://www.googleapis.com/books/v1/volumes"

# Broad non-fiction shelves keep the autonomous catalog useful for CMPYS while
# still producing variety. A time-bucket seed chooses both shelf and page.
BOOK_TOPICS = (
    "biography",
    "business",
    "communication",
    "creativity",
    "economics",
    "education",
    "history",
    "leadership",
    "personal finance",
    "philosophy",
    "psychology",
    "science",
    "technology",
)

# Public catalog search APIs occasionally throttle anonymous traffic. These
# identities are a bounded fallback, not source material: the normal book
# lookup and publication quality gates still run before a guide is visible.
CURATED_BOOK_FALLBACKS = (
    ("Meditations", "Marcus Aurelius", "philosophy"),
    ("The Art of War", "Sun Tzu", "leadership"),
    ("The Prince", "Niccolò Machiavelli", "leadership"),
    ("The Republic", "Plato", "philosophy"),
    ("The Wealth of Nations", "Adam Smith", "economics"),
    ("On the Origin of Species", "Charles Darwin", "science"),
    ("Walden", "Henry David Thoreau", "philosophy"),
    ("The Souls of Black Folk", "W. E. B. Du Bois", "history"),
    ("The Autobiography of Benjamin Franklin", "Benjamin Franklin", "biography"),
    (
        "Narrative of the Life of Frederick Douglass",
        "Frederick Douglass",
        "biography",
    ),
    ("How to Win Friends and Influence People", "Dale Carnegie", "communication"),
    ("Man's Search for Meaning", "Viktor E. Frankl", "psychology"),
    ("Thinking, Fast and Slow", "Daniel Kahneman", "psychology"),
    ("The Psychology of Money", "Morgan Housel", "personal finance"),
    ("Atomic Habits", "James Clear", "psychology"),
    ("Deep Work", "Cal Newport", "education"),
    ("Influence", "Robert B. Cialdini", "psychology"),
    ("The Design of Everyday Things", "Don Norman", "creativity"),
    ("The Innovator's Dilemma", "Clayton M. Christensen", "business"),
    ("The Lean Startup", "Eric Ries", "business"),
    ("Good to Great", "Jim Collins", "business"),
    ("Range", "David Epstein", "education"),
    ("Mindset", "Carol S. Dweck", "psychology"),
    ("The Righteous Mind", "Jonathan Haidt", "psychology"),
    ("Quiet", "Susan Cain", "psychology"),
    ("Factfulness", "Hans Rosling", "science"),
    ("The Black Swan", "Nassim Nicholas Taleb", "economics"),
    ("Essentialism", "Greg McKeown", "leadership"),
    ("Grit", "Angela Duckworth", "psychology"),
    ("Flow", "Mihaly Csikszentmihalyi", "psychology"),
)

# One narrow occupation per query is substantially kinder to the public
# Wikidata Query Service than a broad random-person query. Candidate order is
# randomized locally instead of using expensive SPARQL ORDER BY RAND().
IDOL_OCCUPATIONS = (
    ("arts", "Q33999"),  # actor
    ("business", "Q43845"),  # businessperson
    ("entrepreneurship", "Q131524"),  # entrepreneur
    ("engineering", "Q81096"),  # engineer
    ("investing", "Q806798"),  # investor
    ("leadership", "Q82955"),  # politician / public leader
    ("philanthropy", "Q2259451"),  # philanthropist
    ("science", "Q901"),  # scientist
    ("sports", "Q2066131"),  # athlete
    ("technology", "Q11774202"),  # programmer
    ("writing", "Q482980"),  # author
)

# Used only when the SPARQL discovery endpoint is unavailable. Every QID still
# goes through the direct Wikidata human/article/P18 checks and the Commons
# license verification performed by the idol-photo service before publication.
CURATED_IDOL_QIDS_BY_DOMAIN = {
    "arts": ("Q762", "Q882"),  # Leonardo da Vinci, Charlie Chaplin
    "business": ("Q5284", "Q19837", "Q47213"),  # Gates, Jobs, Buffett
    "entrepreneurship": ("Q19837", "Q5284"),
    "engineering": ("Q7259", "Q80"),  # Lovelace, Berners-Lee
    "investing": ("Q47213",),
    "leadership": ("Q8023", "Q32732"),  # Mandela, Yousafzai
    "philanthropy": ("Q5284", "Q32732"),
    "science": ("Q7186", "Q937", "Q9036", "Q7251"),
    "sports": ("Q11459", "Q25369", "Q36107"),
    "technology": ("Q80", "Q19837", "Q7259"),
    "writing": ("Q19526", "Q40909", "Q273210", "Q72334", "Q7197"),
}

_BOOK_GUIDE_FRAGMENTS = (
    "analysis of",
    "book summary",
    "key takeaways",
    "study guide",
    "summary and analysis",
    "workbook for",
)


@dataclass(frozen=True)
class BookDiscoveryCandidate:
    google_books_id: str
    title: str
    author: str
    source_url: str
    thumbnail_url: str | None
    description: str
    topic: str
    provider: str = "google_books"


@dataclass(frozen=True)
class IdolDiscoveryCandidate:
    wikidata_qid: str
    name: str
    domain: str
    birth_date: Any | None
    wikipedia_url: str
    image_url: str
    image_source_url: str
    image_license: str
    image_attribution: dict[str, Any]


def utc_time_bucket(
    now: datetime | None = None,
    *,
    interval_seconds: int,
) -> int:
    """Return a stable UTC bucket shared by Beat, selection, and tests."""
    current = now or datetime.now(timezone.utc)
    if current.tzinfo is None:
        current = current.replace(tzinfo=timezone.utc)
    width = max(int(interval_seconds), 60)
    return int(current.timestamp()) // width


def discovery_kind_for_bucket(bucket: int) -> IngestKind:
    """Strictly alternate books and idols across adjacent time buckets."""
    return IngestKind.BOOK if bucket % 2 == 0 else IngestKind.IDOL


def _rng(bucket: int, namespace: str) -> random.Random:
    # Do not use Python's process-randomized hash(); identical UTC buckets must
    # make identical choices in workers and deterministic tests.
    digest = hashlib.sha256(f"cmpys:{namespace}:{bucket}".encode()).digest()
    return random.Random(int.from_bytes(digest[:16], "big"))


def _clean_text(value: Any) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", str(value or ""))).strip()


def _looks_like_original_book(title: str) -> bool:
    folded = title.casefold()
    return not any(fragment in folded for fragment in _BOOK_GUIDE_FRAGMENTS)


def _parse_google_books_candidate(
    item: dict[str, Any],
    *,
    topic: str,
) -> BookDiscoveryCandidate | None:
    volume = item.get("volumeInfo") or {}
    title = _clean_text(volume.get("title"))
    authors = [_clean_text(value) for value in volume.get("authors") or []]
    authors = [value for value in authors if value]
    description = _clean_text(volume.get("description"))
    language = str(volume.get("language") or "").casefold()
    page_count = int(volume.get("pageCount") or 0)
    source_url = str(
        volume.get("canonicalVolumeLink") or volume.get("infoLink") or ""
    ).strip()
    google_books_id = str(item.get("id") or "").strip()

    # These fields form a conservative identity/grounding floor. The existing
    # book pipeline still performs its own exact metadata lookup and quality
    # gate before anything becomes visible.
    if (
        not google_books_id
        or not title
        or not authors
        or len(title) > 300
        or len(authors[0]) > 300
        or language != "en"
        or len(description) < 160
        or page_count < 80
        or not source_url.startswith("http")
        or not _looks_like_original_book(title)
    ):
        return None

    return BookDiscoveryCandidate(
        google_books_id=google_books_id,
        title=title,
        author=authors[0],
        source_url=source_url,
        thumbnail_url=(volume.get("imageLinks") or {}).get("thumbnail"),
        description=description,
        topic=topic,
    )


def _curated_book_candidates(
    *,
    bucket: int,
    limit: int,
) -> list[BookDiscoveryCandidate]:
    rng = _rng(bucket, "curated-books")
    entries = list(CURATED_BOOK_FALLBACKS)
    rng.shuffle(entries)
    description = (
        "Curated bibliographic fallback used only while live catalog search is "
        "unavailable. The normal source lookup, generation checks, and publication "
        "quality gate still run before this guide can become visible."
    )
    candidates: list[BookDiscoveryCandidate] = []
    for title, author, topic in entries[: max(1, min(int(limit), 20))]:
        identity = hashlib.sha256(f"{title}\0{author}".encode()).hexdigest()[:20]
        candidates.append(
            BookDiscoveryCandidate(
                google_books_id=f"curated:{identity}",
                title=title,
                author=author,
                source_url=(
                    "https://openlibrary.org/search?q="
                    f"{quote_plus(f'{title} {author}')}"
                ),
                thumbnail_url=None,
                description=description,
                topic=topic,
                provider="curated_fallback",
            )
        )
    return candidates


async def discover_google_books_candidates(
    *,
    bucket: int,
    limit: int = 12,
    client: httpx.AsyncClient | None = None,
) -> list[BookDiscoveryCandidate]:
    """Return a deterministic random slice of well-described English books."""
    rng = _rng(bucket, "google-books")
    topic = BOOK_TOPICS[rng.randrange(len(BOOK_TOPICS))]
    # Bounded pagination prevents an accidental unbounded catalog crawl while
    # rotating beyond the same first page of popular results.
    start_index = rng.randrange(4) * 40
    params = {
        "q": f"subject:{topic}",
        "langRestrict": "en",
        "maxResults": 40,
        "orderBy": "relevance",
        "printType": "books",
        "startIndex": start_index,
    }

    async def _request(active_client: httpx.AsyncClient) -> dict[str, Any]:
        response = await active_client.get(GOOGLE_BOOKS_URL, params=params)
        response.raise_for_status()
        return response.json()

    try:
        if client is None:
            async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as owned:
                data = await _request(owned)
        else:
            data = await _request(client)
    except (httpx.HTTPError, ValueError, TypeError) as exc:
        logger.warning("[CATALOG_DISCOVERY] Google Books lookup failed: %s", exc)
        return _curated_book_candidates(bucket=bucket, limit=limit)

    parsed = [
        candidate
        for item in data.get("items", [])
        if (candidate := _parse_google_books_candidate(item, topic=topic)) is not None
    ]
    rng.shuffle(parsed)
    if parsed:
        return parsed[: max(1, min(int(limit), 20))]
    return _curated_book_candidates(bucket=bucket, limit=limit)


def _commons_description_url(image_url: str) -> str:
    filename = unquote(urlparse(image_url).path.rsplit("/", 1)[-1]).replace(" ", "_")
    return f"https://commons.wikimedia.org/wiki/File:{filename}"


async def discover_wikidata_candidates(
    *,
    bucket: int,
    limit: int = 10,
    occupation_search: Callable[..., Awaitable[list[Any]]] | None = None,
    entity_fetch: Callable[[str], Awaitable[dict[str, Any] | None]] | None = None,
) -> list[IdolDiscoveryCandidate]:
    """Return notable, source-backed humans that already have a real P18 image."""
    from app.providers.wikidata import fetch_entity_by_id, search_by_occupations

    search = occupation_search or search_by_occupations
    fetch = entity_fetch or fetch_entity_by_id
    rng = _rng(bucket, "wikidata-idols")
    domain, occupation_qid = IDOL_OCCUPATIONS[
        rng.randrange(len(IDOL_OCCUPATIONS))
    ]
    try:
        discovered = list(await search([occupation_qid], limit=20))
    except Exception as exc:
        logger.warning("[CATALOG_DISCOVERY] Wikidata occupation lookup failed: %s", exc)
        discovered = []

    qids = [str(getattr(candidate, "externalId", "") or "") for candidate in discovered]
    if not qids:
        qids = list(CURATED_IDOL_QIDS_BY_DOMAIN.get(domain, ()))
    rng.shuffle(qids)
    candidates: list[IdolDiscoveryCandidate] = []
    # Entity enrichment is deliberately bounded. It verifies the QID and P18
    # image through the stable Wikidata API without fanning out indefinitely.
    for qid in qids[:10]:
        if not re.fullmatch(r"Q[1-9]\d*", qid):
            continue
        try:
            entity = await fetch(qid)
        except Exception as exc:
            logger.warning("[CATALOG_DISCOVERY] Wikidata entity %s failed: %s", qid, exc)
            continue
        if not entity:
            continue
        name = _clean_text(entity.get("name"))
        wikipedia_url = str(entity.get("wikipedia_url") or "").strip()
        image_url = str(entity.get("image_url") or "").strip()
        if not name or not wikipedia_url.startswith("https://en.wikipedia.org/"):
            continue
        if not image_url.startswith("https://commons.wikimedia.org/"):
            continue
        if len(name) > 255 or len(wikipedia_url) > 2048 or len(image_url) > 1024:
            continue
        candidates.append(
            IdolDiscoveryCandidate(
                wikidata_qid=qid,
                name=name,
                domain=domain,
                birth_date=entity.get("birth_date"),
                wikipedia_url=wikipedia_url,
                image_url=image_url,
                image_source_url=_commons_description_url(image_url),
                # Exact artist/license metadata is resolved by the idol-photo
                # service before an idle-discovered idol may remain published.
                image_license="wikimedia_pending_verification",
                image_attribution={
                    "provider": "wikidata",
                    "wikidata_qid": qid,
                    "credit": "Wikimedia Commons",
                    "verification_state": "pending",
                },
            )
        )
        if len(candidates) >= max(1, min(int(limit), 10)):
            break
    return candidates
