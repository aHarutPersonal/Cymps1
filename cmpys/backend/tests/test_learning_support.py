import copy
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import httpx
import pytest
from fastapi import HTTPException

from app.services import book_companions as books
from app.services import learning_sources as sources
from app.services import learning_support as support
from app.models.idol import CatalogStatus
from app.services.planning.lesson_package import digest


SOURCE = "The author explains how to replace an abstract intention with a concrete cue and small action."


def draft():
    return books.CompanionDraft.model_validate(
        {
            "scope": "Selected publicly discussed ideas, with original CMPYS applications.",
            "lessons": [
                {
                    "title": "Choose a concrete cue",
                    "idea": "Use a concrete cue to make the intended next action easier to identify.",
                    "content": "Original CMPYS application: "
                    + "A learner picks a specific place and time to practice the skill. "
                    * 20,
                    "question": "Which option gives a specific cue for the next action?",
                    "options": [
                        "After breakfast, write one line.",
                        "Become better.",
                        "Try someday.",
                    ],
                    "answer": 0,
                    "explanation": "After breakfast supplies a recognizable cue and one line is a small action.",
                    "source_ids": ["s1"],
                }
            ],
        }
    )


def review():
    return books.CompanionReview.model_validate(
        {
            "correct_book_and_author": True,
            "primary_sources_only": True,
            "all_claims_supported": True,
            "original_teaching": True,
            "scope_honest": True,
            "exercises_correct_and_answerable": True,
            "issues": [],
            "evidence": [
                {"lesson_index": 0, "source_id": "s1", "support_quote": SOURCE}
            ],
        }
    )


@pytest.mark.parametrize(
    "defect",
    [
        "none",
        "wrong_book",
        "non_primary",
        "unsupported",
        "wrong_answer",
        "invented_quote",
        "unknown_source",
        "missing_coverage",
        "duplicate",
        "copied",
    ],
)
def test_book_publication_requires_independent_complete_evidence(defect):
    candidate, verdict = draft(), review()
    if defect == "wrong_book":
        verdict.correct_book_and_author = False
    if defect == "non_primary":
        verdict.primary_sources_only = False
    if defect == "unsupported":
        verdict.all_claims_supported = False
    if defect == "wrong_answer":
        verdict.exercises_correct_and_answerable = False
    if defect == "invented_quote":
        verdict.evidence[
            0
        ].support_quote = "This nonexistent source quote is long but fabricated and unsupported by the actual page."
    if defect == "unknown_source":
        verdict.evidence[0].source_id = "s99"
    if defect == "missing_coverage":
        candidate.lessons.append(copy.deepcopy(candidate.lessons[0]))
    if defect == "duplicate":
        verdict.evidence.append(copy.deepcopy(verdict.evidence[0]))
    text = candidate.lessons[0].content + SOURCE if defect == "copied" else SOURCE
    assert books.validate_review(candidate, [{"id": "s1", "text": text}], verdict) == (
        defect == "none"
    )


def test_companion_cache_rechecks_content_hash_and_publication():
    content = draft().model_dump()
    resource = SimpleNamespace(
        status=CatalogStatus.PUBLISHED,
        summary_json=content,
        content_markdown="\n\n".join(
            lesson["content"] for lesson in content["lessons"]
        ),
        metadata_json={
            "companion_review": {
                "version": books.VERSION,
                "passed": True,
                "content_hash": digest(content),
            }
        },
    )
    assert books.companion_ready(resource)
    resource.summary_json = {**content, "scope": "Tampered"}
    assert not books.companion_ready(resource)
    resource.summary_json = content
    resource.status = CatalogStatus.FLAGGED
    assert not books.companion_ready(resource)


@pytest.mark.asyncio
async def test_catalog_snippets_never_trigger_book_generation(monkeypatch):
    monkeypatch.setattr(
        books,
        "search_evidence",
        AsyncMock(
            return_value=[
                {
                    "id": "s1",
                    "text": "A short catalog blurb.",
                    "url": "https://publisher.example/book",
                }
            ]
        ),
    )
    call = AsyncMock()
    monkeypatch.setattr(books, "structured_call", call)
    assert await books.build_companion("Book", "Author") is None
    call.assert_not_called()


