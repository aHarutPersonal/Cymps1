"""
Prompt template loader and renderer.

Provides utilities for loading prompt templates from the /prompts directory
and rendering them with variable substitution and validation.

PROMPT WIRING DOCUMENTATION:
============================

System prompts (no placeholders unless noted):

- extractor_system.txt — strict evidence-grounded extraction. System prompt for
  the ingestion pipeline ONLY (profile/achievements/timeline/milestones/persona).
- planner_system.txt — plan/lesson/book-module generation. System prompt for the
  planning trio (plan_generate, plan_item_details, book_module_generate); unlike
  extractor_system it permits world knowledge of real books/courses.
- persona_system.txt — full idol persona pack; system prompt wherever the model
  speaks AS the idol (comparison, blueprint, daily feed).
- guided_learning_system.txt — idol persona as Socratic tutor (guided learning).
- learning_materials_system.txt — curriculum curator JSON contract.
- idol_suggest_system.txt — mentor matching JSON contract.
- interview_system.xml — idol persona conducting the diagnostic interview.

User prompts and their consumers (placeholders per PROMPT_PLACEHOLDERS below):

- profile_extract.txt / achievements_extract.txt / timeline_normalize.txt /
  milestones_by_age.txt — ingestion + extraction services.
- persona_pack.txt — persona generation in ingestion (profile/sources via f-string).
- plan_generate.txt — generate_plan() in planning.
- plan_item_details.txt — regenerate_plan_item_details in tasks/plans.py.
- book_module_generate.txt — generate_book_module() in content_resources.py.
- interview_question.txt / comparison_generate.txt / comparison_scores.txt /
  blueprint_generate.txt — agentic session flow in api/v1/sessions.py.
- idol_suggest.txt — suggest_idols() in api/v1/sessions.py.
- learning_materials_generate.txt — get_learning_materials() in api/v1/sessions.py.
- daily_feed_generate.txt — get_daily_feed() in api/v1/sessions.py.
- discover_feed.txt — discover feed generation in api/v1/feed.py.
- thinking_plan.txt / thinking_task.txt — streamed "thinking out loud" narration.
- image_generate.txt — DEPRECATED, not wired to any service.
"""
import json
import logging
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# Path to prompts directory (at project root)
PROMPTS_DIR = Path(__file__).parent.parent.parent.parent.parent / "prompts"

# Track loaded prompts for debugging
_loaded_prompts: set[str] = set()


# =============================================================================
# Prompt Placeholder Registry
# =============================================================================
# Documents required placeholders for each prompt file

