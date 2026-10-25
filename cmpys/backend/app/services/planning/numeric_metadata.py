"""Occurrence-owned structural list metadata, never numerical fact evidence."""
from __future__ import annotations

import re
from collections.abc import Iterable


_MARKER = re.compile(r"\(([0-9]{1,3})\)|([0-9]{1,3})\)|([0-9]{1,3})․")
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
    if not isinstance(source, str) or not _MARKER.search(source) or _ambiguous_paired_quotes(source):
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
    for match in re.finditer(r"\b(?:sentence|criterion)[ \t]+([1-9]\d?)(?!\w|\.\d|[ \t]*[-−+*/×÷=%])", source, re.I):
        if quoted_or_unclosed_prefix(source, match.start()):
            continue
        suffix = source[match.end():].lstrip()
        word = re.match(r"[^\W\d_]+", suffix)
        if word and word[0].casefold() in _QUANTITY_STARTS | {"day", "days", "month", "months", "year", "years"}:
            continue
        if any(re.match(re.escape(unit) + r"(?!\w)", suffix, re.I) for unit in units if unit):
            continue
        ranges.append(match.span(1))
    return ranges


def reviewed_labeled_ordinal_intervals(source: str) -> list[tuple[int, int]]:
    """Complete same-field instructional labels, only after independent review.

    Return only the ordinal digits. Every number in the following text remains
    a claim; ordinary quoted passages and incomplete lists stay unmasked.
    """
    # A complete quoted model response may discuss its own ordered action
    # labels. Require the explicit model introduction, balanced owning quote,
    # noun/verb syntax and a complete sequence. Ordinary quoted case numbers
    # and all quantities within the model remain untouched.
    model_ranges = []
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
