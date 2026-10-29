"""One-ahead tutorial generation: the learner's current tutorial and the next.

A tutorial mission never has more than two tutorials generated ahead of the
learner: the first step without a completion (current) and the step after it
(next). Later tutorials are written only as the learner advances. A job that
has written its window parks as ``completed`` / ``waiting_for_learner``; the
next completion re-queues that same job so the artifact identity (and with it
completion history and private practice) never changes.
"""
from __future__ import annotations

from collections.abc import Collection, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

TUTORIAL_LESSON_FORMAT = "tutorial_v1"
WAITING_FOR_LEARNER_STEP = "waiting_for_learner"
PARKED_JOB_STATUS = "completed"
# One automatic background retry per window tutorial, per job.
WINDOW_RETRY_LIMIT = 1
ACTIVE_JOB_STATUSES = frozenset({"pending", "queued", "running"})


@dataclass(frozen=True)
class GenerationWindow:
    current_step_id: str | None
    next_step_id: str | None

    @property
    def step_ids(self) -> tuple[str, ...]:
        return tuple(step_id for step_id in (self.current_step_id, self.next_step_id) if step_id)

    def missing(self, ready_step_ids: Collection[str]) -> list[str]:
        ready = {str(step_id) for step_id in ready_step_ids}
        return [step_id for step_id in self.step_ids if step_id not in ready]


def generation_window(step_ids: Sequence[str], completed_step_ids: Collection[str]) -> GenerationWindow:
    """Current = first step without a completion; next = the step after it."""
    completed = {str(step_id) for step_id in completed_step_ids}
    ordered = [str(step_id) for step_id in step_ids]
    for index, step_id in enumerate(ordered):
        if step_id not in completed:
            return GenerationWindow(step_id, ordered[index + 1] if index + 1 < len(ordered) else None)
    return GenerationWindow(None, None)


def details_are_tutorial(details_json: Any) -> bool:
    if not isinstance(details_json, Mapping):
        return False
    if details_json.get("lesson_format") == TUTORIAL_LESSON_FORMAT:
        return True
    generation = details_json.get("_generation")
    outline = generation.get("outline") if isinstance(generation, Mapping) else None
    return isinstance(outline, Mapping) and outline.get("lesson_format") == TUTORIAL_LESSON_FORMAT


def job_is_parked(job: Any) -> bool:
    return (job is not None and getattr(job, "status", None) == PARKED_JOB_STATUS
            and getattr(job, "step", None) == WAITING_FOR_LEARNER_STEP)


def window_requeue_decision(
    *,
    window: GenerationWindow,
    ready_step_ids: Collection[str],
    latest_job: Any,
    artifact_job_id: str | None,
) -> str:
    """``none``, ``reuse`` (an active job already owns the item) or ``requeue``.

    Only the artifact's own parked job is re-queued; a failed job keeps its
    error for the learner, and a newer job owns the item itself.
    """
    if not window.missing(ready_step_ids) or latest_job is None:
        return "none"
    if getattr(latest_job, "status", None) in ACTIVE_JOB_STATUSES:
        return "reuse"
    if artifact_job_id is None or str(getattr(latest_job, "id", "")) != str(artifact_job_id):
        return "none"
    return "requeue" if job_is_parked(latest_job) else "none"


def window_queue(window: GenerationWindow, ready_step_ids: Collection[str]) -> str:
    """The learner is waiting only when their current tutorial is missing."""
    return "default" if window.current_step_id in window.missing(ready_step_ids) else "low_priority"


def window_response(
    *,
    step_ids: Sequence[str],
    ready_step_ids: Collection[str],
    completed_step_ids: Collection[str],
    job_active: bool,
) -> dict[str, Any]:
    """The ``generation_window`` contract of the detailed response."""
    window = generation_window(step_ids, completed_step_ids)
    ready = {str(step_id) for step_id in ready_step_ids}
    remaining_by_design = any(str(step_id) not in ready for step_id in step_ids)
    return {
        "current_step_id": window.current_step_id,
        "next_step_id": window.next_step_id,
        "waiting_for_learner": bool(
            window.step_ids and not window.missing(ready) and remaining_by_design and not job_active
        ),
    }
