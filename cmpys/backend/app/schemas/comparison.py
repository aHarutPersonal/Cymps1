"""Schemas for idol-user comparison."""
from datetime import date
from enum import Enum

from pydantic import BaseModel, Field


class ComparisonMode(str, Enum):
    EXACT = "exact"
    UP_TO = "up_to"


class CategoryBreakdown(BaseModel):
    """Category score breakdown."""
    
    category: str
    percent: float = Field(ge=0, le=100)
    userCount: int = 0
    idolCount: int = 0
    # AI-enhanced fields
    analysis: str | None = None
    userStrengths: list[str] = Field(default_factory=list)
    gaps: list[str] = Field(default_factory=list)
    keyIdolMilestone: str | None = None
    userBestMatch: str | None = None


class MilestoneItem(BaseModel):
    """A milestone from idol's timeline."""
    
    id: str
    title: str
    description: str
    category: str
    ageAtEvent: int | None = None
    eventDate: date | None = None
    importanceScore: float = 0.5


class UserAchievementItem(BaseModel):
    """A user achievement that counted toward comparison."""
    
    id: str
    title: str
    category: str
    achievementDate: date | None = None
    matchedMilestones: list[str] = Field(
        default_factory=list,
        description="IDs of idol milestones this achievement matches"
    )


class ComparisonStrength(BaseModel):
    """A strength identified by AI analysis."""
    
    category: str
    description: str
    achievementTitle: str | None = None


class ComparisonGap(BaseModel):
    """A gap identified by AI analysis."""
    
    category: str
    description: str
    idolMilestone: str | None = None
    ageAtMilestone: int | None = None
    suggestion: str | None = None


class NextMilestone(BaseModel):
    """Suggested next milestone from AI."""
    
    title: str
    description: str
    estimatedTimeframe: str | None = None


class ComparisonResponse(BaseModel):
    """
    Full comparison between user achievements and idol milestones.
    
    Used by progress bars and "what counts" screens.
    """
    
    idolId: str
    idolName: str
    targetAge: int
    mode: ComparisonMode
    
    # Overall score (0-100)
    overallScore: float = Field(ge=0, le=100)
    
    # AI-generated analysis
    overallAnalysis: str | None = None
    realisticPerspective: str | None = None
    encouragement: str | None = None
    
    # Category breakdown
    categoryBreakdown: list[CategoryBreakdown]
    
    # AI-identified strengths and gaps
    strengths: list[ComparisonStrength] = Field(default_factory=list)
    gaps: list[ComparisonGap] = Field(default_factory=list)
    
    # What the user is missing vs the idol
    missingVsIdol: list[MilestoneItem]
    
    # User achievements that counted
    countedUserAchievements: list[UserAchievementItem]
    
    # Idol milestones at the target age
    idolMilestonesAtAge: list[MilestoneItem]
    
    # Data completeness (0-1) based on idol data availability
    completeness: float = Field(ge=0, le=1)
    
    # Counts
    totalIdolMilestones: int
    totalUserAchievements: int
    matchedCount: int
    
    # Suggested next step
    nextMilestone: NextMilestone | None = None
    
    # Whether this comparison used AI analysis
    aiEnhanced: bool = False

