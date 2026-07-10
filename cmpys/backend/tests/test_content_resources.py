import asyncio
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.models.content_resource import ContentResourceKind, LicenseStatus
from app.models.idol import CatalogStatus
from app.services.content_resources import (
    canonical_book_key,
    canonical_video_query_key,
    canonical_youtube_key,
    generate_book_module,
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

    def scalars(self):
        return self

    def all(self):
        if self._value is None:
            return []
        if isinstance(self._value, list):
            return self._value
        return [self._value]


class LLMResponse:
    def __init__(self, data=None, error=None):
        self.data = data or {}
        self.error = error


def _book_module_markdown(title: str, words: int = 3000) -> str:
    return f"# {title}\n\n" + " ".join(["insight"] * words)


def _valid_book_module(title: str = "Deep Work", author: str = "Cal Newport") -> dict:
    sections = []
    markdown_parts = []
    for index in range(5):
        sections.append(
            {
                "title": f"Framework {index + 1}",
                "summary": " ".join(["mechanism"] * 80),
                "exercise": " ".join(["practice"] * 40),
            }
        )
        markdown_parts.append(
            f"## Framework {index + 1}\n\n"
            + " ".join([f"concept{index}"] * 510)
            + "\n\n### Practice This\n1. Apply the framework.\n2. Record the result."
        )
    markdown_parts.append("## Closing Synthesis\n\nConnect the five frameworks into one practice.")
    return {
        "title": title,
        "author_or_creator": author,
        "promise": "Apply the book's central framework.",
        "sections": sections,
        "ideas": [
            {"title": f"Idea {index + 1}", "content": " ".join(["application"] * 40)}
            for index in range(6)
        ],
        "content_markdown": f"# {title}\n\n" + "\n\n".join(markdown_parts),
    }


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


def test_material_to_resource_payload_keeps_in_app_lesson_distinct_from_book():
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
    assert payload["kind"] == ContentResourceKind.IN_APP_LESSON
    assert payload["canonical_key"] == "in_app_lesson:the_intelligent_investor"
    assert payload["summary_json"]["ideas"][0]["title"] == "Margin"


def test_material_to_resource_payload_rejects_short_book_summary():
    assert material_to_resource_payload(
        {
            "title": "Deep Work",
            "type": "book",
            "author": "Cal Newport",
            "content_markdown": "short " * 500,
            "ideas": [{"title": "Depth"}],
        }
    ) is None


@pytest.mark.asyncio
async def test_generate_book_module_retries_until_prd_minimum(monkeypatch):
    """Book modules below 2,500 words should trigger the stronger retry."""
    calls = []

    class Client:
        async def generate_json(self, **kwargs):
            calls.append(kwargs["user_prompt"])
            if len(calls) == 1:
                return LLMResponse(
                    {
                        "title": "Deep Work",
                        "author_or_creator": "Cal Newport",
                        "content_markdown": "word " * 2000,
                        "sections": [],
                        "ideas": [],
                    }
                )
            return LLMResponse(_valid_book_module())

    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client",
        lambda **kwargs: Client(),
    )

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="focus better",
    )

    assert len(calls) == 2
    assert len(result["content_markdown"].split()) >= 2500
    assert result["duration_minutes"] == 13
    assert result["quality_report"]["passed"] is True


@pytest.mark.asyncio
async def test_generate_book_module_repairs_metadata_without_regenerating_lesson(monkeypatch):
    draft = _valid_book_module()
    draft["ideas"] = [
        {"title": f"Idea {index + 1}", "content": "Too short.", "category": "Strategy"}
        for index in range(6)
    ]
    calls = []

    class BalancedClient:
        async def generate_json(self, **kwargs):
            calls.append("balanced")
            return LLMResponse(draft)

    class FastClient:
        async def generate_json(self, **kwargs):
            calls.append("fast")
            return LLMResponse(
                {
                    "sections": draft["sections"],
                    "ideas": [
                        {
                            "title": f"Idea {index + 1}",
                            "content": " ".join(["application"] * 40),
                            "category": "Strategy",
                        }
                        for index in range(6)
                    ],
                }
            )

    def client_factory(**kwargs):
        tier = kwargs.get("tier")
        if tier == "balanced":
            return BalancedClient()
        if tier == "fast":
            return FastClient()
        raise AssertionError("quality tier must not rewrite a sound long lesson")

    monkeypatch.setattr("app.services.llm.client.get_llm_client", client_factory)

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="understand focused work",
    )

    assert calls == ["balanced", "fast"]
    assert result["quality_report"]["passed"] is True
    assert result["content_markdown"] == draft["content_markdown"]


