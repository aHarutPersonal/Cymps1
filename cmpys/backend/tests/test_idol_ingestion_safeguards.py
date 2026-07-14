from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError

from app.models.idol import Idol
from app.services.idol_photos import get_or_resolve_idol_photo, is_verified_idol_photo
from app.services.llm.schemas import Evidence
from app.tasks.ingestion import (
    _delete_existing_timeline_records,
    _filter_valid_source_evidence,
    _idol_catalog_quality,
    _retain_evidence_backed_items,
)


def _verified_attribution() -> dict:
    return {
        "provider": "wikimedia_commons",
        "artist": "Jane Doe",
        "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
    }


def test_raw_image_url_is_not_a_verified_photo():
    idol = Idol(
        name="Ada Lovelace",
        domain="technology",
        image_url=(
            "https://commons.wikimedia.org/wiki/Special:FilePath/"
            "Ada_Lovelace_portrait.jpg"
        ),
    )

    assert is_verified_idol_photo(idol) is False


def test_exact_commons_source_license_and_attribution_are_verified():
    idol = Idol(
        name="Ada Lovelace",
        domain="technology",
        image_url="https://upload.wikimedia.org/ada.jpg",
        image_source_url="https://commons.wikimedia.org/wiki/File:Ada.jpg",
        image_license="CC BY-SA 4.0",
        image_attribution_json=_verified_attribution(),
    )

    assert is_verified_idol_photo(idol) is True


@pytest.mark.asyncio
async def test_photo_resolution_upgrades_an_unverified_cached_url():
    idol = Idol(
        name="Ada Lovelace",
        domain="technology",
        image_url=(
            "https://commons.wikimedia.org/wiki/Special:FilePath/"
            "Ada_Lovelace_portrait.jpg"
        ),
    )
    db = AsyncMock()
    resolver_calls = 0

    async def resolver(**_kwargs):
        nonlocal resolver_calls
        resolver_calls += 1
        return {
            "image_url": "https://upload.wikimedia.org/verified.jpg",
            "source_url": "https://commons.wikimedia.org/wiki/File:Verified.jpg",
            "license_status": "CC BY-SA 4.0",
            "attribution": _verified_attribution(),
        }

    result = await get_or_resolve_idol_photo(db, idol, resolver=resolver)

    assert resolver_calls == 1
    assert result["image_url"] == "https://upload.wikimedia.org/verified.jpg"
    assert is_verified_idol_photo(idol) is True
    db.flush.assert_awaited_once()


def test_evidence_schema_enforces_prompt_snippet_limit():
    with pytest.raises(ValidationError):
        Evidence(
            source_id="source-1",
            chunk_index=0,
            source_url="https://en.wikipedia.org/wiki/Ada_Lovelace",
            snippet="x" * 241,
            confidence=0.9,
        )


def test_source_evidence_must_match_id_url_chunk_and_verbatim_text():
    source = SimpleNamespace(
        id="source-1",
        url="https://en.wikipedia.org/wiki/Ada_Lovelace",
    )
    chunks = [
        SimpleNamespace(
            chunk_index=0,
            text="In 1843, Lovelace published her notes on the Analytical Engine.",
        )
    ]
    valid = Evidence(
        source_id="source-1",
        chunk_index=0,
        source_url=source.url,
        snippet="Lovelace published her notes on the Analytical Engine.",
        confidence=0.95,
    )
    invalid_items = [
        SimpleNamespace(**{**valid.model_dump(), "source_id": "other"}),
        SimpleNamespace(**{**valid.model_dump(), "chunk_index": 9}),
        SimpleNamespace(**{**valid.model_dump(), "source_url": "https://example.com"}),
        SimpleNamespace(**{**valid.model_dump(), "snippet": "A close paraphrase."}),
        SimpleNamespace(**{**valid.model_dump(), "snippet": "x" * 241}),
    ]

    filtered = _filter_valid_source_evidence(
        [valid, valid, *invalid_items],
        source=source,
        chunks=chunks,
    )

    assert filtered == [valid]


def test_claims_without_valid_evidence_are_removed():
    source = SimpleNamespace(id="source-1", url="https://example.com/source")
    chunks = [SimpleNamespace(chunk_index=0, text="Exact source sentence.")]
    supported = SimpleNamespace(
        evidence=[
            SimpleNamespace(
                source_id="source-1",
                chunk_index=0,
                source_url=source.url,
                snippet="Exact source sentence.",
            )
        ]
    )
    unsupported = SimpleNamespace(
        evidence=[
            SimpleNamespace(
                source_id="source-1",
                chunk_index=0,
                source_url=source.url,
                snippet="Invented sentence.",
            )
        ]
    )

    result = _retain_evidence_backed_items(
        [supported, unsupported],
        source=source,
        chunks=chunks,
    )

    assert result == [supported]
    assert unsupported.evidence == []


def test_image_requirement_is_optional_but_exposable_in_quality_gate():
    event = SimpleNamespace(confidence=0.9, evidence=[{"source": "test"}])
    common = {
        "profile_confidence": 0.9,
        "profile_evidence_count": 2,
        "timeline_events": [event, event, event],
        "persona_generated": True,
        "persona_evidence_count": 2,
    }

    _, default_publishable = _idol_catalog_quality(**common)
    _, missing_image_publishable = _idol_catalog_quality(
        **common,
        require_verified_image=True,
        image_verified=False,
    )
    _, verified_image_publishable = _idol_catalog_quality(
        **common,
        require_verified_image=True,
        image_verified=True,
    )

    assert default_publishable is True
    assert missing_image_publishable is False
    assert verified_image_publishable is True


@pytest.mark.asyncio
async def test_reingestion_deletes_canonical_and_legacy_achievement_rows():
    timeline_row = object()
    legacy_achievement_row = object()
    results = [
        SimpleNamespace(
            scalars=lambda: SimpleNamespace(all=lambda: [timeline_row])
        ),
        SimpleNamespace(
            scalars=lambda: SimpleNamespace(all=lambda: [legacy_achievement_row])
        ),
    ]

    class Database:
        def __init__(self):
            self.deleted = []

        async def execute(self, _statement):
            return results.pop(0)

        async def delete(self, record):
            self.deleted.append(record)

    db = Database()

    await _delete_existing_timeline_records(db, "idol-1")

    assert db.deleted == [timeline_row, legacy_achievement_row]
