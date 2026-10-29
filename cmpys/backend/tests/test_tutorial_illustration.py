"""Optional hero illustration for a published tutorial (Imagen 4, no text in the image).

No test here touches the network: Imagen is replaced by an in-memory fake and the
media directory by a temporary one. A missing illustration must never change what
the learner can read, nor the item or job status.
"""
import asyncio
import copy
import hashlib
import json
import os
import time
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from sqlalchemy.dialects import postgresql

from app.services.llm.prompt_loader import PROMPT_PLACEHOLDERS, extract_placeholders, load_prompt
from app.services.planning import tutorial_illustration as ti

JPEG = b"\xff\xd8\xff\xe0synthetic-jpeg-bytes"
TITLE = "Margin of safety"
SENTENCE = "A margin of safety is the gap between what you pay and what the asset is worth."
LESSON = (
    f"# {TITLE}\n\n## Why This Matters\nBecause prices move.\n\n## Core Framework\n"
    f"{SENTENCE} It protects you when your estimate is wrong.\n\n"
    "```comparison\nNo buffer\n- Fragile\nvs\nBuffer\n- Robust\n```\n\n## Worked Example\nA worked case.\n"
)


def key_for(title=TITLE, concept=SENTENCE):
    return hashlib.sha256((title + concept).encode("utf-8")).hexdigest()


class FakeImagen:
    """Stands in for ``genai.Client``; counts every (would-be paid) call."""

    def __init__(self, *, image_bytes=JPEG, error=None, images=None, on_call=None):
        self.calls = []
        self.error = error
        self.on_call = on_call
        self.images = images if images is not None else [
            SimpleNamespace(image=SimpleNamespace(image_bytes=image_bytes))
        ]
        self.aio = SimpleNamespace(models=SimpleNamespace(generate_images=self._generate_images))

    async def _generate_images(self, *, model, prompt, config):
        self.calls.append(SimpleNamespace(model=model, prompt=prompt, config=config))
        if self.on_call:
            self.on_call()
        if self.error:
            raise self.error
        return SimpleNamespace(generated_images=self.images)


def tutorial_step(step_id="step_1", title=TITLE, content=LESSON, **extra):
    return {"id": step_id, "title": title, "lesson_format": "tutorial_v1",
            "lesson_content": content, **extra}


def make_item(steps=None, *, domain="Investing", effective_goal=None):
    idol = SimpleNamespace(domain=domain) if domain else None
    plan = SimpleNamespace(
        idol=idol, roadmap_json={"effective_goal": effective_goal} if effective_goal else {})
    return SimpleNamespace(
        id=str(uuid4()), plan=plan,
        details_json={"steps": steps if steps is not None else [tutorial_step()],
                      "_generation": {"status": "partial", "job_id": "job-1"}},
    )


def fake_database(item):
    db = AsyncMock()
    db.add = MagicMock()
    statements = []

    async def execute(statement, *args, **kwargs):
        statements.append(statement)
        return SimpleNamespace(scalar_one_or_none=lambda: item)

    db.execute.side_effect = execute
    context = AsyncMock()
    context.__aenter__.return_value = db
    return db, statements, (lambda: context)


@pytest.fixture
def enabled(monkeypatch, tmp_path):
    monkeypatch.setattr(ti, "MEDIA_DIR", tmp_path)
    monkeypatch.setattr(ti.settings, "tutorial_illustrations_enabled", True)
    monkeypatch.setattr(ti.settings, "tutorial_illustration_daily_cap", 200)
    return tmp_path / "tutorials"


def wire(monkeypatch, item, imagen=None):
    db, statements, maker = fake_database(item)
    monkeypatch.setattr(ti, "async_session_maker", maker)
    imagen = imagen or FakeImagen()
    monkeypatch.setattr(ti, "build_genai_client", lambda: imagen)
    return db, statements, imagen


# --- the prompt ---------------------------------------------------------------------


