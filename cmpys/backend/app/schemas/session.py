"""Schemas for agentic session workflow."""
from datetime import datetime
from decimal import Decimal
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator


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
        ..., max_length=500,
        description="User's financial/life status description"
    )
    interests: list[str] = Field(
        ..., min_length=1, max_length=10,
        description="User's interest keywords"
    )
    goal: str | None = Field(
        None, max_length=200,
        description="The goal the user picked in onboarding (e.g. 'Build wealth')"
    )


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


class InterviewResponseInput(BaseModel):
    """Validated UI hint for answering one interview question.

    Choice and number selections are still submitted as natural-language
    content. Invalid model output is replaced with a text composer by the
    session endpoint before it reaches a client.
    """

    version: Literal[1] = 1
    kind: Literal["text", "single_choice", "number"] = "text"
    placeholder: str | None = Field(default=None, max_length=100)
    options: list[str] = Field(default_factory=list, max_length=6)
    min_value: float | None = Field(
        default=None, alias="min", ge=-1_000_000, le=1_000_000,
        allow_inf_nan=False,
    )
    max_value: float | None = Field(
        default=None, alias="max", ge=-1_000_000, le=1_000_000,
        allow_inf_nan=False,
    )
    step: float | None = Field(
        default=None, gt=0, le=1000, allow_inf_nan=False,
    )
    initial_value: float | None = Field(
        default=None, alias="initial", ge=-1_000_000, le=1_000_000,
        allow_inf_nan=False,
    )
    unit: str | None = Field(default=None, max_length=40)
    allow_custom: bool = True
    # Server-owned semantic binding for the answer. The model may suggest UI,
    # but the endpoint always overwrites this key with the required next input
    # before persistence, so clients cannot relabel an answer.
    answer_key: Literal[
        "achievement_inventory",
        "current_capability",
        "weekly_hours",
        "target_outcome",
        "constraints_resources",
        "learning_habits_support",
    ] | None = None

    model_config = {"populate_by_name": True}

    @model_validator(mode="after")
    def validate_kind_fields(self):
        """Keep generated controls small, coherent, and safe to render."""
        if self.kind == "single_choice":
            normalized: list[str] = []
            seen: set[str] = set()
            for raw in self.options:
                option = " ".join(str(raw).split()).strip()
                if not option or len(option) > 80:
                    raise ValueError("choice options must be 1-80 characters")
                key = option.casefold()
                if key in seen:
                    continue
                seen.add(key)
                normalized.append(option)
            if not 2 <= len(normalized) <= 6:
                raise ValueError("choice controls require 2-6 unique options")
            self.options = normalized
            self.allow_custom = True
            return self

        if self.kind == "number":
            if self.min_value is None or self.max_value is None or self.step is None:
                raise ValueError("number controls require min, max, and step")
            if self.min_value >= self.max_value:
                raise ValueError("number control min must be below max")
            if self.initial_value is None:
                self.initial_value = self.min_value
            if not self.min_value <= self.initial_value <= self.max_value:
                raise ValueError("number control initial must be within its range")

            values = {
                "min": Decimal(str(self.min_value)),
                "max": Decimal(str(self.max_value)),
                "step": Decimal(str(self.step)),
                "initial": Decimal(str(self.initial_value)),
            }
            if any(
                max(0, -value.normalize().as_tuple().exponent) > 4
                for value in values.values()
            ):
                raise ValueError("number controls support at most 4 decimal places")
            span = values["max"] - values["min"]
            if values["step"] > span or span % values["step"] != 0:
                raise ValueError("number control range must align to its step")
            if (values["initial"] - values["min"]) % values["step"] != 0:
                raise ValueError("number control initial must align to its step")
            if span / values["step"] > 200:
                raise ValueError("number controls may contain at most 200 steps")
            self.options = []
            self.allow_custom = True
            return self

        self.options = []
        self.min_value = None
        self.max_value = None
        self.step = None
        self.initial_value = None
        self.unit = None
        return self

class LearningTopicRequest(BaseModel):
    """Request a Socratic learning session on a topic."""
    
    topic: str = Field(..., max_length=200)

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
