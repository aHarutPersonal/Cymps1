"""Pydantic schemas for achievement extraction."""
import datetime
from enum import Enum

from pydantic import BaseModel, Field


class DatePrecisionEnum(str, Enum):
    DAY = "day"
    MONTH = "month"
    YEAR = "year"
    UNKNOWN = "unknown"


class EvidenceDraft(BaseModel):
    """Evidence snippet supporting an achievement."""

    source_url: str
    snippet: str = Field(..., max_length=500)
    confidence: float = Field(ge=0.0, le=1.0, default=0.3)


class AchievementDraft(BaseModel):
    """Draft achievement extracted from source content."""

    title: str = Field(..., max_length=200)
    description: str = Field(..., max_length=2000)
    category: str = Field(..., max_length=100)
    date: datetime.date | None = None
    date_precision: DatePrecisionEnum = DatePrecisionEnum.UNKNOWN
    age: int | None = Field(None, ge=0, le=150)
    confidence: float = Field(ge=0.0, le=1.0, default=0.3)
    evidence: list[EvidenceDraft] = Field(default_factory=list)
