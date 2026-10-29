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


def _lines(body: str) -> list[str]:
    if _BANNED.search(body):
        raise _Reject("braces, semicolons, => and HTML are not allowed")
    return [line.strip() for line in body.splitlines() if line.strip()]


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


def _headers(lines: list[str], allowed: set[str], required: tuple[str, ...]) -> tuple[dict, list[str]]:
    """Consume leading `key: value` lines; rows start at the first other line."""
    headers: dict[str, str] = {}
    index = 0
    while index < len(lines):
        match = _HEADER.fullmatch(lines[index])
        if not match or match[1].lower() not in allowed:
            break
        if match[1].lower() in headers:
            raise _Reject(f"repeats {match[1].lower()}:")
        headers[match[1].lower()] = match[2].strip()
        index += 1
    missing = [key + ":" for key in required if key not in headers]
    if missing:
        raise _Reject("starts with " + " and ".join(missing) + " header lines")
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


def _formula(body: str) -> FormulaBlock:
    headers, rows = _headers(_lines(body), {"title"}, ("title",))
    if not 2 <= len(rows) <= 6:
        raise _Reject(f"needs 2-6 term lines, found {len(rows)}")
    terms = []
    for line in rows:
        match = _TERM.fullmatch(line)
        if not match:
            raise _Reject(f"term '{line[:40]}' must be '<sign> <label>' with a sign from = + − ± × ÷")
        terms.append(FormulaTerm(_sign(match[1]), _text(match[2], 60, "a term label")))
    if terms[0].sign != "=":
        raise _Reject("the first term must start with =")
    return FormulaBlock(_text(headers["title"], 60, "title"), tuple(terms))


def _chart(body: str) -> ChartBlock:
    headers, lines = _headers(_lines(body), {"type", "title", "unit"}, ("type", "title"))
    kind = headers["type"].lower()
    if kind not in {"waterfall", "bars"}:
        raise _Reject("type must be waterfall or bars")
    if not 2 <= len(lines) <= 8:
        raise _Reject(f"needs 2-8 rows, found {len(lines)}")
    rows = []
    for line in lines:
        cells = line.split("|")
        if len(cells) != 2:
            raise _Reject(f"row '{line[:40]}' must be '<label> | <number>'")
        label, total = cells[0].strip(), cells[0].strip().startswith("=")
        rows.append(ChartRow(_text(label[1:] if total else label, 24, "a row label"),
                             _number(cells[1], "row value"), total))
    totals = [index for index, row in enumerate(rows) if row.total]
    if kind == "waterfall":
        if totals != [len(rows) - 1]:
            raise _Reject("a waterfall ends with one '= <label> | <number>' total row")
        _require_total([row.value for row in rows[:-1]], rows[-1].value, "waterfall total", relative=True)
    elif totals:
        raise _Reject("bars have no '=' total row")
    return ChartBlock(kind, _text(headers["title"], 80, "title"),
                      _text(headers.get("unit", ""), 12, "unit", empty=True) or None, tuple(rows))


def _steps(body: str) -> StepsBlock:
    headers, lines = _headers(_lines(body), {"title", "unit"}, ("title",))
    total = None
    if lines and lines[-1].startswith("="):
        cells = lines.pop()[1:].split("|")
        if len(cells) != 2:
            raise _Reject("the total row must be '= <label> | <number>'")
        total = StepTotal(_text(cells[0], 60, "the total label"), _number(cells[1], "total"))
    if not 2 <= len(lines) <= 6:
        raise _Reject(f"needs 2-6 step rows, found {len(lines)}")
    rows = []
    for line in lines:
        cells = line.split("|")
        if line.startswith("=") or len(cells) != 3:
            raise _Reject(f"row '{line[:40]}' must be '<label> | <number or empty> | <note>'")
        rows.append(StepRow(_text(cells[0], 60, "a step label"),
                            _number(cells[1], "step value") if cells[1].strip() else None,
                            _text(cells[2], 160, "a step note")))
    if total is not None:
        values = [row.value for row in rows if row.value is not None]
        if not values:
            raise _Reject("a total row needs step values")
        _require_total(values, total.value, "total", relative=False)
    return StepsBlock(_text(headers["title"], 80, "title"),
                      _text(headers.get("unit", ""), 12, "unit", empty=True) or None, tuple(rows), total)


