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


# The 8-key question set used before intake v3. Sessions that asked any of
# its retired keys keep it to completion; it is otherwise only read.
INTERVIEW_ANSWER_KEYS_V1 = (
    "achievement_inventory",
    "current_capability",
    "foundation_check",
    "application_check",
    "weekly_hours",
    "target_outcome",
    "constraints_resources",
    "learning_habits_support",
)

# Intake v3: twelve adaptive inputs, in the order they are asked.
INTERVIEW_ANSWER_KEYS_V2 = (
    "achievement_inventory",
    "work_sample",
    "foundation_check",
    "application_check",
    "self_check_method",
    "skill_confidence",
    "practice_volume",
    "resources_capital",
    "network_support",
    "learning_preferences",
    "weekly_hours",
    "target_outcome",
)

# Every key a persisted question may carry, for membership checks only.
ALL_INTERVIEW_ANSWER_KEYS = tuple(
    dict.fromkeys(INTERVIEW_ANSWER_KEYS_V1 + INTERVIEW_ANSWER_KEYS_V2)
)
_V1_ONLY_KEYS = frozenset(INTERVIEW_ANSWER_KEYS_V1) - frozenset(INTERVIEW_ANSWER_KEYS_V2)

# The server builds these controls in full; the model only phrases the question.
SERVER_OWNED_CONTROL_KEYS = frozenset(
    {
        "achievement_inventory",
        "work_sample",
        "current_capability",
        "practice_volume",
        "network_support",
        "learning_preferences",
        "weekly_hours",
    }
)
# The model proposes these controls (option wording, details, labels), but the
# server enforces the kind and replaces a wrong-kind control with its default.
MODEL_CONTROL_KINDS = {
    "self_check_method": "single_choice",
    "skill_confidence": "scale",
    "resources_capital": "single_choice",
    "target_outcome": "text",
}

# The design's five learning modes, shown as pick-all-that-fit cards.
LEARNING_PREFERENCE_OPTIONS = (
    ("Worked examples", "list"),
    ("Reading deeply", "book"),
    ("Doing exercises", "edit"),
    ("Listening", "headphones"),
    ("Short daily sessions", "clock"),
)
WORK_SAMPLE_MISSING_OPTION = "I don’t have one yet"
PREFER_NOT_TO_SAY = "Prefer not to say"

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
    "work_sample": (
        "Ask them to paste or briefly describe one short piece of their own work "
        "toward the goal, even a rough one, and make clear that not having one "
        "yet is an acceptable answer because missing evidence is fine and "
        "pretending is not."
    ),
    "self_check_method": (
        "Ask how they check whether their own work or judgment toward the goal "
        "is right, in the goal domain's own terms, without implying that any "
        "method is the correct one."
    ),
    "skill_confidence": (
        "Ask how comfortable they are today with the one core skill the goal "
        "depends on, naming that skill concretely for this domain, as a rating "
        "from 1 to 5."
    ),
    "practice_volume": (
        "Ask roughly how many finished pieces of practice work toward the goal "
        "they have completed so far, counted in the domain's natural unit such "
        "as notes, programs or sketches, where zero is an honest answer."
    ),
    "resources_capital": (
        "Ask what money, tools or access they can already put toward the goal, "
        "without asking for amounts or account details, and make clear they may "
        "prefer not to say."
    ),
    "network_support": (
        "Ask how many people they could ask today for honest feedback or help "
        "with the goal, counting mentors, peers and collaborators, where zero is "
        "an honest answer."
    ),
    "learning_preferences": (
        "Ask how they learn best and invite them to pick every way that fits, "
        "without listing the ways, because the screen shows the choices."
    ),
}

