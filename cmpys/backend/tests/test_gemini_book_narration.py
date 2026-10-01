import asyncio
import base64
import copy
import hashlib
import json
import struct
from pathlib import Path
from unittest.mock import AsyncMock

import httpx
import pytest

from app.core.config import Settings, settings
from app.services import book_narration as narration


def _chunk(name, body):
    return name + struct.pack("<I", len(body)) + body + (b"\0" if len(body) % 2 else b"")


def _wav(*, frames=24000, channels=1, rate=24000, bits=16, encoding=1, metadata=True):
    frame_bytes = channels * (bits // 8)
    chunks = _chunk(b"fmt ", struct.pack("<HHIIHH", encoding, channels, rate, rate * frame_bytes, frame_bytes, bits))
    if metadata:
        chunks += _chunk(b"JUNK", b"provider metadata" * 353)
    chunks += _chunk(b"data", b"\0" * (frames * frame_bytes))
    if metadata:
        chunks += _chunk(b"LIST", b"odd")
    return b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks


def _response(audio=None):
    return {"candidates": [{"finishReason": "STOP", "content": {"parts": [{
        "inlineData": {"mimeType": "audio/wav", "data": base64.b64encode(audio if audio is not None else _wav()).decode("ascii")},
    }]}}]}


@pytest.fixture(autouse=True)
def gemini_settings(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "book_narration_enabled", True)
    monkeypatch.setattr(settings, "book_narration_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", "GEMINI_TEST_SECRET")
    monkeypatch.setattr(settings, "book_narration_gemini_model", "gemini-3.8-flash-tts")
    monkeypatch.setattr(settings, "book_narration_gemini_voice", "Sulafat")
    monkeypatch.setattr(settings, "book_narration_gemini_mentor_voice", "Gacrux")
    monkeypatch.setattr(settings, "book_narration_media_dir", str(tmp_path))
    narration._locks.clear()


def test_gemini_defaults_are_isolated_from_minimax_model_and_voices(monkeypatch):
    monkeypatch.delenv("BOOK_NARRATION_PROVIDER", raising=False)
    config = Settings(
        _env_file=None, llm_provider="dummy", google_books_secret_id=None,
        book_narration_tts_model="speech-2.8-hd", book_narration_voice_id="Legacy voice",
        book_narration_mentor_voice_id="Legacy mentor",
    )
    assert config.book_narration_provider == "gemini"
    assert config.book_narration_gemini_model == "gemini-3.8-flash-tts"
    assert config.book_narration_gemini_voice == "Sulafat"
    assert config.book_narration_gemini_mentor_voice == "Gacrux"


@pytest.mark.asyncio
async def test_native_request_keeps_directions_out_of_transcript_and_uses_google_key(monkeypatch):
    monkeypatch.setattr(settings, "book_narration_api_base_url", "https://legacy.invalid/minimax")
    monkeypatch.setattr(settings, "book_narration_tts_model", "legacy-model")
    monkeypatch.setattr(settings, "yunwu_api_key", "DO_NOT_USE_LEGACY_KEY")
    observed = []
    audio = _wav(frames=391680)

    async def handler(request):
        observed.append(request)
        return httpx.Response(200, json=_response(audio))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await narration._synthesize_with_gemini(
            "Read these exact words.", style="warm",
            profile=narration._narrator_profile("seasoned_mentor"), client=client,
        )
    assert len(observed) == 1
    request = observed[0]
    assert str(request.url) == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash-tts:generateContent"
    assert request.headers["x-goog-api-key"] == "GEMINI_TEST_SECRET"
    assert "authorization" not in request.headers
    document = json.loads(request.content)
    assert document["contents"] == [{"role": "user", "parts": [{
        "text": "Read these exact words.",
        "speech_metadata": {"style": narration._GEMINI_STYLES["warm"]},
    }]}]
    assert document["generationConfig"] == {
        "responseModalities": ["AUDIO"],
        "speechConfig": {"voiceConfig": {"voice": "Gacrux"}},
    }
    assert result.audio_bytes == audio  # Already WAV: never wrap it a second time.
    assert result.duration_ms == 16320  # Metadata chunks do not count as speech.


@pytest.mark.parametrize("finish_reason", [None, "MAX_TOKENS", "SAFETY", "OTHER", "RECITATION"])
def test_partial_audio_is_rejected_even_if_decodable(finish_reason):
    document = _response()
    document["candidates"][0]["finishReason"] = finish_reason
    with pytest.raises(narration.BookNarrationUnavailableError) as raised:
        narration._parse_gemini_response(document)
    assert raised.value.reason_code == "audio_incomplete"


@pytest.mark.parametrize("document", [None, [], {}, {"candidates": []}, {"candidates": [None]}])
def test_absent_or_malformed_candidate_is_rejected(document):
    with pytest.raises(narration.BookNarrationUnavailableError):
        narration._parse_gemini_response(document)


@pytest.mark.parametrize("kind", ["prompt", "candidate"])
def test_blocked_response_has_sanitized_error(kind):
    document = _response()
    if kind == "prompt":
        document["promptFeedback"] = {"blockReason": "SAFETY", "blockReasonMessage": "PRIVATE_PROVIDER_BODY"}
    else:
        document["candidates"][0]["safetyRatings"] = [{"blocked": True, "category": "PRIVATE_PROVIDER_BODY"}]
    with pytest.raises(narration.BookNarrationUnavailableError) as raised:
        narration._parse_gemini_response(document)
    assert raised.value.reason_code == "provider_rejected"
    assert "PRIVATE" not in str(raised.value)


@pytest.mark.parametrize("encoded", ["%%%", "AAAA!", "私密", "YWJj\n", ""])
def test_base64_must_be_strict(encoded):
    document = _response()
    document["candidates"][0]["content"]["parts"][0]["inlineData"]["data"] = encoded
    with pytest.raises(narration.BookNarrationUnavailableError):
        narration._parse_gemini_response(document)


@pytest.mark.parametrize("mime", [None, "audio/mpeg", "audio/L16;codec=pcm;rate=24000", "text/html"])
def test_no_guessing_raw_pcm_or_other_formats(mime):
    document = _response()
    document["candidates"][0]["content"]["parts"][0]["inlineData"]["mimeType"] = mime
    with pytest.raises(narration.BookNarrationUnavailableError) as raised:
        narration._parse_gemini_response(document)
    assert raised.value.reason_code == "audio_format_invalid"


def test_multiple_audio_parts_are_not_silently_truncated():
    document = _response()
    parts = document["candidates"][0]["content"]["parts"]
    parts.append(copy.deepcopy(parts[0]))
    with pytest.raises(narration.BookNarrationUnavailableError):
        narration._parse_gemini_response(document)


@pytest.mark.parametrize("limit_delta", [-1, -3])
def test_encoded_and_decoded_size_limits(monkeypatch, limit_delta):
    audio = _wav(frames=240, metadata=False)
    monkeypatch.setattr(settings, "book_narration_max_audio_bytes", len(audio) + limit_delta)
    with pytest.raises(narration.BookNarrationUnavailableError) as raised:
        narration._parse_gemini_response(_response(audio))
    assert raised.value.reason_code == "audio_too_large"


@pytest.mark.parametrize("audio", [
    b"not a wave file" * 100,
    _wav()[:-2], _wav() + b"unexpected trailing bytes",
    _wav(frames=0), _wav(channels=2), _wav(rate=22050), _wav(bits=8), _wav(encoding=3),
])
def test_wav_headers_frames_and_positive_duration_are_required(audio):
    with pytest.raises(narration.BookNarrationUnavailableError) as raised:
        narration._parse_gemini_response(_response(audio))
    assert raised.value.reason_code == "audio_invalid"


def test_incomplete_data_chunk_cannot_pass_with_repaired_outer_size():
    audio = _wav(metadata=False)[:-2]
    audio = audio[:4] + struct.pack("<I", len(audio) - 8) + audio[8:]
    with pytest.raises(narration.BookNarrationUnavailableError):
        narration._parse_gemini_response(_response(audio))


@pytest.mark.asyncio
@pytest.mark.parametrize("status,retryable", [(302, False), (403, False), (429, True), (503, True)])
async def test_http_errors_are_sanitized_and_never_automatically_retried(status, retryable):
    observed = []
    async def handler(request):
        observed.append(request)
        return httpx.Response(status, headers={"Location": "https://private.invalid"}, text="PRIVATE_PROVIDER_BODY")
    # Even an injected client's default must not allow credential redirects.
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler), follow_redirects=True) as client:
        with pytest.raises(narration.BookNarrationUnavailableError) as raised:
            await narration._synthesize_with_gemini(
                "PRIVATE_PASSAGE", style="expressive",
                profile=narration._narrator_profile("expressive_narrator"), client=client,
            )
    assert len(observed) == 1
    assert raised.value.http_status == status
    assert raised.value.retryable is retryable
    assert "PRIVATE" not in str(raised.value)


