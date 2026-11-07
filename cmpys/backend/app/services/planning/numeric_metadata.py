"""Occurrence-owned structural list metadata, never numerical fact evidence."""
from __future__ import annotations

import re
from collections.abc import Iterable


_MARKER = re.compile(r"\(([0-9]{1,3})\)|([0-9]{1,3})\)|([0-9]{1,3})․")
_TASK_LABEL = re.compile(
    r"\b(?P<label>Task|Step|Part|Question)[ \t]+(?P<index>[1-9]\d?)[ \t]*[:).]", re.I)
_NATURAL_QUOTED = re.compile(
    r'"(?:\\.|[^"\\])*"|“[^”]*”|«[^»]*»|‘(?:[^’]|(?<=\w)’(?=\w))*’|'
    r"(?<!\w)'(?:[^'\n]|(?<=\w)'(?=\w))*'(?!\w)")
_QUOTED = re.compile(
    r"```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]*`|" + _NATURAL_QUOTED.pattern)
_BOUNDARIES = frozenset(":,;։․՝.!?。！？")
# These are rejected item starts, not unit conversions or asserted facts.
# Case folding here only keeps a possible quantity visible for verification.
_QUANTITY_STARTS = frozenset({
    "cm", "mm", "m", "km", "kg", "mg", "g", "ml", "l", "s", "ms", "h",
    "usd", "eur", "amd", "gbp", "dollar", "dollars", "euro", "euros", "pound", "pounds",
    "percent", "percentage", "percentages",
    "metre", "metres", "meter", "meters", "centimetre", "centimetres", "centimeter", "centimeters",
    "millimetre", "millimetres", "millimeter", "millimeters", "gram", "grams", "kilogram", "kilograms",
    "milligram", "milligrams", "litre", "litres", "liter", "liters", "second", "seconds",
    "minute", "minutes", "hour", "hours",
    "million", "billion", "thousand", "hundred", "dozen", "half", "quarter",
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "of", "per", "times",
    "դրամ", "դոլար", "եվրո", "տոկոս", "տոկոսի", "միլիոն", "միլիարդ", "հազար",
    "հարյուր", "կես", "մեկ", "երկու", "երեք", "չորս", "հինգ", "վեց", "յոթ", "ութ", "ինը", "տասը",
    "մ", "սմ", "մմ", "կմ", "կգ", "գ", "լ", "մլ", "քմ", "քառ", "վրկ", "վայրկյան", "րոպե", "ժամ",
})


def _markdown_label_boundary(line: str) -> bool:
    """A complete standalone bold label may decorate existing punctuation.

    This is not general Markdown stripping. A line-local, nonnumeric label
    needs exactly one balanced ** pair and its own terminal list boundary.
    """
    match = re.fullmatch(r"[ \t]*\*\*([^*\r\n]+)\*\*[ \t]*", line)
    if match is None:
        return False
    label = match[1]
    first_word = re.match(r"[^\W\d_]+", label)
    if (label != label.strip() or first_word is None or len(first_word[0]) < 2
            or any(char.isdigit() for char in label)
            or re.search(r"[+\-−=×÷*/^%<>|`_\\]", label)):
        return False
    return label[-1] in _BOUNDARIES


def _at_list_boundary(source: str, start: int) -> bool:
    prefix = source[:start]
    if not prefix.strip() or (prefix and prefix[-1] in "\r\n"):
        return True
    # A new indented line is a boundary; spaces inside ordinary prose are not.
    line = prefix.rsplit("\n", 1)[-1]
    if not line.strip():
        return True
    trimmed = prefix.rstrip()
    if trimmed[-1] in ".․" and len(trimmed) > 1 and trimmed[-2].isdigit():
        return False  # Never interpret the tail of 0.1) as a list marker.
    return trimmed[-1] in _BOUNDARIES or _markdown_label_boundary(line)


def _ambiguous_paired_quotes(source: str) -> bool:
    """Flat quote matches cannot establish ownership for nested same-pair quotes."""
    closes = {"»": "«", "”": "“", "’": "‘"}
    stack = []
    for index, char in enumerate(source):
        if (char == "’" and 0 < index < len(source) - 1
                and source[index - 1].isalnum() and source[index + 1].isalnum()):
            continue  # A word-internal apostrophe is not a closing quotation.
        if char in closes.values():
            if char in stack:
                return True
            stack.append(char)
        elif char in closes:
            if not stack or stack.pop() != closes[char]:
                return True
    return bool(stack)


def quoted_or_unclosed_prefix(source: str, position: int) -> bool:
    """Keep reviewed introductions tied to the full field's quote ownership.

    Slicing at an inner verb must not discard an opening quote or code fence.
    Complete quoted regions are recognized first; an unmatched opening before
    this position is ambiguous. Word-internal apostrophes are not openings.
    """
    intervals = [match.span() for match in _QUOTED.finditer(source)]
    if any(lower <= position < upper for lower, upper in intervals):
        return True
    prefix = list(source[:position])
    for lower, upper in intervals:
        if upper <= position:
            prefix[lower:upper] = " " * (upper - lower)
    return re.search(r'"|(?<!\w)\'|`|~{3}|[“‘«]', "".join(prefix)) is not None


def _meaningful_item_start(source: str, end: int, item_end: int, units: tuple[str, ...],
                           *, reviewed_articles: bool = False) -> bool:
    suffix = source[end:item_end]
    if not suffix or not suffix[0].isspace():
        return False
    text = suffix.lstrip()
    quote = _NATURAL_QUOTED.match(text)
    if quote is not None:
        # The marker is outside the quote. Inspect its complete natural-language
        # item start with the same quantity guards; never alter quoted content.
        text = quote[0][1:-1].lstrip()
    if reviewed_articles:
        # An independently assigned ordinal may precede "a short note".
        # Validate the following word with the same quantity/formula guards;
        # a lone algebraic variable, "a cm", or "a 20-dollar fee" is not proof.
        text = re.sub(r"^a[ \t]+", "", text, count=1, flags=re.I)
    word = re.match(r"[^\W\d_]+", text)
    if word is None or len(word[0]) < 2 or word[0].casefold() in _QUANTITY_STARTS:
        return False
    for unit in units:
        # A multiword/compound declared unit is equally a possible amount.
        if re.match(re.escape(unit).replace(r"\ ", r"\s+") + r"(?!\w)", text, re.I):
            return False
    return True


