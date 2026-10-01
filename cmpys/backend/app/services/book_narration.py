"""Expressive, cached audiobook narration with provider-native timing."""

from __future__ import annotations

import asyncio
import base64
import binascii
import hashlib
import html
import ipaddress
import json
import logging
import math
import os
import re
import socket
import struct
import unicodedata
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit
from uuid import uuid4

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

_MAX_ALIGNMENT_DIAGNOSTIC_VALUE = 4096
_MAX_ALIGNMENT_DIAGNOSTIC_SCAN = 8192
_ALIGNMENT_VALIDATION_CATEGORIES = frozenset(
    {
        "provider_offset_length",
        "provider_offset_non_contiguous",
        "provider_offset_order",
        "provider_offset_type",
        "segment_document_empty",
        "segment_text_invalid",
        "source_gap_non_whitespace",
        "source_segment_not_found",
        "source_trailing_non_whitespace",
        "time_non_monotonic",
        "time_order",
        "time_out_of_bounds",
        "time_rounding_invalid",
        "time_type",
    }
)


@dataclass(frozen=True)
class _SafeAlignmentDiagnostics:
    segment_index: int
    segment_count: int
    source_length: int
    provider_length: int
    validation_category: str
    first_mismatch_offset: int
    source_unicode_class: str
    provider_unicode_class: str
    nfc_equivalent: bool
    whitespace_collapse_equivalent: bool
    punctuation_normalization_equivalent: bool
    values_truncated: bool


class BookNarrationUnavailableError(RuntimeError):
    """The configured expressive narration provider could not be used."""

    def __init__(
        self,
        message: str,
        *,
        reason_code: str = "narration_unavailable",
        retryable: bool = False,
        alignment_diagnostics: _SafeAlignmentDiagnostics | None = None,
        http_status: int | None = None,
        provider_status: int | None = None,
    ) -> None:
        super().__init__(message)
        self.reason_code = (
            reason_code if isinstance(reason_code, str) and re.fullmatch(r"[a-z0-9_]{1,64}", reason_code)
            else "narration_unavailable"
        )
        self.retryable = retryable
        self.alignment_diagnostics = alignment_diagnostics
        self.http_status = (
            http_status if type(http_status) is int and 100 <= http_status <= 599
            else None
        )
        self.provider_status = (
            provider_status if type(provider_status) is int and abs(provider_status) <= 2**31
            else None
        )


@dataclass(frozen=True)
class NarrationCue:
    """One provider-timed source range using UTF-16 offsets for Flutter."""

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


@dataclass(frozen=True)
class _StylePreset:
    speed: float
    pitch: int


@dataclass(frozen=True)
class _NarratorProfile:
    voice_id: str
    display_name: str


@dataclass(frozen=True)
class _MiniMaxSynthesis:
    audio_bytes: bytes
    duration_ms: int
    subtitle_url: str | None


@dataclass(frozen=True)
class _GeminiSynthesis:
    audio_bytes: bytes
    duration_ms: int


_STYLE_PRESETS: dict[str, _StylePreset] = {
    # MiniMax Speech 2.8 follows punctuation and meaning without an explicit
    # emotion. Avoid forcing one emotion across passages with different moods.
    "expressive": _StylePreset(speed=1.0, pitch=0),
    "warm": _StylePreset(speed=0.96, pitch=0),
    "grounded": _StylePreset(speed=0.93, pitch=-1),
}

