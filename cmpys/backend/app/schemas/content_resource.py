"""Schemas for shared reusable learning resources."""
from datetime import datetime
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
