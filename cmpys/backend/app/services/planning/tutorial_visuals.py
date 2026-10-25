"""Validate a small subset of native reader visuals before tutorial publication.

The independent reviewer still checks whether the visual teaches the concept.
No remote image download or extra media-generation request is needed.
"""
from __future__ import annotations

import re

_FENCE = re.compile(r"^```(comparison|diagram)\s*\n(.*?)^```\s*$", re.M | re.S)
_BAD = re.compile(r"[{};]|=>|<[^>]+>")


def tutorial_visual_issues(markdown: str) -> list[str]:
    for kind, body in _FENCE.findall(markdown):
        if _BAD.search(body):
            continue
        lines = [line.strip() for line in body.splitlines() if line.strip()]
        if kind == "comparison":
            separators = [i for i, line in enumerate(lines) if line.casefold() in {"vs", "versus"}]
            if len(separators) != 1:
                continue
            split = separators[0]
            groups = (lines[:split], lines[split + 1:])
            if all(3 <= len(group) <= 13 and len(group[0]) <= 100
                   and re.search(r"[A-Za-z]", group[0])
                   and all(re.fullmatch(r"(?:[-•]|\d+[.)])\s+\S.*", item) for item in group[1:])
                   for group in groups):
                return []
        else:
            # Deliberately restrict generated diagrams to a native vertical
            # chain. Complex geometry belongs to the reviewed practice package.
            raw = [line.rstrip() for line in body.splitlines() if line.strip()]
            nodes = [i for i, line in enumerate(raw) if re.fullmatch(r"\[[^\[\]]{1,80}\]", line.strip())]
            if 2 <= len(nodes) <= 6 and nodes[0] == 0 and nodes[-1] == len(raw) - 1:
                valid = True
                for a, b in zip(nodes, nodes[1:]):
                    connectors = raw[a + 1:b]
                    if (not connectors or not all(re.fullmatch(r"\s*[│▼↓]\s*", line) for line in connectors)
                            or not any("▼" in line or "↓" in line for line in connectors)
                            or len({len(line) - len(line.lstrip()) for line in connectors}) != 1):
                        valid = False
                if valid:
                    return []
    return ["tutorial must include a valid native comparison or diagram illustrating its concept"]
