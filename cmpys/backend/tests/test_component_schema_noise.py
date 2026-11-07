"""Schema noise around otherwise valid components (pilot 2026-11-03).

glm e23bd2e3: a sound seed failed only on a top-level ``"activity_briefs_note":
"unused"``. haiku-12 c67f590e: a text-only activity omitted ``data``. Content
keys, long notes and numeric activities keep strict validation.
"""
import copy
import json

import pytest
from pydantic import ValidationError

from app.services.llm.prompt_loader import resolve_prompt_text
from app.services.planning.activity_draft import TutorialActivityDraft, with_default_qualitative_data
from app.services.planning.package_builder import parse_initial_seed_response


def _exemplar(name):
    return json.loads(resolve_prompt_text(name).split("\n", 1)[1])


def _seed():
    from tests.test_package_fix2_activity_recovery import SEED
    return copy.deepcopy(SEED)


def test_short_top_level_note_is_dropped():
    seed, _ = parse_initial_seed_response({**_seed(), "activity_briefs_note": "unused"})
    assert "activity_briefs_note" not in seed.model_dump()


@pytest.mark.parametrize("extra", [
    {"activity_briefs_note": "x" * 41},          # long: may carry content
    {"activity_briefs_note": ["unused"]},        # not a string
    {"workbook_summary": "unused"},              # not a *_note key
])
def test_other_top_level_keys_stay_rejected(extra):
    with pytest.raises(ValidationError):
        parse_initial_seed_response({**_seed(), **extra})


def test_text_only_activity_without_data_declares_none():
    draft = _exemplar("tutorial_exemplar_qualitative.txt")
    draft.pop("data")
    with pytest.raises(ValidationError):
        TutorialActivityDraft.model_validate(draft)
    assert TutorialActivityDraft.model_validate(with_default_qualitative_data(draft)).data == []


def test_numeric_activity_without_data_is_not_defaulted():
    draft = _exemplar("tutorial_exemplar_quantitative.txt")
    draft.pop("data")
    assert with_default_qualitative_data(draft) is draft
