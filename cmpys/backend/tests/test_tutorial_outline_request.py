"""Tutorial outlines run at low reasoning with a cap that grows with the sequence."""
from app.core.config import settings
from app.tasks.plans import _outline_client_options, _plan_detail_lesson_count_bounds


def _zai(monkeypatch, overrides=None):
    monkeypatch.setattr(settings, "llm_provider", "zai")
    monkeypatch.setattr(settings, "zai_reasoning_overrides", overrides or {})


def test_tutorial_outline_defaults_to_low_reasoning(monkeypatch):
    _zai(monkeypatch)
    assert _outline_client_options(tutorial=True, maximum_lessons=24, tier="balanced") == {
        "timeout": 45, "max_tokens": 5280, "tier": "balanced", "thinking_level": "low"}
    # Long-lesson outlines keep their request unchanged.
    assert _outline_client_options(tutorial=False, maximum_lessons=4, tier="balanced") == {
        "timeout": 45, "max_tokens": 4000, "tier": "balanced", "thinking_level": "medium"}


def test_an_operation_override_still_wins(monkeypatch):
    _zai(monkeypatch, {"plan_item_tutorial_outline": "high"})
    options = _outline_client_options(tutorial=True, maximum_lessons=24, tier="balanced")
    assert options["thinking_level"] == "high"


def test_cap_grows_only_for_sequences_above_thirty_lessons(monkeypatch):
    _zai(monkeypatch)
    caps = {}
    for hours in (1, 2, 2.5, 3, 6):
        maximum = _plan_detail_lesson_count_bounds(hours, lesson_format="tutorial_v1")[1]
        caps[hours] = _outline_client_options(tutorial=True, maximum_lessons=maximum, tier="balanced")["timeout"]
    # Two attempts at the ceiling still leave most of the job deadline for tutorial 1.
    assert caps == {1: 45, 2: 45, 2.5: 45, 3: 54, 6: 90}