_CACHE_VERSION = "minimax-narration-v4"
_GEMINI_CACHE_VERSION = "gemini-narration-v1"
_GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
_GEMINI_STYLES = {
    "expressive": "Warm, expressive audiobook narration with natural emphasis and clear, unhurried pacing.",
    "warm": "Warm, gentle audiobook narration with a relaxed pace and natural pauses.",
    "grounded": "Calm, grounded audiobook narration with measured pacing and clear emphasis.",
}
_SUPPORTED_PROVIDERS = frozenset({"yunwu", "openlux", "gemini"})
_OFFSET_ENCODING = "utf16"
_DISCLOSURE = "AI-generated voice; not the real person."
_locks: dict[str, asyncio.Lock] = {}
_markdown_image = re.compile(r"!\[([^]]*)\]\([^)]*\)")
_markdown_link = re.compile(r"\[([^]]+)\]\([^)]*\)")
_markdown_ordered_list_marker = re.compile(
    r"(?m)^[ \t]{0,3}(?:>[ \t]{0,3})*\d{1,9}[.)][ \t]+"
)
_source_word = re.compile(r"\w+(?:[\u2019'\-]\w+)*", re.UNICODE)
_subtitle_content_types = frozenset(
    {
        "application/json",
        "text/json",
        "text/plain",
        "application/octet-stream",
        "binary/octet-stream",
    }
)
_punctuation_diagnostic_translation = str.maketrans(
    {
        "\u2018": "'",
        "\u2019": "'",
        "\u201b": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u201f": '"',
        "\u2010": "-",
        "\u2011": "-",
        "\u2012": "-",
        "\u2013": "-",
        "\u2014": "-",
        "\u2212": "-",
        "\u2026": "...",
    }
)


