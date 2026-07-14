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
import asyncio
import json as json_lib
import logging
import re
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload, selectinload

from app.api.dependencies import get_current_user
from app.core.db import get_db
from app.models.chat import ChatThread, ChatMessage, MessageRole
from app.models.idol import CatalogStatus, Idol
from app.models.intake import IntakeSession, SessionPhase
from app.models.plan_job import PlanGenerationJob
from app.models.user import User
from app.schemas.session import (
    DailyFeedResponse,
    DailyInsightResponse,
    GuidedLearningMessageRequest,
    IdolSuggestionItem,
    IdolSuggestionsResponse,
    InterviewMessageRequest,
    LearningMaterialResponse,
    LearningMaterialsResponse,
    LearningTopicRequest,
    SelectIdolRequest,
    SessionCreate,
    SessionResponse,
)
from app.services.gemini import (
    blueprint_stream,
    comparison_stream,
    interview_stream,
    generate_with_grounding,
    stream_learnlm,
)
from app.services.comparison.scoring import generate_comparison_scores
from app.services.content_resources import attach_content_resources_to_materials
from app.services.llm import get_llm_client
from app.services.llm.prompt_loader import load_and_render, sanitize_untrusted_input
from app.services.idol_photos import is_verified_idol_photo, resolve_wikimedia_photo
from app.services.transcripts import build_chat_history_json

logger = logging.getLogger("cmpys.api.sessions")

router = APIRouter(prefix="/sessions", tags=["sessions"])

# Maximum interview turns before forced transition
MAX_INTERVIEW_TURNS = 5
MIN_INTERVIEW_TURNS = 3

# Explicit end-of-interview marker the model is instructed to append to its
# closing turn. Primary completion signal — unambiguous, unlike phrase
# matching ("let me show you" appears in ordinary mid-interview turns).
INTERVIEW_COMPLETE_MARKER = "[INTERVIEW_COMPLETE]"

# Fallback signals for responses where the model forgot the marker. Only
# phrases that are unambiguous closers belong here.
_COMPLETION_FALLBACK_SIGNALS = (
    "now i know the measure of you",
    "the interview is over",
)


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
        .options(
            joinedload(IntakeSession.idol).joinedload(Idol.profile),
            joinedload(IntakeSession.idol).joinedload(Idol.persona),
        )
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


_FALLBACK_IDOLS = [
    ("Steve Jobs", "20th-21st century", ["technology", "design", "business"],
     "Built world-changing products by pairing ruthless focus with obsessive design taste."),
    ("Warren Buffett", "20th-21st century", ["business", "finance", "investing"],
     "Compounded a fortune through patient, long-term value investing and disciplined temperament."),
    ("Marie Curie", "19th-20th century", ["science", "research", "physics"],
     "Pioneered radioactivity research through relentless curiosity and methodical rigor."),
    ("Leonardo da Vinci", "Renaissance", ["art", "science", "engineering"],
     "Fused art and science, mastering many fields through endless observation and notebooks."),
    ("Ada Lovelace", "19th century", ["technology", "mathematics", "science"],
     "Saw the creative potential of computing a century early through rigorous mathematical insight."),
]


def _fallback_idol_suggestions(interests: list[str]) -> list["IdolSuggestionItem"]:
    """Curated mentor suggestions used when live generation is unavailable.
    Ranks the pool by overlap with the user's interests, always returns 3."""
    wanted = {i.lower() for i in (interests or [])}

    def score(domains: list[str]) -> int:
        return len({d.lower() for d in domains} & wanted)

    ranked = sorted(_FALLBACK_IDOLS, key=lambda e: score(e[2]), reverse=True)
    return [
        IdolSuggestionItem(
            name=name,
            era=era,
            relevance_summary=summary,
            wikidata_id=None,
            domains=domains,
            confidence=0.4,
        )
        for name, era, domains, summary in ranked[:3]
    ]


async def _attach_suggestion_photos(
    suggestions: list["IdolSuggestionItem"],
) -> list["IdolSuggestionItem"]:
    """Attach verified Commons portraits without serial lookup latency.

    Published catalog suggestions already carry their verified image URL. LLM,
    fallback, and legacy cached suggestions are resolved by stable Wikidata id
    when available and by name otherwise. Resolution returns only
    license-verified Wikimedia photos; a miss remains ``None`` so the client
    can use its monogram fallback instead of an untrusted image.
    """

    async def attach(suggestion: IdolSuggestionItem) -> IdolSuggestionItem:
        if suggestion.image_url:
            return suggestion
        try:
            photo = await resolve_wikimedia_photo(
                name=suggestion.name,
                wikidata_qid=suggestion.wikidata_id,
            )
        except Exception as exc:
            logger.warning(
                "[SESSION] Portrait resolution failed for %s: %s",
                suggestion.name,
                exc,
            )
            return suggestion
        image_url = str((photo or {}).get("image_url") or "").strip()
        return (
            suggestion.model_copy(update={"image_url": image_url})
            if image_url
            else suggestion
        )

    return list(await asyncio.gather(*(attach(item) for item in suggestions)))


def _match_terms(values: list[str]) -> tuple[set[str], set[str]]:
    """Return normalized phrases and useful tokens for deterministic matching."""
    phrases = {str(value).strip().lower() for value in values if str(value).strip()}
    tokens: set[str] = set()
    for phrase in phrases:
        tokens.update(
            token
            for token in re.findall(r"[a-z0-9+#-]{3,}", phrase)
            if token not in {"and", "the", "with", "from", "that", "this", "want"}
        )
    return phrases, tokens


def _idol_era(idol: Idol) -> str:
    profile = idol.profile
    birth = getattr(profile, "birth_date", None) or idol.birth_date
    death = getattr(profile, "death_date", None)
    if birth and death:
        return f"{birth.year}-{death.year}"
    if birth:
        return f"born {birth.year}"
    era_tags = list(getattr(profile, "era_tags", None) or [])
    return era_tags[0] if era_tags else "documented biography"


