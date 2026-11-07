"""Expressive, cached Gemini audiobook narration with measured word timing."""

from __future__ import annotations

import asyncio
import base64
import binascii
import hashlib
import html
import json
import logging
import os
import re
import struct
import unicodedata
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Any
from uuid import uuid4

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class BookNarrationUnavailableError(RuntimeError):
    """The configured expressive narration provider could not be used."""

    def __init__(
        self,
        message: str,
        *,
        reason_code: str = "narration_unavailable",
        retryable: bool = False,
        http_status: int | None = None,
    ) -> None:
        super().__init__(message)
        self.reason_code = (
            reason_code if isinstance(reason_code, str) and re.fullmatch(r"[a-z0-9_]{1,64}", reason_code)
            else "narration_unavailable"
        )
        self.retryable = retryable
        self.http_status = (
            http_status if type(http_status) is int and 100 <= http_status <= 599
            else None
        )


@dataclass(frozen=True)
class NarrationCue:
    """One measured source range using UTF-16 offsets for Flutter."""

    start: int
    end: int
    startMs: int
    endMs: int
    text: str


@dataclass(frozen=True)
class NarrationAsset:
    audio_url: str
    style: str
    voice: str
    voice_display_name: str
    narrator_profile: str
    provider: str
    model: str
    duration_ms: int | None
    alignment: tuple[NarrationCue, ...]
    alignment_source: str
    alignment_granularity: str
    offset_encoding: str
    source_text_hash: str
    disclosure: str
    cached: bool
    alignment_pending: bool = False


@dataclass(frozen=True)
class _NarratorProfile:
    voice_id: str
    display_name: str


@dataclass(frozen=True)
class _GeminiSynthesis:
    audio_bytes: bytes
    duration_ms: int


_PROVIDER = "gemini"
_GEMINI_CACHE_VERSION = "gemini-narration-v1"
_GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
_GEMINI_ALIGNMENT_MODEL = "gemini-3.5-transcribe"
_GEMINI_STYLES = {
    "expressive": "Warm, expressive audiobook narration with natural emphasis and clear, unhurried pacing.",
    "warm": "Warm, gentle audiobook narration with a relaxed pace and natural pauses.",
    "grounded": "Calm, grounded audiobook narration with measured pacing and clear emphasis.",
}
_OFFSET_ENCODING = "utf16"
_DISCLOSURE = "AI-generated voice; not the real person."
_locks: dict[str, asyncio.Lock] = {}
_alignment_tasks: dict[str, asyncio.Task] = {}


def _schedule_alignment(*, digest, text, audio_bytes, duration_ms, audio_path, metadata_path):
    if digest in _alignment_tasks or len(_alignment_tasks) >= 4:
        return
    async def complete():
        try:
            alignment = await _gemini_word_alignment(text, audio_bytes, duration_ms=duration_ms)
            metadata = json.loads(await asyncio.to_thread(metadata_path.read_text, encoding="utf-8"))
            # A timing result can only decorate the exact passage that produced it.
            if metadata.get("sourceTextHash") != _source_text_hash(text):
                return
            metadata.update(_gemini_alignment_metadata(alignment))
            await _write_cache_atomically(audio_path=audio_path, metadata_path=metadata_path,
                                          audio_bytes=audio_bytes, metadata=metadata)
        except Exception as exc:
            logger.warning("Deferred narration alignment failed (%s)", type(exc).__name__)
    task = asyncio.create_task(complete())
    _alignment_tasks[digest] = task
    task.add_done_callback(lambda done: _alignment_tasks.pop(digest, None))
_markdown_image = re.compile(r"!\[([^]]*)\]\([^)]*\)")
_markdown_link = re.compile(r"\[([^]]+)\]\([^)]*\)")
_markdown_ordered_list_marker = re.compile(
    r"(?m)^[ \t]{0,3}(?:>[ \t]{0,3})*\d{1,9}[.)][ \t]+"
)
_source_word = re.compile(r"\w+(?:[\u2019'\-]\w+)*", re.UNICODE)


