"""Plan-ready, session-scoped inputs captured by the mentor interview.

The chat transcript remains the canonical human-readable record.  Assistant
questions additionally carry a server-owned ``answer_key`` in their persisted
``response_ui_json``.  That lets us bind a user's prose (or number-picker
selection) to a planning concept without asking an LLM to rediscover which
answer meant what later.
"""

from __future__ import annotations

import re
from decimal import Decimal, ROUND_HALF_UP
from typing import Any


INTERVIEW_ANSWER_KEYS = (
    "achievement_inventory",
    "current_capability",
    "foundation_check",
    "application_check",
    "weekly_hours",
    "target_outcome",
    "constraints_resources",
    "learning_habits_support",
)

INTERVIEW_ANSWER_KEY_INSTRUCTIONS = {
    "achievement_inventory": (
        "Ask what they have already completed toward their goal. Invite 1-3 "
        "examples with their role, result and rough recency in one short helper "
        "sentence. Explicitly accept 'none yet'. Do not interrogate every detail."
    ),
    "current_capability": (
        "Ask what they can reliably do without step-by-step help. Invite one "
        "recent example and a sticking point, without a checklist. No experience "
        "is valid; studying a subject, resources or a job title do not establish mastery."
    ),
    "foundation_check": "Use the server-provided foundation diagnostic; never infer general mastery from it.",
    "application_check": "Use the server-provided application diagnostic; unknown is a valid result.",
    "weekly_hours": (
        "Ask only for the number of focused hours they can honestly protect "
        "every week for the next twelve weeks. Do not combine this with a "
        "routine or motivation question."
    ),
    "target_outcome": (
        "Ask for the single concrete result they want by the end of twelve "
        "weeks and the observable evidence that would prove success."
    ),
    "constraints_resources": (
        "Ask for the biggest practical limit the plan should work around. "
        "Briefly invite existing tools or support. Treat 'none' as useful information."
    ),
    "learning_habits_support": (
        "Ask what has helped them learn consistently in the past. Briefly invite "
        "one useful format, routine or feedback partner. A new habit is not "
        "established evidence; 'nothing yet' is valid."
    ),
}

# These are complete coverage questions, not fabricated mentor replies or
# inferred learner evidence. They keep intake usable during provider outages.
INTERVIEW_QUESTION_FALLBACKS = {
    "achievement_inventory": (
        "What have you completed that relates to your goal? Share 1–3 examples "
        "with your role, a result, and roughly when it happened. ‘None yet’ is fine."
    ),
    "current_capability": (
        "What can you already do toward your goal without step-by-step help? "
        "One recent example is enough; mention where you get stuck."
    ),
    "weekly_hours": (
        "How many focused hours can you protect each week for the next twelve weeks? "
        "Choose a realistic number between 3 and 60."
    ),
    "target_outcome": (
        "What single result would make these twelve weeks worthwhile? "
        "Describe something you could show or measure."
    ),
    "constraints_resources": (
        "What is the biggest practical limit your plan should work around? "
        "Mention any tools, access, or support you already have."
    ),
    "learning_habits_support": (
        "What has helped you learn consistently in the past? "
        "A useful format, routine, or feedback partner is enough. ‘Nothing yet’ is fine."
    ),
}

_NUMBER_WORD_UNITS = {
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
    "thirteen": 13,
    "fourteen": 14,
    "fifteen": 15,
    "sixteen": 16,
    "seventeen": 17,
    "eighteen": 18,
    "nineteen": 19,
}
_NUMBER_WORD_TENS = {
    "twenty": 20,
    "thirty": 30,
    "forty": 40,
    "fifty": 50,
    "sixty": 60,
}
_RANGE_RE = re.compile(
    r"\b(\d{1,3}(?:\.\d+)?)\s*(?:-|–|—|\bto\b|\band\b)\s*"
    r"(\d{1,3}(?:\.\d+)?)\b",
    re.IGNORECASE,
)
_NUMBER_RE = re.compile(r"(?<![\w.])(\d{1,3}(?:\.\d+)?)(?![\w.])")
_LEGACY_HOURS_RE = re.compile(
    r"(?<![a-z0-9])(?:"
    r"between\s+\d{1,3}(?:\.\d+)?\s+and\s+\d{1,3}(?:\.\d+)?"
    r"|\d{1,3}(?:\.\d+)?\s*(?:-|–|—|\bto\b)\s*\d{1,3}(?:\.\d+)?"
    r"|\d{1,3}(?:\.\d+)?"
    r")\s*(?:hours?|hrs?|h)(?![a-z])",
    re.IGNORECASE,
)
_HOURS_UNIT_RE = re.compile(r"(?<![a-z])(?:hours?|hrs?|h)(?![a-z])", re.IGNORECASE)


