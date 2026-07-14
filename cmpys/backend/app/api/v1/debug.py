"""Debug endpoints for development and monitoring."""
from fastapi import APIRouter
from pydantic import BaseModel

from app.core.config import settings
from app.services.llm.prompt_loader import (
    PROMPT_REGISTRY,
    get_loaded_prompts,
    list_available_prompts,
)

router = APIRouter(prefix="/debug", tags=["debug"])


class LLMStatusResponse(BaseModel):
    """LLM configuration status (does not expose API keys)."""
    
    provider: str
    model: str | None
    configured: bool


class PromptsResponse(BaseModel):
    """List of available and loaded prompt templates."""
    
    available: list[str]
    loaded: list[str]
    registry: dict[str, dict[str, list[str]]]


@router.get("/llm", response_model=LLMStatusResponse)
async def get_llm_status() -> LLMStatusResponse:
    """
    Get LLM configuration status.
    
    Returns the configured provider and model WITHOUT exposing
    the API key. Use this to verify your configuration.
    """
    models = {
        "openai": settings.openai_model,
        "gemini": settings.gemini_model,
        "yunwu": settings.yunwu_model,
    }
    return LLMStatusResponse(
        provider=settings.llm_provider,
        model=models.get(settings.llm_provider),
        configured=settings.llm_configured,
    )


@router.get("/prompts", response_model=PromptsResponse)
async def get_prompts() -> PromptsResponse:
    """
    Get list of available prompt templates (dev-only).
    
    Returns:
    - available: All prompt files in the /prompts directory
    - loaded: Prompts that have been loaded during this session
    - registry: Mapping of service -> operation -> prompt files
    
    NOTE: Does not expose prompt contents, only filenames.
    """
    return PromptsResponse(
        available=list_available_prompts(),
        loaded=get_loaded_prompts(),
        registry=PROMPT_REGISTRY,
    )
