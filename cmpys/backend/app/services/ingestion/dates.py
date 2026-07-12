"""Deterministic age calculation for partially dated idol milestones."""

from __future__ import annotations

import re
from datetime import date
from typing import Any, Iterable


_EXPLICIT_AGE_PATTERNS = (
    re.compile(r"\b(?:at|by)\s+age\s+(\d{1,3})\b", re.IGNORECASE),
    re.compile(r"\baged\s+(\d{1,3})\b", re.IGNORECASE),
    re.compile(
        r"\b(?:at\s+)?(\d{1,3})\s+years?\s+(?:of\s+age|old)\b",
        re.IGNORECASE,
    ),
    re.compile(r"\b(?:a|an)\s+(\d{1,3})[- ]year[- ]old\b", re.IGNORECASE),
    re.compile(
        r"\bwhen\s+(?:he|she|they|the\s+\w+|\w+)\s+was\s+(\d{1,3})\b",
        re.IGNORECASE,
    ),
)


def _precision_value(value: Any) -> str:
    raw = getattr(value, "value", value)
    return str(raw or "unknown").lower()


def _explicit_evidence_age(evidence: Iterable[Any]) -> int | None:
    """Return a source-stated age only when all matching snippets agree."""
    ages: set[int] = set()
    for item in evidence:
        snippet = str(getattr(item, "snippet", "") or "")
        for pattern in _EXPLICIT_AGE_PATTERNS:
            match = pattern.search(snippet)
            if match:
                age = int(match.group(1))
                if 0 <= age <= 150:
                    ages.add(age)
                break
    return next(iter(ages)) if len(ages) == 1 else None


def compute_event_age(
    *,
    birth_date: date | None,
    event_date: date | None,
    date_precision: Any,
    evidence: Iterable[Any] = (),
) -> int | None:
    """Compute a conservative age without asking the LLM to do date math.

    A verbatim source statement such as ``at age 19`` wins. Day-precision
    dates produce an exact age. Month precision uses the known month, while a
    same-month ambiguity takes the later possible age. Year precision also
    takes the later possible age, preventing an approximate event from being
    presented as having happened earlier than the source proves.
    """
    explicit = _explicit_evidence_age(evidence)
    if explicit is not None:
        return explicit
    if birth_date is None or event_date is None:
        return None

    precision = _precision_value(date_precision)
    age = event_date.year - birth_date.year
    if precision == "day":
        if (event_date.month, event_date.day) < (
            birth_date.month,
            birth_date.day,
        ):
            age -= 1
    elif precision == "month":
        if event_date.month < birth_date.month:
            age -= 1
    elif precision == "year":
        # The exact month is unknown. Use the later possible age so an
        # age-filtered comparison never credits the idol too early.
        pass
    else:
        return None

    return age if 0 <= age <= 150 else None


def apply_computed_timeline_ages(profile: Any, response: Any) -> Any:
    """Overwrite model-supplied date arithmetic with deterministic ages."""
    birth_date = getattr(getattr(profile, "profile", None), "birth_date", None)
    for event in getattr(response, "timeline", []):
        event.age_at_event = compute_event_age(
            birth_date=birth_date,
            event_date=getattr(event, "date", None),
            date_precision=getattr(event, "date_precision", None),
            evidence=getattr(event, "evidence", ()),
        )
    return response