def narration_text_belongs_to_resource(text: str, markdown: str) -> bool:
    """Allow narration only for passages present in the shared resource.

    The client speaks rendered Markdown, so links and formatting marks are
    removed before comparison. Compact Unicode-normalized comparison is
    intentionally insensitive to whitespace, punctuation, and Markdown.
    """

    requested = _compact_for_membership(text)
    if not requested:
        return False
    source = _compact_for_membership(_markdown_to_visible_text(markdown))
    return requested in source


async def render_book_narration(
    text: str,
    style: str,
    narrator_profile: str = "expressive_narrator",
) -> NarrationAsset:
    """Render or retrieve one expressive narration passage."""

    provider = settings.book_narration_provider.casefold()
    if not settings.book_narration_enabled or provider != _PROVIDER:
        raise BookNarrationUnavailableError(
            "Expressive narration is not configured", reason_code="provider_not_configured"
        )
    if style not in _GEMINI_STYLES:
        raise ValueError(f"Unsupported narration style: {style}")
    profile = _narrator_profile(narrator_profile)

    cleaned_text = text.strip()
    source_text_hash = _source_text_hash(cleaned_text)
    model = settings.book_narration_gemini_model
    # Changing any identity part orphans existing paid recordings.
    identity = (
        _GEMINI_CACHE_VERSION, provider, _GEMINI_API_BASE, model,
        narrator_profile, profile.voice_id, style, _GEMINI_STYLES[style],
        "native-wav-no-alignment", source_text_hash,
    )
    digest = hashlib.sha256(
        "\n".join(identity).encode("utf-8")
    ).hexdigest()
    filename = f"book_narration_{digest}.wav"
    media_dir = Path(settings.book_narration_media_dir)
    audio_path = media_dir / filename
    metadata_path = media_dir / f"book_narration_{digest}.json"

    lock = _locks.setdefault(digest, asyncio.Lock())
    try:
        async with lock:
            cached = await _read_cached_asset(
                audio_path=audio_path,
                metadata_path=metadata_path,
                filename=filename,
            )
            if cached is not None:
                if not cached.alignment:
                    # Upgrade existing paid recordings in place. One bounded
                    # attempt per cache entry, including unavailable alignment.
                    metadata = json.loads(await asyncio.to_thread(metadata_path.read_text, encoding="utf-8"))
                    if not metadata.get("alignmentAttempted") and _narration_api_key():
                        audio_bytes = await asyncio.to_thread(audio_path.read_bytes)
                        _schedule_alignment(digest=digest, text=cleaned_text, audio_bytes=audio_bytes,
                                            duration_ms=cached.duration_ms, audio_path=audio_path,
                                            metadata_path=metadata_path)
                        cached = replace(cached, alignment_pending=True)
                logger.info(
                    "Book narration cache hit provider=%s model=%s chars=%d",
                    provider,
                    model,
                    len(cleaned_text),
                )
                return cached

            # Cached audio does not depend on the provider being reachable or
            # its credential remaining configured after the recording exists.
            if not _narration_api_key():
                raise BookNarrationUnavailableError(
                    "Expressive narration is not configured", reason_code="provider_not_configured"
                )
            await asyncio.to_thread(media_dir.mkdir, parents=True, exist_ok=True)
            started = asyncio.get_running_loop().time()
            try:
                synthesis = await _synthesize_with_gemini(
                    cleaned_text, style=style, profile=profile,
                )
            except BookNarrationUnavailableError:
                raise
            except Exception as exc:
                logger.warning(
                    "Expressive book narration generation failed: %s",
                    type(exc).__name__,
                )
                raise BookNarrationUnavailableError(
                    "Narration generation failed", reason_code="synthesis_unexpected"
                ) from exc
            generation_ms = round((asyncio.get_running_loop().time() - started) * 1000)

            # Validated playable audio is saved before optional word alignment,
            # which a bounded background transcription adds to the cache later.
            metadata = {
                "style": style,
                "voice": profile.voice_id,
                "voiceDisplayName": profile.display_name,
                "narratorProfile": narrator_profile,
                "provider": provider,
                "model": model,
                "durationMs": synthesis.duration_ms,
                "alignment": [],
                "alignmentSource": "none",
                "alignmentGranularity": "none",
                "offsetEncoding": _OFFSET_ENCODING,
                "sourceTextHash": source_text_hash,
                "disclosure": _DISCLOSURE,
                "alignmentAttempted": False,
                "alignmentStatus": "pending",
            }
            await _write_cache_atomically(
                audio_path=audio_path,
                metadata_path=metadata_path,
                audio_bytes=synthesis.audio_bytes,
                metadata=metadata,
            )
            _schedule_alignment(digest=digest, text=cleaned_text, audio_bytes=synthesis.audio_bytes,
                                duration_ms=synthesis.duration_ms, audio_path=audio_path,
                                metadata_path=metadata_path)
            logger.info(
                "Book narration generated provider=%s model=%s chars=%d "
                "duration_ms=%d generation_ms=%d",
                provider,
                model,
                len(cleaned_text),
                synthesis.duration_ms,
                generation_ms,
            )
            return NarrationAsset(
                audio_url=f"/media/{filename}",
                style=style,
                voice=profile.voice_id,
                voice_display_name=profile.display_name,
                narrator_profile=narrator_profile,
                provider=provider,
                model=model,
                duration_ms=synthesis.duration_ms,
                alignment=(),
                alignment_source="none",
                alignment_granularity="none",
                offset_encoding=_OFFSET_ENCODING,
                source_text_hash=source_text_hash,
                disclosure=_DISCLOSURE,
                cached=False,
                alignment_pending=True,
            )
    finally:
        # Avoid retaining one asyncio.Lock for every passage ever requested.
        if _locks.get(digest) is lock and not lock.locked():
            _locks.pop(digest, None)


