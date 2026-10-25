from unittest.mock import AsyncMock, MagicMock

import httpx
import pytest

from app.services import content_resources as resources

FEED = '''<feed xmlns="http://www.w3.org/2005/Atom"><entry><id>https://www.gutenberg.org/ebooks/17405.opds</id><title>The Art of War</title></entry></feed>'''
RDF = '''<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:pgterms="http://www.gutenberg.org/2009/pgterms/" xmlns:dcterms="http://purl.org/dc/terms/">
<pgterms:ebook rdf:about="ebooks/17405"><dcterms:title>The Art of War</dcterms:title><dcterms:rights>Public domain in the USA.</dcterms:rights>
<dcterms:creator><pgterms:agent><pgterms:name>Sunzi, active 6th century B.C.</pgterms:name><pgterms:alias>Sun Tzu</pgterms:alias></pgterms:agent></dcterms:creator>
<dcterms:hasFormat><pgterms:file rdf:about="https://www.gutenberg.org/ebooks/17405.txt.utf-8"><dcterms:format><rdf:Description><rdf:value>text/plain; charset=utf-8</rdf:value></rdf:Description></dcterms:format></pgterms:file></dcterms:hasFormat>
</pgterms:ebook></rdf:RDF>'''


def test_official_opds_and_author_alias_identify_source():
    assert resources._gutenberg_catalog_ids(FEED, 'The Art of War') == [17405]
    source = resources._gutenberg_rdf_source(RDF, 17405, 'The Art of War', 'Sun Tzu')
    assert source['metadata_json']['gutenberg_id'] == 17405
    assert source['summary_json']['text_url'] == 'https://www.gutenberg.org/ebooks/17405.txt.utf-8'
    assert resources._gutenberg_rdf_source(RDF, 17405, 'The Art of War', 'Machiavelli') is None


@pytest.mark.parametrize('bad', [
    RDF.replace('ebooks/17405"', 'ebooks/132"'),
    RDF.replace('Public domain in the USA.', 'Copyright protected'),
    RDF.replace('https://www.gutenberg.org/ebooks/17405.txt.utf-8', 'https://evil.test/17405.txt'),
    RDF.replace('<dcterms:creator>', '<dcterms:contributor>').replace('</dcterms:creator>', '</dcterms:contributor>'),
])
def test_wrong_identity_rights_or_source_cannot_be_imported(bad):
    assert resources._gutenberg_rdf_source(bad, 17405, 'The Art of War', 'Sun Tzu') is None


@pytest.mark.parametrize('url', [
    'https://evil.test/ebooks/17405.txt.utf-8',
    'https://www.gutenberg.org.evil.test/ebooks/17405.txt.utf-8',
    'https://user:password@www.gutenberg.org/ebooks/17405.txt.utf-8',
    'https://www.gutenberg.org:8000/ebooks/17405.txt.utf-8',
    'http://127.0.0.1/ebooks/17405.txt.utf-8',
    'https://www.gutenberg.org/ebooks/132.txt.utf-8',
    'https://www.gutenberg.org/ebooks/17405.txt.utf-8?redirect=evil',
])
def test_download_and_redirect_are_limited_to_same_official_book(url):
    assert resources._gutenberg_text_url(url, 17405) is None


def test_same_title_never_overrides_wrong_author_and_coauthors_match_independently():
    assert resources._book_identity_score('Same Title', 'James Clear', 'Same Title', ['James Joyce']) == 0
    assert resources._book_identity_score('Same Title', 'James Clear', 'Same Title', ['Clear, James', 'Another Author']) == 1


def response(text='', status=200, headers=None):
    return httpx.Response(status, text=text, headers=headers, request=httpx.Request('GET', 'https://www.gutenberg.org/'))


def mock_client(monkeypatch, replies):
    client = MagicMock()
    client.get = AsyncMock(side_effect=replies)
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=False)
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **_: client)
    return client