@pytest.mark.asyncio
async def test_fast_book_canary_falls_back_to_balanced_on_quality_failure(monkeypatch):
    from app.services.llm.client import LLMResponse
    from app.services.llm.routing import RoutingDecision, RoutingStats

    calls = []

    class Client:
        def __init__(self, tier):
            self.tier = tier
            self.model = None

        async def generate_json(self, **kwargs):
            calls.append(self.tier)
            if self.tier == "fast":
                return LLMResponse(
                    data={
                        "title": "Deep Work",
                        "author_or_creator": "Cal Newport",
                        "content_markdown": "thin " * 1500,
                        "sections": [],
                        "ideas": [],
                    },
                )
            return LLMResponse(data=_valid_book_module())

    async def choose_canary(**kwargs):
        return RoutingDecision(
            tier="fast",
            reason="fast_canary",
            fast_model="fast-model",
            stats=RoutingStats(),
            exploration_bucket=1,
        )

    monkeypatch.setattr(
        "app.services.llm.routing.choose_llm_tier",
        choose_canary,
    )
    monkeypatch.setattr(
        "app.services.llm.client.get_llm_client",
        lambda **kwargs: Client(kwargs.get("tier", "balanced")),
    )

    result = await generate_book_module(
        title="Deep Work",
        author="Cal Newport",
        user_goal="understand focused work",
    )

    assert calls == ["fast", "balanced"]
    assert result["quality_report"]["passed"] is True
    stages = result["quality_report"]["generation"]["calls"]
    assert stages[0]["routing_reason"] == "fast_canary"
    assert stages[0]["quality_score"] < 0.85
    assert stages[1]["routing_reason"] == "fast_quality_fallback"
    assert stages[1]["quality_score"] >= 0.85


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
    existing = MagicMock()
    existing.id = "book-resource-1"
    existing.content_markdown = "word " * 2600
    existing.status = CatalogStatus.PUBLISHED
    existing.metadata_json = {"quality_report": {"passed": True}}
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
        return _valid_book_module()

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
    assert result.is_public_domain is False
    assert result.duration_minutes == 13
    assert result.content_markdown.startswith("# Deep Work")
    assert result.summary_json["ideas"][0]["title"] == "Idea 1"
    db.add.assert_called_once_with(result)
    db.flush.assert_called_once()


@pytest.mark.asyncio
async def test_book_module_upgrade_never_writes_null_public_domain_flag():
    existing = MagicMock()
    existing.id = "legacy-book-resource"
    existing.content_markdown = "thin"
    existing.status = CatalogStatus.PENDING
    existing.metadata_json = {}
    db = AsyncMock()
    db.execute.return_value = ScalarResult(existing)

    async def factory(**kwargs):
        return _valid_book_module(kwargs["title"], kwargs["author"])

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

    assert result is existing
    assert existing.is_public_domain is False
    db.flush.assert_awaited_once()


@pytest.mark.asyncio
async def test_get_or_create_book_module_resource_grounds_public_domain_source_before_llm():
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
            "content_markdown": None,
            "source_context": "A sampled passage from the public-domain source.",
            "summary_json": {"source": "project_gutenberg"},
            "duration_minutes": 15,
            "metadata_json": {"provider": "gutenberg"},
        }

    async def factory(**kwargs):
        assert "sampled passage" in kwargs["source_context"]
        return _valid_book_module("Meditations", "Marcus Aurelius")

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
        return _valid_book_module(kwargs["title"], kwargs["author"])

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
    assert materials[0]["duration_minutes"] == 13
    assert materials[0]["ideas"][0]["title"] == "Idea 1"