def _log_timing_failure(exc: Exception) -> None:
    diagnostics = getattr(exc, "alignment_diagnostics", None)
    if not isinstance(diagnostics, _SafeAlignmentDiagnostics):
        logger.warning(
            "Book narration provider timing unavailable reason=%s error_type=%s",
            getattr(exc, "reason_code", "timing_unexpected"),
            type(exc).__name__,
        )
        return
    logger.warning(
        "Book narration provider timing unavailable "
        "reason=%s error_type=%s "
        "alignment_segment_index=%d alignment_segment_count=%d "
        "alignment_source_length=%d alignment_provider_length=%d "
        "alignment_validation=%s alignment_first_mismatch_offset=%d "
        "alignment_source_unicode_class=%s "
        "alignment_provider_unicode_class=%s "
        "alignment_nfc_equivalent=%s "
        "alignment_whitespace_collapse_equivalent=%s "
        "alignment_punctuation_normalization_equivalent=%s "
        "alignment_values_truncated=%s",
        getattr(exc, "reason_code", "timing_unexpected"),
        type(exc).__name__,
        diagnostics.segment_index,
        diagnostics.segment_count,
        diagnostics.source_length,
        diagnostics.provider_length,
        diagnostics.validation_category,
        diagnostics.first_mismatch_offset,
        diagnostics.source_unicode_class,
        diagnostics.provider_unicode_class,
        diagnostics.nfc_equivalent,
        diagnostics.whitespace_collapse_equivalent,
        diagnostics.punctuation_normalization_equivalent,
        diagnostics.values_truncated,
    )


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
    if (
        not settings.book_narration_enabled
        or provider not in _SUPPORTED_PROVIDERS
    ):
        raise BookNarrationUnavailableError(
            "Expressive narration is not configured", reason_code="provider_not_configured"
        )
    preset = _STYLE_PRESETS.get(style)
    if preset is None:
        raise ValueError(f"Unsupported narration style: {style}")
    profile = _narrator_profile(narrator_profile, provider=provider)

    cleaned_text = text.strip()
    source_text_hash = _source_text_hash(cleaned_text)
    model = (
        settings.book_narration_gemini_model if provider == "gemini"
        else settings.book_narration_tts_model
    )
    if provider == "gemini":
        identity = (
            _GEMINI_CACHE_VERSION, provider, _GEMINI_API_BASE, model,
            narrator_profile, profile.voice_id, style, _GEMINI_STYLES[style],
            "native-wav-no-alignment", source_text_hash,
        )
        extension = "wav"
    else:
        # Preserve existing MiniMax fingerprints so paid recordings remain usable.
        identity = (
            _CACHE_VERSION, provider,
            settings.book_narration_api_base_url.rstrip("/"), model,
            narrator_profile, profile.voice_id, style,
            str(preset.speed), str(preset.pitch),
            "provider-subtitle-word-request", source_text_hash,
        )
        extension = "mp3"
    digest = hashlib.sha256(
        "\n".join(identity).encode("utf-8")
    ).hexdigest()
    filename = f"book_narration_{digest}.{extension}"
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
                logger.info(
                    "Book narration cache hit provider=%s model=%s chars=%d",
                    provider,
                    model,
                    len(cleaned_text),
                )
                return cached

            # Cached audio does not depend on the provider being reachable or
            # its credential remaining configured after the recording exists.
            if not _narration_api_key(provider):
                raise BookNarrationUnavailableError(
                    "Expressive narration is not configured", reason_code="provider_not_configured"
                )
            await asyncio.to_thread(media_dir.mkdir, parents=True, exist_ok=True)
            started = asyncio.get_running_loop().time()
            try:
                if provider == "gemini":
                    synthesis = await _synthesize_with_gemini(
                        cleaned_text, style=style, profile=profile,
                    )
                else:
                    synthesis = await _synthesize_with_minimax(
                        cleaned_text, preset=preset, profile=profile, provider=provider,
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

            alignment: tuple[NarrationCue, ...] = ()
            alignment_source = "none"
            alignment_granularity = "none"
            subtitle_started = asyncio.get_running_loop().time()
            # Gemini unary TTS supplies audio only. Do not invent alignment or
            # treat an intentionally absent subtitle as a transient error.
            if isinstance(synthesis, _MiniMaxSynthesis):
                try:
                    if not synthesis.subtitle_url:
                        raise BookNarrationUnavailableError(
                            "Narration provider returned no timing", reason_code="subtitle_missing"
                        )
                    subtitle_document = await _fetch_subtitle_with_retry(
                        synthesis.subtitle_url,
                    )
                    alignment, alignment_granularity = _alignment_from_provider_segments(
                        cleaned_text, subtitle_document, duration_ms=synthesis.duration_ms,
                    )
                    if alignment:
                        alignment_source = "provider"
                except Exception as exc:
                    # Preserve the recording without inventing exact word timing.
                    _log_timing_failure(exc)
            subtitle_ms = round(
                (asyncio.get_running_loop().time() - subtitle_started) * 1000
            )

            metadata = {
                "style": style,
                "voice": profile.voice_id,
                "voiceDisplayName": profile.display_name,
                "narratorProfile": narrator_profile,
                "provider": provider,
                "model": model,
                "durationMs": synthesis.duration_ms,
                "alignment": [asdict(cue) for cue in alignment],
                "alignmentSource": alignment_source,
                "alignmentGranularity": alignment_granularity,
                "offsetEncoding": _OFFSET_ENCODING,
                "sourceTextHash": source_text_hash,
                "disclosure": _DISCLOSURE,
            }
            await _write_cache_atomically(
                audio_path=audio_path,
                metadata_path=metadata_path,
                audio_bytes=synthesis.audio_bytes,
                metadata=metadata,
            )
            logger.info(
                "Book narration generated provider=%s model=%s chars=%d "
                "duration_ms=%d generation_ms=%d subtitle_ms=%d granularity=%s",
                provider,
                model,
                len(cleaned_text),
                synthesis.duration_ms,
                generation_ms,
                subtitle_ms,
                alignment_granularity,
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
                alignment=alignment,
                alignment_source=alignment_source,
                alignment_granularity=alignment_granularity,
                offset_encoding=_OFFSET_ENCODING,
                source_text_hash=source_text_hash,
                disclosure=_DISCLOSURE,
                cached=False,
            )
    finally:
        # Avoid retaining one asyncio.Lock for every passage ever requested.
        if _locks.get(digest) is lock and not lock.locked():
            _locks.pop(digest, None)


def _narration_api_key(provider: str) -> str | None:
    """Narration credentials follow its explicit provider, independently of LLMs."""
    if provider == "yunwu":
        return settings.yunwu_api_key
    if provider == "openlux":
        return settings.openlux_api_key
    if provider == "gemini":
        return settings.gemini_api_key
    return None


def _narrator_profile(profile: str, *, provider: str | None = None) -> _NarratorProfile:
    """Resolve only server-approved voices; clients never submit a voice ID."""

    provider = provider or settings.book_narration_provider.casefold()
    if profile == "expressive_narrator":
        return _NarratorProfile(
            voice_id=(settings.book_narration_gemini_voice if provider == "gemini"
                      else settings.book_narration_voice_id),
            display_name="Expressive narrator",
        )
    if profile == "seasoned_mentor":
        return _NarratorProfile(
            voice_id=(settings.book_narration_gemini_mentor_voice if provider == "gemini"
                      else settings.book_narration_mentor_voice_id),
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

    api_key = _narration_api_key("gemini")
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


def _minimax_request_payload(
    text: str,
    *,
    preset: _StylePreset,
    profile: _NarratorProfile,
) -> dict[str, Any]:
    return {
        "model": settings.book_narration_tts_model,
        "text": text,
        "stream": False,
        "language_boost": "auto",
        "output_format": "hex",
        "subtitle_enable": True,
        # Yunwu currently returns provider segments even when word timing is
        # requested. We preserve that actual granularity in the API response.
        "subtitle_type": "word",
        "voice_setting": {
            "voice_id": profile.voice_id,
            "speed": preset.speed,
            "vol": 1.0,
            "pitch": preset.pitch,
        },
        "audio_setting": {
            "sample_rate": 32000,
            "bitrate": 128000,
            "format": "mp3",
            "channel": 1,
        },
    }


async def _synthesize_with_minimax(
    text: str,
    *,
    preset: _StylePreset,
    profile: _NarratorProfile,
    client: httpx.AsyncClient | None = None,
    provider: str | None = None,
) -> _MiniMaxSynthesis:
    """Generate one MP3 through the explicitly selected native MiniMax gateway."""

    provider = provider or settings.book_narration_provider.casefold()
    api_key = _narration_api_key(provider)
    if not api_key:
        raise BookNarrationUnavailableError(
            "Expressive narration is not configured", reason_code="provider_not_configured"
        )
    endpoint = f"{settings.book_narration_api_base_url.rstrip('/')}/t2a_v2"
    timeout = httpx.Timeout(
        settings.book_narration_timeout_seconds,
        connect=min(settings.book_narration_timeout_seconds, 10.0),
    )
    owns_client = client is None
    if client is None:
        client = httpx.AsyncClient(
            timeout=timeout,
            follow_redirects=False,
            trust_env=False,
        )
    try:
        response = await client.post(
            endpoint,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json=_minimax_request_payload(text, preset=preset, profile=profile),
        )
        response.raise_for_status()
        try:
            payload = response.json()
        except (ValueError, json.JSONDecodeError) as exc:
            raise BookNarrationUnavailableError(
                "Narration provider returned invalid JSON", reason_code="provider_json_invalid"
            ) from exc
        return _parse_minimax_response(payload)
    except httpx.HTTPStatusError as exc:
        status_code = exc.response.status_code
        raise BookNarrationUnavailableError(
            "Narration provider request failed", reason_code="provider_http_error",
            http_status=status_code, retryable=status_code in {408, 425, 429} or status_code >= 500,
        ) from exc
    except httpx.TimeoutException as exc:
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


def _parse_minimax_response(payload: Any) -> _MiniMaxSynthesis:
    if not isinstance(payload, dict):
        raise BookNarrationUnavailableError(
            "Narration provider response was invalid", reason_code="provider_response_invalid"
        )
    base_response = payload.get("base_resp")
    provider_status = base_response.get("status_code") if isinstance(base_response, dict) else None
    if type(provider_status) is not int or provider_status != 0:
        raise BookNarrationUnavailableError(
            "Narration provider rejected the request", reason_code="provider_rejected",
            provider_status=provider_status,
        )
    data = payload.get("data")
    extra_info = payload.get("extra_info")
    if not isinstance(data, dict) or not isinstance(extra_info, dict):
        raise BookNarrationUnavailableError("Narration provider returned no audio", reason_code="audio_missing")
    if data.get("status") != 2:
        raise BookNarrationUnavailableError(
            "Narration provider did not complete the audio", reason_code="audio_incomplete"
        )

    raw_audio = data.get("audio")
    subtitle_url = data.get("subtitle_file")
    duration_ms = extra_info.get("audio_length")
    if not isinstance(raw_audio, str) or len(raw_audio) % 2:
        raise BookNarrationUnavailableError("Narration provider returned invalid audio", reason_code="audio_invalid")
    if len(raw_audio) > settings.book_narration_max_audio_bytes * 2:
        raise BookNarrationUnavailableError("Narration provider audio was too large", reason_code="audio_too_large")
    try:
        audio_bytes = bytes.fromhex(raw_audio)
    except ValueError as exc:
        raise BookNarrationUnavailableError(
            "Narration provider returned invalid audio", reason_code="audio_invalid"
        ) from exc
    if len(audio_bytes) < 128:
        raise BookNarrationUnavailableError("Narration provider returned empty audio", reason_code="audio_empty")
    duration = _strict_number(duration_ms)
    if duration is None:
        raise BookNarrationUnavailableError("Narration provider returned no duration", reason_code="duration_invalid")
    duration_ms = round(duration)
    if duration_ms <= 0:
        raise BookNarrationUnavailableError("Narration provider returned no duration", reason_code="duration_invalid")
    return _MiniMaxSynthesis(
        audio_bytes=audio_bytes,
        duration_ms=duration_ms,
        subtitle_url=subtitle_url if isinstance(subtitle_url, str) and subtitle_url else None,
    )


async def _fetch_subtitle_document(
    url: str,
    *,
    client: httpx.AsyncClient | None = None,
) -> list[dict[str, Any]]:
    """Download a bounded subtitle JSON file from an approved public host."""

    await _assert_safe_subtitle_url(url)
    timeout = httpx.Timeout(
        settings.book_narration_subtitle_timeout_seconds,
        connect=min(settings.book_narration_subtitle_timeout_seconds, 5.0),
    )
    owns_client = client is None
    if client is None:
        client = httpx.AsyncClient(
            timeout=timeout,
            follow_redirects=False,
            trust_env=False,
        )
    try:
        async with client.stream("GET", url) as response:
            response.raise_for_status()
            if response.is_redirect:
                raise BookNarrationUnavailableError(
                    "Narration timing redirect was rejected",
                    reason_code="subtitle_redirect_rejected",
                )
            content_type = response.headers.get("content-type", "")
            media_type = content_type.partition(";")[0].strip().lower()
            if media_type not in _subtitle_content_types:
                raise BookNarrationUnavailableError(
                    "Narration timing content type was rejected",
                    reason_code="subtitle_content_type_rejected",
                )
            content_length = response.headers.get("content-length")
            if content_length:
                try:
                    declared_size = int(content_length)
                except ValueError as exc:
                    raise BookNarrationUnavailableError(
                        "Narration timing size was invalid",
                        reason_code="subtitle_size_invalid",
                    ) from exc
                if declared_size > settings.book_narration_max_subtitle_bytes:
                    raise BookNarrationUnavailableError(
                        "Narration timing file was too large",
                        reason_code="subtitle_too_large",
                    )

            body = bytearray()
            async for chunk in response.aiter_bytes():
                body.extend(chunk)
                if len(body) > settings.book_narration_max_subtitle_bytes:
                    raise BookNarrationUnavailableError(
                        "Narration timing file was too large",
                        reason_code="subtitle_too_large",
                    )
    except httpx.HTTPStatusError as exc:
        status_code = exc.response.status_code
        transient = status_code in {408, 425, 429} or status_code >= 500
        raise BookNarrationUnavailableError(
            "Narration timing request failed",
            reason_code=(
                "subtitle_http_transient" if transient else "subtitle_http_rejected"
            ),
            retryable=transient,
        ) from exc
    except httpx.TransportError as exc:
        raise BookNarrationUnavailableError(
            "Narration timing request failed",
            reason_code="subtitle_transport_error",
            retryable=True,
        ) from exc
    except httpx.HTTPError as exc:
        raise BookNarrationUnavailableError(
            "Narration timing request failed",
            reason_code="subtitle_http_error",
        ) from exc
    finally:
        if owns_client:
            await client.aclose()

    try:
        document = json.loads(bytes(body).decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BookNarrationUnavailableError(
            "Narration timing file was invalid",
            reason_code="subtitle_document_invalid",
        ) from exc
    if not isinstance(document, list) or not all(
        isinstance(item, dict) for item in document
    ):
        raise BookNarrationUnavailableError(
            "Narration timing file was invalid",
            reason_code="subtitle_document_invalid",
        )
    return document


async def _fetch_subtitle_with_retry(url: str) -> list[dict[str, Any]]:
    """Retry one transient subtitle transport/DNS failure, and nothing else."""

    try:
        return await _fetch_subtitle_document(url)
    except BookNarrationUnavailableError as exc:
        if not exc.retryable:
            raise
        logger.info("Retrying narration timing reason=%s", exc.reason_code)
        await asyncio.sleep(0.2)
        return await _fetch_subtitle_document(url)


async def _assert_safe_subtitle_url(url: str) -> None:
    parsed = urlsplit(url)
    try:
        port = parsed.port
    except ValueError as exc:
        raise BookNarrationUnavailableError(
            "Narration timing URL was rejected",
            reason_code="subtitle_url_rejected",
        ) from exc
    if (
        parsed.scheme.lower() != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or port not in (None, 443)
    ):
        raise BookNarrationUnavailableError(
            "Narration timing URL was rejected",
            reason_code="subtitle_url_rejected",
        )

    hostname = parsed.hostname.rstrip(".").lower()
    allowed_hosts = {
        item.strip().rstrip(".").lower()
        for item in settings.book_narration_subtitle_allowed_hosts.split(",")
        if item.strip()
    }
    if hostname not in allowed_hosts:
        raise BookNarrationUnavailableError(
            "Narration timing host was rejected",
            reason_code="subtitle_host_rejected",
        )

    try:
        addresses = await asyncio.to_thread(
            socket.getaddrinfo,
            hostname,
            443,
            0,
            socket.SOCK_STREAM,
        )
    except OSError as exc:
        raise BookNarrationUnavailableError(
            "Narration timing host could not be resolved",
            reason_code="subtitle_dns_error",
            retryable=True,
        ) from exc
    if not addresses:
        raise BookNarrationUnavailableError(
            "Narration timing host could not be resolved",
            reason_code="subtitle_dns_error",
            retryable=True,
        )
    for address in addresses:
        raw_ip = address[4][0].split("%", 1)[0]
        try:
            resolved = ipaddress.ip_address(raw_ip)
        except ValueError as exc:
            raise BookNarrationUnavailableError(
                "Narration timing host resolved unexpectedly",
                reason_code="subtitle_dns_invalid",
            ) from exc
        if not resolved.is_global:
            raise BookNarrationUnavailableError(
                "Narration timing host resolved to a non-public address",
                reason_code="subtitle_host_non_public",
            )


def _alignment_from_provider_segments(
    text: str,
    document: list[dict[str, Any]],
    *,
    duration_ms: int,
) -> tuple[tuple[NarrationCue, ...], str]:
    """Map MiniMax segments back to exact source ranges and Flutter UTF-16.

    MiniMax trims whitespace at subtitle segment boundaries and reports
    ``text_begin``/``text_end`` against the concatenated segment text, not the
    original input. Map each exact segment sequentially into the source while
    allowing only omitted whitespace. Any omitted non-whitespace would make
    the timing ambiguous and is rejected rather than guessed.
    """

    if not document:
        raise _alignment_failure(text, document, "segment_document_empty", -1)
    utf16_offsets = _utf16_prefix_offsets(text)
    cues: list[NarrationCue] = []
    codepoint_ranges: list[tuple[int, int]] = []
    source_cursor = 0
    previous_provider_text_end = 0
    previous_time_end = 0.0
    previous_end_ms = 0

    for segment_index, item in enumerate(document):
        provider_start = _strict_int(item.get("text_begin"))
        provider_end = _strict_int(item.get("text_end"))
        start_time = _strict_number(item.get("time_begin"))
        end_time = _strict_number(item.get("time_end"))
        segment_text = item.get("text")
        if not isinstance(segment_text, str) or not segment_text:
            raise _alignment_failure(
                text, document, "segment_text_invalid", segment_index
            )
        if provider_start is None or provider_end is None:
            raise _alignment_failure(
                text, document, "provider_offset_type", segment_index
            )
        if provider_start != previous_provider_text_end:
            raise _alignment_failure(
                text, document, "provider_offset_non_contiguous", segment_index
            )
        if provider_end <= provider_start:
            raise _alignment_failure(
                text, document, "provider_offset_order", segment_index
            )
        if provider_end - provider_start != len(segment_text):
            raise _alignment_failure(
                text, document, "provider_offset_length", segment_index
            )
        if start_time is None or end_time is None:
            raise _alignment_failure(text, document, "time_type", segment_index)
        if start_time < previous_time_end:
            raise _alignment_failure(
                text, document, "time_non_monotonic", segment_index
            )
        if start_time < 0 or end_time <= start_time:
            raise _alignment_failure(text, document, "time_order", segment_index)
        if end_time > duration_ms + 1000:
            raise _alignment_failure(
                text, document, "time_out_of_bounds", segment_index
            )

        source_start = text.find(segment_text, source_cursor)
        if source_start < 0:
            raise _alignment_failure(
                text, document, "source_segment_not_found", segment_index
            )
        if not _is_whitespace_only(text[source_cursor:source_start]):
            raise _alignment_failure(
                text,
                document,
                "source_gap_non_whitespace",
                segment_index,
            )
        source_end = source_start + len(segment_text)

        start_ms = max(round(start_time), previous_end_ms)
        end_ms = min(round(end_time), duration_ms)
        if end_ms <= start_ms:
            raise _alignment_failure(
                text, document, "time_rounding_invalid", segment_index
            )
        cues.append(
            NarrationCue(
                start=utf16_offsets[source_start],
                end=utf16_offsets[source_end],
                startMs=start_ms,
                endMs=end_ms,
                text=segment_text,
            )
        )
        codepoint_ranges.append((source_start, source_end))
        source_cursor = source_end
        previous_provider_text_end = provider_end
        previous_time_end = end_time
        previous_end_ms = end_ms

    if not _is_whitespace_only(text[source_cursor:]):
        raise _alignment_failure(
            text,
            document,
            "source_trailing_non_whitespace",
            len(document) - 1,
        )

    source_words = list(_source_word.finditer(text))
    is_word_granularity = len(source_words) == len(codepoint_ranges) and all(
        len(list(_source_word.finditer(text[start:end]))) == 1
        for start, end in codepoint_ranges
    )
    return tuple(cues), "word" if is_word_granularity else "phrase"


def _alignment_failure(
    text: str,
    document: list[dict[str, Any]],
    validation_category: str,
    segment_index: int,
) -> BookNarrationUnavailableError:
    return BookNarrationUnavailableError(
        "Narration provider timing was inconsistent",
        reason_code="subtitle_alignment_inconsistent",
        alignment_diagnostics=_safe_alignment_diagnostics(
            text,
            document,
            validation_category=validation_category,
            segment_index=segment_index,
        ),
    )


def _safe_alignment_diagnostics(
    text: str,
    document: list[dict[str, Any]],
    *,
    validation_category: str,
    segment_index: int,
) -> _SafeAlignmentDiagnostics:
    provider_parts: list[str] = []
    provider_length = 0
    provider_sample_length = 0
    provider_text_valid = True
    for item in document:
        value = item.get("text")
        if not isinstance(value, str):
            provider_text_valid = False
            continue
        provider_length += len(value)
        if provider_sample_length < _MAX_ALIGNMENT_DIAGNOSTIC_SCAN:
            remaining = _MAX_ALIGNMENT_DIAGNOSTIC_SCAN - provider_sample_length
            sample = value[:remaining]
            provider_parts.append(sample)
            provider_sample_length += len(sample)

    provider_sample = "".join(provider_parts)
    source_sample = text[:_MAX_ALIGNMENT_DIAGNOSTIC_SCAN]
    values_truncated = (
        len(text) > _MAX_ALIGNMENT_DIAGNOSTIC_SCAN
        or provider_length > _MAX_ALIGNMENT_DIAGNOSTIC_SCAN
        or not provider_text_valid
    )
    first_mismatch = _first_mismatch_offset(source_sample, provider_sample)
    source_class = _unicode_class_at(source_sample, first_mismatch)
    provider_class = _unicode_class_at(provider_sample, first_mismatch)
    comparisons_complete = not values_truncated

    return _SafeAlignmentDiagnostics(
        segment_index=_bounded_alignment_value(segment_index),
        segment_count=_bounded_alignment_value(len(document)),
        source_length=_bounded_alignment_value(len(text)),
        provider_length=_bounded_alignment_value(provider_length),
        validation_category=(
            validation_category
            if validation_category in _ALIGNMENT_VALIDATION_CATEGORIES
            else "unknown"
        ),
        first_mismatch_offset=_bounded_alignment_value(first_mismatch),
        source_unicode_class=source_class,
        provider_unicode_class=provider_class,
        nfc_equivalent=(
            comparisons_complete
            and unicodedata.normalize("NFC", source_sample)
            == unicodedata.normalize("NFC", provider_sample)
        ),
        whitespace_collapse_equivalent=(
            comparisons_complete
            and "".join(source_sample.split()) == "".join(provider_sample.split())
        ),
        punctuation_normalization_equivalent=(
            comparisons_complete
            and source_sample.translate(_punctuation_diagnostic_translation)
            == provider_sample.translate(_punctuation_diagnostic_translation)
        ),
        values_truncated=values_truncated,
    )


def _first_mismatch_offset(source: str, provider: str) -> int:
    shared_length = min(len(source), len(provider))
    for index in range(shared_length):
        if source[index] != provider[index]:
            return index
    return -1 if len(source) == len(provider) else shared_length


def _unicode_class_at(value: str, offset: int) -> str:
    if offset < 0 or offset >= len(value):
        return "none"
    return unicodedata.category(value[offset])


def _bounded_alignment_value(value: int) -> int:
    return max(-1, min(value, _MAX_ALIGNMENT_DIAGNOSTIC_VALUE))


def _is_whitespace_only(value: str) -> bool:
    return not value or value.isspace()


def _utf16_prefix_offsets(text: str) -> list[int]:
    offsets = [0]
    current = 0
    for character in text:
        current += 2 if ord(character) > 0xFFFF else 1
        offsets.append(current)
    return offsets


def _strict_int(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def _strict_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    result = float(value)
    return result if math.isfinite(result) else None


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
        if audio_path.suffix == ".wav":
            if metadata.get("provider") != "gemini":
                return None
            audio_bytes = await asyncio.to_thread(audio_path.read_bytes)
            if _wav_duration_ms(audio_bytes) != duration_ms:
                return None
        has_provider_timing = (
            metadata.get("alignmentSource") == "provider"
            and metadata.get("alignmentGranularity") in {"word", "phrase"}
            and bool(alignment)
            and _cached_alignment_is_valid(alignment, duration_ms)
        )
        has_audio_only = (
            metadata.get("alignmentSource") == "none"
            and metadata.get("alignmentGranularity") == "none"
            and not alignment
        )
        # Subtitle availability affects highlighting, not the paid recording.
        # Replaying usable audio must never silently resynthesize the passage.
        if not has_provider_timing and not has_audio_only:
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
