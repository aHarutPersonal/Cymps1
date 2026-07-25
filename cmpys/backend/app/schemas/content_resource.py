"""Schemas for shared reusable learning resources."""
from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class ContentResourceResponse(BaseModel):
    """Shared content resource with current user's state."""

    id: str
    kind: str
    canonicalKey: str
    title: str
    authorOrCreator: str | None = None
    sourceUrl: str | None = None
    thumbnailUrl: str | None = None
    licenseStatus: str
    contentMarkdown: str | None = None
    summaryJson: dict[str, Any] | None = None
    durationMinutes: int | None = None
    metadataJson: dict[str, Any] | None = None
    isSaved: bool = False
    savedAt: datetime | None = None
    progressPercent: int = 0
    cursorJson: dict[str, Any] | None = None
    completedAt: datetime | None = None
    createdAt: datetime
    updatedAt: datetime


class ContentResourceListResponse(BaseModel):
    """Paginated shared resources."""

    resources: list[ContentResourceResponse]
    total: int


class ContentResourceReferenceResponse(BaseModel):
    """Small late-binding response for a generated shared resource."""

    id: str
    canonicalKey: str


class ContentResourceSaveRequest(BaseModel):
    """Save a shared resource to the current user's Vault."""

    collection: str | None = Field(default=None, max_length=80)
    note: str | None = Field(default=None, max_length=5000)


class ContentResourceSaveResponse(BaseModel):
    """Vault save action result."""

    success: bool
    action: str
    resource: ContentResourceResponse


class ContentProgressUpdate(BaseModel):
    """Update reading or watch progress for a shared resource."""

    progressPercent: int = Field(..., ge=0, le=100)
    cursorJson: dict[str, Any] | None = None
    completed: bool | None = None


class ContentNarrationStyle(str, Enum):
    """Human-readable audiobook delivery presets exposed by the reader."""

    EXPRESSIVE = "expressive"
    WARM = "warm"
    GROUNDED = "grounded"


class ContentNarrationRequest(BaseModel):
    """A short, verified passage to render for synchronized playback."""

    text: str = Field(..., min_length=1, max_length=4096)
    style: ContentNarrationStyle = ContentNarrationStyle.EXPRESSIVE


class ContentNarrationCue(BaseModel):
    """Character range and exact media time for one spoken word."""

    start: int = Field(..., ge=0)
    end: int = Field(..., ge=0)
    startMs: int = Field(..., ge=0)
    endMs: int = Field(..., ge=0)


class ContentNarrationResponse(BaseModel):
    """Cached expressive narration plus text/audio synchronization data."""

    audioUrl: str
    style: ContentNarrationStyle
    voice: str
    provider: str
    isAiGenerated: bool = True
    durationMs: int | None = Field(default=None, ge=0)
    alignment: list[ContentNarrationCue] = Field(default_factory=list)
    cached: bool = False


class ContentHighlightCreate(BaseModel):
    """Create a user-specific highlight or note."""

    locatorJson: dict[str, Any] | None = None
    quoteText: str | None = Field(default=None, max_length=5000)
    noteText: str | None = Field(default=None, max_length=5000)


class ContentHighlightResponse(BaseModel):
    """A user-specific highlight/note on a shared resource."""

    id: str
    contentResourceId: str
    locatorJson: dict[str, Any] | None = None
    quoteText: str | None = None
    noteText: str | None = None
    createdAt: datetime
    updatedAt: datetime


class ContentHighlightListResponse(BaseModel):
    """List of highlights for a resource."""

    highlights: list[ContentHighlightResponse]
    total: int


class ContinueReadingResponse(BaseModel):
    """The most recent in-progress content resource."""

    resource: ContentResourceResponse