def _role_value(message: Any) -> str:
    role = getattr(message, "role", "")
    return str(getattr(role, "value", role)).casefold()


def _rounded_hours(value: Decimal) -> int:
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _word_number_candidates(text: str) -> list[tuple[int, int]]:
    """Return ``(character_position, value)`` for English numbers 0-60."""
    tokens = list(re.finditer(r"[a-z]+", text.casefold()))
    candidates: list[tuple[int, int]] = []
    index = 0
    while index < len(tokens):
        token = tokens[index].group(0)
        if token in _NUMBER_WORD_TENS:
            value = _NUMBER_WORD_TENS[token]
            if index + 1 < len(tokens):
                next_token = tokens[index + 1].group(0)
                if (
                    next_token in _NUMBER_WORD_UNITS
                    and _NUMBER_WORD_UNITS[next_token] < 10
                ):
                    value += _NUMBER_WORD_UNITS[next_token]
                    index += 1
            candidates.append((tokens[index].start(), value))
        elif token in _NUMBER_WORD_UNITS:
            candidates.append((tokens[index].start(), _NUMBER_WORD_UNITS[token]))
        index += 1
    return candidates


def _exact_word_number(text: str) -> int | None:
    """Parse a standalone English integer phrase in the supported 0-60 range."""
    words = re.sub(r"[-]+", " ", text.casefold()).split()
    if len(words) == 1:
        return _NUMBER_WORD_UNITS.get(words[0], _NUMBER_WORD_TENS.get(words[0]))
    if (
        len(words) == 2
        and words[0] in _NUMBER_WORD_TENS
        and words[1] in _NUMBER_WORD_UNITS
        and _NUMBER_WORD_UNITS[words[1]] < 10
    ):
        return _NUMBER_WORD_TENS[words[0]] + _NUMBER_WORD_UNITS[words[1]]
    return None