def test_prompt_forbids_text():
    prompt = ti.build_illustration_prompt(TITLE, SENTENCE, "Investing")
    lowered = prompt.lower()
    for forbidden in ("no text", "letters", "numbers", "logos", "real people"):
        assert forbidden in lowered
    # Editorial style on the app's warm paper palette, wide framing.
    for palette in ("editorial illustration", "#f5f2ec", "ember", "iris", "sage"):
        assert palette in lowered
    assert TITLE in prompt and SENTENCE in prompt and "Investing" in prompt
    assert "{" not in prompt  # every placeholder was rendered


def test_prompt_template_is_registered_with_its_placeholders():
    assert PROMPT_PLACEHOLDERS["tutorial_illustration.txt"] == ["title", "concept", "domain"]
    assert sorted(extract_placeholders(load_prompt("tutorial_illustration.txt"))) == [
        "concept", "domain", "title"]


def test_prompt_inputs_are_single_line_and_bounded():
    noisy = "**Bold** idea\n\nwith\tgaps " + "x" * 600
    prompt = ti.build_illustration_prompt(noisy, noisy, noisy)
    assert "\t" not in prompt and "**" not in prompt
    assert len(prompt) < 2500


# --- deriving the concept ---------------------------------------------------------


def test_concept_is_first_core_framework_sentence_after_the_title():
    title, concept = ti.step_inputs(tutorial_step())
    assert title == TITLE
    assert concept == SENTENCE


def test_concept_skips_native_blocks_and_markdown_noise():
    content = ("# T\n\n## Core Framework\n```comparison\nA\n- one\nvs\nB\n- two\n```\n"
               "- **Price** is what you pay. Value is what you get.\n\n## Worked Example\nOther.")
    assert ti.step_inputs(tutorial_step(content=content))[1] == "Price is what you pay."


def test_concept_falls_back_to_description_then_title():
    assert ti.step_inputs({"id": "s", "title": "Only title", "lesson_content": "no headings"})[1] == "Only title"
    described = {"id": "s", "title": "T", "description": "Why scale matters. More.", "lesson_content": "x"}
    assert ti.step_inputs(described)[1] == "Why scale matters."
    assert ti.step_inputs({"id": "s", "lesson_content": "x"}) is None  # no title: nothing to illustrate


# --- generation: the five contract tests ------------------------------------------


@pytest.mark.asyncio
async def test_disabled_returns_none_and_no_call(monkeypatch, tmp_path):
    monkeypatch.setattr(ti, "MEDIA_DIR", tmp_path)
    monkeypatch.setattr(ti.settings, "tutorial_illustrations_enabled", False)
    imagen = FakeImagen()
    monkeypatch.setattr(ti, "build_genai_client", lambda: imagen)
    monkeypatch.setattr(ti, "async_session_maker", lambda: pytest.fail("disabled must not even read the item"))

    assert await ti.generate_tutorial_illustration("item-1", "step_1") is None
    assert imagen.calls == []
    assert not (tmp_path / "tutorials").exists()


def test_feature_is_off_by_default_with_a_daily_cap():
    from app.core.config import Settings

    assert Settings.model_fields["tutorial_illustrations_enabled"].default is False
    assert Settings.model_fields["tutorial_illustration_daily_cap"].default == 200


@pytest.mark.asyncio
async def test_cap_reached_returns_none(monkeypatch, enabled):
    enabled.mkdir()
    for index in range(3):
        (enabled / f"{index:064x}.jpg").write_bytes(JPEG)
    monkeypatch.setattr(ti.settings, "tutorial_illustration_daily_cap", 3)
    _, _, imagen = wire(monkeypatch, make_item())

    assert await ti.generate_tutorial_illustration("item-1", "step_1") is None
    assert imagen.calls == []
    assert sorted(path.name for path in enabled.iterdir()) == [f"{i:064x}.jpg" for i in range(3)]


