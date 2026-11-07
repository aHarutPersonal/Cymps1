import pytest

from app.core.config import settings
from app.services.book_narration import (
    _narrator_profile,
    narration_text_belongs_to_resource,
)


def test_rendered_markdown_passage_is_accepted_for_narration():
    markdown = """
## Choose with care

Read **one small step**, then visit [the guide](https://example.com/guide).
"""

    assert narration_text_belongs_to_resource(
        "Read one small step, then visit the guide.",
        markdown,
    )
    assert not narration_text_belongs_to_resource("Read an unrelated script.", markdown)


def test_ordered_list_markers_are_not_required_in_spoken_chunk_membership():
    markdown = """
1. Observe the business carefully.
2. Wait for a durable advantage.
3. Act with a margin of safety.
"""

    assert narration_text_belongs_to_resource(
        "Observe the business carefully. Wait for a durable advantage.",
        markdown,
    )
    assert not narration_text_belongs_to_resource(
        "Observe the business carelessly. Wait for a durable advantage.",
        markdown,
    )


def test_membership_keeps_digits_that_are_not_markdown_list_markers():
    markdown = "Version 2 preserves the 80/20 rule. Step 3 remains important."

    assert narration_text_belongs_to_resource(markdown, markdown)
    assert not narration_text_belongs_to_resource(
        "Version preserves the rule. Step remains important.",
        markdown,
    )


def test_narrator_profiles_are_server_allowlisted(monkeypatch):
    monkeypatch.setattr(settings, "book_narration_gemini_voice", "Sulafat")
    monkeypatch.setattr(settings, "book_narration_gemini_mentor_voice", "Gacrux")
    expressive = _narrator_profile("expressive_narrator")
    mentor = _narrator_profile("seasoned_mentor")
    assert (expressive.voice_id, expressive.display_name) == ("Sulafat", "Expressive narrator")
    assert (mentor.voice_id, mentor.display_name) == ("Gacrux", "Seasoned mentor")
    with pytest.raises(ValueError):
        _narrator_profile("public_figure_clone")


def test_comparison_cards_speak_existing_box_content_without_frame_characters():
    markdown = '''```
+----------------------------------------------------------------+
| INVESTMENT OPERATION                                           |
| 1. Thorough Financial Analysis (Earnings, Assets, Balance Sheet) |
| 2. Safety of Principal (Protection Against Capital Destruction) |
+----------------------------------------------------------------+
vs.
+----------------------------------------------------------------+
| SPECULATIVE OPERATION                                          |
| 1. Price Momentum Tracking (Buying Because It Is Rising)        |
| 2. Unhedged Capital Exposure (Ignoring Downside Risk)           |
+----------------------------------------------------------------+
```'''
    semantic = '\n'.join(line.strip().strip('|').strip() for line in markdown.splitlines()
                         if not line.startswith(('+', '```')))
    assert narration_text_belongs_to_resource(semantic, markdown)
    assert not narration_text_belongs_to_resource(semantic.replace('Safety', 'Guarantee'), markdown)


def test_new_semantic_comparison_bullets_are_authorized_without_relaxing_source_match():
    markdown = '```comparison\nFirst approach\n- Consider the evidence\n- Check the downside\n\nvs.\n\nSecond approach\n- Follow the price\n- Ignore the risk\n```'
    semantic = 'First approach\n- Consider the evidence\n- Check the downside\nvs.\nSecond approach\n- Follow the price\n- Ignore the risk'
    assert narration_text_belongs_to_resource(semantic, markdown)
    assert not narration_text_belongs_to_resource(semantic.replace('Ignore', 'Guarantee'), markdown)
