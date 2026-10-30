"""Opt-in PostgreSQL verification. All synthetic data is rolled back."""

import copy
import os
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.api.v1 import learning_support as api
from app.models import User, Plan, PlanItem, PlanItemType
from app.models.content_resource import ContentResource
from app.services import book_companions as books, learning_support as support
from app.services.planning.lesson_package import digest
from app.tasks.content_resources import generate_learning_support


@pytest.mark.asyncio
@pytest.mark.skipif(
    not os.environ.get("SUPPORT_TEST_DATABASE_URL"),
    reason="Opt-in isolated PostgreSQL test",
)
async def test_support_leases_reuse_shared_books_and_preserve_tutorials(monkeypatch):
    engine = create_async_engine(os.environ["SUPPORT_TEST_DATABASE_URL"])
    try:
        async with engine.connect() as connection:
            outer = await connection.begin()
            try:
                factory = async_sessionmaker(
                    connection,
                    expire_on_commit=False,
                    join_transaction_mode="create_savepoint",
                )
                monkeypatch.setattr(books, "async_session_maker", factory)
                monkeypatch.setattr(support, "async_session_maker", factory)
                title = f"Book {uuid4().hex}"
                content = {
                    "scope": "Selected public ideas.",
                    "sources": [
                        {
                            "id": "s1",
                            "title": "Author page",
                            "url": "https://example.org/author",
                        }
                    ],
                    "lessons": [
                        {
                            "id": "lesson_1",
                            "title": "Choose a cue",
                            "idea": "Choose a concrete cue.",
                            "content": "Original lesson.",
                            "minutes": 4,
                        }
                    ],
                }
                report = {
                    "version": books.VERSION,
                    "passed": True,
                    "content_hash": digest(content),
                }
                build = AsyncMock(return_value=(content, report))
                monkeypatch.setattr(books, "build_companion", build)
                first = await books.get_companion(title, "Author")
                second = await books.get_companion(title, "Author")
                assert first["id"] == second["id"] and first["status"] == "ready"
                assert build.await_count == 1
                async with factory() as db:
                    owner = User(
                        email=f"support-{uuid4().hex}@example.invalid",
                        password_hash="unused-test",
                    )
                    db.add(owner)
                    await db.flush()
                    plan = Plan(
                        user_id=owner.id,
                        target_age=30,
                        duration_weeks=1,
                        weekly_hours=1,
                    )
                    db.add(plan)
                    await db.flush()
                    details = {
                        "steps": [
                            {
                                "id": "step_1",
                                "title": "Apply a cue",
                                "lesson_content": "A concrete cue identifies when to perform a small action. "
                                * 10,
                                "resources": [title],
                            }
                        ],
                        "materials": [
                            {
                                "type": "book",
                                "title": title,
                                "author_or_creator": "Author",
                            }
                        ],
                    }
                    mission = PlanItem(
                        plan_id=plan.id,
                        title="Apply a taught skill",
                        type=PlanItemType.COURSE,
                        description="Synthetic mission",
                        success_metric="Use the skill",
                        details_json=details,
                        meta_json={"keep_me": "other feature metadata"},
                    )
                    db.add(mission)
                    await db.commit()
                    mission_id, owner_id = mission.id, owner.id
                queue = Mock()
                monkeypatch.setattr(generate_learning_support, "apply_async", queue)
                async with factory() as db:
                    result = await api._support(
                        mission_id,
                        db,
                        SimpleNamespace(id=owner_id),
                        "step_1",
                        None,
                        True,
                    )
                    assert (
                        result["status"] == "checking"
                        and result["books"][0]["status"] == "ready"
                    )
                    again = await api._support(
                        mission_id,
                        db,
                        SimpleNamespace(id=owner_id),
                        "step_1",
                        None,
                        True,
                    )
                    assert again["status"] == "checking" and queue.call_count == 1
                    with pytest.raises(HTTPException) as error:
                        await api._support(
                            mission_id,
                            db,
                            SimpleNamespace(id=str(uuid4())),
                            "step_1",
                            None,
                            True,
                        )
                    assert error.value.status_code == 404
                    await db.commit()
                bundle = AsyncMock(
                    return_value={
                        "books": [{"title": title, "author": "Author"}],
                        "videos": [],
                        "idea": {
                            "bookId": first["id"],
                            "lessonId": "lesson_1",
                            "bookHash": digest(content["lessons"]),
                            "application": "Apply the cue to this tutorial.",
                        },
                    }
                )
                monkeypatch.setattr(support, "build_support", bundle)
                args = queue.call_args.kwargs["args"]
                assert (await support.run_support(*args))["status"] == "ready"
                assert (await support.run_support(*args))["status"] == "superseded"
                assert bundle.await_count == 1
                async with factory() as db:
                    result = await api._support(
                        mission_id,
                        db,
                        SimpleNamespace(id=owner_id),
                        "step_1",
                        None,
                        False,
                    )
                    assert result["idea"]["bookTitle"] == title
                    mission = await db.get(PlanItem, mission_id)
                    assert (
                        mission.details_json == details
                        and mission.progress_percent == 0
                    )
                    assert mission.meta_json["keep_me"] == "other feature metadata"
                    # Edited content invalidates the bundle before it can be served.
                    changed = copy.deepcopy(details)
                    changed["steps"][0]["lesson_content"] += " Changed example."
                    mission.details_json = changed
                    await db.commit()
                    assert (
                        await api._support(
                            mission_id,
                            db,
                            SimpleNamespace(id=owner_id),
                            "step_1",
                            None,
                            False,
                        )
                    )["status"] == "idle"
                    await api._support(
                        mission_id,
                        db,
                        SimpleNamespace(id=owner_id),
                        "step_1",
                        None,
                        True,
                    )
                    mission.details_json = details
                    await db.commit()
                assert (await support.run_support(*queue.call_args.kwargs["args"]))[
                    "status"
                ] == "superseded"
                assert bundle.await_count == 1  # Stale jobs spend nothing.
                async with factory() as db:
                    resource = await db.get(ContentResource, first["id"])
                    resource.summary_json = {"scope": "Tampered"}
                    await db.commit()
                    assert not books.companion_ready(resource)
            finally:
                await outer.rollback()
    finally:
        await engine.dispose()