@pytest.mark.asyncio
async def test_only_todays_files_count_against_the_cap(monkeypatch, enabled):
    enabled.mkdir()
    long_ago = time.time() - 3 * 86400
    for index in range(5):
        stale = enabled / f"{index:064x}.jpg"
        stale.write_bytes(JPEG)
        os.utime(stale, (long_ago, long_ago))
    monkeypatch.setattr(ti.settings, "tutorial_illustration_daily_cap", 1)
    _, _, imagen = wire(monkeypatch, make_item())

    illustration = await ti.generate_tutorial_illustration("item-1", "step_1")

    assert illustration is not None and len(imagen.calls) == 1
    # The new file is today's first, so the next distinct tutorial is over the cap.
    other = make_item([tutorial_step("step_2", "Another idea", LESSON.replace(SENTENCE, "A different sentence."))])
    wire(monkeypatch, other, imagen)
    assert await ti.generate_tutorial_illustration("item-2", "step_2") is None
    assert len(imagen.calls) == 1


@pytest.mark.asyncio
async def test_provider_error_leaves_step_published(monkeypatch, enabled):
    item = make_item()
    before = copy.deepcopy(item.details_json)
    job = SimpleNamespace(status="completed", step="done")
    db, _, imagen = wire(monkeypatch, item, FakeImagen(error=RuntimeError("503 quota exceeded")))

    assert await ti.generate_tutorial_illustration("item-1", "step_1") is None
    result = await ti.illustrate_step("item-1", "step_1")

    assert result["status"] == "skipped"
    assert len(imagen.calls) == 2  # one attempt per call; no hidden retry inside either
    assert item.details_json == before  # lesson still published, untouched
    assert (job.status, job.step) == ("completed", "done")
    db.commit.assert_not_awaited()
    assert not enabled.exists() or list(enabled.iterdir()) == []


@pytest.mark.asyncio
@pytest.mark.parametrize("response", [
    FakeImagen(images=[]),
    FakeImagen(images=[SimpleNamespace(image=None)]),
    FakeImagen(image_bytes=b""),
])
async def test_unusable_provider_response_is_treated_as_an_error(monkeypatch, enabled, response):
    wire(monkeypatch, make_item(), response)
    assert await ti.generate_tutorial_illustration("item-1", "step_1") is None
    assert len(response.calls) == 1
    assert not enabled.exists() or list(enabled.iterdir()) == []


@pytest.mark.asyncio
async def test_missing_provider_credentials_is_not_an_exception(monkeypatch, enabled):
    def no_key():
        raise ValueError("Missing key inputs argument")

    wire(monkeypatch, make_item())
    monkeypatch.setattr(ti, "build_genai_client", no_key)
    assert await ti.generate_tutorial_illustration("item-1", "step_1") is None


@pytest.mark.asyncio
async def test_idempotent_by_hash(monkeypatch, enabled):
    _, _, imagen = wire(monkeypatch, make_item())

    first = await ti.generate_tutorial_illustration("item-1", "step_1")
    second = await ti.generate_tutorial_illustration("item-1", "step_1")

    assert first == second
    assert len(imagen.calls) == 1
    digest = key_for()
    assert first.url == f"/media/tutorials/{digest}.jpg"
    assert (enabled / f"{digest}.jpg").read_bytes() == JPEG
    assert [path.name for path in enabled.iterdir()] == [f"{digest}.jpg"]

    # An existing image is reused without a call and without counting against the cap.
    monkeypatch.setattr(ti.settings, "tutorial_illustration_daily_cap", 1)
    assert await ti.generate_tutorial_illustration("item-1", "step_1") == first
    assert len(imagen.calls) == 1


@pytest.mark.asyncio
async def test_generation_uses_the_agreed_imagen_request(monkeypatch, enabled):
    _, _, imagen = wire(monkeypatch, make_item())

    illustration = await ti.generate_tutorial_illustration("item-1", "step_1")

    call = imagen.calls[0]
    assert call.model == "imagen-4.0-generate-001"
    assert call.config.aspect_ratio == "16:9"
    assert call.config.number_of_images == 1
    assert call.config.output_mime_type == "image/jpeg"
    assert call.prompt == ti.build_illustration_prompt(TITLE, SENTENCE, "Investing")
    assert illustration.provider == "gemini_imagen" and illustration.aspect == "16:9"
    assert 0 < len(illustration.alt) <= 160 and TITLE in illustration.alt