class _DelayedBody(httpx.AsyncByteStream):
    closed = False

    async def __aiter__(self):
        yield b'{"candidates":'
        await asyncio.sleep(10)

    async def aclose(self):
        self.closed = True


@pytest.mark.asyncio
async def test_wall_clock_deadline_cancels_response_and_closes_stream(monkeypatch):
    monkeypatch.setattr(settings, "book_narration_timeout_seconds", 0.02)
    stream = _DelayedBody()
    async def handler(request):
        return httpx.Response(200, stream=stream)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(narration.BookNarrationUnavailableError) as raised:
            await narration._synthesize_with_gemini(
                "Read this.", style="expressive",
                profile=narration._narrator_profile("expressive_narrator"), client=client,
            )
    assert raised.value.reason_code == "provider_timeout"
    assert stream.closed


@pytest.mark.asyncio
@pytest.mark.parametrize("declared", [True, False])
async def test_response_body_is_bounded_before_json_decoding(monkeypatch, declared):
    monkeypatch.setattr(settings, "book_narration_max_audio_bytes", 128)
    body = b"x" * 70_000
    async def handler(request):
        response = httpx.Response(200, content=body)
        if not declared:
            del response.headers["content-length"]
        return response
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(narration.BookNarrationUnavailableError) as raised:
            await narration._synthesize_with_gemini(
                "Read this.", style="expressive",
                profile=narration._narrator_profile("expressive_narrator"), client=client,
            )
    assert raised.value.reason_code == "audio_too_large"