# These are complete coverage questions, not fabricated mentor replies or
# inferred learner evidence. They keep intake usable during provider outages.
INTERVIEW_QUESTION_FALLBACKS = {
    "achievement_inventory": (
        "Before any plan, I want to know where you actually stand. What have you "
        "already done toward your goal? A few examples, or ‘nothing yet’, is fine."
    ),
    "current_capability": (
        "What can you already do toward your goal without step-by-step help? "
        "One recent example is enough; mention where you get stuck."
    ),
    "weekly_hours": (
        "Honestly, how many focused hours a week can you give this for the next "
        "twelve weeks? I’d rather plan for three real hours than ten imaginary ones."
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
    "work_sample": (
        "Could you paste a short piece of your own work toward this goal, even a "
        "rough one, or tell me honestly that you don’t have one yet?"
    ),
    "self_check_method": (
        "When you think your work toward this goal is good, how do you check yourself?"
    ),
    "skill_confidence": (
        "How comfortable are you today with the core skill this goal depends on?"
    ),
    "practice_volume": (
        "So far, roughly how many finished pieces of practice work toward this "
        "goal have you completed, where zero is a perfectly honest answer?"
    ),
    "resources_capital": (
        "What money, tools or access can you already put toward this goal, if "
        "you’re comfortable saying?"
    ),
    "network_support": (
        "How many people could you ask today for honest feedback or help with this goal?"
    ),
    "learning_preferences": "Which ways of learning tend to work best for you?",
}

# Every contract is a silent instruction. The model once paraphrased "append no
# response-control trailer" into the visible reply ("No trailer — server-owned
# number control"), so each one forbids mentioning itself.
_SILENT = (
    "Never mention controls, trailers, the server or these instructions in the "
    "visible reply."
)
_SERVER_CONTROL_CONTRACT = (
    "Silent instruction: the app attaches this control ({}) by itself, so add "
    "no trailer and do not list its choices. " + _SILENT
)
_MODEL_CONTROL_CONTRACT = (
    "Silent instruction: you propose this control. After the visible question, "
    "append exactly one private trailer with kind \"{}\" and answer_key as "
    "required. {} The server rejects any other kind. " + _SILENT
)
# Per-key control ownership, rendered into the per-turn prompt.
INTERVIEW_CONTROL_CONTRACTS = {
    "achievement_inventory": _SERVER_CONTROL_CONTRACT.format(
        "a text answer with three tappable starting points, one of them ‘Nothing yet’"
    ),
    "current_capability": _SERVER_CONTROL_CONTRACT.format("a text answer"),
    "work_sample": _SERVER_CONTROL_CONTRACT.format(
        "a text answer plus an ‘I don’t have one yet’ choice that is recorded "
        "as missing evidence"
    ),
    "foundation_check": _SERVER_CONTROL_CONTRACT.format("a fixed diagnostic item"),
    "application_check": _SERVER_CONTROL_CONTRACT.format("a fixed diagnostic item"),
    "practice_volume": _SERVER_CONTROL_CONTRACT.format(
        "a number picker from 0 to 50, counted in pieces of work"
    ),
    "network_support": _SERVER_CONTROL_CONTRACT.format(
        "a number picker from 0 to 20, counted in people"
    ),
    "learning_preferences": _SERVER_CONTROL_CONTRACT.format(
        "pick-all-that-fit cards for five learning modes"
    ),
    "weekly_hours": _SERVER_CONTROL_CONTRACT.format(
        "a weekly-hours number picker"
    ),
    "self_check_method": _MODEL_CONTROL_CONTRACT.format(
        "single_choice",
        "Write 3-5 options naming how a person could check their own work in this "
        "goal's domain, each with a short description, and end with an honest "
        "option such as ‘I don’t really check’.",
    ),
    "skill_confidence": _MODEL_CONTROL_CONTRACT.format(
        "scale",
        "Write a low_label and a high_label, each at most 40 characters, naming "
        "the two ends of this goal's core skill in plain words.",
    ),
    "resources_capital": _MODEL_CONTROL_CONTRACT.format(
        "single_choice",
        "Write 3-5 options describing levels of money, tools or access relevant "
        "to this goal, each with a short description, and make the last option "
        "exactly ‘Prefer not to say’.",
    ),
    "target_outcome": _MODEL_CONTROL_CONTRACT.format(
        "text",
        "Write 2-3 suggestions, each at most 60 characters, naming concrete, "
        "showable twelve-week results for this goal; never an unsure starting "
        "point such as ‘I’m not sure yet’, because the answer becomes the plan's goal.",
    ),
    "constraints_resources": (
        "Silent instruction: you propose this control. Use kind \"text\" unless 2-6 "
        "neutral, mutually exclusive options genuinely make answering easier. " + _SILENT
    ),
    "learning_habits_support": (
        "Silent instruction: you propose this control. Use kind \"text\" unless 2-6 "
        "neutral, mutually exclusive options genuinely make answering easier. " + _SILENT
    ),
}
INTERVIEW_CLOSING_CONTROL_CONTRACT = (
    "None: this is the closing turn, so append nothing after the reply. " + _SILENT
)


def interview_control_contract(answer_key: str | None) -> str:
    """Return the per-turn control ownership rule for one required key."""
    if answer_key is None:
        return INTERVIEW_CLOSING_CONTROL_CONTRACT
    return INTERVIEW_CONTROL_CONTRACTS.get(
        answer_key,
        "Silent instruction: you propose this control. Use kind \"text\" if "
        "uncertain. " + _SILENT,
    )

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

    # Accept a complete session breakdown only when it agrees with the
    # explicit weekly total; conflicting or ambiguous quantities need clarification.
    if not clamp_legacy:
        sessions = re.fullmatch(
            r"(\d{1,2})\s+hours?\s+(?:per|a|each)\s+week\s*[,;:]?\s*"
            r"(?:in|split into|across)\s+([a-z -]+|\d{1,2})\s+"
            r"(\d{1,3})[ -]minutes?\s+sessions?\.?",
            normalized, re.IGNORECASE,
        )
        if sessions:
            total = int(sessions[1])
            count_text = sessions[2].strip()
            count = int(count_text) if count_text.isdigit() else _exact_word_number(count_text)
            minutes = int(sessions[3])
            if count is not None and count > 0 and minutes > 0 and count * minutes == total * 60:
                return total if 3 <= total <= 60 else None
            return None

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


# Intake v3 capacity: 1-15 hours a week in half-hour steps, stored as minutes.
WEEKLY_MINUTES_MIN = 60
WEEKLY_MINUTES_MAX = 900
WEEKLY_MINUTES_STEP = 30

_WEEK_SUFFIX = (
    r"(?:\s*(?:/\s*|(?:per|a|an|each|every)\s+)(?:week|wk)|\s+weekly)?"
)
_HOUR_UNIT = r"(?:hours?|hrs?|h)"
_MINUTE_UNIT = r"(?:minutes?|mins?|m)"
_HOURS_AND_MINUTES_RE = re.compile(
    rf"(\d{{1,2}})\s*{_HOUR_UNIT}\s*(?:and\s+)?(\d{{1,2}})\s*(?:{_MINUTE_UNIT})?{_WEEK_SUFFIX}"
)
_MINUTES_ONLY_RE = re.compile(rf"(\d{{1,3}})\s*{_MINUTE_UNIT}{_WEEK_SUFFIX}")
_DECIMAL_HOURS_RE = re.compile(
    rf"(\d{{1,2}}(?:\.\d{{1,2}})?)\s*(?:{_HOUR_UNIT})?{_WEEK_SUFFIX}"
)
_WORD_HOURS_RE = re.compile(
    rf"([a-z]+(?:[\s-]+[a-z]+)??)(\s+and\s+a\s+half)?(?:\s*{_HOUR_UNIT})?{_WEEK_SUFFIX}"
)


def _exact_capacity_minutes(text: str) -> int | None:
    """Minutes from one unambiguous capacity expression, or ``None``."""
    match = _HOURS_AND_MINUTES_RE.fullmatch(text)
    if match:
        minutes = int(match[2])
        return int(match[1]) * 60 + minutes if minutes < 60 else None
    match = _MINUTES_ONLY_RE.fullmatch(text)
    if match:
        return int(match[1])
    match = _DECIMAL_HOURS_RE.fullmatch(text)
    if match:
        minutes = Decimal(match[1]) * 60
        return int(minutes) if minutes == minutes.to_integral_value() else None
    match = _WORD_HOURS_RE.fullmatch(text)
    if match:
        value = _exact_word_number(match[1])
        if value is not None:
            return value * 60 + (30 if match[2] else 0)
    return None


def parse_weekly_minutes_answer(text: str) -> int | None:
    """Parse an intake v3 weekly commitment into minutes (60-900, step 30).

    Accepts the number control's ``"4.5 hours / week"`` and common custom
    text: a bare number of hours (``"4.5"``, comma decimal ``"4,5"``), hours
    and minutes (``"4 h 30"``), minutes (``"270 minutes"``) or a number
    word. Whole-hour sentences the legacy parser understands (a weekly total
    followed by a schedule) are accepted too. Ranges, other numbers and
    anything off the 30-minute grid or outside 1-15 hours are rejected
    rather than rounded or guessed.
    """
    normalized = " ".join(str(text or "").split())
    if not normalized:
        return None
    candidate = normalized.casefold().rstrip(".!")
    candidate = re.sub(r"(?<=\d),(?=\d)", ".", candidate)
    candidate = re.sub(r"(\d)\s*½", r"\1.5", candidate).replace("½", "0.5")
    minutes = _exact_capacity_minutes(candidate)
    if minutes is None:
        hours = parse_weekly_hours_answer(normalized)
        minutes = hours * 60 if hours is not None else None
    if (
        minutes is None
        or not WEEKLY_MINUTES_MIN <= minutes <= WEEKLY_MINUTES_MAX
        or minutes % WEEKLY_MINUTES_STEP
    ):
        return None
    return minutes


def parse_weekly_capacity_minutes(
    text: str, key_set: tuple[str, ...]
) -> int | None:
    """Parse a weekly-capacity answer with its session's contract.

    Intake v3 sessions accept 60-900 minutes in 30-minute steps. Legacy
    8-key sessions keep their 3-60 whole-hour contract, stored as minutes.
    """
    if key_set == INTERVIEW_ANSWER_KEYS_V1:
        hours = parse_weekly_hours_answer(text)
        return hours * 60 if hours is not None else None
    return parse_weekly_minutes_answer(text)


def weekly_capacity_rejection(key_set: tuple[str, ...]) -> str:
    """The 409 message for an answer outside the session's capacity contract."""
    if key_set == INTERVIEW_ANSWER_KEYS_V1:
        return "Choose a weekly commitment between 3 and 60 hours."
    return (
        "Choose a weekly commitment between 1 and 15 hours, in half-hour steps."
    )


def baseline_weekly_minutes(plan_inputs: dict[str, Any] | None) -> int | None:
    """Confirmed weekly minutes of a learner baseline.

    Baselines stored before minutes existed carry whole hours only.
    """
    if not isinstance(plan_inputs, dict):
        return None
    minutes = plan_inputs.get("weekly_capacity_minutes")
    if isinstance(minutes, int) and not isinstance(minutes, bool) and minutes > 0:
        return minutes
    hours = plan_inputs.get("weekly_capacity_hours")
    if _is_number(hours) and hours > 0:
        return round(hours * 60)
    return None


def _hours_value(minutes: int) -> int | float:
    """Whole hours stay integers; half hours become floats (4.5)."""
    return minutes // 60 if minutes % 60 == 0 else minutes / 60


def interview_key_set(messages: list[Any]) -> tuple[str, ...]:
    """Return the question set a session is using, judged from its questions.

    A session that was asked any key retired by intake v3 keeps the 8-key set
    until it completes; every other session (including a brand-new one) uses
    the v3 set. Questions are never relabelled, so the answer is stable.
    """
    for message in messages:
        if _role_value(message) != "assistant":
            continue
        metadata = getattr(message, "response_ui_json", None)
        if isinstance(metadata, dict) and metadata.get("answer_key") in _V1_ONLY_KEYS:
            return INTERVIEW_ANSWER_KEYS_V1
    return INTERVIEW_ANSWER_KEYS_V2


def _key_set_name(keys: tuple[str, ...]) -> str:
    return "v1" if keys == INTERVIEW_ANSWER_KEYS_V1 else "v2"


def _baseline_key_set(baseline: dict[str, Any]) -> tuple[str, ...]:
    """Key set of a stored baseline; baselines from before v3 carry no marker."""
    if baseline.get("interview_key_set") == "v2":
        return INTERVIEW_ANSWER_KEYS_V2
    return INTERVIEW_ANSWER_KEYS_V1


def collect_interview_answers(messages: list[Any]) -> dict[str, list[dict[str, Any]]]:
    """Pair user answers with persisted server-owned answer keys.

    ``reply_to_message_id`` is authoritative.  The nearest preceding assistant
    fallback keeps the semantic contract usable for a content-only client that
    predates question IDs, while only questions with a key of the session's
    question set count. An answer sent with the client's "I don't have one
    yet" option is kept as an answer and flagged ``missing_evidence``.
    """
    answers: dict[str, list[dict[str, Any]]] = {
        key: [] for key in interview_key_set(messages)
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
        answer_metadata = getattr(message, "response_ui_json", None)
        answers[key].append(
            {
                "answer": content,
                "source_message_id": message_id,
                "question_id": str(getattr(question, "id", "") or ""),
                "diagnostic_id": str(metadata.get("diagnostic_id") or ""),
                "missing_evidence": isinstance(answer_metadata, dict)
                and answer_metadata.get("missing_evidence") is True,
            }
        )
    return answers


def missing_interview_answer_keys(messages: list[Any]) -> list[str]:
    answers = collect_interview_answers(messages)
    key_set = interview_key_set(messages)
    missing: list[str] = []
    for key in key_set:
        records = answers[key]
        if not records:
            missing.append(key)
        elif key == "weekly_hours" and not any(
            parse_weekly_capacity_minutes(record["answer"], key_set) is not None
            for record in records
        ):
            missing.append(key)
    return missing


def next_interview_answer_key(messages: list[Any]) -> str | None:
    missing = missing_interview_answer_keys(messages)
    return missing[0] if missing else None


# A whole answer that commits to nothing ("I’m not sure yet", "don’t know",
# "no idea"). Matched against intake_diagnostics.normalized() text, where
# apostrophes and punctuation have become spaces.
_NONCOMMITTAL_RE = re.compile(
    r"(?:(?:honestly|to be honest|tbh|well|hmm|um) )?"
    r"(?:"
    r"(?:i m |i am |im )?(?:still )?"
    r"(?:not (?:really |quite |totally |entirely )?(?:sure|certain)|unsure|undecided)"
    r"|(?:i )?(?:(?:don t|dont|do not) (?:really )?know|dunno|idk)"
    r"|(?:i )?(?:have |ve )?no (?:idea|clue|goal|target|plan)"
    r"|(?:i )?(?:haven t|havent|have not) (?:decided|thought about it|figured (?:it|that) out)"
    r"|not decided|nothing|none|not yet|tbd|n a|maybe|anything|whatever|no preference"
    r")"
    r"(?: (?:yet|really|at all|for now|right now|either))*"
)


def is_noncommittal_answer(text: str) -> bool:
    """True when an answer as a whole expresses no commitment or knowledge.

    Used where a verbatim answer would otherwise become a plan input (the
    twelve-week target): such an answer is no evidence and must not replace
    the onboarding goal.
    """
    from app.services.intake_diagnostics import answer_evidence_status, normalized

    if answer_evidence_status(text or "") != "self_reported":
        return True
    return _NONCOMMITTAL_RE.fullmatch(normalized(text)) is not None


def parse_learning_preferences(text: str) -> list[str]:
    """Split a pick-all-that-fit answer (sent as a comma list) into items.

    Known modes keep their canonical label; custom text is kept, trimmed and
    de-duplicated. An unknown/skip answer is no preference, not a mode.
    """
    from app.services.intake_diagnostics import answer_evidence_status

    if answer_evidence_status(text or "") != "self_reported":
        return []
    canonical = {label.casefold(): label for label, _ in LEARNING_PREFERENCE_OPTIONS}
    result: list[str] = []
    seen: set[str] = set()
    for raw in re.split(r"[,;\n]+", text):
        item = " ".join(raw.split()).strip(" .")
        if not item:
            continue
        item = canonical.get(item.casefold(), item[:80])
        if item.casefold() in seen:
            continue
        seen.add(item.casefold())
        result.append(item)
        if len(result) >= 8:
            break
    return result


def build_interview_plan_inputs(
    messages: list[Any],
    *,
    session_goal: str | None = None,
    require_diagnostics: bool = False,
) -> dict[str, Any]:
    """Build the versioned learner baseline consumed by later planning.

    The baseline carries the records of the session's own question set
    (``interview_key_set``), so a legacy 8-key intake stays complete and keeps
    its keys, while a v3 intake exposes the twelve v3 inputs.
    """
    keys = interview_key_set(messages)
    answers = collect_interview_answers(messages)
    latest = {
        key: (records[-1] if records else None) for key, records in answers.items()
    }
    weekly_minutes = None
    for record in reversed(answers["weekly_hours"]):
        weekly_minutes = parse_weekly_capacity_minutes(record["answer"], keys)
        if weekly_minutes is not None:
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

    missing_evidence_keys = [
        key for key in keys if latest[key] and latest[key].get("missing_evidence")
    ]
    evidence_status = {
        # "I don't have one yet" is an honest answer that records missing
        # evidence; it is never self-reported evidence of the skill.
        key: "missing"
        if key in missing_evidence_keys
        else answer_evidence_status(record["answer"] if record else "")
        for key, record in latest.items()
    }
    # An unsure target ("I’m not sure yet") answers the question, so the
    # intake still completes, but it is no evidence and never a plan goal:
    # with no target record, focus, execution goal and profile goals fall back
    # to the onboarding goal.
    target_record = latest.get("target_outcome")
    noncommittal_target = bool(
        target_record and is_noncommittal_answer(target_record["answer"])
    )
    if noncommittal_target:
        evidence_status["target_outcome"] = "unknown"
    learning_preferences = (
        parse_learning_preferences(latest["learning_preferences"]["answer"])
        if latest.get("learning_preferences")
        else []
    )
    baseline = {
        "version": 2,
        "interview_key_set": _key_set_name(keys),
        "answer_evidence_status": evidence_status,
        "skill_diagnostics": diagnostic_summary(answers),
        "placement_policy": "Use demonstrated skills only within the checked scope. Unknown is not beginner. Resources are not knowledge. Validate uncertain prerequisites in the first lesson.",
        "goal": session_goal,
        # Planners read minutes. Hours are the same value for readers of
        # older baselines: an int for whole hours, a float such as 4.5.
        "weekly_capacity_hours": (
            _hours_value(weekly_minutes) if weekly_minutes is not None else None
        ),
        "weekly_capacity_minutes": weekly_minutes,
        "weekly_capacity_confirmed": weekly_minutes is not None,
        "achievement_baseline_status": (
            "none_yet"
            if none_yet
            else "self_reported"
            if achievement_text
            and evidence_status["achievement_inventory"] == "self_reported"
            else "missing"
        ),
        "missing_evidence_keys": missing_evidence_keys,
        "learning_preferences": learning_preferences,
        "answered_keys": [key for key in keys if latest[key]],
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
    for key in keys:
        if key not in _PARSED_VALUE_KEYS:
            baseline[key] = latest[key]
    if noncommittal_target:
        baseline["target_outcome"] = None
    return baseline


# Answers carried as parsed values (capacity, the list of learning modes)
# rather than as answer records; the transcript keeps the exact wording.
_PARSED_VALUE_KEYS = frozenset({"weekly_hours", "learning_preferences"})


def provider_interview_plan_inputs(plan_inputs: dict[str, Any]) -> dict[str, Any]:
    """Return the provider-facing baseline without internal message UUIDs.

    Source IDs remain in the server-side baseline for auditability. Model
    providers only need the self-reported answer text and planning semantics.
    """
    keys = _baseline_key_set(plan_inputs)
    minutes = baseline_weekly_minutes(plan_inputs)
    result: dict[str, Any] = {
        "version": plan_inputs.get("version", 1),
        "interview_key_set": _key_set_name(keys),
        "answer_evidence_status": plan_inputs.get("answer_evidence_status", {}),
        "skill_diagnostics": plan_inputs.get("skill_diagnostics", []),
        "placement_policy": plan_inputs.get("placement_policy"),
        "practice_evidence": plan_inputs.get("practice_evidence", []),
        "north_star_goal": plan_inputs.get("goal"),
        # Minutes are canonical; hours (a float) keep older readers working.
        "weekly_capacity_minutes": minutes,
        "weekly_capacity_hours": minutes / 60 if minutes is not None else None,
        "weekly_capacity_confirmed": bool(plan_inputs.get("weekly_capacity_confirmed")),
        "weekly_capacity_source": plan_inputs.get("weekly_capacity_source"),
        "achievement_baseline_status": plan_inputs.get(
            "achievement_baseline_status", "missing"
        ),
        "missing_evidence_keys": list(plan_inputs.get("missing_evidence_keys") or []),
        "learning_preferences": list(plan_inputs.get("learning_preferences") or []),
        "answered_keys": list(plan_inputs.get("answered_keys") or []),
        "missing_keys": list(plan_inputs.get("missing_keys") or []),
    }
    for key in keys:
        if key == "learning_preferences":
            continue  # carried above as the parsed list
        record = plan_inputs.get(key)
        result[key] = (
            {"answer": str(record.get("answer") or "").strip()}
            if isinstance(record, dict) and str(record.get("answer") or "").strip()
            else None
        )
    return result


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


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


_V1_PLACEMENT_FIELDS = (
    ("current_capability", 450),
    ("target_outcome", 450),
    ("constraints_resources", 450),
)
# Bounded so the whole v3 block stays well under the lesson-context budget.
_V2_PLACEMENT_FIELDS = (
    ("work_sample", 300),
    ("skill_confidence", 60),
    ("practice_volume", 60),
    ("self_check_method", 120),
    ("target_outcome", 300),
    ("resources_capital", 120),
)


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
    if baseline.get("interview_key_set") == "v2":
        placement_fields = _V2_PLACEMENT_FIELDS
        facts["missing_evidence_keys"] = list(baseline.get("missing_evidence_keys") or [])
        facts["learning_preferences"] = list(baseline.get("learning_preferences") or [])[:6]
    else:
        # Pre-v3 baselines keep exactly their previous placement context.
        placement_fields = _V1_PLACEMENT_FIELDS
    for key, limit in placement_fields:
        record = baseline.get(key)
        facts[key] = (
            str(record.get("answer") or "")[:limit] if isinstance(record, dict) else None
        )
    return (
        "Learner placement (self-report and narrow checks, not general mastery):\n"
        + json.dumps(facts, ensure_ascii=False)
    )