@pytest.mark.asyncio
async def test_only_published_tutorial_steps_are_illustrated(monkeypatch, enabled):
    unpublished = tutorial_step("step_2", "Not written yet", "")
    legacy = {"id": "step_3", "title": "Legacy", "lesson_content": LESSON}
    catalog = tutorial_step("step_4", "Catalog", personalized_lesson_version_id="v1")
    item = make_item([tutorial_step(), unpublished, legacy, catalog])
    _, _, imagen = wire(monkeypatch, item)

    for step_id in ("step_2", "step_3", "step_4", "step_missing"):
        assert await ti.generate_tutorial_illustration("item-1", step_id) is None
    assert imagen.calls == []


@pytest.mark.asyncio
async def test_domain_prefers_the_mentor_domain_then_the_goal(monkeypatch, enabled):
    imagen = FakeImagen()
    wire(monkeypatch, make_item(domain="Investing", effective_goal="Run a fund"), imagen)
    await ti.generate_tutorial_illustration("item-1", "step_1")
    assert "Investing" in imagen.calls[-1].prompt

    imagen = FakeImagen()
    other = make_item([tutorial_step(content=LESSON.replace(SENTENCE, "Other idea here."))],
                      domain=None, effective_goal="Run a small fund")
    wire(monkeypatch, other, imagen)
    await ti.generate_tutorial_illustration("item-1", "step_1")
    assert "Run a small fund" in imagen.calls[-1].prompt


# --- attaching the result to the published step ----------------------------------


@pytest.mark.asyncio
async def test_task_attaches_illustration_without_clobbering_concurrent_step_writes(monkeypatch, enabled):
    item = make_item([tutorial_step(), tutorial_step("step_2", "Second idea", "")])

    def concurrent_checkpoint():
        # While Imagen is working, another worker publishes step 2.
        concurrent = copy.deepcopy(item.details_json)
        concurrent["steps"][1]["lesson_content"] = "# Second idea\n\n## Core Framework\nPublished meanwhile."
        concurrent["_generation"]["ready_step_ids"] = ["step_1", "step_2"]
        item.details_json = concurrent

    db, statements, _ = wire(monkeypatch, item, FakeImagen(on_call=concurrent_checkpoint))

    result = await ti.illustrate_step("item-1", "step_1")

    assert result["status"] == "attached"
    steps = item.details_json["steps"]
    assert steps[0]["illustration"]["url"] == f"/media/tutorials/{key_for()}.jpg"
    assert steps[0]["illustration"]["provider"] == "gemini_imagen"
    assert steps[1]["lesson_content"].endswith("Published meanwhile.")  # not clobbered
    assert item.details_json["_generation"]["ready_step_ids"] == ["step_1", "step_2"]
    assert "illustration" not in steps[1]
    db.commit.assert_awaited_once()
    # The write re-reads the row under a row lock, like every other details_json writer.
    locking = [s for s in statements if "FOR UPDATE" in str(s.compile(dialect=postgresql.dialect()))]
    assert locking, "attach must SELECT ... FOR UPDATE the plan item"


@pytest.mark.asyncio
async def test_illustration_of_changed_lesson_is_not_attached(monkeypatch, enabled):
    item = make_item()

    def lesson_regenerated():
        replaced = copy.deepcopy(item.details_json)
        replaced["steps"][0]["lesson_content"] = LESSON.replace(SENTENCE, "A new framing of the idea.")
        item.details_json = replaced

    db, _, imagen = wire(monkeypatch, item, FakeImagen(on_call=lesson_regenerated))

    result = await ti.illustrate_step("item-1", "step_1")

    assert result["status"] == "stale"
    assert "illustration" not in item.details_json["steps"][0]
    db.commit.assert_not_awaited()
    assert len(imagen.calls) == 1


@pytest.mark.asyncio
async def test_missing_item_or_step_is_skipped(monkeypatch, enabled):
    wire(monkeypatch, None)
    assert (await ti.illustrate_step("item-1", "step_1"))["status"] == "skipped"


# --- carrying illustrations through later publications -----------------------------


def prior_with(*steps):
    return {"steps": list(steps), "_generation": {"status": "partial"}}


