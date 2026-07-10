"""Tests for conservative Wikiquote parsing and quote provenance models."""
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.models.idol import CatalogStatus
from app.models.ingest_job import IngestKind
from app.models.verified_quote import QuoteType, QuoteVerificationState, VerifiedQuote
from app.providers.wikiquote import (
    WikiquotePage,
    fetch_wikiquote_page,
    parse_wikiquote_page,
)


def _page(wikitext: str) -> WikiquotePage:
    return WikiquotePage(
        title="Ada Lovelace",
        url="https://en.wikiquote.org/wiki/Ada_Lovelace",
        wikitext=wikitext,
    )


def test_parser_keeps_only_quotes_with_specific_source_signals():
    parsed = parse_wikiquote_page(
        _page(
            """
== Notes ==
* The more I study, the more insatiable do I feel my genius for it to be.
** Letter to Charles Babbage, 10 July 1843, p. 4
* This sentence has enough words but its citation is too vague to publish safely.
** A letter
"""
        )
    )

    assert len(parsed) == 1
    assert parsed[0].text.startswith("The more I study")
    assert parsed[0].source_reference == "Letter to Charles Babbage, 10 July 1843, p. 4"
    assert parsed[0].quote_type == QuoteType.SOURCED
    assert parsed[0].confidence == 0.92


def test_parser_rejects_unsafe_sections_and_deduplicates_markup_variants():
    parsed = parse_wikiquote_page(
        _page(
            """
== Essays ==
* We may say most aptly that the Analytical Engine weaves algebraic patterns.
** ''Sketch of the Analytical Engine'', chapter 3 (1843)
* We may say most aptly that the [[Analytical Engine]] weaves algebraic patterns.
** ''Sketch of the Analytical Engine'', chapter 3 (1843)
== Misattributed ==
* This attractive but invented sentence should never be published as her own words.
** Popular internet collections, 2020
== Disputed ==
* This other doubtful sentence also has enough words to pass a length-only check.
** A biography, 1999, p. 8
"""
        )
    )

    assert len(parsed) == 1
    assert parsed[0].section == "Essays"
    assert "Analytical Engine" in parsed[0].text


def test_parser_does_not_mislabel_foreign_original_as_english():
    parsed = parse_wikiquote_page(
        _page(
            """
== Letters ==
* Un homme heureux est trop content du présent pour se soucier de l'avenir.
** Letter to a friend, 1901, p. 2
* A happy person is too satisfied with the present to worry about the future.
** English translation of a letter to a friend, 1901, p. 2
"""
        )
    )

    assert [item.text for item in parsed] == [
        "A happy person is too satisfied with the present to worry about the future."
    ]


def test_verified_quote_hash_normalizes_case_spacing_and_curly_quotes():
    first = VerifiedQuote.compute_hash("Ada Lovelace", "“Ideas   have shape.”")
    second = VerifiedQuote.compute_hash("ada lovelace", 'ideas have shape.')

    assert first == second
    assert IngestKind.QUOTE.value == "quote"


def test_verified_quote_defaults_are_not_published_implicitly():
    quote = VerifiedQuote(
        speaker="Ada Lovelace",
        text="A sufficiently long sourced quotation for a model default test.",
        normalized_hash="a" * 64,
        source_url="https://example.test/source",
        source_provider="test",
    )

    assert quote.status == CatalogStatus.PENDING
    assert quote.quote_type == QuoteType.ATTRIBUTED
    assert quote.verification_state == QuoteVerificationState.SOURCE_BACKED


@pytest.mark.asyncio
async def test_fetch_wikiquote_page_resolves_redirected_title():
    response = MagicMock()
    response.raise_for_status.return_value = None
    response.json.return_value = {
        "query": {
            "pages": [
                {
                    "title": "Ada Lovelace",
                    "revisions": [
                        {"slots": {"main": {"content": "== Notes ==\n* Quote"}}}
                    ],
                }
            ]
        }
    }
    client = AsyncMock()
    client.get.return_value = response
    context = AsyncMock()
    context.__aenter__.return_value = client

    with patch("app.providers.wikiquote.httpx.AsyncClient", return_value=context):
        page = await fetch_wikiquote_page("Augusta Ada King")

    assert page is not None
    assert page.title == "Ada Lovelace"
    assert page.url.endswith("Ada_Lovelace")
    params = client.get.await_args.kwargs["params"]
    assert params["redirects"] == "1"
