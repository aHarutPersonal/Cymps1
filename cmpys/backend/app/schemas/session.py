"""Schemas for agentic session workflow."""

from datetime import datetime
from decimal import Decimal
from enum import Enum
from typing import Annotated, Any, Literal

from pydantic import (
    BaseModel,
    Field,
    StringConstraints,
    field_validator,
    model_validator,
)


class SessionPhaseSchema(str, Enum):
    """Session phase for API responses."""

    INTAKE = "intake"
    IDOL_SELECTION = "idol_selection"
    INTERVIEW = "interview"
    COMPARISON = "comparison"
    BLUEPRINT = "blueprint"
    GUIDED_LEARNING = "guided_learning"
    COMPLETED = "completed"


# =============================================================================
# Request Schemas
# =============================================================================


class SessionCreate(BaseModel):
    """Create a new agentic session (Phase 1: Intake)."""

    age: int = Field(..., ge=1, le=150, description="User's current age")
    financial_status: str = Field(
        ..., max_length=500, description="User's financial/life status description"
    )
    interests: list[str] = Field(
        ..., min_length=1, max_length=10, description="User's interest keywords"
    )
    goal: str | None = Field(
        None,
        max_length=200,
        description="The goal the user picked in onboarding (e.g. 'Build wealth')",
    )
    # Onboarding "Your situation" step: chips such as "I work full-time" or
    # "Evenings are best" (any short string is accepted) and an optional note.
    # Both are optional so app builds from before v3 keep creating sessions.
    situation: list[Annotated[str, StringConstraints(min_length=1, max_length=60)]] = (
        Field(
            default_factory=list,
            max_length=8,
            description="Situation chips the user picked in onboarding",
        )
    )
    situation_note: str | None = Field(
        None,
        max_length=500,
        description="Optional free-text note about the user's situation",
    )

    @field_validator("situation", mode="before")
    @classmethod
    def _clean_situation(cls, value):
        # null means "nothing picked"; chips are trimmed and single-spaced so
        # a stray space never fails the 1-60 character rule or splits a chip.
        if value is None:
            return []
        if isinstance(value, list):
            return [
                " ".join(item.split()) if isinstance(item, str) else item
                for item in value
            ]
        return value

    @field_validator("situation_note", mode="before")
    @classmethod
    def _clean_situation_note(cls, value):
        if isinstance(value, str):
            return value.strip() or None
        return value


class SelectIdolRequest(BaseModel):
    """Select an idol for the mentoring session."""

    idol_name: str = Field(..., max_length=200)
    wikidata_id: str | None = Field(None, max_length=20)


class InterviewMessageRequest(BaseModel):
    """Send a message during the interview phase."""

    content: str = Field(..., max_length=10000)
    # True for the hidden client protocol message that elicits the mentor's
    # opening question — it is not the user speaking, so it must not be
    # persisted into the transcript that comparison/blueprint later quote.
    is_kickoff: bool = False
    # Identifies the assistant question this answer belongs to. Older clients
    # may omit it; current clients use it to make retries idempotent when the
    # terminal SSE event is lost after the response was committed.
    question_id: str | None = Field(default=None, max_length=64)
    # True when the learner picked the "I don't have one yet" style option of a
    # text question. The answer text is sent as usual; the flag is stored on
    # the persisted answer so planning can tell missing evidence from none.
    missing_evidence: bool = False


InterviewOptionIcon = Literal[
    "list",
    "book",
    "edit",
    "headphones",
    "clock",
    "target",
    "users",
    "layers",
    "calendar",
    "sparkle",
]


class InterviewOptionDetail(BaseModel):
    """Optional description and icon shown beside one choice option.

    Details live in a list parallel to ``options`` so that ``options`` stays a
    plain ``list[str]`` that older clients keep parsing.
    """

    description: str | None = Field(default=None, max_length=90)
    icon: InterviewOptionIcon | None = None

    @field_validator("description", mode="before")
    @classmethod
    def _clean_description(cls, value):
        if isinstance(value, str):
            return " ".join(value.split()) or None
        return value