PROMPT_PLACEHOLDERS = {
    "extractor_system.txt": [],  # No placeholders - pure system prompt
    "planner_system.txt": [],  # No placeholders - pure system prompt
    "idol_suggest_system.txt": [],  # No placeholders - pure system prompt
    "learning_materials_system.txt": [],  # No placeholders - pure system prompt

    "learning_materials_generate.txt": [
        "topic",
    ],

    "persona_system.txt": [
        "idol_name",
        "voice_style",
        "principles",
        "dos",
        "donts",
        "signature_phrases",
        "lexicon_allow",
        "lexicon_ban",
        "worldview_adapter_json",
        "taboo_topics",
        "era_context",
        "disclaimer",
    ],

    "guided_learning_system.txt": [
        "idol_name",
        "topic",
        "voice_style",
        "principles",
        "dos",
        "donts",
        "signature_phrases",
        "lexicon_allow",
        "lexicon_ban",
        "worldview_adapter_json",
        "taboo_topics",
        "era_context",
        "conversation_history_json",
        "disclaimer",
    ],


    "profile_extract.txt": [
        "selected_name",
        "provider",
        "external_id", 
        "wikipedia_url",
        "sources_json_array",
    ],
    
    "achievements_extract.txt": [
        "idol_name",
        "sources_json_array",
    ],
    
    "timeline_normalize.txt": [
        "idol_birth_date",
        "candidates_json",
    ],
    
    "milestones_by_age.txt": [
        "target_age",
        "mode",
        "timeline_json",
    ],
    
    "plan_generate.txt": [
        "user_goal",
        "idol_name",
        "hours_per_week",
        "target_age",
        "user_context",
        "idol_profile_json",
        "idol_persona_json",
        "idol_milestones_json",
        "gaps_json",
        "readiness_by_gap_json",
        "interview_transcript_json",
        "comparison_summary",
        "blueprint_markdown",
        "previous_cycle_block",
    ],
    
    
    
    
    "persona_pack.txt": [
        "idol_name",
    ],  # Also receives profile and sources via f-string injection
    
    
    
    
    "plan_item_details.txt": [
        "task_title",
        "user_goal",
        "learning_preferences",
        "idol_name",
        "idol_domain",
        "idol_evidence_json",
        "session_context",
    ],

    "book_module_generate.txt": [
        "book_title",
        "author",
        "user_goal",
        "source_context",
    ],
    
    
    "discover_feed.txt": [
        "count",
        "interests_json",
        "goals_json",
        "idol_name",
        "exclude_titles_json",
    ],
    
    "thinking_plan.txt": [
        "idol_name",
    ],
    
    "thinking_task.txt": [
        "task_title",
        "idol_name",
    ],
    
    # =========================================================================
    # Agentic Workflow Prompts
    # =========================================================================
    
    "interview_system.xml": [
        "idol_name",
        "idol_era",
        "idol_domain",
        "voice_style",
        "signature_phrases",
        "principles",
        "dos",
        "donts",
        "lexicon_allow",
        "lexicon_ban",
        "worldview_adapter_json",
        "taboo_topics",
        "user_age",
        "user_financial_status",
        "user_interests_json",
        "user_goal",
        "chat_history_json",
    ],

    "interview_question.txt": [
        "idol_name",
        "user_age",
        "user_financial_status",
        "user_interests_json",
        "user_goal",
        "chat_history_json",
        "turn_count",
        "max_turns",
        "idol_facts_json",
        "user_message",
    ],
    
    "comparison_generate.txt": [
        "idol_name",
        "user_age",
        "user_profile_json",
        "interview_transcript_json",
        "idol_facts_json",
    ],
    
    "blueprint_generate.txt": [
        "idol_name",
        "user_age",
        "user_profile_json",
        "interview_transcript_json",
        "comparison_summary",
        "idol_facts_json",
        "weekly_hours",
    ],

    "idol_suggest.txt": [
        "user_age",
        "user_financial_status",
        "user_interests_json",
        "user_goal",
    ],
    
    "daily_feed_generate.txt": [
        "count",
        "idol_name",
        "user_profile_json",
        "idol_evidence_json",
    ],

    
    "image_generate.txt": [
        "idol_name",
        "age",
        "idol_description",
    ],

    "comparison_scores.txt": [
        "idol_name",
        "user_age",
        "user_profile_json",
        "interview_transcript_json",
        "idol_facts_json",
        "comparison_summary",
    ],

    "comparison_analyze.txt": [
        "idol_name",
        "idol_field",
        "idol_bio",
        "target_age",
        "idol_milestones",
        "user_age",
        "user_background",
        "user_achievements",
    ],

}


class PromptRenderError(Exception):
    """Raised when prompt rendering fails due to missing placeholders."""
    
    def __init__(self, prompt_name: str, missing_keys: list[str]):
        self.prompt_name = prompt_name
        self.missing_keys = missing_keys
        super().__init__(
            f"PROMPT_PARAMS_MISSING: Prompt '{prompt_name}' missing required params: {missing_keys}"
        )


_UNTRUSTED_OPEN = "<<<USER_INPUT"
_UNTRUSTED_CLOSE = "USER_INPUT>>>"


def sanitize_untrusted_input(text: str | None) -> str:
    """Wrap untrusted user text in delimiters and neutralise any attempt to
    break out of the block (so it can be safely embedded in an LLM prompt)."""
    raw = "" if text is None else str(text)
    neutralised = re.sub(r"[<>]{3,}", "…", raw)
    neutralised = neutralised.replace("USER_INPUT", "user input")
    return f"{_UNTRUSTED_OPEN}\n{neutralised}\n{_UNTRUSTED_CLOSE}"


def get_prompts_dir() -> Path:
    """Get the prompts directory path."""
    return PROMPTS_DIR


def list_available_prompts() -> list[str]:
    """List all available prompt template files (.txt and .xml)."""
    if not PROMPTS_DIR.exists():
        return []
    txt_files = list(PROMPTS_DIR.glob("*.txt"))
    xml_files = list(PROMPTS_DIR.glob("*.xml"))
    return sorted([f.name for f in txt_files + xml_files])


