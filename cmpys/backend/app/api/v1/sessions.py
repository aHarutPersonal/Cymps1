"""
Agentic session endpoints for the 5-phase workflow.

Endpoints:
- POST   /sessions                       → Create session (Phase 1)
- POST   /sessions/{id}/suggest-idols    → Get 3 idol suggestions (Phase 2)
- POST   /sessions/{id}/select-idol      → Select idol, create thread (Phase 2→3)
- POST   /sessions/{id}/interview        → SSE interview stream (Phase 3)
- POST   /sessions/{id}/generate-results → SSE comparison + blueprint (Phase 4→5)
- GET    /sessions/{id}                  → Get session state
- GET    /sessions/current               → Get current active session
"""
import json as json_lib
import logging
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.chat import ChatThread, ChatMessage, MessageRole
from app.models.idol import Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.user import User
from app.schemas.session import (
    IdolSuggestionItem,
    IdolSuggestionsResponse,
    InterviewMessageRequest,
    SelectIdolRequest,
    SessionCreate,
    SessionResponse,
)
from app.services.gemini import (
    blueprint_stream,
    comparison_stream,
    interview_stream,
    stream_with_grounding,
)
from app.services.content_resources import attach_content_resources_to_materials
from app.services.llm.prompt_loader import load_and_render, load_prompt

logger = logging.getLogger("cmpys.api.sessions")

router = APIRouter(prefix="/sessions", tags=["sessions"])

# Maximum interview turns before forced transition
MAX_INTERVIEW_TURNS = 5
MIN_INTERVIEW_TURNS = 3


# =============================================================================
# Helpers
# =============================================================================


async def _get_session(
    session_id: str,
    user_id: str,
    db: AsyncSession,
) -> IntakeSession:
    """Load a session and verify ownership."""
    stmt = (
        select(IntakeSession)
        .options(selectinload(IntakeSession.idol))
        .where(
            IntakeSession.id == session_id,
            IntakeSession.user_id == user_id,
        )
    )
    result = await db.execute(stmt)
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return session


def _require_phase(session: IntakeSession, expected: SessionPhase) -> None:
    """Reject if session is not in the expected phase."""
    if session.phase != expected:
        raise HTTPException(
            status_code=409,
            detail=f"Session is in phase '{session.phase.value}', "
                   f"expected '{expected.value}'",
        )


def _build_session_response(session: IntakeSession) -> dict:
    """Build a session response dict from the model."""
    selected_idol = None
    if session.idol:
        selected_idol = {
            "id": session.idol.id,
            "name": session.idol.display_name,
            "era": getattr(session.idol, "era_tags", None),
        }
    return {
        "id": session.id,
        "phase": session.phase.value if session.phase else "intake",
        "user_age": session.user_age,
        "user_financial_status": session.user_financial_status,
        "user_interests": session.user_interests or [],
        "selected_idol": selected_idol,
        "interview_turn_count": session.interview_turn_count,
        "comparison_output": session.comparison_output,
        "blueprint_output": session.blueprint_output,
        "interview_thread_id": session.interview_thread_id,
        "created_at": session.created_at.isoformat() if session.created_at else None,
        "updated_at": session.updated_at.isoformat() if session.updated_at else None,
    }


def _build_chat_history_json(messages: list[ChatMessage]) -> str:
    """Build a JSON string of chat history for prompt injection."""
    history = []
    for msg in messages:
        history.append({
            "role": msg.role.value,
            "content": msg.content,
        })
    return json_lib.dumps(history, indent=2)


# =============================================================================
# T012: POST /sessions — Create session (Phase 1: Intake)
# =============================================================================


