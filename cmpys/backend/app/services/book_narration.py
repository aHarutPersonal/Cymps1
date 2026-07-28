"""Expressive, cached audiobook narration with provider-native timing."""

from __future__ import annotations

import asyncio
import hashlib
import html
import ipaddress
import json
import logging
import math
import os
import re
import socket
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
    ) -> None:
        super().__init__(message)
        self.reason_code = reason_code
        self.retryable = retryable
        self.alignment_diagnostics = alignment_diagnostics


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
    subtitle_url: str


_STYLE_PRESETS: dict[str, _StylePreset] = {
    # MiniMax Speech 2.8 follows punctuation and meaning without an explicit
    # emotion. Avoid forcing one emotion across passages with different moods.
    "expressive": _StylePreset(speed=1.0, pitch=0),
    "warm": _StylePreset(speed=0.96, pitch=0),
    "grounded": _StylePreset(speed=0.93, pitch=-1),
}

_CACHE_VERSION = "minimax-narration-v4"
_PROVIDER = "yunwu"
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

    if (
        not settings.book_narration_enabled
        or settings.book_narration_provider.casefold() != _PROVIDER
        or not settings.yunwu_api_key
    ):
        raise BookNarrationUnavailableError("Expressive narration is not configured")
    preset = _STYLE_PRESETS.get(style)
    if preset is None:
        raise ValueError(f"Unsupported narration style: {style}")
    profile = _narrator_profile(narrator_profile)

    cleaned_text = text.strip()
    source_text_hash = _source_text_hash(cleaned_text)
    digest = hashlib.sha256(
        "\n".join(
            (
                _CACHE_VERSION,
                _PROVIDER,
                settings.book_narration_api_base_url.rstrip("/"),
                settings.book_narration_tts_model,
                narrator_profile,
                profile.voice_id,
                style,
                str(preset.speed),
                str(preset.pitch),
                "provider-subtitle-word-request",
                source_text_hash,
            )
        ).encode("utf-8")
    ).hexdigest()
    filename = f"book_narration_{digest}.mp3"
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
                    _PROVIDER,
                    settings.book_narration_tts_model,
                    len(cleaned_text),
                )
                return cached

            await asyncio.to_thread(media_dir.mkdir, parents=True, exist_ok=True)
            started = asyncio.get_running_loop().time()
            try:
                synthesis = await _synthesize_with_minimax(
                    cleaned_text,
                    preset=preset,
                    profile=profile,
                )
            except BookNarrationUnavailableError:
                raise
            except Exception as exc:
                logger.warning(
                    "Expressive book narration generation failed: %s",
                    type(exc).__name__,
                )
                raise BookNarrationUnavailableError(
                    "Narration generation failed"
                ) from exc
            generation_ms = round((asyncio.get_running_loop().time() - started) * 1000)

            alignment: tuple[NarrationCue, ...] = ()
            alignment_source = "none"
            alignment_granularity = "none"
            subtitle_started = asyncio.get_running_loop().time()
            try:
                subtitle_document = await _fetch_subtitle_with_retry(
                    synthesis.subtitle_url,
                )
                alignment, alignment_granularity = _alignment_from_provider_segments(
                    cleaned_text,
                    subtitle_document,
                    duration_ms=synthesis.duration_ms,
                )
                if alignment:
                    alignment_source = "provider"
            except Exception as exc:
                # Preserve the expressive recording, but never invent exact word
                # timing. The response explicitly reports that timing is absent.
                _log_timing_failure(exc)
            subtitle_ms = round(
                (asyncio.get_running_loop().time() - subtitle_started) * 1000
            )

            metadata = {
                "style": style,
                "voice": profile.voice_id,
                "voiceDisplayName": profile.display_name,
                "narratorProfile": narrator_profile,
                "provider": _PROVIDER,
                "model": settings.book_narration_tts_model,
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
                _PROVIDER,
                settings.book_narration_tts_model,
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
                provider=_PROVIDER,
                model=settings.book_narration_tts_model,
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


def _narrator_profile(profile: str) -> _NarratorProfile:
    """Resolve only server-approved voices; clients never submit a voice ID."""

    if profile == "expressive_narrator":
        return _NarratorProfile(
            voice_id=settings.book_narration_voice_id,
            display_name="Expressive narrator",
        )
    if profile == "seasoned_mentor":
        return _NarratorProfile(
            voice_id=settings.book_narration_mentor_voice_id,
            display_name="Seasoned mentor",
        )
    raise ValueError(f"Unsupported narrator profile: {profile}")


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
) -> _MiniMaxSynthesis:
    """Generate one non-streaming MP3 through Yunwu's native MiniMax route."""

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
                "Authorization": f"Bearer {settings.yunwu_api_key}",
                "Content-Type": "application/json",
            },
            json=_minimax_request_payload(text, preset=preset, profile=profile),
        )
        response.raise_for_status()
        try:
            payload = response.json()
        except (ValueError, json.JSONDecodeError) as exc:
            raise BookNarrationUnavailableError(
                "Narration provider returned invalid JSON"
            ) from exc
        return _parse_minimax_response(payload)
    except httpx.HTTPError as exc:
        raise BookNarrationUnavailableError(
            "Narration provider request failed"
        ) from exc
    finally:
        if owns_client:
            await client.aclose()