def parse_weekly_hours_answer(
    text: str,
    *,
    require_week_context: bool = False,
    clamp_legacy: bool = False,
) -> int | None:
    """Parse a weekly commitment, including picker text and common custom text.

    New keyed questions already establish the weekly-hours context, so a bare
    ``"8"`` is valid.  Legacy transcript scans require both an hours expression
    and an explicit week reference to avoid treating unrelated ages or sleep
    durations as capacity.  New answers outside the honest 3-60 product range
    are rejected; legacy values retain historical clamping behavior.
    """
    normalized = " ".join(str(text or "").split())
    # Normalize Russian answers to the same strict integer parser used by the
    # picker. Do not guess ranges or round a fractional commitment.
    russian_numbers = {
        "ноль": "zero",
        "один": "one",
        "одна": "one",
        "два": "two",
        "две": "two",
        "три": "three",
        "четыре": "four",
        "пять": "five",
        "шесть": "six",
        "семь": "seven",
        "восемь": "eight",
        "девять": "nine",
        "десять": "ten",
        "одиннадцать": "eleven",
        "двенадцать": "twelve",
        "тринадцать": "thirteen",
        "четырнадцать": "fourteen",
        "пятнадцать": "fifteen",
        "шестнадцать": "sixteen",
        "семнадцать": "seventeen",
        "восемнадцать": "eighteen",
        "девятнадцать": "nineteen",
        "двадцать": "twenty",
        "тридцать": "thirty",
        "сорок": "forty",
        "пятьдесят": "fifty",
        "шестьдесят": "sixty",
    }
    normalized = re.sub(
        r"[а-яё]+",
        lambda match: russian_numbers.get(match[0].casefold(), match[0]),
        normalized,
        flags=re.IGNORECASE,
    )
    normalized = re.sub(r"\bчас(?:а|ов)?\b", "hours", normalized, flags=re.IGNORECASE)
    normalized = re.sub(r"\bнедел[яюиь]\b", "week", normalized, flags=re.IGNORECASE)
    lowered = normalized.casefold()
    if not normalized:
        return None
    if require_week_context and (
        "week" not in lowered or _LEGACY_HOURS_RE.search(normalized) is None
    ):
        return None

    # A leading explicit weekly total may be followed by a day-by-day schedule.
    # Keep the original answer in the interview; parse only that unambiguous total.
    if not clamp_legacy:
        scheduled = re.match(r"^(\d{1,2})\s+hours?\s+(?:per|a|each)\s+week\b(.*)$", normalized, re.IGNORECASE)
        if scheduled and re.search(r"\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b", scheduled[2], re.IGNORECASE):
            if not re.search(r"\b(?:week|or|instead|maybe|possibly)\b", scheduled[2], re.IGNORECASE):
                total = int(scheduled[1])
                return total if 3 <= total <= 60 else None

    range_matches = list(_RANGE_RE.finditer(normalized))

    # A keyed weekly-hours answer is a confirmed planning constraint, not an
    # estimate. Accept one exact step-1 value: a bare number/number word, or a
    # sentence that explicitly binds that single value to hours per week.
    # Ranges, fractional commitments, and prose containing another number are
    # ambiguous and must be clarified instead of rounded or guessed.
    if not clamp_legacy:
        if range_matches:
            return None
        numeric_matches = list(_NUMBER_RE.finditer(normalized))
        compact_hour_matches = list(
            re.finditer(
                r"(?<![\w.])(\d{1,3}(?:\.\d+)?)(?=(?:h|hr|hrs)(?![a-z]))",
                normalized,
                re.IGNORECASE,
            )
        )
        numeric_spans = {match.span(1) for match in numeric_matches}
        numeric_matches.extend(
            match
            for match in compact_hour_matches
            if match.span(1) not in numeric_spans
        )
        word_candidates = _word_number_candidates(normalized)
        candidates: list[Decimal] = [
            Decimal(match.group(1)) for match in numeric_matches
        ] + [Decimal(value) for _, value in word_candidates]
        if len(candidates) != 1:
            return None
        value = candidates[0]
        if value != value.to_integral_value():
            return None

        bare_numeric = len(numeric_matches) == 1 and numeric_matches[0].span() == (
            0,
            len(normalized),
        )
        bare_word = _exact_word_number(normalized) is not None
        explicit_weekly_hours = (
            _HOURS_UNIT_RE.search(normalized) is not None and "week" in lowered
        )
        if not (bare_numeric or bare_word or explicit_weekly_hours):
            return None
        parsed = int(value)
        return parsed if 3 <= parsed <= 60 else None

    # Legacy transcripts can contain ages, dates, and durations. Parse only
    # the last expression directly attached to an hours unit instead of the
    # last (or first range) anywhere in the answer.
    legacy_hour_matches = list(_LEGACY_HOURS_RE.finditer(normalized))
    if not legacy_hour_matches:
        return None
    legacy_expression = legacy_hour_matches[-1].group(0)
    range_matches = list(_RANGE_RE.finditer(legacy_expression))
    if range_matches:
        match = range_matches[-1]
        low = Decimal(match.group(1))
        high = Decimal(match.group(2))
        if high < low:
            low, high = high, low
        parsed = _rounded_hours((low + high) / 2)
    else:
        candidates: list[tuple[int, Decimal]] = [
            (match.start(), Decimal(match.group(1)))
            for match in re.finditer(r"(\d{1,3}(?:\.\d+)?)", legacy_expression)
        ]
        candidates.extend(
            (position, Decimal(value))
            for position, value in _word_number_candidates(legacy_expression)
        )
        if not candidates:
            return None
        _, value = max(candidates, key=lambda candidate: candidate[0])
        parsed = _rounded_hours(value)

    return max(3, min(60, parsed)) if 1 <= parsed <= 100 else None


