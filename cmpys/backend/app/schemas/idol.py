from datetime import date, datetime

from pydantic import BaseModel, Field


class IdolTagResponse(BaseModel):
    id: str
    name: str
    type: str

    model_config = {"from_attributes": True}


class IdolAliasResponse(BaseModel):
    id: str
    alias_text: str

    model_config = {"from_attributes": True}


class IdolExternalIdResponse(BaseModel):
    id: str
    provider: str
    externalId: str
    wikipediaUrl: str | None = None

    model_config = {"from_attributes": True}


class IdolResponse(BaseModel):
    id: str
    name: str
    birth_date: date | None = None
    domain: str
    image_url: str | None = None
    imageSourceUrl: str | None = None
    imageLicense: str | None = None
    imageAttribution: dict | None = None
    aliases: list[IdolAliasResponse] = []
    tags: list[IdolTagResponse] = []

    model_config = {"from_attributes": True}


class IdolDetailResponse(BaseModel):
    id: str
    name: str
    birth_date: date | None = None
    domain: str
    image_url: str | None = None
    imageSourceUrl: str | None = None
    imageLicense: str | None = None
    imageAttribution: dict | None = None
    created_at: datetime
    aliases: list[IdolAliasResponse] = []
    tags: list[IdolTagResponse] = []
    external_ids: list[IdolExternalIdResponse] = []

    model_config = {"from_attributes": True}


class IdolSearchResponse(BaseModel):
    idols: list[IdolResponse]
    total: int


class IdolSuggestResponse(BaseModel):
    idols: list[IdolResponse]


# =============================================================================
# Hybrid Suggestion Response Models
# =============================================================================


class LocalIdolSuggestion(BaseModel):
    """A local idol suggestion from the database."""
    
    source: str = "local"
    id: str
    name: str
    birthDate: date | None = None
    domain: str
    imageUrl: str | None = None
    imageSourceUrl: str | None = None
    imageLicense: str | None = None
    imageAttribution: dict | None = None
    aliases: list[IdolAliasResponse] = []
    tags: list[IdolTagResponse] = []
    relevanceScore: float = Field(
        default=0.0,
        description="Relevance score based on tag weights matching interests",
    )


class WebIdolSuggestion(BaseModel):
    """A web suggestion from Wikidata (not yet imported)."""
    
    source: str = "web"
    provider: str = "wikidata"
    externalId: str
    name: str
    description: str | None = None
    birthDate: date | None = None
    wikipediaUrl: str | None = None
    imageUrl: str | None = None
    imageSourceUrl: str | None = None
    imageLicense: str | None = None
    imageAttribution: dict | None = None
    occupations: list[str] = []
    confidence: float = 0.5


class SourceMix(BaseModel):
    """Breakdown of suggestion sources."""
    
    local: int = Field(description="Number of suggestions from local database")
    web: int = Field(description="Number of suggestions from web/Wikidata")
    total: int = Field(description="Total number of suggestions returned")


class HybridSuggestResponse(BaseModel):
    """
    Response for hybrid idol suggestions.
    
    Combines local database results with web suggestions from Wikidata.
    Local results come first, followed by web results.
    """
    
    interests: list[str] = Field(description="Parsed interest terms from query")
    suggestions: list[LocalIdolSuggestion | WebIdolSuggestion] = Field(
        description="Mixed list of local and web suggestions, ordered by relevance"
    )
    sourceMix: SourceMix = Field(description="Breakdown of result sources")


class IdolImportRequest(BaseModel):
    provider: str  # "wikidata" or "llm"
    externalId: str
    # Optional fields for LLM-sourced imports (no external API to fetch from)
    name: str | None = None
    description: str | None = None
    birthDate: date | None = None
    wikipediaUrl: str | None = None
    occupations: list[str] = []


class IdolImportResponse(BaseModel):
    idolId: str
    jobId: str | None = None
    status: str


# =============================================================================
# Profile Response Models
# =============================================================================


class EvidenceResponse(BaseModel):
    """Evidence snippet from sources."""
    
    sourceId: str
    chunkIndex: int
    sourceUrl: str
    snippet: str
    confidence: float


class IdolProfileResponse(BaseModel):
    """Extracted profile for an idol."""
    
    id: str
    idolId: str
    displayName: str
    shortDescription: str | None = None
    birthDate: date | None = None
    deathDate: date | None = None
    nationality: list[str] = []
    domains: list[str] = []
    primaryRoles: list[str] = []
    eraTags: list[str] = []
    notableThemes: list[str] = []
    wikipediaUrl: str | None = None
    confidence: float = 0.0
    evidence: list[EvidenceResponse] = []
    createdAt: datetime
    
    model_config = {"from_attributes": True}


# =============================================================================
# Timeline Response Models
# =============================================================================


class TimelineEventResponse(BaseModel):
    """A normalized timeline event."""
    
    id: str
    idolId: str
    canonicalTitle: str
    canonicalDescription: str
    eventDate: date | None = None
    datePrecision: str
    ageAtEvent: int | None = None
    category: str
    importanceScore: float
    confidence: float
    evidence: list[EvidenceResponse] = []
    createdAt: datetime
    
    model_config = {"from_attributes": True}


class TimelineResponse(BaseModel):
    """Timeline for an idol with optional filtering."""
    
    idolId: str
    idolName: str
    events: list[TimelineEventResponse]
    totalEvents: int
    filteredBy: dict | None = None


# =============================================================================
# Persona Response Models
# =============================================================================


class IdolPersonaResponse(BaseModel):
    """Chat persona for idol simulation."""
    
    id: str
    idolId: str
    voiceStyle: str
    principles: list[str] = []
    dos: list[str] = []
    donts: list[str] = []
    signaturePhrases: list[str] = []
    topicsOfStrength: list[str] = []
    tabooTopics: list[str] = []
    groundingEvidence: list[EvidenceResponse] = []
    disclaimer: str
    createdAt: datetime
    
    model_config = {"from_attributes": True}