def _check(body: str) -> CheckBlock:
    lines = _lines(body)
    question = re.fullmatch(r"Q\s*:(.*)", lines[0], re.I) if lines else None
    why = re.fullmatch(r"Why\s*:(.*)", lines[-1], re.I) if len(lines) > 1 else None
    if not question or not why:
        raise _Reject("starts with 'Q: <question>' and ends with 'Why: <explanation>'")
    middle = lines[1:-1]
    answer = _ANSWER.fullmatch(middle[0]) if len(middle) == 1 else None
    if answer:
        tolerance = _number(answer[3], "tolerance")
        if tolerance < 0:
            raise _Reject("tolerance must not be negative")
        numeric = NumericAnswer(_number(answer[1], "answer"), _text(answer[2], 12, "unit", empty=True), tolerance)
        options: tuple[CheckOption, ...] = ()
    else:
        if not 2 <= len(middle) <= 4:
            raise _Reject("needs 2-4 '- [ ] option' lines or one 'answer: <n> | unit: <u> | tolerance: <n>' line")
        matches = [_OPTION.fullmatch(line) for line in middle]
        if not all(matches):
            raise _Reject("options must be '- [ ] text' or '- [x] text'")
        options = tuple(CheckOption(_text(match[2], 120, "an option"), match[1] in "xX") for match in matches)
        if not any(option.correct for option in options):
            raise _Reject("mark at least one correct option with [x]")
        numeric = None
    return CheckBlock(_text(question[1], 240, "the question"), options, numeric, _text(why[1], 280, "Why"))


def _comparison(body: str) -> ComparisonBlock:
    lines = _lines(body)
    separators = [index for index, line in enumerate(lines) if line.casefold() in {"vs", "versus"}]
    if len(separators) != 1:
        raise _Reject("needs exactly one line containing only vs")
    groups = (lines[:separators[0]], lines[separators[0] + 1:])
    for group in groups:
        if not (3 <= len(group) <= 13 and len(group[0]) <= 100 and re.search(r"[A-Za-z]", group[0])
                and all(re.fullmatch(r"(?:[-•]|\d+[.)])\s+\S.*", item) for item in group[1:])):
            raise _Reject("each side needs a heading with a Latin letter and 2-12 bullet items")
    return ComparisonBlock(tuple(groups[0]), tuple(groups[1]))


def _diagram(body: str) -> DiagramBlock:
    # Deliberately restrict generated diagrams to a native vertical chain.
    # Complex geometry belongs to the reviewed practice package.
    _lines(body)
    raw = [line.rstrip() for line in body.splitlines() if line.strip()]
    nodes = [index for index, line in enumerate(raw) if re.fullmatch(r"\[[^\[\]]{1,80}\]", line.strip())]
    if not (2 <= len(nodes) <= 6 and nodes[0] == 0 and nodes[-1] == len(raw) - 1):
        raise _Reject("needs 2-6 [node] lines, starting and ending with a node")
    for start, end in zip(nodes, nodes[1:]):
        connectors = raw[start + 1:end]
        if (not connectors or not all(re.fullmatch(r"\s*[│▼↓]\s*", line) for line in connectors)
                or not any("▼" in line or "↓" in line for line in connectors)
                or len({len(line) - len(line.lstrip()) for line in connectors}) != 1):
            raise _Reject("nodes must be joined by aligned │ and ▼ (or ↓) connector lines")
    return DiagramBlock(tuple(raw[index].strip()[1:-1] for index in nodes))


_PARSERS: dict[str, Callable[[str], object]] = {
    "formula": _formula, "chart": _chart, "steps": _steps, "check": _check,
    "comparison": _comparison, "diagram": _diagram,
}


def fence_error(kind: str, body: str) -> str | None:
    """Return why a fence body is invalid, or None when it parses."""
    try:
        _PARSERS[kind](body)
    except _Reject as exc:
        return str(exc)
    return None


def _parse(kind: str, body: str):
    try:
        return _PARSERS[kind](body)
    except _Reject:
        return None


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
