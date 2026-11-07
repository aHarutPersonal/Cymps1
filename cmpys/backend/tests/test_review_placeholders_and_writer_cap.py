"""Two failure classes from the 2026-11-06 paid subset after the audit fixes.

A lesson review was rejected for an empty placeholder key beside its schema,
and Armenian readings ran out of the 2,600-token writer cap once they were
really written in Armenian. Each fix has a wrong twin that must still fail.
"""
import pytest
from pydantic import ValidationError

from app.services.llm.client import LLMResponse
from app.services.planning.lesson_review import LessonReview, _canonical_review_data
from app.services.planning.lesson_writer import generate_lesson_sections
from tests.test_tutorial_reading_budget import sections
from tests.test_tutorial_workload_profile import short_package
from tests.test_writer_learner_language import TITLE, armenian_sections, lesson_prompt

REVIEW = {"acceptable": True, "issues": [], "practice_minutes": 3, "contains_calculations": False,
          "calculations": [], "literal_facts": [], "literal_fact_ids": [], "math_roles": []}


@pytest.mark.parametrize("key,value", [
    ("issue_severities_placeholder", None), ("public_quick_checks_note", ""), ("notes", "  "),
    ("extra_audits", []), ("meta", {}),
])
def test_an_empty_placeholder_beside_the_schema_is_dropped(key, value):
    review = LessonReview.model_validate(_canonical_review_data({**REVIEW, key: value}, packaged=True))
    assert review.acceptable


@pytest.mark.parametrize("key,value", [
    ("issue_severities_placeholder", "blocking"), ("public_quick_checks_note", "option b is wrong"),
    ("extra_audits", [{"target": "n1"}]), ("meta", {"severity": "blocking"}), ("approved", False),
])
def test_an_unknown_key_with_content_still_fails(key, value):
    with pytest.raises(ValidationError):
        LessonReview.model_validate(_canonical_review_data({**REVIEW, key: value}, packaged=True))


def test_a_legacy_review_keeps_its_strict_wire():
    with pytest.raises(ValidationError):
        LessonReview.model_validate(_canonical_review_data({**REVIEW, "public_quick_checks_note": ""},
                                                           packaged=False))


async def writer_caps(locale, draft):
    options = []

    class Client:
        model = "test"

        async def generate_json(self, **kwargs):
            return LLMResponse(data=draft)

    def factory(**kwargs):
        options.append(kwargs)
        return Client()

    result, _ = await generate_lesson_sections(system_prompt="Teach", lesson_prompt=lesson_prompt(locale),
        package_context=short_package().writer_context(), lesson_format="tutorial_v1",
        allotted_lesson_minutes=6, lesson_title=TITLE, client_factory=factory)
    assert not result.error
    return [option["max_tokens"] for option in options]


@pytest.mark.asyncio
async def test_a_non_latin_learner_script_gets_room_for_its_reading():
    assert await writer_caps("hy", armenian_sections()) == [5200]


@pytest.mark.asyncio
@pytest.mark.parametrize("locale", ["en", None, "es"])
async def test_english_and_latin_script_readings_keep_the_original_cap(locale):
    assert await writer_caps(locale, sections()) == [2600]
