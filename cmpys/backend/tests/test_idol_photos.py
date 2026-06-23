from unittest.mock import AsyncMock

import pytest

from app.models.idol import Idol
from app.api.v1.idols import _idol_to_response
from app.services.idol_photos import get_or_resolve_idol_photo


@pytest.mark.asyncio
async def test_get_or_resolve_idol_photo_reuses_cached_photo():
    idol = Idol(
        name="Warren Buffett",
        domain="investing",
        image_url="https://upload.wikimedia.org/cached.jpg",
    )
    idol.image_license = "cc-by-sa"
    idol.image_source_url = "https://commons.wikimedia.org/wiki/File:Buffett.jpg"
    idol.image_attribution_json = {"artist": "Jane Doe"}

    async def resolver(**kwargs):
        raise AssertionError("resolver should not run when image is cached")

    result = await get_or_resolve_idol_photo(
        AsyncMock(),
        idol,
        resolver=resolver,
    )

    assert result["image_url"] == "https://upload.wikimedia.org/cached.jpg"
    assert result["license_status"] == "cc-by-sa"
    assert result["source_url"] == "https://commons.wikimedia.org/wiki/File:Buffett.jpg"
    assert result["attribution"]["artist"] == "Jane Doe"


@pytest.mark.asyncio
async def test_get_or_resolve_idol_photo_resolves_and_persists_when_missing():
    idol = Idol(name="Warren Buffett", domain="investing")
    db = AsyncMock()

    async def resolver(**kwargs):
        assert kwargs["name"] == "Warren Buffett"
        assert kwargs["wikidata_qid"] == "Q47213"
        assert kwargs["wikipedia_url"] == "https://en.wikipedia.org/wiki/Warren_Buffett"
        return {
            "image_url": "https://upload.wikimedia.org/resolved.jpg",
            "source_url": "https://commons.wikimedia.org/wiki/File:Resolved.jpg",
            "license_status": "cc-by-sa-4.0",
            "attribution": {
                "artist": "Wikimedia contributor",
                "credit": "Wikimedia Commons",
            },
        }

    result = await get_or_resolve_idol_photo(
        db,
        idol,
        wikidata_qid="Q47213",
        wikipedia_url="https://en.wikipedia.org/wiki/Warren_Buffett",
        resolver=resolver,
    )

    assert result["image_url"] == "https://upload.wikimedia.org/resolved.jpg"
    assert idol.image_url == "https://upload.wikimedia.org/resolved.jpg"
    assert idol.image_source_url == "https://commons.wikimedia.org/wiki/File:Resolved.jpg"
    assert idol.image_license == "cc-by-sa-4.0"
    assert idol.image_attribution_json["credit"] == "Wikimedia Commons"
    db.flush.assert_called_once()


def test_idol_response_includes_cached_photo_metadata():
    idol = Idol(
        id="idol-1",
        name="Ada Lovelace",
        domain="technology",
        image_url="https://upload.wikimedia.org/ada.jpg",
    )
    idol.image_source_url = "https://commons.wikimedia.org/wiki/File:Ada.jpg"
    idol.image_license = "public_domain"
    idol.image_attribution_json = {"artist": "Unknown"}
    idol.aliases = []
    idol.tag_links = []

    response = _idol_to_response(idol)

    assert response.image_url == "https://upload.wikimedia.org/ada.jpg"
    assert response.imageSourceUrl == "https://commons.wikimedia.org/wiki/File:Ada.jpg"
    assert response.imageLicense == "public_domain"
    assert response.imageAttribution["artist"] == "Unknown"
