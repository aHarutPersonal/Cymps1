"""IngestJob model — catalog work-queue for background ingestion tasks."""
from enum import Enum

from sqlalchemy import Enum as SQLEnum, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, UUIDMixin, TimestampUpdateMixin


class IngestKind(str, Enum):
    IDOL = "idol"
    BOOK = "book"


class IngestState(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"
    FLAGGED = "flagged"


class IngestJob(Base, UUIDMixin, TimestampUpdateMixin):
    """Tracks pending and completed catalog ingestion work items."""

    __tablename__ = "ingest_jobs"
    __table_args__ = (
        UniqueConstraint("kind", "source", "external_id", name="uq_ingest_identity"),
    )

    kind: Mapped[IngestKind] = mapped_column(
        SQLEnum(IngestKind, name="ingestkind", values_callable=lambda x: [e.value for e in x]),
        nullable=False,
    )
    source: Mapped[str] = mapped_column(String(50), nullable=False)
    external_id: Mapped[str] = mapped_column(String(255), nullable=False)
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    state: Mapped[IngestState] = mapped_column(
        SQLEnum(IngestState, name="ingeststate", values_callable=lambda x: [e.value for e in x]),
        nullable=False,
        default=IngestState.QUEUED,
    )
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)

    def __init__(
        self,
        kind: IngestKind,
        source: str,
        external_id: str,
        priority: int = 0,
        state: IngestState = IngestState.QUEUED,
        attempts: int = 0,
        last_error: str | None = None,
        **kwargs,
    ) -> None:
        super().__init__(
            kind=kind,
            source=source,
            external_id=external_id,
            priority=priority,
            state=state,
            attempts=attempts,
            last_error=last_error,
            **kwargs,
        )
