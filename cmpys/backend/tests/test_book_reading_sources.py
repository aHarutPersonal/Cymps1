from types import SimpleNamespace
from unittest.mock import AsyncMock
import pytest
from app.services import content_resources as resources
from app.api.v1 import content_resources as api
from app.models.idol import CatalogStatus
from app.models.ingest_job import IngestState

@pytest.mark.parametrize('title,author,host', [
    ('Self-Editing for Fiction Writers, Second Edition: How to Edit Yourself Into Print', 'Renni Browne and Dave King', 'www.editorialdepartment.com'),
    ('Self-Editing for Fiction Writers', 'Renni Browne', 'www.editorialdepartment.com'),
    ('Into the Woods: A Five-Act Journey Into Story', 'John Yorke', 'www.johnyorkestory.com'),
])
@pytest.mark.asyncio
async def test_author_excerpts_open_without_generation_or_full_book_claim(monkeypatch, title, author, host):
    lookup = AsyncMock(side_effect=AssertionError('Do not search again for a verified excerpt'))
    monkeypatch.setattr(resources, 'lookup_gutenberg_book', lookup)
    result = await api.resolve_book_reading_source(current_user=object(), title=title, author=author)
    assert result['url'].startswith('https://' + host + '/')
    assert result['scope'] == 'excerpt'
    assert 'Full book not included' in result['description']
    lookup.assert_not_awaited()

@pytest.mark.parametrize('title,author', [
    ('Into the Woods', 'Another Author'), ('Into the Woods', None),
    ('Beyond Into the Woods', 'John Yorke'), ('Trip to the Moon', 'John Yorke'),
    ('Self-Editing for Fiction Writers', 'Renni Other'),
])
def test_excerpt_requires_exact_book_and_author_identity(title, author):
    assert resources.author_book_excerpt(title=title, author=author) is None

@pytest.mark.asyncio
async def test_original_remains_full_text_and_absence_is_explicit(monkeypatch):
    lookup = AsyncMock(return_value={'summary_json': {'reading_url': 'https://www.gutenberg.org/ebooks/46.html.images'}})
    monkeypatch.setattr(resources, 'lookup_gutenberg_book', lookup)
    result = await api.resolve_book_reading_source(current_user=object(), title='A Christmas Carol', author='Charles Dickens')
    assert result['scope'] == 'full_text'
    lookup.return_value = None
    assert await api.resolve_book_reading_source(current_user=object(), title='Missing', author=None) == {'url': None}

@pytest.mark.asyncio
async def test_empty_book_is_not_described_as_bad_generated_text(monkeypatch):
    monkeypatch.setattr(api, 'content_resource_is_servable', lambda _: False)
    book = SimpleNamespace(status=CatalogStatus.FLAGGED, metadata_json={'source_sufficiency': 'insufficient'})
    values = iter([book, SimpleNamespace(state=IngestState.FLAGGED)])
    class DB:
        async def execute(self, _):
            value = next(values)
            return SimpleNamespace(scalar_one_or_none=lambda: value)
    result = await api.resolve_content_resource(db=DB(), current_user=object(), canonicalKey='book:john:woods')
    assert result.id is None
    assert not result.retryable
    assert 'verified source text' in result.message
    assert 'generated guide did not meet' not in result.message

def test_reading_route_precedes_resource_id():
    paths = [getattr(route, 'path', '') for route in api.router.routes]
    assert paths.index('/content-resources/reading-source') < paths.index('/content-resources/{resource_id}')
