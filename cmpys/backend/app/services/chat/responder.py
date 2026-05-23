"""
Chat responder service.

PROMPT MAPPING:
- generate_reply() -> chat_system.txt + chat_reply.txt

This service REQUIRES LLM to function. If LLM is not configured,
raises LLMNotConfiguredError.

REQUIRED PLACEHOLDERS FOR chat_system.txt:
- {idol_name}: Name of the idol
- {voice_style}: Voice/tone description
- {principles}: List of principles
- {dos}: Things the persona should do
- {donts}: Things the persona should avoid
- {signature_phrases}: Characteristic phrases
- {topics_of_strength}: Topics they excel at
- {grounding_facts_json}: JSON of verified facts (milestones/themes)
- {user_context_json}: JSON of user context (age/interests/progress)
- {disclaimer}: Safety disclaimer text

REQUIRED PLACEHOLDERS FOR chat_reply.txt:
- {user_profile_json}: JSON of user profile
- {idol_profile_json}: JSON of idol profile
- {idol_persona_json}: JSON of idol persona pack
- {target_age}: User's target age
- {comparison_json}: JSON of comparison summary (optional)
- {milestones_json}: JSON of idol milestones at target age
- {evidence_snippets_json}: JSON of evidence snippets (optional)
- {conversation_history_json}: JSON of conversation history
- {user_message}: The user's current message
"""
import json
import logging
import re
from dataclasses import dataclass

from pydantic import BaseModel, Field

from app.core.config import settings
from app.models.chat import ChatMessage
from app.models.idol_persona import IdolPersona
from app.models.idol_profile import IdolProfile
from app.models.idol_timeline import IdolTimelineEvent
from app.services.llm import get_llm_client
from app.services.llm.prompt_loader import load_prompt, render_prompt

logger = logging.getLogger(__name__)

# =============================================================================
# Jargon Guard Constants
# =============================================================================

BANNED_MODERN_JARGON = [
    "value proposition",
    "competitors",
    "mentors/advisors",
    "mentor",
    "mentee",
    "market research",
    "networking",
    "pivot",
    "scale up",
    "growth hacking",
    "KPIs",
    "OKRs",
    "stakeholders",
    "leverage",  # as verb
    "synergy",
    "disrupt",
    "iterate",
    "MVP",
    "product-market fit",
]

# Default worldview mappings by domain type
DOMAIN_WORLDVIEW_DEFAULTS = {
    "military": {
        "startup": "campaign",
        "customers": "those you serve",
        "market": "terrain",
        "competitors": "rival forces",
        "product": "your weapon/offering",
        "funding": "provisions",
        "networking": "building alliances",
        "mentor": "elder advisor",
        "pitch": "proposal to the council",
        "scale": "expand your dominion",
    },
    "philosophy": {
        "startup": "undertaking",
        "customers": "those who benefit",
        "market": "the public sphere",
        "competitors": "rival schools",
        "product": "your teaching",
        "funding": "patronage",
        "networking": "discourse with peers",
        "mentor": "master",
        "pitch": "argument",
        "scale": "spread your influence",
    },
    "science": {
        "startup": "inquiry",
        "customers": "those who apply the knowledge",
        "market": "the learned community",
        "competitors": "rival theories",
        "product": "your discovery",
        "funding": "patronage/grants",
        "networking": "correspondence with peers",
        "mentor": "teacher",
        "pitch": "presentation of findings",
        "scale": "disseminate widely",
    },
    "art": {
        "startup": "new work",
        "customers": "patrons and admirers",
        "market": "the art world",
        "competitors": "rival artists",
        "product": "your creation",
        "funding": "commission/patronage",
        "networking": "cultivating patrons",
        "mentor": "master",
        "pitch": "proposal",
        "scale": "gain renown",
    },
    "politics": {
        "startup": "campaign/initiative",
        "customers": "the people/constituents",
        "market": "the political landscape",
        "competitors": "opponents",
        "product": "your policy/vision",
        "funding": "treasury/supporters",
        "networking": "building coalitions",
        "mentor": "advisor",
        "pitch": "address",
        "scale": "extend your influence",
    },
    "default": {
        "startup": "venture",
        "customers": "those you serve",
        "market": "the field",
        "competitors": "rivals",
        "product": "your offering",
        "funding": "resources",
        "networking": "building relationships",
        "mentor": "guide",
        "pitch": "proposal",
        "scale": "grow",
    },
}

