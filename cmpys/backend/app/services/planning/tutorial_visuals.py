"""Validate the native reader blocks of tutorial_v1 lessons by section.

New tutorials (no Guided Practice section) need one primary visual in Core
Framework, one steps fence (plus an optional chart) in Worked Example and one
check fence in Check Your Understanding. Lessons published with a Guided
Practice section keep the legacy rule. Validate rendered text: fence
arithmetic is checked after ``render_package_results`` replaced result tokens.
The independent reviewer still judges whether a visual teaches the concept.
No remote image download or extra media-generation request is needed.
"""
from __future__ import annotations

import re
import textwrap
from typing import Mapping

from app.services.content_quality import PLAN_DETAIL_SECTION_ROWS
from app.services.planning.tutorial_blocks import (  # noqa: F401  (re-exported grammar)
    BLOCK_KINDS, PRIMARY_KINDS, ChartBlock, ChartRow, CheckBlock, CheckOption, ComparisonBlock,
    DiagramBlock, FormulaBlock, FormulaTerm, NumericAnswer, StepRow, StepsBlock, StepTotal,
    fence_error, fence_errors, normalize_fence, parse_chart, parse_check, parse_comparison, parse_diagram,
    parse_formula, parse_steps,
)

_FENCE = re.compile(r"^```(" + "|".join(BLOCK_KINDS) + r")[ \t]*\r?\n(.*?)^```[ \t]*\r?$", re.M | re.S)
_HEADINGS = {heading[3:]: name for name, heading in PLAN_DETAIL_SECTION_ROWS}
_SECTION_HEADING = re.compile(r"^## (.+?)[ \t]*$", re.M)
LEGACY_VISUAL_ISSUE = "tutorial must include a valid native comparison or diagram illustrating its concept"


def native_fences(text: str) -> list[tuple[str, str]]:
    """(kind, body) for every native block that opens at the start of a line."""
    return _FENCE.findall(text or "")


def normalize_native_fences(text: str, *, units: frozenset[str] | set[str] = frozenset()) -> str:
    """Rewrite harmless fence variants in place (see ``normalize_fence``); prose is untouched.

    ``units`` are the case's declared units, also accepted as a bare unit line.
    """
    def rewrite(match: re.Match) -> str:
        start, end = match.start(2) - match.start(), match.end(2) - match.start()
        return match[0][:start] + normalize_fence(match[1], match[2], units=units) + match[0][end:]
    return _FENCE.sub(rewrite, text or "")


# "steps", "steps:" or "check: Q: ..." (the first body line after the colon).
_BARE_LABEL = re.compile(r"[ \t]*(" + "|".join(BLOCK_KINDS) + r")[ \t]*(?::[ \t]*(.*?))?[ \t]*", re.I)
_CHECK_LINE = re.compile(r"[ \t]*(?:-\s+\[[ xX]\]\s+\S.*|answer\s*:.*)", re.I)
_FENCE_LINE = re.compile(r"[ \t]*```")
# The first body line a bare label must be followed by before it is fenced.
# Anything else stays prose, so a missing block is still reported as missing.
_BARE_BODY_START = {
    "formula": re.compile(r"title\s*:.*|[=+\-−±×÷]\s+\S.*", re.I),
    "chart": re.compile(r"(?:type|title)\s*:.*", re.I),
    "steps": re.compile(r"title\s*:.*|[^|]*\|.*", re.I),
    "check": re.compile(r"Q\s*:.*", re.I),
    "diagram": re.compile(r"\[[^\[\]]{1,80}\]"),
}


def _bare_body_fits(kind: str, body: list[str]) -> bool:
    first = body[0].strip()
    if kind == "comparison":
        # A heading, then its first "- item".
        return (len(body) > 1 and not re.match(r"[-•]\s", first)
                and re.match(r"[-•]\s+\S", body[1].strip()) is not None)
    return _BARE_BODY_START[kind].fullmatch(first) is not None


def _is_bare_check(body: list[str]) -> bool:
    """A label-less check paragraph: Q:, two or more options (or one answer line), Why: last."""
    rows = [row for row in body if row.strip()]
    return (len(rows) >= 3 and _BARE_BODY_START["check"].fullmatch(rows[0].strip()) is not None
            and re.match(r"[ \t]*Why\s*:\s*\S", rows[-1], re.I) is not None
            and all(_CHECK_LINE.fullmatch(row) for row in rows[1:-1])
            and (len(rows) >= 4 or re.match(r"[ \t]*answer\s*:", rows[1], re.I) is not None))


