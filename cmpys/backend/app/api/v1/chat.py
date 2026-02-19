"""
Chat with idol personas endpoints.

PROMPT MAPPING:
- POST /chat/threads/{id}/messages
  - Service: app.services.chat.responder.generate_reply()
  - Prompts: chat_system.txt, chat_reply.txt
  - LLM: REQUIRED (returns 503 if not configured)
  
- All other endpoints: NO LLM (database operations only)
"""
import logging
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.config import settings
from app.core.db import get_db, async_session_maker
from app.models.chat import ChatMessage, ChatThread, MessageRole
from app.models.idol import Idol
from app.models.idol_persona import IdolPersona
from app.models.idol_profile import IdolProfile
from app.models.idol_timeline import IdolTimelineEvent
from app.models.user import User
from app.models.user_profile import UserProfile
from app.models.user_achievement import UserAchievement
from app.models.plan import Plan, PlanItem
from app.schemas.chat import (
    AssistantReplyResponse,
    MessageCreate,
    MessageResponse,
    ThreadCreate,
    ThreadDetailResponse,
    ThreadListResponse,
    ThreadResponse,
)
from app.services.chat import generate_reply
import json as json_lib
import openai
from app.services.chat.responder import LLMNotConfiguredError, _persona_to_json, _profile_to_json, _grounding_facts_to_json, _user_context_to_json, _milestones_to_json, _conversation_to_json

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/chat", tags=["chat"])


def _message_to_response(message: ChatMessage) -> MessageResponse:
    """Convert message model to response."""
    return MessageResponse(
        id=message.id,
        threadId=message.thread_id,
        role=message.role,
        content=message.content,
        createdAt=message.created_at,
    )


def _thread_to_response(
    thread: ChatThread,
    idol_name: str | None = None,
    idol_image_url: str | None = None,
    message_count: int = 0,
    last_message: ChatMessage | None = None,
) -> ThreadResponse:
    """Convert thread model to response."""
    return ThreadResponse(
        id=thread.id,
        userId=thread.user_id,
        idolId=thread.idol_id,
        idolName=idol_name,
        idolImageUrl=idol_image_url,
        createdAt=thread.created_at,
        messageCount=message_count,
        lastMessage=_message_to_response(last_message) if last_message else None,
    )


@router.post("/threads", response_model=ThreadResponse, status_code=status.HTTP_201_CREATED)
async def create_thread(
    data: ThreadCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ThreadResponse:
    """
    Create a new chat thread with an idol.
    
    LLM USAGE: NONE (database operation only)
    """
    # Verify idol exists
    idol_stmt = select(Idol).where(Idol.id == data.idolId)
    idol_result = await db.execute(idol_stmt)
    idol = idol_result.scalar_one_or_none()
    
    if not idol:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idol not found",
        )
    
    thread = ChatThread(
        user_id=current_user.id,
        idol_id=data.idolId,
    )
    db.add(thread)
    await db.commit()
    await db.refresh(thread)
    
    return _thread_to_response(thread, idol_name=idol.name, idol_image_url=idol.image_url)