@pytest.mark.asyncio
async def test_attach_content_resources_does_not_serve_failed_book_module():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    async def no_source(**kwargs):
        return None

    async def thin_factory(**kwargs):
        return {
            "title": kwargs["title"],
            "author_or_creator": kwargs["author"],
            "sections": [],
            "ideas": [],
            "content_markdown": "thin " * 200,
        }

    materials = await attach_content_resources_to_materials(
        db,
        [{"title": "Thin Book", "type": "book", "author": "A. Author"}],
        book_source_lookup=no_source,
        book_module_factory=thin_factory,
    )

    assert "content_resource_id" not in materials[0]
    assert materials[0]["resource_unavailable"] is True
    assert materials[0]["quality_status"] == "flagged"


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
            "content_markdown": None,
            "source_context": "Sampled public-domain source text.",
            "summary_json": {"source": "project_gutenberg"},
            "duration_minutes": 15,
        }

    async def factory(**kwargs):
        assert kwargs["source_context"] == "Sampled public-domain source text."
        return _valid_book_module("Meditations", "Marcus Aurelius")

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
async def test_attach_content_resources_defers_uncached_book_generation(monkeypatch):
    from app.services import content_resources as svc

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)
    enqueued = []

    monkeypatch.setattr(
        svc,
        "enqueue_book_module_generation",
        lambda **kwargs: enqueued.append(kwargs),
    )

    async def source_lookup(**kwargs):
        raise AssertionError("source lookup must not run inline when deferred")

    async def factory(**kwargs):
        raise AssertionError("book generation must not run inline when deferred")

    materials = await svc.attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Atomic Habits",
                "type": "book",
                "author_or_creator": "James Clear",
                "reason": "Habit design.",
            }
        ],
        user_goal="build better routines",
        book_source_lookup=source_lookup,
        book_module_factory=factory,
        defer_book_generation=True,
    )

    assert "content_resource_id" not in materials[0]
    assert materials[0]["canonical_key"] == "book:james_clear:atomic_habits"
    assert enqueued == [
        {
            "title": "Atomic Habits",
            "author": "James Clear",
            "user_goal": "build better routines",
            "source_context": "Habit design.",
        }
    ]
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_attach_content_resources_attaches_cached_book_without_enqueue(monkeypatch):
    from app.services import content_resources as svc

    cached = MagicMock()
    cached.id = "book-resource-1"
    cached.canonical_key = "book:james_clear:atomic_habits"
    cached.source_url = "https://example.com/atomic-habits"
    cached.thumbnail_url = None
    cached.license_status = LicenseStatus.LLM_SUMMARY
    cached.content_markdown = _valid_book_module("Atomic Habits", "James Clear")[
        "content_markdown"
    ]
    cached.duration_minutes = 15
    cached.summary_json = {"ideas": [], "promise": "Small habits compound.", "sections": []}
    cached.status = CatalogStatus.PUBLISHED

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult([cached])

    def fail_enqueue(**kwargs):
        raise AssertionError("cached book must not be enqueued")

    monkeypatch.setattr(svc, "enqueue_book_module_generation", fail_enqueue)

    materials = await svc.attach_content_resources_to_materials(
        db,
        [
            {
                "title": "Atomic Habits",
                "type": "book",
                "author_or_creator": "James Clear",
            }
        ],
        defer_book_generation=True,
    )

    # Cached materials only need the single batched IN lookup.
    assert db.execute.await_count == 1
    assert materials[0]["content_resource_id"] == "book-resource-1"
    assert materials[0]["canonical_key"] == "book:james_clear:atomic_habits"
    assert materials[0]["content_markdown"].startswith("# Atomic Habits")
    assert materials[0]["license_status"] == "llm_summary"
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_attach_content_resources_runs_independent_book_prep_concurrently():
    from app.services.content_resources import attach_content_resources_to_materials

    db = AsyncMock()
    db.add = MagicMock()
    db.execute.return_value = ScalarResult(None)

    started = {"Deep Work": asyncio.Event(), "Atomic Habits": asyncio.Event()}

    async def no_source(**kwargs):
        return None

    async def factory(**kwargs):
        title = kwargs["title"]
        other = "Atomic Habits" if title == "Deep Work" else "Deep Work"
        started[title].set()
        # Each factory only completes once the other has started, which
        # deadlocks (and times out) unless the prep work runs concurrently.
        await asyncio.wait_for(started[other].wait(), timeout=1.0)
        return _valid_book_module(title, kwargs["author"])

    materials = await attach_content_resources_to_materials(
        db,
        [
            {"title": "Deep Work", "type": "book", "author_or_creator": "Cal Newport"},
            {"title": "Atomic Habits", "type": "book", "author_or_creator": "James Clear"},
        ],
        user_goal="focus better",
        book_source_lookup=no_source,
        book_module_factory=factory,
    )

    assert materials[0]["canonical_key"] == "book:cal_newport:deep_work"
    assert materials[1]["canonical_key"] == "book:james_clear:atomic_habits"
    assert materials[0]["content_markdown"].startswith("# Deep Work")
    assert materials[1]["content_markdown"].startswith("# Atomic Habits")
    assert db.add.call_count == 2


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