def structural_ordinal_intervals(source: str, units: Iterable[str] = (),
                                 *, reviewed_articles: bool = False) -> list[tuple[int, int]]:
    """Recognize one complete consistent 1..N list within this source field.

    ``(1)``, ``1)`` and Armenian ``1․`` are supported, but mixing forms, gaps, repeated
    values, quoted examples, bare units or formula-like items is ambiguous.
    Only marker bytes are returned; all item content remains unverified data.
    The caller must never concatenate separate fields to establish a sequence.
    """
    if (not isinstance(source, str) or not (_MARKER.search(source) or _TASK_LABEL.search(source))
            or _ambiguous_paired_quotes(source)):
        return []
    # Numbered markers and a "Task|Step|Part|Question 1..N" label sequence are
    # independent structures; each must be complete within this field.
    return sorted(_numbered_marker_intervals(source, units, reviewed_articles=reviewed_articles)
                  + _task_label_intervals(source, units, reviewed_articles=reviewed_articles))


def _task_label_intervals(source: str, units: Iterable[str] = (),
                          *, reviewed_articles: bool = False) -> list[tuple[int, int]]:
    """A complete in-order ``Task 1: ... Task 2: ...`` instruction sequence.

    Only the ordinal digits are returned, and only for one label word whose
    occurrences at list/sentence boundaries are exactly 1..N, each followed by
    ``:``, ``)`` or ``.`` and a non-quantity item start. A lone ``Task 3``,
    ``Step 2 costs $40``, quoted labels and item content stay numeric claims.
    """
    if not _TASK_LABEL.search(source):
        return []
    unit_values = (units,) if isinstance(units, str) else units
    normalized_units = tuple(" ".join(unit.split()) for unit in unit_values
                             if isinstance(unit, str) and unit.strip())
    by_label: dict[str, list[re.Match]] = {}
    for match in _TASK_LABEL.finditer(source):
        if _at_list_boundary(source, match.start()) and not quoted_or_unclosed_prefix(source, match.start()):
            by_label.setdefault(match["label"].casefold(), []).append(match)
    ranges: list[tuple[int, int]] = []
    for matches in by_label.values():
        if (len(matches) >= 2 and [int(m["index"]) for m in matches] == list(range(1, len(matches) + 1))
                and all(_meaningful_item_start(
                            source, match.end(),
                            matches[i + 1].start() if i + 1 < len(matches) else len(source),
                            normalized_units, reviewed_articles=reviewed_articles)
                        for i, match in enumerate(matches))):
            ranges.extend(match.span("index") for match in matches)
    return ranges


def _numbered_marker_intervals(source: str, units: Iterable[str] = (),
                               *, reviewed_articles: bool = False) -> list[tuple[int, int]]:
    if not _MARKER.search(source):
        return []
    unit_values = (units,) if isinstance(units, str) else units
    normalized_units = tuple(" ".join(unit.split()) for unit in unit_values
                             if isinstance(unit, str) and unit.strip())
    quoted = [match.span() for match in _QUOTED.finditer(source)]
    markers = [match for match in _MARKER.finditer(source)
               if _at_list_boundary(source, match.start())
               and not any(start <= match.start() < end for start, end in quoted)]
    if (len(markers) < 2 or len({match.lastindex for match in markers}) != 1
            or [int(match[match.lastindex]) for match in markers] != list(range(1, len(markers) + 1))
            or any(not _meaningful_item_start(source, match.end(),
                       markers[index + 1].start() if index + 1 < len(markers) else len(source),
                       normalized_units, reviewed_articles=reviewed_articles)
                   for index, match in enumerate(markers))):
        return []
    return [match.span() for match in markers]


def mask_structural_ordinals(
    span: str, *, source: str, start: int, units: Iterable[str] = (),
) -> str:
    """Blank only proven markers in an exact owning source slice.

    Length, offsets, raw source and all nonmarker characters stay unchanged.
    A mismatched/partial occurrence is left untouched rather than guessed.
    """
    if (not isinstance(span, str) or not isinstance(source, str) or type(start) is not int
            or start < 0 or source[start:start + len(span)] != span):
        return span
    characters = list(span)
    end = start + len(span)
    for lower, upper in structural_ordinal_intervals(source, units):
        if start <= lower and upper <= end:
            characters[lower - start:upper - start] = " " * (upper - lower)
    return "".join(characters)


def reviewed_sentence_reference_intervals(source: str, units=()) -> list[tuple[int, int]]:
    """Ordinal references in instructional prose, only after independent review.

    Keep quoted prose, attached units, decimals and every surrounding quantity
    intact. This never removes claims from the reviewer's original inventory.
    """
    ranges = []
    number = r"[1-9]\d?"
    reference = r"(?:\(" + number + r"\)|" + number + r")"
    separator = r"(?:,[ \t]*(?:(?:and|or)[ \t]+)?|[ \t]+(?:and|or)[ \t]+)"
    pattern = (r"\b(?:(?:sentence|criterion)[ \t]+(?P<single>" + reference + r")|"
               r"(?:sentences|criteria)[ \t]+(?P<plural>" + reference
               + r"(?:" + separator + reference + r"){1,19}))"
               r"(?!\w|\.\d|[ \t]*[-−+*/×÷=%])")
    for match in re.finditer(pattern, source, re.I):
        if quoted_or_unclosed_prefix(source, match.start()):
            continue
        suffix = source[match.end():].lstrip()
        # A malformed or overlong list cannot license just its valid prefix.
        if re.match(r"(?:,[ \t]*(?:(?:and|or)[ \t]+)?|(?:and|or)[ \t]+)\(?\d", suffix, re.I):
            continue
        word = re.match(r"[^\W\d_]+", suffix)
        if word and word[0].casefold() in _QUANTITY_STARTS | {"day", "days", "month", "months", "year", "years"}:
            continue
        if any(re.match(re.escape(unit) + r"(?!\w)", suffix, re.I) for unit in units if unit):
            continue
        group = "plural" if match["plural"] is not None else "single"
        offset = match.start(group)
        ranges.extend((offset + digit.start(), offset + digit.end())
                      for digit in re.finditer(number, match[group]))
    return ranges


def _reviewed_revision_pass_intervals(source: str) -> list[tuple[int, int]]:
    """Recognize a complete Pass 1..N instruction sequence, never its contents."""
    pattern = re.compile(r"\bPass[ \t]+(?P<index>[1-9]\d?)[ \t]*[:—–](?=[ \t]+\S)", re.I)
    matches = list(pattern.finditer(source))
    if (len(matches) < 2 or [int(m["index"]) for m in matches] != list(range(1, len(matches) + 1))):
        return []
    quotes = list(_NATURAL_QUOTED.finditer(source))
    for i, match in enumerate(matches):
        # A worked passage can end just before its first revision label.
        # Require the complete owning quotation and terminal punctuation;
        # an unmatched quote, inline code or a quoted label stays unmasked.
        boundary = _at_list_boundary(source, match.start()) or any(
            quote.end() <= match.start() and not source[quote.end():match.start()].strip()
            and quote[0][-2:-1] in {".", "!", "?", "։", "․"}
            for quote in quotes)
        if (not boundary or quoted_or_unclosed_prefix(source, match.start())
                or not _meaningful_item_start(source, match.end(),
                    matches[i + 1].start() if i + 1 < len(matches) else len(source),
                    (), reviewed_articles=True)):
            return []
    return [match.span("index") for match in matches]


