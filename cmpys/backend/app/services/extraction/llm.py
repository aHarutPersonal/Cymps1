"""LLM-based achievement extractor using AI models."""
from app.core.config import settings
from app.models.source_chunk import SourceChunk
from app.services.extraction.base import AchievementExtractor
from app.services.extraction.schemas import AchievementDraft


class LLMExtractor(AchievementExtractor):
    """
    LLM-based achievement extractor.

    Uses an AI model to extract structured achievements from text.
    Requires OPENAI_API_KEY or similar to be configured.
    """

    def __init__(self) -> None:
        """Initialize the LLM extractor."""
        if not settings.openai_api_key:
            raise NotImplementedError(
                "LLM extractor requires OPENAI_API_KEY to be set. "
                "Set EXTRACTOR_MODE=deterministic or provide an API key."
            )

    async def extract(
        self,
        chunks: list[SourceChunk],
        idol_name: str,
        source_url: str,
    ) -> list[AchievementDraft]:
        """
        Extract achievements using LLM.

        This is a placeholder implementation that will be filled in
        when LLM integration is added.
        """
        raise NotImplementedError(
            "LLM extraction is not yet implemented. "
            "Use EXTRACTOR_MODE=deterministic for now."
        )

        # Future implementation would:
        # 1. Prepare prompt with chunks and idol context
        # 2. Call OpenAI API with structured output schema
        # 3. Parse response into AchievementDraft objects
        # 4. Validate and return results
