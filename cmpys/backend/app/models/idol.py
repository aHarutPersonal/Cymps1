from datetime import date
from enum import Enum as PyEnum
from typing import TYPE_CHECKING

from pgvector.sqlalchemy import Vector
from sqlalchemy import Date, DateTime, Enum as SAEnum, Float, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampMixin


class CatalogStatus(str, PyEnum):
    PENDING = "pending"
    PUBLISHED = "published"
    FLAGGED = "flagged"

if TYPE_CHECKING:
    from app.models.idol_alias import IdolAlias
    from app.models.idol_achievement import IdolAchievement
    from app.models.idol_external_id import IdolExternalId
    from app.models.idol_job import IdolImportJob
    from app.models.idol_persona import IdolPersona
    from app.models.idol_profile import IdolProfile
    from app.models.idol_source import IdolSource
    from app.models.idol_tag_link import IdolTagLink
    from app.models.idol_timeline import IdolTimelineEvent
    from app.models.intake import IntakeSession
    from app.models.idea_card import IdeaCard


class Idol(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "idols"

    name: Mapped[str] = mapped_column(String(255), nullable=False)
    birth_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    domain: Mapped[str] = mapped_column(String(255), nullable=False)
    image_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    image_source_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    image_license: Mapped[str | None] = mapped_column(String(120), nullable=True)
    image_attribution_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    status: Mapped[CatalogStatus] = mapped_column(
        SAEnum(
            CatalogStatus,
            name="catalog_status",
            values_callable=lambda e: [x.value for x in e],
        ),
        nullable=False,
        default=CatalogStatus.PENDING,
        index=True,
    )
    embedding: Mapped[list[float] | None] = mapped_column(Vector(1024), nullable=True)
    quality_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    published_at: Mapped[object | None] = mapped_column(DateTime(timezone=True), nullable=True)

    def __init__(
        self,
        name: str,
        domain: str,
        status: CatalogStatus = CatalogStatus.PENDING,
        **kwargs,
    ) -> None:
        super().__init__(name=name, domain=domain, status=status, **kwargs)

    # Relationships
    aliases: Mapped[list["IdolAlias"]] = relationship(
        "IdolAlias", back_populates="idol", cascade="all, delete-orphan"
    )
    achievements: Mapped[list["IdolAchievement"]] = relationship(
        "IdolAchievement", back_populates="idol", cascade="all, delete-orphan"
    )
    import_jobs: Mapped[list["IdolImportJob"]] = relationship(
        "IdolImportJob", back_populates="idol"
    )
    tag_links: Mapped[list["IdolTagLink"]] = relationship(
        "IdolTagLink", back_populates="idol", cascade="all, delete-orphan"
    )
    external_ids: Mapped[list["IdolExternalId"]] = relationship(
        "IdolExternalId", back_populates="idol", cascade="all, delete-orphan"
    )
    sources: Mapped[list["IdolSource"]] = relationship(
        "IdolSource", back_populates="idol", cascade="all, delete-orphan"
    )
    
    # One-to-one relationships
    profile: Mapped["IdolProfile | None"] = relationship(
        "IdolProfile", back_populates="idol", uselist=False, cascade="all, delete-orphan"
    )
    persona: Mapped["IdolPersona | None"] = relationship(
        "IdolPersona", back_populates="idol", uselist=False, cascade="all, delete-orphan"
    )
    
    # Timeline events
    timeline_events: Mapped[list["IdolTimelineEvent"]] = relationship(
        "IdolTimelineEvent", back_populates="idol", cascade="all, delete-orphan"
    )
    
    # Intake sessions
    intake_sessions: Mapped[list["IntakeSession"]] = relationship(
        "IntakeSession", back_populates="idol", cascade="all, delete-orphan"
    )

    # Idea cards (atomic insights)
    idea_cards: Mapped[list["IdeaCard"]] = relationship(
        "IdeaCard", back_populates="idol", cascade="all, delete-orphan"
    )