def reviewed_labeled_ordinal_intervals(source: str) -> list[tuple[int, int]]:
    """Complete same-field instructional labels, only after independent review.

    Return only the ordinal digits. Every number in the following text remains
    a claim; ordinary quoted passages and incomplete lists stay unmasked.
    """
    # A complete quoted model response may discuss its own ordered action
    # labels. Require the explicit model introduction, balanced owning quote,
    # noun/verb syntax and a complete sequence. Ordinary quoted case numbers
    # and all quantities within the model remain untouched.
    model_ranges = _reviewed_revision_pass_intervals(source)
    for introduction in re.finditer(r"\bModel:\s*", source, re.I):
        if (not _at_list_boundary(source, introduction.start())
                or quoted_or_unclosed_prefix(source, introduction.start())):
            continue
        quote = _NATURAL_QUOTED.match(source, introduction.end())
        if quote:
            references = list(re.finditer(
                r"\bBeat[ \t]+(?P<index>[1-9]\d?)[ \t]+"
                r"(?=is\b|was\b|shows?\b|carries\b|named\b|reveals?\b|implies\b)",
                quote[0], re.I))
            if (len(references) >= 2 and [int(m['index']) for m in references]
                    == list(range(1, len(references) + 1))):
                model_ranges.extend((quote.start() + m.start('index'), quote.start() + m.end('index'))
                                    for m in references)
    pattern = re.compile(
        r"^[ \t]*(?:[-*•][ \t]+)?(?P<label>physical detail|detail|example|point|step)"
        r"[ \t]+(?P<index>[1-9]\d?)(?:[:։])[ \t]+(?=\S)", re.I | re.M)
    matches = list(pattern.finditer(source))
    # Action-beat labels can follow a prose introduction and use a dash.
    # Match the whole ordered sequence in its owning field, never the bare
    # word "beat" followed by a number (which could be a measured quantity).
    beat_pattern = re.compile(
        r"\b(?P<label>beat)[ \t]+(?P<index>[1-9]\d?)[ \t]*[—–:](?=[ \t]+\S)", re.I)
    beats = list(beat_pattern.finditer(source))
    if any(not _at_list_boundary(source, m.start()) or not _meaningful_item_start(
            source, m.end(), beats[i + 1].start() if i + 1 < len(beats) else len(source),
            (), reviewed_articles=True) for i, m in enumerate(beats)):
        return model_ranges
    matches = sorted(matches + beats, key=lambda m: m.start())
    if (len(matches) < 2 or len({m["label"].casefold() for m in matches}) != 1
            or [int(m["index"]) for m in matches] != list(range(1, len(matches) + 1))
            or any(quoted_or_unclosed_prefix(source, m.start()) for m in matches)):
        return model_ranges
    return sorted([m.span("index") for m in matches] + model_ranges)


# Numerals that name something rather than state a quantity. Only the digits
# are returned; every other number in the same sentence stays a claim.
_IDENTIFIER_NUMERAL = re.compile(r"(?<![\w.-])[A-Za-z]{2,}(?:-[A-Za-z]{2,})*-(?P<digits>\d{1,6})(?!\w|[.,]\d|-\w)")
# "cm^2", "m^3" and "a^2 + b^2": an exponent right after a letter belongs to a
# unit or a symbol, exactly like "cm²" (pilot 2026-11-06 re-run).
_LETTER_EXPONENT = re.compile(r"(?<=[^\W\d_]\^)(?P<digits>[23])(?!\d|[.,]\d)")
# "Place 2 copies side by side", "its 3 sides": a small count of a generic, structural
# thing needs no proof (owner decision 2026-11-06: check only numbers that need
# clarification, such as results and case facts). Only this closed list qualifies;
# counts of the case's own people or items ("12 riders joined") stay claims, and so does
# a listed noun a datum label names or a count equal to a datum value.
_SMALL_COUNT = re.compile(r"(?<![\w.,^\u2212-])(?P<digits>[2-9]|1[0-2])[ \t\u00a0]+(?P<noun>[^\W\d_]{3,})\b")
_STRUCTURAL_NOUNS = frozenset({
    "copies", "sides", "angles", "corners", "vertices", "edges", "faces", "halves", "parts",
    "pieces", "steps", "options", "choices", "ways", "examples", "phases", "columns", "rows",
})
_CITATION_NUMERAL = re.compile(r"\b(?:IAS|IFRS|ISO|RFC|PEP|IEEE)[ \t\u00a0]?(?P<digits>\d{1,6})(?!\w|[.,]\d)")
_ORDINAL_LABEL = re.compile(
    r"\b(?:Reason|Gap|Step|Option|Interpretation|Part)[ \t]+(?P<digits>[1-9]\d?)"
    r"(?![\w.,]\d|\w|[ \t]*(?:[-−+*/×÷=%]|percent\b))", re.I)
# "Sentence N" is not listed: sentence references keep their inventory ID
# and are exempted only after independent review (reviewed_sentence_reference_intervals).
_LABEL_BOUNDARY = frozenset(".!?:;։\"“”‘’'(*•-–—\n")
# A standard angle constant needs its own geometric context in the sentence:
# 90 for a right angle, 180 for a straight angle, 360 for a full turn.
_ANGLE_CONSTANT = re.compile(r"(?<![\w.,])(?P<digits>90|180|360)(?:[ \t]*°|[ \t]*-?[ \t]*degrees?\b|[ \t]+աստիճան\w*)", re.I)
_ANGLE_CONTEXT = {
    "90": re.compile(r"right[ -]angle|perpendicular|ուղիղ\s+անկյուն|ուղղահայաց", re.I),
    # A half-turn ("rotated 180°", "one turned 180 degrees", "180° պտտված") is the same constant
    # (pilot 2026-11-06 audit and geometry round 3).
    "180": re.compile(r"straight\s+(?:angle|line)|փռված\s+անկյուն|ուղիղ\s+գիծ|half[ -]turn|rotat\w*|turn(?:ed|s|ing)?\b|"
                      r"պտտ\w*|պտույտ", re.I),
    "360": re.compile(r"full\s+(?:turn|rotation|circle)|around\s+a\s+point|լրիվ\s+պտույտ", re.I),
}
_LABEL_NUMBER = re.compile(r"(?<![\w.,])(\d+(?:\.\d+)?)[ \t ]+([^\W\d_]+)")


def _at_label_boundary(source: str, start: int) -> bool:
    prefix = source[:start].rstrip(" \t")
    return not prefix or prefix[-1] in _LABEL_BOUNDARY