def get_loaded_prompts() -> list[str]:
    """Get list of prompts that have been loaded during this session."""
    return sorted(_loaded_prompts)


def get_required_placeholders(prompt_name: str) -> list[str]:
    """
    Get the required placeholders for a prompt file.
    
    Args:
        prompt_name: Name of the prompt file (with or without .txt/.xml)
        
    Returns:
        List of required placeholder names
    """
    # Check if already has a valid extension
    if not (prompt_name.endswith(".txt") or prompt_name.endswith(".xml")):
        prompt_name = f"{prompt_name}.txt"
    return PROMPT_PLACEHOLDERS.get(prompt_name, [])


def extract_placeholders(template: str) -> list[str]:
    """
    Extract all placeholders from a template string.
    
    Args:
        template: Template string with {placeholder} patterns
        
    Returns:
        List of unique placeholder names found
    """
    # Match {placeholder_name} patterns, excluding JSON-like content
    pattern = r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'
    matches = re.findall(pattern, template)
    # Filter out common JSON schema tokens
    json_tokens = {'string', 'null', 'true', 'false', 'object', 'array', 'number', 'integer'}
    return list(set(m for m in matches if m not in json_tokens))


@lru_cache(maxsize=32)
def load_prompt(name: str) -> str:
    """
    Load a prompt template from the prompts directory.
    
    Args:
        name: Name of the prompt file (with or without .txt/.xml extension)
        
    Returns:
        The prompt template content
        
    Raises:
        FileNotFoundError: If the prompt file doesn't exist
    """
    # Add .txt extension if not present and not .xml
    if not (name.endswith(".txt") or name.endswith(".xml")):
        name = f"{name}.txt"
    
    prompt_path = PROMPTS_DIR / name
    
    if not prompt_path.exists():
        raise FileNotFoundError(f"Prompt template not found: {prompt_path}")
    
    content = prompt_path.read_text(encoding="utf-8")
    
    # Track loaded prompts
    _loaded_prompts.add(name)
    
    logger.debug(f"[PROMPT] Loaded template: {name} ({len(content)} chars)")
    return content


def render_prompt(
    template: str, 
    variables: dict[str, Any],
    prompt_name: str | None = None,
    strict: bool = True,
) -> str:
    """
    Render a prompt template with variable substitution.
    
    Uses {variable_name} syntax for placeholders.
    
    Args:
        template: The prompt template string
        variables: Dictionary of variable names to values
        prompt_name: Optional name for validation against registry
        strict: If True, raises error on missing required params
        
    Returns:
        The rendered prompt with variables substituted
        
    Raises:
        PromptRenderError: If strict=True and required placeholders are missing
        
    Example:
        >>> template = "Hello {name}, you are {age} years old."
        >>> render_prompt(template, {"name": "Alice", "age": "30"})
        'Hello Alice, you are 30 years old.'
    """
    # Log prompt name and keys (not values for privacy)
    if prompt_name:
        logger.info(f"[PROMPT] Rendering {prompt_name} with keys: {sorted(variables.keys())}")
    else:
        logger.debug(f"[PROMPT] Rendering unnamed prompt with keys: {sorted(variables.keys())}")
    
    # Validate against registry if prompt_name provided
    if prompt_name and strict:
        required = get_required_placeholders(prompt_name)
        missing = [k for k in required if k not in variables]
        if missing:
            logger.error(f"PROMPT_PARAMS_MISSING: {prompt_name} missing: {missing}")
            raise PromptRenderError(prompt_name, missing)
    
    # Convert all values to strings, handling None and JSON
    str_variables = {}
    for key, value in variables.items():
        if value is None:
            str_variables[key] = "null"
        elif isinstance(value, (dict, list)):
            # Compact UTF-8 JSON preserves the exact structure while avoiding
            # thousands of whitespace/escape tokens in source-heavy prompts.
            str_variables[key] = json.dumps(
                value,
                ensure_ascii=False,
                separators=(",", ":"),
            )
        else:
            str_variables[key] = str(value)
    
    result = template
    
    # Track used and unused variables
    used_keys = set()
    
    for key, value in str_variables.items():
        placeholder = "{" + key + "}"
        if placeholder in result:
            result = result.replace(placeholder, value)
            used_keys.add(key)
    
    # Warn about unused variables
    unused = set(str_variables.keys()) - used_keys
    if unused:
        logger.debug(f"Unused variables in prompt render: {unused}")

    if strict:
        unresolved = extract_placeholders(result)
        if unresolved:
            logger.error(f"PROMPT_PARAMS_MISSING: {prompt_name or '<inline>'} unresolved: {unresolved}")
            raise PromptRenderError(prompt_name or "<inline>", sorted(unresolved))
    
    return result