def illustration_for(step):
    return {"url": ti.illustration_url(step), "alt": "Illustration", "provider": "gemini_imagen",
            "aspect": "16:9"}


def test_replacement_artifact_keeps_a_matching_illustration_and_asks_for_missing_ones():
    done = tutorial_step("step_1")
    done["illustration"] = illustration_for(done)
    previous = prior_with(done, tutorial_step("step_2", "Second", ""))
    published = {"steps": [tutorial_step("step_1"), tutorial_step("step_2", "Second"),
                           tutorial_step("step_3", "Third")]}

    pending = ti.reconcile_step_illustrations(previous, published, ["step_1", "step_2", "step_3"])

    assert published["steps"][0]["illustration"] == done["illustration"]
    assert pending == ["step_2", "step_3"]
    assert "illustration" not in published["steps"][1]


def test_a_step_attempted_before_is_never_requested_again():
    previous = prior_with(tutorial_step("step_1"))  # published earlier, no image (failed or disabled)
    published = {"steps": [tutorial_step("step_1")]}
    assert ti.reconcile_step_illustrations(previous, published, ["step_1"]) == []
    assert "illustration" not in published["steps"][0]


def test_illustration_for_a_rewritten_lesson_is_dropped_and_regenerated():
    old = tutorial_step("step_1")
    old["illustration"] = illustration_for(old)
    rewritten = tutorial_step("step_1", content=LESSON.replace(SENTENCE, "A completely new framing."))
    published = {"steps": [rewritten]}

    assert ti.reconcile_step_illustrations(prior_with(old), published, ["step_1"]) == ["step_1"]
    assert "illustration" not in published["steps"][0]


@pytest.mark.parametrize("previous", [None, {}, {"steps": "bad"}, {"steps": [None, 3]}, []])
def test_malformed_predecessor_is_tolerated(previous):
    published = {"steps": [tutorial_step("step_1")]}
    assert ti.reconcile_step_illustrations(previous, published, ["step_1"]) == ["step_1"]


def test_only_ready_tutorial_steps_are_requested():
    published = {"steps": [tutorial_step("step_1"), tutorial_step("step_2", content=""),
                           {"id": "step_3", "title": "Legacy", "lesson_content": LESSON}]}
    assert ti.reconcile_step_illustrations(None, published, ["step_1", "step_3"]) == ["step_1"]
    assert ti.reconcile_step_illustrations(None, {"steps": "bad"}, ["step_1"]) == []


# --- illustration never alters lesson identity ------------------------------------


def test_practice_lesson_version_ignores_the_illustration():
    from app.services.practice.contracts import lesson_version

    step = tutorial_step()
    plain = {"id": "step_1", "title": "Plain", "lesson_content": "body"}
    decorated = {**step, "illustration": illustration_for(step)}
    for generation in (
        {"job_id": "job-1"},
        {"job_id": "job-1", "lesson_package_version": 1,
         "lesson_validation": {"step_1": {"package_hash": "abc"}}},
    ):
        item = SimpleNamespace(details_json={"_generation": generation})
        assert lesson_version(item, step) == lesson_version(item, decorated)
        assert lesson_version(item, step) != lesson_version(item, {**step, "title": "Changed"})
    # Steps without an illustration keep exactly the pre-existing identity.
    legacy = SimpleNamespace(details_json={"_generation": {"job_id": "job-1"}})
    expected = hashlib.sha256(json.dumps({"job": "job-1", "step": plain}, sort_keys=True,
                                         ensure_ascii=False).encode()).hexdigest()
    assert lesson_version(legacy, plain) == expected


def test_approval_hash_ignores_the_illustration():
    from app.services.llm.schemas import plan_detail_step_model
    from app.services.planning.lesson_package import digest
    from tests.test_short_tutorial_pipeline import complete_step

    step = complete_step()
    decorated = {**step, "illustration": illustration_for(tutorial_step())}
    canonical = lambda value: plan_detail_step_model(value).model_validate(value).model_dump(mode="json")
    assert digest(canonical(step)) == digest(canonical(decorated))


