"""Expressive, cached audiobook narration with word-level alignment."""

from __future__ import annotations

import asyncio
import hashlib
import html
import json
import logging
import os
import re
import unicodedata
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable
from uuid import uuid4

from openai import AsyncOpenAI

from app.core.config import settings

logger = logging.getLogger(__name__)


class BookNarrationUnavailableError(RuntimeError):
    """The configured expressive narration provider could not be used."""


@dataclass(frozen=True)
class NarrationCue:
    start: int
    end: int
    startMs: int
    endMs: int


@dataclass(frozen=True)
class NarrationAsset:
    audio_url: str
    style: str
    voice: str
    duration_ms: int | None
    alignment: tuple[NarrationCue, ...]
    cached: bool


@dataclass(frozen=True)
class _StylePreset:
    voice: str
    instructions: str


_STYLE_PRESETS: dict[str, _StylePreset] = {
    "expressive": _StylePreset(
        voice="marin",
        instructions=(
            "Read the supplied text exactly as written, without adding, omitting, "
            "or paraphrasing any words. Perform it like an emotionally intelligent "
            "human audiobook narrator: use natural rises and falls, meaningful "
            "emphasis, varied but unhurried pacing, and restrained authentic emotion "
            "that follows the meaning. Let questions lift naturally and important "
            "ideas land with warmth. Respect every punctuation pause. Never sound "
            "theatrical, promotional, or like a voice assistant."
        ),
    ),
    "warm": _StylePreset(
        voice="marin",
        instructions=(
            "Read the supplied text exactly as written, without adding, omitting, "
            "or paraphrasing any words. Sound like a warm, attentive human reading "
            "to one person: intimate, encouraging, softly expressive, and naturally "
            "paced. Use subtle emphasis and comfortable pauses while avoiding a "
            "sales tone or exaggerated performance."
        ),
    ),
    "grounded": _StylePreset(
        voice="cedar",
        instructions=(
            "Read the supplied text exactly as written, without adding, omitting, "
            "or paraphrasing any words. Use a grounded, thoughtful audiobook style "
            "with a calm human presence, clear phrasing, gentle emotional variation, "
            "and deliberate pauses at punctuation. Keep it natural rather than flat, "
            "dramatic, or instructional."
        ),
    ),
}

_CACHE_VERSION = "expressive-narration-v1"
_locks: dict[str, asyncio.Lock] = {}
_markdown_image = re.compile(r"!\[([^]]*)\]\([^)]*\)")
_markdown_link = re.compile(r"\[([^]]+)\]\([^)]*\)")
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


def align_transcribed_words(
    text: str,
    words: Iterable[Any],
    duration_seconds: float | None,
) -> tuple[NarrationCue, ...]:
    """Map provider word timestamps back to exact source character ranges.

    Whisper can occasionally omit a tiny word or normalize a contraction. Any
    unmatched source words are interpolated between their timed neighbors so
    the reader never stops highlighting midway through a sentence.
    """

    source_tokens = [
        (match.start(), match.end(), _normalize_word(match.group(0)))
        for match in _source_word.finditer(text)
    ]
    if not source_tokens:
        return ()

    timed: list[tuple[float, float] | None] = [None] * len(source_tokens)
    cursor = 0
    last_end = 0.0
    for raw_word in words:
        spoken = _word_field(raw_word, "word", "")
        normalized = _normalize_word(str(spoken))
        if not normalized:
            continue
        match_index: int | None = None
        for index in range(cursor, min(cursor + 8, len(source_tokens))):
            candidate = source_tokens[index][2]
            if (
                candidate == normalized
                or candidate.startswith(normalized)
                or normalized.startswith(candidate)
            ):
                match_index = index
                break
        if match_index is None:
            continue
        start = max(float(_word_field(raw_word, "start", last_end)), last_end)
        end = max(float(_word_field(raw_word, "end", start)), start)
        timed[match_index] = (start, end)
        cursor = match_index + 1
        last_end = end

    known_duration = max(
        float(duration_seconds or 0),
        max((value[1] for value in timed if value is not None), default=0.0),
    )
    if not any(value is not None for value in timed):
        return ()

    index = 0
    while index < len(timed):
        if timed[index] is not None:
            index += 1
            continue
        run_start = index
        while index < len(timed) and timed[index] is None:
            index += 1
        run_end = index
        left = timed[run_start - 1][1] if run_start > 0 and timed[run_start - 1] else 0.0
        right = timed[run_end][0] if run_end < len(timed) and timed[run_end] else known_duration
        right = max(right, left)
        weights = [
            max(len(source_tokens[token_index][2]), 1)
            for token_index in range(run_start, run_end)
        ]
        total_weight = max(sum(weights), 1)
        elapsed = left
        for token_index, weight in zip(range(run_start, run_end), weights, strict=True):
            token_end = elapsed + ((right - left) * weight / total_weight)
            timed[token_index] = (elapsed, token_end)
            elapsed = token_end

    cues: list[NarrationCue] = []
    previous_end_ms = 0
    for (start_char, end_char, _), timing in zip(source_tokens, timed, strict=True):
        assert timing is not None
        start_ms = max(round(timing[0] * 1000), previous_end_ms)
        end_ms = max(round(timing[1] * 1000), start_ms + 1)
        cues.append(
            NarrationCue(
                start=start_char,
                end=end_char,
                startMs=start_ms,
                endMs=end_ms,
            )
        )
        previous_end_ms = end_ms
    return tuple(cues)


