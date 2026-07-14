from copy import deepcopy
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.providers.wikimedia import (
    commons_filename_from_url,
    fetch_verified_commons_image,
    is_recognized_free_license,
)


def _commons_response(*, license_name: str = "CC BY-SA 4.0") -> dict:
    return {
        "query": {
            "pages": [
                {
                    "pageid": 42,
                    "title": "File:Ada Lovelace portrait.jpg",
                    "imageinfo": [
                        {
                            "url": "https://upload.wikimedia.org/original.jpg",
                            "thumburl": "https://upload.wikimedia.org/thumb.jpg",
                            "descriptionurl": (
                                "https://commons.wikimedia.org/wiki/"
                                "File:Ada_Lovelace_portrait.jpg"
                            ),
                            "mime": "image/jpeg",
                            "width": 1200,
                            "height": 1600,
                            "extmetadata": {
                                "LicenseShortName": {"value": license_name},
                                "LicenseUrl": {
                                    "value": (
                                        "https://creativecommons.org/licenses/"
                                        "by-sa/4.0/"
                                    )
                                },
                                "Artist": {
                                    "value": "<a href='/wiki/User:Example'>Jane Doe</a>"
                                },
                                "Credit": {"value": "Wikimedia Commons"},
                                "UsageTerms": {"value": "Creative Commons BY-SA 4.0"},
                                "AttributionRequired": {"value": "true"},
                            },
                        }
                    ],
                }
            ]
        }
    }


def _mock_http_response(payload: dict) -> MagicMock:
    response = MagicMock()
    response.raise_for_status = MagicMock()
    response.json.return_value = payload
    return response


@pytest.mark.parametrize(
    ("url", "expected"),
    [
        (
            "https://commons.wikimedia.org/wiki/Special:FilePath/"
            "Ada_Lovelace_portrait.jpg",
            "Ada Lovelace portrait.jpg",
        ),
        (
            "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/"
            "Ada_Lovelace_portrait.jpg/800px-Ada_Lovelace_portrait.jpg",
            "Ada Lovelace portrait.jpg",
        ),
        ("https://example.com/Ada.jpg", None),
    ],
)
def test_commons_filename_from_url(url, expected):
    assert commons_filename_from_url(url) == expected


@pytest.mark.parametrize(
    ("name", "url", "expected"),
    [
        ("CC BY-SA 4.0", None, True),
        ("Public domain", None, True),
        ("CC0 1.0", None, True),
        ("CC BY-NC 4.0", None, False),
        ("Wikimedia", None, False),
        (
            None,
            "https://creativecommons.org/publicdomain/mark/1.0/",
            True,
        ),
    ],
)
def test_recognized_free_license(name, url, expected):
    assert is_recognized_free_license(name, url) is expected


@pytest.mark.asyncio
async def test_fetch_verified_commons_image_returns_exact_license_and_attribution():
    response = _mock_http_response(_commons_response())
    with patch("app.providers.wikimedia.httpx.AsyncClient") as client_class:
        client = AsyncMock()
        client.get = AsyncMock(return_value=response)
        client_class.return_value.__aenter__ = AsyncMock(return_value=client)
        client_class.return_value.__aexit__ = AsyncMock(return_value=None)

        result = await fetch_verified_commons_image("Ada Lovelace portrait.jpg")

    assert result is not None
    assert result.image_url == "https://upload.wikimedia.org/thumb.jpg"
    assert result.source_url.startswith("https://commons.wikimedia.org/wiki/File:")
    assert result.license_short_name == "CC BY-SA 4.0"
    assert result.license_url.endswith("/by-sa/4.0/")
    assert result.artist == "Jane Doe"
    assert result.credit == "Wikimedia Commons"
    assert result.attribution_required is True
    payload = result.as_photo_payload()
    assert payload["attribution"]["file_name"] == "Ada Lovelace portrait.jpg"
    assert payload["attribution"]["width"] == 1200


@pytest.mark.asyncio
async def test_fetch_verified_commons_image_rejects_unknown_license():
    payload = deepcopy(_commons_response(license_name="Wikimedia"))
    payload["query"]["pages"][0]["imageinfo"][0]["extmetadata"].pop(
        "LicenseUrl"
    )
    response = _mock_http_response(payload)
    with patch("app.providers.wikimedia.httpx.AsyncClient") as client_class:
        client = AsyncMock()
        client.get = AsyncMock(return_value=response)
        client_class.return_value.__aenter__ = AsyncMock(return_value=client)
        client_class.return_value.__aexit__ = AsyncMock(return_value=None)

        result = await fetch_verified_commons_image("Ada Lovelace portrait.jpg")

    assert result is None


@pytest.mark.asyncio
async def test_fetch_verified_commons_image_rejects_tiny_or_non_image_files():
    payload = deepcopy(_commons_response())
    image_info = payload["query"]["pages"][0]["imageinfo"][0]
    image_info["width"] = 128
    image_info["mime"] = "application/pdf"
    response = _mock_http_response(payload)
    with patch("app.providers.wikimedia.httpx.AsyncClient") as client_class:
        client = AsyncMock()
        client.get = AsyncMock(return_value=response)
        client_class.return_value.__aenter__ = AsyncMock(return_value=client)
        client_class.return_value.__aexit__ = AsyncMock(return_value=None)

        result = await fetch_verified_commons_image("Ada Lovelace portrait.jpg")

    assert result is None