@pytest.mark.asyncio
async def test_official_lookup_fetches_text_and_handles_same_book_redirect(monkeypatch):
    client = mock_client(monkeypatch, [response(FEED), response(RDF),
        response(status=302, headers={'location': '/cache/epub/17405/pg17405.txt'}),
        response('Verified original source words. ' * 100)])
    source = await resources.lookup_gutenberg_book(title='The Art of War', author='Sun Tzu')
    assert len(source['source_context'].split()) == 400
    assert source['summary_json']['text_url'].endswith('/pg17405.txt')
    assert client.get.await_count == 4


@pytest.mark.asyncio
async def test_cross_origin_redirect_is_not_followed(monkeypatch):
    client = mock_client(monkeypatch, [response(FEED), response(RDF),
        response(status=302, headers={'location': 'http://169.254.169.254/latest/meta-data/'})])
    assert await resources.lookup_gutenberg_book(title='The Art of War', author='Sun Tzu') is None
    assert client.get.await_count == 3


@pytest.mark.asyncio
@pytest.mark.parametrize('reply', [response('invalid XML'), response(status=503), response('<feed>' + 'x' * 1_000_001)])
async def test_bad_catalog_fails_without_generation(monkeypatch, reply):
    mock_client(monkeypatch, [reply])
    assert await resources.lookup_gutenberg_book(title='The Art of War', author='Sun Tzu') is None


@pytest.mark.asyncio
@pytest.mark.parametrize('third_party', [None, {'source_context': ''}])
async def test_unavailable_or_empty_third_party_uses_official_source(monkeypatch, third_party):
    monkeypatch.setattr(resources, 'lookup_public_domain_book', AsyncMock(return_value=third_party))
    monkeypatch.setattr(resources, 'lookup_book_reference_context', AsyncMock(return_value={'source_context': 'Catalog only'}))
    official = {'source_context': 'Verified original source words. ' * 100}
    lookup = AsyncMock(return_value=official)
    monkeypatch.setattr(resources, 'lookup_gutenberg_book', lookup)
    assert await resources.lookup_book_source(title='The Art of War', author='Sun Tzu') == official
    lookup.assert_awaited_once()

@pytest.mark.parametrize('url,expected',[
 ('https://www.gutenberg.org/cache/epub/17405/pg17405-images.html',True),
 ('http://www.gutenberg.org/ebooks/17405.html.images',True),
 ('https://evil.test/cache/epub/17405/pg17405-images.html',False),
 ('https://www.gutenberg.org/cache/epub/132/pg132-images.html',False),
])
def test_original_reader_url_must_belong_to_verified_book(url,expected):
 html='<dcterms:hasFormat><pgterms:file rdf:about="'+url+'"><dcterms:format><rdf:Description><rdf:value>text/html</rdf:value></rdf:Description></dcterms:format></pgterms:file></dcterms:hasFormat>'
 rdf=RDF.replace('</pgterms:ebook>',html+'</pgterms:ebook>')
 source=resources._gutenberg_rdf_source(rdf,17405,'The Art of War','Sun Tzu')
 assert source['summary_json']['reading_url']==(url.replace('http:','https:') if expected else source['summary_json']['text_url'])

@pytest.mark.asyncio
async def test_original_source_endpoint_uses_verified_source_without_generation(monkeypatch):
 from app.api.v1.content_resources import resolve_original_book_source
 lookup=AsyncMock(return_value={'summary_json':{'reading_url':'https://www.gutenberg.org/ebooks/17405.html.images'}})
 monkeypatch.setattr(resources,'lookup_gutenberg_book',lookup)
 assert await resolve_original_book_source(current_user=object(),title='The Art of War',author='Sun Tzu')=={'url':'https://www.gutenberg.org/ebooks/17405.html.images'}
 lookup.assert_awaited_once_with(title='The Art of War',author='Sun Tzu')
 lookup.return_value=None
 assert await resolve_original_book_source(current_user=object(),title='Missing',author=None)=={'url':None}
