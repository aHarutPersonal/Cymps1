"""
Pydantic schemas for LLM extraction outputs.

These models match the JSON schemas defined in the prompt templates
and are used to validate LLM responses.
"""
import datetime
from enum import Enum

from pydantic import BaseModel, Field


# =============================================================================
# Common Types
# =============================================================================


class DatePrecision(str, Enum):
    DAY = "day"
    MONTH = "month"
    YEAR = "year"
    UNKNOWN = "unknown"


class AchievementCategory(str, Enum):
    CAREER = "career"
    LEARNING = "learning"
    FINANCE = "finance"
    IMPACT = "impact"
    MINDSET = "mindset"
    OTHER = "other"


class ImportanceHint(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class MilestoneMode(str, Enum):
    EXACT = "exact"
    UP_TO = "up_to"


class ResourceKind(str, Enum):
    BOOK = "book"
    COURSE = "course"
    ARTICLE = "article"
    NONE = "none"


class PlanItemType(str, Enum):
    HABIT = "habit"
    PROJECT = "project"
    READING = "reading"
    COURSE = "course"
    PRACTICE = "practice"
    REFLECTION = "reflection"


# =============================================================================
# Evidence
# =============================================================================


class Evidence(BaseModel):
    """Evidence snippet from source text."""
    
    source_id: str
    chunk_index: int = Field(ge=0)
    source_url: str
    snippet: str = Field(max_length=500)
    confidence: float = Field(ge=0.0, le=1.0)


# =============================================================================
# Profile Extraction
# =============================================================================


class ExtractedProfile(BaseModel):
    """Profile extracted from sources."""
    
    display_name: str
    short_description: str | None = None
    birth_date: datetime.date | None = None
    death_date: datetime.date | None = None
    nationality: list[str] = Field(default_factory=list)
    domains: list[str] = Field(default_factory=list)
    primary_roles: list[str] = Field(default_factory=list)
    era_tags: list[str] = Field(default_factory=list)
    notable_themes: list[str] = Field(default_factory=list)
    wikipedia_url: str | None = None
    confidence: float = Field(ge=0.0, le=1.0)
    evidence: list[Evidence] = Field(default_factory=list)


class ProfileExtractionResponse(BaseModel):
    """Response from profile extraction."""
    
    profile: ExtractedProfile


# =============================================================================
# Achievement Extraction
# =============================================================================


class AchievementCandidate(BaseModel):
    """Achievement candidate extracted from sources."""
    
    title: str = Field(max_length=200)
    description: str = Field(max_length=2000)
    date: datetime.date | None = None
    date_precision: DatePrecision = DatePrecision.UNKNOWN
    age_at_event: int | None = Field(None, ge=0, le=150)
    category: AchievementCategory = AchievementCategory.OTHER
    importance_hint: ImportanceHint = ImportanceHint.MEDIUM
    confidence: float = Field(ge=0.0, le=1.0)
    evidence: list[Evidence] = Field(default_factory=list)


class AchievementsExtractionResponse(BaseModel):
    """Response from achievements extraction."""
    
    candidates: list[AchievementCandidate]


# =============================================================================
# Timeline Normalization
# =============================================================================


class TimelineEvent(BaseModel):
    """Normalized timeline event."""
    
    canonical_title: str = Field(max_length=200)
    canonical_description: str = Field(max_length=2000)
    date: datetime.date | None = None
    date_precision: DatePrecision = DatePrecision.UNKNOWN
    age_at_event: int | None = Field(None, ge=0, le=150)
    category: AchievementCategory = AchievementCategory.OTHER
    importance_score: float = Field(ge=0.0, le=1.0)
    confidence: float = Field(ge=0.0, le=1.0)
    evidence: list[Evidence] = Field(default_factory=list)


class DedupeNote(BaseModel):
    """Note about merged/deduplicated events."""
    
    merged_titles: list[str]
    reason: str


class TimelineNormalizationResponse(BaseModel):
    """Response from timeline normalization."""
    
    timeline: list[TimelineEvent]
    dedupe_notes: list[DedupeNote] = Field(default_factory=list)


# =============================================================================
# Milestones by Age
# =============================================================================


class Milestone(BaseModel):
    """Milestone for a specific age."""
    
    title: str = Field(max_length=200)
    description: str = Field(max_length=2000)
    age_at_event: int = Field(ge=0, le=150)
    category: AchievementCategory = AchievementCategory.OTHER
    importance_score: float = Field(ge=0.0, le=1.0)
    confidence: float = Field(ge=0.0, le=1.0)
    evidence: list[Evidence] = Field(default_factory=list)


class MilestonesByAgeResponse(BaseModel):
    """Response from milestones by age query."""
    
    target_age: int = Field(ge=0, le=150)
    mode: MilestoneMode
    milestones: list[Milestone]
    completeness_estimate: float = Field(ge=0.0, le=1.0)


# =============================================================================
# Plan Generation
# =============================================================================


class PlanResource(BaseModel):
    """Resource associated with a plan item."""
    
    kind: ResourceKind = ResourceKind.NONE
    title: str | None = None
    url: str | None = None


class PlanItemDifficulty(str, Enum):
    EASY = "easy"
    MEDIUM = "medium"
    HARD = "hard"


class PlanItem(BaseModel):
    """Single item in a development plan."""
    
    title: str = Field(max_length=200)
    type: PlanItemType
    description: str = Field(max_length=1000)
    idol_parallel: str | None = Field(default=None, max_length=500, description="Specific idol achievement this item emulates")
    week_start: int = Field(ge=1, le=52)
    week_end: int = Field(ge=1, le=52)
    success_metric: str = Field(max_length=300)
    estimated_hours: int = Field(ge=0, le=168)
    resource: PlanResource = Field(default_factory=PlanResource)
    difficulty: PlanItemDifficulty = PlanItemDifficulty.MEDIUM
    confidence: float = Field(ge=0.0, le=1.0)
    # Extra fields for detail generation (stored in meta_json, not exposed to frontend)
    detail_tags: list[str] = Field(default_factory=list, description="Keywords for detail generation")
    primary_gap: str | None = Field(default=None, description="Which gap this item addresses")
    suggested_queries: list[str] = Field(default_factory=list, description="Search queries for materials")


class Plan(BaseModel):
    """Development plan to close gaps."""
    
    idol_name: str | None = Field(default=None, max_length=200)
    duration_weeks: int = Field(ge=1, le=52)
    weekly_hours: int = Field(ge=0, le=168)
    focus: list[str] = Field(default_factory=list)
    rationale: str | None = Field(default=None, max_length=1000, description="Why this plan follows the idol's path")
    items: list[PlanItem] = Field(default_factory=list)


class PlanGenerationResponse(BaseModel):
    """Response from plan generation."""
    
    plan: Plan


# =============================================================================
# Persona Pack
# =============================================================================


class EraContext(str, Enum):
    """Era classification for worldview adaptation."""
    ANCIENT = "ancient"           # Before 500 CE
    MEDIEVAL = "medieval"         # 500-1500 CE
    EARLY_MODERN = "early_modern" # 1500-1800
    MODERN = "modern"             # 1800-1980
    CONTEMPORARY = "contemporary" # 1980-present


class WorldviewAdapter(BaseModel):
    """Maps modern concepts to idol-era equivalents."""
    startup: str = Field(default="venture")
    customers: str = Field(default="those you serve")
    market: str = Field(default="terrain")
    competitors: str = Field(default="rival forces")
    product: str = Field(default="offering")
    funding: str = Field(default="provisions")
    networking: str = Field(default="building alliances")
    mentor: str = Field(default="advisor/master")
    pitch: str = Field(default="proposal")
    scale: str = Field(default="expand influence")


class Persona(BaseModel):
    """Chat persona for idol simulation."""
    
    voice_style: str = Field(max_length=500)
    principles: list[str] = Field(default_factory=list)
    dos: list[str] = Field(default_factory=list)
    donts: list[str] = Field(default_factory=list)
    signature_phrases: list[str] = Field(default_factory=list)
    topics_of_strength: list[str] = Field(default_factory=list)
    taboo_topics: list[str] = Field(default_factory=list)
    grounding_evidence: list[Evidence] = Field(default_factory=list)
    disclaimer: str = Field(
        default="AI simulation based on public sources; may be inaccurate."
    )
    
    # Era-aware fields for historical authenticity
    era_context: EraContext = Field(default=EraContext.CONTEMPORARY)
    lexicon_allow: list[str] = Field(
        default_factory=list,
        description="Era-appropriate terms/phrases to use"
    )
    lexicon_ban: list[str] = Field(
        default_factory=list,
        description="Modern jargon to avoid for historical figures"
    )
    worldview_adapter: WorldviewAdapter = Field(default_factory=WorldviewAdapter)
    default_frameworks: list[str] = Field(
        default_factory=list,
        description="Idol-native problem-solving frameworks (e.g., military strategy, scientific method)"
    )


class PersonaPackResponse(BaseModel):
    """Response from persona pack generation."""
    
    persona: Persona


# =============================================================================
# Idol Discovery (LLM-based)
# =============================================================================


class LLMDiscoveryCandidate(BaseModel):
    """A person candidate from LLM discovery."""
    
    name: str = Field(max_length=200)
    description: str | None = Field(default=None, max_length=500)
    birth_year: int | None = None
    domains: list[str] = Field(default_factory=list)
    wikipedia_slug: str | None = None
    confidence: float = Field(ge=0.0, le=1.0, default=0.8)


class IdolDiscoverResponse(BaseModel):
    """Response from idol discovery LLM call."""
    
    candidates: list[LLMDiscoveryCandidate] = Field(default_factory=list)
