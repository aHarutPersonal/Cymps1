"""Optional lossless display of review source text; no proof or gate changes.

This projection is deliberately not connected to generation. Its caller must
provide authoritative field paths and offsets from the original source
inventory, and keep that original inventory for all canonical verification.
"""
from __future__ import annotations

import copy
import json
from collections.abc import Sequence
from dataclasses import dataclass


SOURCE_PARTS_GUIDANCE = (
    " Source fields may contain ordered text_parts: concatenate each string and each marked "
    "object's text to recover the exact original field. A marked claim_id identifies its "
    "numeric_spans ID; markings and ownership do not establish correctness. "
)


@dataclass(frozen=True)
class SourceOccurrence:
    claim_id: str
    path: tuple[str | int, ...]
    start: int
    end: int


@dataclass(frozen=True)
class ReviewPayloadProjection:
    payload: dict
    guidance: str = ""
    saved_bytes: int = 0

    @property
    def projected(self) -> bool:
        return self.saved_bytes > 0


def _encoded(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"),
                      allow_nan=False).encode("utf-8")


def _source_field(payload: dict, path: tuple) -> tuple[dict, str, str] | None:
    """Resolve only a private source field, never data/formulas/context text."""
    if (type(path) is not tuple or len(path) not in (5, 7)
            or path[:3] != ("package", "workbook", "activities")
            or type(path[3]) is not int or path[3] < 0):
        return None
    activities = payload["package"]["workbook"]["activities"]
    if type(activities) is not list or path[3] >= len(activities):
        return None
    ids = [activity.get("id") if type(activity) is dict else None for activity in activities]
    if any(type(key) is not str or not key for key in ids) or len(set(ids)) != len(ids):
        return None
    activity = activities[path[3]]
    if len(path) == 5:
        if path[4] not in {"instructions", "worked_solution", "hint"}:
            return None
        target, key = activity, path[4]
    else:
        if (path[4] != "fields" or type(path[5]) is not int or path[5] < 0
                or path[6] != "label"):
            return None
        fields = activity.get("fields")
        if type(fields) is not list or path[5] >= len(fields):
            return None
        field_ids = [field.get("id") if type(field) is dict else None for field in fields]
        if (any(type(field_id) is not str or not field_id for field_id in field_ids)
                or len(set(field_ids)) != len(field_ids)):
            return None
        target, key = fields[path[5]], "label"
    if type(target.get(key)) is not str:
        return None
    return target, key, "practice." + activity["id"]


def project_review_payload(
    payload: dict, occurrences: Sequence[SourceOccurrence],
) -> ReviewPayloadProjection:
    """Project only complete, exact mappings that save net UTF-8 request bytes.

    On any ambiguity or lack of savings, return the original payload object.
    Selected strings become ordered source parts; the numeric_spans map becomes
    its same ordered ID list. Every other request field remains unchanged.
    """
    unchanged = ReviewPayloadProjection(payload)
    if type(payload) is not dict or not isinstance(occurrences, Sequence):
        return unchanged
    spans = payload.get("numeric_spans")
    owners = payload.get("numeric_span_owners")
    cases = payload.get("evidence_cases")
    if (type(spans) is not dict or not spans or type(owners) is not dict or type(cases) is not dict
            or any(type(key) is not str or not key or type(span) is not str or not span
                   for key, span in spans.items())
            or len(occurrences) != len(spans)):
        return unchanged
    seen = set()
    fields: dict[tuple, list[SourceOccurrence]] = {}
    try:
        for occurrence in occurrences:
            if (type(occurrence) is not SourceOccurrence
                    or type(occurrence.claim_id) is not str or occurrence.claim_id not in spans
                    or occurrence.claim_id in seen
                    or type(occurrence.start) is not int or type(occurrence.end) is not int
                    or occurrence.start < 0 or occurrence.end <= occurrence.start):
                return unchanged
            resolved = _source_field(payload, occurrence.path)
            if resolved is None:
                return unchanged
            target, key, owner = resolved
            if owners.get(occurrence.claim_id) != owner or owner not in cases:
                return unchanged
            source = target[key]
            if (occurrence.end > len(source)
                    or source[occurrence.start:occurrence.end] != spans[occurrence.claim_id]):
                return unchanged
            seen.add(occurrence.claim_id)
            fields.setdefault(occurrence.path, []).append(occurrence)
        if seen != spans.keys():
            return unchanged
        revised = copy.deepcopy(payload)
        for path, records in fields.items():
            target, key, _ = _source_field(revised, path)
            source = target[key]
            parts = []
            cursor = 0
            for occurrence in sorted(records, key=lambda record: record.start):
                if occurrence.start < cursor:
                    return unchanged
                if occurrence.start > cursor:
                    parts.append(source[cursor:occurrence.start])
                parts.append({"claim_id": occurrence.claim_id,
                              "text": source[occurrence.start:occurrence.end]})
                cursor = occurrence.end
            if cursor < len(source):
                parts.append(source[cursor:])
            reconstructed = "".join(part if isinstance(part, str) else part["text"] for part in parts)
            if reconstructed.encode("utf-8") != source.encode("utf-8"):
                return unchanged
            target[key] = {"text_parts": parts}
        revised["numeric_spans"] = list(spans)
        saved_bytes = len(_encoded(payload)) - len(_encoded(revised)) - len(SOURCE_PARTS_GUIDANCE.encode("utf-8"))
        if saved_bytes <= 0:
            return unchanged
        return ReviewPayloadProjection(revised, SOURCE_PARTS_GUIDANCE, saved_bytes)
    except (KeyError, IndexError, TypeError, ValueError, UnicodeError, RecursionError):
        # Invalid input is not repaired, guessed, truncated or partly projected.
        return unchanged