def load_and_render(
    name: str, 
    variables: dict[str, Any] | None = None,
    strict: bool = True,
) -> str:
    """
    Load a prompt template and render it with variables in one step.
    
    Args:
        name: Name of the prompt file
        variables: Optional dictionary of variables to substitute
        strict: If True, validates all required placeholders are provided
        
    Returns:
        The rendered prompt
    """
    template = load_prompt(name)
    
    # Normalize name for registry lookup
    if name.endswith(".txt") or name.endswith(".xml"):
        prompt_name = name
    else:
        prompt_name = f"{name}.txt"
    
    if variables:
        return render_prompt(template, variables, prompt_name=prompt_name, strict=strict)
    
    logger.info(f"[PROMPT] Loaded {prompt_name} (no variables)")
    return template


def validate_prompt_params(prompt_name: str, params: dict[str, Any]) -> list[str]:
    """
    Validate that all required parameters are provided for a prompt.
    
    Args:
        prompt_name: Name of the prompt file
        params: Dictionary of parameters being passed
        
    Returns:
        List of missing parameter names (empty if all present)
    """
    if not (prompt_name.endswith(".txt") or prompt_name.endswith(".xml")):
        prompt_name = f"{prompt_name}.txt"
    
    required = PROMPT_PLACEHOLDERS.get(prompt_name, [])
    return [k for k in required if k not in params]


# =============================================================================
# Prompt Template Registry (Service -> Prompts mapping)
# =============================================================================

PROMPT_REGISTRY = {
    # Ingestion pipeline
    "ingestion": {
        "profile_extraction": ["extractor_system.txt", "profile_extract.txt"],
        "achievements_extraction": ["extractor_system.txt", "achievements_extract.txt"],
        "timeline_normalization": ["extractor_system.txt", "timeline_normalize.txt"],
        "persona_generation": ["extractor_system.txt", "persona_pack.txt"],
    },
    # Plan generation
    "planning": {
        "generate_plan": ["planner_system.txt", "plan_generate.txt"],
        "generate_item_details": ["planner_system.txt", "plan_item_details.txt"],
        "generate_book_module": ["planner_system.txt", "book_module_generate.txt"],
    },
    # Milestones query
    "milestones": {
        "by_age": ["extractor_system.txt", "milestones_by_age.txt"],
    },
    # Idol suggestion (session flow)
    "idols": {
        "suggest_for_session": ["idol_suggest_system.txt", "idol_suggest.txt"],
    },
    # Agentic workflow (sessions API)
    "agentic": {
        "interview": ["interview_system.xml", "interview_question.txt"],
        "comparison": ["persona_system.txt", "comparison_generate.txt"],
        "comparison_scores": ["comparison_scores.txt"],
        "legacy_comparison_analysis": ["comparison_analyze.txt"],
        "blueprint": ["persona_system.txt", "blueprint_generate.txt"],
    },
    # Guided learning (sessions API)
    "learning": {
        "materials": ["learning_materials_system.txt", "learning_materials_generate.txt"],
        "tutor": ["guided_learning_system.txt"],
    },
    # Feeds
    "feed": {
        "daily_insights": ["persona_system.txt", "daily_feed_generate.txt"],
        "discover": ["discover_feed.txt"],
    },
}


def get_prompts_for_service(service: str, operation: str) -> list[str]:
    """
    Get the list of prompt files used by a service operation.
    
    Args:
        service: Service name (e.g., "ingestion", "planning", "chat")
        operation: Operation name (e.g., "profile_extraction", "generate_plan")
        
    Returns:
        List of prompt file names used by the operation
    """
    service_ops = PROMPT_REGISTRY.get(service, {})
    return service_ops.get(operation, [])
