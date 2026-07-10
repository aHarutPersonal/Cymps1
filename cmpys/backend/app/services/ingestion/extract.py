"""
LLM-based extraction pipeline for idol ingestion.

This module implements multi-step extraction using LLM prompts
to extract structured data from source content.

PROMPT MAPPING:
- run_profile_extraction()      -> extractor_system.txt + profile_extract.txt
- run_achievements_extraction() -> extractor_system.txt + achievements_extract.txt
- run_timeline_normalization()  -> extractor_system.txt + timeline_normalize.txt
- run_milestones_by_age()       -> extractor_system.txt + milestones_by_age.txt
- run_persona_pack()            -> extractor_system.txt + persona_pack.txt
"""
import json
import logging

from app.models.source_chunk import SourceChunk
from app.services.llm import BaseLLMClient, get_llm_client
from app.services.llm.prompt_loader import load_prompt, render_prompt
from app.services.llm.telemetry import record_llm_response
from app.services.llm.schemas import (
    AchievementsExtractionResponse,
    MilestoneMode,
    MilestonesByAgeResponse,
    PersonaPackResponse,
    ProfileExtractionResponse,
    TimelineNormalizationResponse,
)

logger = logging.getLogger(__name__)


def _average_confidence(items: list) -> float:
    values = [float(item.confidence) for item in items if hasattr(item, "confidence")]
    return sum(values) / len(values) if values else 0.0


def _chunks_to_json(chunks: list[SourceChunk], source_url: str, source_id: str) -> str:
    """Convert source chunks to JSON for prompt injection."""
    chunk_list = []
    for chunk in chunks:
        chunk_list.append({
            "source_id": source_id,
            "chunk_index": chunk.chunk_index,
            "source_url": source_url,
            "text": chunk.text,
        })
    return json.dumps(chunk_list, indent=2)


# =============================================================================
# Profile Extraction
# PROMPTS: extractor_system.txt, profile_extract.txt
# =============================================================================


async def run_profile_extraction(
    chunks: list[SourceChunk],
    source_url: str,
    source_id: str,
    idol_name: str,
    wikidata_qid: str | None = None,
    wikipedia_url: str | None = None,
    provider: str = "wikipedia",
    external_id: str | None = None,
    client: BaseLLMClient | None = None,
) -> ProfileExtractionResponse | None:
    """
    Extract canonical profile from source chunks.
    
    PROMPTS USED:
    - System: extractor_system.txt
    - User: profile_extract.txt
    
    REQUIRED PLACEHOLDERS:
    - {selected_name}: Idol name
    - {provider}: Source provider (e.g., "wikidata", "wikipedia")
    - {external_id}: External ID (e.g., Wikidata QID)
    - {wikipedia_url}: Wikipedia URL hint
    - {sources_json_array}: JSON array of source chunks
    
    Args:
        chunks: List of source chunks
        source_url: URL of the source
        source_id: ID of the source record
        idol_name: Name of the idol
        wikidata_qid: Optional Wikidata QID
        wikipedia_url: Optional Wikipedia URL
        provider: Source provider name (default: "wikipedia")
        external_id: External identifier
        client: Optional LLM client (uses default if not provided)
        
    Returns:
        ProfileExtractionResponse or None if extraction fails
    """
    client = client or get_llm_client(max_tokens=2000, tier="fast")
    
    # Load prompt templates using prompt_loader
    system_prompt = load_prompt("extractor_system")
    user_template = load_prompt("profile_extract")
    
    sources_json = _chunks_to_json(chunks, source_url, source_id)
    
    # Render user prompt with ALL required placeholders
    # See: prompts/profile_extract.txt for placeholder definitions
    user_prompt = render_prompt(user_template, {
        "selected_name": idol_name,
        "provider": provider,
        "external_id": external_id or wikidata_qid or "N/A",
        "wikipedia_url": wikipedia_url or source_url or "null",
        "sources_json_array": sources_json,
    }, prompt_name="profile_extract.txt")
    
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=ProfileExtractionResponse,
        repair_on_failure=True,
    )
    await record_llm_response(
        operation="idol_profile_extraction",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated else "failed",
        quality_score=validated.profile.confidence if validated else 0.0,
        metadata={"source_provider": provider, "source_chunk_count": len(chunks)},
    )
    
    if response.error:
        logger.error(f"Profile extraction failed: {response.error}")
        return None
    
    return validated


