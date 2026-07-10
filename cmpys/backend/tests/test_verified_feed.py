"""Verified catalog content is preferred over generated feed filler."""
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.api.v1 import feed
from app.models.idol import CatalogStatus
from app.models.verified_quote import QuoteType, QuoteVerificationState, VerifiedQuote


class _ScalarRows:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows

    def __iter__(self):
        return iter(self._rows)


class _Result:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return _ScalarRows(self._rows)

    def all(self):
        return self._rows


class _ScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one(self):
        return self._value


class _OneResult:
    def __init__(self, value):
        self._value = value

    def one(self):
        return self._value


@pytest.mark.asyncio
async def test_materialize_verified_quote_preserves_text_and_provenance():
    quote = VerifiedQuote(
        id="11111111-1111-1111-1111-111111111111",
        speaker="Ada Lovelace",
        text="The engine might compose elaborate and scientific pieces of music.",
        normalized_hash="a" * 64,
        quote_type=QuoteType.SOURCED,
        category="Creativity",
        source_title="Ada Lovelace",
        source_url="https://en.wikiquote.org/wiki/Ada_Lovelace",
        source_reference="Notes on the Analytical Engine, 1843, p. 12",
        source_provider="wikiquote",
        confidence=0.92,
        status=CatalogStatus.PUBLISHED,
    )
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.side_effect = [_Result([quote]), _Result([])]

    posts = await feed._materialize_verified_quotes(db, limit=10)

    assert len(posts) == 1
    assert posts[0].content == quote.text
    assert posts[0].quote_id == quote.id
    assert posts[0].quote is quote
    assert posts[0].url == quote.source_url
    db.add.assert_called_once_with(posts[0])
    db.flush.assert_awaited_once()


@pytest.mark.asyncio
async def test_background_refill_skips_llm_when_catalog_fills_target():
    db = AsyncMock()
    context = AsyncMock()
    context.__aenter__.return_value = db
    generated = AsyncMock()

    with (
        patch("app.core.db.async_session_maker", return_value=context),
        patch.object(
            feed,
            "_materialize_verified_quotes",
            new=AsyncMock(return_value=[MagicMock() for _ in range(12)]),
        ),
        patch.object(feed, "_generate_and_persist", new=generated),
    ):
        await feed._background_refill("user-1")

    generated.assert_not_awaited()
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_quality_stats_exposes_daily_grounded_usage():
    db = AsyncMock()
    db.execute.side_effect = [
        _Result(
            [
                (QuoteVerificationState.SOURCE_BACKED, 10),
                (QuoteVerificationState.VERIFIED, 3),
            ]
        ),
        _ScalarResult(13),
        _OneResult((2, 642, 520, 2756, 4, 4205.4)),
        _Result(
            [
                (
                    "book_module_generation",
                    "gemini-2.5-flash",
                    3,
                    3,
                    900,
                    1800,
                    2700,
                    0.008,
                    12000.0,
                    0.94,
                ),
                (
                    "quote_verification",
                    "gemini-2.5-flash",
                    2,
                    2,
                    642,
                    520,
                    2756,
                    0.006,
                    4205.4,
                    None,
                ),
            ]
        ),
        _Result([("fast_canary", 1), ("balanced_holdout", 4)]),
        _ScalarResult(0.014),
        _ScalarResult(0.014),
        _Result([]),
    ]

    stats = await feed.get_feed_quality_stats(db, MagicMock())

    assert stats.quote_counts["source_backed"] == 10
    assert stats.quote_counts["verified"] == 3
    assert stats.quote_counts["rejected"] == 0
    assert stats.published_quotes == 13
    assert stats.verification_calls_today == 2
    assert stats.total_tokens_today == 2756
    assert stats.search_queries_today == 4
    assert stats.max_quotes_checked_per_day == stats.daily_call_limit * stats.batch_size
    assert stats.llm_usage_by_operation_today[0].operation == "book_module_generation"
    assert stats.llm_usage_by_operation_today[0].model == "gemini-2.5-flash"
    assert stats.llm_usage_by_operation_today[0].average_quality_score == 0.94
    assert stats.llm_usage_by_operation_today[0].estimated_cost_usd == 0.008
    assert stats.estimated_cost_usd_today == 0.014
    assert stats.background_estimated_cost_usd_today == 0.014
    assert stats.background_reserved_cost_usd == 0.0
    assert stats.background_budget_state == "normal"
    assert stats.routing_decisions_today["fast_canary"] == 1
