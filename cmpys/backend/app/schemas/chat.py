"""Schemas for chat with idol personas."""
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field


class MessageRole(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"


class ThreadCreate(BaseModel):
    """Create a new chat thread."""
    
    idolId: str


class MessageCreate(BaseModel):
    """Send a message in a thread."""
    
    content: str = Field(..., max_length=10000)


class MessageResponse(BaseModel):
    """Chat message response."""
    
    id: str
    threadId: str
    role: MessageRole
    content: str
    createdAt: datetime

    model_config = {"from_attributes": True}


class ThreadResponse(BaseModel):
    """Chat thread response."""
    
    id: str
    userId: str
    idolId: str
    idolName: str | None = None
    idolImageUrl: str | None = None
    createdAt: datetime
    messageCount: int = 0
    lastMessage: MessageResponse | None = None

    model_config = {"from_attributes": True}


class ThreadDetailResponse(BaseModel):
    """Thread with all messages."""
    
    id: str
    userId: str
    idolId: str
    idolName: str | None = None
    idolImageUrl: str | None = None
    createdAt: datetime
    messages: list[MessageResponse] = []

    model_config = {"from_attributes": True}


class AssistantReplyResponse(BaseModel):
    """Response after sending a message."""
    
    userMessage: MessageResponse
    assistantMessage: MessageResponse
    disclaimer: str = "AI simulation based on public sources; may be inaccurate."


class ThreadListResponse(BaseModel):
    """List of threads."""
    
    threads: list[ThreadResponse]
    total: int