@pytest.mark.asyncio
async def test_saved_wav_is_reused_without_key_subtitles_or_legacy_configuration(monkeypatch, tmp_path, caplog):
    audio = _wav()
    synthesize = AsyncMock(return_value=narration._GeminiSynthesis(audio, 1000))
    legacy = AsyncMock(side_effect=AssertionError("No fallback allowed"))
    subtitle = AsyncMock(side_effect=AssertionError("Gemini has no exact timing"))
    monkeypatch.setattr(narration, "_synthesize_with_gemini", synthesize)
    monkeypatch.setattr(narration, "_synthesize_with_minimax", legacy)
    monkeypatch.setattr(narration, "_fetch_subtitle_with_retry", subtitle)
    first, concurrent = await asyncio.gather(
        narration.render_book_narration("A saved passage.", "expressive"),
        narration.render_book_narration("A saved passage.", "expressive"),
    )
    assert first.audio_url == concurrent.audio_url
    assert first.audio_url.endswith(".wav")
    assert (tmp_path / Path(first.audio_url).name).read_bytes() == audio
    assert first.provider == "gemini" and first.model == "gemini-3.8-flash-tts"
    assert first.voice == "Sulafat" and first.duration_ms == 1000
    assert first.alignment == () and first.alignment_source == first.alignment_granularity == "none"
    monkeypatch.setattr(settings, "gemini_api_key", None)
    monkeypatch.setattr(settings, "book_narration_tts_model", "changed-legacy-model")
    monkeypatch.setattr(settings, "book_narration_api_base_url", "https://legacy.invalid")
    cached = await narration.render_book_narration("A saved passage.", "expressive")
    assert cached.cached and cached.audio_url == first.audio_url
    synthesize.assert_awaited_once()
    legacy.assert_not_awaited()
    subtitle.assert_not_awaited()
    assert "timing unavailable" not in caplog.text


