import json
import socket
from unittest.mock import AsyncMock

import httpx
import pytest

from app.core.config import settings
from app.services import book_narration
from app.services.book_narration import (
    BookNarrationUnavailableError,
    _MiniMaxSynthesis,
    _alignment_from_provider_segments,
    _assert_safe_subtitle_url,
    _fetch_subtitle_document,
    _narrator_profile,
    _parse_minimax_response,
    _STYLE_PRESETS,
    _synthesize_with_minimax,
    narration_text_belongs_to_resource,
    render_book_narration,
)


def test_rendered_markdown_passage_is_accepted_for_narration():
    markdown = """
## Choose with care

Read **one small step**, then visit [the guide](https://example.com/guide).
"""

    assert narration_text_belongs_to_resource(
        "Read one small step, then visit the guide.",
        markdown,
    )
    assert not narration_text_belongs_to_resource("Read an unrelated script.", markdown)


def test_provider_phrase_timing_uses_utf16_source_offsets():
    text = "Hello 😊 world. Calm choices matter."
    document = [
        {
            "is_final_segment": True,
            "text": text,
            "text_begin": 0,
            "text_end": len(text),
            "pronounce_text": text,
            "pronounce_text_begin": 0,
            "pronounce_text_end": len(text),
            "time_begin": 0.0,
            "time_end": 3174.013605442177,
        }
    ]

    cues, granularity = _alignment_from_provider_segments(
        text,
        document,
        duration_ms=3312,
    )

    assert granularity == "phrase"
    assert len(cues) == 1
    assert cues[0].start == 0
    # Python/MiniMax report Unicode code points; Flutter String offsets are UTF-16.
    assert cues[0].end == len(text) + 1
    assert cues[0].startMs == 0
    assert cues[0].endMs == 3174
    assert cues[0].text == text


def test_inconsistent_provider_text_range_is_rejected():
    with pytest.raises(BookNarrationUnavailableError):
        _alignment_from_provider_segments(
            "Read this exactly.",
            [
                {
                    "text": "Different text",
                    "text_begin": 0,
                    "text_end": 10,
                    "time_begin": 0.0,
                    "time_end": 900.0,
                }
            ],
            duration_ms=1000,
        )


def test_narrator_profiles_are_server_allowlisted():
    assert _narrator_profile("expressive_narrator").voice_id == (
        "English_expressive_narrator"
    )
    assert _narrator_profile("seasoned_mentor").voice_id == "English_Steadymentor"
    with pytest.raises(ValueError):
        _narrator_profile("public_figure_clone")


def test_minimax_response_decodes_audio_duration_and_subtitle_url(monkeypatch):
    monkeypatch.setattr(settings, "book_narration_max_audio_bytes", 1024)
    audio = b"\xff\xfb" + (b"a" * 126)

    parsed = _parse_minimax_response(
        {
            "base_resp": {"status_code": 0, "status_msg": "success"},
            "data": {
                "audio": audio.hex(),
                "status": 2,
                "subtitle_file": "https://example.invalid/subtitle.json",
            },
            "extra_info": {"audio_length": 3312},
        }
    )

    assert parsed.audio_bytes == audio
    assert parsed.duration_ms == 3312
    assert parsed.subtitle_url.endswith("subtitle.json")


@pytest.mark.parametrize(
    "payload",
    [
        {"base_resp": {"status_code": 1004}},
        {
            "base_resp": {"status_code": 0},
            "data": {"audio": "not-hex", "subtitle_file": "https://x"},
            "extra_info": {"audio_length": 1000},
        },
    ],
)
def test_minimax_response_rejects_provider_and_audio_errors(payload):
    with pytest.raises(BookNarrationUnavailableError):
        _parse_minimax_response(payload)


