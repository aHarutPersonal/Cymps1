"""Pydantic schemas for intake questionnaires."""
from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


# =============================================================================
# Question Types (matching prompt output)
# =============================================================================


class QuestionType(str, Enum):
    """Types of questions that can be rendered in the UI."""
    TEXT = "text"
    MULTILINE = "multiline"
    SINGLE_CHOICE = "single_choice"
    MULTI_CHOICE = "multi_choice"
    SCALE = "scale"


class QuestionCategory(str, Enum):
    """Categories for grouping questions."""
    ACHIEVEMENTS = "achievements"
    SKILLS = "skills"
    CONSTRAINTS = "constraints"
    GOALS = "goals"
    PREFERENCES = "preferences"
    RISK = "risk"
    RESOURCES = "resources"


class QuestionValidation(BaseModel):
    """Validation rules for a question."""
    min_len: int | None = None
    max_len: int | None = None
    min_value: int | None = None  # For scale questions
    max_value: int | None = None  # For scale questions


class Question(BaseModel):
    """
    A single intake question.
    
    Designed to be easily rendered by Flutter:
    - Simple types that map to UI widgets
    - Optional fields for flexibility
    """
    id: str = Field(..., description="Unique question identifier (e.g., 'q1', 'weekly_hours')")
    title: str = Field(..., description="Short title for the question")
    prompt: str = Field(..., description="Full question text/instructions")
    type: QuestionType = Field(..., description="Question type for UI rendering")
    required: bool = Field(default=True, description="Whether an answer is required")
    options: list[str] | None = Field(default=None, description="Options for choice questions")
    placeholder: str | None = Field(default=None, description="Placeholder text for input fields")
    validation: QuestionValidation | None = Field(default=None, description="Validation rules")
    category: QuestionCategory = Field(..., description="Question category for grouping")
    mapping_hint: str = Field(..., description="Hint for mapping answer to user profile field")


# =============================================================================
# Request Schemas
# =============================================================================


class IntakeStartRequest(BaseModel):
    """Request to start an intake session."""
    idol_id: str = Field(..., alias="idolId", description="UUID of the idol to compare against")
    target_age: int | None = Field(default=None, alias="targetAge", description="User's target age for comparison")
    
    class Config:
        populate_by_name = True


class IntakeAnswerRequest(BaseModel):
    """Request to submit an answer to a question."""
    question_id: str = Field(..., alias="questionId", description="ID of the question being answered")
    answer: Any = Field(..., description="The answer value (string, list, number, etc.)")
    
    class Config:
        populate_by_name = True


# =============================================================================
# Response Schemas
# =============================================================================


class IntakeStartResponse(BaseModel):
    """Response after starting an intake session."""
    session_id: str = Field(..., alias="sessionId")
    questions: list[Question]
    
    class Config:
        populate_by_name = True


class IntakeAnswerResponse(BaseModel):
    """Response after submitting an answer."""
    ok: bool = True


class IntakeFinishResponse(BaseModel):
    """Response after finishing intake (triggers plan generation job)."""
    job_id: str = Field(..., alias="jobId")
    
    class Config:
        populate_by_name = True


class AnswerDetail(BaseModel):
    """Detail of a single answer in session status."""
    question_id: str = Field(..., alias="questionId")
    answer: Any
    created_at: datetime = Field(..., alias="createdAt")
    
    class Config:
        populate_by_name = True


class IntakeSessionStatus(str, Enum):
    """Status enum for API response."""
    DRAFT = "draft"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"


class IntakeSessionResponse(BaseModel):
    """Full session status response."""
    session_id: str = Field(..., alias="sessionId")
    idol_id: str = Field(..., alias="idolId")
    status: IntakeSessionStatus
    questions: list[Question]
    answers: list[AnswerDetail]
    created_at: datetime = Field(..., alias="createdAt")
    updated_at: datetime = Field(..., alias="updatedAt")
    
    class Config:
        populate_by_name = True


# =============================================================================
# LLM Response Schemas (for parsing LLM output)
# =============================================================================


class QuestionsGenerateResponse(BaseModel):
    """Response from questions generation LLM call."""
    questions: list[Question]


class SkillLevel(str, Enum):
    """Skill proficiency level."""
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"


class SkillEntry(BaseModel):
    """A skill with level and evidence."""
    name: str
    level: SkillLevel
    evidence: str | None = None


class UserProfilePatch(BaseModel):
    """Patch to apply to user profile from intake answers."""
    weekly_hours: int | None = None
    goals: list[str] = Field(default_factory=list)
    interests: list[str] = Field(default_factory=list)
    domains: list[str] = Field(default_factory=list)
    constraints: list[str] = Field(default_factory=list)
    learning_preferences: list[str] = Field(default_factory=list)
    skills: list[SkillEntry] = Field(default_factory=list)
    achievements_raw: str | None = None


class DatePrecision(str, Enum):
    """Precision of a date."""
    DAY = "day"
    MONTH = "month"
    YEAR = "year"
    UNKNOWN = "unknown"


class AchievementCategory(str, Enum):
    """Achievement category."""
    CAREER = "career"
    LEARNING = "learning"
    FINANCE = "finance"
    IMPACT = "impact"
    MINDSET = "mindset"
    OTHER = "other"


class StructuredAchievement(BaseModel):
    """An achievement extracted from intake answers."""
    title: str
    description: str | None = None
    category: AchievementCategory = AchievementCategory.OTHER
    date: str | None = None  # YYYY-MM-DD format or null
    date_precision: DatePrecision = DatePrecision.UNKNOWN
    confidence: float = Field(default=0.7, ge=0.0, le=1.0)


class ReadinessByGap(BaseModel):
    """Readiness level for each gap category."""
    career: SkillLevel = SkillLevel.BEGINNER
    learning: SkillLevel = SkillLevel.BEGINNER
    finance: SkillLevel = SkillLevel.BEGINNER
    impact: SkillLevel = SkillLevel.BEGINNER
    mindset: SkillLevel = SkillLevel.BEGINNER
    other: SkillLevel = SkillLevel.BEGINNER


class IntakeNormalizeResponse(BaseModel):
    """Response from intake answers normalization LLM call."""
    user_profile_patch: UserProfilePatch
    structured_achievements: list[StructuredAchievement] = Field(default_factory=list)
    readiness_by_gap: ReadinessByGap