# Interview controls: the optional fields each kind owns. After validation every
# other kind-specific field is reset to its default, so a control never carries
# data that belongs to a different kind.
_KIND_FIELDS: dict[str, frozenset[str]] = {
    "text": frozenset({"suggestions", "missing_option"}),
    "single_choice": frozenset({"options", "option_details"}),
    "multi_choice": frozenset(
        {"options", "option_details", "min_selected", "max_selected"}
    ),
    "scale": frozenset({"min_value", "max_value", "step", "low_label", "high_label"}),
    "number": frozenset(
        {
            "min_value",
            "max_value",
            "step",
            "initial_value",
            "unit",
            "presets",
            "daily_hint",
        }
    ),
}
_KIND_SPECIFIC_FIELDS = frozenset().union(*_KIND_FIELDS.values())
_SCALE_BOUNDS = (1, 5, 1)  # min, max, step
# Payload keys a scale ignores; the server owns its range.
_SCALE_IGNORED_KEYS = frozenset(
    {"min", "max", "step", "initial", "min_value", "max_value", "initial_value", "unit"}
)


def _clean_text(raw: Any) -> str:
    return " ".join(str(raw).split()).strip()


def _normalize_choice_options(
    options: list[str],
    details: list[InterviewOptionDetail],
) -> tuple[list[str], list[InterviewOptionDetail]]:
    """Trim and deduplicate options, keeping ``details`` aligned with them."""
    if details and len(details) != len(options):
        raise ValueError("option_details must be empty or match options one to one")
    normalized: list[str] = []
    kept_details: list[InterviewOptionDetail] = []
    seen: set[str] = set()
    for index, raw in enumerate(options):
        option = _clean_text(raw)
        if not option or len(option) > 80:
            raise ValueError("choice options must be 1-80 characters")
        key = option.casefold()
        if key in seen:
            continue
        seen.add(key)
        normalized.append(option)
        if details:
            kept_details.append(details[index])
    return normalized, kept_details