def _parse_minimax_response(payload: Any) -> _MiniMaxSynthesis:
    if not isinstance(payload, dict):
        raise BookNarrationUnavailableError("Narration provider response was invalid")
    base_response = payload.get("base_resp")
    if not isinstance(base_response, dict) or base_response.get("status_code") != 0:
        raise BookNarrationUnavailableError("Narration provider rejected the request")
    data = payload.get("data")
    extra_info = payload.get("extra_info")
    if not isinstance(data, dict) or not isinstance(extra_info, dict):
        raise BookNarrationUnavailableError("Narration provider returned no audio")
    if data.get("status") != 2:
        raise BookNarrationUnavailableError(
            "Narration provider did not complete the audio"
        )

    raw_audio = data.get("audio")
    subtitle_url = data.get("subtitle_file")
    duration_ms = extra_info.get("audio_length")
    if not isinstance(raw_audio, str) or len(raw_audio) % 2:
        raise BookNarrationUnavailableError("Narration provider returned invalid audio")
    if len(raw_audio) > settings.book_narration_max_audio_bytes * 2:
        raise BookNarrationUnavailableError("Narration provider audio was too large")
    try:
        audio_bytes = bytes.fromhex(raw_audio)
    except ValueError as exc:
        raise BookNarrationUnavailableError(
            "Narration provider returned invalid audio"
        ) from exc
    if len(audio_bytes) < 128:
        raise BookNarrationUnavailableError("Narration provider returned empty audio")
    if not isinstance(duration_ms, (int, float)) or isinstance(duration_ms, bool):
        raise BookNarrationUnavailableError("Narration provider returned no duration")
    duration_ms = round(float(duration_ms))
    if duration_ms <= 0:
        raise BookNarrationUnavailableError("Narration provider returned no duration")
    if not isinstance(subtitle_url, str) or not subtitle_url:
        raise BookNarrationUnavailableError("Narration provider returned no timing")
    return _MiniMaxSynthesis(
        audio_bytes=audio_bytes,
        duration_ms=duration_ms,
        subtitle_url=subtitle_url,
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
        if audio_path.stat().st_size < 128:
            return None
        raw = await asyncio.to_thread(metadata_path.read_text, encoding="utf-8")
        metadata = json.loads(raw)
        alignment = tuple(
            NarrationCue(**item) for item in metadata.get("alignment", [])
        )
        duration_ms = metadata.get("durationMs")
        if not isinstance(duration_ms, int) or duration_ms <= 0:
            return None
        if (
            metadata.get("alignmentSource") != "provider"
            or metadata.get("alignmentGranularity") not in {"word", "phrase"}
            or not alignment
        ):
            # Audio is still served to the request that generated it, but an
            # incomplete timing result must not become a permanent cache hit.
            return None
        if not _cached_alignment_is_valid(alignment, duration_ms):
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
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
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