def incidental_numeral_intervals(source: str, labels: Iterable[str] = (),
                                 values: Iterable[float] = ()) -> list[tuple[int, int]]:
    """Digits that identify, enumerate or define rather than state a quantity.

    - identifiers and citations: ``INV-42``, ``badge-req-7``, ``IAS 1``;
    - an exponent 2 or 3 right after a letter: ``cm^2``, ``a^2 + b^2``;
    - a small count (2–12) of a generic, structural thing: ``2 copies``, ``4 sides``;
    - ordinal labels at a line, sentence or quote start: ``Reason 1:``,
      ``Option 3 mislabels it`` (never a following quantity: ``Option 2 gives 41``
      keeps 41);
    - 90/180/360 as a degree constant beside right-angle, straight-angle or
      full-turn wording; any other angle stays a claim;
    - a number followed by the same word as inside one of the owning case's
      datum ``labels`` ("waiting more than 20 minutes"), unless it equals one
      of that case's datum ``values``.
    Quoted or not, these spans are still reviewed as prose.
    """
    if not isinstance(source, str) or not re.search(r"\d", source):
        return []
    ranges = [match.span("digits") for match in _IDENTIFIER_NUMERAL.finditer(source)]
    ranges += [match.span("digits") for match in _CITATION_NUMERAL.finditer(source)]
    ranges += [match.span("digits") for match in _LETTER_EXPONENT.finditer(source)]
    ranges += [match.span("digits") for match in _ORDINAL_LABEL.finditer(source)
               if _at_label_boundary(source, match.start())]
    for match in _ANGLE_CONSTANT.finditer(source):
        sentence_start = max(source.rfind(mark, 0, match.start()) for mark in (".", "!", "?", "։", "\n")) + 1
        sentence_end = min([index for index in (source.find(mark, match.end()) for mark in (". ", "!", "?", "։", "\n"))
                            if index != -1] or [len(source)])
        if _ANGLE_CONTEXT[match["digits"]].search(source[sentence_start:sentence_end]):
            ranges.append(match.span("digits"))
    known = set()
    for value in values:
        try:
            known.add(float(value))
        except (TypeError, ValueError):
            continue
    label_words = set()
    for label in labels:
        for word in re.findall(r"[^\W\d_]+", label) if isinstance(label, str) else ():
            label_words.update({word.casefold(), word.casefold().removesuffix("s")})
    for match in _SMALL_COUNT.finditer(source):
        noun = match["noun"].casefold()
        if (noun in _STRUCTURAL_NOUNS and {noun, noun.removesuffix("s")}.isdisjoint(label_words)
                and float(match["digits"]) not in known):
            ranges.append(match.span("digits"))
    phrases = {(number, word.casefold()) for label in labels if isinstance(label, str)
               for number, word in _LABEL_NUMBER.findall(label) if float(number) not in known}
    if phrases:
        for match in _LABEL_NUMBER.finditer(source):
            if (match[1], match[2].casefold()) in phrases:
                ranges.append(match.span(1))
    return sorted(set(ranges))


def references_section_interval(markdown: str) -> tuple[int, int] | None:
    """The body of a lesson's ``## References`` section: citations, not claims."""
    if not isinstance(markdown, str):
        return None
    heading = re.search(r"^## References[ \t]*$", markdown, re.M)
    if heading is None:
        return None
    following = re.search(r"^## ", markdown[heading.end():], re.M)
    return heading.end(), heading.end() + following.start() if following else len(markdown)


_ATTEMPT_INTRODUCTION = re.compile(
    r"\b(?:diagnostic|flawed|sample|student|draft)\s+(?:attempt|answer|response)\s+(?:says|reads|states)\s*:?\s*", re.I)
_QUOTED_NUMBER = re.compile(r"(?<![\w.])\d{1,3}(?:,\d{3})+(?:\.\d+)?|(?<![\w.,])\d+(?:\.\d+)?")


def quoted_attempt_intervals(source: str, verified_text: str, values: Iterable[float] = (),
                             exempt: Iterable[tuple[int, int]] = ()) -> list[tuple[int, int]]:
    """Numbers inside a quoted attempt the learner must diagnose ("A diagnostic attempt says: “...”").

    The attempt is deliberately wrong, so its claims cannot be bound as facts.
    Its digits are exempt only when EVERY number in the quotation is a datum
    value or also appears in ``verified_text`` (the activity's worked
    solution, whose numbers stay fully checked): the quote can then show no
    number the learner does not also meet in checked content. Digits inside
    ``exempt`` intervals (ordinal labels such as "Reason 1") are not numbers.
    """
    exempt = set(exempt)
    if not isinstance(source, str) or not isinstance(verified_text, str):
        return []
    known = set()
    for value in values:
        try:
            known.add(float(value))
        except (TypeError, ValueError):
            continue
    shown = {float(match[0].replace(",", "")) for match in _QUOTED_NUMBER.finditer(verified_text)}
    ranges = []
    for introduction in _ATTEMPT_INTRODUCTION.finditer(source):
        quote = _NATURAL_QUOTED.match(source, introduction.end())
        if quote is None:
            continue
        numbers = [match for match in _QUOTED_NUMBER.finditer(quote[0])
                   if (quote.start() + match.start(), quote.start() + match.end()) not in exempt]
        if numbers and all(float(match[0].replace(",", "")) in known | shown for match in numbers):
            ranges.extend((quote.start() + match.start(), quote.start() + match.end()) for match in numbers)
    return ranges


# ---------------------------------------------------------------------------
# The shared numeral policy (Phase 0.2, 2026-11-04).
#
# One decision, used by every gate that asks "does this number need declaring
# or binding?": the seed gate, the activity gate (require_declared_numbers),
# the span extractor (lesson_review) and the evidence binder. A numeral is a
# QUANTITY unless one explicit pattern below shows that it names, dates,
# times, labels or versions something. Counts, money, measurements,
# percentages, durations and every operand or result stay quantities. A
# capitalised word alone never makes a number an identifier: only the closed
# noun lists below do ("Revenue 400" is a quantity, "Route 14" is not).
# ---------------------------------------------------------------------------

# The numeral tokenizer every gate shares (lesson_review re-exports these).
# Thousands separators are one horizontal grouping character followed by
# exactly three digits. Never consume general whitespace: newlines/tabs may
# separate list values, and operators/signs/decimal points remain boundaries.
_INTEGER_LITERAL = r"(?:\d{1,3}(?:,\d{3})+|[1-9]\d{0,2}(?:[   ]\d{3})+|\d+)"
_NUMBER_LITERAL = re.compile(
    r"(?<![\w.])[-+−]?" + _INTEGER_LITERAL + r"(?:\.\d+)?"
    r"(?!\.\d|,\d)(?:(?!\w)|(?=(?:x|k|m|b|kg|mg|g|cm|mm|km|ms|s|h|min|hrs|usd|eur|gbp)\b))", re.I)
