"""Which model serves each operation (owner decision, 2026-11-07).

Every structured or streamed generation names an operation. Its stage picks
the primary provider; the other direct provider is always the backup, used
only when the primary cannot serve a call (provider error, rate limit, out of
credit). A tutorial never mixes models inside one attempt: its whole-attempt
retry (``TUTORIAL_FRESH_ATTEMPTS``) runs on the other model instead.

Gemini is not routed here: it serves only Google Search grounded lookups and
audiobook narration.

``LLM_ROUTE_OVERRIDES`` switches a stage or a single operation, e.g.
``{"books": "anthropic"}`` or ``{"book_fidelity_review": "anthropic"}``.
"""

from contextlib import contextmanager
from contextvars import ContextVar

ANTHROPIC = "anthropic"  # Claude Haiku 5.5
OPENAI = "openai"  # gpt-6-luna

# Evidence: BENCHMARK-RESULT.md, "Per-stage model eval" (2026-11-07).
STAGE_PRIMARY = {
    "tutorial": ANTHROPIC,  # 16/16 tutorials against 14/16
    "plan": ANTHROPIC,  # mission outline 6/6 each; week plan 3/3 against 2/3
    "interview": OPENAI,  # owner's choice; intake prompts accept 2/3 against 0/3
    "mentor_chat": OPENAI,  # owner's choice
    "comparison": OPENAI,  # comparison (owner), blueprint and scores follow it
    "practice": OPENAI,  # grading 59/60 against 60/60, and faster
    "books": OPENAI,  # not evaluated; switchable
    "idols": OPENAI,  # catalog extraction; not evaluated; switchable
    "default": OPENAI,  # every operation not listed below
}

OPERATION_STAGES = {
    # The tutorial pipeline: seed, activities, preflight reviews, writer,
    # lesson review and repairs all run under this one operation.
    "plan_item_detail_generation": "tutorial",
    "plan_item_tutorial_outline": "plan",
    "plan_backbone_generation": "plan",
    "plan_backbone_targeted_repair": "plan",
    "plan_week_generation": "plan",
    "interview_stream": "interview",
    "guided_learning_stream": "mentor_chat",
    "comparison_stream": "comparison",
    "blueprint_stream": "comparison",
    "comparison_scores": "comparison",
    "comparison_analysis": "comparison",
    "lesson_practice_review": "practice",
    "lesson_practice_generate": "practice",
    "lesson_book_idea_match": "books",
}
# Families recorded under their own operation names (tutorial repairs and
# retries, book guides and companions, idol catalog extraction).
_STAGE_PREFIXES = (("lesson_package_", "tutorial"), ("lesson_review_", "tutorial"),
                   ("book_", "books"), ("idol_", "idols"))


def other_provider(provider: str) -> str:
    return OPENAI if provider == ANTHROPIC else ANTHROPIC


def stage_for(operation: str | None) -> str:
    if operation in OPERATION_STAGES:
        return OPERATION_STAGES[operation]
    for prefix, stage in _STAGE_PREFIXES:
        if operation and operation.startswith(prefix):
            return stage
    return "default"


def route_for(operation: str | None) -> tuple[str, str]:
    """``(primary, backup)`` providers for ``operation``."""
    from app.core.config import settings

    stage = stage_for(operation)
    overrides = settings.llm_route_overrides
    primary = overrides.get(operation or "") or overrides.get(stage) or STAGE_PRIMARY[stage]
    return primary, other_provider(primary)


def tutorial_attempt_provider(fresh_attempt: int) -> str:
    """A tutorial's first attempt runs on its primary; each fresh attempt switches."""
    primary, backup = route_for("plan_item_detail_generation")
    return primary if fresh_attempt % 2 == 0 else backup


_attempt_provider: ContextVar[str | None] = ContextVar("tutorial_attempt_provider", default=None)


@contextmanager
def tutorial_attempt(fresh_attempt: int):
    """Bind every client the tutorial pipeline builds in this attempt to one model."""
    token = _attempt_provider.set(tutorial_attempt_provider(fresh_attempt))
    try:
        yield
    finally:
        _attempt_provider.reset(token)


def current_tutorial_provider() -> str | None:
    return _attempt_provider.get()