async def _catalog_idol_suggestions(
    db: AsyncSession | None,
    *,
    interests: list[str],
    user_goal: str | None,
    user_age: int | None,
    limit: int = 3,
) -> list["IdolSuggestionItem"]:
    """Return strong, age-grounded matches from the published local catalog.

    The catalog path is intentionally conservative: it only wins over the
    grounded LLM fallback when at least three entries match the user's domain
    and contain a sufficiently confident milestone at or before their age.
    """
    if db is None or user_age is None:
        return []

    from app.models.idol_tag_link import IdolTagLink

    stmt = (
        select(Idol)
        .options(
            selectinload(Idol.profile),
            selectinload(Idol.timeline_events),
            selectinload(Idol.external_ids),
            selectinload(Idol.tag_links).selectinload(IdolTagLink.tag),
        )
        .where(Idol.status == CatalogStatus.PUBLISHED)
        .limit(200)
    )
    result = await db.execute(stmt)
    idols = list(result.scalars().unique().all())

    phrases, wanted_tokens = _match_terms(
        [*(interests or []), *([user_goal] if user_goal else [])]
    )
    if not phrases and not wanted_tokens:
        return []

    ranked: list[tuple[float, str, IdolSuggestionItem]] = []
    for idol in idols:
        if idol.quality_score is not None and idol.quality_score < 0.55:
            continue

        profile = idol.profile
        tags = [link.tag.name for link in idol.tag_links if getattr(link, "tag", None)]
        labels = [
            idol.domain,
            *(getattr(profile, "domains", None) or []),
            *(getattr(profile, "primary_roles", None) or []),
            *(getattr(profile, "notable_themes", None) or []),
            *tags,
        ]
        label_phrases, label_tokens = _match_terms(labels)
        exact_matches = phrases & label_phrases
        token_matches = wanted_tokens & label_tokens
        match_score = len(exact_matches) * 4 + len(token_matches)
        if match_score < 2:
            continue

        milestones = [
            event
            for event in idol.timeline_events
            if event.age_at_event is not None
            and event.age_at_event <= user_age
            and event.confidence >= 0.55
        ]
        if not milestones:
            continue
        milestone = max(
            milestones,
            key=lambda event: (
                event.importance_score,
                event.age_at_event or 0,
                event.confidence,
            ),
        )

        primary_domains = list(getattr(profile, "domains", None) or [])
        if not primary_domains and idol.domain:
            primary_domains = [idol.domain]
        matched = sorted(exact_matches or token_matches)
        match_label = matched[0] if matched else (primary_domains[0] if primary_domains else idol.domain)
        achievement = re.sub(r"\s+", " ", milestone.canonical_description).strip()
        if len(achievement) > 260:
            achievement = achievement[:257].rsplit(" ", 1)[0] + "..."
        relevance = (
            f"By age {milestone.age_at_event}, {achievement} "
            f"This directly connects to your interest in {match_label}."
        )
        wikidata_id = next(
            (
                external.external_id
                for external in idol.external_ids
                if external.provider == "wikidata"
            ),
            None,
        )
        confidence = min(
            0.98,
            0.70
            + min(match_score, 8) * 0.02
            + milestone.confidence * 0.08
            + (idol.quality_score or 0.7) * 0.08,
        )
        primary_domain = primary_domains[0].lower() if primary_domains else idol.domain.lower()
        ranked.append(
            (
                match_score + milestone.importance_score + (idol.quality_score or 0.0),
                primary_domain,
                IdolSuggestionItem(
                    name=idol.name,
                    era=_idol_era(idol),
                    relevance_summary=relevance,
                    wikidata_id=wikidata_id,
                    image_url=(idol.image_url if is_verified_idol_photo(idol) else None),
                    domains=primary_domains[:4],
                    confidence=round(confidence, 2),
                ),
            )
        )

    ranked.sort(key=lambda entry: entry[0], reverse=True)

    # Import pipelines may leave multiple records for the same public figure
    # (for example a Wikidata-backed row and an older LLM-discovered row).
    # Never spend two of the three suggestion slots on the same display name.
    unique_ranked: list[tuple[float, str, IdolSuggestionItem]] = []
    seen_names: set[str] = set()
    for entry in ranked:
        normalized_name = re.sub(
            r"\s+",
            " ",
            entry[2].name.strip().casefold(),
        )
        if normalized_name in seen_names:
            continue
        seen_names.add(normalized_name)
        unique_ranked.append(entry)
    ranked = unique_ranked

    if len(ranked) < limit:
        return []

    # Greedily prefer a second domain while retaining score order.
    selected: list[tuple[float, str, IdolSuggestionItem]] = [ranked.pop(0)]
    while ranked and len(selected) < limit:
        used_domains = {entry[1] for entry in selected}
        diverse_index = next(
            (index for index, entry in enumerate(ranked) if entry[1] not in used_domains),
            0,
        )
        selected.append(ranked.pop(diverse_index))
    return [entry[2] for entry in selected]


# "10 hours a week", "8-12 hrs/week", "about 15h per week" in a message that
# mentions a week. Range midpoint is used; values are clamped to a sane band.
_HOURS_RE = re.compile(
    r"(\d{1,3})(?:\s*(?:-|–|—|\bto\b)\s*(\d{1,3}))?\s*(?:hours?|hrs?|h)\b",
    re.IGNORECASE,
)


def _extract_weekly_hours(messages: list[ChatMessage]) -> int | None:
    """Best-effort weekly-hours commitment from the user's interview answers.

    Scans user turns only (the mentor quotes numbers about its own life), takes
    the LAST match so later corrections win, and clamps to 2–60. Returns None
    when nothing parseable was said — callers fall back to the default.
    """
    found: int | None = None
    for msg in messages:
        if msg.role != MessageRole.USER:
            continue
        text = msg.content or ""
        if "week" not in text.lower():
            continue
        for m in _HOURS_RE.finditer(text):
            lo = int(m.group(1))
            hi = int(m.group(2)) if m.group(2) else lo
            hours = round((lo + hi) / 2)
            if 1 <= hours <= 100:
                found = max(2, min(60, hours))
    return found


async def _sync_interview_turn_count(session: IntakeSession, db) -> None:
    """Set the session's interview turn count from the number of persisted
    assistant messages in its thread — the durable source of truth, robust to
    streams that drop before the counter was bumped.
    """
    result = await db.execute(
        select(func.count(ChatMessage.id)).where(
            ChatMessage.thread_id == session.interview_thread_id,
            ChatMessage.role == MessageRole.ASSISTANT,
        )
    )
    session.interview_turn_count = result.scalar_one()


def _persona_to_dict(persona) -> dict:
    """Convert an IdolPersona object to a dict for JSON serialization and .get() access."""
    if persona is None:
        return {}
    return {
        "voice_style": persona.voice_style or "",
        "principles": persona.principles or [],
        "dos": persona.dos or [],
        "donts": persona.donts or [],
        "signature_phrases": persona.signature_phrases or [],
        "topics_of_strength": persona.topics_of_strength or [],
        "taboo_topics": persona.taboo_topics or [],
        "era_context": persona.era_context or "contemporary",
        "lexicon_allow": persona.lexicon_allow or [],
        "lexicon_ban": persona.lexicon_ban or [],
        "worldview_adapter": persona.worldview_adapter or {},
        "default_frameworks": persona.default_frameworks or [],
        "disclaimer": persona.disclaimer or "",
    }


def _strip_json_fences(text: str) -> str:
    """Strip a wrapping markdown code fence (``` or ```json) from an LLM response."""
    stripped = text.strip()
    if stripped.startswith("```"):
        first_newline = stripped.find("\n")
        if first_newline != -1:
            stripped = stripped[first_newline + 1:]
        if stripped.endswith("```"):
            stripped = stripped[:-3]
    return stripped.strip()


def _unique_idol_suggestions(
    suggestions: list[IdolSuggestionItem],
    *,
    limit: int = 3,
) -> list[IdolSuggestionItem]:
    """Keep the first suggestion for each stable identity and display name."""
    unique: list[IdolSuggestionItem] = []
    seen_external_ids: set[str] = set()
    seen_names: set[str] = set()
    for suggestion in suggestions:
        normalized_name = re.sub(
            r"\s+",
            " ",
            suggestion.name.strip().casefold(),
        )
        external_id = (suggestion.wikidata_id or "").strip().casefold()
        if normalized_name in seen_names:
            continue
        if external_id and external_id in seen_external_ids:
            continue
        seen_names.add(normalized_name)
        if external_id:
            seen_external_ids.add(external_id)
        unique.append(suggestion)
        if len(unique) >= limit:
            break
    return unique


