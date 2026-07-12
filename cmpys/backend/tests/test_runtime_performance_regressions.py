import inspect

import pytest
from starlette.middleware.gzip import GZipMiddleware

from app.main import app
from app.api.v1 import media
from app.tasks import ingestion as ingestion_tasks
from app.tasks import plans as plan_tasks


@pytest.mark.asyncio
async def test_plan_detail_material_resolution_defers_book_generation(monkeypatch):
    calls = {}

    async def resolve(materials):
        calls["resolved"] = materials
        return [{**materials[0], "url": "https://example.com/book"}]

    async def attach(db, materials, **kwargs):
        calls["attach"] = kwargs
        return [{**materials[0], "canonical_key": "book:author:book"}]

    async def sync(db, **kwargs):
        calls["sync"] = kwargs

    monkeypatch.setattr("app.services.tavily.resolve_material_urls", resolve)
    monkeypatch.setattr(
        "app.services.content_resources.attach_content_resources_to_materials",
        attach,
    )
    monkeypatch.setattr(
        "app.services.content_resources.sync_plan_item_content_resource_links",
        sync,
    )

    materials = [{"title": "Book", "type": "book", "author": "Author"}]
    result = await plan_tasks._resolve_plan_detail_materials(
        object(),
        plan_item_id="item-1",
        materials=materials,
        user_goal="learn deeply",
    )

    assert calls["resolved"] == materials
    assert calls["attach"] == {
        "user_goal": "learn deeply",
        "defer_book_generation": True,
    }
    assert calls["sync"]["plan_item_id"] == "item-1"
    assert result[0]["canonical_key"] == "book:author:book"


def test_worker_tasks_have_no_decorative_openai_streams():
    source = inspect.getsource(ingestion_tasks) + inspect.getsource(plan_tasks)

    assert "_generate_thinking_stream_concurrently" not in source
    assert "AsyncOpenAI" not in source


def test_gzip_uses_balanced_compression_level():
    middleware = next(
        item for item in app.user_middleware if item.cls is GZipMiddleware
    )

    assert middleware.kwargs["minimum_size"] == 1024
    assert middleware.kwargs["compresslevel"] == 6


def test_lazy_image_generation_does_not_block_asyncio_loop():
    source = inspect.getsource(media.get_media)

    assert "await asyncio.to_thread(" in source
    assert "await db.commit()" in source