def _gemini_alignment_metadata(alignment: tuple[NarrationCue, ...]) -> dict:
    return {
        "alignment": [asdict(cue) for cue in alignment],
        "alignmentSource": "transcription" if alignment else "none",
        "alignmentGranularity": "word" if alignment else "none",
        "alignmentAttempted": True,
        "alignmentStatus": "ready" if alignment else "unavailable",
        "alignmentModel": _GEMINI_ALIGNMENT_MODEL,
    }


def _transcription_word_cues(text: str, document: dict, *, duration_ms: int) -> tuple[NarrationCue, ...]:
    """Map acoustic timestamps only when the recognized words match the source.

    Case/punctuation do not affect word identity. Missing or substituted words
    reject the alignment; malformed timing ranges are omitted, never guessed.
    At least 90% of source words must retain valid measured ranges.
    """
    if document.get("status") != "completed":
        return ()
    annotations = [a for step in document.get("steps", [])
                   for content in step.get("content", [])
                   for a in content.get("annotations", []) if a.get("type") == "word_info"]
    source_words = list(_source_word.finditer(text))
    if not source_words or len(annotations) != len(source_words):
        return ()
    def normalized(word):
        return unicodedata.normalize("NFC", word).casefold().replace("\u2019", "'")
    offsets = _utf16_prefix_offsets(text)
    cues = []
    previous_end = 0
    for word, annotation in zip(source_words, annotations):
        recognized = _source_word.findall(str(annotation.get("text") or ""))
        if len(recognized) != 1 or normalized(recognized[0]) != normalized(word.group()):
            return ()
        raw_start, raw_end = annotation.get("start_offset"), annotation.get("end_offset")
        if not all(isinstance(v, str) and re.fullmatch(r"\d+(?:\.\d{1,9})?s", v) for v in (raw_start, raw_end)):
            continue
        start, end = round(float(raw_start[:-1]) * 1000), round(float(raw_end[:-1]) * 1000)
        if not (previous_end <= start < end <= duration_ms):
            continue
        cues.append(NarrationCue(offsets[word.start()], offsets[word.end()], start, end, word.group()))
        previous_end = end
    return tuple(cues) if len(cues) / len(source_words) >= 0.9 else ()