# =============================================================================
# Achievements Extraction
# PROMPTS: extractor_system.txt, achievements_extract.txt
# =============================================================================


async def run_achievements_extraction(
    chunks: list[SourceChunk],
    source_url: str,
    source_id: str,
    idol_name: str,
    client: BaseLLMClient | None = None,
) -> AchievementsExtractionResponse | None:
    """
    Extract achievement candidates from source chunks.
    
    PROMPTS USED:
    - System: extractor_system.txt
    - User: achievements_extract.txt
    
    REQUIRED PLACEHOLDERS:
    - {idol_name}: Name of the idol
    - {sources_json_array}: JSON array of source chunks
    
    Args:
        chunks: List of source chunks
        source_url: URL of the source
        source_id: ID of the source record
        idol_name: Name of the idol
        client: Optional LLM client
        
    Returns:
        AchievementsExtractionResponse or None if extraction fails
    """
    client = client or get_llm_client(max_tokens=4000, tier="fast")
    
    # Load prompt templates
    system_prompt = load_prompt("extractor_system")
    user_template = load_prompt("achievements_extract")
    
    sources_json = _chunks_to_json(chunks, source_url, source_id)
    
    # Render user prompt with ALL required placeholders
    # See: prompts/achievements_extract.txt for placeholder definitions
    user_prompt = render_prompt(user_template, {
        "idol_name": idol_name,
        "sources_json_array": sources_json,
    }, prompt_name="achievements_extract.txt")
    
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=AchievementsExtractionResponse,
        repair_on_failure=True,
    )
    await record_llm_response(
        operation="idol_achievements_extraction",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated else "failed",
        quality_score=_average_confidence(validated.candidates) if validated else 0.0,
        metadata={
            "source_chunk_count": len(chunks),
            "candidate_count": len(validated.candidates) if validated else 0,
        },
    )
    
    if response.error:
        logger.error(f"Achievements extraction failed: {response.error}")
        return None
    
    return validated


# =============================================================================
# Timeline Normalization
# PROMPTS: extractor_system.txt, timeline_normalize.txt
# =============================================================================


async def run_timeline_normalization(
    profile: ProfileExtractionResponse,
    candidates: AchievementsExtractionResponse,
    client: BaseLLMClient | None = None,
) -> TimelineNormalizationResponse | None:
    """
    Normalize and deduplicate achievement candidates.
    
    PROMPTS USED:
    - System: extractor_system.txt
    - User: timeline_normalize.txt
    
    REQUIRED PLACEHOLDERS:
    - {idol_birth_date}: Birth date in YYYY-MM-DD format or "null"
    - {candidates_json}: JSON array of achievement candidates
    
    Args:
        profile: Extracted profile with birth date
        candidates: Achievement candidates to normalize
        client: Optional LLM client
        
    Returns:
        TimelineNormalizationResponse or None if normalization fails
    """
    client = client or get_llm_client(max_tokens=4000, tier="fast")
    
    # Load prompt templates
    system_prompt = load_prompt("extractor_system")
    user_template = load_prompt("timeline_normalize")
    
    birth_date = profile.profile.birth_date
    birth_date_str = birth_date.isoformat() if birth_date else "null"
    
    candidates_json = json.dumps(
        [c.model_dump(mode="json") for c in candidates.candidates],
        indent=2,
    )
    
    # Render user prompt with ALL required placeholders
    # See: prompts/timeline_normalize.txt for placeholder definitions
    user_prompt = render_prompt(user_template, {
        "idol_birth_date": birth_date_str,
        "candidates_json": candidates_json,
    }, prompt_name="timeline_normalize.txt")
    
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=TimelineNormalizationResponse,
        repair_on_failure=True,
    )
    await record_llm_response(
        operation="idol_timeline_normalization",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated else "failed",
        quality_score=_average_confidence(validated.timeline) if validated else 0.0,
        metadata={"event_count": len(validated.timeline) if validated else 0},
    )
    
    if response.error:
        logger.error(f"Timeline normalization failed: {response.error}")
        return None
    
    return validated


