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
    if draft.session_workbooks:
        expected = [block.block_id for block in blocks]
        actual = [block_id for session in draft.session_workbooks for block_id in session.block_ids]
        if actual != expected:
            raise SessionPackingError("Practice sessions must cover every block exactly once in teaching order")
        by_id = {block.block_id: block for block in blocks}
        sessions = tuple(tuple(by_id[block_id] for block_id in session.block_ids) for session in draft.session_workbooks)
        for session in sessions:
            minutes = sum(block.minutes for block in session)
            if not MIN_SESSION_MINUTES <= minutes <= MAX_SESSION_MINUTES:
                raise SessionPackingError("Each declared practice session must contain 40–60 minutes of whole blocks")
        return sessions

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