class InterviewResponseInput(BaseModel):
    """Validated UI hint for answering one interview question.

    Choice and number selections are still submitted as natural-language
    content. Invalid model output is replaced with a text composer by the
    session endpoint before it reaches a client.
    """

    version: Literal[1] = 1
    kind: Literal["text", "single_choice", "multi_choice", "scale", "number"] = "text"
    placeholder: str | None = Field(default=None, max_length=100)
    options: list[str] = Field(default_factory=list, max_length=6)
    # Parallel to ``options`` (empty or the same length); choice kinds only.
    option_details: list[InterviewOptionDetail] = Field(
        default_factory=list,
        max_length=6,
    )
    # Text only: tappable starting points, and one "I have none" style option.
    suggestions: list[str] = Field(default_factory=list, max_length=4)
    missing_option: str | None = Field(default=None, max_length=60)
    # Scale only: captions for the two ends of the fixed 1-5 range.
    low_label: str | None = Field(default=None, max_length=40)
    high_label: str | None = Field(default=None, max_length=40)
    # Multi choice only: how many options may be selected.
    min_selected: int = Field(default=1, ge=1, le=6)
    max_selected: int | None = Field(default=None, ge=1, le=6)
    min_value: float | None = Field(
        default=None,
        alias="min",
        ge=-1_000_000,
        le=1_000_000,
        allow_inf_nan=False,
    )
    max_value: float | None = Field(
        default=None,
        alias="max",
        ge=-1_000_000,
        le=1_000_000,
        allow_inf_nan=False,
    )
    step: float | None = Field(
        default=None,
        gt=0,
        le=1000,
        allow_inf_nan=False,
    )
    initial_value: float | None = Field(
        default=None,
        alias="initial",
        ge=-1_000_000,
        le=1_000_000,
        allow_inf_nan=False,
    )
    unit: str | None = Field(default=None, max_length=40)
    # Number only: quick-pick values, and whether to show the daily-time hint.
    presets: list[
        Annotated[float, Field(ge=-1_000_000, le=1_000_000, allow_inf_nan=False)]
    ] = Field(default_factory=list, max_length=4)
    daily_hint: bool = False
    allow_custom: bool = True
    # Server-owned semantic binding for the answer. The model may suggest UI,
    # but the endpoint always overwrites this key with the required next input
    # before persistence, so clients cannot relabel an answer. The union of the
    # pre-v3 (8-key) and v3 (12-key) intake question sets.
    answer_key: (
        Literal[
            "achievement_inventory",
            "current_capability",
            "foundation_check",
            "application_check",
            "weekly_hours",
            "target_outcome",
            "constraints_resources",
            "learning_habits_support",
            "work_sample",
            "self_check_method",
            "skill_confidence",
            "practice_volume",
            "resources_capital",
            "network_support",
            "learning_preferences",
        ]
        | None
    ) = None

    diagnostic_id: str | None = Field(default=None, max_length=80)

    model_config = {"populate_by_name": True}

    @model_validator(mode="before")
    @classmethod
    def ignore_scale_bounds(cls, data):
        """A scale is always 1-5, so whatever bounds the model sent are moot."""
        if isinstance(data, dict) and data.get("kind") == "scale":
            return {k: v for k, v in data.items() if k not in _SCALE_IGNORED_KEYS}
        return data

    @model_validator(mode="after")
    def validate_kind_fields(self):
        """Keep generated controls small, coherent, and safe to render."""
        if self.kind in {"single_choice", "multi_choice"}:
            _validate_choice_fields(self)
        elif self.kind == "number":
            _validate_number_fields(self)
        elif self.kind == "scale":
            _validate_scale_fields(self)
        else:
            _validate_text_fields(self)

        owned = _KIND_FIELDS[self.kind]
        for name in _KIND_SPECIFIC_FIELDS - owned:
            setattr(self, name, _field_default(name))
        return self


def _field_default(name: str) -> Any:
    return InterviewResponseInput.model_fields[name].get_default(
        call_default_factory=True
    )


def _validate_choice_fields(control: InterviewResponseInput) -> None:
    options, details = _normalize_choice_options(
        control.options,
        control.option_details,
    )
    if not 2 <= len(options) <= 6:
        raise ValueError("choice controls require 2-6 unique options")
    control.options = options
    control.option_details = details
    control.allow_custom = True

    if control.kind != "multi_choice":
        return
    if control.min_selected > len(options):
        raise ValueError("min_selected cannot exceed the number of options")
    if control.max_selected is not None and not (
        control.min_selected <= control.max_selected <= len(options)
    ):
        raise ValueError(
            "max_selected must be between min_selected and the number of options"
        )


def _validate_number_fields(control: InterviewResponseInput) -> None:
    if control.min_value is None or control.max_value is None or control.step is None:
        raise ValueError("number controls require min, max, and step")
    if control.min_value >= control.max_value:
        raise ValueError("number control min must be below max")
    if control.initial_value is None:
        control.initial_value = control.min_value
    if not control.min_value <= control.initial_value <= control.max_value:
        raise ValueError("number control initial must be within its range")

    values = {
        "min": Decimal(str(control.min_value)),
        "max": Decimal(str(control.max_value)),
        "step": Decimal(str(control.step)),
        "initial": Decimal(str(control.initial_value)),
    }
    if any(
        max(0, -value.normalize().as_tuple().exponent) > 4 for value in values.values()
    ):
        raise ValueError("number controls support at most 4 decimal places")
    span = values["max"] - values["min"]
    if values["step"] > span or span % values["step"] != 0:
        raise ValueError("number control range must align to its step")
    if (values["initial"] - values["min"]) % values["step"] != 0:
        raise ValueError("number control initial must align to its step")
    if span / values["step"] > 200:
        raise ValueError("number controls may contain at most 200 steps")

    for preset in control.presets:
        value = Decimal(str(preset))
        if not values["min"] <= value <= values["max"]:
            raise ValueError("number control presets must be within its range")
        if (value - values["min"]) % values["step"] != 0:
            raise ValueError("number control presets must align to its step")
    control.allow_custom = True


