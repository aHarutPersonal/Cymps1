"""Deterministically partition semantic lesson blocks into honest sessions."""

from __future__ import annotations

from functools import lru_cache

from app.services.curriculum.schemas import CanonicalModuleDraft, LessonBlock


MIN_SESSION_MINUTES = 40
MAX_SESSION_MINUTES = 60


class SessionPackingError(ValueError):
    pass


def pack_session_blocks(
    draft: CanonicalModuleDraft,
) -> tuple[tuple[LessonBlock, ...], ...]:
    """Find a contiguous 40–60 minute partition without splitting a block."""
    blocks = tuple(draft.blocks)

    @lru_cache(maxsize=None)
    def solve(start: int) -> tuple[tuple[int, int], ...] | None:
        if start == len(blocks):
            return ()
        minutes = 0
        for end in range(start, len(blocks)):
            minutes += blocks[end].minutes
            if minutes > MAX_SESSION_MINUTES:
                break
            if minutes < MIN_SESSION_MINUTES:
                continue
            suffix = solve(end + 1)
            if suffix is not None:
                return ((start, end + 1), *suffix)
        return None

    partition = solve(0)
    if partition is None:
        totals = [block.minutes for block in blocks]
        raise SessionPackingError(
            "module blocks cannot be partitioned into contiguous 40–60 minute "
            f"sessions without splitting semantic blocks: {totals}"
        )
    return tuple(tuple(blocks[start:end]) for start, end in partition)