@pytest.mark.asyncio
async def test_book_build_uses_distinct_review_and_returns_only_checked_sources(
    monkeypatch,
):
    monkeypatch.setattr(
        books,
        "search_evidence",
        AsyncMock(
            return_value=[
                {
                    "id": "s1",
                    "title": "Author interview",
                    "text": SOURCE * 30,
                    "url": "https://publisher.example/interview",
                }
            ]
        ),
    )
    call = AsyncMock(side_effect=[
        books.CompanionSources(source_ids=["s1"]), draft(), review()
    ])
    monkeypatch.setattr(books, "structured_call", call)
    content, report = await books.build_companion("Book", "Author")
    assert call.await_count == 3 and report["passed"]
    assert content["lessons"][0]["minutes"] >= 4
    assert "text" not in content["sources"][0]
    assert report["content_hash"] == digest(content)


@pytest.mark.asyncio
async def test_book_source_fallback_excludes_long_nonprimary_pages(monkeypatch):
    rejected = {"id": "s1", "title": "Retail summary", "text": SOURCE * 30,
                "url": "https://retailer.example/summary"}
    primary = {**rejected, "title": "Author interview",
               "url": "https://author.example/interview"}
    search = AsyncMock(side_effect=[[rejected], [primary]])
    call = AsyncMock(side_effect=[books.CompanionSources(source_ids=[]),
                                 books.CompanionSources(source_ids=["s1"]),
                                 draft(), review()])
    monkeypatch.setattr(books, "search_evidence", search)
    monkeypatch.setattr(books, "structured_call", call)
    content, _ = await books.build_companion("Book: Long Subtitle", "A and B")
    assert search.await_count == 2
    assert '"A and B"' not in search.await_args_list[0].args[0]
    assert content["sources"] == [{k: primary[k] for k in ("id", "title", "url")}]
    assert call.await_args_list[2].args[3]["sources"] == [primary]


@pytest.mark.asyncio
async def test_no_book_draft_is_generated_without_primary_sources(monkeypatch):
    monkeypatch.setattr(books, "search_evidence", AsyncMock(return_value=[{
        "id": "s1", "text": SOURCE * 30, "url": "https://retailer.example"
    }]))
    call = AsyncMock(return_value=books.CompanionSources(source_ids=[]))
    monkeypatch.setattr(books, "structured_call", call)
    assert await books.build_companion("Book", "Author") is None
    assert [c.args[0] for c in call.await_args_list] == [
        "book_companion_sources", "book_companion_sources"
    ]


@pytest.mark.parametrize(
    "url, expected",
    [
        ("https://www.youtube.com/watch?v=abcdefghijk", "abcdefghijk"),
        ("https://youtu.be/abcdefghijk", "abcdefghijk"),
        ("https://youtube.com.evil.example/watch?v=abcdefghijk", None),
        ("https://youtube.com@evil.example/watch?v=abcdefghijk", None),
        ("https://www.youtube.com/watch?v=short", None),
        ("http://www.youtube.com/watch?v=abcdefghijk", None),
        ("https://127.0.0.1/watch?v=abcdefghijk", None),
    ],
)
def test_video_identity_rejects_arbitrary_hosts_and_malformed_ids(url, expected):
    assert sources.youtube_id(url) == expected


@pytest.mark.asyncio
async def test_video_verification_calls_real_oembed_helper(monkeypatch):
    requests = []

    def respond(request):
        requests.append(request)
        if request.url.path == "/oembed":
            assert request.url.params["url"] == (
                "https://www.youtube.com/watch?v=abcdefghijk"
            )
            return httpx.Response(200, json={
                "title": "Demonstration",
                "author_name": "Creator",
                "html": '<iframe src="https://www.youtube.com/embed/abcdefghijk"></iframe>',
            })
        return httpx.Response(200, text="var ytInitialPlayerResponse = " + json.dumps({
            "playabilityStatus": {"status": "OK", "playableInEmbed": True},
            "videoDetails": {
                "videoId": "abcdefghijk", "lengthSeconds": "420",
                "shortDescription": SOURCE * 10,
            },
        }))

    client_type = httpx.AsyncClient
    transport = httpx.MockTransport(respond)
    monkeypatch.setattr(sources.httpx, "AsyncClient", lambda **kw: client_type(
        transport=transport, **kw
    ))
    result = await sources.verify_video_source("https://youtu.be/abcdefghijk")
    assert result["title"] == "Demonstration"
    assert result["seconds"] == 420
    assert [r.url.path for r in requests] == ["/oembed", "/watch"]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure", ["none", "age_gate", "wrong_embed", "wrong_video", "snippet_only"]
)
async def test_server_challenge_uses_exact_public_publisher_evidence_only(
    monkeypatch, failure
):
    metadata = {
        "title": "Lesson",
        "author_name": "Institution",
        "html": '<iframe src="https://www.youtube.com/embed/abcdefghijk"></iframe>',
    }
    if failure == "wrong_embed":
        metadata["html"] = (
            '<iframe src="https://www.youtube.com/embed/otherother1"></iframe>'
        )
    monkeypatch.setattr(
        sources, "_youtube_oembed_metadata", AsyncMock(return_value=metadata)
    )
    reason = (
        "Sign in to confirm your age"
        if failure == "age_gate"
        else "Sign in to confirm you’re not a bot"
    )
    data = {"playabilityStatus": {"status": "LOGIN_REQUIRED", "reason": reason}}
    client = AsyncMock()
    client.__aenter__.return_value = client
    client.get.return_value = httpx.Response(
        200, text="var ytInitialPlayerResponse = " + json.dumps(data)
    )
    monkeypatch.setattr(sources.httpx, "AsyncClient", Mock(return_value=client))
    link = "https://www.youtube.com/watch?v=" + (
        "otherother1" if failure == "wrong_video" else "abcdefghijk"
    )
    evidence = {
        "url": "https://institution.example/lesson",
        "text": link + "\n" + SOURCE * 10,
    }
    if failure == "snippet_only":
        evidence["text"] = link + "\nA short result snippet."
    video = await sources.verify_video_source("https://youtu.be/abcdefghijk", evidence)
    assert bool(video) == (failure == "none")
    if video:
        assert video["evidenceType"] == "publisher_lesson" and video["seconds"] is None