def _validate_scale_fields(control: InterviewResponseInput) -> None:
    control.min_value, control.max_value, control.step = _SCALE_BOUNDS
    control.low_label = _clean_text(control.low_label or "") or None
    control.high_label = _clean_text(control.high_label or "") or None


def _validate_text_fields(control: InterviewResponseInput) -> None:
    suggestions = [_clean_text(raw) for raw in control.suggestions]
    if any(not item or len(item) > 60 for item in suggestions):
        raise ValueError("text suggestions must be 1-60 characters")
    control.suggestions = suggestions
    control.missing_option = _clean_text(control.missing_option or "") or None


class LearningTopicRequest(BaseModel):
    """Request a Socratic learning session on a topic."""

    topic: str = Field(..., max_length=200)
    level: str | None = Field(default=None, max_length=80)
    language: str | None = Field(default=None, max_length=40)


class GuidedLearningMessageRequest(BaseModel):
    """Send a message during the guided learning phase."""

    content: str = Field(..., max_length=10000)


# =============================================================================
# Response Schemas
# =============================================================================


class SelectedIdolInfo(BaseModel):
    """Idol info embedded in session response."""

    id: str
    name: str
    era: str | None = None

    model_config = {"from_attributes": True}


class SessionResponse(BaseModel):
    """Full session state response."""

    id: str
    phase: SessionPhaseSchema
    user_age: int
    user_financial_status: str
    user_interests: list[str]
    user_goal: str | None = None
    selected_idol: SelectedIdolInfo | None = None
    interview_turn_count: int = 0
    comparison_output: str | None = None
    blueprint_output: str | None = None
    # The Flutter client contract intentionally uses this camelCase key.
    # Declaring the alias is essential: FastAPI filters endpoint dictionaries
    # through this response model and otherwise silently drops generated
    # comparison scores even when they are present in the database.
    comparison_scores: dict[str, Any] | None = Field(
        default=None,
        alias="comparisonScores",
    )
    comparison_scores_status: str = Field(
        default="not_started",
        alias="comparisonScoresStatus",
    )
    comparison_scores_retryable: bool = Field(
        default=False,
        alias="comparisonScoresRetryable",
    )
    interview_thread_id: str | None = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True, "populate_by_name": True}


class IdolSuggestionItem(BaseModel):
    """A single idol suggestion."""

    name: str
    era: str
    relevance_summary: str
    wikidata_id: str | None = None
    image_url: str | None = None
    domains: list[str] = Field(default_factory=list)
    confidence: float = Field(ge=0.0, le=1.0, default=0.8)


class IdolSuggestionsResponse(BaseModel):
    """Response with 3 idol suggestions."""

    suggestions: list[IdolSuggestionItem]


class LearningMaterialResponse(BaseModel):
    """A fetched learning resource (article or video)."""

    title: str
    url: str
    type: str = Field(description="'article' or 'video'")
    summary: str
    content_resource_id: str | None = None
    canonical_key: str | None = None
    license_status: str | None = None
    thumbnail_url: str | None = None
    duration_minutes: int | None = None


class LearningMaterialsResponse(BaseModel):
    """Response for fetching learning materials based on a topic."""

    materials: list[LearningMaterialResponse]


class DailyInsightResponse(BaseModel):
    """A single bite-sized insight (Idea Card)."""

    title: str
    content: str
    category: str


class DailyFeedResponse(BaseModel):
    """Daily feed of insights."""

    insights: list[DailyInsightResponse]
