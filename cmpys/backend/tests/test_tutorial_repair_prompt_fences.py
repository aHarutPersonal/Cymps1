"""R1-I5: tutorial section repairs keep the reader's native fenced blocks.

The binding repair rewrites worked_example, whose ```steps fence carries the
result tokens, and the semantic repair rewrites up to three sections. The old
"no markdown fence" sentence told the model to strip those blocks.
"""

import inspect

import pytest

from app.services.planning.tutorial_blocks import BLOCK_KINDS
from app.tasks import plans
from app.tasks.plans import _plan_detail_sections_repair_prompt

SECTIONS = {"worked_example": "```steps\n1. Owner earnings = [[result:c1.r1]]\n```"}


def _prompt(*, lesson_format=None, step_format=None) -> str:
    step = {"title": "Value the car wash", "description": "One concept."}
    if step_format:
        step["lesson_format"] = step_format
    return _plan_detail_sections_repair_prompt(
        task_title="Value one business",
        step=step,
        materials=[],
        sections=SECTIONS,
        field_names=["worked_example"],
        lesson_format=lesson_format,
    )


@pytest.mark.parametrize("kwargs", [{"lesson_format": "tutorial_v1"}, {"step_format": "tutorial_v1"}])
def test_tutorial_repair_keeps_every_native_block(kwargs) -> None:
    prompt = _prompt(**kwargs)
    assert "or a markdown fence" not in prompt
    for kind in BLOCK_KINDS:
        assert f"```{kind}" in prompt, kind
    assert "never wrap the JSON answer itself in a markdown fence" in prompt


def test_legacy_lesson_repair_keeps_its_no_fence_rule() -> None:
    prompt = _prompt()
    assert "or a markdown fence" in prompt
    assert "```formula" not in prompt


def test_every_repair_call_passes_the_lesson_format() -> None:
    source = inspect.getsource(plans)
    calls = source.split("_plan_detail_sections_repair_prompt(")[2:]  # skip the def
    assert len(calls) == 3
    for call in calls:
        arguments = call[: call.index(")")]
        assert "lesson_format=lesson_format" in arguments, arguments
