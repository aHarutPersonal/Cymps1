from unittest.mock import AsyncMock, MagicMock

import pytest

from app.models.content_resource import ContentResourceKind, LicenseStatus
from app.services.content_resources import (
    canonical_book_key,
    canonical_video_query_key,
    canonical_youtube_key,
    get_or_create_book_module_resource,
    get_or_create_video_resource,
    material_to_resource_payload,
    get_or_create_content_resource,
    sync_plan_item_content_resource_links,
)


class ScalarResult:
    def __init__(self, value=None):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


def test_canonical_book_key_is_stable_for_title_and_author_variants():
    assert (
        canonical_book_key("The Intelligent Investor", "Benjamin Graham")
        == "book:benjamin_graham:the_intelligent_investor"
    )
    assert (
        canonical_book_key("  the intelligent investor! ", " Benjamin  Graham ")
        == "book:benjamin_graham:the_intelligent_investor"
    )


def test_canonical_youtube_key_uses_video_id_only():
    assert (
        canonical_youtube_key("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=12s")
        == "youtube:dQw4w9WgXcQ"
    )


def test_canonical_video_query_key_is_stable():
    assert (
        canonical_video_query_key("  Warren Buffett margin of safety interview!! ")
        == "youtube_query:warren_buffett_margin_of_safety_interview"
    )
    assert (
        canonical_youtube_key("https://youtu.be/dQw4w9WgXcQ?si=abc")
        == "youtube:dQw4w9WgXcQ"
    )


def test_material_to_resource_payload_converts_book_summary_material():
    payload = material_to_resource_payload(
        {
            "title": "The Intelligent Investor",
            "type": "in_app_lesson",
            "author": "Benjamin Graham",
            "content_markdown": "# Defensive Investing\n\nA compact lesson.",
            "duration_minutes": 15,
            "ideas": [{"title": "Margin", "content": "Protect downside."}],
        }
    )

    assert payload is not None
    assert payload["kind"] == ContentResourceKind.LLM_BOOK_SUMMARY
    assert payload["license_status"] == LicenseStatus.LLM_SUMMARY
    assert payload["canonical_key"] == "book:benjamin_graham:the_intelligent_investor"
    assert payload["summary_json"]["ideas"][0]["title"] == "Margin"


def test_material_to_resource_payload_converts_valid_youtube_video():
    payload = material_to_resource_payload(
        {
            "title": "Buffett on Safety",
            "type": "video",
            "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "reason": "Explains margin of safety.",
        }
    )

    assert payload is not None
    assert payload["kind"] == ContentResourceKind.VIDEO
    assert payload["license_status"] == LicenseStatus.EXTERNAL_LINK
    assert payload["canonical_key"] == "youtube:dQw4w9WgXcQ"


def test_material_to_resource_payload_converts_article_material():
    payload = material_to_resource_payload(
        {
            "title": "How to Practice Deliberately",
            "type": "article",
            "url": "https://example.com/deliberate-practice",
            "reason": "Useful guided learning source.",
        }
    )

    assert payload is not None
    assert payload["kind"] == ContentResourceKind.ARTICLE
    assert payload["license_status"] == LicenseStatus.EXTERNAL_LINK
    assert payload["canonical_key"] == "article:how_to_practice_deliberately"
    assert payload["metadata_json"]["reason"] == "Useful guided learning source."


@pytest.mark.asyncio
async def test_get_or_create_content_resource_reuses_existing_record():
    existing = AsyncMock()
    existing.id = "resource-1"
    db = AsyncMock()
    db.execute.return_value = ScalarResult(existing)

    result = await get_or_create_content_resource(
        db,
        kind=ContentResourceKind.VIDEO,
        canonical_key="youtube:dQw4w9WgXcQ",
        title="Buffett on Safety",
        license_status=LicenseStatus.EXTERNAL_LINK,
    )

    assert result is existing
    db.add.assert_not_called()
    db.flush.assert_not_called()


@pytest.mark.asyncio
async def test_get_or_create_book_module_resource_reuses_existing_without_generation():
    existing = AsyncMock()
    existing.id = "book-resource-1"
    db = AsyncMock()
    db.execute.return_value = ScalarResult(existing)

    async def factory(**kwargs):
        raise AssertionError("factory should not run when the book module exists")

    result = await get_or_create_book_module_resource(
        db,
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
        module_factory=factory,
    )

    assert result is existing
    db.add.assert_not_called()
    db.flush.assert_not_called()