@router.get("/threads", response_model=ThreadListResponse)
async def list_threads(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> ThreadListResponse:
    """
    List user's chat threads.
    
    LLM USAGE: NONE (database query only)
    """
    # Get total count
    count_stmt = (
        select(func.count())
        .select_from(ChatThread)
        .where(ChatThread.user_id == current_user.id)
    )
    count_result = await db.execute(count_stmt)
    total = count_result.scalar() or 0
    
    # Get threads with idol info
    stmt = (
        select(ChatThread)
        .options(selectinload(ChatThread.idol), selectinload(ChatThread.messages))
        .where(ChatThread.user_id == current_user.id)
        .order_by(ChatThread.created_at.desc())
        .offset(offset)
        .limit(limit)
    )
    result = await db.execute(stmt)
    threads = result.scalars().unique().all()
    
    thread_responses = []
    for thread in threads:
        last_msg = thread.messages[-1] if thread.messages else None
        thread_responses.append(_thread_to_response(
            thread,
            idol_name=thread.idol.name if thread.idol else None,
            idol_image_url=thread.idol.image_url if thread.idol else None,
            message_count=len(thread.messages),
            last_message=last_msg,
        ))
    
    return ThreadListResponse(threads=thread_responses, total=total)


@router.get("/threads/{thread_id}", response_model=ThreadDetailResponse)
async def get_thread(
    thread_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ThreadDetailResponse:
    """
    Get a chat thread with all messages.
    
    LLM USAGE: NONE (database query only)
    """
    stmt = (
        select(ChatThread)
        .options(selectinload(ChatThread.idol), selectinload(ChatThread.messages))
        .where(
            and_(
                ChatThread.id == thread_id,
                ChatThread.user_id == current_user.id,
            )
        )
    )
    result = await db.execute(stmt)
    thread = result.scalar_one_or_none()
    
    if not thread:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Thread not found",
        )
    
    return ThreadDetailResponse(
        id=thread.id,
        userId=thread.user_id,
        idolId=thread.idol_id,
        idolName=thread.idol.name if thread.idol else None,
        idolImageUrl=thread.idol.image_url if thread.idol else None,
        createdAt=thread.created_at,
        messages=[_message_to_response(m) for m in thread.messages],
    )


@router.get("/threads/{thread_id}/messages", response_model=list[MessageResponse])
async def list_messages(
    thread_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    limit: int = Query(50, ge=1, le=100),
    before: str | None = Query(None, description="Get messages before this ID"),
) -> list[MessageResponse]:
    """
    Get messages for a thread.
    
    LLM USAGE: NONE (database query only)
    """
    # Verify thread ownership
    thread_stmt = select(ChatThread).where(
        and_(
            ChatThread.id == thread_id,
            ChatThread.user_id == current_user.id,
        )
    )
    result = await db.execute(thread_stmt)
    if not result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Thread not found",
        )
    
    # Get messages
    stmt = (
        select(ChatMessage)
        .where(ChatMessage.thread_id == thread_id)
        .order_by(ChatMessage.created_at.desc())
        .limit(limit)
    )
    
    if before:
        # Get timestamp of 'before' message
        before_msg = await db.get(ChatMessage, before)
        if before_msg:
            stmt = stmt.where(ChatMessage.created_at < before_msg.created_at)
            
    result = await db.execute(stmt)
    messages = result.scalars().all()
    
    # Return in chronological order
    return [_message_to_response(m) for m in reversed(messages)]


@router.post("/threads/{thread_id}/messages", response_model=AssistantReplyResponse)
async def send_message(
    thread_id: str,
    data: MessageCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> AssistantReplyResponse:
    """
    Send a message in a thread and get AI response.
    
    PROMPT FILES USED:
    - chat_system.txt (system prompt with persona)
    - chat_reply.txt (user prompt template)
    
    LLM USAGE: REQUIRED
    - Returns 503 if LLM not configured
    
    SERVICE: app.services.chat.responder.generate_reply()
    """
    # Load thread with messages
    stmt = (
        select(ChatThread)
        .options(selectinload(ChatThread.messages))
        .where(
            and_(
                ChatThread.id == thread_id,
                ChatThread.user_id == current_user.id,
            )
        )
    )
    result = await db.execute(stmt)
    thread = result.scalar_one_or_none()
    
    if not thread:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Thread not found",
        )
    
    # Load idol for name
    idol_stmt = select(Idol).where(Idol.id == thread.idol_id)
    idol_result = await db.execute(idol_stmt)
    idol = idol_result.scalar_one_or_none()
    idol_name = idol.name if idol else "Unknown"
    
    # Load idol persona
    persona_stmt = select(IdolPersona).where(IdolPersona.idol_id == thread.idol_id)
    persona_result = await db.execute(persona_stmt)
    persona = persona_result.scalar_one_or_none()
    
    # Load idol profile
    profile_stmt = select(IdolProfile).where(IdolProfile.idol_id == thread.idol_id)
    profile_result = await db.execute(profile_stmt)
    profile = profile_result.scalar_one_or_none()
    
    # Get user's age for context (if available)
    user_age = None
    user_profile_stmt = select(UserProfile).where(UserProfile.user_id == current_user.id)
    user_profile_result = await db.execute(user_profile_stmt)
    user_profile = user_profile_result.scalar_one_or_none()
    
    if user_profile and user_profile.birth_date:
        today = date.today()
        user_age = today.year - user_profile.birth_date.year
    
    # Load milestones at user's age
    milestones: list[IdolTimelineEvent] = []
    if user_age:
        milestones_stmt = (
            select(IdolTimelineEvent)
            .where(
                and_(
                    IdolTimelineEvent.idol_id == thread.idol_id,
                    IdolTimelineEvent.age_at_event <= user_age,
                )
            )
            .order_by(IdolTimelineEvent.importance_score.desc())
            .limit(5)
        )
        milestones_result = await db.execute(milestones_stmt)
        milestones = list(milestones_result.scalars().all())
    
    # Store user message
    user_msg = ChatMessage(
        thread_id=thread.id,
        role=MessageRole.USER,
        content=data.content,
    )
    db.add(user_msg)
    await db.flush()
    
    try:
        # Generate reply using the chat service
        # Service: app.services.chat.responder.generate_reply()
        # Prompts: chat_system.txt + chat_reply.txt
        reply_result = await generate_reply(
            user_message=data.content,
            idol_name=idol_name,
            profile=profile,
            persona=persona,
            milestones=milestones,
            conversation_history=list(thread.messages),
            user_age=user_age,
        )
        
        reply_content = reply_result.content
        disclaimer = reply_result.disclaimer
        
    except LLMNotConfiguredError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LLM not configured. Set LLM_PROVIDER=openai and OPENAI_API_KEY to enable chat.",
        )
    
    # Store assistant message
    assistant_msg = ChatMessage(
        thread_id=thread.id,
        role=MessageRole.ASSISTANT,
        content=reply_content,
    )
    db.add(assistant_msg)
    await db.commit()
    
    await db.refresh(user_msg)
    await db.refresh(assistant_msg)
    
    return AssistantReplyResponse(
        userMessage=_message_to_response(user_msg),
        assistantMessage=_message_to_response(assistant_msg),
        disclaimer=disclaimer,
    )