async def _gemini_word_alignment(
    text: str, audio: bytes, *, duration_ms: int, client: httpx.AsyncClient | None = None,
) -> tuple[NarrationCue, ...]:
    """A bounded transcription of the actual recording, not text interpolation."""
    api_key = _narration_api_key()
    if not api_key:
        return ()
    timeout = settings.book_narration_subtitle_timeout_seconds
    owns_client = client is None
    if owns_client:
        client = httpx.AsyncClient(timeout=timeout, follow_redirects=False, trust_env=False)
    try:
        async with asyncio.timeout(timeout):
            async with client.stream(
                "POST", "https://generativelanguage.googleapis.com/v1beta/interactions",
                headers={"x-goog-api-key": api_key}, timeout=timeout, follow_redirects=False,
                json={
                    "model": _GEMINI_ALIGNMENT_MODEL, "store": False,
                    "input": [{"type": "audio", "mime_type": "audio/wav",
                               "data": base64.b64encode(audio).decode("ascii")}],
                    "generation_config": {"transcription_config": {"mode": {
                        "type": "verbatim", "timestamp_granularities": ["word"],
                    }}},
                },
            ) as response:
                response.raise_for_status()
                body = bytearray()
                async for chunk in response.aiter_bytes():
                    body.extend(chunk)
                    if len(body) > settings.book_narration_max_subtitle_bytes:
                        raise ValueError("Alignment response too large")
                return _transcription_word_cues(text, json.loads(body), duration_ms=duration_ms)
    except Exception as exc:
        # Audio stays usable. No provider bodies, URLs or credentials in logs.
        logger.warning("Book narration transcription unavailable error_type=%s", type(exc).__name__)
        return ()
    finally:
        if owns_client:
            await client.aclose()


def _narration_api_key() -> str | None:
    """Narration uses only the Google key, independently of the LLM providers."""
    return settings.gemini_api_key


def _narrator_profile(profile: str) -> _NarratorProfile:
    """Resolve only server-approved voices; clients never submit a voice ID."""

    if profile == "expressive_narrator":
        return _NarratorProfile(
            voice_id=settings.book_narration_gemini_voice,
            display_name="Expressive narrator",
        )
    if profile == "seasoned_mentor":
        return _NarratorProfile(
            voice_id=settings.book_narration_gemini_mentor_voice,
            display_name="Seasoned mentor",
        )
    raise ValueError(f"Unsupported narrator profile: {profile}")