@pytest.mark.asyncio
async def test_get_or_create_book_module_resource_generates_and_saves_once_when_missing():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)
    factory_calls = []

    async def factory(**kwargs):
        factory_calls.append(kwargs)
        return {
            "title": "Deep Work",
            "author_or_creator": "Cal Newport",
            "duration_minutes": 15,
            "promise": "Build a distraction-resistant work ritual.",
            "sections": [{"title": "Protect Focus", "summary": "Batch shallow work."}],
            "ideas": [{"title": "Depth Wins", "content": "Schedule deep work first."}],
            "content_markdown": "# Deep Work\n\nA reusable 15-minute summary.",
        }

    async def no_source(**kwargs):
        return None

    result = await get_or_create_book_module_resource(
        db,
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
        source_lookup=no_source,
        module_factory=factory,
    )

    assert len(factory_calls) == 1
    assert factory_calls[0]["title"] == "Deep Work"
    assert factory_calls[0]["author"] == "Cal Newport"
    assert result.canonical_key == "book:cal_newport:deep_work"
    assert result.kind == ContentResourceKind.LLM_BOOK_SUMMARY
    assert result.license_status == LicenseStatus.LLM_SUMMARY
    assert result.duration_minutes == 15
    assert result.content_markdown.startswith("# Deep Work")
    assert result.summary_json["ideas"][0]["title"] == "Depth Wins"
    db.add.assert_called_once_with(result)
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_get_or_create_book_module_resource_prefers_public_domain_source_before_llm():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def source_lookup(**kwargs):
        assert kwargs["title"] == "Meditations"
        assert kwargs["author"] == "Marcus Aurelius"
        return {
            "title": "Meditations",
            "author_or_creator": "Marcus Aurelius",
            "source_url": "https://www.gutenberg.org/ebooks/2680",
            "license_status": "public_domain",
            "content_markdown": "# Meditations\n\nA public-domain reading source.",
            "summary_json": {"source": "project_gutenberg"},
            "duration_minutes": 15,
            "metadata_json": {"provider": "gutenberg"},
        }

    async def factory(**kwargs):
        raise AssertionError("LLM fallback should not run when public source exists")

    result = await get_or_create_book_module_resource(
        db,
        title="Meditations",
        author="Marcus Aurelius",
        user_goal="practice resilience",
        source_lookup=source_lookup,
        module_factory=factory,
    )

    assert result.kind == ContentResourceKind.PUBLIC_DOMAIN_BOOK
    assert result.license_status == LicenseStatus.PUBLIC_DOMAIN
    assert result.source_url == "https://www.gutenberg.org/ebooks/2680"
    assert result.content_markdown.startswith("# Meditations")
    db.add.assert_called_once_with(result)
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_attach_content_resources_generates_missing_book_module():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def factory(**kwargs):
        return {
            "title": kwargs["title"],
            "author_or_creator": kwargs["author"],
            "duration_minutes": 15,
            "promise": "Apply one durable idea.",
            "sections": [],
            "ideas": [{"title": "Practice", "content": "Use the idea today."}],
            "content_markdown": "# Atomic Habits\n\nSmall improvements compound.",
        }

    async def no_source(**kwargs):
        return None

    materials = await attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Atomic Habits",
                "type": "book",
                "author_or_creator": "James Clear",
                "search_query": "Atomic Habits James Clear",
            }
        ],
        user_goal="build better routines",
        book_source_lookup=no_source,
        book_module_factory=factory,
    )

    assert materials[0]["content_resource_id"] == db.add.call_args.args[0].id
    assert materials[0]["canonical_key"] == "book:james_clear:atomic_habits"
    assert materials[0]["content_markdown"].startswith("# Atomic Habits")
    assert materials[0]["duration_minutes"] == 15
    assert materials[0]["ideas"][0]["title"] == "Practice"


