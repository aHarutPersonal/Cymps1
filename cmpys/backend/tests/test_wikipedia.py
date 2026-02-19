"""Unit tests for Wikipedia provider with mocked httpx responses."""
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.providers.wikipedia import (
    WikipediaContent,
    WikipediaSummary,
    chunk_text,
    fetch_page_extract_plaintext,
    fetch_page_summary,
    fetch_wikipedia_content,
    resolve_title_from_url,
)


class TestResolveTitleFromUrl:
    def test_standard_wiki_url(self):
        url = "https://en.wikipedia.org/wiki/Warren_Buffett"
        assert resolve_title_from_url(url) == "Warren_Buffett"

    def test_wiki_url_with_spaces_encoded(self):
        url = "https://en.wikipedia.org/wiki/Elon%20Musk"
        assert resolve_title_from_url(url) == "Elon_Musk"

    def test_wiki_url_with_anchor(self):
        url = "https://en.wikipedia.org/wiki/Warren_Buffett#Early_life"
        assert resolve_title_from_url(url) == "Warren_Buffett"

    def test_wiki_url_with_query_params(self):
        url = "https://en.wikipedia.org/wiki/Warren_Buffett?oldid=123"
        assert resolve_title_from_url(url) == "Warren_Buffett"

    def test_wiki_index_php_url(self):
        url = "https://en.wikipedia.org/w/index.php?title=Warren_Buffett"
        assert resolve_title_from_url(url) == "Warren_Buffett"

    def test_invalid_url(self):
        url = "https://example.com/not-wikipedia"
        assert resolve_title_from_url(url) is None

    def test_empty_url(self):
        assert resolve_title_from_url("") is None

    def test_none_url(self):
        assert resolve_title_from_url(None) is None


class TestChunkText:
    def test_small_text_no_chunking(self):
        text = "This is a small text."
        chunks = chunk_text(text, min_size=900, max_size=1200)
        assert len(chunks) == 1
        assert chunks[0] == text

    def test_empty_text(self):
        assert chunk_text("") == []
        assert chunk_text("   ") == []

    def test_chunk_by_paragraphs(self):
        # Create text with multiple paragraphs
        para1 = "A" * 500
        para2 = "B" * 500
        para3 = "C" * 500
        text = f"{para1}\n\n{para2}\n\n{para3}"

        chunks = chunk_text(text, min_size=900, max_size=1200)

        # Should split into multiple chunks based on paragraph boundaries
        assert len(chunks) >= 1
        total_chars = sum(len(c) for c in chunks)
        # Total should be approximately the same (minus some whitespace)
        assert total_chars >= 1400

    def test_respects_max_size(self):
        # Create a very long text without paragraphs
        text = "Word " * 500  # ~2500 chars
        chunks = chunk_text(text, min_size=900, max_size=1200)

        for chunk in chunks:
            # Should respect max_size with word-based splitting
            assert len(chunk) <= 1200

    def test_preserves_content(self):
        text = "First paragraph here.\n\nSecond paragraph here.\n\nThird paragraph here."
        chunks = chunk_text(text, min_size=10, max_size=50)

        # All content should be preserved across chunks
        joined = " ".join(chunks)
        assert "First paragraph" in joined
        assert "Second paragraph" in joined
        assert "Third paragraph" in joined


# Mock response data
MOCK_SUMMARY_RESPONSE = {
    "title": "Warren Buffett",
    "displaytitle": "Warren Buffett",
    "extract": "Warren Edward Buffett is an American businessman and philanthropist.",
    "content_urls": {
        "desktop": {
            "page": "https://en.wikipedia.org/wiki/Warren_Buffett"
        }
    },
    "thumbnail": {
        "source": "https://upload.wikimedia.org/thumbnail.jpg"
    }
}

MOCK_EXTRACT_RESPONSE = {
    "query": {
        "pages": {
            "12345": {
                "pageid": 12345,
                "title": "Warren Buffett",
                "extract": "Warren Edward Buffett (born August 30, 1930) is an American businessman, investor, and philanthropist. He is the chairman and CEO of Berkshire Hathaway."
            }
        }
    }
}

MOCK_EXTRACT_NOT_FOUND = {
    "query": {
        "pages": {
            "-1": {
                "title": "NonexistentPage",
                "missing": ""
            }
        }
    }
}