@pytest.mark.parametrize(
    "defect",
    [
        "none",
        "irrelevant",
        "non_primary",
        "inadequate",
        "wrong_level",
        "conflict",
        "fabricated_quote",
    ],
)
def test_video_relevance_requires_actual_content_support(defect):
    verdict = support.VideoReview(
        credible_educational_creator=True,
        substantive_content_evidence=True,
        directly_reinforces_lesson=True,
        appropriate_level=True,
        adds_demonstration_or_explanation=True,
        no_material_conflicts=True,
        why_watch="Demonstrates a concrete cue followed by a small action.",
        try_after="Choose a concrete cue for the skill you just practiced.",
        supporting_quote=SOURCE,
        issues=[],
    )
    if defect == "irrelevant":
        verdict.directly_reinforces_lesson = False
    if defect == "non_primary":
        verdict.credible_educational_creator = False
    if defect == "inadequate":
        verdict.substantive_content_evidence = False
    if defect == "wrong_level":
        verdict.appropriate_level = False
    if defect == "conflict":
        verdict.no_material_conflicts = False
    if defect == "fabricated_quote":
        verdict.supporting_quote = "This quotation was made up rather than found in the supplied public evidence."
    assert support.valid_video_review(verdict, SOURCE) == (defect == "none")


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure", ["none", "unavailable", "no_embed", "wrong_id", "no_content", "too_long"]
)
async def test_video_requires_real_metadata_available_embed_and_content(
    monkeypatch, failure
):
    data = {
        "playabilityStatus": {"status": "OK", "playableInEmbed": True},
        "videoDetails": {
            "videoId": "abcdefghijk",
            "lengthSeconds": "420",
            "shortDescription": SOURCE * 10,
        },
    }
    if failure == "unavailable":
        data["playabilityStatus"]["status"] = "LOGIN_REQUIRED"
    if failure == "no_embed":
        data["playabilityStatus"]["playableInEmbed"] = False
    if failure == "wrong_id":
        data["videoDetails"]["videoId"] = "otherother1"
    if failure == "no_content":
        data["videoDetails"]["shortDescription"] = "Subscribe!"
    if failure == "too_long":
        data["videoDetails"]["lengthSeconds"] = "7200"
    monkeypatch.setattr(
        sources,
        "_youtube_oembed_metadata",
        AsyncMock(
            return_value={
                "title": "Demonstration",
                "author_name": "Creator",
                "html": '<iframe src="https://www.youtube.com/embed/abcdefghijk"></iframe>',
            }
        ),
    )
    client = AsyncMock()
    client.get.return_value = httpx.Response(
        200, text="var ytInitialPlayerResponse = " + json.dumps(data) + "; otherJS();"
    )
    client.__aenter__.return_value = client
    monkeypatch.setattr(sources.httpx, "AsyncClient", Mock(return_value=client))
    video = await sources.verify_video_source("https://youtu.be/abcdefghijk")
    assert bool(video) == (failure == "none")
    assert (
        client.get.await_args.args[0] == "https://www.youtube.com/watch?v=abcdefghijk"
    )


