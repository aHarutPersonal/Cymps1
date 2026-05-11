import pytest

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
