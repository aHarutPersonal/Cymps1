from app.services.llm.prompt_loader import (
    _UNTRUSTED_CLOSE,
    _UNTRUSTED_OPEN,
    get_required_placeholders,
    load_prompt,
)
from app.services.llm.schemas import AIComparisonOutput


def test_legacy_ai_comparison_prompt_exists_and_is_registered() -> None:
    text = load_prompt("comparison_analyze")

    assert "trainable" in text
    assert "same age" in text
    assert set(get_required_placeholders("comparison_analyze")) == {
        "idol_name",
        "idol_field",
        "idol_bio",
        "target_age",
        "idol_milestones",
        "user_age",
        "user_background",
        "user_achievements",
    }


def test_ai_comparison_output_contract_accepts_endpoint_shape() -> None:
    result = AIComparisonOutput.model_validate(
        {
            "overallScore": 42,
            "overallAnalysis": "The supplied record shows an early system.",
            "realisticPerspective": "The evidence is incomplete.",
            "encouragement": "The next gap is trainable.",
            "categoryBreakdown": [
                {
                    "category": "learning",
                    "score": 50,
                    "analysis": "Consistent study is documented.",
                    "userStrengths": ["Weekly practice"],
                    "gaps": ["No completed artifact"],
                    "keyIdolMilestone": None,
                    "userBestMatch": "Weekly practice",
                }
            ],
            "strengths": [],
            "gaps": [],
            "nextMilestone": None,
        }
    )

    assert result.overallScore == 42


def test_ai_comparison_untrusted_markers_are_distinct() -> None:
    assert _UNTRUSTED_OPEN != _UNTRUSTED_CLOSE
