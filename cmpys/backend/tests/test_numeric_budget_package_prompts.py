"""Option B (fewer numeric claims): seed and activity prompts of tutorial packages.

With ``tutorial_numeric_budget = N > 0`` a tutorial_v1 package's seed and
activity requests gain one appended rule; prompt files stay untouched, so their
budget tests still hold. N = 0 (the default) sends byte-identical prompts.
"""
import pytest

from app.core.config import settings
from app.services.llm.client import LLMResponse
from app.services.planning import package_builder as builder
from tests.test_numeric_budget_writer import set_budget
from tests.test_staged_package_builder import components, snapshot


class Capture:
    """Records each system prompt and fails the request without a retry."""

    def __init__(self):
        self.prompts = {}

    def __call__(self, **options):
        capture = self

        class Client:
            model = "offline-package-model"
            provider_name = "dummy"
            last_attempt = None

            async def generate_json(self, *, system_prompt, output_model, **request):
                capture.prompts.setdefault(output_model.__name__, system_prompt)
                return LLMResponse(data={}, error="offline capture", retryable=False, provider="dummy")

        return Client()


@pytest.fixture(autouse=True)
def usage(monkeypatch):
    async def record(**kwargs):
        return True
    monkeypatch.setattr(builder, "record_llm_response", record)


async def prompts(lesson_format):
    step = {"id": "step_1", "title": "Learn a skill", **({"lesson_format": lesson_format} if lesson_format else {})}
    context = {"locale": "en", "goal": "Apply it independently", "target_practice_minutes": 35}
    seed_capture, activity_capture = Capture(), Capture()
    await builder.generate_initial_package(step, context, client_factory=seed_capture)
    seed, _ = components()
    await builder.generate_initial_package(step, context, client_factory=activity_capture,
                                           existing_parts=snapshot(seed))
    activity = next(prompt for name, prompt in activity_capture.prompts.items() if name.endswith("ActivityDraft"))
    return seed_capture.prompts["LessonPackageSeed"], activity


@pytest.mark.asyncio
async def test_default_budget_keeps_package_prompts_byte_identical(monkeypatch):
    unset = [await prompts(fmt) for fmt in ("tutorial_v1", None)]
    set_budget(monkeypatch, 0)
    assert [await prompts(fmt) for fmt in ("tutorial_v1", None)] == unset
    assert not any("NUMBER BUDGET" in prompt for pair in unset for prompt in pair)


@pytest.mark.asyncio
async def test_positive_budget_appends_one_rule_to_tutorial_seed_and_activity_prompts(monkeypatch):
    default_seed, default_activity = await prompts("tutorial_v1")
    legacy = await prompts(None)
    set_budget(monkeypatch, 6)
    assert getattr(settings, "tutorial_numeric_budget") == 6
    seed, activity = await prompts("tutorial_v1")
    rule = builder._NUMERIC_BUDGET_RULE
    assert seed == default_seed + rule and activity == default_activity + rule
    text = " ".join(rule.split())
    assert "declared case and activity data, answer fields and worked-solution calculation steps" in text
    assert "Instructions, hints, explanations and examples" in text
    assert "never introduce new figures" in text and "never restate computed results" in text
    # Legacy (non-tutorial) packages are untouched.
    assert await prompts(None) == legacy