def create_mock_response(json_data, status_code=200):
    """Create a properly configured mock response."""
    mock_response = MagicMock()
    mock_response.json.return_value = json_data
    mock_response.status_code = status_code
    mock_response.raise_for_status = MagicMock()  # Use MagicMock, not AsyncMock
    return mock_response


class TestFetchPageSummary:
    @pytest.mark.asyncio
    async def test_successful_fetch(self):
        mock_response = create_mock_response(MOCK_SUMMARY_RESPONSE)

        with patch("app.providers.wikipedia.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(return_value=mock_response)
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await fetch_page_summary("Warren_Buffett")

            assert result is not None
            assert isinstance(result, WikipediaSummary)
            assert result.title == "Warren Buffett"
            assert result.display_title == "Warren Buffett"
            assert "businessman" in result.extract
            assert result.url == "https://en.wikipedia.org/wiki/Warren_Buffett"
            assert result.thumbnail_url == "https://upload.wikimedia.org/thumbnail.jpg"

    @pytest.mark.asyncio
    async def test_not_found(self):
        import httpx

        mock_response = MagicMock()
        mock_response.raise_for_status.side_effect = httpx.HTTPStatusError(
            "Not Found", request=MagicMock(), response=MagicMock()
        )

        with patch("app.providers.wikipedia.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(return_value=mock_response)
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await fetch_page_summary("NonexistentPageXYZ123")
            assert result is None


class TestFetchPageExtractPlaintext:
    @pytest.mark.asyncio
    async def test_successful_fetch(self):
        mock_response = create_mock_response(MOCK_EXTRACT_RESPONSE)

        with patch("app.providers.wikipedia.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(return_value=mock_response)
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await fetch_page_extract_plaintext("Warren_Buffett")

            assert result is not None
            assert "Warren Edward Buffett" in result
            assert "Berkshire Hathaway" in result

    @pytest.mark.asyncio
    async def test_page_not_found(self):
        mock_response = create_mock_response(MOCK_EXTRACT_NOT_FOUND)

        with patch("app.providers.wikipedia.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(return_value=mock_response)
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await fetch_page_extract_plaintext("NonexistentPage")
            assert result is None


class TestFetchWikipediaContent:
    @pytest.mark.asyncio
    async def test_with_url(self):
        mock_summary_response = create_mock_response(MOCK_SUMMARY_RESPONSE)
        mock_extract_response = create_mock_response(MOCK_EXTRACT_RESPONSE)

        with patch("app.providers.wikipedia.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(side_effect=[mock_summary_response, mock_extract_response])
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await fetch_wikipedia_content(
                wikipedia_url="https://en.wikipedia.org/wiki/Warren_Buffett"
            )

            assert result is not None
            assert isinstance(result, WikipediaContent)
            assert result.title == "Warren Buffett"
            assert "businessman" in result.summary
            assert "Berkshire Hathaway" in result.full_text

    @pytest.mark.asyncio
    async def test_with_title(self):
        mock_summary_response = create_mock_response(MOCK_SUMMARY_RESPONSE)
        mock_extract_response = create_mock_response(MOCK_EXTRACT_RESPONSE)

        with patch("app.providers.wikipedia.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(side_effect=[mock_summary_response, mock_extract_response])
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await fetch_wikipedia_content(title="Warren Buffett")

            assert result is not None
            assert result.title == "Warren Buffett"

    @pytest.mark.asyncio
    async def test_no_url_or_title(self):
        result = await fetch_wikipedia_content()
        assert result is None

    @pytest.mark.asyncio
    async def test_summary_fallback_when_extract_fails(self):
        mock_summary_response = create_mock_response(MOCK_SUMMARY_RESPONSE)
        mock_extract_response = create_mock_response(MOCK_EXTRACT_NOT_FOUND)

        with patch("app.providers.wikipedia.httpx.AsyncClient") as mock_client:
            mock_instance = AsyncMock()
            mock_instance.get = AsyncMock(side_effect=[mock_summary_response, mock_extract_response])
            mock_client.return_value.__aenter__ = AsyncMock(return_value=mock_instance)
            mock_client.return_value.__aexit__ = AsyncMock(return_value=None)

            result = await fetch_wikipedia_content(title="Warren_Buffett")

            # Should fall back to summary extract
            assert result is not None
            assert "businessman" in result.full_text