# Unknown attached unit/word suffixes must keep their quantity in the
# inventory/residual coverage. They do NOT establish a source literal for a
# calculation; only an exact declared result unit can do that.
_ATTACHED_NUMERIC_LITERAL = re.compile(
    r"(?<![\w.])([-+−]?" + _INTEGER_LITERAL + r"(?:\.\d+)?)(?!\.\d|,\d)"
    r"(?=[^\W\d_]|[²³])")

# Words that turn a following number into an amount: "Step 3 of 5", "option
# 3 times", "line 2 cm", "order 40 units". A labelled number followed by one
# of these stays a quantity.
_AMOUNT_WORDS = _QUANTITY_STARTS | frozenset({
    "x", "units", "unit", "items", "pieces", "copies", "boxes", "packs", "bags", "bottles", "cups",
    "credits", "credit", "cents", "cent", "coins", "points", "marks", "votes",
    "km²", "m²", "cm²", "sq", "square", "cubic", "degree", "degrees", "°", "more", "fewer", "less",
    "extra", "additional", "out",
})
# After a verb-like noun these make the number a count ("train 40 staff").
_COUNT_NOUNS = frozenset({
    "people", "persons", "staff", "guests", "riders", "students", "pupils", "members", "customers",
    "orders", "jobs", "messages", "rows", "questions", "paragraphs", "essays", "books", "pages",
    "tickets", "invoices", "requests", "times", "users", "clients", "workers",
})
# Label nouns: the number after one is an ordinal or list label ("Paragraph 1:",
# "Reading 2", "Line 2: Sales", "Option 3", "Step 2"). "Sentence" and
# "criterion" are deliberately absent: sentence references keep their
# inventory ID and are exempted only after independent review.
_LABEL_NOUNS = (
    "paragraph", "line", "option", "step", "item", "part", "section", "chapter", "task", "reason",
    "gap", "interpretation", "revision", "version", "delivery", "phase", "stage", "example", "row",
    "column", "entry", "figure", "table", "exercise", "activity", "lesson", "scenario", "clause",
    "rule", "article", "page", "slide", "tier", "level", "case", "trial", "premise", "module",
    "evidence", "source", "document", "exhibit", "note", "excerpt", "passage", "extract", "scene", "episode",
    "mistake", "misconception",
)
# Identifier nouns: the number after one names a thing ("order 418", "Route 14",
# "Room 3B", "customer 418", "message 881").
_IDENTIFIER_NOUNS = (
    "room", "floor", "building", "district", "ward", "zone", "sector", "bay", "aisle", "lane",
    "platform", "gate", "flight", "tram", "terminal", "hall", "desk", "exit", "highway", "station",
    "ticket", "receipt", "account", "customer", "client", "member", "patient", "shipment", "parcel",
    "job", "signup", "worker", "server", "node", "transaction", "class", "year", "sku", "route", "bus",
    "lot",
)
# Nouns that are also common verbs or gerunds ("order 40 units", "attempt 3
# questions", "claim 300 credits", "reading 3 books"): only after a determiner
# or preposition ("for order 418"), with an initial capital inside a sentence,
# or before a label colon ("Attempt 1:").
_VERB_LIKE_NOUNS = (
    "order", "invoice", "train", "seat", "plot", "batch", "message", "request",
    "attempt", "draft", "reading", "question", "claim", "grade", "run",
)
# "Detail 1:", "Beat 1 —", "Pass 1:" and "Sentence 1" are absent on purpose:
# they become metadata only after independent review
# (reviewed_labeled_ordinal_intervals, reviewed_sentence_reference_intervals).
# Time nouns are labels only when not counting a period ("each week 40 people"):
# capitalised ("Week 2") or after a preposition ("on day 5", "in week 2").
_TIME_NOUNS = ("day", "week", "month", "quarter", "term", "semester", "period", "session", "hour", "minute")
_ARMENIAN_LABEL_NOUNS = (
    "քայլ", "փուլ", "հարց", "վարժություն", "դաս", "դաշտ", "կետ", "տող", "պարբերություն",
    "տարբերակ", "մաս", "բաժին", "գլուխ", "երթուղի", "սենյակ", "դասարան", "սխալ",
)
_DETERMINER = re.compile(
    r"(?:^|[^\w])(?:the|this|that|for|of|on|in|into|to|from|with|by|at|after|before|during|under|"
    r"about|see|via|than|your|our|their|its|his|her|my)[ \t]+$", re.I)
_TIME_PREPOSITION = re.compile(r"(?:^|[^\w])(?:on|by|in|of|from|until|till|before|after|during|since|for|the|this|that)[ \t]+$", re.I)
_COUNTING_PREFIX = re.compile(r"(?:^|[^\w])(?:every|each|per|a|an|one|any|some)[ \t]+$", re.I)
_SENTENCE_START = frozenset(".!?։\n:;\"“”‘’'(*•-–—")
_NAMED_NUMBER = r"\d{1,6}[A-Z]?"
_LIST_SEPARATOR = r"(?:[ \t]*,[ \t]*(?:(?:and|or)[ \t]+)?|[ \t]+(?:and|or|to|through)[ \t]+|[ \t]*[-–—][ \t]*)"


def _noun_alternation(nouns: Iterable[str], plural: bool) -> str:
    forms = []
    for noun in nouns:
        forms.append(re.escape(noun))
        if plural:
            forms.append(re.escape(noun[:-1] + "ies" if noun.endswith("y") and noun[-2:] != "ay" else
                                   noun + "es" if noun.endswith(("s", "x", "ch", "sh")) else noun + "s"))
    return "|".join(sorted(forms, key=len, reverse=True))


_NAMED_NUMERAL = re.compile(
    r"(?<![\w-])(?P<noun>" + _noun_alternation(
        _LABEL_NOUNS + _IDENTIFIER_NOUNS + _VERB_LIKE_NOUNS + _TIME_NOUNS, plural=True)
    + "|" + "|".join(_ARMENIAN_LABEL_NOUNS) + r")"
    r"(?P<joint>[ \t]+(?:numbers?|no\.?|#)[ \t]*|[ \t]*[:#][ \t]*|[ \t]+)"
    r"(?P<numbers>" + _NAMED_NUMBER + r"(?:" + _LIST_SEPARATOR + _NAMED_NUMBER + r"){0,11})"
    r"(?![\w%‰°]|[.,]\d)", re.I)
# "the number 9 bus", "No. 9 bus": a bare number word needs a following identifier noun.
_NUMBER_WORD_IDENTIFIER = re.compile(
    r"\b(?:number|no\.)[ \t]*(?P<digits>\d{1,6})[ \t]+(?:bus|buses|route|line|tram|train|platform|gate|"
    r"room|flight|stop|road|street)\b", re.I)