def wrap_bare_block_labels(text: str) -> str:
    """Fence a block written as a bare ``kind`` / ``kind:`` label line.

    Drafts sometimes write ``steps:`` and the block lines without backticks.
    Only a label line that starts a paragraph (start of field or after a
    blank line), outside any fence, and whose next line (or the text after
    ``kind:`` on the same line) opens that kind's grammar (see
    ``_BARE_BODY_START``) is wrapped: its paragraph becomes the fence body,
    lines trimmed (a diagram keeps relative indentation), and a check also
    takes one following ``Why:`` paragraph after a single blank line. A
    label-less paragraph that is exactly a check (``Q:``, options, ``Why:``)
    is fenced too. Everything else is left unchanged, and the fenced body is
    still validated in full.
    """
    lines = (text or "").split("\n")
    out: list[str] = []
    index, in_fence = 0, False
    while index < len(lines):
        line = lines[index]
        if _FENCE_LINE.match(line):
            in_fence = not in_fence
        label = None if in_fence else _BARE_LABEL.fullmatch(line)
        paragraph_start = index == 0 or not lines[index - 1].strip()
        unlabeled_check = (not in_fence and not label and paragraph_start
                           and _BARE_BODY_START["check"].fullmatch(line.strip()) is not None)
        if (label or unlabeled_check) and paragraph_start:
            kind = label[1].lower() if label else "check"
            end = index + 1
            while end < len(lines) and lines[end].strip() and not _FENCE_LINE.match(lines[end]):
                end += 1
            first = [label[2]] if label and label[2] else [] if label else [line]
            body = first + lines[index + 1:end]
            if (kind == "check" and end + 1 < len(lines) and not lines[end].strip()
                    and re.match(r"[ \t]*Why\s*:", lines[end + 1], re.I)):
                tail = end + 1
                while tail < len(lines) and lines[tail].strip() and not _FENCE_LINE.match(lines[tail]):
                    tail += 1
                body, end = body + lines[end + 1:tail], tail
            if body and _bare_body_fits(kind, body) and (label or _is_bare_check(body)):
                body = (textwrap.dedent("\n".join(body)).split("\n") if kind == "diagram"
                        else [row.strip() for row in body])
                out.extend(["```" + kind, *body, "```"])
                index = end
                continue
        out.append(line)
        index += 1
    return "\n".join(out)


def lesson_sections(markdown: str) -> dict[str, str]:
    """Canonical section bodies by field name; the first copy of a heading wins."""
    matches = [match for match in _SECTION_HEADING.finditer(markdown) if match[1] in _HEADINGS]
    sections: dict[str, str] = {}
    for match, following in zip(matches, [*matches[1:], None]):
        end = following.start() if following else len(markdown)
        sections.setdefault(_HEADINGS[match[1]], markdown[match.end():end].strip())
    return sections


def has_guided_practice(markdown: str) -> bool:
    """Legacy tutorial_v1 lessons carry a Guided Practice section."""
    return "guided_practice" in lesson_sections(markdown)


_REQUIRED = {
    "core_framework": ((PRIMARY_KINDS, "primary visual fence (formula, diagram or comparison)", True),),
    "worked_example": ((("steps",), "steps fence", True), (("chart",), "chart fence", False)),
    "check_your_understanding": ((("check",), "check fence", True),),
}
_DUPLICATE_FIX = {
    "steps fence": ("keep one steps fence that totals the main result and give any other result its own "
                    "valued row, the chart or prose, never a second steps fence"),
    "chart fence": "keep at most one chart fence",
    "check fence": "keep one check fence with one question",
}


def tutorial_section_issues(sections: Mapping[str, str | None], *, case_has_numbers: bool = True) -> list[str]:
    """One issue per missing, duplicate or misplaced block and per defect of each block.

    ``case_has_numbers=False`` (the writer's package has no teaching-case data
    and no result bindings) rejects every steps value as an invented number.
    """
    issues = []
    for name, _ in PLAN_DETAIL_SECTION_ROWS:
        fences = native_fences(str(sections.get(name) or ""))
        expected = _REQUIRED.get(name, ())
        for kinds, label, required in expected:
            found = [(kind, body) for kind, body in fences if kind in kinds]
            if len(found) > 1 or (required and not found):
                fix = _DUPLICATE_FIX.get(label, "keep one primary visual and explain any other idea in prose")
                issues.append(f"{name} must include {'exactly' if required else 'at most'} one "
                              f"valid {label}; found {len(found)}" + (f": {fix}" if found else ""))
            # Every fence is checked, also when there are two of a kind, so
            # one correction can repair all of their lines at once.
            for index, (kind, body) in enumerate(found, 1):
                number = f" {index}" if len(found) > 1 else ""
                issues.extend(f"{name} {kind} fence{number} is invalid: {reason}"
                              for reason in fence_errors(kind, body, case_has_numbers=case_has_numbers))
        allowed = {kind for kinds, _, _ in expected for kind in kinds}
        for kind in sorted({kind for kind, _ in fences} - allowed):
            issues.append(f"{name} must not contain a {kind} fence")
    return issues


def _legacy_visual_issues(markdown: str) -> list[str]:
    for kind, body in native_fences(markdown):
        if kind in {"comparison", "diagram"} and fence_error(kind, body) is None:
            return []
    return [LEGACY_VISUAL_ISSUE]


def tutorial_visual_issues(markdown: str) -> list[str]:
    """Validate a rendered tutorial's native blocks.

    Lessons with a Guided Practice section (and fragments without canonical
    headings) keep the legacy rule: one valid comparison or diagram anywhere.
    New tutorials need one primary visual, one steps fence (plus an optional
    chart) and one check fence in their canonical sections.
    """
    sections = lesson_sections(markdown)
    if not sections or "guided_practice" in sections:
        return _legacy_visual_issues(markdown)
    return tutorial_section_issues(sections)
