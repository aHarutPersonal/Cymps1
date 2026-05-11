from datetime import date

from pydantic import BaseModel, Field


class DiscoveryCandidate(BaseModel):
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
    occupations: list[str] = Field(default_factory=list)
    confidence: float = 0.5


class DiscoveryResponse(BaseModel):
    query: str
    candidates: list[DiscoveryCandidate]