def collect_interview_answers(messages: list[Any]) -> dict[str, list[dict[str, str]]]:
    """Pair user answers with persisted server-owned answer keys.

    ``reply_to_message_id`` is authoritative.  The nearest preceding assistant
    fallback keeps the semantic contract usable for a content-only client that
    predates question IDs, while only questions with a whitelisted key count.
    """
    answers: dict[str, list[dict[str, str]]] = {
        key: [] for key in INTERVIEW_ANSWER_KEYS
    }
    questions_by_id: dict[str, Any] = {}
    nearest_question: Any | None = None

    for message in messages:
        if _role_value(message) == "assistant":
            nearest_question = message
            message_id = getattr(message, "id", None)
            if message_id is not None:
                questions_by_id[str(message_id)] = message
            continue
        if _role_value(message) != "user":
            continue

        reply_to = getattr(message, "reply_to_message_id", None)
        question = questions_by_id.get(str(reply_to)) if reply_to else nearest_question
        metadata = getattr(question, "response_ui_json", None) if question else None
        key = metadata.get("answer_key") if isinstance(metadata, dict) else None
        if key not in answers:
            continue

        content = str(getattr(message, "content", "") or "").strip()
        if not content:
            continue
        message_id = str(getattr(message, "id", "") or "")
        if message_id and any(
            existing["source_message_id"] == message_id for existing in answers[key]
        ):
            continue
        answers[key].append(
            {
                "answer": content,
                "source_message_id": message_id,
                "question_id": str(getattr(question, "id", "") or ""),
                "diagnostic_id": str(metadata.get("diagnostic_id") or ""),
            }
        )
    return answers


def missing_interview_answer_keys(messages: list[Any]) -> list[str]:
    answers = collect_interview_answers(messages)
    missing: list[str] = []
    for key in INTERVIEW_ANSWER_KEYS:
        records = answers[key]
        if not records:
            missing.append(key)
        elif key == "weekly_hours" and not any(
            parse_weekly_hours_answer(record["answer"]) is not None
            for record in records
        ):
            missing.append(key)
    return missing


def next_interview_answer_key(messages: list[Any]) -> str | None:
    missing = missing_interview_answer_keys(messages)
    return missing[0] if missing else None


def build_interview_plan_inputs(
    messages: list[Any],
    *,
    session_goal: str | None = None,
    require_diagnostics: bool = False,
) -> dict[str, Any]:
    """Build the versioned learner baseline consumed by later planning."""
    answers = collect_interview_answers(messages)
    latest = {
        key: (records[-1] if records else None) for key, records in answers.items()
    }
    weekly_hours = None
    for record in reversed(answers["weekly_hours"]):
        weekly_hours = parse_weekly_hours_answer(record["answer"])
        if weekly_hours is not None:
            break

    achievement_text = (
        latest["achievement_inventory"]["answer"]
        if latest["achievement_inventory"]
        else None
    )
    normalized_achievement = (
        re.sub(
            r"[^\w]+",
            " ",
            achievement_text.casefold().replace("'", "").replace("’", ""),
        ).strip()
        if achievement_text
        else ""
    )
    none_yet = normalized_achievement in {
        "нет",
        "пока нет",
        "ничего",
        "пока ничего",
        "none",
        "none yet",
        "nothing",
        "nothing yet",
        "no achievements",
        "no achievements yet",
        "i have none",
        "i have none yet",
        "i havent achieved anything yet",
        "i have not achieved anything yet",
        "i dont have any achievements yet",
        "i do not have any achievements yet",
        "no relevant achievements",
        "no relevant achievements yet",
    }

    from app.services.intake_diagnostics import (
        diagnostic_summary,
        answer_evidence_status,
        reports_no_achievements,
    )
    none_yet = none_yet or reports_no_achievements(achievement_text or "")

    evidence_status = {
        key: answer_evidence_status(record["answer"] if record else "")
        for key, record in latest.items()
    }
    return {
        "version": 2,
        "answer_evidence_status": evidence_status,
        "skill_diagnostics": diagnostic_summary(answers),
        "placement_policy": "Use demonstrated skills only within the checked scope. Unknown is not beginner. Resources are not knowledge. Validate uncertain prerequisites in the first lesson.",
        "goal": session_goal,
        "weekly_capacity_hours": weekly_hours,
        "weekly_capacity_confirmed": weekly_hours is not None,
        "achievement_baseline_status": (
            "none_yet"
            if none_yet
            else "self_reported"
            if achievement_text
            and evidence_status["achievement_inventory"] == "self_reported"
            else "missing"
        ),
        "achievement_inventory": latest["achievement_inventory"],
        "current_capability": latest["current_capability"],
        "foundation_check": latest["foundation_check"],
        "application_check": latest["application_check"],
        "target_outcome": latest["target_outcome"],
        "constraints_resources": latest["constraints_resources"],
        "learning_habits_support": latest["learning_habits_support"],
        "answered_keys": [key for key in INTERVIEW_ANSWER_KEYS if latest[key]],
        "missing_keys": [
            key
            for key in missing_interview_answer_keys(messages)
            if require_diagnostics
            or key not in {"foundation_check", "application_check"}
            or any(
                answers[check] for check in ("foundation_check", "application_check")
            )
        ],
    }