# Default frameworks by domain
DOMAIN_FRAMEWORKS_DEFAULTS = {
    "military": [
        "terrain analysis",
        "force concentration", 
        "supply line security",
        "deception and misdirection",
        "alliance building",
        "disciplined pacing",
    ],
    "philosophy": [
        "dialectical inquiry",
        "first principles reasoning",
        "virtue ethics framework",
        "examination of assumptions",
        "systematic argumentation",
    ],
    "science": [
        "hypothesis-experiment cycle",
        "systematic observation",
        "controlled comparison",
        "peer verification",
        "incremental discovery",
    ],
    "art": [
        "study of masters",
        "deliberate practice",
        "creative constraints",
        "patron relationships",
        "iterative refinement",
    ],
    "politics": [
        "coalition building",
        "public persuasion",
        "strategic timing",
        "resource allocation",
        "compromise and negotiation",
    ],
    "default": [
        "careful observation",
        "methodical planning",
        "incremental progress",
        "learning from failure",
    ],
}


class LLMNotConfiguredError(Exception):
    """Raised when LLM is required but not configured."""
    pass


class ChatReplyResponse(BaseModel):
    """LLM response schema for chat reply."""
    reply: str
    confidence: float = Field(default=0.7, ge=0.0, le=1.0)
    disclaimer_included: bool = True
    follow_up_questions: list[str] = Field(default_factory=list)
    suggested_actions: list[str] = Field(default_factory=list)


@dataclass
class ChatReplyResult:
    """Result from generate_reply."""
    content: str
    disclaimer: str
    confidence: float = 0.7
    follow_up_questions: list[str] | None = None
    suggested_actions: list[str] | None = None


def _milestones_to_json(milestones: list[IdolTimelineEvent]) -> str:
    """Convert milestones to JSON for prompt injection."""
    if not milestones:
        return "[]"
    
    items = []
    for m in milestones[:15]:  # Limit to 15
        items.append({
            "title": m.canonical_title,
            "description": m.canonical_description,
            "age_at_event": m.age_at_event,
            "category": m.category,
            "importance_score": m.importance_score,
        })
    
    return json.dumps(items, indent=2)


def _conversation_to_json(messages: list[ChatMessage], limit: int = 10) -> str:
    """Convert conversation history to JSON for prompt injection."""
    if not messages:
        return "[]"
    
    items = []
    for msg in messages[-limit:]:
        items.append({
            "role": msg.role.value if hasattr(msg.role, 'value') else str(msg.role),
            "content": msg.content,
        })
    
    return json.dumps(items, indent=2)


def _profile_to_json(profile: IdolProfile | None) -> str:
    """Convert idol profile to JSON for prompt injection."""
    if not profile:
        return "{}"
    
    data = {
        "display_name": profile.display_name,
        "short_description": profile.short_description,
        "nationality": profile.nationality,
        "domains": profile.domains,
        "primary_roles": profile.primary_roles,
        "notable_themes": profile.notable_themes,
        "birth_date": profile.birth_date.isoformat() if profile.birth_date else None,
    }
    return json.dumps(data, indent=2)


def _infer_domain_type(domains: list[str] | None) -> str:
    """Infer the primary domain type for fallback worldview/framework selection."""
    if not domains:
        return "default"
    
    domains_lower = [d.lower() for d in domains]
    
    # Check for domain keywords
    if any(k in " ".join(domains_lower) for k in ["military", "war", "strategy", "commander", "general", "army"]):
        return "military"
    if any(k in " ".join(domains_lower) for k in ["philosophy", "ethics", "logic", "metaphysics"]):
        return "philosophy"
    if any(k in " ".join(domains_lower) for k in ["science", "physics", "chemistry", "biology", "mathematics", "astronomy"]):
        return "science"
    if any(k in " ".join(domains_lower) for k in ["art", "painting", "sculpture", "music", "literature", "poetry"]):
        return "art"
    if any(k in " ".join(domains_lower) for k in ["politics", "government", "diplomacy", "statecraft", "law"]):
        return "politics"
    
    return "default"