@router.post("", response_model=SessionResponse)
async def create_session(
    data: SessionCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Create a new agentic session with intake data.
    
    Accepts age, financial status, and interests.
    Returns a new session in the 'intake' phase, then auto-transitions
    to 'idol_selection'.
    """
    # Check for existing active session (edge case from analysis U1)
    stmt = select(IntakeSession).where(
        IntakeSession.user_id == current_user.id,
        IntakeSession.phase.isnot(None),
        IntakeSession.phase != SessionPhase.COMPLETED,
    )
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"Active session already exists (id: {existing.id}, "
                   f"phase: {existing.phase.value}). Complete or abandon it first.",
        )
    
    session = IntakeSession(
        id=str(uuid.uuid4()),
        user_id=current_user.id,
        phase=SessionPhase.INTAKE,
        user_age=data.age,
        user_financial_status=data.financial_status,
        user_interests=data.interests,
        status="draft",  # Legacy field compatibility
    )
    db.add(session)
    
    # Auto-transition to idol_selection since intake data is provided inline
    session.transition_to(SessionPhase.IDOL_SELECTION)
    
    await db.commit()
    await db.refresh(session)
    
    logger.info(f"[SESSION] Created session {session.id} for user {current_user.id}")
    return _build_session_response(session)


# =============================================================================
# T013: POST /sessions/{id}/suggest-idols — Get 3 idol suggestions
# =============================================================================


@router.post("/{session_id}/suggest-idols", response_model=IdolSuggestionsResponse)
async def suggest_idols(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Generate 3 idol suggestions based on intake data.
    
    Uses Gemini + Google Search to find idols whose achievements
    at the user's age are most relevant to their interests.
    """
    session = await _get_session(session_id, current_user.id, db)
    _require_phase(session, SessionPhase.IDOL_SELECTION)
    
    # Render the idol suggestion prompt
    prompt = load_and_render("idol_suggest.txt", {
        "user_age": str(session.user_age),
        "user_financial_status": session.user_financial_status,
        "user_interests_json": json_lib.dumps(session.user_interests),
    })
    
    # Call Gemini with Google Search for factual grounding
    full_response = ""
    async for chunk in stream_with_grounding(
        system_prompt="You are a mentor matching system. Return valid JSON only.",
        user_message=prompt,
    ):
        full_response += chunk
    
    # Parse the LLM response into structured suggestions
    try:
        parsed = json_lib.loads(full_response)
        suggestions_raw = parsed.get("suggestions", [])
    except json_lib.JSONDecodeError:
        logger.error(f"[SESSION] Failed to parse idol suggestions: {full_response[:200]}")
        raise HTTPException(
            status_code=502,
            detail="Failed to parse idol suggestions from AI",
        )
    
    suggestions = [
        IdolSuggestionItem(
            name=s.get("name", "Unknown"),
            era=s.get("era", "Unknown"),
            relevance_summary=s.get("relevance_summary", ""),
            wikidata_id=s.get("wikidata_id"),
            domains=s.get("domains", []),
            confidence=s.get("confidence", 0.8),
        )
        for s in suggestions_raw[:3]
    ]
    
    logger.info(f"[SESSION] Generated {len(suggestions)} idol suggestions for session {session_id}")
    return IdolSuggestionsResponse(suggestions=suggestions)


# =============================================================================
# T014: POST /sessions/{id}/select-idol — Select idol + create thread
# =============================================================================


@router.post("/{session_id}/select-idol", response_model=SessionResponse)
async def select_idol(
    session_id: str,
    data: SelectIdolRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Select an idol for the session.
    
    Finds or imports the idol, creates a chat thread,
    and transitions to the 'interview' phase.
    """
    session = await _get_session(session_id, current_user.id, db)
    _require_phase(session, SessionPhase.IDOL_SELECTION)
    
    # Try to find existing idol by name
    stmt = select(Idol).where(Idol.display_name == data.idol_name)
    result = await db.execute(stmt)
    idol = result.scalar_one_or_none()
    
    if not idol:
        # Create a minimal idol record; full import can happen async
        idol = Idol(
            id=str(uuid.uuid4()),
            display_name=data.idol_name,
            wikidata_id=data.wikidata_id,
            is_ready=False,
        )
        db.add(idol)
        await db.flush()  # Get the idol ID
    
    # Create a chat thread for the interview
    thread = ChatThread(
        id=str(uuid.uuid4()),
        user_id=current_user.id,
        idol_id=idol.id,
    )
    db.add(thread)
    await db.flush()
    
    # Update session
    session.idol_id = idol.id
    session.interview_thread_id = thread.id
    session.transition_to(SessionPhase.INTERVIEW)
    
    await db.commit()
    await db.refresh(session, ["idol"])
    
    logger.info(
        f"[SESSION] Selected idol '{data.idol_name}' for session {session_id}, "
        f"thread {thread.id}"
    )
    return _build_session_response(session)


# =============================================================================
# T015 + T021: GET /sessions/{id} — Get session state
# =============================================================================


@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Get the current state of a session.
    
    Used for polling, resume, and state display.
    Returns full session data including phase, turn count, outputs.
    """
    session = await _get_session(session_id, current_user.id, db)
    return _build_session_response(session)


# =============================================================================
# T022: GET /sessions/current — Get current active session
# =============================================================================


@router.get("/current", response_model=SessionResponse | None)
async def get_current_session(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Get the user's most recent non-completed session, if any.
    
    Used by the frontend on app launch to detect and resume
    an in-progress session.
    """
    stmt = (
        select(IntakeSession)
        .options(selectinload(IntakeSession.idol))
        .where(
            IntakeSession.user_id == current_user.id,
            IntakeSession.phase.isnot(None),
            IntakeSession.phase != SessionPhase.COMPLETED,
        )
        .order_by(IntakeSession.created_at.desc())
        .limit(1)
    )
    result = await db.execute(stmt)
    session = result.scalar_one_or_none()
    
    if not session:
        return None
    
    return _build_session_response(session)


# =============================================================================
# T016 + T017: POST /sessions/{id}/interview — SSE interview stream
# =============================================================================


@router.post("/{session_id}/interview")
async def interview(
    session_id: str,
    data: InterviewMessageRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Send a message during the interview phase (SSE stream).
    
    The AI responds in-character as the selected idol, asks exactly
    one question per turn, and enforces turn limits (3–5 turns).
    """
    session = await _get_session(session_id, current_user.id, db)
    _require_phase(session, SessionPhase.INTERVIEW)
    
    if not session.interview_thread_id:
        raise HTTPException(status_code=400, detail="No interview thread linked")
    
    # Load chat history from the thread
    stmt = (
        select(ChatThread)
        .options(selectinload(ChatThread.messages))
        .where(ChatThread.id == session.interview_thread_id)
    )
    result = await db.execute(stmt)
    thread = result.scalar_one_or_none()
    if not thread:
        raise HTTPException(status_code=404, detail="Interview thread not found")
    
    # Persist the user's message
    user_msg = ChatMessage(
        id=str(uuid.uuid4()),
        thread_id=thread.id,
        role=MessageRole.USER,
        content=data.content,
    )
    db.add(user_msg)
    await db.flush()
    
    # Build context for the prompt
    chat_history_json = _build_chat_history_json(thread.messages)
    
    idol_name = session.idol.display_name if session.idol else "Unknown"
    idol_persona = getattr(session.idol, "persona_pack", None) or {}
    
    # On first turn, fetch idol facts via Google Search
    if session.interview_turn_count == 0 and not session.idol_facts_json:
        logger.info(f"[SESSION] Fetching idol facts for {idol_name} at age {session.user_age}")
        facts_prompt = (
            f"What had {idol_name} achieved by age {session.user_age}? "
            f"List specific, verified accomplishments with dates. Return as JSON array."
        )
        facts_response = ""
        async for chunk in stream_with_grounding(
            system_prompt="You are a historical fact checker. Return accurate, sourced facts.",
            user_message=facts_prompt,
        ):
            facts_response += chunk
        session.idol_facts_json = {"raw_facts": facts_response}
    
    # Load and render the system prompt (interview_system.xml)
    system_prompt = load_and_render("interview_system.xml", {
        "idol_name": idol_name,
        "idol_era": idol_persona.get("era_context", "unknown"),
        "idol_domain": ", ".join(idol_persona.get("topics_of_strength", [])),
        "voice_style": idol_persona.get("voice_style", "authoritative"),
        "signature_phrases": ", ".join(idol_persona.get("signature_phrases", [])),
        "user_age": str(session.user_age),
        "user_financial_status": session.user_financial_status or "",
        "user_interests_json": json_lib.dumps(session.user_interests or []),
        "chat_history_json": chat_history_json,
    })
    
    # Render the per-turn user prompt
    user_prompt = load_and_render("interview_question.txt", {
        "idol_name": idol_name,
        "user_age": str(session.user_age),
        "user_financial_status": session.user_financial_status or "",
        "user_interests_json": json_lib.dumps(session.user_interests or []),
        "chat_history_json": chat_history_json,
        "turn_count": str(session.interview_turn_count + 1),
        "max_turns": str(MAX_INTERVIEW_TURNS),
        "idol_facts_json": json_lib.dumps(session.idol_facts_json or {}),
        "user_message": data.content,
    })
    
    # Determine if this should be the last turn
    current_turn = session.interview_turn_count + 1
    should_transition = current_turn >= MAX_INTERVIEW_TURNS
    
    async def generate_stream():
        nonlocal should_transition
        full_response = ""
        
        try:
            async for chunk in interview_stream(
                system_prompt=system_prompt,
                user_message=user_prompt,
                conversation_history=chat_history_json,
            ):
                full_response += chunk
                yield f"data: {json_lib.dumps({'type': 'chunk', 'content': chunk})}\n\n"
            
            # Persist the AI's response
            async with db.begin_nested():
                ai_msg = ChatMessage(
                    id=str(uuid.uuid4()),
                    thread_id=thread.id,
                    role=MessageRole.ASSISTANT,
                    content=full_response,
                )
                db.add(ai_msg)
                
                # Update turn count
                session.interview_turn_count = current_turn
                
                # Check for soft transition (AI signals completion after min turns)
                if current_turn >= MIN_INTERVIEW_TURNS:
                    # Check for completion signals in the response
                    completion_signals = [
                        "now I know the measure of you",
                        "let me show you",
                        "I've heard enough",
                        "the interview is over",
                        "I have my answer",
                    ]
                    if any(sig in full_response.lower() for sig in completion_signals):
                        should_transition = True
                
                # Hard cap enforcement
                if should_transition:
                    session.transition_to(SessionPhase.COMPARISON)
                
                await db.commit()
            
            # Send done event with phase transition info
            yield f"data: {json_lib.dumps({'type': 'done', 'turn': current_turn, 'max_turns': MAX_INTERVIEW_TURNS, 'phase_transition': should_transition})}\n\n"
            
        except Exception as e:
            logger.error(f"[SESSION] Interview stream error: {e}")
            yield f"data: {json_lib.dumps({'type': 'error', 'message': str(e)})}\n\n"
    
    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


# =============================================================================
# T019 + T020: POST /sessions/{id}/generate-results — Comparison + Blueprint
# =============================================================================


@router.post("/{session_id}/generate-results")
async def generate_results(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Generate the brutal comparison and quarterly blueprint (SSE stream).
    
    Streams two sections sequentially:
    1. Comparison (Phase 4) — emotionally intense reality check
    2. Blueprint (Phase 5) — actionable Q1–Q4 roadmap
    """
    session = await _get_session(session_id, current_user.id, db)
    _require_phase(session, SessionPhase.COMPARISON)
    
    if not session.interview_thread_id:
        raise HTTPException(status_code=400, detail="No interview thread")
    
    # Load full interview transcript
    stmt = (
        select(ChatThread)
        .options(selectinload(ChatThread.messages))
        .where(ChatThread.id == session.interview_thread_id)
    )
    result = await db.execute(stmt)
    thread = result.scalar_one_or_none()
    if not thread:
        raise HTTPException(status_code=404, detail="Interview thread not found")
    
    interview_transcript = _build_chat_history_json(thread.messages)
    idol_name = session.idol.display_name if session.idol else "Unknown"
    idol_persona = getattr(session.idol, "persona_pack", None) or {}
    
    # Build user profile JSON
    user_profile = {
        "age": session.user_age,
        "financial_status": session.user_financial_status,
        "interests": session.user_interests,
    }
    
    # Persona system prompt (reusable for both phases)
    persona_system = (
        f"You are {idol_name}. Stay 100% in character. First person only. "
        f"Never break character. Never use AI disclaimers."
    )
    
    async def generate_stream():
        # =====================================================================
        # Part 1: Brutal Comparison (Phase 4)
        # =====================================================================
        yield f"data: {json_lib.dumps({'type': 'section', 'section': 'comparison'})}\n\n"
        
        comparison_prompt = load_and_render("comparison_generate.txt", {
            "idol_name": idol_name,
            "user_age": str(session.user_age),
            "user_profile_json": json_lib.dumps(user_profile),
            "interview_transcript_json": interview_transcript,
            "idol_facts_json": json_lib.dumps(session.idol_facts_json or {}),
        })
        
        full_comparison = ""
        try:
            async for chunk in comparison_stream(
                system_prompt=persona_system,
                user_message=comparison_prompt,
            ):
                full_comparison += chunk
                yield f"data: {json_lib.dumps({'type': 'chunk', 'section': 'comparison', 'content': chunk})}\n\n"
            
            # Persist comparison output
            session.comparison_output = full_comparison
            session.transition_to(SessionPhase.BLUEPRINT)
            await db.commit()
            
        except Exception as e:
            logger.error(f"[SESSION] Comparison stream error: {e}")
            yield f"data: {json_lib.dumps({'type': 'error', 'section': 'comparison', 'message': str(e)})}\n\n"
            return
        
        # =====================================================================
        # Part 2: Quarterly Blueprint (Phase 5)
        # =====================================================================
        yield f"data: {json_lib.dumps({'type': 'section', 'section': 'blueprint'})}\n\n"
        
        blueprint_prompt = load_and_render("blueprint_generate.txt", {
            "idol_name": idol_name,
            "user_age": str(session.user_age),
            "user_profile_json": json_lib.dumps(user_profile),
            "interview_transcript_json": interview_transcript,
            "comparison_summary": full_comparison[:2000],  # Truncate for context window
            "idol_facts_json": json_lib.dumps(session.idol_facts_json or {}),
        })
        
        full_blueprint = ""
        try:
            async for chunk in blueprint_stream(
                system_prompt=persona_system,
                user_message=blueprint_prompt,
            ):
                full_blueprint += chunk
                yield f"data: {json_lib.dumps({'type': 'chunk', 'section': 'blueprint', 'content': chunk})}\n\n"
            
            # Persist blueprint and transition to completed
            session.blueprint_output = full_blueprint
            session.transition_to(SessionPhase.COMPLETED)
            await db.commit()
            
        except Exception as e:
            logger.error(f"[SESSION] Blueprint stream error: {e}")
            yield f"data: {json_lib.dumps({'type': 'error', 'section': 'blueprint', 'message': str(e)})}\n\n"
            return
        
        # Final done event
        yield f"data: {json_lib.dumps({'type': 'done', 'phase': 'completed'})}\n\n"
    
    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )

# =============================================================================
# Guided Learning Endpoints (Phase 6)
# =============================================================================

from app.schemas.session import GuidedLearningMessageRequest, LearningMaterialsResponse, LearningMaterialResponse, LearningTopicRequest
from app.services.gemini import stream_learnlm

@router.post("/{session_id}/learning-materials", response_model=LearningMaterialsResponse)
async def get_learning_materials(
    session_id: str,
    data: LearningTopicRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Fetch curated learning materials for a specific blueprint topic.
    Uses Google Search grounding to find real articles and videos.
    """
    session = await _get_session(session_id, current_user.id, db)
    
    prompt = (
        f"Find 3 highly educational, beginner-friendly resources (mix of articles and videos) "
        f"to help someone learn about: '{data.topic}'. "
        f"Return ONLY a JSON array of objects with keys: 'title', 'url', 'type' (must be 'article' or 'video'), and 'summary'."
    )
    
    full_response = ""
    async for chunk in stream_with_grounding(
        system_prompt="You are an expert curriculum designer. Return valid JSON only.",
        user_message=prompt,
    ):
        full_response += chunk
        
    try:
        # Strip markdown json block if present
        if full_response.strip().startswith("```json"):
            full_response = full_response.strip()[7:-3]
            
        parsed = json_lib.loads(full_response)
        raw_materials = [
            {
                "title": m.get("title", "Resource"),
                "url": m.get("url", "#"),
                "type": m.get("type", "article"),
                "summary": m.get("summary", ""),
                "reason": m.get("summary", ""),
                "search_query": m.get("search_query") or m.get("title", ""),
            }
            for m in parsed[:3]
        ]
        enriched_materials = await attach_content_resources_to_materials(
            db,
            raw_materials,
            user_goal=data.topic,
        )
        materials = [
            LearningMaterialResponse(
                title=m.get("title", "Resource"),
                url=m.get("url") or "#",
                type=m.get("type", "article"),
                summary=m.get("summary") or m.get("reason") or "",
                content_resource_id=m.get("content_resource_id"),
                canonical_key=m.get("canonical_key"),
                license_status=m.get("license_status"),
                thumbnail_url=m.get("thumbnail_url"),
                duration_minutes=m.get("duration_minutes"),
            )
            for m in enriched_materials
        ]
        return LearningMaterialsResponse(materials=materials)
    except Exception as e:
        logger.error(f"[SESSION] Failed to parse learning materials: {e}. Raw: {full_response}")
        raise HTTPException(status_code=502, detail="Failed to fetch learning materials")


@router.post("/{session_id}/guided-learning")
async def guided_learning(
    session_id: str,
    data: GuidedLearningMessageRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Stream a Socratic tutoring response using LearnLM.
    """
    session = await _get_session(session_id, current_user.id, db)
    
    if session.phase not in [SessionPhase.BLUEPRINT, SessionPhase.GUIDED_LEARNING, SessionPhase.COMPLETED]:
        session.transition_to(SessionPhase.GUIDED_LEARNING)
    
    if not session.learning_thread_id:
        thread = ChatThread(
            id=str(uuid.uuid4()),
            user_id=current_user.id,
            idol_id=session.idol_id,
        )
        db.add(thread)
        await db.flush()
        session.learning_thread_id = thread.id
        await db.commit()
    else:
        stmt = select(ChatThread).options(selectinload(ChatThread.messages)).where(ChatThread.id == session.learning_thread_id)
        result = await db.execute(stmt)
        thread = result.scalar_one()

    # Persist user message
    user_msg = ChatMessage(
        id=str(uuid.uuid4()),
        thread_id=session.learning_thread_id,
        role=MessageRole.USER,
        content=data.content,
    )
    db.add(user_msg)
    await db.flush()
    
    chat_history_json = _build_chat_history_json(thread.messages if 'thread' in locals() and hasattr(thread, 'messages') else [])
    
    idol_name = session.idol.display_name if session.idol else "Your Mentor"
    idol_persona = getattr(session.idol, "persona_pack", None) or {}
    
    async def generate_stream():
        full_response = ""
        try:
            async for chunk in stream_learnlm(
                idol_name=idol_name,
                idol_persona_context=json_lib.dumps(idol_persona),
                user_message=data.content,
                conversation_history=chat_history_json,
            ):
                full_response += chunk
                yield f"data: {json_lib.dumps({'type': 'chunk', 'content': chunk})}\n\n"
                
            async with db.begin_nested():
                ai_msg = ChatMessage(
                    id=str(uuid.uuid4()),
                    thread_id=session.learning_thread_id,
                    role=MessageRole.ASSISTANT,
                    content=full_response,
                )
                db.add(ai_msg)
                await db.commit()
                
            yield f"data: {json_lib.dumps({'type': 'done'})}\n\n"
        except Exception as e:
            logger.error(f"[SESSION] Guided learning stream error: {e}")
            yield f"data: {json_lib.dumps({'type': 'error', 'message': str(e)})}\n\n"
            
    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive"}
    )

# =============================================================================
# T023: GET /sessions/{id}/feed — Generate Daily Insights (Idea Cards)
# =============================================================================

from app.schemas.session import DailyFeedResponse, DailyInsightResponse

@router.get("/{session_id}/feed", response_model=DailyFeedResponse)
async def get_daily_feed(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Generate a daily feed of bite-sized insights (Idea Cards) from the idol.
    """
    session = await _get_session(session_id, current_user.id, db)
    
    idol_name = session.idol.display_name if session.idol else "Your Mentor"
    
    user_profile = {
        "age": session.user_age,
        "financial_status": session.user_financial_status,
        "interests": session.user_interests,
    }
    
    prompt = load_and_render("daily_feed_generate.txt", {
        "count": "3",
        "idol_name": idol_name,
        "user_profile_json": json_lib.dumps(user_profile),
    })
    
    full_response = ""
    async for chunk in stream_with_grounding(
        system_prompt=f"You are {idol_name}. Deliver profound microlearning insights.",
        user_message=prompt,
    ):
        full_response += chunk
        
    try:
        # Strip markdown json block if present
        if full_response.strip().startswith("```json"):
            full_response = full_response.strip()[7:-3]
        elif full_response.strip().startswith("```"):
            full_response = full_response.strip()[3:-3]
            
        parsed = json_lib.loads(full_response)
        insights = [
            DailyInsightResponse(
                title=item.get("title", "Insight"),
                content=item.get("content", ""),
                category=item.get("category", "Mindset"),
            )
            for item in parsed[:3]
        ]
        return DailyFeedResponse(insights=insights)
    except Exception as e:
        logger.error(f"[SESSION] Failed to parse daily feed: {e}. Raw: {full_response}")
        raise HTTPException(status_code=502, detail="Failed to fetch daily feed")