_VERSION = re.compile(r"(?<![\w.])(?:version|release|v)[ \t]*(?P<number>\d+(?:\.\d+){1,3})(?![\w]|[.,]\d)", re.I)
# A short code after an identifier noun: "message m-17", "job j-902".
_NOUN_CODE = re.compile(
    r"\b(?:message|job|request|order|invoice|batch|shipment|signup|ticket|run|worker|record|"
    r"transaction|account|customer|receipt|parcel|item)[ \t]+(?P<code>[A-Za-z]{1,3}[-_]\d{1,8}[A-Za-z]?)(?![\w-]|[.,]\d)", re.I)
_HASH_IDENTIFIER = re.compile(r"(?<![\w&#])#(?P<digits>\d{1,8})(?![\w.,]\d|\w)")
# A record key whose name says it holds an identifier: "order_ref: 88", "job_id: 42".
_ID_KEY = re.compile(
    r"\b(?:(?:[a-z][a-z0-9]*_)*(?:id|ref|no|num|number|code|key|ref_no)\b[ \t]*[:=][ \t]*"
    r"|(?:[a-z][a-z0-9]*_)+(?:id|ref|no|num|number|code)[ \t]+)"
    r"[\"'“‘]?(?P<value>[A-Za-z0-9][A-Za-z0-9_-]{0,30})(?![.,]\d)", re.I)
# Letter-led codes joined by - or _: "S-204", "k-77-a", "r-ord-88",
# "invoice-42-reminder-1", "KB-12". A lone lowercase letter ("x-2") is algebra.
_CODE = re.compile(
    r"(?<![\w.\-])(?P<code>[A-Za-z][A-Za-z0-9]*(?:[-_](?:[A-Za-z][A-Za-z0-9]*|\d+[A-Z]?))+)(?![\w\-]|[.,]\d)")
_MONTHS = (r"January|February|March|April|May|June|July|August|September|October|November|December|"
           r"Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec")
_ARMENIAN_MONTHS = (r"հունվար|փետրվար|մարտ|ապրիլ|մայիս|հունիս|հուլիս|օգոստոս|սեպտեմբեր|"
                    r"հոկտեմբեր|նոյեմբեր|դեկտեմբեր")
_DAY = r"(?:3[01]|[12]\d|0?[1-9])(?:st|nd|rd|th)?"
_YEAR = r"(?:1[89]\d\d|2[01]\d\d)"
_MONTH_NAME = r"(?:(?-i:" + _MONTHS + r")\.?|(?:" + _ARMENIAN_MONTHS + r")[^\W\d_]*)"
# Month-first: "April 5", "March 10 to March 14", "March 10–14", "April 5, 2026".
_MONTH_DAY = re.compile(
    r"(?<![\w])" + _MONTH_NAME + r"[ \t]+(?P<day>" + _DAY + r")(?P<rest>"
    r"(?:[ \t]*(?:[-–—]|to|through|until|and)[ \t]*(?:" + _MONTH_NAME + r"[ \t]+)?" + _DAY + r")?"
    r"(?:,?[ \t]+" + _YEAR + r")?)(?![\w]|[.,]\d|[ \t]*[%‰°])", re.I)
# Day-first: "5 April", "13 June", "10–14 March", "5th of April 2026", "մարտի 10".
_DAY_MONTH = re.compile(
    r"(?<![\w.,])(?P<days>" + _DAY + r"(?:[ \t]*(?:[-–—]|to|and)[ \t]*" + _DAY + r")?)"
    r"[ \t]+(?:of[ \t]+)?" + _MONTH_NAME + r"(?P<rest>(?:,?[ \t]+" + _YEAR + r")?)(?![\w])", re.I)
_MONTH_YEAR = re.compile(r"(?<![\w])" + _MONTH_NAME + r",?[ \t]+(?P<year>" + _YEAR + r")(?![\w]|[.,]\d)", re.I)
_NUMERIC_DATE = re.compile(
    r"(?<![\w.,/-])(?:" + _YEAR + r"-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])"
    r"|(?:0?[1-9]|[12]\d|3[01])[/.](?:0?[1-9]|1[0-2])[/.]" + _YEAR + r")(?![\w/-]|[.,]\d)")
# A year after an explicit time preposition, ending its clause: "in 2025,", "by 2030.".
_PLAIN_YEAR = re.compile(r"\b(?:in|since|during|until|by|before|after)[ \t]+(?P<year>" + _YEAR + r")(?=[ \t]*(?:[,.;:!?)\]]|$))", re.I)
# A trailing label colon still ends a time ("- Monday 08:00: step 3 ..."); "08:00:1" does not.
_CLOCK = re.compile(r"(?<![\w.:,])(?:[01]?\d|2[0-3]):[0-5]\d(?::[0-5]\d)?(?!\d|[.,:]\d)")
_MERIDIEM = re.compile(r"(?<![\w.,:])(?:1[0-2]|0?[1-9])(?::[0-5]\d)?[ \t]*(?:a\.?m\.?|p\.?m\.?)(?!\w)", re.I)
_RATIO_CONTEXT = re.compile(r"\b(?:ratio|odds|scale|proportion|scores?|scoreboard|mix|aspect)\b", re.I)
_ORDINAL_SUFFIX = re.compile(r"(?<![\w.,])(?P<digits>\d{1,3})(?:st|nd|rd|th)(?!\w)", re.I)
_FRACTION_PREFIX = re.compile(r"(?:^|[^\w])(?:a|an|one|two|three|four|five|per|\d+)[ \t]+$", re.I)
# "1. Name" / "2) Explain" at a line start; a lone "(1)" needs its complete sequence.
_LINE_MARKER = re.compile(r"(?m)^[ \t]*(?:[-*•][ \t]+)?(?P<digits>[1-9]\d?)[.)․](?=[ \t]+\S)")
_INLINE_MARKER = re.compile(r"\((?P<digits>[1-9]\d?)\)")


def _amount_follows(source: str, end: int, units: tuple[str, ...]) -> bool:
    """True when the text after a labelled number makes it an amount."""
    tail = source[end:]
    if re.match(r"[ \t]*(?:[-−+*/×÷=^<>≤≥%‰°$€£]|percent\b)", tail):
        return True
    word = re.match(r"[ \t]+([^\W\d_]+|[²³°])", tail)
    if word and word[1].casefold() in _AMOUNT_WORDS:
        return True
    stripped = tail.lstrip(" \t")
    return any(re.match(re.escape(unit).replace(r"\ ", r"\s+") + r"(?!\w)", stripped, re.I) for unit in units)