def _persona_to_json(persona: IdolPersona | None, profile: IdolProfile | None = None) -> str:
    """
    Convert idol persona to JSON for prompt injection.
    
    Includes era_context, lexicon rules, worldview_adapter, and default_frameworks
    with fallback generation based on profile domains if not present.
    """
    if not persona:
        return "{}"
    
    # Get domains for fallback inference
    domains = profile.domains if profile else []
    domain_type = _infer_domain_type(domains)
    
    # Era context (fallback to contemporary)
    era_context = getattr(persona, 'era_context', None) or 'contemporary'
    
    # Lexicon allow (fallback empty)
    lexicon_allow = getattr(persona, 'lexicon_allow', None) or []
    
    # Lexicon ban (fallback based on era)
    lexicon_ban = getattr(persona, 'lexicon_ban', None)
    if not lexicon_ban:
        # For historical figures, apply default ban list
        if era_context in ('ancient', 'medieval', 'early_modern'):
            lexicon_ban = BANNED_MODERN_JARGON.copy()
        elif era_context == 'modern':
            # Lighter ban for 1800-1980 figures
            lexicon_ban = ["growth hacking", "KPIs", "OKRs", "pivot", "MVP", "product-market fit"]
        else:
            lexicon_ban = []
    
    # Worldview adapter (fallback based on domain)
    worldview_adapter = getattr(persona, 'worldview_adapter', None)
    if not worldview_adapter or worldview_adapter == {}:
        worldview_adapter = DOMAIN_WORLDVIEW_DEFAULTS.get(domain_type, DOMAIN_WORLDVIEW_DEFAULTS["default"])
    
    # Default frameworks (fallback based on domain)
    default_frameworks = getattr(persona, 'default_frameworks', None)
    if not default_frameworks:
        default_frameworks = DOMAIN_FRAMEWORKS_DEFAULTS.get(domain_type, DOMAIN_FRAMEWORKS_DEFAULTS["default"])
    
    data = {
        "voice_style": persona.voice_style,
        "principles": persona.principles,
        "dos": persona.dos,
        "donts": persona.donts,
        "signature_phrases": persona.signature_phrases,
        "topics_of_strength": persona.topics_of_strength,
        "taboo_topics": persona.taboo_topics,
        # Era-aware fields
        "era_context": era_context,
        "lexicon_allow": lexicon_allow,
        "lexicon_ban": lexicon_ban,
        "worldview_adapter": worldview_adapter,
        "default_frameworks": default_frameworks,
    }
    return json.dumps(data, indent=2)


def _user_context_to_json(user_age: int | None) -> str:
    """Build user context JSON."""
    return json.dumps({
        "age": user_age,
        "weekly_hours": None,  # Could be passed in future
        "current_plan": None,  # Could be passed in future
    }, indent=2)


def _grounding_facts_to_json(
    profile: IdolProfile | None,
    milestones: list[IdolTimelineEvent],
) -> str:
    """Build grounding facts JSON from profile and milestones."""
    facts = {
        "themes": profile.notable_themes if profile else [],
        "domains": profile.domains if profile else [],
        "milestones": [
            {
                "title": m.canonical_title,
                "age": m.age_at_event,
                "category": m.category,
            }
            for m in milestones[:10]
        ],
    }
    return json.dumps(facts, indent=2)


# =============================================================================
# Jargon Guard
# =============================================================================


def _contains_banned_jargon(text: str, banned_terms: list[str]) -> list[str]:
    """
    Check if text contains any banned modern jargon terms.
    Returns list of found banned terms.
    """
    text_lower = text.lower()
    found = []
    for term in banned_terms:
        # Use word boundary matching for single words, simple contains for phrases
        if " " in term:
            if term.lower() in text_lower:
                found.append(term)
        else:
            # Word boundary check for single words
            pattern = r'\b' + re.escape(term.lower()) + r'\b'
            if re.search(pattern, text_lower):
                found.append(term)
    return found


class JargonRewriteResponse(BaseModel):
    """Response schema for jargon rewrite."""
    rewritten_reply: str


