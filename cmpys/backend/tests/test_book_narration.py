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
    _fetch_subtitle_with_retry,
    _narrator_profile,
    _parse_minimax_response,
    _STYLE_PRESETS,
    _synthesize_with_minimax,
    narration_text_belongs_to_resource,
    render_book_narration,
)


@pytest.fixture(autouse=True)
def legacy_narration_provider(monkeypatch):
    """These fixtures exercise legacy MiniMax recordings, independent of defaults."""
    monkeypatch.setattr(settings, "book_narration_provider", "yunwu")


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


def test_ordered_list_markers_are_not_required_in_spoken_chunk_membership():
    markdown = """
1. Observe the business carefully.
2. Wait for a durable advantage.
3. Act with a margin of safety.
"""

    assert narration_text_belongs_to_resource(
        "Observe the business carefully. Wait for a durable advantage.",
        markdown,
    )
    assert not narration_text_belongs_to_resource(
        "Observe the business carelessly. Wait for a durable advantage.",
        markdown,
    )


def test_membership_keeps_digits_that_are_not_markdown_list_markers():
    markdown = "Version 2 preserves the 80/20 rule. Step 3 remains important."

    assert narration_text_belongs_to_resource(markdown, markdown)
    assert not narration_text_belongs_to_resource(
        "Version preserves the rule. Step remains important.",
        markdown,
    )


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


def test_provider_segments_remap_trimmed_whitespace_and_unicode_to_source():
    text = "  Hello 😊 world.  Calm choices matter. \n"
    first = "Hello 😊 world."
    second = "Calm choices matter."
    document = [
        {
            "text": first,
            "text_begin": 0,
            "text_end": len(first),
            "time_begin": 0.0,
            "time_end": 1200.0,
        },
        {
            "text": second,
            "text_begin": len(first),
            "text_end": len(first) + len(second),
            "time_begin": 1350.0,
            "time_end": 2800.0,
        },
    ]

    cues, granularity = _alignment_from_provider_segments(
        text,
        document,
        duration_ms=3000,
    )

    first_start = text.index(first)
    second_start = text.index(second)
    assert granularity == "phrase"
    assert [(cue.text, cue.startMs, cue.endMs) for cue in cues] == [
        (first, 0, 1200),
        (second, 1350, 2800),
    ]
    assert cues[0].start == len(text[:first_start].encode("utf-16-le")) // 2
    assert cues[0].end == len(text[: first_start + len(first)].encode("utf-16-le")) // 2
    assert cues[1].start == len(text[:second_start].encode("utf-16-le")) // 2
    assert (
        cues[1].end == len(text[: second_start + len(second)].encode("utf-16-le")) // 2
    )


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


def test_alignment_diagnostics_report_only_bounded_structural_differences():
    source = "Alpha — Beta"
    provider = "Alpha - Beta"
    with pytest.raises(BookNarrationUnavailableError) as failure:
        _alignment_from_provider_segments(
            source,
            [
                {
                    "text": provider,
                    "text_begin": 0,
                    "text_end": len(provider),
                    "time_begin": 0.0,
                    "time_end": 900.0,
                }
            ],
            duration_ms=1000,
        )

    diagnostics = failure.value.alignment_diagnostics
    assert diagnostics is not None
    assert diagnostics.segment_index == 0
    assert diagnostics.segment_count == 1
    assert diagnostics.source_length == len(source)
    assert diagnostics.provider_length == len(provider)
    assert diagnostics.validation_category == "source_segment_not_found"
    assert diagnostics.first_mismatch_offset == 6
    assert diagnostics.source_unicode_class == "Pd"
    assert diagnostics.provider_unicode_class == "Pd"
    assert diagnostics.nfc_equivalent is False
    assert diagnostics.whitespace_collapse_equivalent is False
    assert diagnostics.punctuation_normalization_equivalent is True
    assert diagnostics.values_truncated is False

    oversized_source = "a" * 5000
    oversized_provider = "b" * 9000
    with pytest.raises(BookNarrationUnavailableError) as oversized_failure:
        _alignment_from_provider_segments(
            oversized_source,
            [
                {
                    "text": oversized_provider,
                    "text_begin": 0,
                    "text_end": len(oversized_provider),
                    "time_begin": 0.0,
                    "time_end": 900.0,
                }
            ],
            duration_ms=1000,
        )
    oversized = oversized_failure.value.alignment_diagnostics
    assert oversized is not None
    assert oversized.source_length == 4096
    assert oversized.provider_length == 4096
    assert oversized.first_mismatch_offset == 0
    assert oversized.values_truncated is True


