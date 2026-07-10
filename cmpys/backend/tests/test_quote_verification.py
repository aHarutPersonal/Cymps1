"""Deterministic gates around grounded quote cross-checking."""
import json
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from app.core.config import settings
from app.models.idol import CatalogStatus
from app.models.ingest_job import IngestKind
from app.models.verified_quote import QuoteVerificationState, VerifiedQuote
from app.services.quote_verification import (
    GroundedSource,
    ModelQuoteCheck,
    VerificationVerdict,
    evaluate_quote_check,
    _parse_json_object,
    quote_text_similarity,
    verify_quote_batch,
)


def _quote() -> VerifiedQuote:
    return VerifiedQuote(
        id="11111111-1111-1111-1111-111111111111",
        speaker="Steve Jobs",
        text="Innovation distinguishes between a leader and a follower.",
        normalized_hash="a" * 64,
        source_url="https://en.wikiquote.org/wiki/Steve_Jobs",
        source_provider="wikiquote",
        status=CatalogStatus.PUBLISHED,
    )


def _result(verdict=VerificationVerdict.EXACT_MATCH, confidence=0.94):
    return ModelQuoteCheck(
        quote_id="11111111-1111-1111-1111-111111111111",
        verdict=verdict,
        confidence=confidence,
        canonical_text="Innovation distinguishes between a leader and a follower",
        evidence_title="Steve Jobs in The Innovation Secrets",
        evidence_url="https://example.edu/jobs-transcript",
        explanation="Exact wording appears in the archived transcript.",
    )


def test_similarity_ignores_case_and_punctuation():
    assert quote_text_similarity("Ideas matter!", "ideas matter") == 1.0


def test_grounded_json_parser_ignores_surrounding_search_prose():
    parsed = _parse_json_object(
        'Search complete. {"results": [{"quote_id": "q1"}]} Sources follow.'
    )

    assert parsed == {"results": [{"quote_id": "q1"}]}


def test_exact_match_requires_independent_grounded_source():
    evaluated = evaluate_quote_check(
        _quote(),
        _result(),
        [
            GroundedSource(
                title="Steve Jobs in The Innovation Secrets",
                url="https://example.edu/jobs-transcript",
            )
        ],
    )

    assert evaluated.state == QuoteVerificationState.VERIFIED
    assert evaluated.evidence_url == "https://example.edu/jobs-transcript"


def test_quote_aggregator_cannot_create_verified_badge():
    evaluated = evaluate_quote_check(
        _quote(),
        _result(),
        [
            GroundedSource(
                title="Steve Jobs - Wikiquote",
                url="https://vertexaisearch.cloud.google.com/grounding-api-redirect/x",
            )
        ],
    )

    assert evaluated.state == QuoteVerificationState.INCONCLUSIVE
    assert evaluated.evidence_url is None


def test_high_confidence_contradiction_flags_quote():
    evaluated = evaluate_quote_check(
        _quote(),
        _result(verdict=VerificationVerdict.CONTRADICTED, confidence=0.91),
        [
            GroundedSource(
                title="Authorship analysis from Example University",
                url="https://example.edu/quote-authorship",
            )
        ],
    )

    assert evaluated.state == QuoteVerificationState.REJECTED


@pytest.mark.asyncio
async def test_grounded_batch_records_usage_and_evaluates_results(monkeypatch):
    quote = _quote()
    response = SimpleNamespace(
        text=json.dumps(
            {
                "results": [
                    {
                        "quote_id": quote.id,
                        "verdict": "exact_match",
                        "confidence": 0.95,
                        "canonical_text": quote.text,
                        "evidence_title": "Steve Jobs archive transcript",
                        "evidence_url": "https://archive.example.org/jobs",
                        "explanation": "Exact text found in an archived transcript.",
                    }
                ]
            }
        ),
        usage_metadata=SimpleNamespace(
            prompt_token_count=220,
            candidates_token_count=80,
            total_token_count=300,
        ),
        candidates=[
            SimpleNamespace(
                grounding_metadata=SimpleNamespace(
                    grounding_chunks=[
                        SimpleNamespace(
                            web=SimpleNamespace(
                                title="Steve Jobs archive transcript",
                                uri="https://archive.example.org/jobs",
                            )
                        )
                    ],
                    web_search_queries=["Steve Jobs exact quote transcript"],
                )
            )
        ],
    )

    class _Models:
        config = None

        async def generate_content(self, **kwargs):
            self.config = kwargs["config"]
            return response

    models = _Models()
    fake_client = SimpleNamespace(aio=SimpleNamespace(models=models))
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    with patch("app.services.gemini._gemini_client", return_value=fake_client):
        run = await verify_quote_batch([quote])

    assert run.error is None
    assert run.results[0].state == QuoteVerificationState.VERIFIED
    assert run.prompt_tokens == 220
    assert run.completion_tokens == 80
    assert run.search_queries == 1
    assert models.config.response_mime_type is None
    assert IngestKind.QUOTE_VERIFICATION.value == "quote_verification"
