"""Opt-in PostgreSQL regression for a failed practice's cooldown response.

The unique probe table and all data are rolled back after verification.
"""
import asyncio
import os
from datetime import datetime
from uuid import uuid4

from sqlalchemy import DateTime, Integer, String, func, inspect
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.api.v1.practice import _refreshed_practice_view
from app.core.config import settings


async def verify_practice_timestamp_response():
    class ProbeBase(DeclarativeBase):
        pass

    class Probe(ProbeBase):
        __tablename__ = "practice_timestamp_probe_" + uuid4().hex
        id: Mapped[int] = mapped_column(Integer, primary_key=True)
        state: Mapped[str] = mapped_column(String)
        updated_at: Mapped[datetime] = mapped_column(
            DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
        )

    engine = create_async_engine(settings.database_url)
    try:
        async with engine.connect() as connection:
            outer = await connection.begin()
            try:
                await connection.run_sync(ProbeBase.metadata.create_all)
                async with AsyncSession(
                    connection, expire_on_commit=False,
                    join_transaction_mode="create_savepoint",
                ) as db:
                    row = Probe(id=1, state="preparing")
                    db.add(row)
                    await db.commit()
                    row.state = "failed"
                    await db.commit()
                    assert "updated_at" in inspect(row).expired_attributes

                    # Exercise the actual exhausted-preparation serializer,
                    # without creating a learner, plan or paid generation.
                    row.generation_attempts = 3
                    row.workbook_json = None
                    row.lease_until = None
                    row.lesson_version = "probe"
                    row.revision = 3
                    row.answers_json = {}
                    row.attempts_json = []
                    row.hints_json = []
                    result = await _refreshed_practice_view(row, db)
                    assert result["state"] == "failed"
                    assert result["can_retry_preparation"] is False
                    assert 1700 < result["retry_after_seconds"] <= 1800
                    assert "updated_at" not in inspect(row).expired_attributes
            finally:
                await outer.rollback()
    finally:
        await engine.dispose()


def test_practice_timestamp_response_against_postgres():
    if os.environ.get("RUN_POSTGRES_INTEGRATION") != "1":
        import pytest
        pytest.skip("Set RUN_POSTGRES_INTEGRATION=1 for the PostgreSQL regression")
    asyncio.run(verify_practice_timestamp_response())


if __name__ == "__main__":
    asyncio.run(verify_practice_timestamp_response())
    print("PASS: practice cooldown timestamp refreshes; probe rolled back")