async def _apply_jargon_guard(
    reply: str,
    era_context: str,
    worldview_adapter: dict,
    idol_name: str,
    domain_type: str,
) -> str:
    """
    Apply jargon guard for historical idols.
    
    If era_context is not modern/contemporary and reply contains banned jargon,
    call LLM once to rewrite using idol-era metaphors.
    
    Preserves the disclaimer sentence unchanged.
    """
    # Skip for modern/contemporary figures
    if era_context in ('modern', 'contemporary'):
        return reply
    
    # Check for banned jargon
    banned_terms = BANNED_MODERN_JARGON
    found_jargon = _contains_banned_jargon(reply, banned_terms)
    
    if not found_jargon:
        logger.debug("[JARGON_GUARD] No banned jargon found, skipping rewrite")
        return reply
    
    logger.info(f"[JARGON_GUARD] Found banned jargon: {found_jargon}. Rewriting...")
    
    # Separate disclaimer from main reply
    disclaimer_sentence = "Note: AI simulation based on public sources; may be inaccurate."
    main_reply = reply
    if disclaimer_sentence in reply:
        main_reply = reply.replace(disclaimer_sentence, "").strip()
    
    # Build rewrite prompt
    client = get_llm_client()
    
    system_prompt = f"""You are a rewriter. Your job is to take a chat reply that contains modern corporate jargon 
and rewrite it using era-appropriate language for {idol_name}, a {era_context} figure.

CRITICAL RULES:
1. Keep the same meaning and actions - just change the vocabulary
2. Use these mappings for modern concepts:
{json.dumps(worldview_adapter, indent=2)}

3. Banned terms to replace: {found_jargon}
4. Keep the tone and structure similar
5. Do NOT add or remove information
6. Output ONLY the rewritten text, nothing else"""

    user_prompt = f"""Rewrite this reply, replacing modern jargon with era-appropriate terms:

{main_reply}

Return JSON with key "rewritten_reply" containing the rewritten text."""

    try:
        validated, response = await client.generate_and_validate(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            output_model=JargonRewriteResponse,
            repair_on_failure=False,
            max_tokens=1000,
        )
        
        if validated:
            rewritten = validated.rewritten_reply.strip()
            # Re-append disclaimer
            if disclaimer_sentence not in rewritten:
                rewritten = f"{rewritten}\n\n{disclaimer_sentence}"
            logger.info("[JARGON_GUARD] Successfully rewrote reply")
            return rewritten
        else:
            logger.warning("[JARGON_GUARD] Rewrite failed, returning original")
            return reply
            
    except Exception as e:
        logger.warning(f"[JARGON_GUARD] Rewrite error: {e}, returning original")
        return reply


# =============================================================================
# Main Entry Point
# PROMPTS: chat_system.txt, chat_reply.txt
# =============================================================================


