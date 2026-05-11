from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UUIDMixin, TimestampUpdateMixin

if TYPE_CHECKING:
    from app.models.idol import Idol


class IdolImportJob(Base, UUIDMixin, TimestampUpdateMixin):
    __tablename__ = "idol_import_jobs"

    user_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    idol_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False), ForeignKey("idols.id", ondelete="SET NULL"), nullable=True
    )
    query_text: Mapped[str] = mapped_column(String(500), nullable=False)
    status: Mapped[str] = mapped_column(String(50), nullable=False, default="pending")
    progress_percent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    step: Mapped[str | None] = mapped_column(String(100), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    thinking_text: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Relationships
    idol: Mapped["Idol | None"] = relationship("Idol", back_populates="import_jobs")
