"""A completed rejection repairs the guide; provider outages preserve it."""
import copy
from unittest.mock import AsyncMock

import pytest

from app.models.content_resource import ContentResource, ContentResourceKind, LicenseStatus
from app.models.idol import CatalogStatus
from app.services.content_resources import get_or_create_book_module_resource, content_resource_is_servable
from app.services.planning.lesson_package import digest
from app.services.book_fidelity import FIDELITY_VERSION
from tests.test_content_resources import ScalarResult, _source_fixture, _valid_book_module


def cached_book():
    module = _valid_book_module()
    return ContentResource(id='00000000-0000-0000-0000-000000000001',
        kind=ContentResourceKind.LLM_BOOK_SUMMARY, canonical_key='book:cal_newport:deep_work',
        title=module['title'], author_or_creator=module['author_or_creator'],
        content_markdown=module['content_markdown'],
        summary_json={'sections': module['sections'], 'ideas': module['ideas']},
        metadata_json={}, status=CatalogStatus.PUBLISHED, license_status=LicenseStatus.LLM_SUMMARY)


def verdict(content, source, *, passed, completed=True):
    return {'version': FIDELITY_VERSION, 'content_hash': digest(content), 'source_hash': digest(source['source_context']),
            'source_id': source['source_url'], 'passed': passed, 'review_completed': completed,
            'claims': [], 'issues': [] if passed else ['Unsupported claim']}


@pytest.mark.asyncio
@pytest.mark.parametrize('replacement_passes', [True, False])
async def test_negative_fidelity_generates_replacement_and_preserves_original_on_failure(monkeypatch, replacement_passes):
    existing = cached_book()
    original = existing.content_markdown
    source = _source_fixture()
    source['metadata_json'] = {'provider': 'verified'}
    source['summary_json'] = {'text_url': 'https://example.test/original.txt'}
    replacement = _valid_book_module()
    replacement['content_markdown'] += '\n\nReplacement text marker.'
    db = AsyncMock(); db.execute.return_value = ScalarResult(existing)
    review = AsyncMock(side_effect=[verdict(original, source, passed=False),
        verdict(replacement['content_markdown'], source, passed=replacement_passes)])
    monkeypatch.setattr('app.services.book_fidelity.review_book_fidelity', review)
    factory = AsyncMock(return_value=replacement)
    result = await get_or_create_book_module_resource(db, title=existing.title, author=existing.author_or_creator,
        user_goal='Learn', source_lookup=AsyncMock(return_value=source), module_factory=factory)
    assert result is existing and review.await_count == 2
    factory.assert_awaited_once()
    assert existing.source_url == source['source_url']
    assert existing.summary_json['text_url'] == source['summary_json']['text_url']
    assert content_resource_is_servable(existing) == replacement_passes
    if replacement_passes:
        assert existing.content_markdown == replacement['content_markdown']
    else:
        assert existing.content_markdown == original
        quality = existing.metadata_json['quality_report']
        assert not quality['passed'] and quality['fidelity']['content_hash'] == digest(original)
        assert existing.metadata_json['last_recovery_quality_report']['fidelity']['content_hash'] == digest(replacement['content_markdown'])


@pytest.mark.asyncio
async def test_unavailable_review_does_not_regenerate_or_publish(monkeypatch):
    existing = cached_book(); original = existing.content_markdown; source = _source_fixture()
    db = AsyncMock(); db.execute.return_value = ScalarResult(existing)
    review = AsyncMock(return_value=verdict(original, source, passed=False, completed=False))
    monkeypatch.setattr('app.services.book_fidelity.review_book_fidelity', review)
    factory = AsyncMock()
    result = await get_or_create_book_module_resource(db, title=existing.title, author=existing.author_or_creator,
        user_goal='Learn', source_lookup=AsyncMock(return_value=source), module_factory=factory)
    factory.assert_not_awaited()
    assert result.content_markdown == original and result.status == CatalogStatus.FLAGGED
    assert not content_resource_is_servable(result)
    assert result.source_url == source['source_url']


@pytest.mark.asyncio
@pytest.mark.parametrize('change', ['none', 'source', 'content', 'version', 'source_id'])
async def test_completed_rejection_reused_only_for_exact_source_content_and_version(monkeypatch, change):
    existing = cached_book(); source = _source_fixture()
    prior = verdict(existing.content_markdown, source, passed=False)
    existing.metadata_json = {'quality_report': {'fidelity': copy.deepcopy(prior), 'passed': False}}
    if change == 'source': source['source_context'] += ' Changed verified source.'
    if change == 'content': existing.content_markdown += '\n\nChanged guide text.'
    if change == 'version': existing.metadata_json['quality_report']['fidelity']['version'] = -1
    if change == 'source_id': source['source_url'] += '/edition'
    replacement = _valid_book_module(); replacement['content_markdown'] += '\n\nReplacement.'
    db = AsyncMock(); db.execute.return_value = ScalarResult(existing)
    replies = [verdict(replacement['content_markdown'], source, passed=True)]
    if change != 'none': replies.insert(0, verdict(existing.content_markdown, source, passed=False))
    review = AsyncMock(side_effect=replies)
    monkeypatch.setattr('app.services.book_fidelity.review_book_fidelity', review)
    factory = AsyncMock(return_value=replacement)
    result = await get_or_create_book_module_resource(db, title=existing.title, author=existing.author_or_creator,
        user_goal='Learn', source_lookup=AsyncMock(return_value=source), module_factory=factory)
    assert review.await_count == (1 if change == 'none' else 2)
    factory.assert_awaited_once()
    assert content_resource_is_servable(result)

@pytest.mark.asyncio
@pytest.mark.parametrize('fresh_passes', [True,False])
async def test_scoped_book_repair_publishes_only_after_fresh_independent_review(monkeypatch,fresh_passes):
    source=_source_fixture();existing=cached_book();original=existing.content_markdown
    draft=_valid_book_module();draft['content_markdown']+='\n\nCandidate factual assertion.'
    fixed=copy.deepcopy(draft);fixed['content_markdown']=fixed['content_markdown'].replace('Candidate factual assertion.','Corrected factual assertion.')
    db=AsyncMock();db.execute.return_value=ScalarResult(existing)
    review=AsyncMock(side_effect=[verdict(original,source,passed=False),
        verdict(draft['content_markdown'],source,passed=False),verdict(fixed['content_markdown'],source,passed=fresh_passes)])
    repair=AsyncMock(return_value=fixed)
    monkeypatch.setattr('app.services.book_fidelity.review_book_fidelity',review)
    monkeypatch.setattr('app.services.book_fidelity.repair_book_fidelity',repair)
    result=await get_or_create_book_module_resource(db,title=existing.title,author=existing.author_or_creator,
        user_goal='Learn',source_lookup=AsyncMock(return_value=source),module_factory=AsyncMock(return_value=draft))
    assert review.await_count==3 and repair.await_count==1
    assert content_resource_is_servable(result)==fresh_passes
    assert result.content_markdown==(fixed['content_markdown'] if fresh_passes else original)
    if fresh_passes: assert result.metadata_json['quality_report']['fidelity_repaired'] is True
