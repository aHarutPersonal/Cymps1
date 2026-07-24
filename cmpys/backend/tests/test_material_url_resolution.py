import pytest

from app.services import tavily
from app.services.tavily import resolve_material_urls


@pytest.mark.asyncio
async def test_resolve_material_urls_preserves_video_search_query_when_unresolved(
    monkeypatch,
):
    async def unresolved(query: str):
        return None

    monkeypatch.setattr("app.services.tavily._resolve_single_video", unresolved)

    materials = await resolve_material_urls(
        [
            {
                "title": "Margin of Safety",
                "type": "video",
                "search_query": "Warren Buffett margin of safety interview",
            }
        ]
    )

    assert materials[0]["url"] is None
    assert materials[0]["search_query"] == "Warren Buffett margin of safety interview"


@pytest.mark.asyncio
async def test_video_resolution_uses_validated_direct_search_before_gemini(monkeypatch):
    calls = []

    async def direct(query: str):
        calls.append(("direct", query))
        return "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    async def grounded(query: str):
        calls.append(("grounded", query))
        raise AssertionError(
            "grounded search should not run after a validated direct hit"
        )

    monkeypatch.setattr(tavily, "_search_video_via_youtube_api", direct)
    monkeypatch.setattr(tavily, "_search_video_via_google", grounded)

    result = await tavily._resolve_single_video("margin of safety interview")

    assert result == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    assert calls == [("direct", "margin of safety interview")]


@pytest.mark.asyncio
async def test_video_resolution_falls_back_to_gemini_after_direct_miss(monkeypatch):
    calls = []

    async def direct(query: str):
        calls.append("direct")
        return None

    async def grounded(query: str):
        calls.append("grounded")
        return "https://www.youtube.com/watch?v=abcdefghijk"

    monkeypatch.setattr(tavily, "_search_video_via_youtube_api", direct)
    monkeypatch.setattr(tavily, "_search_video_via_google", grounded)

    result = await tavily._resolve_single_video("obscure mentor lecture")

    assert result == "https://www.youtube.com/watch?v=abcdefghijk"
    assert calls == ["direct", "grounded"]


def test_direct_youtube_result_must_match_title_or_creator() -> None:
    relevant = {
        "title": "Warren Buffett Explains the Margin of Safety",
        "author_name": "Value Investing Archive",
    }
    irrelevant = {
        "title": "Relaxing Jazz Music for Study",
        "author_name": "Ambient Channel",
    }

    query = "Warren Buffett margin of safety interview"
    assert tavily._oembed_matches_query(relevant, query) is True
    assert tavily._oembed_matches_query(irrelevant, query) is False


@pytest.mark.asyncio
async def test_non_video_resolution_returns_exact_tavily_page(monkeypatch) -> None:
    async def search(query: str):
        assert '"Deep Work"' in query
        assert '"Cal Newport"' in query
        return [
            {
                "title": "Deep Work by Cal Newport",
                "url": "https://calnewport.com/deep-work/?utm_source=test",
                "content": "Deep Work is a book by Cal Newport.",
                "score": 0.92,
            }
        ]

    monkeypatch.setattr(tavily, "_tavily_search", search)

    result = await resolve_material_urls(
        [
            {
                "title": "Deep Work",
                "type": "book",
                "author_or_creator": "Cal Newport",
                "search_query": "Deep Work Cal Newport",
            }
        ]
    )

    assert result[0]["url"] == "https://calnewport.com/deep-work/"
    assert result[0]["url_resolution_status"] == "resolved"
    assert result[0]["url_provider"] == "tavily"


@pytest.mark.asyncio
async def test_search_pages_are_rejected_instead_of_used_as_fallback(
    monkeypatch,
) -> None:
    async def search(query: str):
        return [
            {
                "title": "Deep Work by Cal Newport",
                "url": "https://www.google.com/search?q=deep+work",
                "content": "Deep Work Cal Newport",
                "score": 0.99,
            },
            {
                "title": "Search for Deep Work",
                "url": "https://www.amazon.com/s?k=deep+work",
                "content": "Deep Work Cal Newport",
                "score": 0.98,
            },
        ]

    monkeypatch.setattr(tavily, "_tavily_search", search)

    result = await resolve_material_urls(
        [
            {
                "title": "Deep Work",
                "type": "book",
                "author_or_creator": "Cal Newport",
            }
        ]
    )

    assert result[0]["url"] is None
    assert result[0]["url_resolution_status"] == "unresolved"
    assert "google.com/search" not in str(result[0])
    assert "amazon.com/s" not in str(result[0])


@pytest.mark.asyncio
async def test_book_review_is_not_mistaken_for_the_book_page(monkeypatch) -> None:
    async def search(query: str):
        return [
            {
                "title": "Deep Work by Cal Newport Review and Summary",
                "url": "https://example.com/deep-work-review",
                "content": "Deep Work Cal Newport",
                "score": 0.99,
            }
        ]

    monkeypatch.setattr(tavily, "_tavily_search", search)

    result = await resolve_material_urls(
        [
            {
                "title": "Deep Work",
                "type": "book",
                "author_or_creator": "Cal Newport",
            }
        ]
    )

    assert result[0]["url"] is None


@pytest.mark.parametrize(
    "url",
    [
        "javascript:alert(1)",
        "http://localhost/resource",
        "http://127.0.0.1/resource",
        "https://www.coursera.org/search?query=analytics",
        "https://www.youtube.com/results?search_query=analytics",
    ],
)
def test_direct_resource_url_guard_rejects_unsafe_or_search_urls(url: str) -> None:
    assert tavily.is_direct_resource_url(url) is False


def test_direct_resource_url_guard_accepts_exact_pages() -> None:
    assert tavily.is_direct_resource_url(
        "https://www.coursera.org/learn/wharton-business-analytics"
    )