# --- API shape ----------------------------------------------------------------------


def test_step_detail_exposes_a_valid_illustration_and_tolerates_a_bad_one():
    from app.api.v1.plans import _parse_item_details
    from app.schemas.plan import StepDetail

    assert StepDetail(id="s", title="T").illustration is None
    step = tutorial_step()
    good = {**step, "illustration": illustration_for(step)}
    details = _parse_item_details({"steps": [good], "materials": []})
    assert details.steps[0].illustration.url == good["illustration"]["url"]
    assert details.steps[0].illustration.aspect == "16:9"

    for broken in ({"url": "/x.jpg"}, "text", {**good["illustration"], "alt": "a" * 161},
                   {**good["illustration"], "provider": "other"}):
        details = _parse_item_details({"steps": [{**step, "illustration": broken}], "materials": []})
        assert details is not None  # the lesson still renders
        assert details.steps[0].illustration is None
        assert details.steps[0].lesson_content == LESSON


# --- Celery wiring ------------------------------------------------------------------


def test_enqueue_goes_to_the_low_priority_queue_only_when_enabled(monkeypatch):
    """R1-M3: a best-effort image never takes a foreground lesson slot.

    worker-low consumes low_priority and mounts the same media volume
    (infra/docker-compose.prod.yml: worker-low merges the worker anchor).
    """
    from app.tasks import plans

    calls = []
    monkeypatch.setattr(plans.illustrate_tutorial_step, "apply_async",
                        lambda *a, **kw: calls.append((a, kw)))
    monkeypatch.setattr(plans.settings, "tutorial_illustrations_enabled", False)
    plans._enqueue_tutorial_illustrations("item-1", ["step_1"])
    assert calls == []

    monkeypatch.setattr(plans.settings, "tutorial_illustrations_enabled", True)
    plans._enqueue_tutorial_illustrations("item-1", ["step_1", "step_2"])
    assert calls == [((), {"args": ["item-1", "step_1"], "queue": "low_priority"}),
                     ((), {"args": ["item-1", "step_2"], "queue": "low_priority"})]


def test_a_broker_failure_does_not_escape_the_enqueue(monkeypatch):
    from app.tasks import plans

    monkeypatch.setattr(plans.settings, "tutorial_illustrations_enabled", True)
    monkeypatch.setattr(plans.illustrate_tutorial_step, "apply_async",
                        MagicMock(side_effect=ConnectionError("broker down")))
    plans._enqueue_tutorial_illustrations("item-1", ["step_1", "step_2"])  # must not raise
    assert plans.illustrate_tutorial_step.apply_async.call_count == 2


def test_raising_illustration_task_never_changes_job_status(monkeypatch):
    from app.tasks import plans

    job = SimpleNamespace(status="completed", step="done", error_message=None)
    item = SimpleNamespace(status="in_progress", progress_percent=40)
    monkeypatch.setattr(plans.settings, "tutorial_illustrations_enabled", True)
    monkeypatch.setattr(plans, "illustrate_step", AsyncMock(side_effect=RuntimeError("imagen exploded")))

    outcome = plans.illustrate_tutorial_step.run("item-1", "step_1")  # swallowed: nothing retries

    assert outcome == {"status": "failed"}
    assert (job.status, job.step, job.error_message) == ("completed", "done", None)
    assert (item.status, item.progress_percent) == ("in_progress", 40)
    assert plans.illustrate_tutorial_step.max_retries in (0, None)
    assert not getattr(plans.illustrate_tutorial_step, "autoretry_for", ())


def test_task_has_a_deadline_the_solo_pool_can_enforce(monkeypatch):
    from app.tasks import plans

    async def stuck(*_):
        await asyncio.Event().wait()

    monkeypatch.setattr(plans, "illustrate_step", stuck)
    monkeypatch.setattr(plans, "ILLUSTRATION_TASK_TIMEOUT_SECONDS", 0.01)
    assert plans.illustrate_tutorial_step.run("item-1", "step_1") == {"status": "failed"}


# --- publication: enqueue only after the tutorial is durably published ---------------