def _render_persona_system(idol_name: str, idol_persona: dict) -> str:
    """Render the evidence-based mentor portrayal with full voice fidelity.

    The fallback remains transparent when ingestion has not produced a persona
    pack yet; missing evidence must never weaken the identity boundary."""
    if not idol_persona:
        return (
            f"You are the CMPYS Mentor, an AI portrayal inspired by public "
            f"information about {idol_name}; you are not the literal person and "
            "do not possess their memories or identity. Be useful and candid, "
            "but do not invent biographical facts, quotations, or lived "
            "experience. If asked who you are, state this boundary plainly."
        )
    return load_and_render("persona_system.txt", {
        "idol_name": idol_name,
        "voice_style": idol_persona.get("voice_style") or "direct and authoritative",
        "principles": "; ".join(idol_persona.get("principles", [])) or "none documented",
        "dos": "; ".join(idol_persona.get("dos", [])) or "none documented",
        "donts": "; ".join(idol_persona.get("donts", [])) or "none documented",
        "signature_phrases": ", ".join(idol_persona.get("signature_phrases", [])) or "none documented",
        "lexicon_allow": ", ".join(idol_persona.get("lexicon_allow", [])) or "language consistent with your era",
        "lexicon_ban": ", ".join(idol_persona.get("lexicon_ban", [])) or "modern jargon inconsistent with your era",
        "worldview_adapter_json": json_lib.dumps(idol_persona.get("worldview_adapter", {})),
        "taboo_topics": ", ".join(idol_persona.get("taboo_topics", [])) or "none documented",
        "era_context": idol_persona.get("era_context") or "contemporary",
        "disclaimer": idol_persona.get("disclaimer") or "",
    })


# Session ids whose scores backfill was already enqueued by this process.
# Cheap dedup so polling clients don't flood the queue; the task itself is
# idempotent, so a duplicate after a restart is harmless.
_scores_backfill_enqueued: set[str] = set()


def _maybe_enqueue_scores_backfill(session: IntakeSession) -> None:
    """Self-heal sessions with a comparison verdict but no structured scores.

    Without scores the client silently falls back to seed (demo) numbers, so
    any fetch of such a session queues background generation. Best-effort:
    a broker hiccup must never fail the read path.
    """
    if session.comparison_scores_json is not None or not session.comparison_output:
        return
    session_id = str(session.id)
    if session_id in _scores_backfill_enqueued:
        return
    _scores_backfill_enqueued.add(session_id)
    try:
        from app.tasks.comparison import backfill_comparison_scores

        backfill_comparison_scores.apply_async(
            args=[session_id], queue="low_priority"
        )
        logger.info(f"[CMP_SCORES] Enqueued scores backfill for session={session_id}")
    except Exception as e:
        logger.warning(f"[CMP_SCORES] Could not enqueue backfill for {session_id}: {e}")


def _build_session_response(session: IntakeSession) -> dict:
    """Build a session response dict from the model."""
    selected_idol = None
    if session.idol:
        # Read the idol's era only if its profile relationship is already
        # loaded — touching an unloaded relationship here would trigger an
        # async lazy-load outside the greenlet (MissingGreenlet) right after a
        # commit, e.g. for a freshly-created idol in select_idol.
        era = None
        try:
            from sqlalchemy import inspect as sa_inspect
            if "profile" not in sa_inspect(session.idol).unloaded:
                profile = session.idol.profile
                era_tags = getattr(profile, "era_tags", None) if profile else None
                # IdolProfile.era_tags is a PostgreSQL array, while the
                # session contract exposes one concise display string. Older
                # sessions may therefore surface values like
                # ["modern_era"]; never pass that list into Pydantic's string
                # field or the otherwise-valid session read becomes a 500.
                if isinstance(era_tags, str):
                    era = era_tags
                elif isinstance(era_tags, (list, tuple)):
                    era = next(
                        (str(tag).strip() for tag in era_tags if str(tag).strip()),
                        None,
                    )
        except Exception:
            era = None
        selected_idol = {
            "id": session.idol.id,
            "name": session.idol.name,
            "era": era,
        }
    return {
        "id": session.id,
        "phase": session.phase.value if session.phase else "intake",
        "user_age": session.user_age,
        "user_financial_status": session.user_financial_status,
        "user_interests": session.user_interests or [],
        "user_goal": getattr(session, "user_goal", None),
        "selected_idol": selected_idol,
        "interview_turn_count": session.interview_turn_count,
        "comparison_output": session.comparison_output,
        "blueprint_output": session.blueprint_output,
        "comparisonScores": getattr(session, "comparison_scores_json", None),
        "interview_thread_id": session.interview_thread_id,
        "created_at": session.created_at.isoformat() if session.created_at else None,
        "updated_at": session.updated_at.isoformat() if session.updated_at else None,
    }


def _build_chat_history_json(
    messages: list[ChatMessage],
    *,
    max_chars: int | None = None,
) -> str:
    """Build a JSON string of chat history for prompt injection.

    Delegates to the shared serializer with ``sanitize_user=True`` so
    user-authored turns are wrapped with the untrusted-input delimiters (the
    model treats them as DATA, not instructions) in interview / comparison /
    blueprint generation. Assistant turns are model-generated and left as-is.
    """
    return build_chat_history_json(
        messages,
        max_chars=max_chars,
        sanitize_user=True,
    )


# =============================================================================
# T012: POST /sessions - Create session (Phase 1: Intake)
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
        user_goal=data.goal,
        status="draft",  # Legacy field compatibility
    )
    db.add(session)

    # Auto-transition to idol_selection since intake data is provided inline
    session.transition_to(SessionPhase.IDOL_SELECTION)

    await db.commit()
    await db.refresh(session)

    logger.info(f"[SESSION] Created session {session.id} for user {current_user.id}")
    return _build_session_response(session)


