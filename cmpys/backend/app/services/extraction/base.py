"""Base class for achievement extraction."""
from abc import ABC, abstractmethod

from app.models.source_chunk import SourceChunk
from app.services.extraction.schemas import AchievementDraft


class AchievementExtractor(ABC):
    """Abstract base class for achievement extractors."""

    @abstractmethod
    async def extract(
        self,
        chunks: list[SourceChunk],
        idol_name: str,
        source_url: str,
    ) -> list[AchievementDraft]:
        """
        Extract achievements from source chunks.

        Args:
            chunks: List of source chunks to analyze
            idol_name: Name of the idol for context
            source_url: URL of the source for evidence linking

        Returns:
            List of AchievementDraft objects
        """
        pass


def get_extractor() -> AchievementExtractor:
    """
    Factory function to get the configured extractor.

    Uses EXTRACTOR_MODE env var: 'deterministic' (default) or 'llm'
    """
    from app.core.config import settings

    if settings.extractor_mode == "llm":
        from app.services.extraction.llm import LLMExtractor
        return LLMExtractor()
    else:
        from app.services.extraction.deterministic import DeterministicExtractor
        return DeterministicExtractor()