async def generate_reply(
    user_message: str,
    idol_name: str,
    profile: IdolProfile | None,
    persona: IdolPersona | None,
    milestones: list[IdolTimelineEvent],
    conversation_history: list[ChatMessage],
    user_age: int | None = None,
    user_profile: dict | None = None,
    comparison_summary: dict | None = None,
) -> ChatReplyResult:
    """
    Generate an LLM response as the idol persona.
    
    PROMPTS USED:
    - System: chat_system.txt
    - User: chat_reply.txt
    
    REQUIRES LLM - raises LLMNotConfiguredError if not configured.
    
    Args:
        user_message: The user's message
        idol_name: Name of the idol
        profile: Idol profile (optional)
        persona: Idol persona (optional, but recommended)
        milestones: Relevant milestones for context
        conversation_history: Previous messages in the thread
        user_age: User's age for milestone filtering
        user_profile: Optional user profile dict
        comparison_summary: Optional comparison results
        
    Returns:
        ChatReplyResult with content and disclaimer
        
    Raises:
        LLMNotConfiguredError: If LLM is not configured
    """
    logger.info(f"[CHAT] Generating reply for idol={idol_name}, user_age={user_age}")
    logger.debug(f"[CHAT] User message: {user_message[:100]}...")
    logger.debug(f"[CHAT] History length: {len(conversation_history)}, Milestones: {len(milestones)}")
    
    # Check LLM is configured
    if not settings.llm_configured:
        logger.error("[CHAT] LLM not configured, cannot generate reply")
        raise LLMNotConfiguredError(
            "LLM is not configured. Set OPENAI_API_KEY and LLM_PROVIDER=openai"
        )
    
    client = get_llm_client()
    logger.debug(f"[CHAT] Using LLM client: {type(client).__name__}")
    
    # Load prompt templates
    system_template = load_prompt("chat_system")
    user_template = load_prompt("chat_reply")
    
    # Prepare default disclaimer
    default_disclaimer = "This is an AI simulation based on public information. Not the real person."
    
    # Build idol_persona_json early since we use it in both prompts
    idol_persona_json = _persona_to_json(persona, profile)
    
    # Build system prompt with ALL required placeholders
    # See: prompts/chat_system.txt for placeholder definitions
    system_prompt = render_prompt(system_template, {
        "idol_name": idol_name,
        "voice_style": persona.voice_style if persona else "Thoughtful and informative",
        "principles": "\n".join(persona.principles) if persona and persona.principles else "Be helpful and honest.",
        "dos": "\n".join(persona.dos) if persona and persona.dos else "Share insights and experiences.",
        "donts": "\n".join(persona.donts) if persona and persona.donts else "Claim to be the real person.",
        "signature_phrases": "\n".join(persona.signature_phrases) if persona and persona.signature_phrases else "None",
        "topics_of_strength": "\n".join(persona.topics_of_strength) if persona and persona.topics_of_strength else "General wisdom",
        "grounding_facts_json": _grounding_facts_to_json(profile, milestones),
        "idol_persona_json": idol_persona_json,
        "user_context_json": _user_context_to_json(user_age),
        "disclaimer": persona.disclaimer if persona and persona.disclaimer else default_disclaimer,
    }, prompt_name="chat_system.txt")
    
    disclaimer = persona.disclaimer if persona and persona.disclaimer else default_disclaimer
    
    # Build user prompt with ALL required placeholders
    # See: prompts/chat_reply.txt for placeholder definitions
    user_prompt = render_prompt(user_template, {
        "user_profile_json": json.dumps(user_profile or {"age": user_age}, indent=2),
        "idol_profile_json": _profile_to_json(profile),
        "idol_persona_json": idol_persona_json,
        "idol_name": idol_name,
        "target_age": str(user_age) if user_age else "25",
        "comparison_json": json.dumps(comparison_summary, indent=2) if comparison_summary else "null",
        "milestones_json": _milestones_to_json(milestones),
        "evidence_snippets_json": "[]",  # Could be populated in future
        "conversation_history_json": _conversation_to_json(conversation_history),
        "user_message": user_message,
    }, prompt_name="chat_reply.txt")
    
    # Generate reply
    logger.info("[CHAT] Calling LLM for chat response...")
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=ChatReplyResponse,
        repair_on_failure=True,
    )
    
    if validated:
        logger.info(f"[CHAT] LLM response received, confidence={validated.confidence}")
        logger.debug(f"[CHAT] Reply preview: {validated.reply[:100]}...")
        
        reply_content = validated.reply
        
        # Apply jargon guard for historical idols
        era_context = getattr(persona, 'era_context', None) or 'contemporary'
        if era_context not in ('modern', 'contemporary'):
            # Get worldview adapter and domain type for rewriting
            domains = profile.domains if profile else []
            domain_type = _infer_domain_type(domains)
            worldview_adapter = getattr(persona, 'worldview_adapter', None)
            if not worldview_adapter or worldview_adapter == {}:
                worldview_adapter = DOMAIN_WORLDVIEW_DEFAULTS.get(domain_type, DOMAIN_WORLDVIEW_DEFAULTS["default"])
            
            reply_content = await _apply_jargon_guard(
                reply=reply_content,
                era_context=era_context,
                worldview_adapter=worldview_adapter,
                idol_name=idol_name,
                domain_type=domain_type,
            )
        
        return ChatReplyResult(
            content=reply_content,
            disclaimer=disclaimer,
            confidence=validated.confidence,
            follow_up_questions=validated.follow_up_questions,
            suggested_actions=validated.suggested_actions,
        )
    
    # Fallback if validation fails
    if response.raw_response:
        logger.warning(f"[CHAT] Validation failed, using raw response. Error: {response.error}")
        return ChatReplyResult(
            content=response.raw_response,
            disclaimer=disclaimer,
        )
    
    # Error fallback
    logger.error(f"[CHAT] LLM call failed completely. Error: {response.error}")
    return ChatReplyResult(
        content="I apologize, but I'm having trouble generating a response right now. Please try again.",
        disclaimer=disclaimer,
    )
