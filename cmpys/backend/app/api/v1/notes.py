"""User notes CRUD endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.note import Note, NoteAttachment
from app.models.user import User
from app.schemas.note import (
    NoteAttachmentResponse,
    NoteCreate,
    NoteListResponse,
    NoteResponse,
    NoteUpdate,
)

router = APIRouter(prefix="/notes", tags=["notes"])


def _to_response(note: Note) -> NoteResponse:
    """Convert model to response schema."""
    return NoteResponse(
        id=note.id,
        userId=note.user_id,
        title=note.title,
        content=note.content,
        attachments=[
            NoteAttachmentResponse(
                id=a.id,
                idolId=a.idol_id,
                planItemId=a.plan_item_id,
                achievementId=a.achievement_id,
            )
            for a in note.attachments
        ],
        createdAt=note.created_at,
        updatedAt=note.updated_at,
    )


@router.post("", response_model=NoteResponse, status_code=status.HTTP_201_CREATED)
async def create_note(
    data: NoteCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> NoteResponse:
    """Create a new note."""
    note = Note(
        user_id=current_user.id,
        title=data.title,
        content=data.content,
    )
    db.add(note)
    await db.flush()

    # Add attachments
    for att_data in data.attachments:
        attachment = NoteAttachment(
            note_id=note.id,
            idol_id=att_data.idolId,
            plan_item_id=att_data.planItemId,
            achievement_id=att_data.achievementId,
        )
        db.add(attachment)

    await db.commit()

    # Reload with attachments
    stmt = (
        select(Note).options(selectinload(Note.attachments)).where(Note.id == note.id)
    )
    result = await db.execute(stmt)
    note = result.scalar_one()

    return _to_response(note)


@router.get("", response_model=NoteListResponse)
async def list_notes(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    q: str | None = Query(None, description="Search in title and content"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> NoteListResponse:
    """List user notes with optional search."""
    stmt = (
        select(Note)
        .options(selectinload(Note.attachments))
        .where(Note.user_id == current_user.id)
    )

    if q:
        search_filter = or_(
            Note.title.ilike(f"%{q}%"),
            Note.content.ilike(f"%{q}%"),
        )
        stmt = stmt.where(search_filter)

    # Get total count
    count_stmt = select(func.count(Note.id)).where(Note.user_id == current_user.id)
    if q:
        count_stmt = stmt.with_only_columns(func.count(Note.id)).order_by(None)
    total_result = await db.execute(count_stmt)
    total = total_result.scalar() or 0

    # Get paginated results
    stmt = stmt.order_by(Note.created_at.desc())
    stmt = stmt.offset(offset).limit(limit)

    result = await db.execute(stmt)
    notes = result.scalars().unique().all()

    return NoteListResponse(
        notes=[_to_response(n) for n in notes],
        total=total,
    )


@router.get("/{note_id}", response_model=NoteResponse)
async def get_note(
    note_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> NoteResponse:
    """Get a specific note."""
    stmt = (
        select(Note)
        .options(selectinload(Note.attachments))
        .where(
            and_(
                Note.id == note_id,
                Note.user_id == current_user.id,
            )
        )
    )
    result = await db.execute(stmt)
    note = result.scalar_one_or_none()

    if not note:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Note not found",
        )

    return _to_response(note)


@router.patch("/{note_id}", response_model=NoteResponse)
async def update_note(
    note_id: str,
    data: NoteUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> NoteResponse:
    """Update a note."""
    stmt = (
        select(Note)
        .options(selectinload(Note.attachments))
        .where(
            and_(
                Note.id == note_id,
                Note.user_id == current_user.id,
            )
        )
    )
    result = await db.execute(stmt)
    note = result.scalar_one_or_none()

    if not note:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Note not found",
        )

    if data.title is not None:
        note.title = data.title
    if data.content is not None:
        note.content = data.content

    # Handle attachments update
    if data.attachments is not None:
        # Remove existing attachments
        for att in note.attachments:
            await db.delete(att)

        # Add new attachments
        for att_data in data.attachments:
            attachment = NoteAttachment(
                note_id=note.id,
                idol_id=att_data.idolId,
                plan_item_id=att_data.planItemId,
                achievement_id=att_data.achievementId,
            )
            db.add(attachment)

    await db.commit()

    # Reload with attachments
    stmt = (
        select(Note).options(selectinload(Note.attachments)).where(Note.id == note.id)
    )
    result = await db.execute(stmt)
    note = result.scalar_one()

    return _to_response(note)


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_note(
    note_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> None:
    """Delete a note."""
    stmt = select(Note).where(
        and_(
            Note.id == note_id,
            Note.user_id == current_user.id,
        )
    )
    result = await db.execute(stmt)
    note = result.scalar_one_or_none()

    if not note:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Note not found",
        )

    await db.delete(note)
    await db.commit()