def item():
    return SimpleNamespace(
        title="Improve a practical skill",
        details_json={
            "steps": [
                {
                    "id": "step_1",
                    "title": "Apply a cue",
                    "lesson_content": "Useful original teaching. " * 30,
                    "resources": ["Book"],
                }
            ],
            "materials": [
                {
                    "type": "book",
                    "title": "Book",
                    "author_or_creator": "Author",
                    "content_markdown": "Untrusted invented book text",
                    "ideas": [{"title": "Untrusted", "content": "Untrusted idea"}],
                }
            ],
        },
    )


def test_support_is_bound_to_actual_tutorial_and_strips_planner_book_prose():
    source = item()
    value = support.support_input(source, "step_1", None)
    assert value["books"] == [{"title": "Book", "author": "Author"}]
    before = value["revision"]
    source.details_json["steps"][0]["lesson_content"] += " Changed meaning."
    assert support.support_input(source, "step_1", None)["revision"] != before
    with pytest.raises(HTTPException):
        support.support_input(source, "unknown", None)
    with pytest.raises(HTTPException):
        support.support_input(source, None, "Foreign book")
    source.details_json["_generation"] = {"status": "revoked"}
    with pytest.raises(HTTPException):
        support.support_input(source, "step_1", None)


@pytest.mark.asyncio
async def test_video_discovery_runs_even_when_outline_has_only_books(monkeypatch):
    value = support.support_input(item(), "step_1", None)
    monkeypatch.setattr(
        support,
        "get_companion",
        AsyncMock(return_value={"title": "Book", "status": "unavailable"}),
    )
    discover = AsyncMock(return_value=[])
    monkeypatch.setattr(support, "find_support_video", discover)
    result = await support.build_support(value)
    discover.assert_awaited_once_with(value)
    assert result["idea"] is None and result["videos"] == []


@pytest.mark.asyncio
async def test_video_fallback_runs_after_first_candidates_are_rejected(monkeypatch):
    search = AsyncMock(side_effect=[
        [{"url": "https://youtu.be/abcdefghijk", "text": "First result"}],
        [{"url": "https://youtu.be/otherother1", "text": "Fallback result"}],
    ])
    verify = AsyncMock(return_value=None)
    monkeypatch.setattr(support, "search_evidence", search)
    monkeypatch.setattr(support, "verify_video_source", verify)
    value = {"mission": "Writing an essay thesis", "lesson_title": "Sharpen your skill"}
    assert await support.find_support_video(value) == []
    assert search.await_count == 2 and verify.await_count == 2
    assert all("Writing an essay thesis" in c.args[0] for c in search.await_args_list)


@pytest.mark.asyncio
async def test_concurrent_book_preparation_finishes_before_idea_matching(monkeypatch):
    ready = {"title": "Book", "status": "ready", "lessons": []}
    get = AsyncMock(side_effect=[{"title": "Book", "status": "checking"}, ready])
    match = AsyncMock(return_value={"bookId": "shared", "lessonId": "lesson_1"})
    monkeypatch.setattr(support, "get_companion", get)
    monkeypatch.setattr(support.asyncio, "sleep", AsyncMock())
    monkeypatch.setattr(support, "match_book_idea", match)
    monkeypatch.setattr(support, "find_support_video", AsyncMock(return_value=[]))
    value = support.support_input(item(), "step_1", None)
    result = await support.build_support(value)
    match.assert_awaited_once_with(value, [ready])
    assert result["idea"]["bookId"] == "shared"
    assert "books_pending" not in result


@pytest.mark.asyncio
async def test_public_bundle_hides_quarantined_book_and_its_idea(monkeypatch):
    resource = SimpleNamespace(
        status=CatalogStatus.FLAGGED,
        title="Book",
        author_or_creator="Author",
        metadata_json={},
    )
    db = SimpleNamespace(
        execute=AsyncMock(
            return_value=SimpleNamespace(scalar_one_or_none=lambda: resource)
        )
    )
    result = await support.public_support(
        db,
        {
            "status": "ready",
            "result": {
                "books": [{"title": "Book", "author": "Author"}],
                "idea": {"bookId": "book-1"},
                "videos": [],
            },
        },
    )
    assert result["idea"] is None and result["books"][0]["status"] == "unavailable"


@pytest.mark.asyncio
async def test_owner_check_precedes_any_generation(monkeypatch):
    from app.api.v1 import learning_support as api

    owner_check = AsyncMock(side_effect=HTTPException(404, "Plan item not found"))
    monkeypatch.setattr(api, "_get_item_for_user", owner_check)
    with pytest.raises(HTTPException) as error:
        await api._support(
            "item", SimpleNamespace(), SimpleNamespace(id="user"), "step_1", None, True
        )
    assert error.value.status_code == 404
    assert owner_check.await_args.kwargs["for_update"] is True
