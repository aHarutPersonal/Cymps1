"""Opt-in real PostgreSQL regression for async session response timestamps.

Run with RUN_POSTGRES_INTEGRATION=1, or execute this file directly. All probe
DDL/data lives inside an outer transaction that is rolled back after the test.
"""
import asyncio
import os
from datetime import datetime
from uuid import uuid4

from sqlalchemy import DateTime, Integer, String, func, inspect
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.api.v1.sessions import _build_refreshed_session_response
from app.core.config import settings


async def verify_session_timestamp_response():
    class ProbeBase(DeclarativeBase):
        pass

    class Probe(ProbeBase):
        __tablename__ = "session_timestamp_probe_" + uuid4().hex
        id: Mapped[int] = mapped_column(Integer, primary_key=True)
        comparison_scores_status: Mapped[str] = mapped_column(String)
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
                    row = Probe(id=1, comparison_scores_status="queued")
                    db.add(row)
                    await db.commit()
                    row.comparison_scores_status = "ready"
                    await db.commit()
                    assert "updated_at" in inspect(row).expired_attributes

                    # Unmapped response values isolate the SQL timestamp bug
                    # without creating users, mentors, or learner sessions.
                    row.idol = None
                    row.phase = None
                    row.user_age = 24
                    row.user_financial_status = ""
                    row.user_interests = []
                    row.user_goal = None
                    row.interview_turn_count = 0
                    row.comparison_output = None
                    row.blueprint_output = None
                    row.comparison_scores_json = None
                    row.interview_thread_id = None
                    row.created_at = None
                    response = await _build_refreshed_session_response(row, db)
                    assert response["updated_at"]
                    assert "updated_at" not in inspect(row).expired_attributes
                    assert response["comparisonScoresStatus"] == "ready"
            finally:
                await outer.rollback()
    finally:
        await engine.dispose()


def test_session_timestamp_response_against_postgres():
    if os.environ.get("RUN_POSTGRES_INTEGRATION") != "1":
        import pytest
        pytest.skip("Set RUN_POSTGRES_INTEGRATION=1 for the real PostgreSQL regression")
    asyncio.run(verify_session_timestamp_response())


if __name__ == "__main__":
    asyncio.run(verify_session_timestamp_response())
    print("PASS: expired SQL timestamp refreshes before session serialization; probe rolled back")