def _sentence_start(source: str, start: int) -> bool:
    prefix = source[:start].rstrip(" \t*_")
    return not prefix or prefix[-1] in _SENTENCE_START


def _named_numeral_intervals(source: str, units: tuple[str, ...]) -> list[tuple[int, int]]:
    """Two passes: a verb-like label at a sentence start ("Reading 1 fits the
    policy") counts only when THIS field also uses the same label unambiguously
    ("Reading 1:", "under Reading 1"); fields are never joined."""
    first = _named_numeral_pass(source, units, confirmed=frozenset())
    return _named_numeral_pass(source, units, confirmed=first[1])[0]


def _named_numeral_pass(source: str, units: tuple[str, ...], *, confirmed: frozenset):
    ranges, labels = [], set()
    verb_like = {noun for noun in _VERB_LIKE_NOUNS}
    identifier = set(_IDENTIFIER_NOUNS)
    time_nouns = set(_TIME_NOUNS)
    for match in _NAMED_NUMERAL.finditer(source):
        noun = match["noun"]
        folded = noun.casefold()
        singular = re.sub(r"(?:ies)$", "y", folded)
        singular = singular[:-2] if singular.endswith(("ses", "xes", "ches", "shes")) else singular
        singular = singular[:-1] if singular.endswith("s") and singular[:-1] in set(
            _LABEL_NOUNS + _IDENTIFIER_NOUNS + _VERB_LIKE_NOUNS + _TIME_NOUNS) else singular
        numbers = list(re.finditer(_NAMED_NUMBER, match["numbers"]))
        plural = singular != folded
        if plural and len(numbers) < 2 and "number" not in match["joint"].casefold():
            continue  # "readings 3" is not a list label; "Steps 1 and 2" is.
        if not plural and len(numbers) > 1 and not re.search(r"\band\b|,", match["numbers"]):
            numbers = numbers[:1]  # "Step 2 - 3" is arithmetic; keep only the label.
        prefix = source[:match.start()]
        if _COUNTING_PREFIX.search(prefix):
            continue
        labelled = re.match(r"[ \t]*[:()\].,;—–]", source[match.end():]) is not None
        school = (singular in {"grade", "year", "class"} and noun[:1].isupper()
                  and all(1 <= int(re.match(r"\d+", number[0])[0]) <= 13 for number in numbers))
        if not school and (singular in verb_like or plural and singular in {"claim", "draft", "attempt", "question", "route",
                                                              "detail", "plot", "seat", "request", "message",
                                                              "batch", "invoice", "grade", "reading", "order"}):
            capital = noun[:1].isupper() and not _sentence_start(source, match.start())
            key = (singular, match["numbers"])
            if not (_DETERMINER.search(prefix) or capital or labelled or "#" in match["joint"]
                    or "no" in match["joint"].casefold() or ":" in match["joint"]
                    or (noun[:1].isupper() and key in confirmed)):
                continue
            follower = re.match(r"[ \t]+([^\W\d_]+)", source[match.end():])
            if follower and follower[1].casefold() in _AMOUNT_WORDS | _COUNT_NOUNS:
                continue
            if not (noun[:1].isupper() and key in confirmed and _sentence_start(source, match.start())):
                labels.add(key)
        if singular in time_nouns:
            if not (noun[:1].isupper() or _TIME_PREPOSITION.search(prefix) or labelled):
                continue
        if singular in {"year", "class", "grade"} and any(
                len(number[0].rstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) not in (1, 2, 4) for number in numbers):
            continue
        # "Route 9 trips": a declared unit after an identifier names what is on
        # Route 9; generic amount words ("Room 3 metres", "account 300 credits") still count.
        if _amount_follows(source, match.end(), () if singular in identifier else units):
            # Only the trailing amount is a quantity: "Steps 1 and 2 cost 40" never
            # reaches here, but "Line 2 cm" and "Step 3 of 5" keep their numbers.
            continue
        offset = match.start("numbers")
        for number in numbers:
            digits = re.match(r"\d+", number[0])
            ranges.append((offset + number.start(), offset + number.start() + digits.end()))
    return ranges, frozenset(labels)


def _code_intervals(source: str) -> list[tuple[int, int]]:
    ranges = []
    for match in _CODE.finditer(source):
        code = match["code"]
        if not re.search(r"\d", code):
            continue
        segments = re.split(r"[-_]", code)
        lettered = [segment for segment in segments if segment[:1].isalpha()]
        first = segments[0]
        if not (len(re.match(r"[A-Za-z]+", first)[0]) >= 2 or (len(first) == 1 and first.isupper())
                or len(lettered) >= 2):
            continue  # "x-2" is algebra, not a code.
        ranges.extend((match.start("code") + digit.start(), match.start("code") + digit.end())
                      for digit in re.finditer(r"\d+", code))
    for match in _ID_KEY.finditer(source):
        ranges.extend((match.start("value") + digit.start(), match.start("value") + digit.end())
                      for digit in re.finditer(r"\d+", match["value"]))
    ranges += [match.span("digits") for match in _HASH_IDENTIFIER.finditer(source)]
    ranges += [match.span("digits") for match in _NUMBER_WORD_IDENTIFIER.finditer(source)]
    for pattern, group in ((_VERSION, "number"), (_NOUN_CODE, "code")):
        for match in pattern.finditer(source):
            ranges += _digits_in(source, match.start(group), match.end(group))
    return ranges


def _digits_in(source: str, start: int, end: int) -> list[tuple[int, int]]:
    return [(start + digit.start(), start + digit.end()) for digit in re.finditer(r"\d+", source[start:end])]


_DATE_PREPOSITION = re.compile(
    r"(?:^|[^\w])(?:on|by|before|after|until|till|from|since|through|between|due|dated|starting|"
    r"ending|effective|of|as[ \t]+of|the|this|that|next|last)[ \t]+$", re.I)
_DATE_FOLLOW = frozenset(
    "the a an at in on by for from when while with is was were will would and or but as after before then so "
    "because if he she it they we you i this that these those his her their our its my your there to through "
    "until deadline".split())


def _month_day_is_date(source: str, match) -> bool:
    """"April 5" is a date unless the number reads as a following count ("In March 12 riders")."""
    if _DATE_PREPOSITION.search(source[:match.start()]):
        return True
    tail = source[match.end():]
    if not tail.strip() or re.match(r"[ \t]*(?:[,.;:!?)\]'\"”’—–-]|\n|-?[^\W\d_]*ին\b)", tail):
        return True
    word = re.match(r"[ \t]+([^\W\d_]+)", tail)
    return bool(word) and word[1].casefold() in _DATE_FOLLOW


