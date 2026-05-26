"""Schemas for development plans."""
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field


class PlanItemType(str, Enum):
    HABIT = "habit"
    PROJECT = "project"
    READING = "reading"
    COURSE = "course"
    PRACTICE = "practice"
    REFLECTION = "reflection"


class PlanItemStatus(str, Enum):
    NOT_STARTED = "not_started"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    SKIPPED = "skipped"


class PlanGenerateRequest(BaseModel):
    """Request to generate a new plan."""
    
    idolId: str
    targetAge: int = Field(..., ge=1, le=150)
    durationWeeks: int = Field(default=12, ge=1, le=52)
    weeklyHours: int = Field(default=10, ge=1, le=168)
    focus: str | None = Field(default=None, max_length=200)


class PlanItemUpdate(BaseModel):
    """Update a plan item."""
    
    status: PlanItemStatus | None = None
    progressPercent: int | None = Field(None, ge=0, le=100)
    notes: str | None = Field(None, max_length=5000)


class PlanItemCreate(BaseModel):
    """Request to create a plan item manually."""

    title: str = Field(..., min_length=1, max_length=200)
    description: str = Field(..., min_length=10)
    type: PlanItemType = PlanItemType.PROJECT
    weekStart: int | None = Field(None, ge=1)
    weekEnd: int | None = Field(None, ge=1)
    estimatedHours: int = Field(default=1, ge=0)
    successMetric: str = Field(default="Completed as planned", max_length=300)
    dailyInstructions: str | None = Field(default=None, max_length=2000)


class PlanItemResponse(BaseModel):
    """Plan item response."""
    
    id: str
    planId: str
    title: str
    type: PlanItemType
    description: str
    weekStart: int
    weekEnd: int
    successMetric: str
    estimatedHours: int
    status: PlanItemStatus
    progressPercent: int
    notes: str | None = None
    resourceTitle: str | None = None
    resourceUrl: str | None = None
    createdAt: datetime
    updatedAt: datetime

    model_config = {"from_attributes": True}


class PlanResponse(BaseModel):
    """Plan response with items."""
    
    id: str
    userId: str
    idolId: str | None = None
    idolName: str | None = None
    targetAge: int
    durationWeeks: int
    weeklyHours: int
    items: list[PlanItemResponse] = []
    createdAt: datetime
    
    # Roadmap-level data from plan_generate.txt
    roadmapThesis: str | None = None
    antiGoals: list[str] = []
    
    # Computed fields
    totalItems: int = 0
    completedItems: int = 0
    overallProgress: float = 0.0

    model_config = {"from_attributes": True}


# =============================================================================
# Plan Item Details & Progress
# =============================================================================

class StepDetail(BaseModel):
    """A single step within a plan item."""
    id: str
    title: str
    description: str | None = None
    # Additional fields from LLM prompt schema
    expected_output: str | None = None  # Artifact/deliverable for this step
    estimate_minutes: int | None = None  # Estimated time for this step
    order: int | None = None  # Step order (1-based)
    resources: list[str] | None = None  # Material IDs referenced by this step
    substeps: list[str] | None = None  # Tactical sub-actions
    lesson_content: str | None = None  # Full markdown lesson for this step


class BookIdeaDetail(BaseModel):
    """A single Deepstash-style idea card from a book."""
    title: str
    content: str
    category: str = "Mindset"


class MaterialDetail(BaseModel):
    """A material/resource for a plan item."""
    title: str
    url: str | None = None
    type: str | None = None  # e.g., "book", "article", "video", "in_app_lesson"
    content_resource_id: str | None = None  # Shared content_resources.id
    canonical_key: str | None = None  # Stable shared-resource key
    author_or_creator: str | None = None
    thumbnail_url: str | None = None
    license_status: str | None = None
    search_query: str | None = None
    # Additional fields from LLM prompt schema
    content_markdown: str | None = None  # In-app lesson content
    duration_minutes: int | None = None  # Estimated duration
    reason: str | None = None  # Why this material helps
    ideas: list[BookIdeaDetail] | None = None  # Deepstash-style idea cards


class ItemDetails(BaseModel):
    """Detailed steps and materials for a plan item."""
    steps: list[StepDetail] = []
    materials: list[MaterialDetail] = []
    generated_from_prompt_version: str | None = None
    generated_at: str | None = None


class ItemProgress(BaseModel):
    """Progress tracking for a plan item."""
    completed_steps: int = 0
    total_steps: int = 0
    percent: float = 0.0


class DetailsStatus(str, Enum):
    """Status of plan item details generation."""
    AVAILABLE = "available"
    PENDING = "pending"
    GENERATING = "generating"
    FAILED = "failed"


class PlanItemDetailedResponse(BaseModel):
    """Extended plan item response with details and progress."""
    item: PlanItemResponse
    details: ItemDetails | None = None
    progress: ItemProgress
    completed: bool = False
    # Details generation status
    details_status: DetailsStatus = DetailsStatus.AVAILABLE
    job_id: str | None = None


class ToggleCompleteResponse(BaseModel):
    """Response for toggling item completion."""
    completed: bool
    progress: ItemProgress


class ToggleStepResponse(BaseModel):
    """Response for toggling step completion."""
    step_id: str
    completed: bool
    progress: ItemProgress
    item_completed: bool


class RegenerateDetailsResponse(BaseModel):
    """Response for regenerate details request."""
    job_id: str


class WeekSummaryResponse(BaseModel):
    """Summary of a plan week."""
    week: int
    completed_items: int
    total_items: int
    percent: float