@router.post("/{session_id}/abandon", status_code=status.HTTP_204_NO_CONTENT)
async def abandon_session(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Abandon an in-progress session so the user can start a fresh one.

    Terminal action from any phase: marks the session COMPLETED so it stops
    being the user's "current" active session and `create_session` no longer
    409s. Idempotent — abandoning an already-finished/absent session is a no-op.
    """
    session = await _get_session(session_id, current_user.id, db)
    if session.phase != SessionPhase.COMPLETED:
        # Bypass transition validation — abandon is terminal from any phase.
        session.phase = SessionPhase.COMPLETED
        await db.commit()
        logger.info(f"[SESSION] Abandoned session {session_id}")


# =============================================================================
# T013: POST /sessions/{id}/suggest-idols - Get 3 idol suggestions
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

    # The inputs (age/status/interests) are frozen on the session, so the
    # first successful generation is definitive — reuse it on retries and
    # back-navigation instead of a fresh 5-15s grounded LLM call.
    if session.idol_suggestions_json:
        cached = _unique_idol_suggestions(
            [IdolSuggestionItem(**s) for s in session.idol_suggestions_json]
        )
        if len(cached) >= 3:
            cached = await _attach_suggestion_photos(cached)
            if (
                len(cached) != len(session.idol_suggestions_json)
                or any(
                    cached_item.model_dump(mode="json") != stored_item
                    for cached_item, stored_item in zip(
                        cached, session.idol_suggestions_json, strict=False
                    )
                )
            ):
                session.idol_suggestions_json = [
                    suggestion.model_dump(mode="json") for suggestion in cached
                ]
                await db.commit()
            logger.info(
                "[SESSION] Returning %s cached idol suggestions for session %s",
                len(cached),
                session_id,
            )
            return IdolSuggestionsResponse(suggestions=cached)
        # A stale duplicate-filled cache does not satisfy the three-mentor
        # contract. Let the catalog/grounded fallback replace it below.
        session.idol_suggestions_json = None

    # Fast path: use high-quality, age-grounded entries already paid for and
    # verified in the shared catalog. The helper returns an empty list unless
    # it can satisfy the full three-item quality bar, so weak local data never
    # displaces the grounded Gemini fallback.
    catalog_suggestions = await _catalog_idol_suggestions(
        db,
        interests=session.user_interests or [],
        user_goal=session.user_goal,
        user_age=session.user_age,
    )
    if len(catalog_suggestions) >= 3:
        catalog_suggestions = await _attach_suggestion_photos(catalog_suggestions)
        session.idol_suggestions_json = [
            suggestion.model_dump(mode="json") for suggestion in catalog_suggestions
        ]
        await db.commit()
        logger.info(
            "[SESSION] Returning %s published catalog suggestions for session %s",
            len(catalog_suggestions),
            session_id,
        )
        return IdolSuggestionsResponse(suggestions=catalog_suggestions)

    # Render the idol suggestion prompt
    prompt = load_and_render("idol_suggest.txt", {
        "user_age": str(session.user_age),
        "user_financial_status": session.user_financial_status,
        "user_interests_json": json_lib.dumps(session.user_interests),
        "user_goal": session.user_goal or "not specified",
    })

    # The catalog lookup is complete. Do not keep that read transaction and a
    # pooled connection open during the slower grounded fallback.
    if db is not None:
        await db.commit()

    # Call Gemini with Google Search for factual grounding. Any failure
    # (provider down, bad JSON) falls back to a curated set so the user is
    # never left with an empty selection screen.
    suggestions: list[IdolSuggestionItem] = []
    try:
        full_response = await generate_with_grounding(
            system_prompt=load_and_render("idol_suggest_system.txt", {}),
            user_message=prompt,
            operation="idol_suggestion",
        )

        parsed = json_lib.loads(_strip_json_fences(full_response))
        suggestions_raw = parsed.get("suggestions", [])
        suggestions = _unique_idol_suggestions([
            IdolSuggestionItem(
                name=s.get("name", "Unknown"),
                era=s.get("era", "Unknown"),
                relevance_summary=s.get("relevance_summary", ""),
                wikidata_id=s.get("wikidata_id"),
                domains=s.get("domains", []),
                confidence=s.get("confidence", 0.8),
            )
            for s in suggestions_raw[:3]
        ])
    except Exception as e:
        logger.error(f"[SESSION] Idol suggestion generation failed ({e}); using fallback")

    if len(suggestions) >= 3:
        suggestions = await _attach_suggestion_photos(suggestions)
        # Cache only real LLM output — the static fallback should not become
        # sticky; a failed generation gets retried on the next call.
        session.idol_suggestions_json = [s.model_dump(mode="json") for s in suggestions]
        await db.commit()
    else:
        suggestions = _fallback_idol_suggestions(session.user_interests or [])
        suggestions = await _attach_suggestion_photos(suggestions)

    logger.info(f"[SESSION] Generated {len(suggestions)} idol suggestions for session {session_id}")
    return IdolSuggestionsResponse(suggestions=suggestions)


# =============================================================================
# T014: POST /sessions/{id}/select-idol - Select idol + create thread
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

    # Prefer an existing canonical identity. Names are not unique in legacy
    # catalog data, so collect every case-insensitive match and rank them
    # deterministically instead of calling scalar_one_or_none (which raises
    # MultipleResultsFound and leaves the session in idol_selection).
    clean_name = data.idol_name.strip()
    stmt = (
        select(Idol)
        .options(selectinload(Idol.external_ids))
        .where(func.lower(func.trim(Idol.name)) == clean_name.lower())
    )
    result = await db.execute(stmt)
    candidates = list(result.scalars().all())

    def selection_rank(candidate: Idol) -> tuple[int, int, int, float, int, str]:
        external_ids = list(candidate.external_ids)
        requested_identity = bool(
            data.wikidata_id
            and any(
                external.provider == "wikidata"
                and external.external_id == data.wikidata_id
                for external in external_ids
            )
        )
        has_wikidata = any(
            external.provider == "wikidata" for external in external_ids
        )
        return (
            int(requested_identity),
            int(candidate.status == CatalogStatus.PUBLISHED),
            int(has_wikidata),
            candidate.quality_score if candidate.quality_score is not None else -1.0,
            int(candidate.published_at is not None),
            str(candidate.id),
        )

    idol = max(candidates, key=selection_rank, default=None)
    if len(candidates) > 1:
        logger.warning(
            "[SESSION] Resolved %s catalog rows named %r to idol %s",
            len(candidates),
            clean_name,
            idol.id if idol else "none",
        )

    if not idol:
        # Create a minimal idol record; full import can happen async
        idol = Idol(
            id=str(uuid.uuid4()),
            name=clean_name,
            domain="unknown",  # Placeholder until ingestion fills it in
        )
        # Store wikidata_id as an external ID if provided
        if data.wikidata_id:
            from app.models.idol_external_id import IdolExternalId
            ext_id = IdolExternalId(
                id=str(uuid.uuid4()),
                idol_id=idol.id,
                provider="wikidata",
                external_id=data.wikidata_id,
            )
            db.add(ext_id)
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
    session.idol = idol

    # Build the response BEFORE committing. db.commit() expires every attribute
    # (expire_on_commit), and re-reading them here in async context would
    # trigger MissingGreenlet lazy-loads. The in-memory values are already
    # correct, so snapshot them first, then persist.
    response = _build_session_response(session)
    await db.commit()

    # Prefetch the grounded idol facts in the background so the first
    # interview turn doesn't pay the 3-8s Google-Search round trip inline.
    # Best-effort: the interview path still fetches inline if this hasn't
    # landed (it only prefills session.idol_facts_json).
    asyncio.create_task(_prefetch_idol_facts(
        session_id=session.id,
        idol_name=data.idol_name,
        user_age=session.user_age,
    ))

    logger.info(
        f"[SESSION] Selected idol '{data.idol_name}' for session {session_id}, "
        f"thread {thread.id}"
    )
    return response


async def _prefetch_idol_facts(session_id: str, idol_name: str, user_age: int | None) -> None:
    """Background task: fetch idol facts and store them on the session.

    Uses its own DB session — the request's session is closed by the time
    this runs. Any failure is swallowed; the interview stream falls back to
    fetching the facts inline (guarded by `not session.idol_facts_json`).
    """
    from app.core.db import async_session_maker
    try:
        facts_prompt = (
            f"What had {idol_name} achieved by age {user_age}? "
            f"List specific, verified accomplishments as concise bullet points, "
            f"one per line, each with the year and {idol_name}'s age at the time."
        )
        facts_response = await generate_with_grounding(
            system_prompt="You are a historical fact checker. Return accurate, sourced facts.",
            user_message=facts_prompt,
            operation="idol_fact_lookup",
        )
        if not facts_response:
            return
        async with async_session_maker() as bg_db:
            result = await bg_db.execute(
                select(IntakeSession).where(IntakeSession.id == session_id)
            )
            bg_session = result.scalar_one_or_none()
            # Never clobber facts the interview path may have written first.
            if bg_session and not bg_session.idol_facts_json:
                bg_session.idol_facts_json = {"raw_facts": facts_response}
                await bg_db.commit()
                logger.info(f"[SESSION] Prefetched idol facts for session {session_id}")
    except Exception as e:
        logger.warning(f"[SESSION] Idol facts prefetch failed (will fetch inline): {e}")


# =============================================================================
# T015 + T021: GET /sessions/{id} - Get session state
# =============================================================================


# =============================================================================
# T022: GET /sessions/current - Get current active session
# =============================================================================
# NOTE: this MUST be declared before GET /{session_id} so the literal "current"
# path is not captured by the dynamic session-id route.


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
        .options(
            joinedload(IntakeSession.idol).joinedload(Idol.profile),
            joinedload(IntakeSession.idol).joinedload(Idol.persona),
        )
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

    _maybe_enqueue_scores_backfill(session)
    return _build_session_response(session)


@router.get("/latest", response_model=SessionResponse | None)
async def get_latest_session(
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """Return the user's newest session, including completed onboarding.

    ``/current`` is deliberately limited to resumable, non-completed sessions.
    Post-onboarding features need the completed session as their source of
    truth for the selected idol, comparison scores, blueprint, and plan-job
    recovery, so they must use this endpoint instead.
    """
    stmt = (
        select(IntakeSession)
        .options(
            joinedload(IntakeSession.idol).joinedload(Idol.profile),
            joinedload(IntakeSession.idol).joinedload(Idol.persona),
        )
        .where(IntakeSession.user_id == current_user.id)
        .order_by(IntakeSession.created_at.desc())
        .limit(1)
    )
    result = await db.execute(stmt)
    session = result.scalar_one_or_none()
    if not session:
        return None

    _maybe_enqueue_scores_backfill(session)
    return _build_session_response(session)


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
    _maybe_enqueue_scores_backfill(session)
    return _build_session_response(session)


# =============================================================================
# T016 + T017: POST /sessions/{id}/interview - SSE interview stream
# =============================================================================


def _interview_question_params(
    session,
    *,
    idol_name: str,
    chat_history_json: str,
    current_turn: int,
    user_message: str,
) -> dict[str, str]:
    """Params for interview_question.txt. Must cover every key the
    PROMPT_PLACEHOLDERS registry declares for it — a missing key raises
    PROMPT_PARAMS_MISSING mid-stream and kills the interview turn."""
    return {
        "idol_name": idol_name,
        "user_age": str(session.user_age),
        "user_financial_status": session.user_financial_status or "",
        "user_interests_json": json_lib.dumps(session.user_interests or []),
        "user_goal": session.user_goal or "not specified",
        "chat_history_json": chat_history_json,
        "turn_count": str(current_turn),
        "max_turns": str(MAX_INTERVIEW_TURNS),
        "idol_facts_json": json_lib.dumps(session.idol_facts_json or {}),
        "user_message": sanitize_untrusted_input(user_message),
    }


def _render_interview_prompts(
    session: IntakeSession,
    *,
    idol_name: str,
    idol_persona: dict,
    chat_history_json: str,
    current_turn: int,
    user_message: str,
) -> tuple[str, str]:
    """Render one interview turn with exactly one copy of chat history.

    The per-turn prompt owns the transcript. The system prompt still receives
    every required placeholder, but its history slot is deliberately empty so
    longer interviews do not pay for the same tokens twice.
    """
    system_prompt = load_and_render("interview_system.xml", {
        "idol_name": idol_name,
        "idol_era": idol_persona.get("era_context", "unknown"),
        "idol_domain": ", ".join(idol_persona.get("topics_of_strength", [])),
        "voice_style": idol_persona.get("voice_style", "authoritative"),
        "signature_phrases": ", ".join(idol_persona.get("signature_phrases", [])),
        "principles": "; ".join(idol_persona.get("principles", [])),
        "dos": "; ".join(idol_persona.get("dos", [])),
        "donts": "; ".join(idol_persona.get("donts", [])),
        "lexicon_allow": ", ".join(idol_persona.get("lexicon_allow", [])),
        "lexicon_ban": ", ".join(idol_persona.get("lexicon_ban", [])),
        "taboo_topics": ", ".join(idol_persona.get("taboo_topics", [])),
        "worldview_adapter_json": json_lib.dumps(idol_persona.get("worldview_adapter", {})),
        "user_age": str(session.user_age),
        "user_financial_status": session.user_financial_status or "",
        "user_interests_json": json_lib.dumps(session.user_interests or []),
        "user_goal": session.user_goal or "not specified",
        "chat_history_json": "[]",
    })
    user_prompt = load_and_render(
        "interview_question.txt",
        _interview_question_params(
            session,
            idol_name=idol_name,
            chat_history_json=chat_history_json,
            current_turn=current_turn,
            user_message=user_message,
        ),
    )
    return system_prompt, user_prompt


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
    one question per turn, and enforces turn limits (3-5 turns).
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

    history_messages = list(thread.messages)

    # A reconstructed onboarding screen sends the hidden kickoff again. If an
    # opening question is already durable, replay it instead of charging for a
    # second model call and incrementing the interview twice.
    if (
        data.is_kickoff
        and session.interview_turn_count > 0
        and history_messages
        and history_messages[-1].role == MessageRole.ASSISTANT
    ):
        previous_question = history_messages[-1].content
        current_turn = session.interview_turn_count
        await db.commit()

        async def replay_opening_question():
            yield f"data: {json_lib.dumps({'type': 'chunk', 'content': previous_question})}\n\n"
            yield f"data: {json_lib.dumps({'type': 'done', 'turn': current_turn, 'max_turns': MAX_INTERVIEW_TURNS, 'phase_transition': False})}\n\n"

        logger.info(
            "[SESSION] Replaying completed interview turn %s for session %s",
            current_turn,
            session_id,
        )
        return StreamingResponse(
            replay_opening_question(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache, no-transform",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )

    has_pending_user_turn = bool(
        history_messages
        and history_messages[-1].role == MessageRole.USER
    )
    # If the screen was reconstructed after an answered turn failed, its
    # generic kickoff acts as a recovery signal: retry the durable unanswered
    # answer rather than discarding it and starting the interview over.
    resume_pending_answer = bool(data.is_kickoff and has_pending_user_turn)
    user_content = (
        history_messages[-1].content
        if resume_pending_answer
        else data.content
    )
    effective_kickoff = data.is_kickoff and not resume_pending_answer
    pending_retry = bool(
        has_pending_user_turn
        and history_messages[-1].content == user_content
    )
    prompt_history = (
        history_messages[:-1]
        if has_pending_user_turn
        else history_messages
    )

    # Persist the user's message — but never the kickoff protocol message.
    # It is the client speaking, not the person; persisting it would leak
    # "Hi — I'm ready. Ask me your first question." into the transcript that
    # comparison/blueprint later quote as the user's own words.
    if not effective_kickoff and not pending_retry:
        user_msg = ChatMessage(
            id=str(uuid.uuid4()),
            thread_id=thread.id,
            role=MessageRole.USER,
            content=user_content,
        )
        db.add(user_msg)
        await db.flush()

    # Build context for the prompt
    chat_history_json = _build_chat_history_json(prompt_history)

    idol_name = session.idol.name if session.idol else "Unknown"
    idol_persona_obj = getattr(session.idol, "persona", None)
    idol_persona = _persona_to_dict(idol_persona_obj)

    # Determine if this should be the last turn
    current_turn = session.interview_turn_count + 1
    should_transition = current_turn >= MAX_INTERVIEW_TURNS

    # End the short read/write transaction before handing control to a model
    # stream.  Otherwise this request keeps a pooled database connection
    # checked out for the entire (often 10-30 second) generation.
    await db.commit()

    async def generate_stream():
        nonlocal should_transition
        full_response = ""

        try:
            # Emit a byte immediately so the client sees the stream is alive
            # before the (first-turn) Google-Search grounding, which can take
            # several seconds. Without this the connection is silent and the app
            # can give up before the first interview chunk arrives.
            yield f"data: {json_lib.dumps({'type': 'status', 'message': 'thinking'})}\n\n"

            # On the first turn, fetch idol facts via Google Search — done
            # INSIDE the stream so the SSE response starts immediately rather
            # than blocking on grounding before the first byte.
            if session.interview_turn_count == 0 and not session.idol_facts_json:
                logger.info(f"[SESSION] Fetching idol facts for {idol_name} at age {session.user_age}")
                facts_prompt = (
                    f"What had {idol_name} achieved by age {session.user_age}? "
                    f"List specific, verified accomplishments as concise bullet points, "
                    f"one per line, each with the year and {idol_name}'s age at the time."
                )
                facts_response = await generate_with_grounding(
                    system_prompt="You are a historical fact checker. Return accurate, sourced facts.",
                    user_message=facts_prompt,
                    operation="interview_idol_fact_lookup",
                )
                session.idol_facts_json = {"raw_facts": facts_response}

            # Render both prompts inside the stream so render errors become SSE
            # error events. The verified fact sheet now lives in the per-turn
            # prompt, and the transcript is included exactly once.
            system_prompt, user_prompt = _render_interview_prompts(
                session,
                idol_name=idol_name,
                idol_persona=idol_persona,
                chat_history_json=chat_history_json,
                current_turn=current_turn,
                user_message=user_content,
            )

            async for chunk in interview_stream(
                system_prompt=system_prompt,
                user_message=user_prompt,
            ):
                full_response += chunk
                yield f"data: {json_lib.dumps({'type': 'chunk', 'content': chunk})}\n\n"

            # Persist the AI's response — with the completion marker stripped
            # so it never pollutes the transcript fed to comparison/blueprint.
            clean_response = full_response.replace(
                INTERVIEW_COMPLETE_MARKER, ""
            ).rstrip()
            if not clean_response.strip():
                raise RuntimeError("Interview model returned an empty response")

            ai_msg = ChatMessage(
                id=str(uuid.uuid4()),
                thread_id=thread.id,
                role=MessageRole.ASSISTANT,
                content=clean_response,
            )
            db.add(ai_msg)

            # Update turn count
            session.interview_turn_count = current_turn

            # Soft transition after min turns: the explicit marker the
            # prompt instructs the model to append is the primary signal;
            # a couple of unambiguous closing phrases are the fallback.
            if current_turn >= MIN_INTERVIEW_TURNS:
                lower = full_response.lower()
                if INTERVIEW_COMPLETE_MARKER.lower() in lower or any(
                    sig in lower for sig in _COMPLETION_FALLBACK_SIGNALS
                ):
                    should_transition = True

            # Hard cap enforcement
            if should_transition:
                session.transition_to(SessionPhase.COMPARISON)

            await db.commit()

            # Send done event with phase transition info
            yield f"data: {json_lib.dumps({'type': 'done', 'turn': current_turn, 'max_turns': MAX_INTERVIEW_TURNS, 'phase_transition': should_transition})}\n\n"

        except Exception as e:
            logger.exception("[SESSION] Interview stream error: %s", e)
            yield f"data: {json_lib.dumps({'type': 'error', 'message': 'The interview reply could not be completed. Please retry.'})}\n\n"

    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


# =============================================================================
# T019 + T020: POST /sessions/{id}/generate-results - Comparison + Blueprint
# =============================================================================


async def _get_or_create_session_plan_job(
    db,
    *,
    session: IntakeSession,
    user_id: str,
    weekly_hours: int,
) -> PlanGenerationJob | None:
    """Create the staged plan job as soon as result generation begins.

    The job remains at ``waiting_for_strategy`` until comparison + blueprint
    are persisted. This makes the post-interview pipeline immediate and
    observable without sacrificing plan quality by generating before its
    strategic inputs exist. Replays reuse active/completed work; a failed job
    gets one fresh row when the user explicitly retries the pipeline.
    """
    if not session.idol_id:
        return None

    existing = (
        await db.execute(
            select(PlanGenerationJob)
            .where(
                PlanGenerationJob.user_id == user_id,
                PlanGenerationJob.idol_id == session.idol_id,
                PlanGenerationJob.session_id == session.id,
                PlanGenerationJob.status.in_(["pending", "running", "completed"]),
            )
            .order_by(PlanGenerationJob.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if existing:
        if existing.status in {"pending", "running"}:
            last_update = getattr(existing, "updated_at", None) or getattr(
                existing, "created_at", None
            )
            if last_update is not None:
                if last_update.tzinfo is None:
                    last_update = last_update.replace(tzinfo=timezone.utc)
                if datetime.now(timezone.utc) - last_update >= timedelta(minutes=15):
                    existing.status = "failed"
                    existing.step = "error"
                    existing.error_message = "Generation worker stopped before completion"
                    await db.commit()
                    existing = None

    if existing:
        if existing.status == "pending" and existing.step == "waiting_for_strategy":
            existing.weekly_hours = weekly_hours
            await db.commit()
        return existing

    job = PlanGenerationJob(
        user_id=user_id,
        idol_id=session.idol_id,
        session_id=session.id,
        target_age=session.user_age or 24,
        duration_weeks=12,
        weekly_hours=weekly_hours,
        status="pending",
        progress_percent=0,
        step="waiting_for_strategy",
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)
    return job


async def _dispatch_session_plan_job(db, job: PlanGenerationJob | None) -> None:
    """Publish a staged plan job once its comparison/blueprint inputs exist."""
    if job is None or job.status in {"running", "completed"}:
        return
    if job.status == "pending" and job.step != "waiting_for_strategy":
        # Already published; Celery has not moved it to running yet.
        return

    job.status = "pending"
    job.step = "analyzing_gaps"
    job.progress_percent = 0
    job.error_message = None
    await db.commit()

    try:
        from app.tasks.plans import run_plan_generation

        run_plan_generation.delay(str(job.id))
    except Exception as exc:
        job.status = "failed"
        job.step = "error"
        job.error_message = "Plan generation could not be queued"
        await db.commit()
        raise exc


@router.post("/{session_id}/generate-results")
async def generate_results(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Run the automatic post-interview strategy pipeline (SSE stream).

    Streams comparison and strategic blueprint sequentially, then dispatches
    the staged 12-week execution plan. The order preserves plan quality while
    the client presents useful mentor-learning cards instead of a wait screen.
    """
    session = await _get_session(session_id, current_user.id, db)
    # Idempotent from every post-interview phase. BLUEPRINT resumes without
    # regenerating a successful comparison; COMPLETED replays cached artifacts
    # and recovers/returns the plan job after a dropped client connection.
    if session.phase not in (
        SessionPhase.COMPARISON,
        SessionPhase.BLUEPRINT,
        SessionPhase.COMPLETED,
    ):
        raise HTTPException(
            status_code=409,
            detail=(
                f"Session is in phase '{session.phase.value}', expected "
                "'comparison', 'blueprint', or 'completed'"
            ),
        )

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
    idol_name = session.idol.name if session.idol else "Unknown"
    idol_persona_obj = getattr(session.idol, "persona", None)
    idol_persona = _persona_to_dict(idol_persona_obj)

    # Build user profile JSON
    user_profile = {
        "age": session.user_age,
        "financial_status": session.user_financial_status,
        "interests": session.user_interests,
        "goal": session.user_goal,
    }

    # Weekly hours the user actually committed to during the interview;
    # falls back to the historical default when they never gave a number.
    weekly_hours = _extract_weekly_hours(thread.messages) or 10

    # Persona system prompt (reusable for both phases). comparison_generate.txt
    # and blueprint_generate.txt both defer voice, intensity, and era language
    # to "your persona (in the system prompt)" — so it must be the full pack.
    persona_system = _render_persona_system(idol_name, idol_persona)

    # Stage the plan job immediately. It is intentionally not published to a
    # worker until comparison + blueprint are ready, because those artifacts
    # are required inputs to the quality contract.
    plan_job = await _get_or_create_session_plan_job(
        db,
        session=session,
        user_id=current_user.id,
        weekly_hours=weekly_hours,
    )

    # Everything needed by the generator is now materialized in memory.
    # Release the connection while the two long model streams are running;
    # later persistence calls transparently acquire it again.
    await db.commit()

    async def generate_stream():
        if plan_job is not None:
            yield f"data: {json_lib.dumps({'type': 'plan_job', 'job_id': str(plan_job.id)})}\n\n"

        # =====================================================================
        # Part 1: Comparison — generate once, then replay on retry/resume.
        # =====================================================================
        scores_task = None
        full_comparison = session.comparison_output or ""
        yield f"data: {json_lib.dumps({'type': 'section', 'section': 'comparison'})}\n\n"

        if full_comparison:
            yield f"data: {json_lib.dumps({'type': 'chunk', 'section': 'comparison', 'content': full_comparison})}\n\n"
        else:
            if session.phase == SessionPhase.BLUEPRINT:
                # Repair the only inconsistent recoverable state: blueprint
                # phase without its prerequisite comparison artifact.
                session.transition_to(SessionPhase.COMPARISON)
                await db.commit()

            comparison_prompt = load_and_render("comparison_generate.txt", {
                "idol_name": idol_name,
                "user_age": str(session.user_age),
                "user_profile_json": json_lib.dumps(user_profile),
                "interview_transcript_json": interview_transcript,
                "idol_facts_json": json_lib.dumps(session.idol_facts_json or {}),
            })
            try:
                async for chunk in comparison_stream(
                    system_prompt=persona_system,
                    user_message=comparison_prompt,
                ):
                    full_comparison += chunk
                    yield f"data: {json_lib.dumps({'type': 'chunk', 'section': 'comparison', 'content': chunk})}\n\n"

                session.comparison_output = full_comparison
                if session.phase == SessionPhase.COMPARISON:
                    session.transition_to(SessionPhase.BLUEPRINT)
                await db.commit()
            except Exception as e:
                logger.error(f"[SESSION] Comparison stream error: {e}")
                # Remain in COMPARISON so the same endpoint can retry without
                # making the user repeat the interview.
                session.comparison_output = None
                await db.commit()
                yield f"data: {json_lib.dumps({'type': 'error', 'section': 'comparison', 'message': 'Comparison generation failed. Please try again.', 'retryable': True})}\n\n"
                return

        if session.comparison_scores_json is None:
            # Score generation depends only on the comparison, so overlap it
            # with blueprint writing and plan preparation.
            scores_task = asyncio.create_task(generate_comparison_scores(
                get_llm_client(),
                idol_name=idol_name,
                user_age=session.user_age,
                user_profile_json=json_lib.dumps(user_profile),
                interview_transcript_json=interview_transcript,
                idol_facts_json=json_lib.dumps(session.idol_facts_json or {}),
                comparison_summary=full_comparison,
            ))

        # =====================================================================
        # Part 2: Blueprint — resume without repeating comparison work.
        # =====================================================================
        yield f"data: {json_lib.dumps({'type': 'section', 'section': 'blueprint'})}\n\n"
        full_blueprint = session.blueprint_output or ""
        if full_blueprint:
            yield f"data: {json_lib.dumps({'type': 'chunk', 'section': 'blueprint', 'content': full_blueprint})}\n\n"
        else:
            blueprint_prompt = load_and_render("blueprint_generate.txt", {
                "idol_name": idol_name,
                "user_age": str(session.user_age),
                "user_profile_json": json_lib.dumps(user_profile),
                "interview_transcript_json": interview_transcript,
                "comparison_summary": full_comparison[:2000],
                "idol_facts_json": json_lib.dumps(session.idol_facts_json or {}),
                "weekly_hours": str(weekly_hours),
            })
            try:
                async for chunk in blueprint_stream(
                    system_prompt=persona_system,
                    user_message=blueprint_prompt,
                ):
                    full_blueprint += chunk
                    yield f"data: {json_lib.dumps({'type': 'chunk', 'section': 'blueprint', 'content': chunk})}\n\n"

                session.blueprint_output = full_blueprint
                if session.phase == SessionPhase.BLUEPRINT:
                    session.transition_to(SessionPhase.COMPLETED)
                await db.commit()
            except Exception as e:
                logger.error(f"[SESSION] Blueprint stream error: {e}")
                if scores_task is not None:
                    scores_task.cancel()
                # Remain in BLUEPRINT; the retry reuses the finished comparison.
                session.blueprint_output = None
                await db.commit()
                yield f"data: {json_lib.dumps({'type': 'error', 'section': 'blueprint', 'message': 'Blueprint generation failed. Please try again.', 'retryable': True})}\n\n"
                return

        # =====================================================================
        # Part 3: Dispatch the staged 12-week plan job.
        # =====================================================================
        try:
            await _dispatch_session_plan_job(db, plan_job)
        except Exception as e:
            logger.error(f"[SESSION] Failed to enqueue plan generation: {e}")
            if scores_task is not None:
                scores_task.cancel()
            yield f"data: {json_lib.dumps({'type': 'error', 'section': 'plan', 'message': 'Plan generation could not start. Please try again.', 'retryable': True})}\n\n"
            return

        # =====================================================================
        # Part 3.5: Structured comparison scores (best-effort)
        # =====================================================================
        # Started concurrently with the blueprint (see Part 1) — by now the
        # task is usually already finished, so this await is ~free. The prose
        # comparison is the mirror; these are the numbers behind the Compare
        # screen's gauges/radar. Best-effort: a failure leaves
        # comparison_scores_json null and the client shows a pending state.
        if session.comparison_scores_json is not None:
            yield f"data: {json_lib.dumps({'type': 'comparison_scores', 'ready': True})}\n\n"
        elif scores_task is not None:
            try:
                scores = await scores_task
                if scores:
                    session.comparison_scores_json = scores
                    await db.commit()
                    yield f"data: {json_lib.dumps({'type': 'comparison_scores', 'ready': True})}\n\n"
            except Exception as e:
                logger.error(f"[SESSION] comparison scores failed: {e}")

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
    await _get_session(session_id, current_user.id, db)

    # The grounded search is network-bound and does not need a database
    # connection.  Close the read transaction until resource attachment.
    await db.commit()

    # Braces in the user-typed topic would read as unresolved placeholders
    # under strict rendering — neutralise them before substitution.
    safe_topic = data.topic.replace("{", "(").replace("}", ")")
    prompt = load_and_render("learning_materials_generate.txt", {"topic": safe_topic})

    full_response = await generate_with_grounding(
        system_prompt=load_and_render("learning_materials_system.txt", {}),
        user_message=prompt,
        operation="learning_material_search",
    )

    try:
        parsed = json_lib.loads(_strip_json_fences(full_response))
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
        # Only attach resources that are already cached; uncached book modules
        # are generated in the background so this request stays fast. The
        # client tolerates materials without a content_resource_id.
        enriched_materials = await attach_content_resources_to_materials(
            db,
            raw_materials,
            user_goal=data.topic,
            defer_book_generation=True,
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
        # A newly flushed ORM relationship is not loaded. Accessing
        # ``thread.messages`` (even through ``hasattr``) attempts async I/O
        # from a synchronous attribute descriptor and raises MissingGreenlet.
        # The new thread has no history by definition, so keep that fact
        # explicit and never touch the relationship on the first turn.
        history_messages: list[ChatMessage] = []
    else:
        stmt = (
            select(ChatThread)
            .options(selectinload(ChatThread.messages))
            .where(ChatThread.id == session.learning_thread_id)
        )
        result = await db.execute(stmt)
        thread = result.scalar_one()
        history_messages = list(thread.messages)

    thread_id = str(thread.id)

    # A failed provider stream leaves the already-committed user turn as the
    # final message. Manual Retry sends the same text; reuse that pending turn
    # instead of duplicating the transcript and model context.
    has_pending_user_turn = bool(
        history_messages
        and history_messages[-1].role == MessageRole.USER
    )
    pending_retry = bool(
        has_pending_user_turn
        and history_messages[-1].content == data.content
    )

    # A final user-only turn means its provider stream never completed. Do not
    # present that abandoned request as answered conversation context, even
    # when the learner moves on with a different question.
    prompt_history = (
        history_messages[:-1]
        if has_pending_user_turn
        else history_messages
    )

    # Persist user message
    if not pending_retry:
        user_msg = ChatMessage(
            id=str(uuid.uuid4()),
            thread_id=thread_id,
            role=MessageRole.USER,
            content=data.content,
        )
        db.add(user_msg)
        await db.flush()

    # Recent complete turns carry the useful tutoring signal. Bounding this
    # prevents latency and token cost from growing forever with chat age.
    chat_history_json = _build_chat_history_json(
        prompt_history,
        max_chars=12_000,
    )

    idol_name = session.idol.name if session.idol else "Your Mentor"
    idol_persona_obj = getattr(session.idol, "persona", None)
    idol_persona = _persona_to_dict(idol_persona_obj)

    # Render the Socratic tutor system prompt with the full persona pack.
    # strict=False: the conversation history contains user-typed text whose
    # stray braces would otherwise read as unresolved placeholders.
    goal = getattr(session, "user_goal", None)
    blueprint = getattr(session, "blueprint_output", None)
    topic_context = "\n".join(
        part
        for part in [
            (
                "Learner goal: " + sanitize_untrusted_input(str(goal))
                if goal
                else ""
            ),
            (
                "Strategic blueprint excerpt: "
                + sanitize_untrusted_input(str(blueprint)[:2_000])
                if blueprint
                else ""
            ),
        ]
        if part
    )

    tutor_system_prompt = load_and_render("guided_learning_system.txt", {
        "idol_name": idol_name,
        "topic": topic_context or "No saved goal or blueprint is available.",
        "voice_style": idol_persona.get("voice_style") or "direct and authoritative",
        "principles": "; ".join(idol_persona.get("principles", [])) or "none documented",
        "dos": "; ".join(idol_persona.get("dos", [])) or "none documented",
        "donts": "; ".join(idol_persona.get("donts", [])) or "none documented",
        "signature_phrases": ", ".join(idol_persona.get("signature_phrases", [])) or "none documented",
        "lexicon_allow": ", ".join(idol_persona.get("lexicon_allow", [])) or "language consistent with your era",
        "lexicon_ban": ", ".join(idol_persona.get("lexicon_ban", [])) or "modern jargon inconsistent with your era",
        "worldview_adapter_json": json_lib.dumps(idol_persona.get("worldview_adapter", {})),
        "taboo_topics": ", ".join(idol_persona.get("taboo_topics", [])) or "none documented",
        "era_context": idol_persona.get("era_context") or "contemporary",
        "conversation_history_json": chat_history_json,
        "disclaimer": idol_persona.get("disclaimer") or "",
    }, strict=False)

    # Persist the user's turn and release the pooled connection before the
    # tutor stream begins. The assistant turn opens a fresh short transaction.
    await db.commit()

    async def generate_stream():
        full_response = ""
        started = time.perf_counter()
        first_chunk_at: float | None = None
        try:
            # Establish SSE immediately. The provider has a bounded 60-second
            # deadline, while clients keep a larger margin to receive the
            # terminal error if that deadline is reached.
            yield f"data: {json_lib.dumps({'type': 'status', 'message': 'thinking'})}\n\n"

            async for chunk in stream_learnlm(
                system_prompt=tutor_system_prompt,
                user_message=data.content,
            ):
                if first_chunk_at is None:
                    first_chunk_at = time.perf_counter()
                full_response += chunk
                yield f"data: {json_lib.dumps({'type': 'chunk', 'content': chunk})}\n\n"

            if not full_response.strip():
                raise RuntimeError("Tutor returned an empty response")

            ai_msg = ChatMessage(
                id=str(uuid.uuid4()),
                thread_id=thread_id,
                role=MessageRole.ASSISTANT,
                content=full_response,
            )
            db.add(ai_msg)
            await db.commit()

            elapsed_ms = (time.perf_counter() - started) * 1000
            first_chunk_ms = (
                (first_chunk_at - started) * 1000
                if first_chunk_at is not None
                else None
            )
            logger.info(
                "[SESSION] Guided learning completed in %.0fms "
                "(first chunk %.0fms, %s chars)",
                elapsed_ms,
                first_chunk_ms or 0,
                len(full_response),
            )

            yield f"data: {json_lib.dumps({'type': 'done'})}\n\n"
        except Exception as e:
            logger.exception("[SESSION] Guided learning stream error: %s", e)
            yield f"data: {json_lib.dumps({'type': 'error', 'message': 'The mentor reply could not be completed. Please retry.'})}\n\n"

    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )

# =============================================================================
# T023: GET /sessions/{id}/feed - Generate Daily Insights (Idea Cards)
# =============================================================================

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

    # Daily by design: serve today's cached insights instead of re-running a
    # 5-15s grounded generation on every open of the screen.
    today_iso = date.today().isoformat()
    cached_feed = session.daily_feed_json or {}
    if cached_feed.get("date") == today_iso and cached_feed.get("insights"):
        return DailyFeedResponse(insights=[
            DailyInsightResponse(**item) for item in cached_feed["insights"]
        ])

    idol_name = session.idol.name if session.idol else "Your Mentor"
    idol_persona_obj = getattr(session.idol, "persona", None)
    idol_persona = _persona_to_dict(idol_persona_obj)

    user_profile = {
        "age": session.user_age,
        "financial_status": session.user_financial_status,
        "interests": session.user_interests,
    }

    # Documented evidence the prompt's anti-fabrication rules draw from:
    # signature phrases, principles, and sourced grounding evidence.
    raw_evidence = getattr(idol_persona_obj, "grounding_evidence", None)
    idol_evidence = {
        "signature_phrases": idol_persona.get("signature_phrases", []),
        "principles": idol_persona.get("principles", []),
        "grounding_evidence": raw_evidence[:10] if isinstance(raw_evidence, list) else [],
    }

    prompt = load_and_render("daily_feed_generate.txt", {
        "count": "3",
        "idol_name": idol_name,
        "user_profile_json": json_lib.dumps(user_profile),
        "idol_evidence_json": json_lib.dumps(idol_evidence),
    })

    # The model/search call can be slow; the session snapshot above is enough
    # to run it without monopolizing a database connection.
    await db.commit()

    full_response = await generate_with_grounding(
        system_prompt=_render_persona_system(idol_name, idol_persona),
        user_message=prompt,
        operation="daily_feed_generation",
    )

    try:
        parsed = json_lib.loads(_strip_json_fences(full_response))
        # The prompt asks for {"insights": [...]}; tolerate a bare array too.
        if isinstance(parsed, dict):
            parsed = parsed.get("insights", [])
        if not isinstance(parsed, list):
            parsed = []
        insights = [
            DailyInsightResponse(
                title=item.get("title", "Insight"),
                content=item.get("content", ""),
                category=item.get("category", "Mindset"),
            )
            for item in parsed[:3]
            if isinstance(item, dict)
        ]
        if insights:
            session.daily_feed_json = {
                "date": today_iso,
                "insights": [i.model_dump(mode="json") for i in insights],
            }
            await db.commit()
        return DailyFeedResponse(insights=insights)
    except Exception as e:
        logger.error(f"[SESSION] Failed to parse daily feed: {e}. Raw: {full_response}")
        raise HTTPException(status_code=502, detail="Failed to fetch daily feed")
