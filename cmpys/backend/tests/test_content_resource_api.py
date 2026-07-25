from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from app.api.v1.content_resources import (
    delete_content_highlight,
    prepare_content_narration,
)
from app.schemas.content_resource import ContentNarrationRequest
from app.services.book_narration import NarrationAsset, NarrationCue


class ScalarResult:
    def __init__(self, value=None):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


@pytest.mark.asyncio
async def test_delete_content_highlight_removes_only_current_users_resource_note():
    db = AsyncMock()
    db.get.return_value = MagicMock(id="resource-1")
    highlight = MagicMock(id="highlight-1", user_id="user-1", content_resource_id="resource-1")
    db.execute.return_value = ScalarResult(highlight)
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
        MagicMock(content_markdown="A human voice follows the meaning.")
    )
    renderer = AsyncMock(
        return_value=NarrationAsset(
            audio_url="/media/book_narration_example.mp3",
            style="expressive",
            voice="marin",
            duration_ms=2100,
            alignment=(NarrationCue(start=0, end=1, startMs=0, endMs=100),),
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
    )
    db.commit.assert_awaited_once()
    assert response.audioUrl == "/media/book_narration_example.mp3"
    assert response.voice == "marin"
    assert response.isAiGenerated is True


@pytest.mark.asyncio
async def test_prepare_narration_rejects_arbitrary_text(monkeypatch):
    db = AsyncMock()
    db.execute.return_value = ScalarResult(
        MagicMock(content_markdown="Only this published passage may be spoken.")
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
