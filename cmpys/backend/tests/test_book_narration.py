from types import SimpleNamespace

from app.services.book_narration import (
    align_transcribed_words,
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


def test_word_timing_maps_to_source_ranges_and_interpolates_a_missing_word():
    text = "A thoughtful reader sounds truly human."
    words = [
        SimpleNamespace(word="A", start=0.0, end=0.15),
        SimpleNamespace(word="thoughtful", start=0.15, end=0.7),
        # Whisper occasionally omits a short word; "reader" still has an
        # exact source cue interpolated between its neighbors.
        SimpleNamespace(word="sounds", start=1.1, end=1.45),
        SimpleNamespace(word="truly", start=1.45, end=1.8),
        SimpleNamespace(word="human", start=1.8, end=2.25),
    ]

    cues = align_transcribed_words(text, words, duration_seconds=2.3)

    assert [text[cue.start : cue.end] for cue in cues] == [
        "A",
        "thoughtful",
        "reader",
        "sounds",
        "truly",
        "human",
    ]
    assert cues[2].startMs == cues[1].endMs
    assert cues[2].endMs == cues[3].startMs
    assert all(cue.endMs > cue.startMs for cue in cues)