def _date_intervals(source: str) -> list[tuple[int, int]]:
    ranges = []
    for match in _MONTH_DAY.finditer(source):
        if _month_day_is_date(source, match):
            ranges += _digits_in(source, match.start(), match.end())
    for pattern in (_DAY_MONTH, _MONTH_YEAR, _NUMERIC_DATE):
        for match in pattern.finditer(source):
            ranges += _digits_in(source, match.start(), match.end())
    ranges += [match.span("year") for match in _PLAIN_YEAR.finditer(source)]
    return ranges


def _clock_intervals(source: str) -> list[tuple[int, int]]:
    ranges = []
    for pattern in (_CLOCK, _MERIDIEM):
        for match in pattern.finditer(source):
            lower = max(source.rfind(mark, 0, match.start()) for mark in (". ", "!", "?", "։", "\n")) + 1
            upper = min([index for index in (source.find(mark, match.end()) for mark in (". ", "!", "?", "։", "\n"))
                         if index != -1] or [len(source)])
            if _RATIO_CONTEXT.search(source[lower:upper]):
                continue  # "a 3:15 ratio" compares quantities.
            before = source[:match.start()]
            bullet = re.search(r"(?:^|\n)[ \t]*[-*•][ \t]+$", before) is not None  # "- 10:02:11 ..."
            if (not bullet and re.search(r"[-−+*/×÷=^][ \t]*$", before)) or re.match(
                    r"[ \t]*[-−+*/×÷=^]", source[match.end():]):
                continue
            ranges += _digits_in(source, match.start(), match.end())
    return ranges


def _ordinal_suffix_intervals(source: str) -> list[tuple[int, int]]:
    # "the 2nd attempt", "on the 5th"; "a 5th of the budget" is a fraction.
    return [match.span("digits") for match in _ORDINAL_SUFFIX.finditer(source)
            if not _FRACTION_PREFIX.search(source[:match.start()])]


def _list_marker_intervals(source: str, units: tuple[str, ...]) -> list[tuple[int, int]]:
    """A numbered item marker at a line start ("1. Name the gap", "2) Explain")."""
    ranges = []
    for match in _LINE_MARKER.finditer(source):
        if _meaningful_item_start(source, match.end(), len(source), units, reviewed_articles=True):
            ranges.append(match.span("digits"))
    # An inline "(1) ... (2) ..." enumeration inside one field: the complete
    # 1..N sequence, each before a word, never a parenthesised amount.
    quoted = [match.span() for match in _QUOTED.finditer(source)]
    markers = [match for match in _INLINE_MARKER.finditer(source)
               if not any(lower <= match.start() < upper for lower, upper in quoted)
               and not quoted_or_unclosed_prefix(source, match.start())]
    if (len(markers) >= 2 and [int(match["digits"]) for match in markers] == list(range(1, len(markers) + 1))
            and all(_meaningful_item_start(source, match.end(),
                                           markers[index + 1].start() if index + 1 < len(markers) else len(source),
                                           units, reviewed_articles=True)
                    for index, match in enumerate(markers))):
        ranges += [match.span("digits") for match in markers]
    return ranges


def non_quantity_numeral_intervals(source: str, *, labels: Iterable[str] = (), values: Iterable[float] = (),
                                   units: Iterable[str] = (), structural: bool = True) -> list[tuple[int, int]]:
    """Source digit intervals that name, date, time, label or version something.

    The single numeral policy. Only the digits are returned; every other
    number in the same sentence stays a quantity. Composed of:
    - ``incidental_numeral_intervals`` (codes such as INV-42, citations,
      ordinal labels at a sentence start, angle constants, datum-label words);
    - ``structural_ordinal_intervals`` (a complete 1..N list in this field);
    - labels and identifiers after a closed noun list: "Paragraph 1:",
      "Reading 2", "Line 2", "Option 3", "Steps 1 and 2", "order 418",
      "Route 14", "Room 3B", "Year 5", "Revision numbers 1 and 2", "#418",
      "order_ref: 88", never before an amount word ("Step 3 of 5", "line 2 cm");
    - letter-led codes: "S-204", "k-77-a", "invoice-42-reminder-1";
    - dates: "April 5", "5 April", "March 10 to March 14", "2026-03-10";
    - clock times: "17:00", "10:02:11", "9 am", "8 p.m." (not in a ratio);
    - ordinals "2nd"/"5th" (not fractions) and numbered item markers.

    ``structural=False`` omits only ``structural_ordinal_intervals``, for a
    caller that already masks exactly those intervals with
    ``mask_structural_ordinals`` over the same field (lesson_review).
    """
    if not isinstance(source, str) or not re.search(r"\d", source):
        return []
    unit_values = (units,) if isinstance(units, str) else units
    normalized = tuple(" ".join(unit.split()) for unit in unit_values if isinstance(unit, str) and unit.strip())
    ranges = list(incidental_numeral_intervals(source, labels, values))
    if structural:
        ranges += structural_ordinal_intervals(source, normalized)
    ranges += _named_numeral_intervals(source, normalized)
    ranges += _code_intervals(source)
    ranges += _date_intervals(source)
    ranges += _clock_intervals(source)
    ranges += _ordinal_suffix_intervals(source)
    ranges += _list_marker_intervals(source, normalized)
    return sorted(set(ranges))


def quantity_numerals(source: str, *, labels: Iterable[str] = (), values: Iterable[float] = (),
                      units: Iterable[str] = ()) -> list[tuple[int, int, str]]:
    """Every numeral (shared tokenizer) in ``source`` that IS a quantity, as (start, end, text)."""
    if not isinstance(source, str) or not re.search(r"\d", source):
        return []
    exempt = non_quantity_numeral_intervals(source, labels=labels, values=values, units=units)
    found = {}
    for match in _NUMBER_LITERAL.finditer(source):
        found[match.start()] = (match.start(), match.end(), match.group())
    for match in _ATTACHED_NUMERIC_LITERAL.finditer(source):
        found.setdefault(match.start(1), (match.start(1), match.end(1), match.group(1)))
    quantities = []
    for start, end, text in sorted(found.values()):
        digits = [start + index for index, char in enumerate(text) if char.isdigit()]
        if not all(any(lower <= index < upper for lower, upper in exempt) for index in digits):
            quantities.append((start, end, text))
    return quantities


def is_quantity_numeral(source: str, start: int, end: int, *, labels: Iterable[str] = (),
                        values: Iterable[float] = (), units: Iterable[str] = ()) -> bool:
    """THE policy decision for one numeral occurrence source[start:end].

    False only when every digit of the numeral is covered by an explicit
    non-quantity pattern (``non_quantity_numeral_intervals``).
    """
    if not isinstance(source, str) or not 0 <= start < end <= len(source):
        return False
    exempt = non_quantity_numeral_intervals(source, labels=labels, values=values, units=units)
    digits = [index for index in range(start, end) if source[index].isdigit()]
    return bool(digits) and not all(any(lower <= index < upper for lower, upper in exempt) for index in digits)
