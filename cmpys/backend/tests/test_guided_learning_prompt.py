"""
Tests for the guided-learning Socratic system prompt.
"""
import pytest

from app.services.llm.prompt_loader import (
    PromptRenderError,
    extract_placeholders,
    load_and_render,
)


FULL_PARAMS = {
    "idol_name": "Warren Buffett",
    "topic": "intrinsic value",
    "voice_style": "Folksy, plainspoken, patient",
    "principles": ["Margin of safety", "Circle of competence"],
    "dos": ["Use simple analogies"],
    "donts": ["No hype"],
    "signature_phrases": ["Be fearful when others are greedy"],
    "lexicon_allow": ["owner earnings"],
    "lexicon_ban": ["to the moon"],
    "worldview_adapter_json": {"crypto": "speculation without underlying value"},
    "taboo_topics": ["day trading tips"],
    "era_context": "contemporary",
    "conversation_history_json": '[{"role": "user", "content": "What is a moat?"}]',
    "disclaimer": "AI simulation based on public sources.",
}


class TestGuidedLearningSystemPrompt:
    def test_renders_with_persona_fields(self):
        rendered = load_and_render("guided_learning_system.txt", FULL_PARAMS, strict=True)

        assert "Warren Buffett" in rendered
        assert "Folksy, plainspoken" in rendered
        assert "Margin of safety" in rendered
        assert "intrinsic value" in rendered
        assert "What is a moat?" in rendered
        assert not extract_placeholders(rendered)

    def test_keeps_socratic_method(self):
        rendered = load_and_render("guided_learning_system.txt", FULL_PARAMS, strict=True)

        assert "Guide with questions" in rendered
        assert "misconception" in rendered.lower()

    def test_requires_all_fields(self):
        with pytest.raises(PromptRenderError):
            load_and_render(
                "guided_learning_system.txt",
                {"idol_name": "Warren Buffett"},
                strict=True,
            )