async def render_book_narration(text: str, style: str) -> NarrationAsset:
    """Render or retrieve one expressive narration passage."""

    if not settings.book_narration_enabled or not settings.openai_api_key:
        raise BookNarrationUnavailableError("Expressive narration is not configured")
    preset = _STYLE_PRESETS.get(style)
    if preset is None:
        raise ValueError(f"Unsupported narration style: {style}")

    cleaned_text = text.strip()
    digest = hashlib.sha256(
        "\n".join(
            (
                _CACHE_VERSION,
                settings.book_narration_tts_model,
                settings.book_narration_alignment_model,
                style,
                preset.voice,
                cleaned_text,
            )
        ).encode("utf-8")
    ).hexdigest()
    filename = f"book_narration_{digest}.mp3"
    media_dir = Path(settings.book_narration_media_dir)
    audio_path = media_dir / filename
    metadata_path = media_dir / f"book_narration_{digest}.json"

    lock = _locks.setdefault(digest, asyncio.Lock())
    async with lock:
        cached = await _read_cached_asset(
            audio_path=audio_path,
            metadata_path=metadata_path,
            filename=filename,
        )
        if cached is not None:
            return cached

        await asyncio.to_thread(media_dir.mkdir, parents=True, exist_ok=True)
        client = AsyncOpenAI(api_key=settings.openai_api_key)
        try:
            try:
                response = await client.audio.speech.create(
                    model=settings.book_narration_tts_model,
                    voice=preset.voice,
                    input=cleaned_text,
                    instructions=preset.instructions,
                    response_format="mp3",
                    timeout=settings.book_narration_timeout_seconds,
                )
                audio_bytes = await response.aread()
            except Exception as exc:
                logger.warning(
                    "Expressive book narration generation failed: %s",
                    type(exc).__name__,
                )
                raise BookNarrationUnavailableError("Narration generation failed") from exc
            if len(audio_bytes) < 128:
                raise BookNarrationUnavailableError("Narration provider returned empty audio")

            alignment: tuple[NarrationCue, ...] = ()
            duration_ms: int | None = None
            try:
                transcript = await client.audio.transcriptions.create(
                    file=(filename, audio_bytes, "audio/mpeg"),
                    model=settings.book_narration_alignment_model,
                    response_format="verbose_json",
                    timestamp_granularities=["word"],
                    temperature=0,
                    timeout=settings.book_narration_timeout_seconds,
                )
                duration = float(getattr(transcript, "duration", 0) or 0)
                duration_ms = round(duration * 1000) if duration > 0 else None
                alignment = align_transcribed_words(
                    cleaned_text,
                    getattr(transcript, "words", None) or (),
                    duration,
                )
            except Exception as exc:
                # Playback quality is more important than perfect highlighting.
                # The Flutter player estimates word positions from media duration
                # when alignment is unavailable.
                logger.warning("Book narration alignment failed: %s", type(exc).__name__)
        finally:
            await client.close()

        metadata = {
            "style": style,
            "voice": preset.voice,
            "durationMs": duration_ms,
            "alignment": [asdict(cue) for cue in alignment],
        }
        await _write_cache_atomically(
            audio_path=audio_path,
            metadata_path=metadata_path,
            audio_bytes=audio_bytes,
            metadata=metadata,
        )
        return NarrationAsset(
            audio_url=f"/media/{filename}",
            style=style,
            voice=preset.voice,
            duration_ms=duration_ms,
            alignment=alignment,
            cached=False,
        )


async def _read_cached_asset(
    *,
    audio_path: Path,
    metadata_path: Path,
    filename: str,
) -> NarrationAsset | None:
    if not audio_path.is_file() or not metadata_path.is_file():
        return None
    try:
        raw = await asyncio.to_thread(metadata_path.read_text, encoding="utf-8")
        metadata = json.loads(raw)
        alignment = tuple(NarrationCue(**item) for item in metadata.get("alignment", []))
        return NarrationAsset(
            audio_url=f"/media/{filename}",
            style=str(metadata["style"]),
            voice=str(metadata["voice"]),
            duration_ms=metadata.get("durationMs"),
            alignment=alignment,
            cached=True,
        )
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        return None


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
        audio_temp.write_bytes(audio_bytes)
        metadata_temp.write_text(
            json.dumps(metadata, separators=(",", ":")),
            encoding="utf-8",
        )
        os.replace(audio_temp, audio_path)
        os.replace(metadata_temp, metadata_path)

    await asyncio.to_thread(write)


def _markdown_to_visible_text(markdown: str) -> str:
    text = _markdown_image.sub(r"\1", markdown)
    text = _markdown_link.sub(r"\1", text)
    return html.unescape(re.sub(r"[`*_~>#|]", "", text))


def _compact_for_membership(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return "".join(character for character in normalized if character.isalnum())


def _normalize_word(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return "".join(character for character in normalized if character.isalnum())


def _word_field(value: Any, field: str, default: Any) -> Any:
    if isinstance(value, dict):
        return value.get(field, default)
    return getattr(value, field, default)