@pytest.mark.asyncio
@pytest.mark.parametrize("changed_setting,value", [
    ("book_narration_gemini_voice", "Kore"),
    ("book_narration_gemini_model", "gemini-3.8-flash-lite-tts"),
])
async def test_gemini_cache_tracks_actual_model_and_voice(monkeypatch, changed_setting, value):
    synthesize = AsyncMock(return_value=narration._GeminiSynthesis(_wav(), 1000))
    monkeypatch.setattr(narration, "_synthesize_with_gemini", synthesize)
    first = await narration.render_book_narration("Read this.", "expressive")
    monkeypatch.setattr(settings, changed_setting, value)
    second = await narration.render_book_narration("Read this.", "expressive")
    assert first.audio_url != second.audio_url
    assert not second.cached and synthesize.await_count == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("corruption", ["audio", "duration"])
async def test_corrupt_wav_cache_is_rejected(monkeypatch, tmp_path, corruption):
    synthesize = AsyncMock(return_value=narration._GeminiSynthesis(_wav(), 1000))
    monkeypatch.setattr(narration, "_synthesize_with_gemini", synthesize)
    first = await narration.render_book_narration("Read this.", "expressive")
    path = tmp_path / Path(first.audio_url).name
    if corruption == "audio":
        path.write_bytes(path.read_bytes()[:-2])
    else:
        metadata_path = path.with_suffix(".json")
        metadata = json.loads(metadata_path.read_text())
        metadata["durationMs"] = 2000
        metadata_path.write_text(json.dumps(metadata))
    recovered = await narration.render_book_narration("Read this.", "expressive")
    assert not recovered.cached and synthesize.await_count == 2


@pytest.mark.asyncio
async def test_missing_google_key_never_borrows_other_provider_keys(monkeypatch):
    monkeypatch.setattr(settings, "gemini_api_key", None)
    monkeypatch.setattr(settings, "yunwu_api_key", "LEGACY_KEY")
    monkeypatch.setattr(settings, "openlux_api_key", "OTHER_KEY")
    synthesis = AsyncMock()
    monkeypatch.setattr(narration, "_synthesize_with_gemini", synthesis)
    with pytest.raises(narration.BookNarrationUnavailableError) as raised:
        await narration.render_book_narration("No saved passage.", "expressive")
    assert raised.value.reason_code == "provider_not_configured"
    synthesis.assert_not_awaited()


@pytest.mark.asyncio
async def test_legacy_mp3_cache_fingerprint_is_unchanged(monkeypatch):
    monkeypatch.setattr(settings, "book_narration_provider", "yunwu")
    monkeypatch.setattr(settings, "yunwu_api_key", "LEGACY_KEY")
    synthesize = AsyncMock(return_value=narration._MiniMaxSynthesis(b"\xff\xfb" + b"a" * 256, 1000, None))
    monkeypatch.setattr(narration, "_synthesize_with_minimax", synthesize)
    text = "Saved legacy passage."
    expected = hashlib.sha256("\n".join((
        "minimax-narration-v4", "yunwu", settings.book_narration_api_base_url.rstrip("/"),
        settings.book_narration_tts_model, "expressive_narrator", settings.book_narration_voice_id,
        "expressive", "1.0", "0", "provider-subtitle-word-request",
        hashlib.sha256(text.encode()).hexdigest(),
    )).encode()).hexdigest()
    asset = await narration.render_book_narration(text, "expressive")
    assert asset.audio_url == f"/media/book_narration_{expected}.mp3"