class RecordingItem(SimpleNamespace):
    """Records every details_json assignment so ordering can be asserted."""

    def __setattr__(self, name, value):
        if name == "details_json":
            self.events.append("publish")
        super().__setattr__(name, value)


async def drive_publication(monkeypatch, *, enabled=True, apply_async=None):
    """Run the real detail job through a checkpoint publication and a final one.

    The generator is stubbed (no provider calls) but ``_checkpoint_details``, the
    publication lock helpers and the final publication all run for real.
    """
    from app.models.plan import PlanItemStatus, PlanItemType
    from app.tasks import plans
    from tests.test_short_tutorial_pipeline import complete_step, outline

    events: list = []
    steps = outline(3)["steps"]
    published_steps = [complete_step(step) for step in steps]
    plan = SimpleNamespace(id=str(uuid4()), idol=None, roadmap_json={}, completed_at=None)
    item = RecordingItem(
        events=events, id=str(uuid4()), plan=plan, title="Practice a validated skill",
        description="Work through one example", type=PlanItemType.PROJECT,
        estimated_hours=1, success_metric="Explain the result", details_json={},
        status=PlanItemStatus.NOT_STARTED, progress_percent=0,
        meta_json={"estimated_minutes": 20},  # three 6-7 minute tutorials
    )
    job = SimpleNamespace(id=str(uuid4()), user_id=str(uuid4()), plan_item=item, status="running",
                          created_at=datetime.now(timezone.utc), result_json={}, supersedes_artifact=False,
                          progress_percent=0, step="loading_context", error_message=None, thinking_text=None)
    db = AsyncMock()
    db.add = MagicMock()

    async def commit():
        events.append("commit")

    db.commit.side_effect = commit
    db.execute.side_effect = [
        SimpleNamespace(rowcount=1),                       # claim the job
        SimpleNamespace(scalar_one_or_none=lambda: job),   # load it with its context
        SimpleNamespace(scalar_one_or_none=lambda: None),  # no user profile
    ]
    context = AsyncMock()
    context.__aenter__.return_value = db
    monkeypatch.setattr(plans, "async_session_maker", lambda: context)
    monkeypatch.setattr(plans.settings, "lesson_catalog_first_enabled", False)
    monkeypatch.setattr(plans.settings, "tutorial_illustrations_enabled", enabled)
    monkeypatch.setattr(plans, "_load_session_context", AsyncMock(return_value={}))
    monkeypatch.setattr(plans, "_resolve_plan_detail_materials", AsyncMock(return_value=[]))
    monkeypatch.setattr(plans, "_lock_current_detail_artifact_publication",
                        AsyncMock(return_value=(plan, item, job)))
    monkeypatch.setattr("app.services.llm.routing.choose_llm_tier", AsyncMock(
        return_value=SimpleNamespace(tier="balanced", reason="test")))
    monkeypatch.setattr("app.services.llm.telemetry.record_usage_records", AsyncMock())

    enqueued: list = []

    def default_apply_async(*, args, queue):
        enqueued.append((args[1], queue))
        events.append(f"enqueue:{args[1]}")
        # At enqueue time the tutorial must already be readable in the database.
        assert any(s.get("lesson_content") for s in item.details_json["steps"] if s["id"] == args[1])
        if args[1] == "step_2":
            raise ConnectionError("broker down")  # must not fail the job

    monkeypatch.setattr(plans.illustrate_tutorial_step, "apply_async", apply_async or default_apply_async)

    async def generate(**kwargs):
        partial = {**outline(3), "steps": [published_steps[0], *copy.deepcopy(steps[1:])]}
        await kwargs["on_checkpoint"](partial, "lesson_ready")
        events.append("checkpoint-1-done")
        # The illustration task attaches step 1's image while the job keeps working.
        # The final payload below never saw it; publication must carry it over.
        attached = copy.deepcopy(item.details_json)
        attached["steps"][0]["illustration"] = {
            "url": ti.illustration_url(attached["steps"][0]), "alt": "Illustration",
            "provider": "gemini_imagen", "aspect": "16:9"}
        SimpleNamespace.__setattr__(item, "details_json", attached)  # not a publication
        full = {**outline(3), "steps": copy.deepcopy(published_steps)}
        return full, [], None

    monkeypatch.setattr(plans, "_generate_plan_item_details_parallel", generate)
    result = await plans._regenerate_plan_item_details_async(job.id)
    return SimpleNamespace(result=result, events=events, enqueued=enqueued, item=item, job=job)


