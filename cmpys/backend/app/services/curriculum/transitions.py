"""Pure state-machine helpers for resumable curriculum jobs."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class PipelineStage(str, Enum):
    """Values intentionally match ``app.models.curriculum.GenerationStage``."""

    TAXONOMY = "taxonomy"
    SOURCE_RESEARCH = "source_research"
    TECHNIQUE_DESIGN = "technique_design"
    OUTLINE = "outline"
    WRITING = "writing"
    FACTUAL_REVIEW = "factual_review"
    PEDAGOGY_REVIEW = "pedagogy_review"
    ORIGINALITY_REVIEW = "originality_review"
    PUBLISH = "publish"


class PipelineState(str, Enum):
    QUEUED = "queued"
    COMPLETED = "completed"
    FLAGGED = "flagged"


PIPELINE_VERSION = "curriculum-pipeline-v1"
PROMPT_VERSION = "curriculum-prompts-v1"


@dataclass(frozen=True, slots=True)
class Transition:
    stage: PipelineStage
    repair_attempts: int
    state: PipelineState = PipelineState.QUEUED
    reason: str | None = None

    @property
    def terminal(self) -> bool:
        return self.state in {PipelineState.COMPLETED, PipelineState.FLAGGED}


_SUCCESS_NEXT = {
    PipelineStage.TAXONOMY: PipelineStage.SOURCE_RESEARCH,
    PipelineStage.SOURCE_RESEARCH: PipelineStage.TECHNIQUE_DESIGN,
    PipelineStage.TECHNIQUE_DESIGN: PipelineStage.OUTLINE,
    PipelineStage.OUTLINE: PipelineStage.WRITING,
    PipelineStage.WRITING: PipelineStage.FACTUAL_REVIEW,
    PipelineStage.FACTUAL_REVIEW: PipelineStage.PEDAGOGY_REVIEW,
    PipelineStage.PEDAGOGY_REVIEW: PipelineStage.ORIGINALITY_REVIEW,
    PipelineStage.ORIGINALITY_REVIEW: PipelineStage.PUBLISH,
}


def transition_after_success(
    stage: PipelineStage,
    *,
    repair_attempts: int,
) -> Transition:
    if stage == PipelineStage.PUBLISH:
        return Transition(
            PipelineStage.PUBLISH,
            repair_attempts,
            state=PipelineState.COMPLETED,
        )
    if stage in _SUCCESS_NEXT:
        return Transition(_SUCCESS_NEXT[stage], repair_attempts)
    raise ValueError(f"stage {stage.value} cannot transition after success")


def transition_after_gate_failure(
    stage: PipelineStage,
    *,
    repair_attempts: int,
    max_repairs: int,
) -> Transition:
    if stage not in {
        PipelineStage.WRITING,
        PipelineStage.FACTUAL_REVIEW,
        PipelineStage.PEDAGOGY_REVIEW,
        PipelineStage.ORIGINALITY_REVIEW,
        PipelineStage.PUBLISH,
    }:
        raise ValueError("only writing/review gates may request a targeted repair")
    if repair_attempts >= max(0, max_repairs):
        return Transition(
            stage,
            repair_attempts,
            state=PipelineState.FLAGGED,
            reason="quality_gate_exhausted",
        )
    return Transition(PipelineStage.WRITING, repair_attempts + 1)


def retry_delay_seconds(attempts: int) -> int:
    """One minute exponential backoff, capped at one hour."""
    return min(60 * (2 ** max(attempts - 1, 0)), 60 * 60)


def is_terminal_state(state: PipelineState) -> bool:
    return state in {PipelineState.COMPLETED, PipelineState.FLAGGED}