async def _synthesize_with_gemini(
    text: str,
    *,
    style: str,
    profile: _NarratorProfile,
    client: httpx.AsyncClient | None = None,
) -> _GeminiSynthesis:
    """Generate one complete native WAV using Google's unary TTS endpoint."""

    api_key = _narration_api_key()
    model = settings.book_narration_gemini_model
    if not api_key or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", model):
        raise BookNarrationUnavailableError(
            "Expressive narration is not configured", reason_code="provider_not_configured"
        )
    # Gemini 3.8 treats text as a verbatim transcript. Directions belong only in
    # speech_metadata, otherwise they can be read aloud with the book passage.
    payload = {
        "contents": [{"role": "user", "parts": [{
            "text": text,
            "speech_metadata": {"style": _GEMINI_STYLES[style]},
        }]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {"voiceConfig": {"voice": profile.voice_id}},
        },
    }
    timeout = httpx.Timeout(
        settings.book_narration_timeout_seconds,
        connect=min(settings.book_narration_timeout_seconds, 10.0),
    )
    owns_client = client is None
    if client is None:
        client = httpx.AsyncClient(timeout=timeout, follow_redirects=False, trust_env=False)
    # Bound the HTTP body as well as decoded audio, including when the provider
    # omits Content-Length or keeps sending data within each read timeout.
    max_body_bytes = 4 * ((settings.book_narration_max_audio_bytes + 2) // 3) + 65_536
    try:
        async with asyncio.timeout(settings.book_narration_timeout_seconds):
            async with client.stream(
                "POST", f"{_GEMINI_API_BASE}/{model}:generateContent",
                headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
                json=payload, timeout=timeout, follow_redirects=False,
            ) as response:
                response.raise_for_status()
                declared_length = response.headers.get("content-length", "")
                if declared_length.isdigit() and int(declared_length) > max_body_bytes:
                    raise BookNarrationUnavailableError(
                        "Narration provider response was too large", reason_code="audio_too_large"
                    )
                body = bytearray()
                async for chunk in response.aiter_bytes():
                    if len(body) + len(chunk) > max_body_bytes:
                        raise BookNarrationUnavailableError(
                            "Narration provider response was too large", reason_code="audio_too_large"
                        )
                    body.extend(chunk)
            try:
                document = json.loads(body)
            except (ValueError, UnicodeDecodeError) as exc:
                raise BookNarrationUnavailableError(
                    "Narration provider returned invalid JSON", reason_code="provider_json_invalid"
                ) from exc
            return _parse_gemini_response(document)
    except httpx.HTTPStatusError as exc:
        status_code = exc.response.status_code
        raise BookNarrationUnavailableError(
            "Narration provider request failed", reason_code="provider_http_error",
            http_status=status_code, retryable=status_code in {408, 425, 429} or status_code >= 500,
        ) from exc
    except (TimeoutError, httpx.TimeoutException) as exc:
        raise BookNarrationUnavailableError(
            "Narration provider request timed out", reason_code="provider_timeout", retryable=True,
        ) from exc
    except httpx.TransportError as exc:
        raise BookNarrationUnavailableError(
            "Narration provider request failed", reason_code="provider_transport_error", retryable=True,
        ) from exc
    except httpx.HTTPError as exc:
        raise BookNarrationUnavailableError(
            "Narration provider request failed", reason_code="provider_http_error"
        ) from exc
    finally:
        if owns_client:
            await client.aclose()


def _parse_gemini_response(payload: Any) -> _GeminiSynthesis:
    if not isinstance(payload, dict):
        raise BookNarrationUnavailableError(
            "Narration provider response was invalid", reason_code="provider_response_invalid"
        )
    feedback = payload.get("promptFeedback")
    if isinstance(feedback, dict) and feedback.get("blockReason"):
        raise BookNarrationUnavailableError(
            "Narration provider rejected the request", reason_code="provider_rejected"
        )
    candidates = payload.get("candidates")
    if not isinstance(candidates, list) or len(candidates) != 1 or not isinstance(candidates[0], dict):
        raise BookNarrationUnavailableError(
            "Narration provider returned no complete audio", reason_code="audio_missing"
        )
    candidate = candidates[0]
    if candidate.get("finishReason") != "STOP":
        # Partial audio (including MAX_TOKENS) must never enter the cache.
        raise BookNarrationUnavailableError(
            "Narration provider did not complete the audio", reason_code="audio_incomplete"
        )
    ratings = candidate.get("safetyRatings")
    if isinstance(ratings, list) and any(
        isinstance(rating, dict) and rating.get("blocked") is True for rating in ratings
    ):
        raise BookNarrationUnavailableError(
            "Narration provider rejected the request", reason_code="provider_rejected"
        )
    content = candidate.get("content")
    parts = content.get("parts") if isinstance(content, dict) else None
    audio_parts = [
        part["inlineData"] for part in parts
        if isinstance(part, dict) and isinstance(part.get("inlineData"), dict)
    ] if isinstance(parts, list) else []
    if len(audio_parts) != 1:
        raise BookNarrationUnavailableError(
            "Narration provider returned invalid audio parts", reason_code="audio_missing"
        )
    inline = audio_parts[0]
    mime_type = inline.get("mimeType")
    if not isinstance(mime_type, str) or mime_type.casefold() not in {"audio/wav", "audio/x-wav"}:
        # Unary Gemini 3.8 returns a complete WAV by default. Raw PCM belongs to
        # a different output contract and must not be guessed or double-wrapped.
        raise BookNarrationUnavailableError(
            "Narration provider returned an unsupported audio format", reason_code="audio_format_invalid"
        )
    encoded = inline.get("data")
    if not isinstance(encoded, str) or not encoded:
        raise BookNarrationUnavailableError(
            "Narration provider returned empty audio", reason_code="audio_empty"
        )
    max_audio_bytes = settings.book_narration_max_audio_bytes
    if len(encoded) > 4 * ((max_audio_bytes + 2) // 3):
        raise BookNarrationUnavailableError(
            "Narration provider audio was too large", reason_code="audio_too_large"
        )
    try:
        audio_bytes = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise BookNarrationUnavailableError(
            "Narration provider returned invalid audio", reason_code="audio_invalid"
        ) from exc
    if len(audio_bytes) > max_audio_bytes:
        raise BookNarrationUnavailableError(
            "Narration provider audio was too large", reason_code="audio_too_large"
        )
    return _GeminiSynthesis(audio_bytes=audio_bytes, duration_ms=_wav_duration_ms(audio_bytes))


def _wav_duration_ms(audio: bytes) -> int:
    """Validate complete mono 24 kHz PCM WAV and measure only its audio frames.

    Gemini may include metadata chunks before or after its data. RIFF chunk
    walking avoids assuming a 44-byte header or counting metadata as speech.
    """
    def invalid() -> BookNarrationUnavailableError:
        return BookNarrationUnavailableError(
            "Narration provider returned invalid WAV audio", reason_code="audio_invalid"
        )

    if (
        len(audio) < 44 or audio[:4] != b"RIFF" or audio[8:12] != b"WAVE"
        or struct.unpack_from("<I", audio, 4)[0] + 8 != len(audio)
    ):
        raise invalid()
    offset = 12
    format_seen = False
    data_size: int | None = None
    while offset < len(audio):
        if offset + 8 > len(audio):
            raise invalid()
        chunk_id = audio[offset:offset + 4]
        chunk_size = struct.unpack_from("<I", audio, offset + 4)[0]
        start = offset + 8
        end = start + chunk_size
        padded_end = end + chunk_size % 2
        if padded_end > len(audio):
            raise invalid()
        if chunk_id == b"fmt ":
            if format_seen or chunk_size < 16:
                raise invalid()
            encoding, channels, rate, byte_rate, frame_bytes, bits = struct.unpack_from("<HHIIHH", audio, start)
            if (encoding, channels, rate, byte_rate, frame_bytes, bits) != (1, 1, 24000, 48000, 2, 16):
                raise invalid()
            format_seen = True
        elif chunk_id == b"data":
            if not format_seen or data_size is not None or chunk_size == 0 or chunk_size % 2:
                raise invalid()
            data_size = chunk_size
        offset = padded_end
    if not format_seen or data_size is None:
        raise invalid()
    duration_ms = round((data_size // 2) * 1000 / 24000)
    if duration_ms <= 0:
        raise invalid()
    return duration_ms


def _utf16_prefix_offsets(text: str) -> list[int]:
    offsets = [0]
    current = 0
    for character in text:
        current += 2 if ord(character) > 0xFFFF else 1
        offsets.append(current)
    return offsets


async def _read_cached_asset(
    *,
    audio_path: Path,
    metadata_path: Path,
    filename: str,
) -> NarrationAsset | None:
    if not audio_path.is_file() or not metadata_path.is_file():
        return None
    try:
        file_size = audio_path.stat().st_size
        if file_size < 128 or file_size > settings.book_narration_max_audio_bytes:
            return None
        raw = await asyncio.to_thread(metadata_path.read_text, encoding="utf-8")
        metadata = json.loads(raw)
        alignment = tuple(
            NarrationCue(**item) for item in metadata.get("alignment", [])
        )
        duration_ms = metadata.get("durationMs")
        if type(duration_ms) is not int or duration_ms <= 0:
            return None
        if metadata.get("provider") != _PROVIDER:
            return None
        audio_bytes = await asyncio.to_thread(audio_path.read_bytes)
        if _wav_duration_ms(audio_bytes) != duration_ms:
            return None
        has_measured_timing = (
            metadata.get("alignmentSource") == "transcription"
            and metadata.get("alignmentGranularity") == "word"
            and bool(alignment)
            and _cached_alignment_is_valid(alignment, duration_ms)
        )
        has_audio_only = (
            metadata.get("alignmentSource") == "none"
            and metadata.get("alignmentGranularity") == "none"
            and not alignment
        )
        # Timing availability affects highlighting, not the paid recording.
        # Replaying usable audio must never silently resynthesize the passage.
        if not has_measured_timing and not has_audio_only:
            return None
        return NarrationAsset(
            audio_url=f"/media/{filename}",
            style=str(metadata["style"]),
            voice=str(metadata["voice"]),
            voice_display_name=str(metadata["voiceDisplayName"]),
            narrator_profile=str(metadata["narratorProfile"]),
            provider=str(metadata["provider"]),
            model=str(metadata["model"]),
            duration_ms=duration_ms,
            alignment=alignment,
            alignment_source=str(metadata["alignmentSource"]),
            alignment_granularity=str(metadata["alignmentGranularity"]),
            offset_encoding=str(metadata["offsetEncoding"]),
            source_text_hash=str(metadata["sourceTextHash"]),
            disclosure=str(metadata["disclosure"]),
            cached=True,
        )
    except (OSError, ValueError, TypeError, KeyError, BookNarrationUnavailableError):
        return None


def _cached_alignment_is_valid(
    alignment: tuple[NarrationCue, ...],
    duration_ms: int,
) -> bool:
    previous_text_end = 0
    previous_time_end = 0
    for cue in alignment:
        if (
            cue.start < previous_text_end
            or cue.end <= cue.start
            or cue.startMs < previous_time_end
            or cue.endMs <= cue.startMs
            or cue.endMs > duration_ms
            or not cue.text
        ):
            return False
        previous_text_end = cue.end
        previous_time_end = cue.endMs
    return True


async def _write_cache_atomically(
    *,
    audio_path: Path,
    metadata_path: Path,
    audio_bytes: bytes,
    metadata: dict[str, Any],
) -> None:
    suffix = uuid4().hex
    audio_temp = audio_path.with_name(f"{audio_path.name}.{suffix}.tmp")
    metadata_temp = metadata_path.with_name(f"{metadata_path.name}.{suffix}.tmp")

    def write() -> None:
        try:
            audio_temp.write_bytes(audio_bytes)
            metadata_temp.write_text(
                json.dumps(metadata, separators=(",", ":")),
                encoding="utf-8",
            )
            os.replace(audio_temp, audio_path)
            os.replace(metadata_temp, metadata_path)
        finally:
            audio_temp.unlink(missing_ok=True)
            metadata_temp.unlink(missing_ok=True)

    await asyncio.to_thread(write)


def _source_text_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _markdown_to_visible_text(markdown: str) -> str:
    # Markdown parsers render an ordered-list item's body without its source
    # marker. Remove only syntactically plausible, line-anchored markers; digits
    # elsewhere remain part of the authorization text.
    text = _markdown_ordered_list_marker.sub("", markdown)
    text = _markdown_image.sub(r"\1", text)
    text = _markdown_link.sub(r"\1", text)
    return html.unescape(re.sub(r"[`*_~>#|]", "", text))


def _compact_for_membership(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return "".join(character for character in normalized if character.isalnum())