def provider_interview_plan_inputs(plan_inputs: dict[str, Any]) -> dict[str, Any]:
    """Return the provider-facing baseline without internal message UUIDs.

    Source IDs remain in the server-side baseline for auditability. Model
    providers only need the self-reported answer text and planning semantics.
    """
    result: dict[str, Any] = {
        "version": plan_inputs.get("version", 1),
        "answer_evidence_status": plan_inputs.get("answer_evidence_status", {}),
        "skill_diagnostics": plan_inputs.get("skill_diagnostics", []),
        "placement_policy": plan_inputs.get("placement_policy"),
        "practice_evidence": plan_inputs.get("practice_evidence", []),
        "north_star_goal": plan_inputs.get("goal"),
        "weekly_capacity_hours": plan_inputs.get("weekly_capacity_hours"),
        "weekly_capacity_confirmed": bool(plan_inputs.get("weekly_capacity_confirmed")),
        "weekly_capacity_source": plan_inputs.get("weekly_capacity_source"),
        "achievement_baseline_status": plan_inputs.get(
            "achievement_baseline_status", "missing"
        ),
        "answered_keys": list(plan_inputs.get("answered_keys") or []),
        "missing_keys": list(plan_inputs.get("missing_keys") or []),
    }
    for key in INTERVIEW_ANSWER_KEYS:
        record = plan_inputs.get(key)
        result[key] = (
            {"answer": str(record.get("answer") or "").strip()}
            if isinstance(record, dict) and str(record.get("answer") or "").strip()
            else None
        )
    return result


def extract_legacy_weekly_hours(messages: list[Any]) -> int | None:
    """Compatibility parser for interviews created before semantic keys."""
    found: int | None = None
    for message in messages:
        if _role_value(message) != "user":
            continue
        parsed = parse_weekly_hours_answer(
            str(getattr(message, "content", "") or ""),
            require_week_context=True,
            clamp_legacy=True,
        )
        if parsed is not None:
            found = parsed
    return found


def compact_placement_context(baseline: dict[str, Any]) -> str:
    """Keep placement evidence ahead of long narrative context in lesson prompts."""
    import json

    if not baseline:
        return (
            "Learner placement: not assessed; check prerequisites in the first lesson."
        )
    facts = {
        "answer_evidence_status": baseline.get("answer_evidence_status", {}),
        "skill_diagnostics": [
            {key: item.get(key) for key in ("skill_id", "status", "scope")}
            for item in (baseline.get("skill_diagnostics") or [])[:2]
            if isinstance(item, dict)
        ],
    }
    from app.services.practice.evidence import compact_practice_evidence
    facts["recent_practice"] = compact_practice_evidence(baseline.get("practice_evidence") or [])
    for key in ("current_capability", "target_outcome", "constraints_resources"):
        record = baseline.get(key)
        facts[key] = (
            str(record.get("answer") or "")[:450] if isinstance(record, dict) else None
        )
    return (
        "Learner placement (self-report and narrow checks, not general mastery):\n"
        + json.dumps(facts, ensure_ascii=False)
    )