@router.post("/threads/{thread_id}/messages/stream")
async def send_message_stream(
    thread_id: str,
    data: MessageCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> StreamingResponse:
    """
    Send a message and stream the AI response in real-time using SSE.
    
    Returns Server-Sent Events with the format:
    - data: {"type": "chunk", "content": "..."} - streamed text chunks
    - data: {"type": "done", "messageId": "..."} - completion signal
    - data: {"type": "error", "error": "..."} - error signal
    """
    # Load thread with messages
    stmt = (
        select(ChatThread)
        .where(
            and_(
                ChatThread.id == thread_id,
                ChatThread.user_id == current_user.id,
            )
        )
    )
    result = await db.execute(stmt)
    thread = result.scalar_one_or_none()
    
    if not thread:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Thread not found",
        )
    
    # Load idol for name
    idol_stmt = select(Idol).where(Idol.id == thread.idol_id)
    idol_result = await db.execute(idol_stmt)
    idol = idol_result.scalar_one_or_none()
    idol_name = idol.name if idol else "Unknown"
    
    # Load idol persona
    persona_stmt = select(IdolPersona).where(IdolPersona.idol_id == thread.idol_id)
    persona_result = await db.execute(persona_stmt)
    persona = persona_result.scalar_one_or_none()
    
    # Load idol profile
    profile_stmt = select(IdolProfile).where(IdolProfile.idol_id == thread.idol_id)
    profile_result = await db.execute(profile_stmt)
    profile = profile_result.scalar_one_or_none()
    
    # Get user's age for context
    user_age = None
    user_profile_stmt = select(UserProfile).where(UserProfile.user_id == current_user.id)
    user_profile_result = await db.execute(user_profile_stmt)
    user_profile = user_profile_result.scalar_one_or_none()
    
    if user_profile and user_profile.birth_date:
        today = date.today()
        user_age = today.year - user_profile.birth_date.year
    
    # Load milestones
    milestones: list[IdolTimelineEvent] = []
    if user_age:
        milestones_stmt = (
            select(IdolTimelineEvent)
            .where(
                and_(
                    IdolTimelineEvent.idol_id == thread.idol_id,
                    IdolTimelineEvent.age_at_event <= user_age,
                )
            )
            .order_by(IdolTimelineEvent.importance_score.desc())
            .limit(5)
        )
        milestones_result = await db.execute(milestones_stmt)
        milestones = list(milestones_result.scalars().all())
    
    # Load achievements
    ach_stmt = select(UserAchievement).where(UserAchievement.user_id == current_user.id)
    ach_result = await db.execute(ach_stmt)
    achievements = list(ach_result.scalars().all())
    
    # Load active plan
    plan_stmt = (
        select(Plan)
        .options(selectinload(Plan.items))
        .where(Plan.user_id == current_user.id)
        .order_by(Plan.created_at.desc())
        .limit(1)
    )
    plan_result = await db.execute(plan_stmt)
    active_plan = plan_result.scalar_one_or_none()

    # Store user message first
    user_msg = ChatMessage(
        thread_id=thread.id,
        role=MessageRole.USER,
        content=data.content,
    )
    db.add(user_msg)
    await db.flush()
    await db.refresh(user_msg)
    user_msg_id = user_msg.id
    
    async def generate_stream():
        """Generator for SSE stream."""
        import asyncio
        
        try:
            if not settings.llm_configured:
                yield f"data: {json_lib.dumps({'type': 'error', 'error': 'LLM not configured'})}\n\n"
                return
            
            # Format user context
            user_context_str = f"User Age: {user_age or 'Unknown'}\n"
            
            if user_profile:
                if user_profile.goals:
                    user_context_str += f"Goals: {', '.join(user_profile.goals)}\n"
                if user_profile.interests:
                    user_context_str += f"Interests: {', '.join(user_profile.interests)}\n"
            
            if achievements:
                ach_list = [a.title for a in achievements[:5]]
                user_context_str += f"Recent Achievements: {', '.join(ach_list)}\n"
            
            if active_plan:
                total_items = len(active_plan.items)
                avg_progress = int(sum(i.progress_percent for i in active_plan.items) / total_items) if total_items > 0 else 0
                user_context_str += f"Current Plan: {total_items} items, {avg_progress}% complete.\n"
                pending = [i.title for i in active_plan.items if i.status in ('pending', 'in_progress', 'not_started')][:3]
                if pending:
                    user_context_str += f"Focus items: {', '.join(pending)}\n"

            # Build prompts
            voice_style = persona.voice_style if persona else "Thoughtful and informative"
            principles = "\n".join(persona.principles) if persona and persona.principles else "Be helpful and honest."
            
            system_prompt = f"""You are {idol_name}, a simulated AI persona based on public information.

Voice Style: {voice_style}

Principles:
{principles}

User Context:
{user_context_str}

Instructions:
- Respond naturally and conversationally as {idol_name}
- Stay in character based on known facts about this person
- Be warm, engaging, and helpful
- Keep responses concise but meaningful
- DO NOT include JSON formatting - respond with plain text only
- DO NOT include disclaimers or meta-commentary about being an AI
- To suggest a concrete action for their plan, add: [SUGGESTION: Action Title] at the end."""

            # Simple user prompt for streaming
            conversation_history = ""
            for msg in list(thread.messages)[-10:]:  # Last 10 messages for context
                role = "User" if msg.role.value == "user" else idol_name
                conversation_history += f"{role}: {msg.content}\n"
            
            user_prompt = f"""Previous conversation:
{conversation_history}

User: {data.content}

Respond as {idol_name}:"""
            
            # Stream from OpenAI
            openai_client = openai.AsyncOpenAI(api_key=settings.openai_api_key)
            
            accumulated_content = ""
            stream = await openai_client.chat.completions.create(
                model=settings.openai_model or "gpt-4o-mini",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                stream=True,
                temperature=0.7,
            )
            
            async for chunk in stream:
                delta = chunk.choices[0].delta
                if delta.content:
                    accumulated_content += delta.content
                    yield f"data: {json_lib.dumps({'type': 'chunk', 'content': delta.content})}\n\n"
            
            # Store complete assistant message
            async with async_session_maker() as save_db:
                assistant_msg = ChatMessage(
                    thread_id=thread_id,
                    role=MessageRole.ASSISTANT,
                    content=accumulated_content,
                )
                save_db.add(assistant_msg)
                await save_db.commit()
                await save_db.refresh(assistant_msg)
                
                yield f"data: {json_lib.dumps({'type': 'done', 'messageId': str(assistant_msg.id), 'userMessageId': str(user_msg_id)})}\n\n"
                
        except Exception as e:
            logger.exception(f"[CHAT] Stream error: {e}")
            yield f"data: {json_lib.dumps({'type': 'error', 'error': str(e)})}\n\n"
    
    # Import session maker for saving
    from app.core.db import async_session_maker
    
    await db.commit()  # Commit user message before streaming
    
    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