@pytest.mark.asyncio
async def test_native_yunwu_request_uses_minimax_payload(monkeypatch):
    monkeypatch.setattr(
        settings,
        "book_narration_api_base_url",
        "https://api.yunwu.ai/minimax/v1",
    )
    monkeypatch.setattr(settings, "book_narration_tts_model", "speech-2.8-hd")
    monkeypatch.setattr(settings, "yunwu_api_key", "test-key")
    audio = b"\xff\xfb" + (b"a" * 126)
    observed: dict = {}

    async def handler(request: httpx.Request) -> httpx.Response:
        observed["url"] = str(request.url)
        observed["payload"] = json.loads(request.content)
        return httpx.Response(
            200,
            json={
                "base_resp": {"status_code": 0},
                "data": {
                    "audio": audio.hex(),
                    "status": 2,
                    "subtitle_file": "https://example.invalid/subtitle.json",
                },
                "extra_info": {"audio_length": 1400},
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await _synthesize_with_minimax(
            "Read this.",
            preset=_STYLE_PRESETS["expressive"],
            profile=_narrator_profile("expressive_narrator"),
            client=client,
        )

    assert observed["url"] == "https://api.yunwu.ai/minimax/v1/t2a_v2"
    assert observed["payload"]["model"] == "speech-2.8-hd"
    assert observed["payload"]["subtitle_enable"] is True
    assert observed["payload"]["subtitle_type"] == "word"
    assert observed["payload"]["output_format"] == "hex"
    assert (
        observed["payload"]["voice_setting"]["voice_id"]
        == "English_expressive_narrator"
    )
    assert "emotion" not in observed["payload"]["voice_setting"]
    assert result.duration_ms == 1400


@pytest.mark.asyncio
async def test_subtitle_url_requires_exact_allowed_public_host(monkeypatch):
    host = "minimax-algeng-chat-tts.oss-cn-wulanchabu.aliyuncs.com"
    monkeypatch.setattr(settings, "book_narration_subtitle_allowed_hosts", host)
    monkeypatch.setattr(
        socket,
        "getaddrinfo",
        lambda *_args, **_kwargs: [
            (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("8.8.8.8", 443))
        ],
    )

    await _assert_safe_subtitle_url(f"https://{host}/signed.json?token=redacted")

    with pytest.raises(BookNarrationUnavailableError):
        await _assert_safe_subtitle_url("https://attacker.example/subtitle.json")

    monkeypatch.setattr(
        socket,
        "getaddrinfo",
        lambda *_args, **_kwargs: [
            (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("127.0.0.1", 443))
        ],
    )
    with pytest.raises(BookNarrationUnavailableError):
        await _assert_safe_subtitle_url(f"https://{host}/subtitle.json")


@pytest.mark.asyncio
async def test_subtitle_download_is_json_and_size_bounded(monkeypatch):
    monkeypatch.setattr(
        book_narration,
        "_assert_safe_subtitle_url",
        AsyncMock(return_value=None),
    )
    monkeypatch.setattr(settings, "book_narration_max_subtitle_bytes", 1024)
    document = [
        {
            "text": "Read this.",
            "text_begin": 0,
            "text_end": 10,
            "time_begin": 0.0,
            "time_end": 900.0,
        }
    ]

    async def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "application/json"},
            json=document,
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await _fetch_subtitle_document(
            "https://provider.example/subtitle.json",
            client=client,
        )
    assert result == document

    monkeypatch.setattr(settings, "book_narration_max_subtitle_bytes", 8)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(BookNarrationUnavailableError):
            await _fetch_subtitle_document(
                "https://provider.example/subtitle.json",
                client=client,
            )


@pytest.mark.asyncio
async def test_render_uses_provider_timing_and_persistent_cache(monkeypatch, tmp_path):
    text = "Hello 😊 world."
    synthesis = _MiniMaxSynthesis(
        audio_bytes=b"\xff\xfb" + (b"a" * 256),
        duration_ms=2000,
        subtitle_url="https://provider.example/subtitle.json",
    )
    synthesize = AsyncMock(return_value=synthesis)
    fetch_subtitle = AsyncMock(
        return_value=[
            {
                "text": text,
                "text_begin": 0,
                "text_end": len(text),
                "time_begin": 0.0,
                "time_end": 1800.0,
            }
        ]
    )
    monkeypatch.setattr(settings, "book_narration_enabled", True)
    monkeypatch.setattr(settings, "yunwu_api_key", "test-key")
    monkeypatch.setattr(settings, "book_narration_media_dir", str(tmp_path))
    monkeypatch.setattr(settings, "book_narration_tts_model", "speech-2.8-hd")
    monkeypatch.setattr(
        book_narration,
        "_synthesize_with_minimax",
        synthesize,
    )
    monkeypatch.setattr(
        book_narration,
        "_fetch_subtitle_document",
        fetch_subtitle,
    )
    book_narration._locks.clear()

    first = await render_book_narration(text, "expressive", "seasoned_mentor")
    second = await render_book_narration(text, "expressive", "seasoned_mentor")

    assert first.cached is False
    assert second.cached is True
    assert first.provider == "yunwu"
    assert first.model == "speech-2.8-hd"
    assert first.narrator_profile == "seasoned_mentor"
    assert first.voice == "English_Steadymentor"
    assert first.alignment_source == "provider"
    assert first.alignment_granularity == "phrase"
    assert first.offset_encoding == "utf16"
    assert first.alignment[0].end == len(text) + 1
    assert first.source_text_hash == second.source_text_hash
    assert first.disclosure == "AI-generated voice; not the real person."
    synthesize.assert_awaited_once()
    fetch_subtitle.assert_awaited_once()
    assert len(list(tmp_path.glob("book_narration_*.mp3"))) == 1
    assert len(list(tmp_path.glob("book_narration_*.json"))) == 1
    assert book_narration._locks == {}