# =============================================================================
# Milestones by Age
# PROMPTS: extractor_system.txt, milestones_by_age.txt
# =============================================================================


async def run_milestones_by_age(
    timeline: TimelineNormalizationResponse,
    target_age: int,
    mode: MilestoneMode = MilestoneMode.UP_TO,
    client: BaseLLMClient | None = None,
) -> MilestonesByAgeResponse | None:
    """
    Get milestones for a specific age from the timeline.
    
    PROMPTS USED:
    - System: extractor_system.txt
    - User: milestones_by_age.txt
    
    REQUIRED PLACEHOLDERS:
    - {target_age}: Target age as integer
    - {mode}: "exact" or "up_to"
    - {timeline_json}: JSON array of timeline events
    
    Args:
        timeline: Normalized timeline
        target_age: Target age to query
        mode: "exact" for only that age, "up_to" for age and below
        client: Optional LLM client
        
    Returns:
        MilestonesByAgeResponse or None if query fails
    """
    client = client or get_llm_client(max_tokens=4000, tier="fast")
    
    # Load prompt templates
    system_prompt = load_prompt("extractor_system")
    user_template = load_prompt("milestones_by_age")
    
    timeline_json = json.dumps(
        [e.model_dump(mode="json") for e in timeline.timeline],
        indent=2,
    )
    
    # Render user prompt with ALL required placeholders
    # See: prompts/milestones_by_age.txt for placeholder definitions
    user_prompt = render_prompt(user_template, {
        "target_age": str(target_age),
        "mode": mode.value,
        "timeline_json": timeline_json,
    }, prompt_name="milestones_by_age.txt")
    
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=MilestonesByAgeResponse,
        repair_on_failure=True,
    )
    await record_llm_response(
        operation="idol_milestones_by_age",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated else "failed",
        quality_score=validated.completeness_estimate if validated else 0.0,
        metadata={
            "target_age": target_age,
            "milestone_count": len(validated.milestones) if validated else 0,
        },
    )
    
    if response.error:
        logger.error(f"Milestones by age query failed: {response.error}")
        return None
    
    return validated


# =============================================================================
# Persona Pack
# PROMPTS: extractor_system.txt, persona_pack.txt
# =============================================================================


async def run_persona_pack(
    profile: ProfileExtractionResponse,
    chunks: list[SourceChunk],
    source_url: str,
    source_id: str,
    client: BaseLLMClient | None = None,
) -> PersonaPackResponse | None:
    """
    Generate a chat persona pack for the idol.
    
    PROMPTS USED:
    - System: extractor_system.txt
    - User: persona_pack.txt
    
    Args:
        profile: Extracted profile
        chunks: Source chunks for grounding
        source_url: URL of the source
        source_id: ID of the source record
        client: Optional LLM client
        
    Returns:
        PersonaPackResponse or None if generation fails
    """
    client = client or get_llm_client(max_tokens=2000, tier="fast")
    
    # Load prompt templates
    system_prompt = load_prompt("extractor_system")
    user_template = load_prompt("persona_pack")
    
    sources_json = _chunks_to_json(chunks, source_url, source_id)
    profile_json = json.dumps(profile.profile.model_dump(mode="json"), indent=2)
    
    # Build user prompt
    user_prompt = f"""IDOL PROFILE:
{profile_json}

SOURCES (chunked):
{sources_json}

{user_template}"""
    
    validated, response = await client.generate_and_validate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        output_model=PersonaPackResponse,
        repair_on_failure=True,
    )
    evidence_count = (
        len(validated.persona.grounding_evidence) if validated else 0
    )
    await record_llm_response(
        operation="idol_persona_generation",
        response=response,
        model=getattr(client, "model", None),
        result_status="schema_valid" if validated else "failed",
        quality_score=min(1.0, evidence_count / 5),
        metadata={
            "source_chunk_count": len(chunks),
            "grounding_evidence_count": evidence_count,
        },
    )
    
    if response.error:
        logger.error(f"Persona pack generation failed: {response.error}")
        return None
    
    return validated