@pytest.mark.asyncio
async def test_enqueue_happens_after_publish_and_never_changes_job_status(monkeypatch):
    run = await drive_publication(monkeypatch)
    events, item = run.events, run.item

    assert run.result["status"] == "completed", run.result
    assert run.job.status == "completed"  # an enqueue failure (step_2) never changes the job
    kept = item.details_json["steps"][0]["illustration"]
    assert kept["url"] == ti.illustration_url(item.details_json["steps"][0])  # survived republication
    assert all("illustration" not in step for step in item.details_json["steps"][1:])
    # Step 1 is requested right after the checkpoint that published it ...
    first = events.index("enqueue:step_1")
    assert "publish" in events[:first] and "commit" in events[events.index("publish"):first]
    assert first < events.index("checkpoint-1-done")
    # ... and the final publication requests only the tutorials it newly completed.
    assert run.enqueued == [("step_1", "low_priority"), ("step_2", "low_priority"), ("step_3", "low_priority")]
    last_publish = len(events) - 1 - events[::-1].index("publish")
    for step_id in ("step_2", "step_3"):
        later = events.index(f"enqueue:{step_id}")
        assert later > last_publish and "commit" in events[last_publish:later]


@pytest.mark.asyncio
async def test_disabled_flag_publishes_normally_and_enqueues_nothing(monkeypatch):
    run = await drive_publication(monkeypatch, enabled=False,
                                  apply_async=lambda **kw: pytest.fail("disabled must not enqueue"))
    assert run.result["status"] == "completed" and run.job.status == "completed"
    assert [s["id"] for s in run.item.details_json["steps"] if s.get("lesson_content")] == [
        "step_1", "step_2", "step_3"]


@pytest.mark.asyncio
async def test_illustration_bookkeeping_failure_cannot_block_publication(monkeypatch):
    from app.tasks import plans

    monkeypatch.setattr(plans, "reconcile_step_illustrations",
                        MagicMock(side_effect=RuntimeError("unexpected stored shape")))
    run = await drive_publication(monkeypatch, apply_async=lambda **kw: pytest.fail("nothing to enqueue"))

    assert run.result["status"] == "completed" and run.job.status == "completed"
    assert len([s for s in run.item.details_json["steps"] if s.get("lesson_content")]) == 3


# --- deployment: the default-queue worker must share web's media volume ---------------


def test_default_worker_shares_the_media_volume_and_receives_the_flag_default_off():
    from pathlib import Path

    import yaml

    compose = yaml.safe_load(
        (Path(__file__).resolve().parents[2] / "infra" / "docker-compose.prod.yml").read_text())
    services = compose["services"]
    assert "cmpys_media" in compose["volumes"]
    # web serves /media; the worker that runs the task writes it. Same named volume.
    for name in ("web", "worker", "worker-high", "worker-low"):
        assert "cmpys_media:/app/media" in services[name]["volumes"], name
    # Compose passes only listed variables through, and the feature stays off by default.
    for name in ("worker", "worker-high", "worker-low"):
        environment = services[name]["environment"]
        assert environment["TUTORIAL_ILLUSTRATIONS_ENABLED"] == "${TUTORIAL_ILLUSTRATIONS_ENABLED:-false}"
        assert environment["TUTORIAL_ILLUSTRATION_DAILY_CAP"] == "${TUTORIAL_ILLUSTRATION_DAILY_CAP:-200}"
    sample = (Path(__file__).resolve().parents[1] / ".env.example").read_text()
    assert "TUTORIAL_ILLUSTRATIONS_ENABLED=false" in sample
    assert "TUTORIAL_ILLUSTRATION_DAILY_CAP=200" in sample
