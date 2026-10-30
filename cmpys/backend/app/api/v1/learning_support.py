"""Owner-scoped preparation and reads of optional supporting material."""

from datetime import datetime, timedelta, timezone
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.api.v1.plans import _get_item_for_user
from app.core.db import get_db
from app.models.user import User
from app.services.learning_support import public_support, support_input
from app.services.planning.artifact_identity import artifact_job_reference_is_valid

router = APIRouter(prefix="/plan-items", tags=["learning-support"])


async def _support(item_id, db, user, step_id, book_title, prepare):
    if bool(step_id) == bool(book_title):
        raise HTTPException(422, "Choose one tutorial or one book.")
    item = await _get_item_for_user(db, str(item_id), user.id, for_update=prepare)
    if not await artifact_job_reference_is_valid(
        db, item.details_json, plan_item_id=str(item.id), user_id=str(user.id)
    ):
        raise HTTPException(409, "This tutorial publication is no longer available.")
    value = support_input(item, step_id, book_title)
    entries = dict((item.meta_json or {}).get("learning_support") or {})
    entry = entries.get(value["key"], {})
    now = datetime.now(timezone.utc)
    current = entry.get("revision") == value["revision"]
    fresh = current and entry.get("retry_after", "") > now.isoformat()
    if fresh:
        return await public_support(db, entry)
    if not prepare:
        return {"status": "idle", "books": [], "idea": None, "videos": []}
    active = sum(
        e.get("status") in {"checking", "running"}
        and e.get("retry_after", "") > now.isoformat()
        for e in entries.values()
    )
    if active >= 2:
        raise HTTPException(
            429, "Other supporting materials are being prepared. Try again shortly."
        )
    token = str(uuid4())
    entry = {
        "status": "checking",
        "revision": value["revision"],
        "token": token,
        "input": value,
        "retry_after": (now + timedelta(minutes=10)).isoformat(),
        "result": {"books": value["books"]},
    }
    entries[value["key"]] = entry
    item.meta_json = {**(item.meta_json or {}), "learning_support": entries}
    await db.commit()  # Durable lease before publishing to the queue.
    from app.tasks.content_resources import generate_learning_support

    try:
        generate_learning_support.apply_async(
            args=[str(item_id), value["key"], token], queue="low_priority"
        )
    except Exception:
        # Preserve other concurrent metadata writes and release this exact lease.
        item = await _get_item_for_user(db, str(item_id), user.id, for_update=True)
        entries = dict((item.meta_json or {}).get("learning_support") or {})
        if entries.get(value["key"], {}).get("token") == token:
            entry = {
                **entry,
                "status": "unavailable",
                "retry_after": (now + timedelta(minutes=2)).isoformat(),
            }
            entries[value["key"]] = entry
            item.meta_json = {**(item.meta_json or {}), "learning_support": entries}
            await db.commit()
        raise HTTPException(
            503, "Supporting materials could not be queued. Try again shortly."
        ) from None
    return await public_support(db, entry)


@router.get("/{item_id}/learning-support")
async def read_support(
    item_id: UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    step_id: str | None = Query(None, max_length=100),
    book_title: str | None = Query(None, max_length=300),
):
    return await _support(item_id, db, user, step_id, book_title, False)


@router.post("/{item_id}/learning-support")
async def prepare_support(
    item_id: UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    step_id: str | None = Query(None, max_length=100),
    book_title: str | None = Query(None, max_length=300),
):
    return await _support(item_id, db, user, step_id, book_title, True)
