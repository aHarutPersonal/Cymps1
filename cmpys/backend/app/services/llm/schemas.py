"""
Pydantic schemas for LLM extraction outputs.

These models match the JSON schemas defined in the prompt templates
and are used to validate LLM responses.
"""
import datetime
from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field, model_validator


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


class BinaryTask(BaseModel):
    """A single binary (done/not-done) task within a week."""

    title: str = Field(max_length=300)
    description: str = Field(min_length=10, max_length=1000)
    type: str = Field(default="project", max_length=50)  # project|course|habit|practice|reading|reflection
    estimated_hours: float = Field(default=1.0, ge=0.1, le=40.0)
    daily_instructions: str | None = Field(default=None, max_length=2000)
    success_metric: str | None = Field(default=None, max_length=300)


class PlanWeek(BaseModel):
    """One week of the strategic roadmap."""

    week_number: int = Field(ge=1, le=52)
    primary_mission: str = Field(max_length=500)
    binary_tasks: list[BinaryTask] = Field(default_factory=list)
    predicted_friction: str = Field(default="", max_length=500)
    friction_solution: str = Field(default="", max_length=500)

    @model_validator(mode="after")
    def require_mission_and_daily_rhythm(self) -> "PlanWeek":
        """Keep the generated roadmap usable on both Plan and Today screens."""
        normalized_types = {task.type.strip().lower() for task in self.binary_tasks}
        mission_types = {"project", "course", "reading"}
        daily_types = {"habit", "practice"}

        if not normalized_types.intersection(mission_types):
            raise ValueError(
                "each plan week must include at least one primary mission task "
                "(project, course, or reading)"
            )
        if not normalized_types.intersection(daily_types):
            raise ValueError(
                "each plan week must include at least one daily rhythm task "
                "(habit or practice)"
            )
        return self


class PlanGenerationResponse(BaseModel):
    """Response from the new plan_generate.txt prompt."""

    roadmap_thesis: str = Field(default="", max_length=1000)
    anti_goals: list[str] = Field(default_factory=list)
    weeks: list[PlanWeek] = Field(default_factory=list)


class PlanDetailIdeaOutput(BaseModel):
    title: str = Field(max_length=50)
    content: str
    category: str | None = None


class PlanDetailMaterialOutput(BaseModel):
    title: str
    type: Literal["book", "video", "in_app_lesson", "article", "course", "tool"]
    author_or_creator: str | None = None
    search_query: str
    duration_minutes: int | None = Field(default=None, ge=1)
    canonical_hint: str | None = None
    source_strategy: str | None = None
    reason: str
    content_markdown: str | None = None
    ideas: list[PlanDetailIdeaOutput] = Field(default_factory=list)


class PlanDetailStepOutput(BaseModel):
    id: str = Field(pattern=r"^step_[1-3]$")
    title: str = Field(max_length=60)
    description: str
    estimate_minutes: int = Field(ge=40, le=60)
    reading_minutes: int = Field(ge=1, le=30)
    practice_minutes: int = Field(ge=20, le=59)
    lesson_content: str
    resources: list[str] = Field(min_length=1, max_length=2)
    substeps: list[str] = Field(min_length=2, max_length=3)


class PlanItemDetailsOutput(BaseModel):
    """Native structured-output contract for long plan-item lessons."""

    steps: list[PlanDetailStepOutput] = Field(min_length=3, max_length=3)
    materials: list[PlanDetailMaterialOutput] = Field(min_length=3, max_length=3)
    definition_of_done: str
    mental_model: str

    @model_validator(mode="after")
    def require_complete_learning_contract(self) -> "PlanItemDetailsOutput":
        """Protect reader depth and resource integrity before persistence."""
        required_headings = (
            "## Why This Matters",
            "## Core Framework",
            "## Worked Example",
            "## Failure Modes",
            "## Guided Practice",
            "## Check Your Understanding",
            "## References",
        )
        material_titles = {material.title for material in self.materials}

        if len({step.id for step in self.steps}) != 3:
            raise ValueError("step ids must be unique")
        for step in self.steps:
            lesson_words = len(step.lesson_content.split())
            if not 1200 <= lesson_words <= 1800:
                raise ValueError(
                    f"{step.id} lesson_content has {lesson_words} words; "
                    "required range is 1200-1800"
                )
            missing = [
                heading for heading in required_headings
                if heading not in step.lesson_content
            ]
            if missing:
                raise ValueError(f"{step.id} is missing lesson headings: {missing}")
            if any(title not in material_titles for title in step.resources):
                raise ValueError(
                    f"{step.id} resources must exactly match top-level material titles"
                )
            for substep in step.substeps:
                words = len(substep.split())
                if not 20 <= words <= 50:
                    raise ValueError(
                        f"{step.id} substeps must contain 20-50 words"
                    )

        kinds = [material.type for material in self.materials]
        if kinds.count("book") != 1 or kinds.count("video") != 1:
            raise ValueError("materials must contain exactly one book and one video")
        if sum(kind in {"article", "course", "tool", "in_app_lesson"} for kind in kinds) != 1:
            raise ValueError(
                "the third material must be an article, course, tool, or in_app_lesson"
            )

        for material in self.materials:
            content = material.content_markdown
            if material.type == "in_app_lesson":
                words = len((content or "").split())
                if not 400 <= words <= 600:
                    raise ValueError(
                        "in_app_lesson content_markdown must contain 400-600 words"
                    )
            elif content is not None:
                raise ValueError(
                    f"{material.type} material content_markdown must be null"
                )
            if material.type == "book" and material.ideas:
                raise ValueError("book material ideas must be empty")
        return self


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