@pytest.mark.asyncio
async def test_attach_content_resources_prefers_public_domain_book_source():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def source_lookup(**kwargs):
        return {
            "title": "Meditations",
            "author_or_creator": "Marcus Aurelius",
            "source_url": "https://www.gutenberg.org/ebooks/2680",
            "license_status": "public_domain",
            "content_markdown": "# Meditations\n\nPublic-domain source.",
            "summary_json": {"source": "project_gutenberg"},
            "duration_minutes": 15,
        }

    async def factory(**kwargs):
        raise AssertionError("LLM fallback should not run")

    materials = await attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Meditations",
                "type": "book",
                "author_or_creator": "Marcus Aurelius",
            }
        ],
        book_source_lookup=source_lookup,
        book_module_factory=factory,
    )

    resource = db.add.call_args.args[0]
    assert resource.kind == ContentResourceKind.PUBLIC_DOMAIN_BOOK
    assert materials[0]["content_resource_id"] == resource.id
    assert materials[0]["canonical_key"] == "book:marcus_aurelius:meditations"
    assert materials[0]["url"] == "https://www.gutenberg.org/ebooks/2680"
    assert materials[0]["license_status"] == "public_domain"
    assert materials[0]["content_markdown"].startswith("# Meditations")


@pytest.mark.asyncio
async def test_attach_content_resources_resolves_video_query_material():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def resolver(query: str):
        return "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    materials = await attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Margin of Safety",
                "type": "video",
                "search_query": "Warren Buffett margin of safety interview",
                "reason": "A useful video.",
            }
        ],
        video_resolver=resolver,
    )

    assert materials[0]["content_resource_id"] == db.add.call_args.args[0].id
    assert materials[0]["canonical_key"] == "youtube:dQw4w9WgXcQ"
    assert materials[0]["url"] == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"


@pytest.mark.asyncio
async def test_get_or_create_video_resource_resolves_query_and_saves_youtube_resource():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def resolver(query: str):
        assert query == "Warren Buffett margin of safety interview"
        return "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    result = await get_or_create_video_resource(
        db,
        title="Margin of Safety",
        search_query="Warren Buffett margin of safety interview",
        resolver=resolver,
    )

    assert result.canonical_key == "youtube:dQw4w9WgXcQ"
    assert result.kind == ContentResourceKind.VIDEO
    assert result.source_url == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    assert result.license_status == LicenseStatus.EXTERNAL_LINK
    assert result.metadata_json["search_query"] == "Warren Buffett margin of safety interview"
    db.add.assert_called_once_with(result)
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_get_or_create_video_resource_caches_unavailable_query_without_researching():
    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def resolver(query: str):
        return None

    result = await get_or_create_video_resource(
        db,
        title="Obscure Mentor Clip",
        search_query="very obscure unavailable mentor clip",
        resolver=resolver,
    )

    assert result.canonical_key == "youtube_query:very_obscure_unavailable_mentor_clip"
    assert result.kind == ContentResourceKind.VIDEO
    assert result.source_url is None
    assert result.license_status == LicenseStatus.UNKNOWN
    assert result.metadata_json["unavailable"] is True
    db.add.assert_called_once_with(result)
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_sync_plan_item_content_resource_links_replaces_existing_links():
    db = AsyncMock()
    db.add = MagicMock()

    await sync_plan_item_content_resource_links(
        db,
        plan_item_id="plan-item-1",
        materials=[
            {
                "title": "Deep Work",
                "type": "book",
                "content_resource_id": "resource-book",
                "canonical_key": "book:cal_newport:deep_work",
                "reason": "Focus training.",
                "license_status": "llm_summary",
            },
            {
                "title": "Local note",
                "type": "tool",
            },
            {
                "title": "Buffett Interview",
                "type": "video",
                "content_resource_id": "resource-video",
                "canonical_key": "youtube:dQw4w9WgXcQ",
                "search_query": "Warren Buffett interview",
            },
        ],
    )

    db.execute.assert_awaited_once()
    assert db.add.call_count == 2
    first = db.add.call_args_list[0].args[0]
    second = db.add.call_args_list[1].args[0]
    assert first.plan_item_id == "plan-item-1"
    assert first.content_resource_id == "resource-book"
    assert first.material_index == 0
    assert first.canonical_key == "book:cal_newport:deep_work"
    assert first.metadata_json["reason"] == "Focus training."
    assert second.content_resource_id == "resource-video"
    assert second.material_index == 2
    assert second.metadata_json["search_query"] == "Warren Buffett interview"
    db.flush.assert_awaited_once()