def test_alignment_diagnostics_classify_whitespace_only_difference():
    with pytest.raises(BookNarrationUnavailableError) as failure:
        _alignment_from_provider_segments(
            "Alpha Beta",
            [
                {
                    "text": "Alpha",
                    "text_begin": 0,
                    "text_end": 5,
                    "time_begin": 0.0,
                    "time_end": 400.0,
                },
                {
                    "text": "Beta",
                    "text_begin": 5,
                    "text_end": 9,
                    "time_begin": 300.0,
                    "time_end": 900.0,
                },
            ],
            duration_ms=1000,
        )

    diagnostics = failure.value.alignment_diagnostics
    assert diagnostics is not None
    assert diagnostics.validation_category == "time_non_monotonic"
    assert diagnostics.first_mismatch_offset == 5
    assert diagnostics.source_unicode_class == "Zs"
    assert diagnostics.provider_unicode_class == "Lu"
    assert diagnostics.whitespace_collapse_equivalent is True
    assert diagnostics.punctuation_normalization_equivalent is False


@pytest.mark.parametrize("second_begin", [4, 6])
def test_non_contiguous_provider_ranges_are_rejected(second_begin):
    with pytest.raises(BookNarrationUnavailableError):
        _alignment_from_provider_segments(
            "Alpha Beta",
            [
                {
                    "text": "Alpha",
                    "text_begin": 0,
                    "text_end": 5,
                    "time_begin": 0.0,
                    "time_end": 400.0,
                },
                {
                    "text": "Beta",
                    "text_begin": second_begin,
                    "text_end": second_begin + 4,
                    "time_begin": 450.0,
                    "time_end": 900.0,
                },
            ],
            duration_ms=1000,
        )


