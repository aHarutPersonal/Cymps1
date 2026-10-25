import asyncio
import json
from unittest.mock import AsyncMock

import httpx
import pytest

from app.core.config import settings
from app.services import book_narration as narration
from tests.test_gemini_book_narration import _wav


def document(words):
    return {"status": "completed", "steps": [{"content": [{"annotations": [
        {"type": "word_info", "text": word, "start_offset": f"{i + .1}s",
         "end_offset": f"{i + .6}s"} for i, word in enumerate(words)
    ]}]}]}


@pytest.mark.asyncio
async def test_slow_alignment_never_holds_cold_or_cached_audio(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "book_narration_enabled", True)
    monkeypatch.setattr(settings, "book_narration_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", "TEST_KEY")
    monkeypatch.setattr(settings, "book_narration_media_dir", str(tmp_path))
    started, release = asyncio.Event(), asyncio.Event()
    async def slow(*args, **kwargs):
        started.set()
        await release.wait()
        return ()
    synthesize = AsyncMock(return_value=narration._GeminiSynthesis(_wav(frames=48000), 2000))
    monkeypatch.setattr(narration, "_synthesize_with_gemini", synthesize)
    monkeypatch.setattr(narration, "_gemini_word_alignment", slow)
    first = await asyncio.wait_for(narration.render_book_narration("Hello world", "expressive"), 1)
    await started.wait()
    second = await asyncio.wait_for(narration.render_book_narration("Hello world", "expressive"), 1)
    assert first.audio_url == second.audio_url and first.alignment_pending and second.alignment_pending
    synthesize.assert_awaited_once()
    release.set()
    await asyncio.gather(*narration._alignment_tasks.values())


def test_acoustic_ranges_keep_pauses_and_utf16_source_offsets():
    cues = narration._transcription_word_cues("😀 Hello, WORLD!", document(["hello", "World."]), duration_ms=2500)
    assert [(c.start, c.end, c.startMs, c.endMs, c.text) for c in cues] == [
        (3, 8, 100, 600, "Hello"), (10, 15, 1100, 1600, "WORLD"),
    ]


@pytest.mark.parametrize("words", [["hello"], ["hello", "wrong"], ["hello", "world", "extra"]])
def test_missing_added_and_substituted_words_never_receive_guessed_cues(words):
    assert narration._transcription_word_cues("Hello world", document(words), duration_ms=4000) == ()


@pytest.mark.parametrize("bad_value", ["0.500s", "NaNs", None, "9999s", "-1s"])
def test_bad_final_timestamp_is_omitted_without_fabricating_an_endpoint(bad_value):
    words = [f"word{i}" for i in range(10)]
    data = document(words)
    data["steps"][0]["content"][0]["annotations"][-1]["end_offset"] = bad_value
    cues = narration._transcription_word_cues(" ".join(words), data, duration_ms=10000)
    assert len(cues) == 9
    assert cues[-1].text == "word8"


def test_low_coverage_or_overlapping_timestamps_are_not_published():
    data = document(["Hello", "world"])
    data["steps"][0]["content"][0]["annotations"][1]["start_offset"] = "0.500s"
    assert narration._transcription_word_cues("Hello world", data, duration_ms=2000) == ()


@pytest.mark.asyncio
async def test_transcription_uses_audio_without_retaining_interaction(monkeypatch):
    monkeypatch.setattr(settings, "gemini_api_key", "TEST_KEY")
    async def handler(request):
        payload = json.loads(request.content)
        assert payload["store"] is False
        assert payload["input"][0] == {"type": "audio", "mime_type": "audio/wav", "data": "d2F2"}
        assert payload["generation_config"]["transcription_config"]["mode"]["timestamp_granularities"] == ["word"]
        return httpx.Response(200, json=document(["Hello", "world"]))
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        cues = await narration._gemini_word_alignment("Hello world", b"wav", duration_ms=2000, client=client)
    assert len(cues) == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["http", "large", "invalid", "timeout"])
async def test_transcription_failure_leaves_audio_usable(monkeypatch, failure):
    monkeypatch.setattr(settings, "gemini_api_key", "TEST_KEY")
    monkeypatch.setattr(settings, "book_narration_max_subtitle_bytes", 100)
    async def handler(request):
        if failure == "timeout":
            raise httpx.ReadTimeout("sensitive provider details")
        return httpx.Response(503 if failure == "http" else 200,
                              content=b"x" * (101 if failure == "large" else 10))
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        assert await narration._gemini_word_alignment("Hello", b"wav", duration_ms=2000, client=client) == ()


@pytest.mark.asyncio
@pytest.mark.parametrize("success", [True, False])
async def test_existing_recording_gets_one_alignment_attempt_without_resynthesis(monkeypatch, tmp_path, success):
    monkeypatch.setattr(settings, "book_narration_enabled", True)
    monkeypatch.setattr(settings, "book_narration_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", "TEST_KEY")
    monkeypatch.setattr(settings, "book_narration_media_dir", str(tmp_path))
    synthesize = AsyncMock(return_value=narration._GeminiSynthesis(_wav(frames=48000), 2000))
    align = AsyncMock(return_value=())
    monkeypatch.setattr(narration, "_synthesize_with_gemini", synthesize)
    monkeypatch.setattr(narration, "_gemini_word_alignment", align)
    first = await narration.render_book_narration("Hello world", "expressive")
    assert first.alignment_pending
    await asyncio.gather(*narration._alignment_tasks.values())
    metadata_path = next(tmp_path.glob("*.json"))
    metadata = json.loads(metadata_path.read_text())
    metadata.pop("alignmentAttempted")  # Simulate an older paid recording.
    metadata_path.write_text(json.dumps(metadata))
    cues = narration._transcription_word_cues("Hello world", document(["Hello", "world"]), duration_ms=2000)
    align.return_value = cues if success else ()
    second = await narration.render_book_narration("Hello world", "expressive")
    assert second.alignment_pending
    await asyncio.gather(*narration._alignment_tasks.values())
    third = await narration.render_book_narration("Hello world", "expressive")
    assert synthesize.await_count == 1
    assert align.await_count == 2  # Initial recording and one legacy upgrade.
    assert first.audio_url == second.audio_url == third.audio_url
    assert second.cached and third.cached
    assert third.alignment == (cues if success else ())
    assert third.alignment_source == ("transcription" if success else "none")
