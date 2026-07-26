"""Deterministic quality gates for generated learning content.

The checks in this module are deliberately cheap: they run before any retry so
we only spend another LLM call when a user-visible quality requirement failed.
They do not try to replace factual verification; source-grounded prompts and
the ingestion evidence model handle that part of the pipeline.
"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import asdict, dataclass
from typing import Any


# At a conservative adult learning pace of 200 words/minute, 3,200 words is
# sixteen minutes before the embedded exercises. This keeps the product's
# "more than 15 minutes" promise true even for a fast, uninterrupted read.
MIN_BOOK_MODULE_WORDS = 3200
TARGET_BOOK_MODULE_WORDS = 3600
MAX_BOOK_MODULE_WORDS = 4500
BOOK_MODULE_QUALITY_GATE_VERSION = 2

MIN_PLAN_DETAIL_LESSON_WORDS = 1900
TARGET_PLAN_DETAIL_LESSON_WORDS = 2600
MAX_PLAN_DETAIL_LESSON_WORDS = 4200
MIN_PLAN_DETAIL_MATERIAL_WORDS = 350

_FILLER_PHRASES = (
    "in this section we'll explore",
    "in this section, we'll explore",
    "let's dive in",
    "it is important to note",
    "it's important to note",
    "as mentioned earlier",
    "as we've seen",
    "key takeaway",
    "why this matters",
    "real-world example",
    "replicable angle",
    "this teaches us",
    "in today's fast-paced",
    "unlock your potential",
    "the bottom line is",
)

EXPECTED_BOOK_HEADING_COUNT = 7
EXPECTED_BOOK_PRACTICE_COUNT = 6
MAX_DUPLICATE_PARAGRAPH_RATIO = 0.12
MAX_NEAR_DUPLICATE_PARAGRAPH_RATIO = 0.10
MAX_REPEATED_SENTENCE_OPENING_RATIO = 0.20

_GROUNDING_QUOTE_RE = re.compile(
    r'(?:"((?:[^"\n]|\n(?![ \t]*(?:#{1,6}\s|[-*+]\s|\d+[.)]\s|\|)))*)"|'
    r"“((?:[^”\n]|\n(?![ \t]*(?:#{1,6}\s|[-*+]\s|\d+[.)]\s|\|)))*)”|"
    r"‘((?:[^‘’\n]|\n(?![ \t]*(?:#{1,6}\s|[-*+]\s|\d+[.)]\s|\|))|"
    r"(?<=\w)’(?=\w)|(?<=[sS])’(?=\s+(?:[*_`]{1,3})?[^\W\d_]))*)’|"
    r"«((?:[^»\n]|\n(?![ \t]*(?:#{1,6}\s|[-*+]\s|\d+[.)]\s|\|)))*)»|"
    r"(?<![\w])\'((?:[^\'\n]|\n(?![ \t]*(?:#{1,6}\s|[-*+]\s|"
    r"\d+[.)]\s|\|))|(?<=\w)\'(?=\w)|"
    r"(?<=[sS])\'(?=\s+(?:[*_`]{1,3})?[^\W\d_]))*)"
    r"\'(?![\w]))"
)
_GROUNDING_YEAR_RE = re.compile(r"(?:\b[12]\d{3}s?\b|(?<!\w)[’']\d{2}s?\b)")
_ATTRIBUTION_VERB_PATTERN = (
    r"(?:acknowledges?|acknowledged|adds?|added|advises?|advised|argues?|argued|"
    r"asks?|asked|asserts?|asserted|believes?|believed|calls?|called|claims?|claimed|"
    r"comments?|commented|concludes?|concluded|contends?|contended|continues?|"
    r"continued|declares?|declared|defines?|defined|describes?|described|"
    r"emphasizes?|emphasized|explains?|explained|insists?|insisted|maintains?|"
    r"maintained|mentions?|mentioned|notes?|noted|offers?|offered|observes?|observed|"
    r"proposes?|proposed|puts?|reads?|recalls?|recalled|recommends?|recommended|"
    r"remarks?|remarked|reminds?|reminded|replies?|replied|reports?|reported|"
    r"responds?|responded|said|says|shares?|shared|states?|stated|suggests?|suggested|"
    r"tells?|told|warns?|warned|writes?|wrote)"
)
_HYPOTHETICAL_SPEAKER_RE = re.compile(
    rf"\b(?:prospect|customer|interviewee|interviewer|practitioner|manager|founder|owner|user|buyer|client|"
    rf"respondent|person|someone|coach|facilitator|partner|they|he|she|you)\b"
    rf"[^,;.!?\n]{{0,45}}?\b"
    rf"{_ATTRIBUTION_VERB_PATTERN}\b",
    re.IGNORECASE,
)
_HYPOTHETICAL_SPEAKER_SUFFIX_RE = re.compile(
    rf"^\s*[,;:—–-]?\s*{_ATTRIBUTION_VERB_PATTERN}\s+(?:the\s+)?"
    rf"(?:prospect|customer|interviewee|interviewer|practitioner|manager|founder|owner|user|buyer|client|"
    rf"respondent|person|someone|coach|facilitator|partner)\b",
    re.IGNORECASE,
)
_ROLEPLAY_CONTEXT_RE = re.compile(
    r"\b(?:hypothetical|imagine|role[- ]?play|scenario|suppose)\b",
    re.IGNORECASE,
)
_NON_SOURCE_ACCORDING_TO_RE = re.compile(
    r"\baccording\s+to\s+(?:(?:your|our|the|this|these|a|an)\s+)?"
    r"(?:[a-z-]+\s+){0,2}(?:"
    r"notes?|exercises?|examples?|journals?|scenarios?|worksheets?|lessons?|"
    r"responses?|dialogues?|scripts?|customers?|prospects?|interviewees?|interviewers?|practitioners?|"
    r"managers?|founders?|owners?|users?|buyers?|clients?|respondents?|partners?"
    r")\b",
    re.IGNORECASE,
)
_NON_SOURCE_SENTENCE_START_PATTERN = (
    r"(?:A|An|As|At|Before|Customer|For|Founder|He|If|Imagine|In|Instead|It|"
    r"Manager|On|Owner|Prospect|She|Suppose|Supposing|That|The|Then|They|This|"
    r"User|We|When|You|Your)"
)
_PROPER_NAME_ATTRIBUTION_PREFIX_RE = re.compile(
    rf"\b(?:As\s+)?(?!{_NON_SOURCE_SENTENCE_START_PATTERN}\b)"
    rf"[A-Z][\w'’.-]*(?:\s+(?:&\s+)?[A-Z][\w'’.-]*){{0,5}}"
    rf"[^.!?]{{0,50}}\b{_ATTRIBUTION_VERB_PATTERN}\b"
    r"[^.!?]{0,60}\s*[,;:]?\s*$"
)
_DIRECT_ATTRIBUTION_PREFIX_RE = re.compile(
    rf"(?:"
    rf"\baccording\s+to\b[^.!?]{{0,100}}[,;:]?\s*|"
    rf"\b(?:as\s+)?(?:the\s+)?(?:author|book)\b[^.!?]{{0,80}}\b"
    rf"{_ATTRIBUTION_VERB_PATTERN}\b[^.!?]{{0,60}}\s*[,;:]?\s*|"
    rf"\bin\s+the\s+book\s*,\s*(?:the\s+)?author\b[^.!?]{{0,60}}\b"
    rf"{_ATTRIBUTION_VERB_PATTERN}\b[^.!?]{{0,60}}\s*[,;:]?\s*"
    rf")$",
    re.IGNORECASE,
)
_DIRECT_ATTRIBUTION_SUFFIX_RE = re.compile(
    rf"^\s*[,;:—–-]?\s*(?:"
    rf"according\s+to\b[^.!?]{{0,100}}|"
    rf"{_ATTRIBUTION_VERB_PATTERN}\b[^.!?]{{0,60}}\b(?:author|book)\b|"
    rf"(?:the\s+)?(?:author|book)\b[^.!?]{{0,40}}\b"
    rf"{_ATTRIBUTION_VERB_PATTERN}\b"
    rf")",
    re.IGNORECASE,
)
_SOURCE_NOUN_ATTRIBUTION_PREFIX_RE = re.compile(
    rf"\b(?:the\s+)?(?:source|chapter|preface|publisher|study|research|report|paper|text)\b"
    rf"[^.!?]{{0,60}}\b{_ATTRIBUTION_VERB_PATTERN}\b"
    r"[^.!?]{0,60}\s*[,;:]?\s*$",
    re.IGNORECASE,
)
_PROPER_NAME_ATTRIBUTION_SUFFIX_RE = re.compile(
    rf"^\s*[,;:—–-]?\s*(?:"
    rf"{_ATTRIBUTION_VERB_PATTERN}\s+"
    rf"(?!{_NON_SOURCE_SENTENCE_START_PATTERN}\b)"
    rf"[A-Z][\w'’.-]*(?:\s+(?:&\s+)?[A-Z][\w'’.-]*){{0,5}}|"
    rf"(?!{_NON_SOURCE_SENTENCE_START_PATTERN}\b)"
    rf"[A-Z][\w'’.-]*(?:\s+(?:&\s+)?[A-Z][\w'’.-]*){{0,5}}"
    rf"[^.!?]{{0,40}}\b{_ATTRIBUTION_VERB_PATTERN}\b"
    rf")"
)
_AUTHOR_WORDS_PREFIX_RE = re.compile(
    r"\b(?:in\s+)?(?:the\s+)?author(?:'s|’s)\s+(?:own\s+)?"
    r"(?:words?|account|advice|definition|description|warning)\s*[,;:]?\s*$",
    re.IGNORECASE,
)
_PROPER_NAME_PATTERN = (
    rf"(?!{_NON_SOURCE_SENTENCE_START_PATTERN}\b)"
    rf"[A-Z][\w'’.-]*(?:\s+(?:&\s+)?[A-Z][\w'’.-]*){{0,5}}"
)
_PROPER_NAME_WORDS_PREFIX_RE = re.compile(
    rf"\b(?:In\s+)?{_PROPER_NAME_PATTERN}(?:'s|’s)\s+(?:own\s+)?"
    r"(?:words?|account|advice|definition|description|warning)\s*[,;:]?\s*$"
)
_PROPER_NAME_CREDIT_PREFIX_RE = re.compile(
    r"(?:^|[.!?]\s+|\n\s*)"
    r"(?P<credit>(?:The\s+)?[A-Z][\w'’.-]*"
    r"(?:\s+(?:&\s+)?[A-Z][\w'’.-]*){0,5})\s*:\s*$"
)
_PROPER_NAME_CREDIT_SUFFIX_RE = re.compile(
    rf"^\s*(?:[—–-]\s*|\(\s*){_PROPER_NAME_PATTERN}\s*\)?"
    rf"(?=\s*(?:[.!?]|\n|$))"
)
_ILLUSTRATIVE_DIALOGUE_CUE_RE = re.compile(
    r"(?:\b(?:delivers?\s+fluff|offers?\s+(?:a\s+)?compliment|"
    r"proposes?\s+(?:an?\s+)?(?:idea|feature)|instead\s+of\s+saying|"
    r"instead\s+of\s+asking|(?:simply|just|then|instead)\s+(?:ask|say)|"
    r"(?:a|the)\s+(?:precise\s+)?(?:problem\s+|customer\s+|discovery\s+)?"
    r"interview\s+(?:asks?|says?)|"
    rf"(?:the|this|your|our|a|an)\s+(?:(?:following|next|practice)\s+)?"
    rf"(?:exercise|prompt|example|worksheet|script|activity|practice|lesson|"
    rf"checklist|template)\s+{_ATTRIBUTION_VERB_PATTERN}|"
    r"you\s+(?:must\s+|might\s+|should\s+)?ask)\b[^.!?\n]{0,35}[(:,]\s*)$",
    re.IGNORECASE,
)
_IMPERATIVE_QUOTE_CUE_RE = re.compile(
    rf"(?:^|[.!?\n]\s+)(?:(?:(?:in|during|for)\s+"
    rf"(?:(?:this|the|your|an?)\s+)?(?:exercise|worksheet|practice|activity|journal)"
    rf"\s*,\s*)|(?:(?:now|next|then)\s*,?\s*))?"
    rf"(?:(?:as\s+)?(?:the|your|an?)\s+(?:interviewer|practitioner|coach|"
    rf"facilitator)\s*,\s*)?"
    rf"{_ATTRIBUTION_VERB_PATTERN}\b[^.!?\n:]{{0,60}}[,:]\s*$",
    re.IGNORECASE,
)
_BROAD_ATTRIBUTION_SIGNAL_RE = re.compile(
    rf"\b(?:author|book|according|{_ATTRIBUTION_VERB_PATTERN})\b",
    re.IGNORECASE,
)
_COORDINATED_QUOTE_GAP_RE = re.compile(
    r"\s*(?:[,;:]\s*)?(?:and|or|&|as\s+well\s+as)\s*",
    re.IGNORECASE,
)
_NON_SOURCE_CREDIT_WORDS = {
    "activity",
    "answer",
    "checklist",
    "dialogue",
    "define",
    "describe",
    "discussion",
    "example",
    "explain",
    "exercise",
    "framework",
    "goal",
    "instruction",
    "journal",
    "language",
    "lesson",
    "note",
    "objective",
    "practice",
    "prompt",
    "question",
    "reflection",
    "reminder",
    "response",
    "rule",
    "scenario",
    "script",
    "step",
    "summary",
    "starter",
    "task",
    "template",
    "this",
    "tip",
    "verification",
    "warning",
    "write",
    "worksheet",
    "line",
}
_ATTRIBUTION_ONLY_GENERIC_PREFIX_RE = re.compile(
    rf"^(?:"
    rf"according\s+to(?:\s+research\s+by)?\s+[^,.;!?]{{1,100}}|"
    rf"(?:in\s+the\s+book\s*,\s*)?(?:the\s+)?(?:author|book)\s+"
    rf"(?:clearly\s+|famously\s+)?{_ATTRIBUTION_VERB_PATTERN}"
    rf"(?:\s+in\s+the\s+book)?|"
    rf"as\s+(?:the\s+)?(?:author|book)\s+(?:clearly\s+|famously\s+)?"
    rf"{_ATTRIBUTION_VERB_PATTERN}"
    rf")\s*[,;:]?\s*$",
    re.IGNORECASE,
)
_ATTRIBUTION_ONLY_NAME_PREFIX_RE = re.compile(
    rf"^(?:As\s+)?{_PROPER_NAME_PATTERN}\s+"
    rf"(?:clearly\s+|famously\s+)?{_ATTRIBUTION_VERB_PATTERN}"
    rf"(?:\s+in\s+the\s+book)?\s*[,;:]?\s*$"
)
_ATTRIBUTION_ONLY_SUFFIX_RE = re.compile(
    rf"^\s*[,;:]?\s*(?:"
    rf"{_ATTRIBUTION_VERB_PATTERN}\s+(?:the\s+)?(?:author|book)|"
    rf"according\s+to(?:\s+research\s+by)?\s+[^,.;!?]{{1,100}}|"
    rf"(?:the\s+)?(?:author|book)\s+{_ATTRIBUTION_VERB_PATTERN}"
    rf")\s*[.!?]?\s*$",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class ContentQualityReport:
    passed: bool
    score: float
    issues: list[str]
    metrics: dict[str, int | float]

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["gate_version"] = BOOK_MODULE_QUALITY_GATE_VERSION
        return payload


def _word_count(value: str | None) -> int:
    return len((value or "").split())


def _duplicate_paragraph_ratio(markdown: str) -> float:
    paragraphs = [
        re.sub(r"\s+", " ", paragraph.strip().lower())
        for paragraph in re.split(r"\n\s*\n", markdown)
        if _word_count(paragraph) >= 20
    ]
    if not paragraphs:
        return 0.0
    return 1.0 - (len(set(paragraphs)) / len(paragraphs))


def _paragraph_shingles(paragraph: str, width: int = 3) -> set[tuple[str, ...]]:
    words = re.findall(r"[a-z0-9]+(?:['’][a-z0-9]+)?", paragraph.casefold())
    if len(words) < width:
        return set()
    return {
        tuple(words[index : index + width]) for index in range(len(words) - width + 1)
    }


def _near_duplicate_paragraph_ratio(markdown: str) -> float:
    """Find templated paragraphs that differ only in a few swapped words.

    Exact paragraph equality misses the common failure mode where a model
    repeats the same paragraph skeleton while changing a framework name. A
    conservative shingle threshold catches that pattern without treating
    recurring book terminology as duplication.
    """
    paragraphs = [
        re.sub(r"\s+", " ", paragraph.strip())
        for paragraph in re.split(r"\n\s*\n", markdown)
        if _word_count(paragraph) >= 40
    ]
    if len(paragraphs) < 2:
        return 0.0

    shingles = [_paragraph_shingles(paragraph) for paragraph in paragraphs]
    near_duplicate_count = 0
    for index, current in enumerate(shingles):
        if not current:
            continue
        for previous in shingles[:index]:
            if not previous:
                continue
            union = current | previous
            similarity = len(current & previous) / len(union) if union else 0.0
            if similarity >= 0.72:
                near_duplicate_count += 1
                break
    return near_duplicate_count / len(paragraphs)


def _repeated_sentence_opening_metrics(markdown: str) -> tuple[int, float, int]:
    """Measure exact four-word sentence-stem repetition in prose only."""
    prose_lines = []
    for line in markdown.splitlines():
        stripped = line.strip()
        if not stripped or re.match(r"^(?:#{1,6}\s|[-*+]\s|\d+[.)]\s|>|\|)", stripped):
            continue
        prose_lines.append(stripped)

    sentences = re.split(r"(?<=[.!?])\s+", " ".join(prose_lines))
    openings: list[tuple[str, ...]] = []
    for sentence in sentences:
        words = re.findall(r"[a-z0-9]+(?:['’][a-z0-9]+)?", sentence.casefold())
        if len(words) >= 8:
            openings.append(tuple(words[:4]))
    if len(openings) < 12:
        return 0, 0.0, len(openings)

    most_common_count = Counter(openings).most_common(1)[0][1]
    return most_common_count, most_common_count / len(openings), len(openings)


def _normalize_source_text(value: str) -> str:
    value = re.sub(r"!\[([^\]\n]*)\]\([^\)\n]+\)", r"\1", value)
    value = re.sub(r"\[([^\]\n]+)\]\([^\)\n]+\)", r"\1", value)
    value = re.sub(r"(?m)^[ \t]*>\s?", "", value)
    value = value.replace("*", "").replace("`", "")
    value = re.sub(r"(?<!\w)_{1,3}|_{1,3}(?!\w)", "", value)
    value = (
        value.casefold()
        .replace("’", "'")
        .replace("‘", "'")
        .replace("“", '"')
        .replace("”", '"')
        .replace("«", '"')
        .replace("»", '"')
    )
    return re.sub(r"\s+", " ", value).strip()


def _grounding_quote_text(match: Any) -> str:
    """Return the inner text for every supported quotation delimiter."""
    for index in range(1, 6):
        try:
            value = match.group(index)
        except (IndexError, AttributeError):
            break
        if value is not None:
            return str(value)
    return ""


@dataclass(frozen=True)
class _GroundingQuoteSpan:
    """Small match-compatible span for delimiter-free Markdown epigraphs."""

    marker: str
    quote_text: str
    start_index: int
    end_index: int

    def group(self, index: int = 0) -> str:
        if index == 0:
            return self.marker
        if index == 1:
            return self.quote_text
        raise IndexError(index)

    def start(self, _index: int = 0) -> int:
        return self.start_index

    def end(self, _index: int = 0) -> int:
        return self.end_index


def _iter_grounding_quote_matches(markdown: str):
    """Yield non-empty complete quote pairs for grounding inspection.

    Pairing every quote first is important: applying the minimum length inside
    the regex can misread the closing mark of a short quote as the opening mark
    of a later quote and classify the prose between them as quoted text.
    """
    for match in _GROUNDING_QUOTE_RE.finditer(markdown):
        if _word_count(_grounding_quote_text(match).strip()) >= 1:
            yield match


def _normalized_source_credit_names(values: tuple[str, ...]) -> set[str]:
    return {
        _normalize_source_text(value)
        for value in values
        if isinstance(value, str) and value.strip()
    }


def _strip_credit_line_prefix(value: str) -> str:
    """Remove only structural Markdown prefixes from a source-credit line."""
    candidate = value.strip()
    while True:
        stripped = re.sub(
            r"^(?:#{1,6}\s+|[-*+>]\s+|\d+[.)]\s+)",
            "",
            candidate,
            count=1,
        ).strip()
        if stripped == candidate:
            return candidate
        candidate = stripped


def _strip_credit_markdown(value: str) -> str:
    """Unwrap balanced whole-credit Markdown without discarding prose."""
    candidate = value.strip()
    while candidate:
        link = re.fullmatch(r"\[([^\]\n]+)\]\([^\)\n]+\)", candidate)
        if link is not None:
            candidate = link.group(1).strip()
            continue

        unwrapped = None
        for opening, closing in (
            ("***", "***"),
            ("___", "___"),
            ("**", "**"),
            ("__", "__"),
            ("*", "*"),
            ("_", "_"),
            ("`", "`"),
        ):
            if (
                candidate.startswith(opening)
                and candidate.endswith(closing)
                and len(candidate) > len(opening) + len(closing)
            ):
                unwrapped = candidate[len(opening) : -len(closing)].strip()
                break
        if unwrapped is None:
            return candidate
        candidate = unwrapped
    return candidate


def _expected_source_credit_candidate(
    value: str,
    expected: set[str],
) -> bool:
    expected_without_terminal_punctuation = {
        expected_name.rstrip(".!?") for expected_name in expected
    }
    for raw_candidate in (value.strip(), value.strip().rstrip(".!?")):
        candidate = _normalize_source_text(_strip_credit_markdown(raw_candidate))
        if candidate in expected or (
            candidate.rstrip(".!?") in expected_without_terminal_punctuation
        ):
            return True
    return False


def _suffix_source_credit_candidates(suffix: str) -> list[str]:
    """Return progressively hard-wrapped adjacent suffix-credit candidates."""
    candidates: list[str] = []
    parts: list[str] = []
    for index, raw_line in enumerate(suffix.splitlines()):
        stripped = raw_line.strip()
        # splitlines() exposes the separator immediately after a quote as an
        # empty first entry. A later blank line ends adjacency.
        if not stripped:
            if index == 0:
                continue
            break
        if re.fullmatch(r"(?:\*{1,3}|_{1,3}|`{1,3})", stripped):
            continue
        # A blockquote marker is structure; a following hyphen is the actual
        # credit delimiter and must remain available to the parser below.
        while re.match(r"^>\s*", stripped):
            stripped = re.sub(r"^>\s*", "", stripped, count=1).strip()
        parts.append(stripped)
        candidates.append(" ".join(parts))
        if len(parts) >= 3:
            break
    return candidates


def _expected_composite_source_credit(value: str, expected: set[str]) -> bool:
    if _expected_source_credit_candidate(value, expected):
        return True
    parts = [part.strip() for part in value.split(",") if part.strip()]
    return len(parts) >= 2 and all(
        _expected_source_credit_candidate(part, expected) for part in parts
    )


def _suffix_has_expected_source_credit(suffix: str, expected: set[str]) -> bool:
    for suffix_line in _suffix_source_credit_candidates(suffix):
        suffix_line = _strip_credit_markdown(suffix_line)
        if suffix_line.startswith(("—", "–", "-")) and (
            _expected_composite_source_credit(suffix_line[1:], expected)
        ):
            return True
        parenthesized = re.fullmatch(r"\(\s*(.+?)\s*\)\s*[.!?]?", suffix_line)
        if parenthesized is not None and _expected_composite_source_credit(
            parenthesized.group(1), expected
        ):
            return True
    return False


def _has_expected_source_credit(
    prefix: str,
    suffix: str,
    source_credit_names: tuple[str, ...],
) -> bool:
    """Match exact known title/author credits, including lowercase styling."""
    expected = _normalized_source_credit_names(source_credit_names)
    if not expected:
        return False

    prefix_candidates: list[str] = []
    prefix_lines = prefix.splitlines()
    adjacent_prefix_lines: list[str] = []
    for raw_line in reversed(prefix_lines[-3:]):
        if not raw_line.strip():
            break
        adjacent_prefix_lines.insert(0, _strip_credit_line_prefix(raw_line))
        joined = " ".join(adjacent_prefix_lines)
        unwrapped = _strip_credit_markdown(joined)
        if unwrapped.endswith(":"):
            prefix_candidates.append(unwrapped[:-1])
        if joined.endswith(":"):
            prefix_candidates.append(joined[:-1])
    if any(
        _expected_composite_source_credit(candidate, expected)
        for candidate in prefix_candidates
    ):
        return True

    if _suffix_has_expected_source_credit(suffix, expected):
        return True

    # A single exact suffix credit may apply to a coordinated pair of quotes:
    # `"first" and "second" — Author`. Attribute both individual spans rather
    # than merging them into a fabricated quotation containing the conjunction.
    coordinated = _COORDINATED_QUOTE_GAP_RE.match(suffix)
    if coordinated is not None:
        next_quote = _GROUNDING_QUOTE_RE.match(suffix, coordinated.end())
        if next_quote is not None and _suffix_has_expected_source_credit(
            suffix[next_quote.end() :],
            expected,
        ):
            return True
    return False


def _has_expected_source_verb_attribution(
    prefix: str,
    suffix: str,
    source_credit_names: tuple[str, ...],
) -> bool:
    """Recognize known title/author names next to explicit attribution verbs."""
    expected = _normalized_source_credit_names(source_credit_names)
    if not expected:
        return False
    normalized_prefix = _normalize_source_text(prefix)
    normalized_suffix = _normalize_source_text(suffix)
    for name in expected:
        escaped = re.escape(name)
        if re.search(
            rf"\baccording\s+to\s+{escaped}\s*[,;:]?\s*$",
            normalized_prefix,
            re.IGNORECASE,
        ):
            return True
        if re.search(
            rf"\b{escaped}\s+(?:clearly\s+|famously\s+)?"
            rf"{_ATTRIBUTION_VERB_PATTERN}\b[^.!?]*$",
            normalized_prefix,
            re.IGNORECASE,
        ):
            return True
        if re.match(
            rf"^\s*[,;:—–-]?\s*(?:{_ATTRIBUTION_VERB_PATTERN}\s+)?"
            rf"{escaped}\b",
            normalized_suffix,
            re.IGNORECASE,
        ):
            return True
    return False


def _has_source_credit_prefix(value: str) -> bool:
    """Accept name/title credits while rejecting educational UI labels."""
    match = _PROPER_NAME_CREDIT_PREFIX_RE.search(value)
    if match is None:
        return False
    words = [
        word.casefold()
        for word in re.findall(r"[A-Za-z][\w'’.-]*", match.group("credit"))
    ]
    return len(words) >= 2 and words[-1] not in _NON_SOURCE_CREDIT_WORDS


def _has_source_credit_suffix(value: str) -> bool:
    match = _PROPER_NAME_CREDIT_SUFFIX_RE.search(value)
    if match is None:
        return False
    words = [
        word.casefold() for word in re.findall(r"[A-Za-z][\w'’.-]*", match.group(0))
    ]
    return len(words) >= 2 and words[-1] not in _NON_SOURCE_CREDIT_WORDS


def _proper_attribution_is_hypothetical(
    prefix: str,
    match: re.Match[str],
) -> bool:
    """Tie a hypothetical cue only to the proper-name clause it introduces."""
    lead = prefix[: match.start()]
    role = (
        r"(?:prospect|customer|interviewee|interviewer|practitioner|manager|founder|owner|user|buyer|client|"
        r"respondent|person|coach|facilitator|partner)"
    )
    return bool(
        re.search(
            rf"\b(?:(?:when|if|imagine|suppose|supposing)\s+"
            rf"(?:(?:a|an|the)\s+)?(?:{role}\s+)?|{role}\s+)$",
            lead,
            re.IGNORECASE,
        )
    )


def _has_quote_adjacent_source_attribution(
    text: str,
    quote_match: re.Match[str],
    source_credit_names: tuple[str, ...] = (),
) -> bool:
    """Return whether nearby grammar attributes this exact quote to a source."""
    prefix = text[: quote_match.start()][-120:]
    suffix = text[quote_match.end() :][:120]

    # Bind attribution to the nearest speaker clause. In a construction such
    # as `When a customer says "No," Fitzpatrick writes, "..."`, the later
    # named source must not retroactively claim the customer's short dialogue.
    hypothetical_prefixes = list(_HYPOTHETICAL_SPEAKER_RE.finditer(prefix))
    if hypothetical_prefixes:
        nearest = hypothetical_prefixes[-1]
        tail = prefix[nearest.end() :]
        if len(tail.strip()) <= 12 and not _BROAD_ATTRIBUTION_SIGNAL_RE.search(tail):
            return False

    # A short label in a relative clause (`the editor, who calls it "wrong"`)
    # is terminology, not a quotation attributed by an earlier source clause.
    if _word_count(_grounding_quote_text(quote_match).strip()) <= 2 and re.search(
        r"\bwho\s+(?:calls?|called|labels?|labelled|labeled|terms?|termed)\s+it\s*$",
        prefix,
        re.IGNORECASE,
    ):
        return False

    if _has_expected_source_credit(prefix, suffix, source_credit_names):
        return True
    if _has_expected_source_verb_attribution(prefix, suffix, source_credit_names):
        return True

    # Explicit book/author grammar is authoritative even when an illustrative
    # role also appears nearby in the surrounding prose.
    non_source_according_to = _NON_SOURCE_ACCORDING_TO_RE.search(prefix + " " + suffix)
    if (
        (
            (
                _DIRECT_ATTRIBUTION_PREFIX_RE.search(prefix)
                or _DIRECT_ATTRIBUTION_SUFFIX_RE.search(suffix)
                or _SOURCE_NOUN_ATTRIBUTION_PREFIX_RE.search(prefix)
            )
            and non_source_according_to is None
        )
        or _AUTHOR_WORDS_PREFIX_RE.search(prefix)
        or _PROPER_NAME_WORDS_PREFIX_RE.search(prefix)
    ):
        return True
    if _ILLUSTRATIVE_DIALOGUE_CUE_RE.search(prefix) or _IMPERATIVE_QUOTE_CUE_RE.search(
        prefix
    ):
        return False
    if _PROPER_NAME_CREDIT_PREFIX_RE.search(prefix):
        return False
    if _PROPER_NAME_CREDIT_SUFFIX_RE.search(suffix):
        return False
    if non_source_according_to is not None:
        return False

    # A title-cased person can be either a cited source or a role in a
    # hypothetical. Resolve explicit hypothetical framing before accepting the
    # general proper-name grammar.
    proper_prefix = _PROPER_NAME_ATTRIBUTION_PREFIX_RE.search(prefix)
    if proper_prefix is not None:
        if _proper_attribution_is_hypothetical(prefix, proper_prefix):
            return False
        if not _HYPOTHETICAL_SPEAKER_RE.search(proper_prefix.group(0)):
            return True
    proper_suffix = _PROPER_NAME_ATTRIBUTION_SUFFIX_RE.search(suffix)
    if (
        proper_suffix is not None
        and not _HYPOTHETICAL_SPEAKER_RE.search(proper_suffix.group(0))
        and not _HYPOTHETICAL_SPEAKER_SUFFIX_RE.search(suffix)
        and not _ROLEPLAY_CONTEXT_RE.search(prefix + " " + suffix)
    ):
        return True

    line_start = text.rfind("\n", 0, quote_match.start()) + 1
    line_prefix = text[line_start : quote_match.start()]
    if _word_count(_grounding_quote_text(quote_match).strip()) <= 2 and re.match(
        r"\s*(?:[-*+]\s+|\d+[.)]\s+)",
        line_prefix,
    ):
        return False

    combined_context = prefix + " " + suffix
    without_hypothetical_speakers = _HYPOTHETICAL_SPEAKER_RE.sub(
        "",
        combined_context,
    )
    if (
        without_hypothetical_speakers != combined_context
        or non_source_according_to is not None
        or _HYPOTHETICAL_SPEAKER_SUFFIX_RE.search(suffix)
        or _ROLEPLAY_CONTEXT_RE.search(prefix + " " + suffix)
        or _ILLUSTRATIVE_DIALOGUE_CUE_RE.search(prefix)
        or _IMPERATIVE_QUOTE_CUE_RE.search(prefix)
    ):
        return False
    return bool(_BROAD_ATTRIBUTION_SIGNAL_RE.search(without_hypothetical_speakers))


def _is_source_attribution_only(value: str) -> bool:
    """Return whether a string consists solely of attribution boilerplate."""
    candidate = value.strip()
    if not candidate:
        return False

    complete_patterns = (
        _ATTRIBUTION_ONLY_GENERIC_PREFIX_RE,
        _ATTRIBUTION_ONLY_NAME_PREFIX_RE,
        _ATTRIBUTION_ONLY_SUFFIX_RE,
        _AUTHOR_WORDS_PREFIX_RE,
        _PROPER_NAME_WORDS_PREFIX_RE,
        _PROPER_NAME_CREDIT_SUFFIX_RE,
    )
    for pattern in complete_patterns:
        match = pattern.fullmatch(candidate)
        if match is not None:
            return True
    return False


def _iter_ambiguous_quote_spans(markdown: str):
    """Yield conservative spans for nested/ambiguous same-style quotations."""
    for paragraph_match in re.finditer(
        r"(?s)(.*?)(?:\n[ \t]*\n|\Z)",
        markdown,
    ):
        line = paragraph_match.group(1)
        if not line:
            continue
        line_start = paragraph_match.start(1)

        # Straight double quotes have one glyph for both sides. Four or more
        # marks can be either two short quotes or one quote with a quoted term.
        # When all conventional pairs are short but the outer span is long,
        # preserve safety by treating that ambiguous outer span as one quote.
        positions = [index for index, char in enumerate(line) if char == '"']
        if len(positions) >= 4 and len(positions) % 2 == 0:
            outer_text = line[positions[0] + 1 : positions[-1]]
            between_pair_attribution = any(
                _BROAD_ATTRIBUTION_SIGNAL_RE.search(middle)
                or re.search(r"[.!?](?:\s|$)", middle)
                or _COORDINATED_QUOTE_GAP_RE.fullmatch(middle)
                for index in range(1, len(positions) - 1, 2)
                if (middle := line[positions[index] + 1 : positions[index + 1]])
            )
            if _word_count(outer_text) >= 8 and not between_pair_attribution:
                yield _GroundingQuoteSpan(
                    line[positions[0] : positions[-1] + 1],
                    outer_text,
                    line_start + positions[0],
                    line_start + positions[-1] + 1,
                )

        straight_single_positions: list[int] = []
        for position, character in enumerate(line):
            if character != "'":
                continue
            previous = line[position - 1] if position else ""
            following = line[position + 1] if position + 1 < len(line) else ""
            if previous.isalnum() and following.isalnum():
                continue
            tail = line[position + 1 :]
            next_word = re.match(r"\s+(?:[*_`]{1,3})?([^\W\d_])", tail)
            if previous.casefold() == "s" and next_word is not None:
                continue
            straight_single_positions.append(position)
        if len(straight_single_positions) >= 4:
            outer_text = line[
                straight_single_positions[0] + 1 : straight_single_positions[-1]
            ]
            between_pair_attribution = any(
                _BROAD_ATTRIBUTION_SIGNAL_RE.search(middle)
                or re.search(r"[.!?](?:\s|$)", middle)
                or _COORDINATED_QUOTE_GAP_RE.fullmatch(middle)
                for index in range(1, len(straight_single_positions) - 1, 2)
                if (
                    middle := line[
                        straight_single_positions[index]
                        + 1 : straight_single_positions[index + 1]
                    ]
                )
            )
            if _word_count(outer_text) >= 8 and not between_pair_attribution:
                yield _GroundingQuoteSpan(
                    line[
                        straight_single_positions[0] : straight_single_positions[-1] + 1
                    ],
                    outer_text,
                    line_start + straight_single_positions[0],
                    line_start + straight_single_positions[-1] + 1,
                )

        # Directional delimiters make nesting visible. Apostrophes can add
        # extra right-single tokens, so use the outer bounds conservatively.
        for opening, closing in (("“", "”"), ("«", "»"), ("‘", "’")):
            tokens: list[tuple[int, str]] = []
            for index, char in enumerate(line):
                if char == opening:
                    tokens.append((index, char))
                    continue
                if char != closing:
                    continue
                if closing == "’":
                    previous = line[index - 1] if index else ""
                    following = line[index + 1] if index + 1 < len(line) else ""
                    if previous.isalnum() and following.isalnum():
                        continue
                    next_word = re.match(
                        r"\s+(?:[*_`]{1,3})?([^\W\d_])",
                        line[index + 1 :],
                    )
                    if previous.casefold() == "s" and next_word is not None:
                        continue
                tokens.append((index, char))
            if len(tokens) < 4:
                continue
            opening_positions = [index for index, char in tokens if char == opening]
            closing_positions = [index for index, char in tokens if char == closing]
            if len(opening_positions) < 2 or len(closing_positions) < 2:
                continue
            first = opening_positions[0]
            last = closing_positions[-1]
            if first >= last:
                continue
            ordered = sorted(tokens)
            separated_attribution = any(
                ordered[index][1] == closing
                and ordered[index + 1][1] == opening
                and (
                    _BROAD_ATTRIBUTION_SIGNAL_RE.search(
                        line[ordered[index][0] + 1 : ordered[index + 1][0]]
                    )
                    or re.search(
                        r"[.!?](?:\s|$)",
                        line[ordered[index][0] + 1 : ordered[index + 1][0]],
                    )
                    or _COORDINATED_QUOTE_GAP_RE.fullmatch(
                        line[ordered[index][0] + 1 : ordered[index + 1][0]]
                    )
                )
                for index in range(len(ordered) - 1)
            )
            quote_text = line[first + 1 : last]
            if _word_count(quote_text) >= 8 and not separated_attribution:
                yield _GroundingQuoteSpan(
                    line[first : last + 1],
                    quote_text,
                    line_start + first,
                    line_start + last + 1,
                )


def _iter_blockquote_epigraph_spans(
    markdown: str,
    source_credit_names: tuple[str, ...],
    delimited_matches: list[Any],
):
    """Group Markdown blockquote prose around an exact known-source credit."""
    lines: list[tuple[int, int, str, bool, str]] = []
    offset = 0
    for line_with_ending in markdown.splitlines(keepends=True):
        body = line_with_ending.rstrip("\r\n")
        blockquote = re.match(r"^[ \t]{0,3}>\s?(.*)$", body)
        is_blockquote = blockquote is not None
        content = blockquote.group(1) if blockquote is not None else body
        lines.append((offset, offset + len(body), body, is_blockquote, content))
        offset += len(line_with_ending)

    def _is_emphasized_epigraph(value: str) -> bool:
        candidate = value.strip()
        return any(
            candidate.startswith(wrapper)
            and candidate.endswith(wrapper)
            and len(candidate) > len(wrapper) * 2
            for wrapper in ("***", "___", "**", "__", "*", "_")
        )

    def _span_for_segment(
        segment: list[tuple[int, int, str, bool, str]],
    ) -> _GroundingQuoteSpan | None:
        if not segment:
            return None
        nonempty_lines = [line for line in segment if line[4].strip()]
        if (
            not nonempty_lines
            or (
                not any(line[3] for line in segment)
                and not all(_is_emphasized_epigraph(line[4]) for line in nonempty_lines)
            )
            or any(
                re.match(r"^(?:#{1,6}\s|[-*+]\s|\d+[.)]\s|\|)", line[4].strip())
                for line in nonempty_lines
            )
        ):
            return None
        quote_text = " ".join(
            _strip_credit_markdown(line[4].strip()) for line in nonempty_lines
        )
        marker_start = segment[0][0]
        marker_end = segment[-1][1]
        if _word_count(quote_text) < 1 or any(
            match.start() >= marker_start and match.end() <= marker_end
            for match in delimited_matches
        ):
            return None
        return _GroundingQuoteSpan(
            markdown[marker_start:marker_end],
            quote_text,
            marker_start,
            marker_end,
        )

    yielded_spans: set[tuple[int, int]] = set()

    # Suffix credits may be blockquoted or unquoted. Permit ordinary lazy
    # continuation lines only between the first `>` line and the credit.
    for credit_index, line in enumerate(lines):
        credit_text = line[4] if line[3] else line[2]
        if not _has_expected_source_credit("", credit_text, source_credit_names):
            continue
        emphasized_index = credit_index - 1
        if (
            emphasized_index >= 0
            and not lines[emphasized_index][2].strip()
            and not lines[emphasized_index][3]
        ):
            # A blank separator between an emphasized epigraph and its credit
            # is normal Markdown layout and must not sever the attribution.
            emphasized_index -= 1
        if emphasized_index >= 0 and _is_emphasized_epigraph(
            lines[emphasized_index][4]
        ):
            emphasized_span = _span_for_segment([lines[emphasized_index]])
            if (
                emphasized_span is not None
                and (
                    emphasized_span.start(),
                    emphasized_span.end(),
                )
                not in yielded_spans
            ):
                yielded_spans.add((emphasized_span.start(), emphasized_span.end()))
                yield emphasized_span
        earliest_blockquote: int | None = None
        for candidate_index in range(credit_index - 1, max(-1, credit_index - 7), -1):
            candidate = lines[candidate_index]
            if not candidate[2].strip() and not candidate[3]:
                break
            if candidate[3]:
                earliest_blockquote = candidate_index
                continue
            if earliest_blockquote is not None:
                break
        if earliest_blockquote is None:
            continue
        span = _span_for_segment(lines[earliest_blockquote:credit_index])
        if span is not None and (span.start(), span.end()) not in yielded_spans:
            yielded_spans.add((span.start(), span.end()))
            yield span

    # Prefix credits are exact title/author labels followed by a blockquote.
    for credit_index, line in enumerate(lines[:-1]):
        credit_text = line[4] if line[3] else line[2]
        if not _has_expected_source_credit(credit_text, "", source_credit_names):
            continue
        first_quote_index = credit_index + 1
        if (
            first_quote_index < len(lines)
            and not lines[first_quote_index][2].strip()
            and not lines[first_quote_index][3]
        ):
            first_quote_index += 1
        if first_quote_index >= len(lines):
            continue
        if not lines[first_quote_index][3] and not _is_emphasized_epigraph(
            lines[first_quote_index][4]
        ):
            continue
        end_index = first_quote_index
        while end_index < len(lines):
            candidate = lines[end_index]
            if not candidate[2].strip() and not candidate[3]:
                break
            if end_index > first_quote_index and _has_expected_source_credit(
                "",
                candidate[4] if candidate[3] else candidate[2],
                source_credit_names,
            ):
                break
            end_index += 1
        span = _span_for_segment(lines[first_quote_index:end_index])
        if span is not None and (span.start(), span.end()) not in yielded_spans:
            yielded_spans.add((span.start(), span.end()))
            yield span


def _iter_unclosed_attributed_quote_spans(
    markdown: str,
    source_credit_names: tuple[str, ...],
    parsed_matches: list[Any],
):
    """Fail closed on malformed/mixed quote markers after source attribution."""
    offset = 0
    for part in re.split(r"(\n[ \t]*\n)", markdown):
        if re.fullmatch(r"\n[ \t]*\n", part):
            offset += len(part)
            continue
        if not part:
            continue
        for local_start, character in enumerate(part):
            if character not in {'"', "'", "“", "”", "‘", "’", "«", "»"}:
                continue
            if character in {"'", "’"}:
                previous = part[local_start - 1] if local_start else ""
                following = part[local_start + 1] if local_start + 1 < len(part) else ""
                if previous.isalnum() and following.isalnum():
                    continue
                next_word = re.match(
                    r"\s+(?:[*_`]{1,3})?([^\W\d_])",
                    part[local_start + 1 :],
                )
                if previous.casefold() == "s" and next_word is not None:
                    continue
            start = offset + local_start
            if any(match.start() <= start < match.end() for match in parsed_matches):
                continue
            quote_text = part[local_start + 1 :].strip().strip("\"'“”‘’«»")
            if _word_count(quote_text) < 1:
                continue
            span = _GroundingQuoteSpan(
                markdown[start : offset + len(part)],
                quote_text,
                start,
                offset + len(part),
            )
            if _has_quote_adjacent_source_attribution(
                markdown,
                span,
                source_credit_names,
            ):
                yield span
                break
        offset += len(part)


def _iter_attributed_quote_matches(
    markdown: str,
    source_credit_names: tuple[str, ...] = (),
):
    """Yield long quotes with direct source attribution, including hard wraps."""
    all_delimited_matches = list(_GROUNDING_QUOTE_RE.finditer(markdown))
    delimited_matches = [
        match
        for match in all_delimited_matches
        if _word_count(_grounding_quote_text(match).strip()) >= 1
    ]
    ambiguous_matches = list(_iter_ambiguous_quote_spans(markdown))
    for match in ambiguous_matches:
        if _has_quote_adjacent_source_attribution(
            markdown,
            match,
            source_credit_names,
        ):
            yield match

    for match in delimited_matches:
        if any(
            match.start() >= ambiguous.start() and match.end() <= ambiguous.end()
            for ambiguous in ambiguous_matches
        ):
            continue
        if _has_quote_adjacent_source_attribution(
            markdown,
            match,
            source_credit_names,
        ):
            yield match

    yield from _iter_blockquote_epigraph_spans(
        markdown,
        source_credit_names,
        delimited_matches,
    )
    yield from _iter_unclosed_attributed_quote_spans(
        markdown,
        source_credit_names,
        [*all_delimited_matches, *ambiguous_matches],
    )


def _year_context(value: str, start: int, end: int) -> str:
    """Return the local sentence/line around a specific year occurrence."""
    lower_bound = max(
        value.rfind("\n", 0, start),
        value.rfind(".", 0, start),
        value.rfind("!", 0, start),
        value.rfind("?", 0, start),
    )
    upper_candidates = [
        position
        for delimiter in ("\n", ".", "!", "?")
        if (position := value.find(delimiter, end)) >= 0
    ]
    upper_bound = min(upper_candidates) if upper_candidates else len(value)
    return value[lower_bound + 1 : upper_bound][:320].strip()


def _year_claim_is_supported(
    markdown: str,
    occurrence: re.Match[str],
    source_context: str,
) -> bool:
    """Require claim-level overlap, not just the same bare year elsewhere."""
    output_context = _year_context(markdown, occurrence.start(), occurrence.end())
    normalized_claim = _normalize_source_text(output_context).strip(" .!?")
    normalized_source = _normalize_source_text(source_context)
    if normalized_claim and normalized_claim in normalized_source:
        return True

    abbreviated = re.fullmatch(
        r"[’'](?P<digits>\d{2})(?P<decade>s?)", occurrence.group(0)
    )
    if abbreviated is None:
        full = re.fullmatch(
            r"(?P<century>[12]\d)(?P<digits>\d{2})(?P<decade>s?)",
            occurrence.group(0),
        )
        if full is None:
            return False
        source_abbreviations = re.finditer(
            rf"(?<!\w)[’']{full.group('digits')}{full.group('decade')}\b",
            source_context,
        )
        for source_abbreviation in source_abbreviations:
            expanded_source = (
                source_context[: source_abbreviation.start()]
                + occurrence.group(0)
                + source_context[source_abbreviation.end() :]
            )
            if normalized_claim in _normalize_source_text(expanded_source):
                return True
        return False
    # Resolve the century from an explicit full-year occurrence in the source
    # instead of assuming that `'83` means 1983. The surrounding claim still
    # has to match verbatim after that one conservative substitution.
    for full_year in re.findall(r"\b[12]\d{3}s?\b", source_context):
        full_is_decade = full_year.endswith("s")
        full_digits = full_year[:-1] if full_is_decade else full_year
        if full_digits[-2:] != abbreviated.group("digits") or full_is_decade != bool(
            abbreviated.group("decade")
        ):
            continue
        expanded_context = output_context.replace(occurrence.group(0), full_year, 1)
        expanded_claim = _normalize_source_text(expanded_context).strip(" .!?")
        if expanded_claim and expanded_claim in normalized_source:
            return True
    return False


def _unsupported_grounding_years(
    markdown: str,
    source_context: str | None,
) -> set[str]:
    source_text = source_context or ""
    return {
        occurrence.group(0)
        for occurrence in _GROUNDING_YEAR_RE.finditer(markdown)
        if not _year_claim_is_supported(markdown, occurrence, source_text)
    }


def _grounding_quote_is_supported(quote: str, normalized_source: str) -> bool:
    normalized_quote = _normalize_source_text(quote)
    if not normalized_quote:
        return False
    if _word_count(normalized_quote) >= 8:
        return normalized_quote in normalized_source
    # Short phrases are too collision-prone for substring matching. Require
    # explicit quotation punctuation in the supplied source material.
    return f'"{normalized_quote}"' in normalized_source


def _source_grounding_metrics(
    markdown: str,
    source_context: str | None,
    source_credit_names: tuple[str, ...] = (),
) -> dict[str, int]:
    """Detect high-risk quotes/dates absent from the available source context."""
    source_text = source_context or ""
    source = _normalize_source_text(source_text)
    attributed_quotes = [
        _grounding_quote_text(match).strip()
        for match in _iter_attributed_quote_matches(markdown, source_credit_names)
    ]

    unmatched_quotes = sum(
        1
        for quote in attributed_quotes
        if not _grounding_quote_is_supported(quote, source)
    )
    unmatched_years = len(_unsupported_grounding_years(markdown, source_text))
    return {
        "source_grounding_eligible": int(bool(source)),
        "attributed_quote_count": len(attributed_quotes),
        "unmatched_attributed_quote_count": unmatched_quotes,
        "unmatched_year_count": unmatched_years,
    }


def evaluate_book_module(
    data: dict[str, Any],
    *,
    source_context: str | None = None,
) -> ContentQualityReport:
    """Score a generated book module using user-visible, deterministic rules."""
    markdown = str(data.get("content_markdown") or "")
    sections = data.get("sections") if isinstance(data.get("sections"), list) else []
    ideas = data.get("ideas") if isinstance(data.get("ideas"), list) else []

    words = _word_count(markdown)
    heading_count = len(re.findall(r"^##\s+\S", markdown, flags=re.MULTILINE))
    practice_count = len(
        re.findall(
            r"^###\s+Practice This\s*$", markdown, flags=re.MULTILINE | re.IGNORECASE
        )
    )
    closing_synthesis_count = len(
        re.findall(
            r"^##\s+Closing Synthesis\s*$",
            markdown,
            flags=re.MULTILINE | re.IGNORECASE,
        )
    )
    filler_count = sum(markdown.lower().count(phrase) for phrase in _FILLER_PHRASES)
    duplicate_ratio = _duplicate_paragraph_ratio(markdown)
    near_duplicate_ratio = _near_duplicate_paragraph_ratio(markdown)
    (
        repeated_opening_count,
        repeated_opening_ratio,
        prose_sentence_count,
    ) = _repeated_sentence_opening_metrics(markdown)
    source_credit_values = [
        str(value)
        for value in (
            data.get("title"),
            data.get("author_or_creator"),
            data.get("author"),
        )
        if value
    ]
    # Editorial credits commonly use only an author's surname. Add that alias
    # only from author fields (never from a multi-word book title), and only
    # when the source identity itself contains at least two name tokens.
    for raw_author in (data.get("author_or_creator"), data.get("author")):
        if not raw_author:
            continue
        author_names: list[tuple[str, bool]] = []
        for entry in re.split(r"\s*;\s*|\s+(?:and|&)\s+", str(raw_author)):
            comma_parts = [part.strip() for part in entry.split(",") if part.strip()]
            first_part_words = (
                re.findall(r"[A-Za-z][\w'’.-]*", comma_parts[0]) if comma_parts else []
            )
            if len(comma_parts) == 2 and len(first_part_words) == 1:
                # Library metadata often stores one person as `Surname, Given`.
                author_names.append((comma_parts[0], True))
            elif len(comma_parts) > 1:
                author_names.extend((part, False) for part in comma_parts)
            else:
                author_names.append((entry, False))
        for author_name, surname_only in author_names:
            name_words = re.findall(r"[A-Za-z][\w'’.-]*", author_name)
            if not name_words:
                continue
            suffixes = {
                "jr",
                "sr",
                "ii",
                "iii",
                "iv",
                "esq",
                "md",
                "m.d",
                "phd",
                "ph.d",
            }
            while (
                len(name_words) >= 2
                and name_words[-1].strip(".").casefold() in suffixes
            ):
                name_words.pop()
            surname = name_words[-1].strip(".")
            if len(surname) >= 3 and (len(name_words) >= 2 or surname_only):
                source_credit_values.append(surname)
    source_credit_names = tuple(dict.fromkeys(source_credit_values))
    grounding = _source_grounding_metrics(
        markdown,
        source_context,
        source_credit_names,
    )
    thin_section_summaries = sum(
        1 for section in sections if _word_count(section.get("summary")) < 60
    )
    thin_section_exercises = sum(
        1 for section in sections if _word_count(section.get("exercise")) < 30
    )
    thin_ideas = sum(1 for idea in ideas if _word_count(idea.get("content")) < 35)

    issues: list[str] = []
    if words < MIN_BOOK_MODULE_WORDS:
        issues.append(
            f"content_markdown has {words} words; minimum is {MIN_BOOK_MODULE_WORDS}"
        )
    if words > MAX_BOOK_MODULE_WORDS:
        issues.append(
            f"content_markdown has {words} words; maximum is {MAX_BOOK_MODULE_WORDS}"
        )
    if len(sections) < 5:
        issues.append(f"sections has {len(sections)} items; minimum is 5")
    if len(sections) > 7:
        issues.append(f"sections has {len(sections)} items; maximum is 7")
    if len(ideas) < 6:
        issues.append(f"ideas has {len(ideas)} items; minimum is 6")
    if len(ideas) > 10:
        issues.append(f"ideas has {len(ideas)} items; maximum is 10")
    if thin_section_summaries:
        issues.append(f"{thin_section_summaries} section summaries are too thin")
    if thin_section_exercises:
        issues.append(f"{thin_section_exercises} section exercises are too thin")
    if thin_ideas:
        issues.append(f"{thin_ideas} idea cards are too thin")
    if practice_count != EXPECTED_BOOK_PRACTICE_COUNT:
        issues.append(
            f"content_markdown has {practice_count} Practice This blocks; "
            f"expected {EXPECTED_BOOK_PRACTICE_COUNT}"
        )
    if heading_count != EXPECTED_BOOK_HEADING_COUNT:
        issues.append(
            f"content_markdown has {heading_count} level-2 headings; "
            f"expected {EXPECTED_BOOK_HEADING_COUNT}"
        )
    if closing_synthesis_count != 1:
        issues.append(
            f"content_markdown has {closing_synthesis_count} Closing Synthesis headings; "
            "expected 1"
        )
    if filler_count:
        issues.append(
            f"content_markdown contains {filler_count} banned filler or canned phrases"
        )
    if duplicate_ratio > MAX_DUPLICATE_PARAGRAPH_RATIO:
        issues.append(
            f"content_markdown repeats too many substantial paragraphs "
            f"({duplicate_ratio:.0%} duplicate)"
        )
    if near_duplicate_ratio > MAX_NEAR_DUPLICATE_PARAGRAPH_RATIO:
        issues.append(
            "content_markdown repeats too many templated paragraph structures "
            f"({near_duplicate_ratio:.0%} near-duplicate)"
        )
    if (
        repeated_opening_count >= 4
        and repeated_opening_ratio > MAX_REPEATED_SENTENCE_OPENING_RATIO
    ):
        issues.append(
            "content_markdown overuses one sentence opening "
            f"({repeated_opening_count} of {prose_sentence_count} prose sentences)"
        )
    if grounding["unmatched_attributed_quote_count"]:
        issues.append(
            f"{grounding['unmatched_attributed_quote_count']} attributed quotation(s) "
            "were not found in the supplied source text"
        )
    if grounding["unmatched_year_count"]:
        issues.append(
            f"{grounding['unmatched_year_count']} dates were not found in the supplied source text"
        )

    score = 0.0
    score += min(words / MIN_BOOK_MODULE_WORDS, 1.0) * 0.35
    score += min(len(sections) / 5, 1.0) * 0.15
    score += min(len(ideas) / 6, 1.0) * 0.10
    score += min(practice_count / EXPECTED_BOOK_PRACTICE_COUNT, 1.0) * 0.15
    score += min(heading_count / EXPECTED_BOOK_HEADING_COUNT, 1.0) * 0.05
    score += 0.05 if filler_count == 0 else 0.0
    score += 0.05 if duplicate_ratio <= MAX_DUPLICATE_PARAGRAPH_RATIO else 0.0
    score += 0.05 if near_duplicate_ratio <= MAX_NEAR_DUPLICATE_PARAGRAPH_RATIO else 0.0
    score += (
        0.05
        if repeated_opening_count < 4
        or repeated_opening_ratio <= MAX_REPEATED_SENTENCE_OPENING_RATIO
        else 0.0
    )
    grounding_penalty = min(
        0.20,
        grounding["unmatched_attributed_quote_count"] * 0.12
        + grounding["unmatched_year_count"] * 0.04,
    )
    detail_penalty = min(
        0.15,
        (thin_section_summaries + thin_section_exercises + thin_ideas) * 0.01,
    )
    score = max(0.0, score - detail_penalty - grounding_penalty)

    hard_requirements_pass = (
        words >= MIN_BOOK_MODULE_WORDS
        and words <= MAX_BOOK_MODULE_WORDS
        and 5 <= len(sections) <= 7
        and 6 <= len(ideas) <= 10
        and practice_count == EXPECTED_BOOK_PRACTICE_COUNT
        and heading_count == EXPECTED_BOOK_HEADING_COUNT
        and closing_synthesis_count == 1
        and filler_count == 0
        and duplicate_ratio <= MAX_DUPLICATE_PARAGRAPH_RATIO
        and near_duplicate_ratio <= MAX_NEAR_DUPLICATE_PARAGRAPH_RATIO
        and (
            repeated_opening_count < 4
            or repeated_opening_ratio <= MAX_REPEATED_SENTENCE_OPENING_RATIO
        )
        and thin_section_summaries == 0
        and thin_section_exercises == 0
        and thin_ideas == 0
        and grounding["unmatched_attributed_quote_count"] == 0
        and grounding["unmatched_year_count"] == 0
    )
    return ContentQualityReport(
        passed=hard_requirements_pass and score >= 0.85,
        score=round(score, 3),
        issues=issues,
        metrics={
            "word_count": words,
            "section_count": len(sections),
            "idea_count": len(ideas),
            "heading_count": heading_count,
            "practice_block_count": practice_count,
            "closing_synthesis_count": closing_synthesis_count,
            "filler_phrase_count": filler_count,
            "duplicate_paragraph_ratio": round(duplicate_ratio, 3),
            "near_duplicate_paragraph_ratio": round(near_duplicate_ratio, 3),
            "repeated_sentence_opening_count": repeated_opening_count,
            "repeated_sentence_opening_ratio": round(repeated_opening_ratio, 3),
            "prose_sentence_count": prose_sentence_count,
            "thin_section_summary_count": thin_section_summaries,
            "thin_section_exercise_count": thin_section_exercises,
            "thin_idea_count": thin_ideas,
            **grounding,
        },
    )


def build_book_retry_instruction(report: ContentQualityReport) -> str:
    """Build a focused retry instruction instead of repeating generic guidance."""
    issue_lines = "\n".join(f"- {issue}" for issue in report.issues)
    return (
        "\n\nQUALITY RETRY: The previous draft failed these checks:\n"
        f"{issue_lines}\n"
        f"Rewrite the complete JSON module. Keep accurate material, but fix every listed issue. "
        f"Target {TARGET_BOOK_MODULE_WORDS}-{MAX_BOOK_MODULE_WORDS} words in content_markdown. "
        "Add substance through explanation, grounded examples, comparisons, and concrete practice; "
        "do not pad, repeat paragraphs, or invent facts. Preserve supported claims while varying "
        "paragraph structure and sentence openings, and remove canned labels or transitions."
    )
