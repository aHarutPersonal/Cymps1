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


@dataclass(frozen=True)
class ContentQualityReport:
    passed: bool
    score: float
    issues: list[str]
    metrics: dict[str, int | float]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


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
        tuple(words[index : index + width])
        for index in range(len(words) - width + 1)
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
    value = value.casefold().replace("’", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", value).strip()


def _source_grounding_metrics(markdown: str, source_context: str | None) -> dict[str, int]:
    """Detect high-risk quotes/dates absent from the available source context."""
    source_text = source_context or ""
    source = _normalize_source_text(source_text)
    attributed_quotes: list[str] = []
    for match in re.finditer(r"[\"“]([^\"”\n]{35,400})[\"”]", markdown):
        quote = match.group(1).strip()
        if _word_count(quote) < 8:
            continue
        nearby = markdown[max(0, match.start() - 120) : match.end() + 120].casefold()
        if re.search(
            r"\b(author|book|according|argues?|calls?|describes?|said|says|writes?|wrote)\b",
            nearby,
        ):
            attributed_quotes.append(quote)

    unmatched_quotes = sum(
        1
        for quote in attributed_quotes
        if _normalize_source_text(quote) not in source
    )
    output_years = set(re.findall(r"\b(?:1[5-9]\d{2}|20\d{2})\b", markdown))
    source_years = set(re.findall(r"\b(?:1[5-9]\d{2}|20\d{2})\b", source_text))
    unmatched_years = len(output_years - source_years)
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
        re.findall(r"^###\s+Practice This\s*$", markdown, flags=re.MULTILINE | re.IGNORECASE)
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
    grounding = _source_grounding_metrics(markdown, source_context)
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
    if grounding["unmatched_year_count"] >= 2:
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
    score += (
        0.05
        if near_duplicate_ratio <= MAX_NEAR_DUPLICATE_PARAGRAPH_RATIO
        else 0.0
    )
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
        and grounding["unmatched_year_count"] < 2
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
