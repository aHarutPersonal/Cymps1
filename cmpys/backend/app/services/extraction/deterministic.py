"""Deterministic achievement extractor using rule-based extraction."""
import re
from datetime import date

from app.models.source_chunk import SourceChunk
from app.services.extraction.base import AchievementExtractor
from app.services.extraction.schemas import (
    AchievementDraft,
    DatePrecisionEnum,
    EvidenceDraft,
)


class DeterministicExtractor(AchievementExtractor):
    """
    Rule-based achievement extractor.

    Uses pattern matching to find:
    - Section headings suggesting achievements
    - Sentences with dates and action verbs
    - Fills remaining slots with chunk-based placeholders
    """

    # Action verbs that often indicate achievements
    ACTION_VERBS = [
        "founded", "created", "launched", "started", "won", "received",
        "became", "joined", "acquired", "sold", "published", "invented",
        "established", "discovered", "developed", "pioneered", "led",
        "built", "designed", "achieved", "awarded", "elected", "appointed",
    ]

    # Keywords for categorizing headings
    HEADING_CATEGORIES = {
        "career": ["career", "business", "company", "work", "professional"],
        "award": ["award", "honor", "recognition", "prize", "medal"],
        "education": ["education", "academic", "university", "degree", "school"],
        "philanthropy": ["philanthropy", "charity", "giving", "foundation", "donate"],
    }

    # Keywords for categorizing sentences
    SENTENCE_CATEGORIES = {
        "entrepreneurship": ["founded", "started", "created", "launched", "co-founded"],
        "award": ["won", "received", "awarded", "honored"],
        "business": ["acquired", "sold", "merger", "billion", "million", "ipo"],
        "education": ["graduated", "degree", "university", "studied", "enrolled"],
    }

    async def extract(
        self,
        chunks: list[SourceChunk],
        idol_name: str,
        source_url: str,
    ) -> list[AchievementDraft]:
        """Extract achievements using deterministic rules."""
        if not chunks:
            return []

        # Combine chunks for full text analysis
        full_text = "\n\n".join(c.text for c in sorted(chunks, key=lambda x: x.chunk_index))

        achievements: list[AchievementDraft] = []

        # Strategy 1: Extract from section headings
        heading_achievements = self._extract_from_headings(full_text, source_url)
        achievements.extend(heading_achievements[:5])

        # Strategy 2: Extract from date-containing sentences
        date_achievements = self._extract_from_dated_sentences(
            chunks, idol_name, source_url
        )
        achievements.extend(date_achievements)

        # Strategy 3: Fill with chunk-based placeholders if needed
        target_count = 10
        if len(achievements) < target_count:
            placeholder_achievements = self._create_placeholders(
                chunks, source_url, target_count - len(achievements)
            )
            achievements.extend(placeholder_achievements)

        # Limit to 15 max
        return achievements[:15]

    def _extract_from_headings(
        self, full_text: str, source_url: str
    ) -> list[AchievementDraft]:
        """Extract achievements from section headings."""
        achievements = []

        # Find section headings
        heading_pattern = r"##\s*([A-Z][^#\n]+)"
        headings = re.findall(heading_pattern, full_text)

        # Filter to achievement-related headings
        achievement_keywords = [
            "career", "award", "achievement", "business", "found",
            "company", "education", "philanthropy", "work", "life",
            "history", "legacy", "contribution",
        ]

        for heading in headings:
            heading = heading.strip()
            if any(kw in heading.lower() for kw in achievement_keywords):
                category = self._categorize_heading(heading)
                achievements.append(
                    AchievementDraft(
                        title=heading[:200],
                        description=f"Notable period or achievement: {heading}",
                        category=category,
                        date=None,
                        date_precision=DatePrecisionEnum.UNKNOWN,
                        confidence=0.4,
                        evidence=[
                            EvidenceDraft(
                                source_url=source_url,
                                snippet=f"Section: {heading}",
                                confidence=0.4,
                            )
                        ],
                    )
                )

        return achievements

    def _extract_from_dated_sentences(
        self,
        chunks: list[SourceChunk],
        idol_name: str,
        source_url: str,
    ) -> list[AchievementDraft]:
        """Extract achievements from sentences containing dates and action verbs."""
        achievements = []
        year_pattern = r"(?:in\s+)?(\d{4})[,\s]"

        for chunk in chunks:
            sentences = re.split(r"(?<=[.!?])\s+", chunk.text)

            for sentence in sentences:
                year_match = re.search(year_pattern, sentence)

                if year_match and any(
                    verb in sentence.lower() for verb in self.ACTION_VERBS
                ):
                    year = int(year_match.group(1))

                    # Validate year range
                    if not (1800 <= year <= 2030):
                        continue

                    title = self._create_title_from_sentence(sentence, idol_name)
                    if not title or len(title) < 10:
                        continue

                    category = self._categorize_sentence(sentence)

                    achievements.append(
                        AchievementDraft(
                            title=title[:200],
                            description=sentence[:2000],
                            category=category,
                            date=date(year, 1, 1),
                            date_precision=DatePrecisionEnum.YEAR,
                            confidence=0.35,
                            evidence=[
                                EvidenceDraft(
                                    source_url=source_url,
                                    snippet=sentence[:500],
                                    confidence=0.35,
                                )
                            ],
                        )
                    )

        return achievements

    def _create_placeholders(
        self,
        chunks: list[SourceChunk],
        source_url: str,
        count: int,
    ) -> list[AchievementDraft]:
        """Create placeholder achievements from chunk content."""
        achievements = []

        for i, chunk in enumerate(chunks[:count]):
            first_sentence = chunk.text.split(".")[0][:150]

            achievements.append(
                AchievementDraft(
                    title=f"Notable fact #{i + 1}",
                    description=first_sentence + "...",
                    category="general",
                    date=None,
                    date_precision=DatePrecisionEnum.UNKNOWN,
                    confidence=0.2,
                    evidence=[
                        EvidenceDraft(
                            source_url=source_url,
                            snippet=chunk.text[:500],
                            confidence=0.2,
                        )
                    ],
                )
            )

        return achievements

    def _create_title_from_sentence(self, sentence: str, idol_name: str) -> str:
        """Create a concise title from a sentence."""
        title = sentence.replace(idol_name, "").strip()

        # Truncate at first separator
        for sep in [",", ".", ";", " and ", " which ", " that "]:
            if sep in title:
                title = title.split(sep)[0]
                break

        # Clean up leading date patterns
        title = re.sub(r"^\s*(In\s+\d{4}\s*[,]?\s*)?", "", title)
        title = title.strip().capitalize()

        return title[:150] if title else ""

    def _categorize_heading(self, heading: str) -> str:
        """Categorize achievement based on heading text."""
        heading_lower = heading.lower()

        for category, keywords in self.HEADING_CATEGORIES.items():
            if any(kw in heading_lower for kw in keywords):
                return category

        return "general"

    def _categorize_sentence(self, sentence: str) -> str:
        """Categorize achievement based on sentence content."""
        sentence_lower = sentence.lower()

        for category, keywords in self.SENTENCE_CATEGORIES.items():
            if any(kw in sentence_lower for kw in keywords):
                return category

        return "career"
