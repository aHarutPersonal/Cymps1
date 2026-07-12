import pytest

from app.services import tavily
from app.services.tavily import resolve_material_urls


@pytest.mark.asyncio
async def test_resolve_material_urls_preserves_video_search_query_when_unresolved(monkeypatch):
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
        raise AssertionError("grounded search should not run after a validated direct hit")

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
