from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.v1.content_resources import (
    delete_content_highlight,
    prepare_content_narration,
)
from app.models.content_resource import ContentResourceKind
from app.models.idol import CatalogStatus
from app.schemas.content_resource import ContentNarrationRequest
from app.services.book_narration import NarrationAsset, NarrationCue


class ScalarResult:
    def __init__(self, value=None):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


def test_narration_request_rejects_unregistered_voice_profile():
    with pytest.raises(ValidationError):
        ContentNarrationRequest(
            text="Read this passage.",
            narratorProfile="warren_buffett_clone",
        )


@pytest.mark.asyncio
async def test_delete_content_highlight_removes_only_current_users_resource_note():
    db = AsyncMock()
    db.get.return_value = MagicMock(id="resource-1")
    highlight = MagicMock(
        id="highlight-1", user_id="user-1", content_resource_id="resource-1"
    )
    resource = MagicMock(
        id="resource-1",
        status=CatalogStatus.PUBLISHED,
        kind=ContentResourceKind.ARTICLE,
    )
    db.execute.side_effect = [ScalarResult(resource), ScalarResult(highlight)]
    current_user = MagicMock(id="user-1")

    await delete_content_highlight(
        resource_id="resource-1",
        highlight_id="highlight-1",
        db=db,
        current_user=current_user,
    )

    resource_lookup = str(db.execute.await_args_list[0].args[0])
    assert "content_resources.status" in resource_lookup
    db.delete.assert_awaited_once_with(highlight)


@pytest.mark.asyncio
async def test_prepare_narration_only_renders_text_from_the_resource(monkeypatch):
    db = AsyncMock()
    db.execute.return_value = ScalarResult(
        MagicMock(
            content_markdown="A human voice follows the meaning.",
            status=CatalogStatus.PUBLISHED,
            kind=ContentResourceKind.ARTICLE,
        )
    )
    renderer = AsyncMock(
        return_value=NarrationAsset(
            audio_url="/media/book_narration_example.mp3",
            style="expressive",
            voice="English_expressive_narrator",
            voice_display_name="Expressive narrator",
            narrator_profile="expressive_narrator",
            provider="yunwu",
            model="speech-2.8-hd",
            duration_ms=2100,
            alignment=(NarrationCue(start=0, end=1, startMs=0, endMs=100, text="A"),),
            alignment_source="provider",
            alignment_granularity="phrase",
            offset_encoding="utf16",
            source_text_hash="example-hash",
            disclosure="AI-generated voice; not the real person.",
            cached=False,
        )
    )
    monkeypatch.setattr(
        "app.api.v1.content_resources.render_book_narration",
        renderer,
    )

    response = await prepare_content_narration(
        resource_id="resource-1",
        data=ContentNarrationRequest(
            text="A human voice follows the meaning.",
            style="expressive",
        ),
        db=db,
        current_user=MagicMock(id="user-1"),
    )

    renderer.assert_awaited_once_with(
        "A human voice follows the meaning.",
        "expressive",
        "expressive_narrator",
    )
    db.commit.assert_awaited_once()
    assert response.audioUrl == "/media/book_narration_example.mp3"
    assert response.voice == "English_expressive_narrator"
    assert response.voiceDisplayName == "Expressive narrator"
    assert response.narratorProfile.value == "expressive_narrator"
    assert response.narratorProfileLabel == "Expressive narrator"
    assert response.provider == "yunwu"
    assert response.model == "speech-2.8-hd"
    assert response.alignmentSource == "provider"
    assert response.alignmentGranularity == "phrase"
    assert response.offsetEncoding == "utf16"
    assert response.sourceTextHash == "example-hash"
    assert response.isAiGenerated is True


@pytest.mark.asyncio
async def test_prepare_narration_rejects_arbitrary_text(monkeypatch):
    db = AsyncMock()
    db.execute.return_value = ScalarResult(
        MagicMock(
            content_markdown="Only this published passage may be spoken.",
            status=CatalogStatus.PUBLISHED,
            kind=ContentResourceKind.ARTICLE,
        )
    )
    renderer = AsyncMock()
    monkeypatch.setattr(
        "app.api.v1.content_resources.render_book_narration",
        renderer,
    )

    with pytest.raises(HTTPException) as raised:
        await prepare_content_narration(
            resource_id="resource-1",
            data=ContentNarrationRequest(
                text="An unrelated script supplied by a client.",
                style="expressive",
            ),
            db=db,
            current_user=MagicMock(id="user-1"),
        )

    assert raised.value.status_code == 422
    renderer.assert_not_awaited()
    db.commit.assert_not_awaited()
