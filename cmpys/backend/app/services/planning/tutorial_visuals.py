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
