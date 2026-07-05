"""Schemas for agentic session workflow."""
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field


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
    interview_thread_id: str | None = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class IdolSuggestionItem(BaseModel):
    """A single idol suggestion."""
    
    name: str
    era: str
    relevance_summary: str
    wikidata_id: str | None = None
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
