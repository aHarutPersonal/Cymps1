"""Schemas for user notes."""
from datetime import datetime

from pydantic import BaseModel, Field


class NoteAttachmentCreate(BaseModel):
    """Create an attachment for a note."""
    
    idolId: str | None = None
    planItemId: str | None = None
    achievementId: str | None = None


class NoteAttachmentResponse(BaseModel):
    """Note attachment response."""
    
    id: str
    idolId: str | None = None
    planItemId: str | None = None
    achievementId: str | None = None

    model_config = {"from_attributes": True}


class NoteCreate(BaseModel):
    """Create a new note."""
    
    title: str | None = Field(None, max_length=200)
    content: str = Field(..., max_length=50000)
    attachments: list[NoteAttachmentCreate] = []


class NoteUpdate(BaseModel):
    """Update a note."""
    
    title: str | None = Field(None, max_length=200)
    content: str | None = Field(None, max_length=50000)
    attachments: list[NoteAttachmentCreate] | None = None


class NoteResponse(BaseModel):
    """Note response with attachments."""
    
    id: str
    userId: str
    title: str | None = None
    content: str
    attachments: list[NoteAttachmentResponse] = []
    createdAt: datetime
    updatedAt: datetime

    model_config = {"from_attributes": True}


class NoteListResponse(BaseModel):
    """List of notes."""
    
    notes: list[NoteResponse]
    total: int
