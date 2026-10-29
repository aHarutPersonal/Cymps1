"""The learner's situation, collected by the onboarding "Your situation" step.

``POST /sessions`` stores situation chips ("I work full-time", "Evenings are
best") and an optional note as ``IntakeSession.situation_json``::

    {"situation": ["I commute", ...], "note": "free text" | None}

The column is null for sessions created by app builds from before v3, so every
reader here tolerates a missing or malformed value and an old session renders
exactly as it did before.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

SITUATION_MAX_ITEMS = 8


def build_situation_json(
    situation: Sequence[str] | None, note: str | None
) -> dict[str, Any] | None:
    """The stored form of the onboarding situation; ``None`` when empty."""
    chips = [chip for chip in (situation or []) if isinstance(chip, str) and chip]
    note = note.strip() if isinstance(note, str) else ""
    if not chips and not note:
        return None
    return {"situation": chips, "note": note or None}


def read_situation(situation_json: Any) -> tuple[list[str], str | None]:
    """Chips and note from a stored value; ``([], None)`` for anything else."""
    if not isinstance(situation_json, dict):
        return [], None
    raw_chips = situation_json.get("situation")
    chips = [
        " ".join(chip.split())
        for chip in (raw_chips if isinstance(raw_chips, list) else [])
        if isinstance(chip, str) and chip.strip()
    ][:SITUATION_MAX_ITEMS]
    raw_note = situation_json.get("note")
    note = raw_note.strip() if isinstance(raw_note, str) else ""
    return chips, note or None


def session_situation(session: Any) -> tuple[list[str], str | None]:
    """Chips and note of a session, tolerating sessions that predate v3."""
    return read_situation(getattr(session, "situation_json", None))


def situation_profile_fields(session: Any) -> dict[str, Any]:
    """``user_profile`` entries for the comparison and blueprint prompts.

    Keys are present only when the learner said something, so a session from
    before v3 produces a byte-identical prompt profile.
    """
    chips, note = session_situation(session)
    fields: dict[str, Any] = {}
    if chips:
        fields["situation"] = chips
    if note:
        fields["situation_note"] = note
    return fields


def situation_sentence(
    situation: Sequence[str] | None,
    note: str | None,
    *,
    max_length: int | None = None,
) -> str:
    """One readable sentence, e.g. ``Situation: I commute; Evenings are best.
    Two kids under five.``; empty when nothing was said.

    ``max_length`` cuts at a word boundary and ends with an ellipsis, so a long
    note never leaves a half word behind.
    """
    chips = [chip for chip in (situation or []) if chip]
    note = " ".join(note.split()) if isinstance(note, str) else ""
    if note and note[-1] not in ".!?…":
        note += "."
    if chips:
        sentence = "Situation: " + "; ".join(chips) + "."
        if note:
            sentence += " " + note
    elif note:
        sentence = "Situation: " + note
    else:
        return ""
    if max_length is not None and len(sentence) > max_length:
        cut = sentence[: max_length - 1].rstrip()
        space = cut.rfind(" ")
        # Prefer a word boundary, unless the only one is too early to matter.
        if space > max_length // 2:
            cut = cut[:space].rstrip(" ;,")
        sentence = cut + "…"
    return sentence


def situation_context_lines(
    situation: Sequence[str] | None, note: str | None
) -> list[str]:
    """Lines for the plan prompts' free-text ``user_context``."""
    chips = [chip for chip in (situation or []) if chip]
    note = " ".join(note.split()) if isinstance(note, str) else ""
    lines: list[str] = []
    if chips:
        lines.append("Situation: " + "; ".join(chips))
    if note:
        lines.append("Situation note: " + note)
    return lines
