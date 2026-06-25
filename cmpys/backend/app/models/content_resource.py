"""Reusable learning/content resources shared across users and plans."""
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from pgvector.sqlalchemy import Vector
from sqlalchemy import Boolean, DateTime, Enum as SQLEnum, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampUpdateMixin, UUIDMixin
from app.models.idol import CatalogStatus

if TYPE_CHECKING:
    from app.models.user import User


class ContentResourceKind(str, Enum):
    PUBLIC_DOMAIN_BOOK = "public_domain_book"
    LLM_BOOK_SUMMARY = "llm_book_summary"
    VIDEO = "video"
    ARTICLE = "article"
    IN_APP_LESSON = "in_app_lesson"


class LicenseStatus(str, Enum):
    PUBLIC_DOMAIN = "public_domain"
    LICENSED = "licensed"
    LLM_SUMMARY = "llm_summary"
    EXTERNAL_LINK = "external_link"
    UNKNOWN = "unknown"


class ContentResource(Base, UUIDMixin, TimestampUpdateMixin):
    """A deduplicated book module, video, article, or lesson."""

    __tablename__ = "content_resources"

    kind: Mapped[ContentResourceKind] = mapped_column(
        SQLEnum(
            ContentResourceKind,
            name="content_resource_kind",
            values_callable=lambda e: [x.value for x in e],
        ),
        nullable=False,
        index=True,
    )
    canonical_key: Mapped[str] = mapped_column(String(320), nullable=False, unique=True, index=True)
    title: Mapped[str] = mapped_column(String(300), nullable=False)
    author_or_creator: Mapped[str | None] = mapped_column(String(300), nullable=True)
    source_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    thumbnail_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    license_status: Mapped[LicenseStatus] = mapped_column(
        SQLEnum(
            LicenseStatus,
            name="content_resource_license_status",
            values_callable=lambda e: [x.value for x in e],
        ),
        nullable=False,
        default=LicenseStatus.UNKNOWN,
    )
    content_markdown: Mapped[str | None] = mapped_column(Text, nullable=True)
    summary_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    duration_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    metadata_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    status: Mapped[CatalogStatus] = mapped_column(
        SQLEnum(
            CatalogStatus,
            name="catalog_status",
            create_type=False,
            values_callable=lambda e: [x.value for x in e],
        ),
        nullable=False,
        default=CatalogStatus.PENDING,
        index=True,
    )
    embedding: Mapped[list[float] | None] = mapped_column(Vector(1024), nullable=True)
    is_public_domain: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    source_provider: Mapped[str | None] = mapped_column(String(50), nullable=True)
    source_external_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    read_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)

    saves: Mapped[list["UserContentSave"]] = relationship(
        "UserContentSave",
        back_populates="resource",
        cascade="all, delete-orphan",
    )
    progress_records: Mapped[list["UserContentProgress"]] = relationship(
        "UserContentProgress",
        back_populates="resource",
        cascade="all, delete-orphan",
    )
    highlights: Mapped[list["UserContentHighlight"]] = relationship(
        "UserContentHighlight",
        back_populates="resource",
        cascade="all, delete-orphan",
    )


class UserContentSave(Base, UUIDMixin, TimestampUpdateMixin):
    """User-specific Vault save pointing to a shared content resource."""

    __tablename__ = "user_content_saves"
    __table_args__ = (
        UniqueConstraint("user_id", "content_resource_id", name="uq_user_content_save"),
        Index("ix_user_content_saves_user_id", "user_id"),
    )

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    content_resource_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("content_resources.id", ondelete="CASCADE"),
        nullable=False,
    )
    collection: Mapped[str | None] = mapped_column(String(80), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)

    user: Mapped["User"] = relationship("User", back_populates="content_saves")
    resource: Mapped["ContentResource"] = relationship("ContentResource", back_populates="saves")


class UserContentProgress(Base, UUIDMixin, TimestampUpdateMixin):
    """User-specific reading/watch progress for a shared resource."""

    __tablename__ = "user_content_progress"
    __table_args__ = (
        UniqueConstraint("user_id", "content_resource_id", name="uq_user_content_progress"),
        Index("ix_user_content_progress_user_id", "user_id"),
    )

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    content_resource_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("content_resources.id", ondelete="CASCADE"),
        nullable=False,
    )
    progress_percent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    cursor_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship("User", back_populates="content_progress")
    resource: Mapped["ContentResource"] = relationship("ContentResource", back_populates="progress_records")


class UserContentHighlight(Base, UUIDMixin, TimestampUpdateMixin):
    """User-specific highlight or note for a shared resource."""

    __tablename__ = "user_content_highlights"
    __table_args__ = (Index("ix_user_content_highlights_user_resource", "user_id", "content_resource_id"),)

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    content_resource_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey("content_resources.id", ondelete="CASCADE"),
        nullable=False,
    )
    locator_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    quote_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    note_text: Mapped[str | None] = mapped_column(Text, nullable=True)

    user: Mapped["User"] = relationship("User", back_populates="content_highlights")
    resource: Mapped["ContentResource"] = relationship("ContentResource", back_populates="highlights")
