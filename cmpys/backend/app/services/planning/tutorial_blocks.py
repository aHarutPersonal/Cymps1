"""Line grammar of the native tutorial_v1 reader blocks (one parser per fence).

Each parser takes a fence body (the lines between the opening ```kind line
and the closing ``` line) and returns a frozen dataclass, or None when the body
breaks its grammar. The Flutter reader mirrors this grammar and shows a fence
it cannot parse as plain lines. Lines are trimmed and blank lines ignored
(except that diagram connectors keep their indentation). Signs accept the
ASCII hyphen "-" and the minus "−". Numbers are checked after result tokens
are rendered; a raw [[result:...]] token is not a number.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal
from typing import Callable

PRIMARY_KINDS = ("formula", "diagram", "comparison")
BLOCK_KINDS = ("formula", "chart", "steps", "check", "diagram", "comparison")
_BANNED = re.compile(r"[{};]|=>|<[A-Za-z/!][^<>]*>")
_NUMBER = re.compile(r"[+\-−]?[0-9]+(?:\.[0-9]+)?")
_HEADER = re.compile(r"(title|type|unit)\s*:\s*(.*)", re.I)
_TERM = re.compile(r"([=+\-−±×÷])\s+(\S.*)")
_OPTION = re.compile(r"-\s+\[([ xX])\]\s+(.*)")
_ANSWER = re.compile(r"answer\s*:([^|]*)\|\s*unit\s*:([^|]*)\|\s*tolerance\s*:([^|]*)", re.I)


@dataclass(frozen=True)
class FormulaTerm:
    sign: str  # one of = + − ± × ÷ (an ASCII "-" is stored as "−")
    label: str


@dataclass(frozen=True)
class FormulaBlock:
    title: str
    terms: tuple[FormulaTerm, ...]


@dataclass(frozen=True)
class ChartRow:
    label: str  # a total row's leading "=" is not part of its label
    value: Decimal
    total: bool = False


@dataclass(frozen=True)
class ChartBlock:
    type: str  # "waterfall" or "bars"
    title: str
    unit: str | None
    rows: tuple[ChartRow, ...]


@dataclass(frozen=True)
class StepRow:
    label: str
    value: Decimal | None  # None: a reasoning step without a number
    note: str


@dataclass(frozen=True)
class StepTotal:
    label: str
    value: Decimal


@dataclass(frozen=True)
class StepsBlock:
    title: str
    unit: str | None
    rows: tuple[StepRow, ...]
    total: StepTotal | None


@dataclass(frozen=True)
class CheckOption:
    text: str
    correct: bool


@dataclass(frozen=True)
class NumericAnswer:
    value: Decimal
    unit: str
    tolerance: Decimal


@dataclass(frozen=True)
class CheckBlock:
    question: str
    options: tuple[CheckOption, ...]
    answer: NumericAnswer | None
    why: str

    @property
    def select_all(self) -> bool:
        return sum(option.correct for option in self.options) > 1


@dataclass(frozen=True)
class ComparisonBlock:
    left: tuple[str, ...]  # heading, then items
    right: tuple[str, ...]


@dataclass(frozen=True)
class DiagramBlock:
    nodes: tuple[str, ...]


class _Reject(ValueError):
    """Why a fence body breaks its grammar; used only for writer diagnostics."""


_SUM_FIX = ("every row with a number adds into the running total: give inputs such as base or height "
            "an empty number cell and put the value in the note, and write a product as one "
            "row, e.g. 'Base × height | 24 | 6 × 4'")
_SECOND_RESULT_FIX = ("total the main result on that final row and give any other result its own valued "
                      "row, the chart or prose, never a second \"=\" row or a second steps fence")


def _clip(line: str) -> str:
    return line if len(line) <= 60 else line[:57] + "..."


class _Defects:
    """Every defect of one fence body, each naming its line and a concrete fix."""

    def __init__(self) -> None:
        self.items: list[str] = []

    def add(self, message: str, line: str | None = None) -> None:
        self.items.append(f"line '{_clip(line)}': {message}" if line is not None else message)

    def value(self, parse: Callable, *args, line: str | None = None):
        """Run one cell parser; record its defect and return None instead of raising."""
        try:
            return parse(*args)
        except _Reject as exc:
            self.add(str(exc), line)
            return None


def _banned_fix(line: str) -> str:
    fixes = []
    if ";" in line:
        fixes.append("use a comma or a full stop instead of a semicolon")
    if "{" in line or "}" in line:
        fixes.append("remove the braces")
    if "=>" in line:
        fixes.append("write => as words")
    if re.search(r"<[A-Za-z/!][^<>]*>", line):
        fixes.append("remove the HTML tags")
    return " and ".join(fixes)


def _lines(body: str, defects: _Defects) -> list[str]:
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    for line in lines:
        if _BANNED.search(line):
            defects.add(f"braces, semicolons, => and HTML are not allowed: {_banned_fix(line)}", line)
    return lines


def _text(value: str, limit: int, what: str, *, empty: bool = False) -> str:
    value = value.strip()
    if (not value and not empty) or len(value) > limit:
        raise _Reject(f"{what} must be {0 if empty else 1}-{limit} characters")
    return value


def _number(value: str, what: str) -> Decimal:
    value = value.strip()
    if not _NUMBER.fullmatch(value):
        raise _Reject(f"{what} '{value[:40]}' must be a plain number such as -30 or 4.5")
    return Decimal(value.replace("−", "-"))


def _sign(value: str) -> str:
    return "−" if value == "-" else value


def _headers(lines: list[str], allowed: set[str], required: tuple[str, ...],
             defects: _Defects) -> tuple[dict, list[str]]:
    """Consume leading `key: value` lines; rows start at the first other line."""
    headers: dict[str, str] = {}
    index = 0
    while index < len(lines):
        match = _HEADER.fullmatch(lines[index])
        if not match or match[1].lower() not in allowed:
            break
        if match[1].lower() in headers:
            defects.add(f"repeats {match[1].lower()}: keep one {match[1].lower()}: line", lines[index])
        headers[match[1].lower()] = match[2].strip()
        index += 1
    missing = [key + ":" for key in required if key not in headers]
    if missing:
        defects.add("starts with " + " and ".join(missing) + " header lines")
    return headers, lines[index:]


def _places(value: Decimal) -> int:
    return -min(value.as_tuple().exponent, 0)


def _require_total(parts: list[Decimal], total: Decimal, what: str, *, relative: bool) -> None:
    """Check a stated total against its rows.

    relative (waterfall): within 0.5% of the total, never stricter than half a
    unit of the finest decimal shown. Otherwise (steps): equal up to display
    rounding only, i.e. half a unit of the coarsest decimal shown, so the
    reader's running total agrees with the printed total.
    """
    values = [*parts, total]
    rounding = Decimal("0.5") * Decimal(10) ** -(max if relative else min)(map(_places, values))
    allowed = max(abs(total) * Decimal("0.005"), rounding) if relative else rounding
    if abs(sum(parts) - total) > allowed:
        raise _Reject(f"{what} {total} must equal the sum of the rows above it ({sum(parts)})")


def _formula(body: str, defects: _Defects) -> FormulaBlock:
    headers, rows = _headers(_lines(body, defects), {"title"}, ("title",), defects)
    equations = sum(1 for line in rows if line.startswith("="))
    if not 2 <= len(rows) <= 6:
        defects.add(f"needs 2-6 term lines, found {len(rows)}"
                    + (". A formula fence holds one equation: show any other equation in prose"
                       if len(rows) > 6 or equations > 1 else ""))
    terms = []
    for line in rows:
        match = _TERM.fullmatch(line)
        if not match:
            defects.add("a term must be '<sign> <label>' with a sign from = + − ± × ÷", line)
            continue
        label = defects.value(_text, match[2], 60, "a term label", line=line)
        terms.append(FormulaTerm(_sign(match[1]), label or ""))
    first = _TERM.fullmatch(rows[0]) if rows else None
    if first and _sign(first[1]) != "=":
        defects.add("the first term must start with =", rows[0])
    title = defects.value(_text, headers["title"], 60, "title") if "title" in headers else ""
    return FormulaBlock(title or "", tuple(terms))


def _chart(body: str, defects: _Defects) -> ChartBlock:
    headers, lines = _headers(_lines(body, defects), {"type", "title", "unit"}, ("type", "title"), defects)
    kind = headers.get("type", "").lower()
    if "type" in headers and kind not in {"waterfall", "bars"}:
        defects.add("type must be waterfall or bars")
    if not 2 <= len(lines) <= 8:
        defects.add(f"needs 2-8 rows, found {len(lines)}")
    rows, complete = [], True
    for line in lines:
        cells = line.split("|")
        if len(cells) != 2:
            defects.add("a chart row must be '<label> | <number>' with nothing after the number", line)
            complete = False
            continue
        label, total = cells[0].strip(), cells[0].strip().startswith("=")
        text = defects.value(_text, label[1:] if total else label, 24, "a row label", line=line)
        value = defects.value(_number, cells[1], "row value", line=line)
        complete &= value is not None
        rows.append(ChartRow(text or "", value if value is not None else Decimal(0), total))
    totals = [index for index, row in enumerate(rows) if row.total]
    if kind == "waterfall":
        if totals != [len(rows) - 1]:
            defects.add("a waterfall ends with one '= <label> | <number>' total row, and only that last row "
                        "starts with =")
        elif complete and len(rows) == len(lines):
            try:
                _require_total([row.value for row in rows[:-1]], rows[-1].value, "waterfall total", relative=True)
            except _Reject as exc:
                defects.add(f"{exc}. Every row adds into the running total")
    elif kind == "bars" and totals:
        defects.add("bars have no '=' total row", lines[totals[0]] if len(rows) == len(lines) else None)
    title = defects.value(_text, headers["title"], 80, "title") if "title" in headers else ""
    unit = defects.value(lambda text: _text(text, 12, "unit", empty=True), headers.get("unit", ""))
    return ChartBlock(kind, title or "", unit or None, tuple(rows))


_NO_NUMBERS = "this case has no numbers; do not score or count — leave step values empty"
_PLAIN_ROW = "write this last row as '<label> | | <note>' without the leading \"=\""


def _steps(body: str, defects: _Defects, *, case_has_numbers: bool = True) -> StepsBlock:
    """``case_has_numbers=False``: the package has no case data, so any step value is invented."""
    headers, lines = _headers(_lines(body, defects), {"title", "unit"}, ("title",), defects)
    total, total_known = None, True
    empty_total = None  # the "=" line whose number cell is empty
    if lines and lines[-1].startswith("=") and not case_has_numbers:
        defects.add(f"{_NO_NUMBERS} and {_PLAIN_ROW}", lines.pop())
    elif lines and lines[-1].startswith("="):
        line = lines.pop()
        cells = line[1:].split("|")
        if len(cells) in (2, 3) and not cells[1].strip():
            # Reported after the rows: the fix depends on whether they carry numbers.
            empty_total, cells = line, []
        if len(cells) == 3 and cells[1].strip():
            defects.add('remove the text after the number on the "=" row: the total row is '
                        "'= <label> | <number>' with nothing after the number", line)
        elif len(cells) != 2 and empty_total is None:
            defects.add("the total row must be '= <label> | <number>'", line)
        label = value = None
        if len(cells) in (2, 3):
            label = defects.value(_text, cells[0], 60, "the total label", line=line)
            value = defects.value(_number, cells[1], "total", line=line)
        total_known = value is not None
        if value is not None:
            total = StepTotal(label or "", value)
    if not 2 <= len(lines) <= 6:
        defects.add(f"needs 2-6 step rows, found {len(lines)}")
    rows, sums_known = [], True
    for line in lines:
        cells = line.split("|")
        if line.startswith("="):
            defects.add('only the last line may start with "=": ' + _SECOND_RESULT_FIX, line)
            sums_known = False
            continue
        if len(cells) != 3:
            fix = (f"a unit belongs in a header line, write 'unit: {line}'" if _is_unit_line(line)
                   else "write '<label> | <number or empty> | <note>'")
            defects.add(f"a step row must be '<label> | <number or empty> | <note>': {fix}", line)
            # A malformed row's number cannot join the running total check.
            sums_known &= len(cells) == 1 or not cells[1].strip()
            continue
        label = defects.value(_text, cells[0], 60, "a step label", line=line)
        if cells[1].strip() and not case_has_numbers:
            defects.add(_NO_NUMBERS, line)
            value = None
        else:
            value = defects.value(_number, cells[1], "step value", line=line) if cells[1].strip() else None
            sums_known &= value is not None or not cells[1].strip()
        note = defects.value(_text, cells[2], 160, "a step note", line=line)
        rows.append(StepRow(label or "", value, note or ""))
    if empty_total is not None:
        values = [row.value for row in rows if row.value is not None]
        if values or not sums_known or any(re.search(r"\d", line) for line in [*lines, empty_total]):
            known = f" ({sum(values)})" if sums_known and values else ""
            defects.add('the "=" total row has no number: write the sum of the rows above'
                        f"{known}, as the result's display token when the package has one, "
                        "and never add numbers to rows that had none", empty_total)
        else:
            defects.add("these reasoning rows carry no numbers: write this last row as "
                        "'<label> | | <note>' and remove the leading \"=\"", empty_total)
    if total is not None and sums_known:
        values = [row.value for row in rows if row.value is not None]
        if not values:
            defects.add("a total row needs step values: " + _SUM_FIX)
        else:
            try:
                _require_total(values, total.value, "total", relative=False)
            except _Reject as exc:
                defects.add(f"{exc}: {_SUM_FIX}")
    title = defects.value(_text, headers["title"], 80, "title") if "title" in headers else ""
    unit = defects.value(lambda text: _text(text, 12, "unit", empty=True), headers.get("unit", ""))
    return StepsBlock(title or "", unit or None, tuple(rows), total if total_known else None)


def _check(body: str, defects: _Defects) -> CheckBlock:
    lines = _lines(body, defects)
    question = re.fullmatch(r"Q\s*:(.*)", lines[0], re.I) if lines else None
    why = re.fullmatch(r"Why\s*:(.*)", lines[-1], re.I) if len(lines) > 1 else None
    if not question or not why:
        defects.add("starts with 'Q: <question>' and ends with 'Why: <explanation>'"
                    + ("" if question else ": add a first line 'Q: <question>'")
                    + ("" if why else ": add a last line 'Why: <explanation>'"))
    middle = lines[1 if question else 0:len(lines) - 1 if why else len(lines)]
    answer = _ANSWER.fullmatch(middle[0]) if len(middle) == 1 else None
    numeric, options = None, ()
    if answer:
        tolerance = defects.value(_number, answer[3], "tolerance", line=middle[0])
        if tolerance is not None and tolerance < 0:
            defects.add("tolerance must not be negative", middle[0])
        value = defects.value(_number, answer[1], "answer", line=middle[0])
        unit = defects.value(lambda text: _text(text, 12, "unit", empty=True), answer[2], line=middle[0])
        if value is not None and tolerance is not None:
            numeric = NumericAnswer(value, unit or "", tolerance)
    else:
        if not 2 <= len(middle) <= 4:
            defects.add(f"needs 2-4 '- [ ] option' lines or one 'answer: <n> | unit: <u> | tolerance: <n>' "
                        f"line, found {len(middle)}")
        parsed = []
        for line in middle:
            match = _OPTION.fullmatch(line)
            if not match:
                defects.add("options must be '- [ ] text' or '- [x] text'", line)
                continue
            parsed.append(CheckOption(defects.value(_text, match[2], 120, "an option", line=line) or "",
                                      match[1] in "xX"))
        options = tuple(parsed)
        if not any(option.correct for option in options):
            defects.add("mark at least one correct option with [x]: write '- [x] <option>' for each correct one")
    question_text = defects.value(_text, question[1], 240, "the question", line=lines[0]) if question else ""
    why_text = defects.value(_text, why[1], 280, "Why", line=lines[-1]) if why else ""
    return CheckBlock(question_text or "", options, numeric, why_text or "")


def _comparison(body: str, defects: _Defects) -> ComparisonBlock:
    lines = _lines(body, defects)
    separators = [index for index, line in enumerate(lines) if line.casefold() in {"vs", "versus"}]
    if len(separators) != 1:
        defects.add(f"needs exactly one line containing only vs, found {len(separators)}")
        return ComparisonBlock((), ())
    groups = (lines[:separators[0]], lines[separators[0] + 1:])
    for side, group in zip(("left", "right"), groups):
        problem = "each side needs a heading with a Latin letter and 2-12 bullet items"
        if not group:
            defects.add(f"{problem}: the {side} side is empty")
            continue
        heading = group[0]
        if len(heading) > 100 or not re.search(r"[A-Za-z]", heading):
            defects.add(f"{problem}: the {side} heading needs a Latin letter and at most 100 characters, "
                        "add a short translation in parentheses such as '(Testable)'", heading)
        if not 3 <= len(group) <= 13:
            defects.add(f"{problem}: the {side} side has {len(group) - 1} items")
        for item in group[1:]:
            if not re.fullmatch(r"(?:[-•]|\d+[.)])\s+\S.*", item):
                defects.add(f"{problem}: write each item as '- <item>'", item)
    return ComparisonBlock(tuple(groups[0]), tuple(groups[1]))


def _diagram(body: str, defects: _Defects) -> DiagramBlock:
    # Deliberately restrict generated diagrams to a native vertical chain.
    # Complex geometry belongs to the reviewed practice package.
    _lines(body, defects)
    raw = [line.rstrip() for line in body.splitlines() if line.strip()]
    nodes = [index for index, line in enumerate(raw) if re.fullmatch(r"\[[^\[\]]{1,80}\]", line.strip())]
    if not (2 <= len(nodes) <= 6 and nodes[0] == 0 and nodes[-1] == len(raw) - 1):
        defects.add("needs 2-6 [node] lines, starting and ending with a node")
        return DiagramBlock(())
    for start, end in zip(nodes, nodes[1:]):
        connectors = raw[start + 1:end]
        if (not connectors or not all(re.fullmatch(r"\s*[│▼↓]\s*", line) for line in connectors)
                or not any("▼" in line or "↓" in line for line in connectors)
                or len({len(line) - len(line.lstrip()) for line in connectors}) != 1):
            defects.add("nodes must be joined by aligned │ and ▼ (or ↓) connector lines", raw[start].strip())
    return DiagramBlock(tuple(raw[index].strip()[1:-1] for index in nodes))


_PARSERS: dict[str, Callable[[str, _Defects], object]] = {
    "formula": _formula, "chart": _chart, "steps": _steps, "check": _check,
    "comparison": _comparison, "diagram": _diagram,
}


def _run(kind: str, body: str, *, case_has_numbers: bool = True) -> tuple[object | None, list[str]]:
    defects = _Defects()
    block = (_steps(body, defects, case_has_numbers=case_has_numbers) if kind == "steps"
             else _PARSERS[kind](body, defects))
    return (None if defects.items else block), defects.items


def fence_errors(kind: str, body: str, *, case_has_numbers: bool = True) -> list[str]:
    """Every reason a fence body is invalid (empty when it parses), each with its fix.

    ``case_has_numbers=False`` (the package has no teaching-case data and no
    result bindings) makes any steps value an invented number.
    """
    return _run(kind, body, case_has_numbers=case_has_numbers)[1]


def fence_error(kind: str, body: str) -> str | None:
    """Return why a fence body is invalid (all defects joined), or None when it parses."""
    return "; ".join(fence_errors(kind, body)) or None


def _parse(kind: str, body: str):
    return _run(kind, body)[0]


# A closed list of unit words and symbols a bare line under a steps title may
# be. Anything else (a datum such as "6 cm", a label such as "Revenue") stays
# a malformed row for the writer to fix, never a silent unit header.
_UNIT_WORDS = frozenset({
    "$", "€", "£", "¥", "₽", "֏", "usd", "eur", "gbp", "jpy", "rub", "amd", "chf", "cad", "aud",
    "$m", "$k", "$bn", "€m", "€k", "£m", "usd m", "eur m", "dollars", "euros", "դրամ", "դոլար",
    "mm", "cm", "m", "km", "in", "ft", "yd", "mi", "mm²", "cm²", "m²", "km²", "ha",
    "sq mm", "sq cm", "sq m", "sq km", "sq ft", "sq in", "mg", "g", "kg", "t", "lb", "oz", "ml", "l",
    "ms", "s", "sec", "min", "h", "hr", "hrs", "second", "seconds", "minute", "minutes", "hour", "hours",
    "day", "days", "week", "weeks", "month", "months", "year", "years", "%", "percent", "pp",
    "մմ", "սմ", "մ", "կմ", "քմ", "քառ. սմ", "քառ. մ", "քառակուսի սմ", "քառակուսի մ", "քառակուսի մետր",
    "քառակուսի սանտիմետր", "գ", "կգ", "տ", "լ", "վ", "րոպե", "ժամ", "օր", "շաբաթ", "ամիս", "տարի", "տոկոս",
})


def _is_unit_line(line: str, units: frozenset[str] | set[str] = frozenset()) -> bool:
    """A bare line that can only be a unit: a recognised or declared unit, never a datum."""
    line = line.strip()
    if not line or "|" in line or re.search(r"\d", line):
        return False
    return line in units or line.casefold() in _UNIT_WORDS


def _commas(text: str) -> str:
    """A semicolon inside a text cell reads the same as a comma; a trailing one is dropped."""
    return re.sub(r"\s*;[\s;]*$", "", re.sub(r"\s*;[\s;]*(?=\S)", ", ", text))


def _normalize_steps(lines: list[str], units: frozenset[str] | set[str] = frozenset()) -> list[str]:
    content = [index for index, line in enumerate(lines) if line.strip()]
    if not content:
        return lines
    last = content[-1]
    cells = lines[last].strip().split("|")
    headers = [_HEADER.fullmatch(lines[index].strip()) for index in content]
    if lines[last].strip().startswith("=") and len(cells) == 3 and cells[1].strip():
        # "= Label | N | note": the total row carries only its number.
        lines[last] = lines[last].rstrip().rsplit("|", 1)[0].rstrip()
    elif (lines[last].strip().startswith("=") and len(cells) == 3 and not cells[1].strip()
          and not any(re.search(r"\d", lines[index]) for index, match in zip(content, headers) if not match)):
        # "= Verdict | | note" in a fence whose rows hold no digit in any cell:
        # no total exists, so it is an ordinary row. A digit anywhere (label,
        # value or note) keeps the "=" and validation rejects the missing total.
        lines[last] = re.sub(r"^(\s*)=\s*", r"\1", lines[last], count=1)
    keys = [match[1].lower() for match in headers if match]
    title = next((position for position, match in enumerate(headers)
                  if match and match[1].lower() == "title"), None)
    if title is not None and title + 1 < len(content) and "unit" not in keys:
        index = content[title + 1]
        line = lines[index].strip()
        # A bare unit such as "cm" directly under the title is its unit header.
        if not _HEADER.fullmatch(line) and _is_unit_line(line, units):
            lines[index] = lines[index].replace(line, "unit: " + line, 1)
    for index in content:
        stripped = lines[index].strip()
        cells = stripped.split("|")
        if not stripped.startswith("=") and len(cells) == 3 and ";" in cells[2]:
            lines[index] = lines[index].replace(stripped, "|".join([*cells[:2], _commas(cells[2])]), 1)
    return lines


def _normalize_check(lines: list[str]) -> list[str]:
    for index, line in enumerate(lines):
        stripped = line.strip()
        if ";" not in stripped:
            continue
        text = re.fullmatch(r"(?:Q|Why)\s*:(.*)", stripped, re.I) or _OPTION.fullmatch(stripped)
        if text:
            cell = text.lastindex  # the question, explanation or option text
            fixed = stripped[:text.start(cell)] + _commas(text[cell]) + stripped[text.end(cell):]
            lines[index] = line.replace(stripped, fixed, 1)
    return lines


def normalize_fence(kind: str, body: str, *, units: frozenset[str] | set[str] = frozenset()) -> str:
    """Rewrite harmless variants of a fence body to the canonical grammar.

    Deterministic and content-neutral: a note after a steps total's number is
    dropped, a last "= <label> | | <note>" row under step rows that carry no
    number loses its "=" (no number is added), a bare line directly under a steps title becomes its "unit:"
    header only when it is a recognised unit word or symbol (or one of the
    case's declared ``units``) with no digit, and semicolons inside steps notes and check Q, Why and
    option text become commas. Braces, "=>" and HTML are left for validation
    to reject, and validation still decides everything else. Line endings and
    indentation are preserved.
    """
    if kind not in ("steps", "check"):
        return body
    lines = body.splitlines(keepends=True)
    endings = [line[len(line.rstrip("\r\n")):] for line in lines]
    stripped = [line.rstrip("\r\n") for line in lines]
    fixed = _normalize_steps(stripped, units) if kind == "steps" else _normalize_check(stripped)
    return "".join(line + ending for line, ending in zip(fixed, endings))


def parse_formula(body: str) -> FormulaBlock | None:
    return _parse("formula", body)


def parse_chart(body: str) -> ChartBlock | None:
    return _parse("chart", body)


def parse_steps(body: str) -> StepsBlock | None:
    return _parse("steps", body)


def parse_check(body: str) -> CheckBlock | None:
    return _parse("check", body)


def parse_comparison(body: str) -> ComparisonBlock | None:
    return _parse("comparison", body)


def parse_diagram(body: str) -> DiagramBlock | None:
    return _parse("diagram", body)