# =============================================================================
# Agentic Workflow — Interview, Comparison, Blueprint
# =============================================================================


class InterviewQuestionResponse(BaseModel):
    """LLM output for a single interview turn."""
    
    question: str = Field(max_length=2000, description="The idol's in-character question")
    emotional_reaction: str = Field(
        max_length=1000,
        description="The idol's emotional reaction to the user's previous answer"
    )
    should_continue: bool = Field(
        default=True,
        description="False when the idol signals the interview is complete"
    )


class CitedAchievement(BaseModel):
    """A specific idol achievement cited in the comparison."""
    
    achievement: str = Field(max_length=500)
    age_at_achievement: int | None = Field(None, ge=0, le=150)
    source_hint: str | None = Field(None, max_length=500)


class ComparisonResponse(BaseModel):
    """LLM output for the brutal reality comparison."""
    
    comparison_text: str = Field(description="Full comparison prose in idol's voice")
    cited_achievements: list[CitedAchievement] = Field(
        default_factory=list,
        description="Structured list of idol achievements referenced"
    )


class AIComparisonCategoryOutput(BaseModel):
    """Category result for the legacy structured comparison endpoint."""

    category: str
    score: float = Field(ge=0, le=100)
    analysis: str
    userStrengths: list[str] = Field(default_factory=list)
    gaps: list[str] = Field(default_factory=list)
    keyIdolMilestone: str | None = None
    userBestMatch: str | None = None


class AIComparisonStrengthOutput(BaseModel):
    category: str
    description: str
    achievementTitle: str | None = None


class AIComparisonGapOutput(BaseModel):
    category: str
    description: str
    idolMilestone: str | None = None
    ageAtMilestone: int | None = Field(default=None, ge=0, le=150)
    suggestion: str | None = None


class AIComparisonNextMilestoneOutput(BaseModel):
    title: str
    description: str
    estimatedTimeframe: str | None = None


class AIComparisonOutput(BaseModel):
    """Strict LLM contract used by ``GET /comparison/ai``."""

    overallScore: float = Field(ge=0, le=100)
    overallAnalysis: str
    realisticPerspective: str
    encouragement: str
    categoryBreakdown: list[AIComparisonCategoryOutput]
    strengths: list[AIComparisonStrengthOutput] = Field(default_factory=list)
    gaps: list[AIComparisonGapOutput] = Field(default_factory=list)
    nextMilestone: AIComparisonNextMilestoneOutput | None = None


class CitedResource(BaseModel):
    """A real resource recommended in the blueprint."""
    
    title: str = Field(max_length=300)
    url: str | None = Field(None, max_length=2000)
    resource_type: str = Field(default="book", max_length=50)  # book, course, article, platform


class BlueprintResponse(BaseModel):
    """LLM output for the Q1–Q4 quarterly blueprint."""
    
    blueprint_markdown: str = Field(description="Full Q1–Q4 blueprint in Markdown format")
    resources_cited: list[CitedResource] = Field(
        default_factory=list,
        description="Structured list of resources recommended across all quarters"
    )


class IdolSuggestion(BaseModel):
    """A single idol suggestion for the session-based flow."""
    
    name: str = Field(max_length=200)
    era: str = Field(max_length=100, description="Life dates or era label")
    relevance_summary: str = Field(max_length=500)
    wikidata_id: str | None = Field(None, max_length=20)
    domains: list[str] = Field(default_factory=list)
    confidence: float = Field(ge=0.0, le=1.0, default=0.8)


class IdolSuggestionsResponse(BaseModel):
    """Response from the session-based idol suggestion flow (exactly 3)."""
    
    suggestions: list[IdolSuggestion] = Field(
        min_length=1,
        max_length=3,
    )