def test_provider_segments_may_not_skip_non_whitespace_source_text():
    with pytest.raises(BookNarrationUnavailableError):
        _alignment_from_provider_segments(
            "Alpha hidden Beta",
            [
                {
                    "text": "Alpha",
                    "text_begin": 0,
                    "text_end": 5,
                    "time_begin": 0.0,
                    "time_end": 400.0,
                },
                {
                    "text": "Beta",
                    "text_begin": 5,
                    "text_end": 9,
                    "time_begin": 450.0,
                    "time_end": 900.0,
                },
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


@pytest.mark.parametrize("subtitle", [None, "", 42])
def test_valid_audio_does_not_require_optional_subtitle_url(subtitle):
    parsed = _parse_minimax_response({
        "base_resp": {"status_code": 0},
        "data": {"status": 2, "audio": (b"\xff\xfb" + b"a" * 126).hex(), "subtitle_file": subtitle},
        "extra_info": {"audio_length": 1000},
    })
    assert parsed.duration_ms == 1000
    assert len(parsed.audio_bytes) == 128
    assert parsed.subtitle_url is None


@pytest.mark.parametrize("duration", [float("nan"), float("inf"), True, 0, -1])
def test_missing_timing_does_not_relax_required_audio_duration(duration):
    with pytest.raises(BookNarrationUnavailableError) as raised:
        _parse_minimax_response({
            "base_resp": {"status_code": 0},
            "data": {"status": 2, "audio": (b"\xff\xfb" + b"a" * 126).hex()},
            "extra_info": {"audio_length": duration},
        })
    assert raised.value.reason_code == "duration_invalid"


def test_provider_rejection_diagnostic_keeps_only_numeric_code():
    with pytest.raises(BookNarrationUnavailableError) as raised:
        _parse_minimax_response({"base_resp": {"status_code": 1004, "status_msg": "PRIVATE_PROVIDER_BODY"}})
    assert raised.value.provider_status == 1004
    assert raised.value.reason_code == "provider_rejected"
    assert "PRIVATE_PROVIDER_BODY" not in str(raised.value)


@pytest.mark.asyncio
@pytest.mark.parametrize("provider", ["yunwu", "openlux"])
async def test_native_gateway_uses_only_explicit_provider_credential(monkeypatch, provider):
    monkeypatch.setattr(settings, "book_narration_provider", provider)
    monkeypatch.setattr(settings, "book_narration_api_base_url", f"https://{provider}.example/minimax/v1")
    monkeypatch.setattr(settings, "yunwu_api_key", "YUNWU_TEST_KEY")
    monkeypatch.setattr(settings, "openlux_api_key", "OPENLUX_TEST_KEY")
    observed = []
    async def handler(request):
        observed.append(request)
        return httpx.Response(200, json={
            "base_resp": {"status_code": 0},
            "data": {"status": 2, "audio": (b"\xff\xfb" + b"a" * 126).hex()},
            "extra_info": {"audio_length": 1000},
        })
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await _synthesize_with_minimax("Private passage", preset=_STYLE_PRESETS["expressive"],
                                       profile=_narrator_profile("expressive_narrator"), client=client)
    assert len(observed) == 1
    assert str(observed[0].url) == f"https://{provider}.example/minimax/v1/t2a_v2"
    assert observed[0].headers["authorization"] == f"Bearer {provider.upper()}_TEST_KEY"


@pytest.mark.asyncio
async def test_gateway_http_failure_exposes_safe_status_without_retry(monkeypatch):
    monkeypatch.setattr(settings, "book_narration_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "PRIVATE_TEST_KEY")
    calls = []
    async def handler(request):
        calls.append(request)
        return httpx.Response(403, text="PRIVATE_PROVIDER_BODY")
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(BookNarrationUnavailableError) as raised:
            await _synthesize_with_minimax("PRIVATE_PASSAGE", preset=_STYLE_PRESETS["expressive"],
                                           profile=_narrator_profile("expressive_narrator"), client=client)
    assert len(calls) == 1
    assert raised.value.reason_code == "provider_http_error"
    assert raised.value.http_status == 403
    assert raised.value.retryable is False
    assert "PRIVATE" not in str(raised.value)


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
async def test_subtitle_transport_error_is_classified_as_retryable(monkeypatch):
    monkeypatch.setattr(
        book_narration,
        "_assert_safe_subtitle_url",
        AsyncMock(return_value=None),
    )

    async def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("offline", request=request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(BookNarrationUnavailableError) as failure:
            await _fetch_subtitle_document(
                "https://provider.example/subtitle.json",
                client=client,
            )

    assert failure.value.reason_code == "subtitle_transport_error"
    assert failure.value.retryable is True


@pytest.mark.asyncio
async def test_subtitle_retry_is_bounded_and_only_for_transient_errors(monkeypatch):
    document = [{"text": "Ready"}]
    transient = BookNarrationUnavailableError(
        "temporary",
        reason_code="subtitle_transport_error",
        retryable=True,
    )
    fetch = AsyncMock(side_effect=[transient, document])
    sleep = AsyncMock()
    monkeypatch.setattr(book_narration, "_fetch_subtitle_document", fetch)
    monkeypatch.setattr(book_narration.asyncio, "sleep", sleep)

    assert await _fetch_subtitle_with_retry("https://provider.example") == document
    assert fetch.await_count == 2
    sleep.assert_awaited_once_with(0.2)

    rejected = BookNarrationUnavailableError(
        "rejected",
        reason_code="subtitle_host_rejected",
    )
    fetch.reset_mock(side_effect=True)
    fetch.side_effect = rejected
    with pytest.raises(BookNarrationUnavailableError) as failure:
        await _fetch_subtitle_with_retry("https://provider.example")
    assert failure.value is rejected
    assert fetch.await_count == 1


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


@pytest.mark.asyncio
async def test_render_logs_alignment_structure_without_source_or_provider_text(
    monkeypatch,
    tmp_path,
    caplog,
):
    source = "Alpha — Beta"
    provider = "Alpha - Beta"
    synthesis = _MiniMaxSynthesis(
        audio_bytes=b"\xff\xfb" + (b"a" * 256),
        duration_ms=1600,
        subtitle_url="https://provider.example/private-signed-subtitle.json",
    )
    monkeypatch.setattr(settings, "book_narration_enabled", True)
    monkeypatch.setattr(settings, "yunwu_api_key", "test-key")
    monkeypatch.setattr(settings, "book_narration_media_dir", str(tmp_path))
    monkeypatch.setattr(
        book_narration,
        "_synthesize_with_minimax",
        AsyncMock(return_value=synthesis),
    )
    monkeypatch.setattr(
        book_narration,
        "_fetch_subtitle_with_retry",
        AsyncMock(
            return_value=[
                {
                    "text": provider,
                    "text_begin": 0,
                    "text_end": len(provider),
                    "time_begin": 0.0,
                    "time_end": 1500.0,
                }
            ]
        ),
    )
    book_narration._locks.clear()

    asset = await render_book_narration(source, "expressive")

    assert asset.alignment_source == "none"
    assert "alignment_segment_index=0" in caplog.text
    assert "alignment_segment_count=1" in caplog.text
    assert "alignment_source_length=12" in caplog.text
    assert "alignment_provider_length=12" in caplog.text
    assert "alignment_validation=source_segment_not_found" in caplog.text
    assert "alignment_first_mismatch_offset=6" in caplog.text
    assert "alignment_source_unicode_class=Pd" in caplog.text
    assert "alignment_provider_unicode_class=Pd" in caplog.text
    assert "alignment_nfc_equivalent=False" in caplog.text
    assert "alignment_whitespace_collapse_equivalent=False" in caplog.text
    assert "alignment_punctuation_normalization_equivalent=True" in caplog.text
    assert "alignment_values_truncated=False" in caplog.text
    assert source not in caplog.text
    assert provider not in caplog.text
    assert synthesis.subtitle_url not in caplog.text
    assert "test-key" not in caplog.text


@pytest.mark.asyncio
async def test_render_reuses_recording_with_missing_provider_timing(
    monkeypatch,
    tmp_path,
    caplog,
):
    text = "Playback should remain available."
    synthesis = _MiniMaxSynthesis(
        audio_bytes=b"\xff\xfb" + (b"a" * 256),
        duration_ms=1600,
        subtitle_url="https://provider.example/subtitle.json",
    )
    synthesize = AsyncMock(return_value=synthesis)
    fetch_subtitle = AsyncMock(
        side_effect=[
            BookNarrationUnavailableError(
                "temporary timing failure",
                reason_code="subtitle_alignment_inconsistent",
            ),
            [
                {
                    "text": text,
                    "text_begin": 0,
                    "text_end": len(text),
                    "time_begin": 0.0,
                    "time_end": 1500.0,
                }
            ],
        ]
    )
    monkeypatch.setattr(settings, "book_narration_enabled", True)
    monkeypatch.setattr(settings, "yunwu_api_key", "test-key")
    monkeypatch.setattr(settings, "book_narration_media_dir", str(tmp_path))
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

    first = await render_book_narration(text, "expressive")
    second = await render_book_narration(text, "expressive")

    assert first.alignment_source == "none"
    assert first.alignment == ()
    assert second.alignment_source == "none"
    assert second.alignment == ()
    assert second.audio_url == first.audio_url
    assert second.cached
    assert synthesize.await_count == 1
    assert fetch_subtitle.await_count == 1
    assert "reason=subtitle_alignment_inconsistent" in caplog.text
    assert text not in caplog.text
    assert synthesis.subtitle_url not in caplog.text


@pytest.mark.asyncio
async def test_audio_only_cache_works_without_credential_and_keeps_provider_identity(monkeypatch, tmp_path):
    import asyncio
    from pathlib import Path
    text = "A saved recording remains available."
    synthesize = AsyncMock(return_value=_MiniMaxSynthesis(
        audio_bytes=b"\xff\xfb" + b"a" * 256, duration_ms=1600, subtitle_url=None,
    ))
    subtitle = AsyncMock(side_effect=AssertionError("No subtitle URL should be fetched"))
    monkeypatch.setattr(settings, "book_narration_enabled", True)
    monkeypatch.setattr(settings, "book_narration_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "YUNWU_TEST_KEY")
    monkeypatch.setattr(settings, "openlux_api_key", None)
    monkeypatch.setattr(settings, "book_narration_media_dir", str(tmp_path))
    monkeypatch.setattr(book_narration, "_synthesize_with_minimax", synthesize)
    monkeypatch.setattr(book_narration, "_fetch_subtitle_with_retry", subtitle)
    book_narration._locks.clear()

    first, concurrent = await asyncio.gather(
        render_book_narration(text, "expressive"), render_book_narration(text, "expressive"),
    )
    assert first.audio_url == concurrent.audio_url
    assert first.alignment_source == "none" and first.alignment == ()
    assert Path(tmp_path / Path(first.audio_url).name).stat().st_size == 258
    synthesize.assert_awaited_once()
    subtitle.assert_not_awaited()
    monkeypatch.setattr(settings, "yunwu_api_key", None)
    cached = await render_book_narration(text, "expressive")
    assert cached.cached and cached.audio_url == first.audio_url
    synthesize.assert_awaited_once()

    # Choosing another provider never borrows the old provider's credential or
    # labels its cache as a recording from the newly selected provider.
    monkeypatch.setattr(settings, "book_narration_provider", "openlux")
    with pytest.raises(BookNarrationUnavailableError, match="not configured"):
        await render_book_narration(text, "expressive")
    synthesize.assert_awaited_once()
    monkeypatch.setattr(settings, "openlux_api_key", "OPENLUX_TEST_KEY")
    openlux_asset = await render_book_narration(text, "expressive")
    assert openlux_asset.provider == "openlux"
    assert openlux_asset.audio_url != first.audio_url
    assert synthesize.await_args.kwargs["provider"] == "openlux"
    assert synthesize.await_count == 2


@pytest.mark.parametrize("enabled,provider,expected_load", [
    (True, "openlux", True), (False, "openlux", False), (True, "yunwu", False),
])
def test_narration_can_load_openlux_secret_without_switching_text_provider(monkeypatch, enabled, provider, expected_load):
    from unittest.mock import Mock
    from app.core import credentials
    from app.core.config import Settings
    read_secret = Mock(return_value="OPENLUX_TEST_SECRET")
    monkeypatch.setattr(credentials, "read_aws_secret", read_secret)
    config = Settings(
        _env_file=None, llm_provider="zai", zai_api_key="ZAI_TEST_KEY", zai_secret_id=None,
        google_books_secret_id=None, openlux_api_key=None, openlux_secret_id="test/openlux",
        openlux_secret_region="us-east-1", openlux_keychain_service=None,
        book_narration_provider=provider, book_narration_enabled=enabled,
    )
    assert config.llm_provider == "zai" and config.zai_api_key == "ZAI_TEST_KEY"
    assert read_secret.call_count == int(expected_load)
    assert config.openlux_api_key == ("OPENLUX_TEST_SECRET" if expected_load else None)
    assert "OPENLUX_TEST_SECRET" not in repr(config)
